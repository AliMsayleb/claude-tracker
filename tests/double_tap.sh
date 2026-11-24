#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
result="$("$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget" --test-double-tap | tr '\n' ' ')"
check "double tap, slow taps, single, shortcut, triple, shift" \
  "double=1 slow=0 single=0 shortcut=0 triple=1 withshift=0 " "$result"
finish
