#!/bin/zsh
# Claude Code — Steroids Mode :: macOS uninstaller
set -e

SERVICES="$HOME/Library/Services"

echo "Removing Claude Code — Steroids Mode (macOS)…"
launchctl bootout "gui/$UID/com.yairixstudio.arrange-hotkey" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.yairixstudio.arrange-hotkey.plist"
launchctl bootout "gui/$UID/com.yairixstudio.claude-steroids" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.yairixstudio.claude-steroids.plist"
# Every Quick Action this version ships, by enumerating the same folder the
# installer copies from — so a bundle added there is removed here without
# anyone having to remember to update a second list.
for wf in "${0:A:h}/quick-actions/"*.workflow(N); do
  rm -rf "$SERVICES/${wf:t}"
done
# Names this project shipped before 2.0 — an install that predates the rename
# leaves them behind, and they keep answering right-clicks forever.
rm -rf "$SERVICES/Launch Claude.workflow"
rm -rf "$SERVICES/Launch Claude Steroids.workflow"
rm -rf "$HOME/.local/share/claude-code-steroids"
rm -rf "$HOME/.config/claude-code-steroids"
rm -rf "$HOME/Applications/Arrange Terminals.app"
rm -rf "$HOME/Applications/Claude Steroids.app"
# Drop every permission grant the app accumulated (Automation → Terminal, …)
/usr/bin/tccutil reset All com.yairixstudio.claude-steroids 2>/dev/null || true
# Every switch this project ever created in System Settings ▸ Extensions ▸
# Finder, including the pre-2.0 names — a row whose workflow is gone controls
# nothing and only clutters the list.
for svc in "Open Coding Agent Here" "Steroids Mode (9× Grid)" \
           "Open in Claude" "Open in Claude — Steroids (9×)" \
           "Open in Codex"  "Open in Codex — Steroids (9×)" \
           "Arrange Terminals" \
           "Open in Claude Steroids" "Launch Claude" "Launch Claude Steroids"; do
  /usr/libexec/PlistBuddy -c \
    "Delete :NSServicesStatus:'(null) - $svc - runWorkflowAsService'" \
    "$HOME/Library/Preferences/pbs.plist" 2>/dev/null || true
done
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo "✅ Uninstalled."
