#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

name="Claude Tracker"
destination_directory="${INSTALL_DIR:-$HOME/Applications}"
destination="$destination_directory/$name.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

[ -n "${SKIP_BUILD:-}" ] || ./scripts/build.sh

mkdir -p "$destination_directory"
[ -n "${SKIP_LAUNCH:-}" ] || pkill -x claude-widget 2> /dev/null || true
rm -rf "$destination"
cp -R build/ClaudeWidget.app "$destination"

if [ -z "${SKIP_REGISTER:-}" ]; then
  "$lsregister" -f "$destination"
  mdimport "$destination"
fi

[ -n "${SKIP_LAUNCH:-}" ] || open "$destination"
echo "installed $destination"
