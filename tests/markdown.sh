#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"
expected='heading1:Title
paragraph:plain **bold** line/second line
bullet•:one
bullet•:two
bullet3.:three
code:code **not bold**
code:| a | b |/| 1 | 2 |'
check "markdown blocks are parsed" "$(printf '%b' "$expected")" "$("$binary" --test-markdown)"
finish
