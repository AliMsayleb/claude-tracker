#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
expected="#!/bin/zsh
cd -- '/work/it'\\''s here' || exit 1
command -v claude > /dev/null || { echo \"Claude Code (claude) was not found in your PATH.\"; read -r; exit 1; }
exec claude --resume 11111111-2222-3333-4444-555555555555

nil
nil"
check "terminal script quotes paths safely and rejects bad input" "$expected" "$("$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget" --test-terminal-script)"
finish
