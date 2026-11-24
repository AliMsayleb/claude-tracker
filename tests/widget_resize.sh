#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"

check "resize maths for each edge, with limits" \
  "left-wider=50,100,350,400 right-wider=100,100,340,400 left-min=140,100,260,400 right-max=100,100,800,400 bottom-shorter=100,200,300,300 bottom-taller=100,50,300,450 bottom-min=100,420,300,80 " \
  "$("$binary" --test-resize | tr '\n' ' ')"
check "dragging the edges resizes the widget and remembers the height" \
  "left edge grew by 60, right edge fixed=true|right edge grew by 40, left edge fixed=true|bottom edge shrank by 80, top fixed=true, height remembered=true|" \
  "$(timeout 20 "$binary" --sample --test-widget-drag | tr '\n' '|')"
check "each edge has a cursor area that shows the resize cursor, and background cursors are enabled" \
  "background cursor enabled=true|left edge: cursor=left-right tracking=true thin=true|bottom edge: cursor=up-down tracking=true thin=true|right edge: cursor=left-right tracking=true thin=true|" \
  "$(timeout 20 "$binary" --sample --test-cursors | tr '\n' '|')"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
timeout 20 "$binary" --sample --snapshot "$work/normal.png" > /dev/null
timeout 20 "$binary" --sample --test-mid-drag 250 --snapshot "$work/short.png" > /dev/null
timeout 20 "$binary" --sample --test-mid-drag 800 --snapshot "$work/tall.png" > /dev/null
check "while dragging shorter, the header stays at the top" "same" "$(python3 -I "$root/tests/strip_diff.py" "$work/normal.png" "$work/short.png" 80)"
check "while dragging taller, the header stays at the top" "same" "$(python3 -I "$root/tests/strip_diff.py" "$work/normal.png" "$work/tall.png" 80)"
timeout 20 "$binary" --sample --widget-cap 300 --test-mid-drag 650 --snapshot "$work/grow.png" > /dev/null
timeout 20 "$binary" --sample --widget-cap 900 --test-mid-drag 650 --snapshot "$work/roomy.png" > /dev/null
check "dragging a capped widget taller reveals more rows as it grows" "same" "$(python3 -I "$root/tests/strip_diff.py" "$work/roomy.png" "$work/grow.png" 1300 380)"

finish
