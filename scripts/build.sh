#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app="build/ClaudeWidget.app"
archs="${ARCHS:-$(uname -m)}"
rm -rf "$app"
mkdir -p build
touch build/.metadata_never_index
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

binaries=()
for arch in $archs; do
  swiftc -swift-version 5 -O -target "$arch-apple-macos15.0" Sources/*.swift -o "build/claude-widget-$arch"
  binaries+=("build/claude-widget-$arch")
done
if [ "${#binaries[@]}" -gt 1 ]; then
  lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/claude-widget"
else
  cp "${binaries[0]}" "$app/Contents/MacOS/claude-widget"
fi
rm -f "${binaries[@]}"

if [ ! -f build/AppIcon.icns ]; then
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Info.plist "$app/Contents/Info.plist"
cp hook/permission-hook.sh "$app/Contents/Resources/permission-hook.sh"
codesign --force --sign "${SIGN_IDENTITY:--}" ${SIGN_IDENTITY:+--options runtime} "$app"

echo "built $app ($archs)"
