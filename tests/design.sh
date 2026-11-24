#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"

check "choices use the shared RichPicker, not plain menus or system pickers" "ok" "$(python3 -I "$root/tests/design_lint.py" | tail -1)"

finish
