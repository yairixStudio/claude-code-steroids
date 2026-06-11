#!/bin/zsh
# Claude Code — Steroids Mode :: macOS installer
# Installs two Finder Quick Actions: "Open in Claude" and "Open in Claude — Steroids (9×)".
set -e

SCRIPT_DIR="${0:A:h}"
DEST="$HOME/.local/share/claude-code-steroids"
SERVICES="$HOME/Library/Services"

echo "Installing Claude Code — Steroids Mode (macOS)…"

mkdir -p "$DEST" "$SERVICES"

# 1) Helper scripts
cp "$SCRIPT_DIR/scripts/steroids-grid.sh" "$DEST/"
cp "$SCRIPT_DIR/scripts/arrange-terminals.sh" "$DEST/"
cp "$SCRIPT_DIR/scripts/claude-session.sh" "$DEST/"
chmod +x "$DEST/steroids-grid.sh" "$DEST/arrange-terminals.sh" "$DEST/claude-session.sh"

# 2) Quick Actions: two Finder ones + a no-input "Arrange Terminals" service
#    that can be triggered from any app via a global keyboard shortcut.
rm -rf "$SERVICES/Open in Claude.workflow" "$SERVICES/Open in Claude Steroids.workflow" \
       "$SERVICES/Arrange Terminals.workflow"
cp -R "$SCRIPT_DIR/quick-actions/Open in Claude.workflow" "$SERVICES/"
cp -R "$SCRIPT_DIR/quick-actions/Open in Claude Steroids.workflow" "$SERVICES/"
cp -R "$SCRIPT_DIR/quick-actions/Arrange Terminals.workflow" "$SERVICES/"

# 2b) Make sure "Arrange Terminals" shows in the Services menu, with NO key
#     binding there — Services shortcuts lose to the frontmost app's own
#     shortcuts. The real hotkey is the daemon below (2c).
defaults write pbs NSServicesStatus -dict-add \
  '"(null) - Arrange Terminals - runWorkflowAsService"' \
  '{ "enabled_context_menu" = 1; "enabled_services_menu" = 1; }'

# 2c) Menu bar app + global hotkeys (⌃⌥C / ⌃⌥S / ⌃⌥T) — one lean compiled
#     binary using NSStatusItem + RegisterEventHotKey, started at login as a
#     LaunchAgent.
if command -v swiftc >/dev/null 2>&1; then
  echo "Compiling menu bar app (⌃⌥C session / ⌃⌥S steroids / ⌃⌥T arrange)…"
  swiftc -O "$SCRIPT_DIR/scripts/steroids-menubar.swift" -o "$DEST/steroids-menubar"
  AGENT="$HOME/Library/LaunchAgents/com.yairixstudio.claude-steroids.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>              <string>com.yairixstudio.claude-steroids</string>
	<key>ProgramArguments</key>   <array><string>$DEST/steroids-menubar</string></array>
	<key>RunAtLoad</key>          <true/>
	<key>KeepAlive</key>          <dict><key>SuccessfulExit</key><false/></dict>
	<key>LimitLoadToSessionType</key> <string>Aqua</string>
	<key>StandardOutPath</key>    <string>/tmp/claude-steroids-menubar.log</string>
	<key>StandardErrorPath</key>  <string>/tmp/claude-steroids-menubar.log</string>
</dict>
</plist>
PLIST
  # Retire the older single-hotkey daemon, if present
  launchctl bootout "gui/$UID/com.yairixstudio.arrange-hotkey" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/com.yairixstudio.arrange-hotkey.plist" "$DEST/arrange-hotkey"
  launchctl bootout "gui/$UID/com.yairixstudio.claude-steroids" 2>/dev/null || true
  launchctl bootstrap "gui/$UID" "$AGENT"
else
  echo "⚠️  swiftc not found — skipping the menu bar app and hotkeys."
  echo "    Install Xcode Command Line Tools (xcode-select --install) and re-run."
fi

# 3) Refresh the Services registry so the items appear immediately
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

# 4) "Arrange Terminals" Dock button — a tiny app bundle wrapping the script.
#    Click it (Dock / Launchpad / Spotlight) to tile the current desktop's
#    Terminal windows into a grid sized to how many there are.
APPS="$HOME/Applications"
APP="$APPS/Arrange Terminals.app"
mkdir -p "$APPS"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$SCRIPT_DIR/scripts/arrange-terminals.sh" "$APP/Contents/MacOS/arrange-terminals"
chmod +x "$APP/Contents/MacOS/arrange-terminals"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>            <string>Arrange Terminals</string>
	<key>CFBundleIdentifier</key>      <string>com.yairixstudio.arrange-terminals</string>
	<key>CFBundleVersion</key>         <string>1.0</string>
	<key>CFBundleExecutable</key>      <string>arrange-terminals</string>
	<key>CFBundlePackageType</key>     <string>APPL</string>
	<key>LSUIElement</key>             <true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>Arrange Terminals moves and resizes Terminal windows into a grid.</string>
</dict>
</plist>
PLIST
# Make Launchpad/Spotlight notice the new app right away
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

cat <<'DONE'

✅ Installed.

How to use:
  • Right-click any folder in Finder → Quick Actions →
        "Open in Claude"                 (one session)
        "Open in Claude — Steroids (9×)" (nine sessions, 3×3 grid)
  • Menu bar: a small grid icon (⊞) next to the clock with the three actions.
    It starts automatically at every login.
  • Global hotkeys (work from any app, either Option/Control key):
        ⌃⌥C  New Claude Session       (one window, in ~)
        ⌃⌥S  Steroids Mode (9× grid)  (nine sessions, in ~)
        ⌃⌥T  Arrange Terminals        (grid: 4 → 2×2, 9 → 3×3, 10 → 4×3 …)
    (To change a combo, edit macos/scripts/steroids-menubar.swift and re-run
     this installer.)
  • Optional Dock button: drag "Arrange Terminals" from ~/Applications.

First run notes:
  • macOS will ask once for "Automation" permission (Terminal). Click OK.
  • If the menu items or the shortcut don't work yet, log out/in or relaunch
    Finder (hold Option, right-click the Finder Dock icon → Relaunch).

Requires: Claude Code CLI on your PATH  →  https://claude.com/claude-code
DONE
