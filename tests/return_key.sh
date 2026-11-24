#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
result="$(timeout 20 "$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget" --sample --test-return-key | tr '\n' '|')"
check "shift-return adds a line break, plain return sends" "send pid=1 ab|seen pid=1|after shift-return: [ab\\n]|" "$result"
finish
