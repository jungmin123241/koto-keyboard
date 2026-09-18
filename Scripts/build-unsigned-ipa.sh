#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'This script requires a macOS runner with Xcode.' >&2
  exit 1
fi
command -v xcodebuild >/dev/null
command -v python3 >/dev/null
mkdir -p artifacts
xcodebuild -version | tee artifacts/xcode-version.log

# Build for a physical iPhone. A simulator .app cannot be installed on a phone.
# No Apple ID, signing certificate, provisioning profile or GitHub secret is used.
xcodebuild \
  -project KotoKeyboard.xcodeproj \
  -scheme KotoKeyboard-FreeDevice \
  -configuration FreeDevice \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath artifacts/UnsignedDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_ENTITLEMENTS= \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  build 2>&1 | tee artifacts/iphone-build.log

python3 Scripts/package_ipa.py \
  artifacts/UnsignedDerivedData/Build/Products/FreeDevice-iphoneos/KotoKeyboard.app \
  artifacts/KotoKeyboard-FreeDevice-unsigned.ipa

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '%s\n' \
    '### iPhone IPA created' \
    '' \
    'Download **KotoKeyboard-FreeDevice-unsigned** under Artifacts and extract the ZIP on Windows.' \
    'Use the IPA inside with Sideloadly and your own free Apple account.' \
    '**Keep the keyboard extension (PlugIns).** The IPA is unsigned and does not install by tapping it.' \
    'This build uses Mock translation. It requires iOS 18 or newer; shared settings and remote translation are disabled.' \
    'Build success does not establish successful installation or keyboard behavior on your iPhone.' \
    >> "$GITHUB_STEP_SUMMARY"
fi
