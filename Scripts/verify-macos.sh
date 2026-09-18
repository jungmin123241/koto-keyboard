#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null
command -v swift >/dev/null
mkdir -p artifacts
swift test 2>&1 | tee artifacts/swift-test.log
xcodebuild -project KotoKeyboard.xcodeproj -scheme KotoKeyboard -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tee artifacts/build.log
xcodebuild -project KotoKeyboard.xcodeproj -scheme KotoKeyboard-FreeDevice -configuration FreeDevice -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tee artifacts/free-device-build.log
# Supply an installed simulator UDID/name, e.g. SIMULATOR='platform=iOS Simulator,id=...'.
if [ -z "${SIMULATOR:-}" ]; then
  echo 'Build completed. Set SIMULATOR from xcrun simctl list devices available to run XCTest/UI tests.'
  exit 2
fi
xcodebuild -project KotoKeyboard.xcodeproj -scheme KotoKeyboard -configuration Debug -destination "$SIMULATOR" -resultBundlePath "artifacts/Test-$(date +%Y%m%d-%H%M%S).xcresult" CODE_SIGNING_ALLOWED=NO test 2>&1 | tee artifacts/xctest.log
