// Claude Code — Steroids Mode (macOS)
// Lean menu bar app: a small grid icon next to the clock/volume with three
// actions, each also bound to a TRUE global hotkey (Carbon RegisterEventHotKey,
// which beats the frontmost app's own shortcuts and needs no Accessibility):
//
//   ⌃⌥C  New Claude Session        (one Terminal window, YOLO mode, in ~)
//   ⌃⌥S  Steroids Mode (9× grid)   (nine sessions tiled 3×3, in ~)
//   ⌃⌥T  Arrange Terminals         (retile current desktop's windows)
//
// Side-agnostic: macOS normalizes left/right modifiers for hotkey matching,
// so one registration covers both Option (and Control) keys. Do NOT register
// per-side variants — they all match the same press and fire multiple times.
//
// Compiled and installed as a login LaunchAgent by install.sh.
// To change a combo: edit the `combos` table and re-run install.sh.
// Key codes: T=0x11 C=0x08 S=0x01 G=0x05 R=0x0F …

import AppKit
import Carbon

let scriptsDir = NSString(
    string: "~/.local/share/claude-code-steroids"
).expandingTildeInPath

func runScript(_ name: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["\(scriptsDir)/\(name)"]
    try? task.run()
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

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
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: ""))
        item.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = [.control, .option]
        it.target = self
        return it
    }

    @objc func newSession() { runScript("claude-session.sh") }
    @objc func steroids()   { runScript("steroids-grid.sh") }
    @objc func arrange()    { runScript("arrange-terminals.sh") }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar icon only — no Dock icon
app.run()
