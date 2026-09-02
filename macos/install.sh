#!/bin/zsh
# Claude Code — Steroids Mode :: macOS installer
# Installs two Finder Quick Actions: "Open in Claude" and "Open in Claude — Steroids (9×)".
set -e

SCRIPT_DIR="${0:A:h}"
DEST="$HOME/.local/share/claude-code-steroids"
SERVICES="$HOME/Library/Services"
CONFIG_DIR="$HOME/.config/claude-code-steroids"
CONFIG="$CONFIG_DIR/config.json"

echo "Installing Claude Code — Steroids Mode (macOS)…"

mkdir -p "$DEST" "$SERVICES"

# 1) Helper scripts
cp "$SCRIPT_DIR/scripts/steroids-config.sh" "$DEST/"
cp "$SCRIPT_DIR/scripts/steroids-grid.sh" "$DEST/"
cp "$SCRIPT_DIR/scripts/arrange-terminals.sh" "$DEST/"
cp "$SCRIPT_DIR/scripts/claude-session.sh" "$DEST/"
cp "$SCRIPT_DIR/scripts/close-terminals.sh" "$DEST/"
chmod +x "$DEST/steroids-config.sh" "$DEST/steroids-grid.sh" "$DEST/arrange-terminals.sh" \
         "$DEST/claude-session.sh" "$DEST/close-terminals.sh"

# 1b) Settings. Seeded only when absent, so re-running the installer to pick up
#     a new version never resets the agent you chose.
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG" ]; then
  cat > "$CONFIG" <<'JSON'
{
  "version" : 1,
  "agent" : "claude",
  "columns" : 3,
  "rows" : 3,
  "yolo" : true,
  "paths" : {
  }
}
JSON
fi

# 2) Quick Actions. Six Finder ones — a neutral pair that follows whichever
#    agent Settings names, plus a pinned pair per agent so a right-click can
#    send one folder to Claude and the next to Codex without going through
#    Settings — and a no-input "Arrange Terminals" service that can be triggered
#    from any app.
#
#    Installed by enumerating the folder rather than by name: adding a Quick
#    Action should be dropping a bundle into quick-actions/, not editing three
#    lists that can disagree with each other.
for wf in "$SCRIPT_DIR/quick-actions/"*.workflow; do
  rm -rf "$SERVICES/${wf:t}"
  cp -R "$wf" "$SERVICES/"
done

# Retire the names this project shipped before 2.0. Left in place they show up
# as a second, stale set of items in the same right-click menu, still running
# whatever the version that installed them baked in.
rm -rf "$SERVICES/Launch Claude.workflow" "$SERVICES/Launch Claude Steroids.workflow"

# 2b) Switch every one of them on explicitly.
#
#     A workflow sitting in ~/Library/Services is not the same thing as a menu
#     item: macOS keeps a separate on/off switch per service in pbs.plist
#     (System Settings ▸ Extensions ▸ Finder), and a service with no entry there
#     is at the mercy of whatever macOS decides the default is — which is how
#     "Open in Claude" came to be installed, valid, and completely invisible for
#     anyone whose switch defaulted off. Only "Arrange Terminals" used to be
#     registered here, which is exactly why it was the only one that reappeared.
#
#     The switch is keyed by the service's MENU ITEM name, not by the bundle
#     filename — for the grids those differ ("Open in Codex Steroids.workflow"
#     presents itself as "Open in Codex — Steroids (9×)"), and a switch written
#     under the filename is a row that controls nothing. Read the name back out
#     of each bundle so the two can never drift apart.
#
#     No key binding in these entries: a Services shortcut loses to the
#     frontmost app's own shortcuts, so the real hotkeys are the menu bar app's
#     (2c).
#     Driven by quick-actions/, never by what happens to be in ~/Library/
#     Services — flipping switches on somebody else's Quick Action is not this
#     installer's business.
for wf in "$SCRIPT_DIR/quick-actions/"*.workflow; do
  svc="$(/usr/libexec/PlistBuddy -c 'Print :NSServices:0:NSMenuItem:default' \
         "$SERVICES/${wf:t}/Contents/Info.plist" 2>/dev/null)"
  [ -z "$svc" ] && continue
  defaults write pbs NSServicesStatus -dict-add \
    "\"(null) - $svc - runWorkflowAsService\"" \
    '{ "enabled_context_menu" = 1; "enabled_services_menu" = 1; }'
done

#     Switches for the names this project shipped before 2.0. Their workflows
#     were removed above, so these rows now control nothing — they just sit in
#     the Extensions list looking like features.
for svc in "Launch Claude" "Launch Claude Steroids" "Open in Claude Steroids"; do
  /usr/libexec/PlistBuddy -c \
    "Delete :NSServicesStatus:'(null) - $svc - runWorkflowAsService'" \
    "$HOME/Library/Preferences/pbs.plist" 2>/dev/null || true
done

# 2c) Menu bar app + global hotkeys (⌃⌥C / ⌃⌥S / ⌃⌥T) — NSStatusItem +
#     RegisterEventHotKey, compiled into a real app bundle ("Claude
#     Steroids.app") and started at login as a LaunchAgent. The bundle matters:
#     permission prompts show the app's name instead of a raw binary path, and
#     TCC keys grants to the stable bundle ID — which is what lets the app's
#     own "Permissions" menu revoke or re-request them with tccutil.
if command -v swiftc >/dev/null 2>&1; then
  echo "Compiling menu bar app (⌃⌥C session / ⌃⌥S steroids / ⌃⌥T arrange)…"
  BUNDLE_ID="com.yairixstudio.claude-steroids"
  APPS="$HOME/Applications"
  APP_BUNDLE="$APPS/Claude Steroids.app"
  mkdir -p "$APPS"
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_BUNDLE/Contents/MacOS"
  swiftc -O "$SCRIPT_DIR/scripts/steroids-menubar.swift" \
         -o "$APP_BUNDLE/Contents/MacOS/steroids-menubar"
  cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>            <string>Claude Steroids</string>
	<key>CFBundleDisplayName</key>     <string>Claude Steroids</string>
	<key>CFBundleIdentifier</key>      <string>com.yairixstudio.claude-steroids</string>
	<key>CFBundleVersion</key>         <string>2.2</string>
	<key>CFBundleShortVersionString</key> <string>2.2</string>
	<key>CFBundleExecutable</key>      <string>steroids-menubar</string>
	<key>CFBundlePackageType</key>     <string>APPL</string>
	<key>LSUIElement</key>             <true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>Claude Steroids opens, arranges, and closes the Terminal windows that run your Claude Code sessions.</string>
</dict>
</plist>
PLIST
  # Ad-hoc signature so TCC identifies the app by bundle ID, not binary path —
  # grants survive rebuilds and `tccutil reset … $BUNDLE_ID` can target them.
  codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE" 2>/dev/null || true

  AGENT="$HOME/Library/LaunchAgents/com.yairixstudio.claude-steroids.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>              <string>com.yairixstudio.claude-steroids</string>
	<key>ProgramArguments</key>   <array><string>$APP_BUNDLE/Contents/MacOS/steroids-menubar</string></array>
	<key>RunAtLoad</key>          <true/>
	<key>KeepAlive</key>          <dict><key>SuccessfulExit</key><false/></dict>
	<key>LimitLoadToSessionType</key> <string>Aqua</string>
	<key>StandardOutPath</key>    <string>/tmp/claude-steroids-menubar.log</string>
	<key>StandardErrorPath</key>  <string>/tmp/claude-steroids-menubar.log</string>
</dict>
</plist>
PLIST
  # Retire the older single-hotkey daemon and the pre-bundle bare binary
  launchctl bootout "gui/$UID/com.yairixstudio.arrange-hotkey" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/com.yairixstudio.arrange-hotkey.plist" "$DEST/arrange-hotkey"
  launchctl bootout "gui/$UID/com.yairixstudio.claude-steroids" 2>/dev/null || true
  rm -f "$DEST/steroids-menubar"

  # bootout returns before launchd has finished retiring the service, and
  # bootstrapping a label that is still on its way out fails with "5:
  # Input/output error" — which, under set -e, used to abort the installer here
  # and skip everything after it. Wait for the label to actually go, then retry
  # a few times before giving up.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    launchctl print "gui/$UID/com.yairixstudio.claude-steroids" >/dev/null 2>&1 || break
    sleep 0.3
  done
  for _ in 1 2 3 4 5; do
    launchctl bootstrap "gui/$UID" "$AGENT" 2>/dev/null && break
    sleep 0.5
  done
  if ! launchctl print "gui/$UID/com.yairixstudio.claude-steroids" >/dev/null 2>&1; then
    echo "⚠️  Could not start the menu bar app via launchd — starting it directly."
    echo "    It will start normally at your next login."
    open -a "$APP_BUNDLE" 2>/dev/null || true
  fi
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
        "Open in Claude — Steroids (9×)" (a grid of sessions)
  • Menu bar: a small grid icon (⊞) next to the clock. Per agent it offers
    "New Session" and a "Steroids Mode ▸" submenu — pick 2×2, 3×2, 3×3, 4×3
    or 4×4 and that grid opens right away, whatever Settings says. The agent
    selected in Settings is listed first, and its default grid wears a ✓.
    Starts automatically at every login.
  • Global hotkeys (work from any app, either Option/Control key):
        ⌃⌥C  New Session          (one window, in ~)
        ⌃⌥S  Steroids Mode        (a grid of sessions, in ~)
        ⌃⌥T  Arrange Terminals    (grid: 4 → 2×2, 9 → 3×3, 10 → 4×3 …)
    (To change a combo, edit macos/scripts/steroids-menubar.swift and re-run
     this installer.)
  • Optional Dock button: drag "Arrange Terminals" from ~/Applications.

Settings — menu bar icon → Settings… (three things, saved as you click):
  • Agent      Claude Code or OpenAI Codex. Every entry point above — hotkeys,
               menu, Finder right-click — runs whichever one is selected, and
               the window shows a live ✓ with the path it resolved to.
  • Grid       2×2 through 4×4 (the config file accepts anything up to 8×8).
  • Autonomy   Skip approval prompts, on or off. Off passes no flag at all, so
               each CLI behaves exactly as it does when you run it yourself.
  Stored in ~/.config/claude-code-steroids/config.json — reinstalling keeps it.

Permissions:
  • Nothing is requested at install or launch. The first time an action runs,
    macOS asks once for Automation → Terminal ("Claude Steroids wants to
    control Terminal"). Click Allow — that's the only permission it needs.
  • Menu bar icon → Permissions shows a live ✓ for that grant and lets you
    revoke/re-request it, open Privacy & Security, or reset all grants.

First run notes:
  • If the menu items or the shortcut don't work yet, log out/in or relaunch
    Finder (hold Option, right-click the Finder Dock icon → Relaunch).

Requires one of:
  Claude Code   https://claude.com/claude-code    (npm i -g @anthropic-ai/claude-code)
  OpenAI Codex  https://developers.openai.com/codex  (npm i -g @openai/codex)
DONE
