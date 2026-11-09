#!/usr/bin/env bash
# Live Omarchy 4.5 integration check: Snapmenu's annotation paths must open
# Omasnap on the chosen file, dismiss the card, and preserve a temporary shot.
# No exported screenshot is kept and the clipboard is not touched.
set -euo pipefail

PLUGIN_ID=io.github.analytically.snapmenu
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/snapmenu"
SHELL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
for tool in omarchy-shell hyprctl wtype jq magick pgrep; do
  command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }
done
[[ -n ${WAYLAND_DISPLAY:-} ]] || { echo 'not a Wayland session' >&2; exit 1; }
[[ -x /usr/bin/omasnap ]] || { echo 'Omasnap is not installed' >&2; exit 1; }
# Omasnap's --file command terminates an existing capture instance. Never
# disrupt a user's already-open editor or capture to run this test.
if pgrep -x omasnap >/dev/null; then
  echo 'Omasnap is already running; close it before this live test' >&2
  exit 1
fi
state() { omarchy-shell shell call "$PLUGIN_ID" debugState ''; }
[[ $(state | jq -r '.opened or .busy or .selectorActive') == false ]] || {
  echo 'Snapmenu is in use; run this test when it is idle' >&2
  exit 1
}
[[ $(jq -r --arg id "$PLUGIN_ID" '[.bar.layout[]?[]? | select(.id == $id)] | length' "$SHELL_CONFIG") == 1 ]] || {
  echo 'Snapmenu bar entry not found; refusing to change settings' >&2
  exit 1
}

WORK=$(mktemp -d)
FIXTURE="$WORK/test-shot.png"
LAST_SHOT="$STATE_DIR/last-shot"
HAD_LAST_SHOT=false
[[ ! -f $LAST_SHOT ]] || { cp -a "$LAST_SHOT" "$WORK/last-shot"; HAD_LAST_SHOT=true; }
TEMP_SHOT=''
EDITOR_PID=''
setting() {
  jq -r --arg id "$PLUGIN_ID" --arg key "$1" \
    '[.bar.layout[]?[]? | select(.id == $id)] | first | if has($key) then .[$key] else empty end' "$SHELL_CONFIG"
}
SAVE_WAS=$(setting saveToDisk); SAVE_WAS=${SAVE_WAS:-true}
COPY_WAS=$(setting copyToClipboard); COPY_WAS=${COPY_WAS:-false}
ANNOTATE_WAS=$(setting openAnnotate); ANNOTATE_WAS=${ANNOTATE_WAS:-false}
RESULT_WAS=$(setting showResult); RESULT_WAS=${RESULT_WAS:-true}
set_setting() {
  omarchy-shell shell summon "$PLUGIN_ID" \
    "{\"command\":{\"action\":\"set-setting\",\"key\":\"$1\",\"value\":$2}}" >/dev/null
  for _ in {1..20}; do
    [[ $(setting "$1") == "$2" ]] && return 0
    sleep 0.1
  done
  echo "setting $1 did not persist" >&2
  return 1
}
editor_pid_for() { pgrep -f -x "/usr/bin/omasnap --file $1" | head -1 || true; }
editor_mapped() {
  hyprctl layers -j | jq -e '[.. | objects | select(.namespace? == "omasnap")] | length > 0' >/dev/null 2>&1 ||
    hyprctl clients -j | jq -e '[.[] | select((.title // "" | test("omasnap"; "i")) or (.class // "" | test("omasnap"; "i")))] | length > 0' >/dev/null 2>&1
}
wait_for_editor() {
  local file=$1
  EDITOR_PID=''
  for _ in {1..40}; do
    EDITOR_PID=$(editor_pid_for "$file")
    [[ -n $EDITOR_PID ]] && editor_mapped && return 0
    sleep 0.2
  done
  echo "Omasnap did not map an editor for $file" >&2
  return 1
}
stop_editor() {
  [[ -n $EDITOR_PID ]] || return 0
  kill -TERM "$EDITOR_PID" 2>/dev/null || true
  for _ in {1..20}; do
    kill -0 "$EDITOR_PID" 2>/dev/null || break
    sleep 0.1
  done
  EDITOR_PID=''
}
cleanup() {
  trap - EXIT
  set +e
  stop_editor
  omarchy-shell shell hide "$PLUGIN_ID" >/dev/null 2>&1
  set_setting openAnnotate "$ANNOTATE_WAS" >/dev/null 2>&1
  set_setting showResult "$RESULT_WAS" >/dev/null 2>&1
  set_setting saveToDisk "$SAVE_WAS" >/dev/null 2>&1
  set_setting copyToClipboard "$COPY_WAS" >/dev/null 2>&1
  case "$TEMP_SHOT" in "$STATE_DIR"/tmp/*.png) rm -f -- "$TEMP_SHOT" ;; esac
  if $HAD_LAST_SHOT; then cp -a "$WORK/last-shot" "$LAST_SHOT"; else rm -f "$LAST_SHOT"; fi
  rm -rf -- "$WORK"
}
trap cleanup EXIT

# The keyboard shortcut must actually hand the test image to Omasnap, without
# leaving Snapmenu's full-screen card over its editor.
magick -size 160x100 xc:steelblue "$FIXTURE"
omarchy-shell shell summon "$PLUGIN_ID" "$(jq -nc --arg path "$FIXTURE" '{path:$path}')" >/dev/null
for _ in {1..25}; do
  [[ $(state | jq -r '.stage == "result" and .cardFocus') == true ]] && break
  sleep 0.2
done
[[ $(state | jq -r '.stage == "result" and .cardFocus') == true ]] || {
  echo 'action card never got keyboard focus' >&2; exit 1;
}
wtype -k a
wait_for_editor "$FIXTURE"
[[ $(state | jq -r '.opened') == false ]] || { echo 'annotation left the card open' >&2; exit 1; }
[[ -f $FIXTURE ]] || { echo 'Omasnap lost the source file' >&2; exit 1; }
echo 'PASS: A opens the fixture in Omasnap and dismisses the card'
stop_editor

# Automatic annotation takes a real, small capture, but Save off keeps it in
# Snapmenu's temporary state folder. No screenshot lands in Pictures.
set_setting saveToDisk false
set_setting copyToClipboard false
set_setting showResult true
set_setting openAnnotate true
MONITOR=$(hyprctl monitors -j | jq -c '.[] | select(.focused == true)')
[[ -n $MONITOR ]] || { echo 'no focused monitor' >&2; exit 1; }
X=$(jq -r '.x + 20' <<<"$MONITOR")
Y=$(jq -r '.y + 20' <<<"$MONITOR")
OLD_FILE=$(state | jq -r '.currentFile // ""')
omarchy-shell shell call "$PLUGIN_ID" captureAreaAt "$X,$Y 96x96" >/dev/null
for _ in {1..50}; do
  candidate=$(state | jq -r '.currentFile // ""')
  if [[ $candidate != "$OLD_FILE" && $candidate == "$STATE_DIR/tmp/"*.png ]]; then
    TEMP_SHOT=$candidate
    EDITOR_PID=$(editor_pid_for "$TEMP_SHOT")
  fi
  [[ -n $EDITOR_PID ]] && editor_mapped && break
  sleep 0.2
done
[[ -n $EDITOR_PID && -f $TEMP_SHOT ]] || { echo 'automatic annotation did not open a temporary shot' >&2; exit 1; }
[[ $(state | jq -r '.opened') == false ]] || { echo 'automatic annotation opened the card over Omasnap' >&2; exit 1; }
echo 'PASS: automatic annotation opens a retained temporary shot without a card'
