#!/bin/zsh
# Claude Code — Steroids Mode (macOS)
# Opens ONE new Terminal window running the agent selected in Settings —
# Claude Code or OpenAI Codex — in the given directory.
#
# Usage: claude-session.sh [<directory>] [--agent claude|codex]
#        directory defaults to $HOME; --agent pins one agent for this run,
#        which is what the per-agent Quick Actions pass.

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

# Two layers of quoting: the folder goes into a shell command line, and that
# whole command line goes into an AppleScript string literal. See
# steroids-config.sh — without both, a folder named  don't  breaks the script.
CMD="cd $(steroids_shell_quote "$DIR") && $STEROIDS_CMD"

# Window is created BEFORE activating Terminal so it opens on the Space the
# user is currently looking at (activating first can switch Spaces).
/usr/bin/osascript <<APPLESCRIPT
tell application "Terminal"
	do script $(steroids_applescript_quote "$CMD")
	activate
end tell
APPLESCRIPT
