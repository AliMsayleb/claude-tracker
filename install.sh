#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

hook_choice="ask"
check_only=""
for argument in "$@"; do
  case "$argument" in
    --with-hook) hook_choice="yes" ;;
    --no-hook) hook_choice="no" ;;
    --check) check_only="yes" ;;
    -h|--help)
      echo "Usage: ./install.sh [--with-hook | --no-hook] [--check]"
      echo "  --with-hook  also add the Allow/Deny hook to ~/.claude/settings.json"
      echo "  --no-hook    do not add the hook (and do not ask)"
      echo "  --check      only check the requirements"
      exit 0
      ;;
    *) echo "Unknown option: $argument" >&2; exit 1 ;;
  esac
done

problems=0
problem() { echo "  ✗ $1" >&2; problems=$((problems + 1)); }
ok() { echo "  ✓ $1"; }

echo "Checking requirements"
major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$major" -ge 15 ]; then ok "macOS $(sw_vers -productVersion)"; else problem "macOS 15 or newer is required (you have $(sw_vers -productVersion))"; fi
if command -v swiftc > /dev/null && xcode-select -p > /dev/null 2>&1; then ok "Swift compiler"; else problem "Swift compiler not found. Install the Xcode command line tools: xcode-select --install"; fi
if command -v jq > /dev/null; then ok "jq"; else problem "jq not found. Install it with: brew install jq"; fi
if [ -d "/Applications/Claude.app" ] || command -v claude > /dev/null; then ok "Claude Desktop or Claude Code"; else echo "  ! Claude Desktop / Claude Code not found (the widget shows nothing until a session runs)"; fi

if [ "$problems" -gt 0 ]; then
  echo "Fix the problems above and run ./install.sh again." >&2
  exit 1
fi
[ -z "$check_only" ] || exit 0

echo "Installing"
./scripts/install-app.sh

if [ "$hook_choice" = "ask" ]; then
  if [ -t 0 ]; then
    echo
    echo "Allow / Deny buttons need one hook in ~/.claude/settings.json. This is the change:"
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$HOME/.claude-widget/permission-hook.sh" ] && break; sleep 0.5; done
    ./scripts/install-hook.sh --dry-run
    printf "Add it? [y/N] "
    read -r answer
    case "$answer" in y|Y|yes|YES) hook_choice="yes" ;; *) hook_choice="no" ;; esac
  else
    hook_choice="no"
  fi
fi
if [ "$hook_choice" = "yes" ]; then
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$HOME/.claude-widget/permission-hook.sh" ] && break; sleep 0.5; done
  ./scripts/install-hook.sh
else
  echo "Skipped the hook. Add it later with: scripts/install-hook.sh"
fi

echo
echo "Done. Claude Tracker is running. To open it later: Spotlight (⌘Space) -> \"Claude Tracker\"."
echo "Double-tap ⌘ to show or hide it (grant Accessibility from the widget's right-click menu)."
