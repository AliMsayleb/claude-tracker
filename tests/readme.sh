#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"

missing=""
for image in $(grep -o 'docs/screenshots/[A-Za-z0-9_-]*\.png' "$root/README.md" | sort -u); do
  [ -s "$root/$image" ] || missing="$missing $image"
done
check "every screenshot the README uses exists" "" "$missing"
check "the README shows at least four different screenshots" "yes" \
  "$([ "$(grep -o 'docs/screenshots/[A-Za-z0-9_-]*\.png' "$root/README.md" | sort -u | wc -l | tr -d ' ')" -ge 4 ] && echo yes || echo no)"
check "screenshots are not huge (each under 1 MB)" "" "$(find "$root/docs/screenshots" -name '*.png' -size +1M)"

finish
