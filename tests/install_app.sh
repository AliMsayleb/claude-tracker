#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tests/lib.sh"

target="$(mktemp -d)"
trap 'rm -rf "$target"' EXIT
INSTALL_DIR="$target" SKIP_BUILD=1 SKIP_LAUNCH=1 SKIP_REGISTER=1 "$root/scripts/install-app.sh" > /dev/null

app="$target/Claude Tracker.app"
plist="$app/Contents/Info.plist"
check "app is installed under its search name" "yes" "$([ -d "$app" ] && echo yes || echo no)"
check "display name is Claude Tracker" "Claude Tracker" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$plist")"
check "bundle id is unchanged so settings are kept" "com.local.claude-widget" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
check "installed copy is a valid signed app" "ok" "$(codesign --verify --deep "$app" 2> /dev/null && echo ok || echo bad)"
check "installed copy runs" "ok" "$("$app/Contents/MacOS/claude-widget" --test-markdown > /dev/null 2>&1 && echo ok || echo bad)"
check "installing twice replaces the old copy" "yes" "$(INSTALL_DIR="$target" SKIP_BUILD=1 SKIP_LAUNCH=1 SKIP_REGISTER=1 "$root/scripts/install-app.sh" > /dev/null 2>&1 && [ -d "$app" ] && echo yes || echo no)"

finish
