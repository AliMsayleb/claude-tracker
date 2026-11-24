#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

destination="${INSTALL_DIR:-$HOME/Applications}/Claude Tracker.app"
widget_home="${CLAUDE_WIDGET_HOME:-$HOME/.claude-widget}"
settings="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"

[ -n "${SKIP_QUIT:-}" ] || pkill -x claude-widget 2> /dev/null || true
rm -rf "$destination"
if [ -f "$settings" ]; then CLAUDE_SETTINGS_FILE="$settings" CLAUDE_WIDGET_HOME="$widget_home" ./scripts/uninstall-hook.sh > /dev/null; fi
rm -rf "$widget_home"
[ "${1:-}" != "--purge-preferences" ] || defaults delete com.local.claude-widget 2> /dev/null || true

echo "Removed Claude Tracker, its hook and ~/.claude-widget."
echo "If it is listed under System Settings > General > Login Items, remove it there."
