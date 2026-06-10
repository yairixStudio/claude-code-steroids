#!/bin/zsh
# Claude Code — Steroids Mode (macOS)
# Opens 9 Claude Code sessions in a 3x3 grid, all inside the given directory.
# Each session runs: claude --dangerously-skip-permissions
#
# Usage: steroids-grid.sh <directory>   (defaults to $HOME)

DIR="${1:-$HOME}"

# Logical screen size via NSScreen — needs NO Automation permission (unlike Finder),
# so it works reliably from a Finder Quick Action's restricted context.
SIZE="$(/usr/bin/osascript -l JavaScript -e 'ObjC.import("AppKit"); var f=$.NSScreen.mainScreen.frame; Math.round(f.size.width)+" "+Math.round(f.size.height)' 2>/dev/null)"
SCW="${SIZE%% *}"
SCH="${SIZE##* }"
[ -z "$SCW" ] && SCW=1512   # sensible fallback
[ -z "$SCH" ] && SCH=982

# Values are baked into the AppleScript (no argv) — this is what works under the
# Quick Action sandbox.
/usr/bin/osascript <<APPLESCRIPT
set claudeCmd to "cd '$DIR' && claude --dangerously-skip-permissions"
set scW to $SCW
set scH to $SCH
set topMargin to 38 -- room for the menu bar / notch
set winW to scW / 3
set winH to (scH - topMargin) / 3
tell application "Terminal"
	activate
	repeat with idx from 0 to 8
		set col to idx mod 3
		set rw to idx div 3
		set x1 to (col * winW) as integer
		set y1 to (topMargin + rw * winH) as integer
		do script claudeCmd
		delay 0.35
		try
			set bounds of front window to {x1, y1, (x1 + winW) as integer, (y1 + winH) as integer}
		end try
	end repeat
end tell
APPLESCRIPT
