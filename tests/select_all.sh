#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
check "command-A selects all text in the reply box" "handled=true selected=11" \
  "$(timeout 20 "$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget" --sample --test-select-all)"
finish
