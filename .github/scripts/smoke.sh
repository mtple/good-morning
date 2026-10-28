#!/bin/bash
# Launches the built app on the CI Mac, drives it with keystrokes, and screenshots each step into shots/.
# Not a pass/fail test: the screenshots are for a person (or Claude) to look at.
set -u
APP="$1"
mkdir -p shots
step=0
shot() { step=$((step + 1)); sleep "${2:-1.5}"; screencapture -x "shots/$(printf %02d $step)-$1.png" || echo "screencapture failed"; }
keys() { osascript -e "tell application \"System Events\" to keystroke \"$1\"" || echo "keystroke failed: $1"; }
key() { osascript -e "tell application \"System Events\" to key code $1 ${2:+using {$2}}" || echo "key code failed: $1"; }
combo() { osascript -e "tell application \"System Events\" to keystroke \"$1\" using {$2}" || echo "combo failed: $1"; }

swift .github/scripts/seed.swift "$HOME/Pages"
open "$APP"
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
keys "Typing while not locked in. "
shot not-locked-alert
key 53
combo "l" "command down"
shot locked-again 2
ls shots
cat "$HOME/Pages"/*.md | tail -c 400
