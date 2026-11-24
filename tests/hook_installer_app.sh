#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export CLAUDE_SETTINGS_FILE="$work/settings.json"
export CLAUDE_WIDGET_HOME="$work/home"

original='{"theme":"auto","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo done"}]}],"PermissionRequest":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/other"}]}]}}'
printf '%s' "$original" > "$CLAUDE_SETTINGS_FILE"
chmod 600 "$CLAUDE_SETTINGS_FILE"

check "status before installing" "hook installed=false" "$("$binary" --hook-status)"
check "install reports success" "hook installed=true" "$("$binary" --install-hook)"
check "other settings and hooks are kept" "auto|echo done|/usr/local/bin/other" \
  "$(jq -r '[.theme, .hooks.Stop[0].hooks[0].command, .hooks.PermissionRequest[0].hooks[0].command] | join("|")' "$CLAUDE_SETTINGS_FILE")"
check "our hook uses a 10 minute timeout" "630" "$(jq -r '.hooks.PermissionRequest[1].hooks[0].timeout' "$CLAUDE_SETTINGS_FILE")"
check "a backup of the original is saved" "$(printf '%s' "$original" | jq -S -c .)" "$(jq -S -c . "$CLAUDE_SETTINGS_FILE.bak-claude-tracker")"
check "file permissions are kept" "600" "$(stat -f %Lp "$CLAUDE_SETTINGS_FILE")"
"$binary" --install-hook > /dev/null
check "installing twice does not duplicate" "2" "$(jq '.hooks.PermissionRequest | length' "$CLAUDE_SETTINGS_FILE")"
check "uninstall removes only our hook" "hook installed=false" "$("$binary" --uninstall-hook)"
check "other PermissionRequest hook survives uninstall" "1" "$(jq '.hooks.PermissionRequest | length' "$CLAUDE_SETTINGS_FILE")"

echo '{"theme":"dark"}' > "$CLAUDE_SETTINGS_FILE"
"$binary" --install-hook > /dev/null
"$binary" --uninstall-hook > /dev/null
check "install then uninstall restores a file without hooks" '{"theme":"dark"}' "$(jq -c . "$CLAUDE_SETTINGS_FILE")"
echo 'not json' > "$CLAUDE_SETTINGS_FILE"
check "a broken settings file is never overwritten" "not json" "$("$binary" --install-hook > /dev/null 2>&1; cat "$CLAUDE_SETTINGS_FILE")"
rm "$CLAUDE_SETTINGS_FILE"
check "a missing settings file is created" "hook installed=true" "$("$binary" --install-hook)"

finish
