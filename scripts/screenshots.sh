#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

binary="build/ClaudeWidget.app/Contents/MacOS/claude-widget"
[ -x "$binary" ] || ./scripts/build.sh
output="docs/screenshots"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$output"

compose() {
  swift scripts/compose-screenshot.swift "$1" "$output/$2.png"
  width="$(sips -g pixelWidth "$output/$2.png" | awk '/pixelWidth/ {print $2}')"
  [ "$width" -le 1200 ] || sips --resampleWidth 1200 "$output/$2.png" > /dev/null
}

timeout 30 "$binary" --sample --snapshot "$work/widget.png"
compose "$work/widget.png" widget
timeout 30 "$binary" --sample --click 100 327 --snapshot "$work/popup.png"
compose "$work/popup.png-reply.png" popup
timeout 30 "$binary" --sample --click 100 150 --snapshot "$work/permission.png"
compose "$work/permission.png-reply.png" popup-permission
timeout 30 "$binary" --sample --click 264 22 --snapshot "$work/add.png"
compose "$work/add.png-picker.png" add-session
timeout 30 "$binary" --sample --open-shortcuts --snapshot "$work/shortcuts.png"
compose "$work/shortcuts.png-shortcuts.png" shortcuts
echo "screenshots written to $output"
