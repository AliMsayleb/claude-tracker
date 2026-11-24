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

[ -f "$settings" ] || echo '{}' > "$settings"

updated="$(jq --arg command "$command" '
  .hooks.PermissionRequest = (
    ((.hooks.PermissionRequest // []) | map(select(any(.hooks[]?; .command == $command) | not)))
    + [{"hooks": [{"type": "command", "command": $command, "timeout": 630}]}]
  )
' "$settings")"

if [ "${1:-}" = "--dry-run" ]; then
  diff <(jq -S . "$settings") <(printf '%s' "$updated" | jq -S .) || true
  exit 0
fi

cp -p "$settings" "$settings.bak-claude-widget"
printf '%s\n' "$updated" > "$settings.tmp"
chmod "$(stat -f %Lp "$settings")" "$settings.tmp"
mv "$settings.tmp" "$settings"
echo "hook installed in $settings (backup: $settings.bak-claude-widget)"
