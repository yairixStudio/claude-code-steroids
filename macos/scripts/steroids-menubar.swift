// Claude Code — Steroids Mode (macOS)
// Lean menu bar app: a small grid icon next to the clock/volume with three
// actions, each also bound to a TRUE global hotkey (Carbon RegisterEventHotKey,
// which beats the frontmost app's own shortcuts and needs no Accessibility):
//
//   ⌃⌥C  New Claude Session        (one Terminal window, YOLO mode, in ~)
//   ⌃⌥S  Steroids Mode (9× grid)   (nine sessions tiled 3×3, in ~)
//   ⌃⌥T  Arrange Terminals         (retile current desktop's windows)
//
// Permissions policy: the app requests NOTHING at launch. The one permission
// it needs — Automation → Terminal — is requested by macOS the first time an
// action actually runs. The "Permissions" submenu shows a live ✓ for it and
// lets you revoke (tccutil) or re-request it, jump to the Privacy & Security
// pane, or reset every grant this app holds.
//
// Side-agnostic: macOS normalizes left/right modifiers for hotkey matching,
// so one registration covers both Option (and Control) keys. Do NOT register
// per-side variants — they all match the same press and fire multiple times.
//
// Compiled into "Claude Steroids.app" and installed as a login LaunchAgent by
// install.sh. The bundle (stable bundle ID + ad-hoc signature) is what makes
// macOS show a real app name in permission prompts and lets tccutil target
// our grants by ID instead of by binary path.
// To change a combo: edit the `combos` table and re-run install.sh.
// Key codes: T=0x11 C=0x08 S=0x01 G=0x05 R=0x0F …

import AppKit
import ApplicationServices
import Carbon

let scriptsDir = NSString(
    string: "~/.local/share/claude-code-steroids"
).expandingTildeInPath

let appBundleID = Bundle.main.bundleIdentifier ?? "com.yairixstudio.claude-steroids"
let terminalBundleID = "com.apple.Terminal"

func runScript(_ name: String, _ args: [String] = []) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["\(scriptsDir)/\(name)"] + args
    try? task.run()
}

@discardableResult
func runTool(_ path: String, _ args: [String]) -> Int32 {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = args
    do { try task.run() } catch { return -1 }
    task.waitUntilExit()
    return task.terminationStatus
}

// Automation → Terminal status, via the same API macOS itself consults.
// noErr = granted. AEDeterminePermission can only answer for a RUNNING
// target, hence errProcNotFound when Terminal is closed.
let errNotPermitted: OSStatus = -1743   // user denied; macOS never re-prompts
let errConsentNeeded: OSStatus = -1744  // never asked; ask=true triggers prompt
let errProcNotFound: OSStatus = -600    // Terminal not running — can't tell

func terminalAutomationStatus(askIfNeeded: Bool = false) -> OSStatus {
    var addr = AEAddressDesc()
    let bytes = Array(terminalBundleID.utf8)
    let made = bytes.withUnsafeBufferPointer {
        AECreateDesc(typeApplicationBundleID, $0.baseAddress, $0.count, &addr)
    }
    guard made == 0 else { return OSStatus(made) }
    defer { AEDisposeDesc(&addr) }
    return AEDeterminePermissionToAutomateTarget(
        &addr, AEEventClass(typeWildCard), AEEventID(typeWildCard), askIfNeeded)
}

func handleHotKey(_ id: UInt32) {
    switch id {
    case 1: runScript("arrange-terminals.sh")
    case 2: runScript("claude-session.sh")
    case 3: runScript("steroids-grid.sh")
    default: break
    }
}

var eventType = EventTypeSpec(
    eventClass: OSType(kEventClassKeyboard),
    eventKind: UInt32(kEventHotKeyPressed)
)
InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
    var hk = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &hk)
    handleHotKey(hk.id)
    return noErr
}, 1, &eventType, nil, nil)

let combos: [(keyCode: UInt32, id: UInt32)] = [
    (UInt32(kVK_ANSI_T), 1), // ⌃⌥T arrange grid
    (UInt32(kVK_ANSI_C), 2), // ⌃⌥C new session
    (UInt32(kVK_ANSI_S), 3), // ⌃⌥S steroids 9×
]
var hotKeyRefs = [EventHotKeyRef?](repeating: nil, count: combos.count)
for (i, combo) in combos.enumerated() {
    RegisterEventHotKey(combo.keyCode, UInt32(controlKey | optionKey),
                        EventHotKeyID(signature: OSType(0x4152_5447), id: combo.id),
                        GetApplicationEventTarget(), 0, &hotKeyRefs[i])
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    let permMenu = NSMenu()
    let autoItem = NSMenuItem()

    func applicationDidFinishLaunching(_ note: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "square.grid.3x3",
                                 accessibilityDescription: "Claude Steroids") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "⊞"
            }
        }
        let menu = NSMenu()
        menu.addItem(makeItem("New Claude Session", #selector(newSession), "c"))
        menu.addItem(makeItem("Steroids Mode (9× Grid)", #selector(steroids), "s"))
        menu.addItem(makeItem("Arrange Terminals", #selector(arrange), "t"))
        menu.addItem(.separator())

        // "Permissions" submenu — live ✓ per grant, refreshed every open.
        permMenu.delegate = self
        autoItem.title = "Automation — Control Terminal"
        autoItem.action = #selector(toggleAutomation)
        autoItem.target = self
        permMenu.addItem(autoItem)
        permMenu.addItem(.separator())
        permMenu.addItem(makePlain("Open Privacy & Security Settings…",
                                   #selector(openPrivacySettings)))
        permMenu.addItem(makePlain("Reset All Permissions of This App",
                                   #selector(resetAllPermissions)))
        let permItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        menu.setSubmenu(permMenu, for: permItem)
        menu.addItem(permItem)
        menu.addItem(.separator())

        // "Quit" submenu — closes Terminal windows cleanly (processes killed
        // first, so Terminal never shows a confirmation dialog).
        let quitMenu = NSMenu()
        quitMenu.addItem(makeItem("Close Terminals on This Desktop", #selector(closeSpace), ""))
        quitMenu.addItem(makeItem("Close ALL Claude Terminals", #selector(closeClaudeAll), ""))
        quitMenu.addItem(.separator())
        quitMenu.addItem(NSMenuItem(title: "Quit Menu Bar App",
                                    action: #selector(NSApplication.terminate(_:)),
                                    keyEquivalent: ""))
        let quitItem = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "")
        menu.setSubmenu(quitMenu, for: quitItem)
        menu.addItem(quitItem)
        item.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = [.control, .option]
        it.target = self
        return it
    }

    private func makePlain(_ title: String, _ action: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        return it
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === permMenu else { return }
        let st = terminalAutomationStatus()
        autoItem.state = (st == noErr) ? .on : .off
        switch st {
        case noErr:
            autoItem.title = "Automation — Control Terminal"
        case errConsentNeeded:
            autoItem.title = "Automation — Control Terminal  (click to allow)"
        case errNotPermitted:
            autoItem.title = "Automation — Control Terminal  (denied — opens Settings)"
        case errProcNotFound:
            autoItem.title = "Automation — Control Terminal  (launch Terminal to check)"
        default:
            autoItem.title = "Automation — Control Terminal"
        }
    }

    @objc func toggleAutomation() {
        DispatchQueue.global().async {
            var st = terminalAutomationStatus()
            if st == errProcNotFound {
                // The status API needs Terminal alive — start it in the
                // background, then retry briefly.
                let url = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in }
                for _ in 0..<10 {
                    usleep(300_000)
                    st = terminalAutomationStatus()
                    if st != errProcNotFound { break }
                }
            }
            switch st {
            case noErr:
                // ✓ → unchecked: drop the grant; next action re-prompts.
                runTool("/usr/bin/tccutil", ["reset", "AppleEvents", appBundleID])
            case errConsentNeeded:
                _ = terminalAutomationStatus(askIfNeeded: true)
            case errNotPermitted:
                DispatchQueue.main.async { self.openPrivacySettings() }
            default:
                break
            }
        }
    }

    @objc func openPrivacySettings() {
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func resetAllPermissions() {
        DispatchQueue.global().async {
            runTool("/usr/bin/tccutil", ["reset", "All", appBundleID])
        }
    }

    @objc func newSession()    { runScript("claude-session.sh") }
    @objc func steroids()      { runScript("steroids-grid.sh") }
    @objc func arrange()       { runScript("arrange-terminals.sh") }
    @objc func closeSpace()    { runScript("close-terminals.sh", ["space"]) }
    @objc func closeClaudeAll(){ runScript("close-terminals.sh", ["claude"]) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar icon only — no Dock icon
app.run()
