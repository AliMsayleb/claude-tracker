#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

check "every button and tap target uses a hover-aware style" "ok" "$(python3 -I "$root/tests/hover_lint.py")"

compare() {
  local name="$1" suffix="$2"; shift 2
  timeout 20 "$binary" --sample "$@" --snapshot "$work/$name-normal.png"
  timeout 20 "$binary" --sample --preview-all-hover "$@" --snapshot "$work/$name-hover.png"
  local pixels
  pixels="$(python3 -I "$root/tests/hover_diff.py" "$work/$name-normal.png$suffix" "$work/$name-hover.png$suffix")"
  check "$name: hover states change how it looks (at least 300 pixels)" "yes" "$([ "${pixels:-0}" -ge 300 ] && echo yes || echo no)"
}

compare widget "" 
compare search-window "-picker.png" --click 232 22
compare new-session-window "-newsession.png" --open-new-session
compare shortcuts-window "-shortcuts.png" --open-shortcuts
compare question-popup "-reply.png" --click 100 272

finish
