#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

binary="build/ClaudeWidget.app/Contents/MacOS/claude-widget"
[ -x "$binary" ] || ./scripts/build.sh
"$binary" --print-shortcuts > build/shortcuts.md
python3 -I - << 'PY'
import re
readme = open("README.md").read()
block = open("build/shortcuts.md").read().strip()
updated = re.sub(r"(<!-- shortcuts:start -->).*?(<!-- shortcuts:end -->)", lambda m: m.group(1) + "\n" + block + "\n" + m.group(2), readme, flags=re.S)
open("README.md", "w").write(updated)
PY
echo "README shortcuts updated"
