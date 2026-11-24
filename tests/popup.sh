#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
result="$(timeout 30 "$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget" --sample --test-popup | tr '\n' '|')"
check "popup remembers size, stays open, zooms, closes with command-W" \
  "reopened size=900x700|still open after losing focus=true|zoom after + + + - = 1.2|zoom after reset = 1.0|closed by command-W=true|" "$result"
finish
