#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"

click() {
  timeout 20 "$binary" --sample --click "$1" "$2"
}

check "Allow button reports an allow decision" "decide sample-request allow" "$(click 53 216)"
check "Deny button reports a deny decision" "decide sample-request deny" "$(click 134 216)"
check "plain click opens the popup and does not mark the session read" "" "$(click 100 272)"
domain_for_target="com.local.claude-widget"
previous_target="$(defaults read "$domain_for_target" openTarget 2> /dev/null || echo unset)"
set_target() { defaults write "$domain_for_target" openTarget -string "$1"; }
restore_target() { if [ "$previous_target" = "unset" ]; then defaults delete "$domain_for_target" openTarget 2> /dev/null; else defaults write "$domain_for_target" openTarget -string "$previous_target"; fi; }
set_target desktop
check "command-click opens Desktop and marks the session read" "seen pid=3 jump pid=3" "$(timeout 20 "$binary" --sample --command-click 100 615 | tr '
' ' ' | sed 's/ $//')"
set_target terminal
check "command-click opens Terminal when that is the chosen default" "seen pid=3 terminal pid=3" "$(timeout 20 "$binary" --sample --command-click 100 615 | tr '\n' ' ' | sed 's/ $//')"
restore_target

check "the green check on an unread row marks it read" "seen pid=5" "$(timeout 20 "$binary" --sample --preview-row-hover --click 270 505)"
check "the cross on a row removes it" "remove pid=5" "$(timeout 20 "$binary" --sample --preview-row-hover --click 295 505)"

check "clicking an option in a question row answers it" "answer sample-question Which environment should I deploy to?=Staging" "$(click 100 371)"
check "clicking a later option answers with that option" "answer sample-question Which environment should I deploy to?=Cancel" "$(click 100 447)"
check "plain click on the request text opens the popup only" "" "$(click 100 150)"

work="$(mktemp -d)"
domain="com.local.claude-widget"
previous="$(defaults read "$domain" collapsed 2> /dev/null || echo unset)"
restore() {
  if [ "$previous" = "unset" ]; then defaults delete "$domain" collapsed 2> /dev/null; else defaults write "$domain" collapsed -bool "$([ "$previous" = 1 ] && echo true || echo false)"; fi
  rm -rf "$work"
}
trap restore EXIT

pixel_height() { sips -g pixelHeight "$1" | awk '/pixelHeight/ {print $2}'; }

defaults write "$domain" collapsed -bool false
timeout 20 "$binary" --sample --click 100 272 --snapshot "$work/popup.png"
check "plain click shows the popup window" "yes" "$([ -f "$work/popup.png-reply.png" ] && echo yes || echo no)"
check "popup is larger than before (at least 600 points wide)" "yes" "$([ "$(sips -g pixelWidth "$work/popup.png-reply.png" | awk '/pixelWidth/ {print $2}')" -ge 1200 ] && echo yes || echo no)"

timeout 20 "$binary" --sample --snapshot "$work/expanded.png"
timeout 20 "$binary" --sample --click 24 22 --snapshot "$work/collapsed.png"
expanded="$(pixel_height "$work/expanded.png")"
collapsed="$(pixel_height "$work/collapsed.png")"
check "chevron collapses the list to the header" "yes" "$([ "$collapsed" -lt 100 ] && [ "$expanded" -gt 400 ] && echo yes || echo no)"
cp "$work/collapsed.png" "$root/build/collapsed.png"

defaults write "$domain" collapsed -bool true
timeout 20 "$binary" --sample --click 24 22 --snapshot "$work/reopened.png"
check "chevron expands it again" "$expanded" "$(pixel_height "$work/reopened.png")"

timeout 20 "$binary" --sample --click 296 22 --snapshot "$work/quit.png"
check "the close button quits before the snapshot is taken" "absent" "$([ -f "$work/quit.png" ] && echo present || echo absent)"

finish
