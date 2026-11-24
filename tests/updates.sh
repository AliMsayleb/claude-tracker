#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"
current="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/build/ClaudeWidget.app/Contents/Info.plist")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

check "version comparison" "1.2.1 > 1.2.0: true|1.10.0 > 1.9.9: true|v2.0 > 1.99: true|1.2.0 > 1.2.0: false|1.1.9 > 1.2.0: false|1.2 > 1.2.0: false|" \
  "$("$binary" --test-version-compare | tr '\n' '|')"

mkdir -p "$work/package" "$work/release"
ditto "$root/build/ClaudeWidget.app" "$work/package/Claude Tracker.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 9.9.9' "$work/package/Claude Tracker.app/Contents/Info.plist"
codesign --force --sign - "$work/package/Claude Tracker.app" 2> /dev/null
ditto -c -k --keepParent "$work/package/Claude Tracker.app" "$work/release/Claude-Tracker.zip"
(cd "$work/release" && shasum -a 256 Claude-Tracker.zip > Claude-Tracker.zip.sha256)

write_release() {
  jq -n --arg tag "$1" --arg zip "file://$work/release/Claude-Tracker.zip" --arg sha "file://$work/release/Claude-Tracker.zip.sha256" \
    '{tag_name: $tag, body: "Release notes", assets: [{name: "Claude-Tracker.zip", browser_download_url: $zip}, {name: "Claude-Tracker.zip.sha256", browser_download_url: $sha}]}' > "$work/latest.json"
}
export CLAUDE_TRACKER_UPDATE_URL="file://$work/latest.json"

write_release v9.9.9
check "a newer release is detected" "update available 9.9.9" "$("$binary" --check-update)"
write_release v0.0.1
check "an older release is not offered" "up to date $current" "$("$binary" --check-update)"
write_release "v$current"
check "the same version is not offered" "up to date $current" "$("$binary" --check-update)"

write_release v9.9.9
downloaded="$("$binary" --download-update "$work/out")"
check "download is verified, unpacked and reports the app" "downloaded $work/out/unpacked/Claude Tracker.app" "$downloaded"
check "the downloaded app is the new version" "9.9.9" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$work/out/unpacked/Claude Tracker.app/Contents/Info.plist")"

echo "0000000000000000000000000000000000000000000000000000000000000000  Claude-Tracker.zip" > "$work/release/Claude-Tracker.zip.sha256"
check "a wrong checksum is refused" "failed: The download is corrupted (checksum mismatch)." "$("$binary" --download-update "$work/bad")"
check "a wrong checksum exits with an error" "1" "$("$binary" --download-update "$work/bad" > /dev/null; echo $?)"
check "nothing is installed from a refused download" "no" "$([ -d "$work/bad/unpacked" ] && echo yes || echo no)"

jq -n '{tag_name: "v9.9.9", assets: []}' > "$work/latest.json"
check "a release without a download is reported" "failed: The latest release has no downloadable app." "$("$binary" --download-update "$work/none")"
export CLAUDE_TRACKER_UPDATE_URL="file://$work/does-not-exist.json"
check "an unreachable server is reported, not crashed on" "1" "$("$binary" --check-update > /dev/null 2>&1; echo $?)"
unset CLAUDE_TRACKER_UPDATE_URL

mkdir -p "$work/it's here"
for destination in "$work/inst" "$work/it's here"; do
  mkdir -p "$destination/Claude Tracker.app/Contents"
  echo old > "$destination/Claude Tracker.app/old-marker"
  sleep 1 &
  waiting=$!
  "$binary" --print-update-script "$waiting" "$work/out/unpacked/Claude Tracker.app" "$destination/Claude Tracker.app" > "$work/update.sh"
  SKIP_LAUNCH=1 bash "$work/update.sh"
  check "the update script replaces the app (destination: ${destination##*/})" "9.9.9|gone" \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$destination/Claude Tracker.app/Contents/Info.plist")|$([ -e "$destination/Claude Tracker.app/old-marker" ] && echo present || echo gone)"
  check "the update script waited for the old app to quit" "no" "$(kill -0 "$waiting" 2> /dev/null && echo yes || echo no)"
done

finish
