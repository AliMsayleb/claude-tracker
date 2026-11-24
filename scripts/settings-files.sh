#!/bin/bash
set -euo pipefail

if [ -n "${CLAUDE_SETTINGS_FILE:-}" ]; then
  printf '%s\n' "$CLAUDE_SETTINGS_FILE" | tr ':' '\n'
  exit 0
fi

home="${CLAUDE_TRACKER_HOME:-$HOME}"
candidates=()
if [ -n "${CLAUDE_TRACKER_CONFIG_DIRS:-}" ]; then
  while IFS= read -r dir; do candidates+=("$dir"); done < <(printf '%s\n' "$CLAUDE_TRACKER_CONFIG_DIRS" | tr ':' '\n')
else
  [ -z "${CLAUDE_CONFIG_DIR:-}" ] || candidates+=("$CLAUDE_CONFIG_DIR")
  candidates+=("$home/.claude" "$home/.config/claude")
  for dir in "$home"/.claude*; do
    case "$(basename "$dir")" in .claude-widget | .claude.json* | *[Bb]ackup* | *[Bb][Aa][Kk]* | *[Oo]ld* | *[Cc]opy* | *[Tt]mp* | *[Aa]rchive*) continue ;; esac
    [ -e "$dir/sessions" ] || [ -e "$dir/projects" ] || [ -e "$dir/settings.json" ] || continue
    candidates+=("$dir")
  done
fi

seen=""
for dir in "${candidates[@]}"; do
  [ -d "$dir" ] || continue
  real="$(cd "$dir" && pwd -P)"
  case "$seen" in *"|$real|"*) continue ;; esac
  seen="$seen|$real|"
  printf '%s\n' "$dir/settings.json"
done
