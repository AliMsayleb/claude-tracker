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

finish
