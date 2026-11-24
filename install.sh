#!/bin/bash
set -euo pipefail

repository="AliMsayleb/claude-tracker"
release_url="https://github.com/$repository/releases/latest/download"
name="Claude Tracker"
destination_directory="${INSTALL_DIR:-$HOME/Applications}"
destination="$destination_directory/$name.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

from_source=""
check_only=""
for argument in "$@"; do
  case "$argument" in
    --from-source) from_source="yes" ;;
    --check) check_only="yes" ;;
    -h|--help)
      echo "Usage: ./install.sh [--from-source] [--check]"
      echo "  (default)      download the ready-made app (no compiler needed)"
      echo "  --from-source  build it yourself (needs the full Xcode app)"
      echo "  --check        only check the requirements"
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
for tool in curl unzip shasum; do
  if command -v "$tool" > /dev/null; then :; else problem "$tool is missing"; fi
done
if [ -n "$from_source" ]; then
  if [ -d /Applications/Xcode.app ] || xcode-select -p 2> /dev/null | grep -q '\.app/Contents/Developer'; then
    ok "Xcode"
  else
    problem "Building from source needs the full Xcode app from the App Store, not only the command line tools. Skip --from-source to use the ready-made app."
  fi
fi
if [ -d "/Applications/Claude.app" ] || command -v claude > /dev/null; then ok "Claude Desktop or Claude Code"; else echo "  ! Claude Desktop / Claude Code not found (the widget shows nothing until a session runs)"; fi

if [ "$problems" -gt 0 ]; then
  echo "Fix the problems above and run the installer again." >&2
  exit 1
fi
[ -z "$check_only" ] || exit 0

if [ -n "$from_source" ]; then
  cd "$(dirname "$0")"
  echo "Building from source"
  ./scripts/install-app.sh
else
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  echo "Downloading"
  if ! curl -fsSL "$release_url/Claude-Tracker.zip" -o "$work/app.zip" || ! curl -fsSL "$release_url/Claude-Tracker.zip.sha256" -o "$work/app.sha256"; then
    echo "Could not download the app. Check your connection, or build it yourself with: ./install.sh --from-source" >&2
    exit 1
  fi
  expected="$(awk '{print $1}' "$work/app.sha256")"
  actual="$(shasum -a 256 "$work/app.zip" | awk '{print $1}')"
  if [ "$expected" != "$actual" ]; then
    echo "The download is corrupted (checksum mismatch). Try again." >&2
    exit 1
  fi
  ditto -x -k "$work/app.zip" "$work/unpacked"
  [ -d "$work/unpacked/$name.app" ] || { echo "Unexpected download contents." >&2; exit 1; }

  echo "Installing"
  mkdir -p "$destination_directory"
  [ -n "${SKIP_LAUNCH:-}" ] || pkill -x claude-widget 2> /dev/null || true
  rm -rf "$destination"
  ditto "$work/unpacked/$name.app" "$destination"
  xattr -dr com.apple.quarantine "$destination" 2> /dev/null || true
  if [ -z "${SKIP_REGISTER:-}" ]; then
    "$lsregister" -f "$destination"
    mdimport "$destination"
  fi
  [ -n "${SKIP_LAUNCH:-}" ] || open "$destination"
fi

echo
echo "Done: $destination"
echo "Open it any time with Spotlight (⌘Space, then \"Claude Tracker\")."
echo "Right-click the widget header for \"Set up Allow / Deny buttons\" and the ⌘ shortcut."
