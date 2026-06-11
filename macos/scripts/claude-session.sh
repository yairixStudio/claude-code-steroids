#!/bin/zsh
# Claude Code — Steroids Mode (macOS)
# Opens ONE new Terminal window running Claude Code in the given directory.
#
# Usage: claude-session.sh <directory>   (defaults to $HOME)

DIR="${1:-$HOME}"

/usr/bin/osascript <<APPLESCRIPT
tell application "Terminal"
	activate
	do script "cd '$DIR' && claude --dangerously-skip-permissions"
end tell
APPLESCRIPT
