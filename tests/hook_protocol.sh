#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
hook="$root/hook/permission-hook.sh"
payload='{"session_id":"s-1","tool_name":"Bash","tool_input":{"command":"ls"}}'
allow_json='{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
deny_json='{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from the Claude Code widget"}}}'
homes=()

new_home() {
  home="$(mktemp -d)"
  homes+=("$home")
  mkdir -p "$home/requests"
  date +%s > "$home/heartbeat"
}

cleanup() { [ "${#homes[@]}" -eq 0 ] || rm -rf "${homes[@]}"; }
trap cleanup EXIT

wait_for_request() {
  for _ in $(seq 1 40); do
    ls "$1"/requests/*.json > /dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

request_id() { basename "$(ls "$1"/requests/*.json | head -1)" .json; }

wait_for_exit() {
  for _ in $(seq 1 40); do
    kill -0 "$1" 2> /dev/null || return 0
    sleep 0.1
  done
  return 1
}

run_with_decision() {
  local home="$1" decision="$2"
  printf '%s' "$payload" | CLAUDE_WIDGET_HOME="$home" "$hook" > "$home/out" &
  local pid=$!
  wait_for_request "$home"
  printf '%s' "$decision" > "$home/requests/$(request_id "$home").decision"
  wait "$pid"
  cat "$home/out"
}

new_home; rm "$home/heartbeat"
started=$(date +%s)
out="$(printf '%s' "$payload" | CLAUDE_WIDGET_HOME="$home" "$hook")"
check "no heartbeat: silent" "" "$out"
check "no heartbeat: exits at once" "yes" "$([ "$(seconds_since "$started")" -le 1 ] && echo yes || echo no)"
check "no heartbeat: no request left" "0" "$(ls "$home/requests" | wc -l | tr -d ' ')"

new_home; touch -t 200001010000 "$home/heartbeat"
out="$(printf '%s' "$payload" | CLAUDE_WIDGET_HOME="$home" "$hook")"
check "stale heartbeat: silent" "" "$out"

new_home
out="$(printf '%s' '{"session_id":"s-1","tool_name":"AskUserQuestion","tool_input":{}}' | CLAUDE_WIDGET_HOME="$home" "$hook")"
check "AskUserQuestion: ignored" "" "$out"
check "AskUserQuestion: no request" "0" "$(ls "$home/requests" | wc -l | tr -d ' ')"

new_home
out="$(printf '%s' '{"session_id":"s-1","tool_name": "ExitPlanMode","tool_input":{}}' | CLAUDE_WIDGET_HOME="$home" "$hook")"
check "ExitPlanMode with spaces: ignored" "" "$out"

new_home
check "allow decision" "$allow_json" "$(run_with_decision "$home" allow)"
check "allow: request cleaned up" "0" "$(ls "$home/requests" | wc -l | tr -d ' ')"

new_home
check "deny decision" "$deny_json" "$(run_with_decision "$home" deny)"
check "deny: request cleaned up" "0" "$(ls "$home/requests" | wc -l | tr -d ' ')"

new_home
printf '%s' "$payload" | CLAUDE_WIDGET_HOME="$home" "$hook" > "$home/out" &
pid=$!
wait_for_request "$home"
check "request payload saved verbatim" "$payload" "$(cat "$home/requests/$(request_id "$home").json")"
rm "$home/requests/$(request_id "$home").json"
wait_for_exit "$pid"
check "request removed by widget: hook exits" "gone" "$(kill -0 "$pid" 2> /dev/null && echo running || echo gone)"
check "request removed by widget: silent" "" "$(cat "$home/out")"

new_home
printf '%s' "$payload" | CLAUDE_WIDGET_HOME="$home" "$hook" > "$home/out" &
pid=$!
wait_for_request "$home"
touch -t 200001010000 "$home/heartbeat"
wait_for_exit "$pid"
check "widget stopped: hook exits" "gone" "$(kill -0 "$pid" 2> /dev/null && echo running || echo gone)"
check "widget stopped: silent" "" "$(cat "$home/out")"
check "widget stopped: request cleaned" "0" "$(ls "$home/requests" | wc -l | tr -d ' ')"

new_home
printf '%s' "$payload" | CLAUDE_WIDGET_HOOK_WAIT=1 CLAUDE_WIDGET_HOME="$home" "$hook" > "$home/out" &
pid=$!
sleep 0.5; date +%s > "$home/heartbeat"
wait_for_exit "$pid"
check "timeout: hook exits" "gone" "$(kill -0 "$pid" 2> /dev/null && echo running || echo gone)"
check "timeout: silent" "" "$(cat "$home/out")"
check "timeout: request cleaned" "0" "$(ls "$home/requests" | wc -l | tr -d ' ')"

finish
