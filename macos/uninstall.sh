#!/bin/zsh
# Claude Code — Steroids Mode :: macOS uninstaller
set -e

SERVICES="$HOME/Library/Services"

echo "Removing Claude Code — Steroids Mode (macOS)…"
rm -rf "$SERVICES/Open in Claude.workflow"
rm -rf "$SERVICES/Open in Claude Steroids.workflow"
rm -rf "$HOME/.local/share/claude-code-steroids"
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo "✅ Uninstalled."
