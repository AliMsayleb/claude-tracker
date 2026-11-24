#!/bin/bash
set -euo pipefail

if [ -z "${HOOK_SCRIPT_SINGLE:-}" ]; then
  while IFS= read -r file; do
    HOOK_SCRIPT_SINGLE=1 CLAUDE_SETTINGS_FILE="$file" "$0" "$@"
  done < <("$(dirname "$0")/settings-files.sh")
  exit 0
fi

settings="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
hook="${CLAUDE_WIDGET_HOME:-$HOME/.claude-widget}/permission-hook.sh"
command="\"$hook\""

[ -f "$settings" ] || exit 0

updated="$(jq --arg command "$command" '
  if .hooks.PermissionRequest then
    .hooks.PermissionRequest |= map(select(any(.hooks[]?; .command == $command) | not))
    | if (.hooks.PermissionRequest | length) == 0 then del(.hooks.PermissionRequest) else . end
    | if (.hooks | length) == 0 then del(.hooks) else . end
  else . end
' "$settings")"

cp -p "$settings" "$settings.bak-claude-widget"
printf '%s\n' "$updated" > "$settings.tmp"
chmod "$(stat -f %Lp "$settings")" "$settings.tmp"
mv "$settings.tmp" "$settings"
echo "hook removed from $settings (backup: $settings.bak-claude-widget)"
