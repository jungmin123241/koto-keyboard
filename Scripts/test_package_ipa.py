import hashlib
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

from package_ipa import package


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "KotoKeyboard.app"
        self.extension = self.app / "PlugIns" / "KotoKeyboardExtension.appex"
        self.output = self.root / "output" / "Keyboard.ipa"
        self.extension.mkdir(parents=True)
        for folder, executable, bundle_id in (
            (self.app, "KotoKeyboard", "com.test.koto"),
            (self.extension, "KotoKeyboardExtension", "com.test.koto.keyboard"),
        ):
            info = {"CFBundleExecutable": executable, "CFBundleIdentifier": bundle_id,
                    "CFBundleSupportedPlatforms": ["iPhoneOS"], "CFBundleVersion": "1",
                    "CFBundleShortVersionString": "0.1.0"}
            if folder == self.extension:
                info["NSExtension"] = {"NSExtensionPointIdentifier": "com.apple.keyboard-service"}
            (folder / "Info.plist").write_bytes(plistlib.dumps(info))
            (folder / executable).write_bytes(self.macho(platform=2))

    @staticmethod
    def macho(platform):
        return struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 1, 24, 0, 0) + struct.pack("<6I", 0x32, 24, platform, 0x00120000, 0x00120000, 0)

    def modify(self, folder, field, value):
        file = folder / "Info.plist"
        info = plistlib.loads(file.read_bytes())
        info[field] = value
        file.write_bytes(plistlib.dumps(info))

    def test_payload_contains_app_and_keyboard_and_checksum(self):
        package(self.app, self.output)
        with zipfile.ZipFile(self.output) as archive:
            self.assertIn("Payload/KotoKeyboard.app/KotoKeyboard", archive.namelist())
            self.assertIn("Payload/KotoKeyboard.app/PlugIns/KotoKeyboardExtension.appex/KotoKeyboardExtension", archive.namelist())
        self.assertTrue(self.output.with_suffix(".ipa.sha256").read_text().startswith(hashlib.sha256(self.output.read_bytes()).hexdigest()))

    def test_rejects_simulator_bundle(self):
        self.modify(self.app, "CFBundleSupportedPlatforms", ["iPhoneSimulator"])
        with self.assertRaisesRegex(ValueError, "simulator"):
            package(self.app, self.output)
        self.assertFalse(self.output.exists())

    def test_rejects_arm64_simulator_binary_even_if_plist_claims_device(self):
        (self.extension / "KotoKeyboardExtension").write_bytes(self.macho(platform=7))
        with self.assertRaisesRegex(ValueError, "physical iPhone"):
            package(self.app, self.output)

    def test_rejects_missing_keyboard(self):
        (self.extension / "Info.plist").unlink()
        with self.assertRaises(FileNotFoundError):
            package(self.app, self.output)

    def test_rejects_mismatched_identifier(self):
        self.modify(self.extension, "CFBundleIdentifier", "com.other.app.keyboard")
        with self.assertRaisesRegex(ValueError, "bundle IDs"):
            package(self.app, self.output)

    def test_rejects_mismatched_versions(self):
        self.modify(self.extension, "CFBundleVersion", "99")
        with self.assertRaisesRegex(ValueError, "versions"):
            package(self.app, self.output)

    def test_rejects_signing_material(self):
        (self.app / "embedded.mobileprovision").write_bytes(b"test fixture")
        with self.assertRaisesRegex(ValueError, "unsigned"):
            package(self.app, self.output)

    def test_rejects_truncated_binary(self):
        (self.app / "KotoKeyboard").write_bytes(b"not an executable")
        with self.assertRaisesRegex(ValueError, "Truncated"):
            package(self.app, self.output)


if __name__ == "__main__":
    unittest.main()
