#!/usr/bin/env bash
# Live portal cancellation checks. Briefly opens native file choosers on the
# desktop; needs a running Omarchy shell, Wayland, wtype, jq and python3-atspi.
#
#   tests/manual/file_picker_cancel.sh
set -euo pipefail

PLUGIN_ID=io.github.analytically.snapmenu
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
state() { omarchy-shell shell call "$PLUGIN_ID" debugState ''; }
field() { state | jq -r ".$1"; }
cleanup() {
  /usr/bin/python3 "$SCRIPT_DIR/cancel_portal.py" >/dev/null 2>&1 || true
  omarchy-shell snapmenu.menu close >/dev/null 2>&1 || true
  omarchy-shell shell hide "$PLUGIN_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for tool in omarchy-shell wtype jq; do
  command -v "$tool" >/dev/null || { printf 'missing %s\n' "$tool" >&2; exit 1; }
done
[[ -n ${WAYLAND_DISPLAY:-} ]] || { printf 'no Wayland session\n' >&2; exit 1; }
/usr/bin/python3 -c 'import gi; gi.require_version("Atspi", "2.0"); from gi.repository import Atspi' \
  || { printf 'python3-atspi is required\n' >&2; exit 1; }

wait_field() { # field expected
  for _ in {1..50}; do
    [[ $(field "$1") == "$2" ]] && return 0
    sleep 0.1
  done
  printf 'expected %s=%s, got %s\n' "$1" "$2" "$(field "$1")" >&2
  return 1
}

cancel_portal() {
  wait_field busy true
  /usr/bin/python3 "$SCRIPT_DIR/cancel_portal.py"
  wait_field busy false
}

cleanup
printf 'Open from full-screen menu: Cancel stays closed\n'
omarchy-shell shell summon "$PLUGIN_ID" '{}' >/dev/null
wait_field opened true
wait_field cardFocus true
wtype -k o
cancel_portal
[[ $(field opened) == false && $(field stage) != result ]]

printf 'Open from bar dropdown: Cancel never summons the full-screen menu\n'
omarchy-shell snapmenu.menu toggle >/dev/null
for _ in {1..30}; do
  [[ $(omarchy-shell snapmenu.menu isOpen) == true ]] && break
  sleep 0.1
done
[[ $(omarchy-shell snapmenu.menu isOpen) == true ]]
open_row=$(omarchy-shell snapmenu.menu rows | jq 'map(.id) | index("open")')
[[ $open_row != null ]]
omarchy-shell snapmenu.menu activate "$open_row" >/dev/null
cancel_portal
[[ $(field opened) == false && $(omarchy-shell snapmenu.menu isOpen) == false ]]

printf 'Dismiss while chooser is open: its later answer cannot reopen Snapmenu\n'
omarchy-shell shell summon "$PLUGIN_ID" '{"command":{"action":"open"}}' >/dev/null
wait_field busy true
omarchy-shell shell hide "$PLUGIN_ID" >/dev/null
/usr/bin/python3 "$SCRIPT_DIR/cancel_portal.py"
sleep 0.5
[[ $(field opened) == false && $(field busy) == false ]]

printf 'Export folder: Cancel returns to Settings without changing the folder\n'
omarchy-shell shell summon "$PLUGIN_ID" '{"stage":"settings"}' >/dev/null
wait_field opened true
wait_field cardFocus true
original_export_dir=$(field exportDir)
# The export-folder row is the ninth selectable row in Settings. Navigating
# without pressing other rows ensures this check does not alter user settings.
for _ in {1..8}; do wtype -k Down; done
wtype -k Return
cancel_portal
[[ $(field opened) == true && $(field stage) == settings && $(field exportDir) == "$original_export_dir" ]]

printf 'file-picker cancellation: all checks passed\n'
