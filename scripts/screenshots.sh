#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

binary="build/ClaudeWidget.app/Contents/MacOS/claude-widget"
[ -x "$binary" ] || ./scripts/build.sh
output="docs/screenshots"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$output"

snap() {
  expected="$1"; shift
  for _ in 1 2 3; do
    rm -f "$expected"
    timeout 30 "$binary" --sample "$@" > /dev/null 2>&1 || true
    [ -s "$expected" ] && return 0
  done
  echo "could not capture $expected" >&2
  exit 1
}

compose() {
  swift scripts/compose-screenshot.swift "$1" "$output/$2.png"
  width="$(sips -g pixelWidth "$output/$2.png" | awk '/pixelWidth/ {print $2}')"
  [ "$width" -le 1200 ] || sips --resampleWidth 1200 "$output/$2.png" > /dev/null
}

snap "$work/widget.png" --snapshot "$work/widget.png"
compose "$work/widget.png" widget
snap "$work/popup.png-reply.png" --click 100 505 --snapshot "$work/popup.png"
compose "$work/popup.png-reply.png" popup
snap "$work/question.png-reply.png" --click 100 272 --snapshot "$work/question.png"
compose "$work/question.png-reply.png" popup-question
snap "$work/permission.png-reply.png" --click 100 150 --snapshot "$work/permission.png"
compose "$work/permission.png-reply.png" popup-permission
snap "$work/add.png-picker.png" --click 232 22 --snapshot "$work/add.png"
compose "$work/add.png-picker.png" add-session
snap "$work/newsession.png-newsession.png" --open-new-session --new-session-target terminal --draft-new-session "$HOME/Documents" "Add dark mode to the settings screen, then run the tests and fix anything that breaks." --snapshot "$work/newsession.png"
compose "$work/newsession.png-newsession.png" new-session
snap "$work/shortcuts.png-shortcuts.png" --open-shortcuts --snapshot "$work/shortcuts.png"
compose "$work/shortcuts.png-shortcuts.png" shortcuts
echo "screenshots written to $output"
