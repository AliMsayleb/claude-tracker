#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"

work="$(mktemp -d)"
children=()
cleanup() { for pid in "${children[@]:-}"; do kill "$pid" 2> /dev/null; done; rm -rf "$work"; }
trap cleanup EXIT

home="$work/home"
mkdir -p "$home/.claude_backup/sessions" "$home/.claude-old/projects" "$home/.claude/sessions" "$home/.claude-work/projects" "$home/.claude-widget" "$home/.claudeX" "$home/elsewhere/sessions"
export CLAUDE_TRACKER_HOME="$home"
unset CLAUDE_CONFIG_DIR CLAUDE_SESSIONS_DIR CLAUDE_PROJECTS_DIR CLAUDE_SETTINGS_FILE CLAUDE_TRACKER_CONFIG_DIRS
export CLAUDE_WIDGET_HOME="$work/widget-home"

check "the default and any other .claude* folder with Claude data are found" ".claude|.claude-work" \
  "$("$binary" --print-config-dirs | xargs -n1 basename | tr '\n' '|' | sed 's/|$//')"
check "backup and leftover copies are not touched" "0" "$("$binary" --print-config-dirs | xargs -n1 basename | grep -c -i -E 'backup|old')"
check "the widget's own folder and unrelated .claude* folders are ignored" "0" \
  "$("$binary" --print-config-dirs | grep -c -E 'claude-widget|claudeX')"
check "CLAUDE_CONFIG_DIR adds its folder" "1" \
  "$(CLAUDE_CONFIG_DIR="$home/elsewhere" "$binary" --print-config-dirs | grep -c 'elsewhere')"
check "CLAUDE_TRACKER_CONFIG_DIRS replaces the search" "$home/elsewhere|$home/.claude-work" \
  "$(CLAUDE_TRACKER_CONFIG_DIRS="$home/elsewhere:$home/.claude-work" "$binary" --print-config-dirs | tr '\n' '|' | sed 's/|$//')"
check "a symlink to a folder is not listed twice" "2" \
  "$(ln -s "$home/.claude-work" "$home/.claude-link"; "$binary" --print-config-dirs | wc -l | tr -d ' ')"
rm -f "$home/.claude-link"

now_ms=$(( $(date +%s) * 1000 ))
spawn() { sleep 300 > /dev/null 2>&1 & children+=($!); disown $!; last_pid=$!; }
write_session() {
  jq -n --argjson pid "$1" --arg sid "$2" --arg name "$3" --argjson now "$now_ms" \
    '{pid: $pid, sessionId: $sid, cwd: "/work/project", name: $name, status: "idle", startedAt: $now, statusUpdatedAt: $now}' > "$4/$1.json"
}
spawn; first=$last_pid
spawn; second=$last_pid
write_session "$first" sess-one "In the default folder" "$home/.claude/sessions"
mkdir -p "$home/.claude-work/sessions"
write_session "$second" sess-two "In the work folder" "$home/.claude-work/sessions"
check "sessions from every config folder are listed" "In the default folder|In the work folder" \
  "$("$binary" --dump | jq -r '[.[].title] | sort | join("|")')"

mkdir -p "$home/.claude-work/projects/-work-project"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Found in the work folder"}]}}' > "$home/.claude-work/projects/-work-project/sess-two.jsonl"
check "a transcript is found in whichever config folder holds it" "Found in the work folder" "$("$binary" --detail "$second" | head -1)"

printf '{"theme":"auto"}' > "$home/.claude/settings.json"
printf '{"theme":"dark"}' > "$home/.claude-work/settings.json"
check "installing the hook covers every config folder" "hook installed=true" "$("$binary" --install-hook)"
check "the default settings got the hook" "1" "$(jq '.hooks.PermissionRequest | length' "$home/.claude/settings.json")"
check "the work settings got the hook" "1" "$(jq '.hooks.PermissionRequest | length' "$home/.claude-work/settings.json")"
check "removing the hook covers every config folder" "0|0" \
  "$("$binary" --uninstall-hook > /dev/null; jq '.hooks.PermissionRequest // [] | length' "$home/.claude/settings.json" | tr '\n' '|' ; jq '.hooks.PermissionRequest // [] | length' "$home/.claude-work/settings.json")"

printf '{}' > "$home/.claude/settings.json"; printf '{}' > "$home/.claude-work/settings.json"
CLAUDE_WIDGET_HOME="$work/widget-home" "$root/scripts/install-hook.sh" > /dev/null
check "the install script covers every config folder" "1|1" \
  "$(jq '.hooks.PermissionRequest | length' "$home/.claude/settings.json" | tr '\n' '|' ; jq '.hooks.PermissionRequest | length' "$home/.claude-work/settings.json")"
CLAUDE_WIDGET_HOME="$work/widget-home" "$root/scripts/uninstall-hook.sh" > /dev/null
check "the uninstall script covers every config folder" "0|0" \
  "$(jq '.hooks.PermissionRequest // [] | length' "$home/.claude/settings.json" | tr '\n' '|' ; jq '.hooks.PermissionRequest // [] | length' "$home/.claude-work/settings.json")"

finish
