#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"
export CLAUDE_TRACKER_CLAUDE_ARGS="--model haiku"
for variable in $(env | grep -E '^(CLAUDE_CODE_|CLAUDE_AGENT_SDK|CLAUDE_PREVIEW)' | cut -d= -f1) CLAUDECODE CLAUDE_EFFORT CLAUDE_PID ANTHROPIC_BASE_URL; do unset "$variable"; done

prompt=$'-- it\'s a "quoted" test with $(echo X) and `echo Y`.\nSecond line: reply with only the word OK'
started="$("$binary" --start-session background "$root" "$prompt")"
echo "$started"
id="$(echo "$started" | awk -F' · ' '/^backgrounded/ {print $2}')"
check "the launcher reports a started background session" "yes" "$([ -n "$id" ] && echo yes || echo no)"

for _ in $(seq 1 20); do
  session="$(claude agents --json --all 2> /dev/null | jq -c --arg name "-- it's a \"quoted\" test with \$(echo X) and \`echo Y\`." '[.[] | select(.name != null)] | map(select(.name | startswith("-- it")))[0] // empty')"
  [ -n "$session" ] && break
  sleep 1
done
check "the session shows up in the sessions list" "yes" "$([ -n "$session" ] && echo yes || echo no)"
session_id="$(echo "$session" | jq -r '.sessionId')"
cwd="$(echo "$session" | jq -r '.cwd')"
check "it runs in the chosen folder" "$root" "$cwd"

transcript=""
for _ in $(seq 1 30); do
  transcript="$(ls "$HOME"/.claude/projects/*/"$session_id".jsonl 2> /dev/null | head -1)"
  [ -n "$transcript" ] && grep -q '"role":"user"' "$transcript" 2> /dev/null && break
  sleep 1
done
first_message="$(jq -rs '[.[] | select(.type == "user" and (.message.content | type) == "string")][0].message.content' "$transcript" 2> /dev/null)"
check "Claude received the prompt exactly as typed" "$prompt" "$first_message"

claude stop "$id" > /dev/null 2>&1
claude rm "$id" > /dev/null 2>&1
finish
