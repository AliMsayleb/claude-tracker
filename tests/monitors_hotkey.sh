#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"

left="0,0,1440,900"
right="1440,0,1920,1080"
screens="$left;$right"
check "a widget on the left monitor picks the left monitor" "0" "$("$binary" --print-popup-screen "100,500,300,200" "$screens")"
check "a widget on the right monitor picks the right monitor" "1" "$("$binary" --print-popup-screen "1600,500,300,200" "$screens")"
check "a widget on a monitor to the left of the main one picks it" "0" "$("$binary" --print-popup-screen "-1000,100,300,200" "-1920,0,1920,1080;0,0,1440,900")"
check "a widget straddling two monitors picks the one it covers most" "1" "$("$binary" --print-popup-screen "1340,300,400,200" "$screens")"
check "a widget far outside every monitor picks the nearest by overlap, else the first" "0" "$("$binary" --print-popup-screen "9000,9000,300,200" "$screens")"
check "no monitors gives no answer" "none" "$("$binary" --print-popup-screen "0,0,10,10" "")"

check "the new-session hotkey is Control-Option-N" "⌃⌥N keyCode=45 modifiers=6144" "$("$binary" --print-hotkey)"
check "sample mode never registers the global hotkey" "hotkey registered=false" "$(timeout 20 "$binary" --sample --test-hotkey)"
check "the hotkey is documented in the shortcuts list" "1" "$("$binary" --print-shortcuts | grep -c 'Start a new session from any app')"

finish
