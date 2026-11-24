#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
status=0
for suite in hook_protocol widget_logic install_hook ui_clicks double_tap select_all markdown return_key popup widget_window widget_resize install_app config_dirs uninstall shortcuts terminal hook_installer_app readme updates new_session keyboard_isolation hover monitors_hotkey; do
  echo "== $suite"
  output="$(bash "$root/tests/$suite.sh" 2>&1)"
  code=$?
  printf '%s\n' "$output"
  [ "$code" -eq 0 ] || status=1
  printf '%s\n' "$output" | grep -q "all passed" || { echo "FAIL $suite did not report results"; status=1; }
done
[ "$status" -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
exit $status
