#!/bin/zsh
# Claude Code — Steroids Mode (macOS)
# Opens ONE new Terminal window running Claude Code in the given directory.
#
# Usage: claude-session.sh <directory>   (defaults to $HOME)

DIR="${1:-$HOME}"

# Window is created BEFORE activating Terminal so it opens on the Space the
# user is currently looking at (activating first can switch Spaces).
/usr/bin/osascript <<APPLESCRIPT
tell application "Terminal"
	do script "cd '$DIR' && claude --dangerously-skip-permissions"
	activate
end tell
APPLESCRIPT
