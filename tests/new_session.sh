#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"
binary="$root/build/ClaudeWidget.app/Contents/MacOS/claude-widget"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/it's a folder"
folder="$work/it's a folder"
cat > "$work/bin/claude" << 'FAKE'
#!/bin/bash
echo "CWD:$(pwd -P)"
for argument in "$@"; do printf 'ARG:%s\n' "$argument"; done
FAKE
chmod +x "$work/bin/claude"

nasty=$'-dash first, it\'s "quoted" $(echo INJECTED) `echo INJECTED` \\ backslash; echo INJECTED\nsecond line & more'

first_line="${nasty%%$'\n'*}"
for target in terminal background; do
  "$binary" --print-new-session "$target" "$folder" "$nasty" > "$work/$target.sh"
  output="$(PATH="$work/bin:$PATH" zsh "$work/$target.sh")"
  check "$target: starts in the chosen folder" "CWD:$(cd "$folder" && pwd -P)" "$(printf '%s\n' "$output" | head -1)"
  received="$(printf '%s\n' "$output" | sed -n '/^ARG:--$/,$p' | sed '1d' | sed '1s/^ARG://')"
  check "$target: the prompt arrives as one untouched argument after a double dash" "$nasty" "$received"
  check "$target: nothing in the prompt was executed" "0" "$(printf '%s\n' "$output" | grep -c -x 'INJECTED')"
done
check "background: asks for a named background session" "ARG:--bg|ARG:--name|ARG:${first_line:0:40}|ARG:--" \
  "$(PATH="$work/bin:$PATH" zsh "$work/background.sh" | sed -n '2,5p' | tr '\n' '|' | sed 's/|$//')"
check "terminal: the prompt follows a double dash, so a leading dash is not an option" "ARG:--" \
  "$(PATH="$work/bin:$PATH" zsh "$work/terminal.sh" | sed -n '2p')"

"$binary" --print-new-session desktop "$folder" "Fix it & ship +1 'now' #1 100%" > "$work/url.txt"
check "desktop: the link survives special characters" "Fix it & ship +1 'now' #1 100%|$folder|code|/new" \
  "$(python3 -I -c "
import sys, urllib.parse as u
url = u.urlsplit(open('$work/url.txt').read().strip())
q = u.parse_qs(url.query)
print('|'.join([q['q'][0], q['folder'][0], url.netloc, url.path]))")"

check "an empty prompt is refused" "error: Write what you want Claude to do." "$("$binary" --print-new-session terminal "$folder" "   ")"
check "a relative folder is refused" "error: Pick a folder that exists." "$("$binary" --print-new-session terminal "relative/path" "hi")"
check "a missing folder is refused" "error: Pick a folder that exists." "$("$binary" --print-new-session terminal "$work/nope" "hi")"
long="$(python3 -I -c 'print("x" * 2500)')"
check "a prompt too long for a desktop link is refused" "error: That prompt is too long for this option (limit 2000 characters)." "$("$binary" --print-new-session desktop "$folder" "$long")"
check "the same prompt is fine for the terminal" "0" "$("$binary" --print-new-session terminal "$folder" "$long" > /dev/null; echo $?)"

check "the window starts a session with the folder and prompt it shows" "start background $work hello there" \
  "$(timeout 20 "$binary" --sample --draft-new-session "$work" "hello there" --start-new-session background)"
check "the window refuses to start with no prompt" "" "$(timeout 20 "$binary" --sample --draft-new-session "$work" "" --start-new-session desktop)"
timeout 20 "$binary" --sample --open-new-session --snapshot "$work/w.png"
check "the new-session window opens" "yes" "$([ -f "$work/w.png-newsession.png" ] && echo yes || echo no)"

check "resume link uses the session id" "claude://resume?session=22222222-2222-2222-2222-222222222222" "$("$binary" --print-resume-url 22222222-2222-2222-2222-222222222222)"
check "resume link refuses anything that is not a session id" "nil" "$("$binary" --print-resume-url "x&folder=/")"
check "background → desktop uses the background launch script" "0" "$("$binary" --print-new-session backgroundDesktop "$folder" "hi" | diff -q - <("$binary" --print-new-session background "$folder" "hi") > /dev/null; echo $?)"
check "background → desktop accepts a long prompt" "0" "$("$binary" --print-new-session backgroundDesktop "$folder" "$long" > /dev/null; echo $?)"

check "no folder: the desktop link has no folder" "claude://code/new?q=hi" "$("$binary" --print-new-session desktop none "hi")"
scratch="$work/scratch/org/user"
mkdir -p "$scratch/scratch-2026-10-01-aaaaaa" "$scratch/scratch-2026-11-01-bbbbbb" "$scratch/scratch-2026-11-24-cccccc"
cat > "$work/claude.json" << JSON
{"projects": {"$scratch/scratch-2026-10-01-aaaaaa": {"hasTrustDialogAccepted": true},
 "$scratch/scratch-2026-11-01-bbbbbb": {"hasTrustDialogAccepted": true},
 "$scratch/scratch-2026-11-24-cccccc": {"hasTrustDialogAccepted": false}}}
JSON
export CLAUDE_TRACKER_SCRATCH_ROOT="$work/scratch" CLAUDE_TRACKER_CLAUDE_JSON="$work/claude.json"
for target in terminal background; do
  "$binary" --print-new-session "$target" none "$nasty" > "$work/nofolder-$target.sh"
  output="$(PATH="$work/bin:$PATH" zsh "$work/nofolder-$target.sh")"
  check "no folder ($target): uses the newest trusted Desktop scratch folder" "CWD:$(cd "$scratch/scratch-2026-11-01-bbbbbb" && pwd -P)" "$(printf '%s\n' "$output" | head -1)"
  check "no folder ($target): the prompt still arrives untouched" "$nasty" "$(printf '%s\n' "$output" | sed -n '/^ARG:--$/,$p' | sed '1d' | sed '1s/^ARG://')"
done
echo '{"projects": {}}' > "$work/claude.json"
"$binary" --print-new-session terminal none "hi" > "$work/fallback.sh"
check "no folder: falls back to the widget's own folder when no trusted scratch folder exists" "yes" "$(grep -q 'no-folder' "$work/fallback.sh" && echo yes || echo no)"
unset CLAUDE_TRACKER_SCRATCH_ROOT CLAUDE_TRACKER_CLAUDE_JSON
timeout 20 "$binary" --sample --new-session-size 900 700 --new-session-no-folder --snapshot "$work/big.png" > /dev/null
check "the new-session window can be resized" "1800x1400" "$(sips -g pixelWidth -g pixelHeight "$work/big.png-newsession.png" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}')"
timeout 20 "$binary" --sample --open-new-session --snapshot "$work/normal.png" > /dev/null
check "the window opens at its normal size again after a resize" "1200x1320" "$(sips -g pixelWidth -g pixelHeight "$work/normal.png-newsession.png" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}')"


for target in terminal background; do
  "$binary" --print-new-session "$target" "$folder" "hi" --with-model opus --with-effort xhigh > "$work/choice-$target.sh"
  args="$(PATH="$work/bin:$PATH" zsh "$work/choice-$target.sh" | grep '^ARG:' | tr '\n' '|')"
  check "$target: the chosen model is passed to claude" "yes" "$(printf '%s' "$args" | grep -q 'ARG:--model|ARG:opus|' && echo yes || echo no)"
  check "$target: the chosen effort is passed to claude" "yes" "$(printf '%s' "$args" | grep -q 'ARG:--effort|ARG:xhigh|' && echo yes || echo no)"
  "$binary" --print-new-session "$target" "$folder" "hi" > "$work/default-$target.sh"
  check "$target: no model or effort flags unless chosen" "0" "$(grep -c -e '--model' -e '--effort' "$work/default-$target.sh")"
done

finish
