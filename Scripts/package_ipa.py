"""Validate and package our arm64 iPhone app, including its keyboard, for local signing."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import struct
import zipfile


def read_info(bundle):
    with (bundle / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("Expected an iPhoneOS bundle, not a simulator build")
    executable = info.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable:
        raise ValueError("Bundle executable is missing or invalid")
    return info


def validate_macho(binary):
    with binary.open("rb") as source:
        header = source.read(32)
        if len(header) != 32:
            raise ValueError("Truncated Mach-O executable")
        magic, cpu, _, file_type, count, size, _, _ = struct.unpack("<8I", header)
        if magic != 0xFEEDFACF or cpu != 0x0100000C or file_type != 2:
            raise ValueError("Expected a thin arm64 Mach-O executable")
        if size > 1024 * 1024 or count > 10000:
            raise ValueError("Invalid Mach-O load commands")
        commands = source.read(size)
    cursor = 0
    device_platform = False
    for _ in range(count):
        if cursor + 8 > len(commands):
            raise ValueError("Truncated Mach-O load command")
        command, length = struct.unpack_from("<2I", commands, cursor)
        if length < 8 or cursor + length > len(commands):
            raise ValueError("Invalid Mach-O load command length")
        if command == 0x32:  # LC_BUILD_VERSION
            if length < 24:
                raise ValueError("Invalid build version command")
            platform = struct.unpack_from("<I", commands, cursor + 8)[0]
            if platform != 2:  # PLATFORM_IOS, not PLATFORM_IOSSIMULATOR (7)
                raise ValueError("Executable was not built for a physical iPhone")
            device_platform = True
        cursor += length
    if not device_platform:
        raise ValueError("Executable has no iOS build version")


def package(app, output):
    app = Path(app).resolve()
    output = Path(output).resolve()
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("Expected the built KotoKeyboard.app directory")
    if output == app or app in output.parents:
        raise ValueError("Output must be outside the app bundle")
    info = read_info(app)
    extension = app / "PlugIns" / "KotoKeyboardExtension.appex"
    extension_info = read_info(extension)
    if extension_info.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.keyboard-service":
        raise ValueError("The embedded keyboard extension is missing or invalid")
    bundle_id = info.get("CFBundleIdentifier")
    if not bundle_id or extension_info.get("CFBundleIdentifier") != bundle_id + ".keyboard":
        raise ValueError("App and keyboard bundle IDs do not match")
    for field in ("CFBundleVersion", "CFBundleShortVersionString"):
        if not info.get(field) or info[field] != extension_info.get(field):
            raise ValueError("App and keyboard versions do not match")
    for bundle, metadata in ((app, info), (extension, extension_info)):
        validate_macho(bundle / metadata["CFBundleExecutable"])
    files = sorted(app.rglob("*"))
    for file in files:
        if file.is_symlink():
            raise ValueError("Unexpected symlink in this app bundle")
        if file.name in ("embedded.mobileprovision", "_CodeSignature") or file.suffix in (".p8", ".p12"):
            raise ValueError("Expected an unsigned bundle with no signing credentials")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for file in files:
            if file.is_file():
                archive.write(file, (Path("Payload") / app.name / file.relative_to(app)).as_posix())
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError("IPA archive integrity check failed")
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix + ".sha256").write_text(digest + "  " + output.name + "\n", encoding="utf-8")
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    print("Created:", package(arguments.app, arguments.output))
