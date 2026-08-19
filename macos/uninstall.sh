#!/bin/zsh
# Claude Code — Steroids Mode :: macOS uninstaller
set -e

SERVICES="$HOME/Library/Services"

echo "Removing Claude Code — Steroids Mode (macOS)…"
launchctl bootout "gui/$UID/com.yairixstudio.arrange-hotkey" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.yairixstudio.arrange-hotkey.plist"
launchctl bootout "gui/$UID/com.yairixstudio.claude-steroids" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.yairixstudio.claude-steroids.plist"
rm -rf "$SERVICES/Open in Claude.workflow"
rm -rf "$SERVICES/Open in Claude Steroids.workflow"
rm -rf "$SERVICES/Arrange Terminals.workflow"
rm -rf "$HOME/.local/share/claude-code-steroids"
rm -rf "$HOME/Applications/Arrange Terminals.app"
rm -rf "$HOME/Applications/Claude Steroids.app"
# Drop every permission grant the app accumulated (Automation → Terminal, …)
/usr/bin/tccutil reset All com.yairixstudio.claude-steroids 2>/dev/null || true
/usr/libexec/PlistBuddy -c \
  'Delete :NSServicesStatus:(null) - Arrange Terminals - runWorkflowAsService' \
  "$HOME/Library/Preferences/pbs.plist" 2>/dev/null || true
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo "✅ Uninstalled."
