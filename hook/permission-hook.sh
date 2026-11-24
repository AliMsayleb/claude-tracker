#!/bin/bash
home="${CLAUDE_WIDGET_HOME:-$HOME/.claude-widget}"
heartbeat="$home/heartbeat"
requests="$home/requests"
max_wait="${CLAUDE_WIDGET_HOOK_WAIT:-600}"

widget_is_running() {
  [ -f "$heartbeat" ] && [ $(( $(date +%s) - $(stat -f %m "$heartbeat") )) -lt 5 ]
}

widget_is_running || exit 0

payload="$(cat)"

if printf '%s' "$payload" | grep -Eq '"tool_name" *: *"(AskUserQuestion|ExitPlanMode)"'; then
  exit 0
fi

mkdir -p "$requests"
id="$(date +%s)-$$-$RANDOM"
request="$requests/$id.json"
decision="$requests/$id.decision"
trap 'rm -f "$request" "$request.tmp" "$decision"' EXIT

printf '%s' "$payload" > "$request.tmp" && mv "$request.tmp" "$request"

deadline=$((SECONDS + max_wait))
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -f "$decision" ]; then
    case "$(cat "$decision")" in
      allow)
        printf '%s' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
        exit 0
        ;;
      deny)
        printf '%s' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from the Claude Code widget"}}}'
        exit 0
        ;;
    esac
  fi
  [ -f "$request" ] || exit 0
  widget_is_running || exit 0
  sleep 0.5
done
exit 0
