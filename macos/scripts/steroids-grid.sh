#!/bin/zsh
# steroids-grid.sh <directory>
# Opens 9 Claude sessions (claude --dangerously-skip-permissions) in a 3x3 grid,
# all running inside the given directory. Defaults to $HOME if none given.
#
# Mirrors the working "Launch Claude" Quick Action: the AppleScript is built with
# the values baked in (no argv / stdin-args), which is what works under the
# restricted Quick Action context.

DIR="${1:-$HOME}"

# Visible screen area via NSScreen — excludes the menu bar/notch AND the Dock
# (whatever side it's on), and needs NO automation permission (unlike Finder).
# Emits: originX topInset width height (top inset converted from AppKit's
# bottom-up y-axis to window-bounds' top-down axis).
GEOM="$(/usr/bin/osascript -l JavaScript -e 'ObjC.import("AppKit"); var s=$.NSScreen.mainScreen, f=s.frame, v=s.visibleFrame; Math.round(v.origin.x)+" "+Math.round(f.size.height-(v.origin.y+v.size.height))+" "+Math.round(v.size.width)+" "+Math.round(v.size.height)' 2>/dev/null)"
read -r GX GY GW GH <<< "$GEOM"
[ -z "$GH" ] && { GX=0; GY=33; GW=1512; GH=887; }

# Windows are created BEFORE activating Terminal: new windows always appear on
# the currently active Space, whereas activating first can switch macOS to a
# Space that already has Terminal windows and dump the grid there.
/usr/bin/osascript <<APPLESCRIPT
set claudeCmd to "cd '$DIR' && exec /opt/homebrew/bin/claude --dangerously-skip-permissions"
set gX to $GX
set gY to $GY
set winW to $GW / 3
set winH to $GH / 3
tell application "Terminal"
	repeat with idx from 0 to 8
		set col to idx mod 3
		set rw to idx div 3
		set x1 to (gX + col * winW) as integer
		set y1 to (gY + rw * winH) as integer
		do script claudeCmd
		delay 0.35
		try
			set bounds of front window to {x1, y1, (x1 + winW) as integer, (y1 + winH) as integer}
		end try
	end repeat
	activate
end tell
APPLESCRIPT
