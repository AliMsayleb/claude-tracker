#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
check "test windows drop real keystrokes but keep scripted keys and clicks" "scripted key kept=true unscripted key dropped=true unscripted synthetic key dropped=true mouse kept=true" \
  "$(timeout 20 "$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget" --sample --test-keyboard-isolation)"
finish
