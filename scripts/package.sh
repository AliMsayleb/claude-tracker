#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
ARCHS="arm64 x86_64" ./scripts/build.sh

mkdir -p dist
archive="dist/Claude-Tracker-$version.zip"
rm -f "$archive"
rm -rf build/package && mkdir -p build/package
cp -R build/ClaudeWidget.app "build/package/Claude Tracker.app"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  ditto -c -k --keepParent "build/package/Claude Tracker.app" build/package/notarize.zip
  xcrun notarytool submit build/package/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "build/package/Claude Tracker.app"
fi

ditto -c -k --keepParent "build/package/Claude Tracker.app" "$archive"
cp "$archive" dist/Claude-Tracker.zip
(cd dist && shasum -a 256 Claude-Tracker.zip > Claude-Tracker.zip.sha256)
touch dist/.metadata_never_index
rm -rf build/package
echo "packaged $archive"

