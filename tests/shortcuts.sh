#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

in_readme="$(sed -n '/<!-- shortcuts:start -->/,/<!-- shortcuts:end -->/p' "$root/README.md" | sed '1d;$d')"
check "README shortcut list matches the in-app list" "$("$binary" --print-shortcuts)" "$in_readme"
check "the list covers the widget, popup, anywhere and add-session sections" "4" "$("$binary" --print-shortcuts | grep -c '^### ')"
check "double-tap, command-click, Shift-Return and the text size keys are documented" "4" \
  "$("$binary" --print-shortcuts | grep -c -E 'Double-tap|Open the session in Claude Desktop|New line|Bigger text')"
timeout 20 "$binary" --sample --open-shortcuts --snapshot "$work/s.png"
check "the shortcuts window opens" "yes" "$([ -f "$work/s.png-shortcuts.png" ] && echo yes || echo no)"

finish
