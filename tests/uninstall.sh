#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export INSTALL_DIR="$work/Applications"
export CLAUDE_WIDGET_HOME="$work/widget-home"
export CLAUDE_SETTINGS_FILE="$work/settings.json"
export SKIP_BUILD=1 SKIP_LAUNCH=1 SKIP_REGISTER=1 SKIP_QUIT=1

echo '{"theme":"dark"}' > "$CLAUDE_SETTINGS_FILE"
mkdir -p "$CLAUDE_WIDGET_HOME/requests"
echo x > "$CLAUDE_WIDGET_HOME/heartbeat"
"$root/scripts/install-app.sh" > /dev/null
"$root/scripts/install-hook.sh" > /dev/null
check "hook is installed before uninstalling" "1" "$(jq '.hooks.PermissionRequest | length' "$CLAUDE_SETTINGS_FILE")"

"$root/scripts/uninstall.sh" > /dev/null
check "app is removed" "no" "$([ -e "$INSTALL_DIR/Claude Tracker.app" ] && echo yes || echo no)"
check "widget data folder is removed" "no" "$([ -e "$CLAUDE_WIDGET_HOME" ] && echo yes || echo no)"
check "hook is removed from settings" "null" "$(jq -c '.hooks.PermissionRequest' "$CLAUDE_SETTINGS_FILE")"
check "other settings are kept" "dark" "$(jq -r '.theme' "$CLAUDE_SETTINGS_FILE")"
"$root/scripts/uninstall.sh" > /dev/null
check "uninstalling twice is harmless" "0" "$?"
check "installer rejects unknown options" "1" "$("$root/install.sh" --nonsense > /dev/null 2>&1; echo $?)"
check "installer requirement check passes on this Mac" "0" "$("$root/install.sh" --check > /dev/null 2>&1; echo $?)"

finish
