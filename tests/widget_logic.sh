#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"

sessions="$(mktemp -d)"
home="$(mktemp -d)"
mkdir -p "$home/requests"
children=()
cleanup() {
  [ "${#children[@]}" -eq 0 ] || kill "${children[@]}" 2> /dev/null
  rm -rf "$sessions" "$home" "$desktop"
}
trap cleanup EXIT

export CLAUDE_SESSIONS_DIR="$sessions"
export CLAUDE_WIDGET_HOME="$home"
desktop="$(mktemp -d)"
export CLAUDE_DESKTOP_SESSIONS_DIR="$desktop"

now_ms=$(( $(date +%s) * 1000 ))

spawn_live_process() {
  sleep 300 > /dev/null 2>&1 &
  last_pid=$!
  disown "$last_pid"
  children+=("$last_pid")
}

write_session() {
  jq -n --argjson pid "$1" --arg sid "$2" --arg name "$3" --arg status "$4" --arg waiting "$5" \
    --argjson started "$6" --argjson updated "$7" \
    '{pid: $pid, sessionId: $sid, cwd: "/work/project", name: $name, status: $status,
      startedAt: $started, statusUpdatedAt: $updated, entrypoint: "claude-desktop",
      hostSessionId: ("local_" + $sid)}
     + (if $waiting == "" then {} else {waitingFor: $waiting} end)' > "$sessions/$1.json"
}

write_request() {
  jq -n --arg sid "$2" --arg tool "$3" --arg command "$4" \
    '{session_id: $sid, tool_name: $tool, tool_input: {command: $command}}' > "$home/requests/$1.json"
  touch -t "$(date -v-"$5"S +%Y%m%d%H%M.%S)" "$home/requests/$1.json"
}

spawn_live_process; pid_a=$last_pid
spawn_live_process; pid_b=$last_pid
spawn_live_process; pid_c=$last_pid
spawn_live_process; pid_e=$last_pid
spawn_live_process; pid_f=$last_pid

write_session "$pid_a" sess-a "Needs permission session" waiting "permission prompt" "$now_ms" $((now_ms - 30000))
write_session "$pid_b" sess-b "Needs answer session" waiting "input needed" "$now_ms" $((now_ms - 20000))
write_session "$pid_c" sess-c "Working session" busy "" "$now_ms" $((now_ms - 5000))
write_session 999999 sess-d "Dead session" idle "" "$now_ms" "$now_ms"
write_session "$pid_e" sess-e "Reused pid session" idle "" $((now_ms - 864000000)) "$now_ms"
write_session "$pid_f" sess-f "Idle session" idle "" "$now_ms" $((now_ms - 60000))
echo '{ not json' > "$sessions/garbage.json"

write_request req-expired sess-a Bash "echo expired" 700
write_request req-before-waiting sess-a Bash "echo before" 60
write_request req-current sess-a Bash "rm -rf build" 10
write_request req-busy-session sess-c Bash "echo busy" 20
write_request req-fresh-busy sess-c Bash "echo fresh" 1
write_request req-unknown-session sess-x Bash "echo unknown" 20
jq -n '{session_id: "sess-b", tool_name: "AskUserQuestion", tool_input: {questions: [{question: "Which color?", header: "Color", multiSelect: false, options: [{label: "Red", description: "warm"}, {label: "Blue", description: "cool"}]}]}}' > "$home/requests/req-question.json"
touch -t "$(date -v-10S +%Y%m%d%H%M.%S)" "$home/requests/req-question.json"

jq -n '{sessionId: "local_sess-f", title: "x", cwd: "/w", isArchived: false, lastActivityAt: 5, lastFocusedAt: 1000, lastTurnEdgeAt: 2000, postTurnSummary: {status_detail: "Finished the refactor", needs_action: ""}}' > "$desktop/local_sess-f.json"
jq -n '{sessionId: "local_sess-b", title: "x", cwd: "/w", isArchived: false, lastActivityAt: 5, lastFocusedAt: 1000, lastTurnEdgeAt: 2000, postTurnSummary: {status_detail: "old", needs_action: "Do you want a reply?"}}' > "$desktop/local_sess-b.json"
jq -n '{sessionId: "local_sess-c", title: "x", cwd: "/w", isArchived: false, lastActivityAt: 5, lastFocusedAt: 1000, lastTurnEdgeAt: 2000}' > "$desktop/local_sess-c.json"

dump() { "$binary" --dump; }

check "list order" \
  "Needs permission session|Needs answer session|Idle session|Working session" \
  "$(dump | jq -r '[.[].title] | join("|")')"
check "dead pid and reused pid are hidden" "0" \
  "$(dump | jq '[.[] | select(.title == "Dead session" or .title == "Reused pid session")] | length')"
check "states" "needsPermission|needsInput|unread|working" "$(dump | jq -r '[.[].state] | join("|")')"
check "desktop deep link id is passed on" "local_sess-a" "$(dump | jq -r '.[0].hostSessionId')"
check "requests attach only to waiting-for-permission sessions (oldest first)" \
  "req-expired,req-before-waiting,req-current" \
  "$(dump | jq -r '.[0].requests | map(.id) | join(",")')"
check "no requests on a working session" "0" "$(dump | jq '.[3].requests | length')"
check "request tool and detail" "Bash|rm -rf build" \
  "$(dump | jq -r '.[0].requests[] | select(.id == "req-current") | "\(.toolName)|\(.detail)"')"

projects="$(mktemp -d)"; export CLAUDE_PROJECTS_DIR="$projects"
mkdir -p "$projects/-work-project"
{
  echo '{"type":"user","message":{"content":"hi"}}'
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Older answer"}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Latest answer"},{"type":"tool_use","name":"Bash"}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}'
  echo '{"type":"user","message":{"content":"tool result"}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"old1","name":"Agent"}]}}'
  echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"old1"}]}}'
  echo '{"type":"user","message":{"content":"next question"}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a1","name":"Agent"},{"type":"tool_use","id":"a2","name":"Task"},{"type":"tool_use","id":"a3","name":"Agent"}]}}'
  echo '{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","id":"side1","name":"Agent"}]}}'
  echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a1"},{"type":"tool_result","tool_use_id":"a2"}]}}'
  echo '{"type":"user","message":{"content":"Another Claude session sent a message: keep going"}}'
} > "$projects/-work-project/sess-f.jsonl"
check "expanded detail is the last assistant text" "Latest answer" "$("$binary" --detail "$pid_f")"
check "sub-agent counter counts only the current turn, ignoring side chains and replies sent from the widget" "2/3" \
  "$(dump | jq -r '[.[] | select(.title == "Idle session")][0].agents | "\(.done)/\(.total)"')"
check "no counter without sub-agents" "null" "$(dump | jq -c '[.[] | select(.title == "Working session")][0].agents')"
long_text="$(python3 -I -c 'print("Paragraph one. " * 400 + "\n\nTHE-VERY-END")')"
jq -cn --arg text "$long_text" '{type: "assistant", message: {content: [{type: "text", text: $text}]}}' > "$projects/-work-project/sess-b.jsonl"
long_reply="$("$binary" --detail "$pid_b")"
check "a long reply (6000+ characters) reaches the popup in full" "yes" \
  "$([ "${#long_reply}" -gt 6000 ] && [[ "$long_reply" == *THE-VERY-END ]] && echo yes || echo no)"
check "detail is empty when there is no transcript" "" "$("$binary" --detail "$pid_c")"
rm -rf "$projects"; unset CLAUDE_PROJECTS_DIR

echo '{"seen":{"local_sess-f":99999999999999}}' > "$home/state.json"
check "clicking a row marks it seen (no longer unread)" "idle" "$(dump | jq -r '[.[] | select(.title == "Idle session")][0].state')"
rm "$home/state.json"

check "unread: idle session whose turn ended after last focus" "Finished the refactor" "$(dump | jq -r '.[2].summary')"
check "needs-answer row shows what is needed" "Do you want a reply?" "$(dump | jq -r '.[1].summary')"
check "working session is never marked unread or summarized" "working|null" "$(dump | jq -r '.[3] | "\(.state)|\(.summary)"')"
jq -n '{sessionId: "local_old", title: "Old session", cwd: "/work/old", isArchived: false, lastActivityAt: 1000000}' > "$desktop/local_old.json"
jq -n '{sessionId: "local_arch", title: "Archived", cwd: "/work/a", isArchived: true, lastActivityAt: 1}' > "$desktop/local_arch.json"
echo '{"hidden":["local_sess-f"],"pinned":["local_old","local_arch"]}' > "$home/state.json"
check "hidden session is not listed" "0" "$(dump | jq '[.[] | select(.title == "Idle session")] | length')"
check "pinned existing session is listed as not running" "Old session|false"   "$(dump | jq -r '.[] | select(.title == "Old session") | "\(.title)|\(.running)"')"
check "archived sessions are not offered" "0" "$(dump | jq '[.[] | select(.title == "Archived")] | length')"
rm "$home/state.json"

sockdir="$(mktemp -d)"
python3 -I - "$sockdir/$pid_a.sock" "$sockdir/received" << 'PY' &
import socket, sys
path, out = sys.argv[1], sys.argv[2]
server = socket.socket(socket.AF_UNIX)
server.bind(path)
server.listen(1)
connection, _ = server.accept()
data = b""
while True:
    chunk = connection.recv(4096)
    if not chunk:
        break
    data += chunk
open(out, "wb").write(data)
PY
for _ in $(seq 1 30); do [ -S "$sockdir/$pid_a.sock" ] && break; sleep 0.1; done
jq --arg path "$sockdir/$pid_a.sock" '. + {messagingSocketPath: $path}' "$sessions/$pid_a.json" > "$sessions/tmp" && mv "$sessions/tmp" "$sessions/$pid_a.json"
echo '{"peerToken":"tok123","procStart":"x","pidDomain":"darwin"}' > "$sessions/$pid_a.deadbeef.key"
check "send reports success" "sent" "$("$binary" --send "$pid_a" "hello there")"
wait $!
check "message is an auth line then a user message" '["auth","tok123"]|["user","hello there"]' \
  "$(jq -c '[.type, (.token // .message.content)]' "$sockdir/received" | tr '\n' '|' | sed 's/|$//')"
check "send to a session without a socket fails" "failed: This session has no safe message socket." "$("$binary" --send "$pid_c" "hi")"
check "send to an unknown session fails" "no such session" "$("$binary" --send 424242 "hi")"
rm -rf "$sockdir"

"$binary" --gc
remaining="$(ls "$home/requests" | sed 's/\.json$//' | sort | tr '\n' ',')"
check "gc keeps current requests, fresh ones and a pending question" "req-current,req-fresh-busy,req-question," "$remaining"
check "heartbeat written by gc" "yes" "$([ -f "$home/heartbeat" ] && echo yes || echo no)"

check "after gc the permission row has one request" "req-current" \
  "$(dump | jq -r '.[0].requests | map(.id) | join(",")')"

check "a question attaches to the session that is waiting for an answer" "Which color?|Red,Blue" \
  "$(dump | jq -r '[.[] | select(.title == "Needs answer session")][0].requests[0].questions[0] | "\(.question)|\([.options[].label] | join(","))"')"
"$binary" --answer req-question 1 > /dev/null
check "answering writes a hook response with the chosen option and the original questions" \
  "allow|Blue|Which color?" \
  "$(jq -r '.hookSpecificOutput.decision | "\(.behavior)|\(.updatedInput.answers["Which color?"])|\(.updatedInput.questions[0].question)"' "$home/requests/req-question.decision")"
check "answering a missing option fails" "1" "$("$binary" --answer req-question 9 > /dev/null; echo $?)"

"$binary" --decide req-current allow
check "decide allow writes decision file" "allow" "$(cat "$home/requests/req-current.decision")"
"$binary" --decide req-current deny
check "decide deny overwrites" "deny" "$(cat "$home/requests/req-current.decision")"
"$binary" --decide no-such-request allow > /dev/null
check "decide unknown request fails" "1" "$?"

write_session 1 sess-spare "Spare process session" busy "" "$now_ms" "$now_ms"
check "a session started in a process that was already running is listed" "1" \
  "$(dump | jq '[.[] | select(.title == "Spare process session")] | length')"
check "a reused pid is still hidden" "0" \
  "$(dump | jq '[.[] | select(.title == "Reused pid session")] | length')"

spawn_live_process; bg_idle=$last_pid
spawn_live_process; bg_busy=$last_pid
write_session "$bg_idle" sess-bg-idle "Background idle" idle "" "$now_ms" "$now_ms"
write_session "$bg_busy" sess-bg-busy "Background busy" busy "" "$now_ms" "$now_ms"
for pid in "$bg_idle" "$bg_busy"; do jq '. + {kind: "bg"}' "$sessions/$pid.json" > "$sessions/$pid.tmp" && mv "$sessions/$pid.tmp" "$sessions/$pid.json"; done
check "a finished background session is ready for Desktop" "true" "$(dump | jq -r '.[] | select(.title == "Background idle") | .readyForDesktop')"
check "a background session that is still working is not ready" "false" "$(dump | jq -r '.[] | select(.title == "Background busy") | .readyForDesktop')"
check "an ordinary idle session is not offered for hand-over" "false" "$(dump | jq -r '.[] | select(.title == "Idle session") | .readyForDesktop')"

spawn_live_process; mark_pid=$last_pid
write_session "$mark_pid" sess-mark "Marked session" idle "" "$now_ms" "$now_ms"
jq -n '{sessionId: "local_sess-mark", title: "x", cwd: "/w", isArchived: false, lastActivityAt: 5, lastFocusedAt: 5000, lastTurnEdgeAt: 2000}' > "$desktop/local_sess-mark.json"
state_of() { dump | jq -r '.[] | select(.title == "Marked session") | .state'; }
check "a session you already looked at is not unread" "idle" "$(state_of)"
echo "{\"unreadMarks\": {\"local_sess-mark\": 6000}}" > "$home/state.json"
check "marking a session unread makes it unread" "unread" "$(state_of)"
echo "{\"unreadMarks\": {\"local_sess-mark\": 6000}, \"seen\": {\"local_sess-mark\": 7000}}" > "$home/state.json"
check "looking at it again clears the mark" "idle" "$(state_of)"
echo "{\"unreadMarks\": {\"local_sess-mark\": 4000}}" > "$home/state.json"
check "opening it in Desktop after marking clears the mark" "idle" "$(state_of)"
rm -f "$home/state.json"

finish
