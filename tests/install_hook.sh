#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export CLAUDE_SETTINGS_FILE="$work/settings.json"
export CLAUDE_WIDGET_HOME="$work/widget-home"
hook_command="\"$work/widget-home/permission-hook.sh\""

original='{"theme":"auto","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo done"}]}],"PermissionRequest":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/other-hook"}]}]}}'
printf '%s' "$original" > "$CLAUDE_SETTINGS_FILE"
chmod 600 "$CLAUDE_SETTINGS_FILE"

"$root/scripts/install-hook.sh" --dry-run > /dev/null
check "dry run leaves the file untouched" "$original" "$(cat "$CLAUDE_SETTINGS_FILE")"

"$root/scripts/install-hook.sh" > /dev/null
settings() { jq -c "$1" "$CLAUDE_SETTINGS_FILE"; }
check "install adds our hook" "1" "$(settings "[.hooks.PermissionRequest[].hooks[] | select(.command == $(jq -n --arg c "$hook_command" '$c'))] | length")"
check "install keeps the other PermissionRequest hook" "1" "$(settings '[.hooks.PermissionRequest[].hooks[] | select(.command == "/usr/local/bin/other-hook")] | length')"
check "install keeps unrelated hooks" "echo done" "$(settings '.hooks.Stop[0].hooks[0].command' | tr -d '"')"
check "install keeps unrelated settings" "auto" "$(settings '.theme' | tr -d '"')"
check "install writes a backup of the original" "$original" "$(cat "$CLAUDE_SETTINGS_FILE.bak-claude-widget")"
check "install keeps file permissions" "600" "$(stat -f %Lp "$CLAUDE_SETTINGS_FILE")"

"$root/scripts/install-hook.sh" > /dev/null
check "installing twice does not duplicate" "1" "$(settings "[.hooks.PermissionRequest[].hooks[] | select(.command == $(jq -n --arg c "$hook_command" '$c'))] | length")"

"$root/scripts/uninstall-hook.sh" > /dev/null
check "uninstall removes our hook" "0" "$(settings "[.hooks.PermissionRequest[].hooks[] | select(.command == $(jq -n --arg c "$hook_command" '$c'))] | length")"
check "uninstall keeps the other PermissionRequest hook" "1" "$(settings '[.hooks.PermissionRequest[].hooks[] | select(.command == "/usr/local/bin/other-hook")] | length')"
check "uninstall keeps unrelated hooks" "echo done" "$(settings '.hooks.Stop[0].hooks[0].command' | tr -d '"')"

printf '%s' '{"theme":"dark"}' > "$CLAUDE_SETTINGS_FILE"
"$root/scripts/install-hook.sh" > /dev/null
"$root/scripts/uninstall-hook.sh" > /dev/null
check "install then uninstall on a file without hooks restores it" '{"theme":"dark"}' "$(jq -c . "$CLAUDE_SETTINGS_FILE")"

rm "$CLAUDE_SETTINGS_FILE"
"$root/scripts/install-hook.sh" > /dev/null
check "install creates a missing settings file" "1" "$(settings '.hooks.PermissionRequest | length')"

finish
