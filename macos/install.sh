#!/bin/zsh
# Claude Code — Steroids Mode :: macOS installer
# Installs two Finder Quick Actions: "Open in Claude" and "Open in Claude — Steroids (9×)".
set -e

SCRIPT_DIR="${0:A:h}"
DEST="$HOME/.local/share/claude-code-steroids"
SERVICES="$HOME/Library/Services"

echo "Installing Claude Code — Steroids Mode (macOS)…"

mkdir -p "$DEST" "$SERVICES"

# 1) Grid helper script
cp "$SCRIPT_DIR/scripts/steroids-grid.sh" "$DEST/"
chmod +x "$DEST/steroids-grid.sh"

# 2) Finder Quick Actions
rm -rf "$SERVICES/Open in Claude.workflow" "$SERVICES/Open in Claude Steroids.workflow"
cp -R "$SCRIPT_DIR/quick-actions/Open in Claude.workflow" "$SERVICES/"
cp -R "$SCRIPT_DIR/quick-actions/Open in Claude Steroids.workflow" "$SERVICES/"

# 3) Refresh the Services registry so the items appear immediately
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

cat <<'DONE'

✅ Installed.

How to use:
  • Right-click any folder in Finder → Quick Actions →
        "Open in Claude"                 (one session)
        "Open in Claude — Steroids (9×)" (nine sessions, 3×3 grid)

First run notes:
  • macOS will ask once for "Automation" permission (Terminal). Click OK.
  • If the menu items don't show up yet, log out/in or relaunch Finder
    (hold Option, right-click the Finder Dock icon → Relaunch).

Requires: Claude Code CLI on your PATH  →  https://claude.com/claude-code
DONE
