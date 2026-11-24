#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"
domain="com.local.claude-widget"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

keys="replyPopupSize replyFontScale widgetMaxHeight collapsed"
snapshot_keys() { for key in $keys; do echo "$key=$(defaults read "$domain" "$key" 2> /dev/null || echo unset)"; done; }
before="$(snapshot_keys)"

check "search matches words across title and folder" "[]=3 [RECON]=1 [mobile pay]=1 [weekly docs]=1 [xyz]=0 [  ]=3 " \
  "$("$binary" --test-search | tr '\n' ' ')"
check "widget keeps a user-set width and caps its height" "width=420 height<=220=true" \
  "$(timeout 20 "$binary" --sample --test-widget-size)"
timeout 20 "$binary" --sample --click 232 22 --snapshot "$work/p.png"
check "the magnifier opens the add-session window" "yes" "$([ -f "$work/p.png-picker.png" ] && echo yes || echo no)"
timeout 20 "$binary" --sample --click 264 22 --snapshot "$work/n.png"
check "the plus button opens the new-session window" "yes" "$([ -f "$work/n.png-newsession.png" ] && echo yes || echo no)"
check "test runs leave your saved settings untouched" "$before" "$(snapshot_keys)"

finish
