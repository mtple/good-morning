#!/bin/bash
# Launches the built app on the CI Mac, drives it with keystrokes, and screenshots each step into shots/.
# Fails only if the app is no longer running at the end. The rest is for a person (or Claude) to judge from the screenshots.
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
# About 20 more words crosses the goal: the progress line glows and the word count lifts.
keys "And now enough words to reach the goal, one after another, until the count goes past it and the page lets go."
shot goal-reached 0.3
shot goal-settled 2.5
ls shots
echo "--- pages folder"; ls -la "$HOME/Pages"
echo "--- end of today's page"; cat "$HOME/Pages"/2*.md | tail -c 400; echo
echo "--- app log"; tail -40 app.log
pgrep -x GoodMorning > /dev/null || { echo "::error::Good Morning quit or crashed during the smoke run"; exit 1; }
