#!/bin/bash
# Launches the built app on the CI Mac, drives it with keystrokes, and screenshots each step into shots/.
# Fails if the app is no longer running at the end, if typing reaches the page while the calendar is up, or if the
# time goal isn't reached and logged with the calendar open. The rest is for a person (or Claude) to judge from the screenshots.
set -u
APP="$1"
mkdir -p shots
step=0
shot() { step=$((step + 1)); sleep "${2:-1.5}"; screencapture -x "shots/$(printf %02d $step)-$1.png" || echo "screencapture failed"; }
keys() { osascript -e "tell application \"System Events\" to keystroke \"$1\"" || echo "keystroke failed: $1"; }
key() { osascript -e "tell application \"System Events\" to key code $1" || echo "key code failed: $1"; }
combo() { osascript -e "tell application \"System Events\" to keystroke \"$1\" using {$2}" || echo "combo failed: $1"; }

swift .github/scripts/seed.swift "$HOME/Pages"
defaults read com.mtple.GoodMorning | grep -v journalFolderBookmark | head -20
open --stdout app.log --stderr app.log "$APP"
shot first-launch 4
# Choose a Folder… is the default button. In the picker, ⇧⌘G takes a path.
key 36
sleep 2
osascript -e 'tell application "System Events" to keystroke "g" using {command down, shift down}' || echo "go-to-folder failed"
sleep 1
keys "$HOME/Pages"
key 36
sleep 1.5
shot folder-picker 0.5
key 36
shot launched-locked 5
keys "Typing a new line at the end to see where the caret settles. "
key 36; key 36
keys "Another paragraph, still typing, and the line should hold its place on the screen as the page moves up. "
shot after-typing
combo "=" "command down"; combo "=" "command down"
shot bigger-text
combo "-" "command down"; combo "-" "command down"; combo "-" "command down"
shot smaller-text
combo "0" "command down"
combo "p" "command down"
shot palette
key 125; key 125
shot palette-arrowed 0.5
key 126; key 126; key 126
shot palette-wrapped 0.5
key 53
combo "s" "command down"
shot saved 0.4
combo "l" "command down"
shot unlocked 2
keys "Typing while not locked in, and none of it should go missing. "
shot not-locked-banner
key 53
shot banner-dismissed 0.8
combo "l" "command down"
shot locked-again 2
# The calendar (⌘Y), left open while the two-minute time goal passes. Today should go from a ring to filled, and
# the counted total should go up by one, without closing the card or changing month.
failed=0
log="$HOME/Pages/.good-morning.json"
today=$(date +%F)
completed() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], {}).get("completed", False))' "$log" "$today" 2>/dev/null; }
combo "y" "command down"
shot calendar-open
# Typing while the card is up must not reach the page.
keys "calendarleak "
shot calendar-typing 0.5
for _ in $(seq 1 36); do
  [ "$(completed)" = True ] && break
  sleep 5
done
if [ "$(completed)" = True ]; then
  echo "time goal logged as complete"
else
  echo "::error::The time goal wasn't logged as complete within three minutes of opening the calendar"
  failed=1
fi
shot calendar-time-goal 2
# Step out of full screen so the clock stops and nothing else redraws the card, then change the word goal from
# outside the app, as Settings would. The earlier 600-word page should fill at 550 and go back to a ring after.
key 53
key 53
shot stepped-out 2
combo "y" "command down"
shot calendar-paused
goal=$(defaults read com.mtple.GoodMorning wordGoal)
defaults write com.mtple.GoodMorning wordGoal -int 550
shot calendar-goal-550 2
defaults write com.mtple.GoodMorning wordGoal -int "$goal"
shot calendar-goal-restored 2
key 53
combo "s" "command down"
shot calendar-closed 1
ls shots
echo "--- pages folder"; ls -la "$HOME/Pages"
echo "--- end of today's page"; cat "$HOME/Pages"/2*.md | tail -c 400; echo
echo "--- app log"; tail -40 app.log
echo "--- time log"; cat "$log"; echo
if grep -q calendarleak "$HOME/Pages/$today.md"; then
  echo "::error::Typing reached the page while the calendar was up"
  failed=1
fi
pgrep -x GoodMorning > /dev/null || { echo "::error::Good Morning quit or crashed during the smoke run"; exit 1; }
exit $failed
