#!/bin/zsh
# steroids-grid.sh [<directory>] [--agent claude|codex]
# Opens a grid of agent sessions — Claude Code or OpenAI Codex, whichever is
# selected in Settings — all running inside the given directory. The grid is
# 3x3 by default; Settings can make it anything from 1x1 to 8x8.
# Defaults to $HOME if no directory is given. --agent pins one agent for this
# run, which is what the per-agent Quick Actions pass; grid size and the
# autonomy toggle always come from Settings.
#
# Mirrors the working "Launch Claude" Quick Action: the AppleScript is built with
# the values baked in (no argv / stdin-args), which is what works under the
# restricted Quick Action context.

# A half-finished install used to fail silently here: with the helper missing,
# every value below stayed empty and the script went on to hand Terminal an
# AppleScript full of holes. Nothing launched from a hotkey or a Quick Action
# has a console to complain to, so say it in the only place that is visible.
if ! source "${0:A:h}/steroids-config.sh" 2>/dev/null; then
	/usr/bin/osascript -e 'display alert "Claude Code — Steroids" message "steroids-config.sh is missing. Re-run macos/install.sh to repair the installation." as critical' 2>/dev/null
	exit 1
fi
steroids_parse_args "$@"
steroids_load_config "$STEROIDS_AGENT_OVERRIDE"

DIR="$STEROIDS_DIR"

# Visible screen area via NSScreen — excludes the menu bar/notch AND the Dock
# (whatever side it's on), and needs NO automation permission (unlike Finder).
# Emits: originX topInset width height (top inset converted from AppKit's
# bottom-up y-axis to window-bounds' top-down axis).
GEOM="$(/usr/bin/osascript -l JavaScript -e 'ObjC.import("AppKit"); var s=$.NSScreen.mainScreen, f=s.frame, v=s.visibleFrame; Math.round(v.origin.x)+" "+Math.round(f.size.height-(v.origin.y+v.size.height))+" "+Math.round(v.size.width)+" "+Math.round(v.size.height)' 2>/dev/null)"
read -r GX GY GW GH <<< "$GEOM"
[ -z "$GH" ] && { GX=0; GY=33; GW=1512; GH=887; }

# exec so the pane belongs to the agent itself: closing a swarm matches on the
# session's processes, and a wrapper shell would hide the agent behind it.
CMD="$(steroids_applescript_quote "cd $(steroids_shell_quote "$DIR") && exec $STEROIDS_CMD")"
LAST=$(( STEROIDS_COLS * STEROIDS_ROWS - 1 ))

# Windows are created BEFORE activating Terminal: new windows always appear on
# the currently active Space, whereas activating first can switch macOS to a
# Space that already has Terminal windows and dump the grid there.
/usr/bin/osascript <<APPLESCRIPT
set agentCmd to $CMD
set gX to $GX
set gY to $GY
set winW to $GW / $STEROIDS_COLS
set winH to $GH / $STEROIDS_ROWS
tell application "Terminal"
	repeat with idx from 0 to $LAST
		set col to idx mod $STEROIDS_COLS
		set rw to idx div $STEROIDS_COLS
		set x1 to (gX + col * winW) as integer
		set y1 to (gY + rw * winH) as integer
		do script agentCmd
		delay 0.35
		try
			set bounds of front window to {x1, y1, (x1 + winW) as integer, (y1 + winH) as integer}
		end try
	end repeat
	activate
end tell
APPLESCRIPT
