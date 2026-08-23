// Claude Code — Steroids Mode (macOS)
// Lean menu bar app: a small grid icon next to the clock/volume with three
// actions, each also bound to a TRUE global hotkey (Carbon RegisterEventHotKey,
// which beats the frontmost app's own shortcuts and needs no Accessibility):
//
//   ⌃⌥C  New Session          (one Terminal window, in ~)
//   ⌃⌥S  Steroids Mode        (a grid of sessions, in ~)
//   ⌃⌥T  Arrange Terminals    (retile current desktop's windows)
//
// Which agent those sessions run — Claude Code or OpenAI Codex — is a setting,
// not a hardcode. Settings… opens a small window that writes one JSON file:
//
//   ~/.config/claude-code-steroids/config.json
//
// The shell scripts and the Finder Quick Actions read the same file, so one
// switch there changes every entry point at once.
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

// MARK: - Agents

// One entry per supported CLI. Adding a third is this struct plus one line in
// `agents` — the settings window, the menu titles and the scripts all read the
// table rather than naming an agent.
//
// yoloFlag is per-agent because every CLI spells "stop asking me" differently.
// With the toggle OFF we pass no flag at all, so each CLI behaves exactly as it
// does when you run it yourself — no second-guessing its defaults.
struct AgentSpec {
    let id: String
    let label: String
    let bin: String
    let yoloFlag: String
    let installHint: String
}

let agents: [AgentSpec] = [
    AgentSpec(id: "claude", label: "Claude Code", bin: "claude",
              yoloFlag: "--dangerously-skip-permissions",
              installHint: "npm i -g @anthropic-ai/claude-code"),
    AgentSpec(id: "codex", label: "OpenAI Codex", bin: "codex",
              yoloFlag: "--dangerously-bypass-approvals-and-sandbox",
              installHint: "npm i -g @openai/codex"),
]

func agentSpec(_ id: String) -> AgentSpec {
    return agents.first { $0.id == id } ?? agents[0]
}

// MARK: - Config

let configURL = URL(fileURLWithPath: NSString(
    string: "~/.config/claude-code-steroids/config.json"
).expandingTildeInPath)

// Deliberately tiny and deliberately forgiving: every field is optional and
// out-of-range values are clamped, because a config the user hand-edited into
// nonsense must never be the reason a hotkey stops opening a session. The shell
// side (steroids-config.sh) applies the same defaults and the same clamps.
struct Config {
    var agent = "claude"
    var yolo = true
    var columns = 3
    var rows = 3
    var paths: [String: String] = [:]

    static func load() -> Config {
        var c = Config()
        guard let data = try? Data(contentsOf: configURL),
              let raw = try? JSONSerialization.jsonObject(with: data),
              let d = raw as? [String: Any] else { return c }

        if let a = d["agent"] as? String, agents.contains(where: { $0.id == a }) { c.agent = a }
        if let y = d["yolo"] as? Bool { c.yolo = y }
        if let n = d["columns"] as? Int, (1...8).contains(n) { c.columns = n }
        if let n = d["rows"] as? Int, (1...8).contains(n) { c.rows = n }
        if let p = d["paths"] as? [String: String] { c.paths = p }
        return c
    }

    func save() {
        let dict: [String: Any] = [
            "version": 1,
            "agent": agent,
            "yolo": yolo,
            "columns": columns,
            "rows": rows,
            "paths": paths,
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: configURL, options: .atomic)
    }

    var spec: AgentSpec { return agentSpec(agent) }
    var sessionCount: Int { return columns * rows }
    var explicitPath: String { return paths[agent] ?? "" }
}

// Where an agent actually lives. launchd starts this app with a bare PATH that
// has never heard of /opt/homebrew/bin, so asking a LOGIN shell is the only way
// to see the same binaries the user's Terminal sees.
func loginShellWhich(_ bin: String) -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["-lc", "command -v \(bin)"]   // bin comes from the table above, never from user text
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do { try task.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { return nil }
    let path = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return path.isEmpty ? nil : path
}

// MARK: - Running the scripts

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

// MARK: - Automation permission

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

// MARK: - Hotkeys

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
    (UInt32(kVK_ANSI_S), 3), // ⌃⌥S steroids grid
]
var hotKeyRefs = [EventHotKeyRef?](repeating: nil, count: combos.count)
for (i, combo) in combos.enumerated() {
    RegisterEventHotKey(combo.keyCode, UInt32(controlKey | optionKey),
                        EventHotKeyID(signature: OSType(0x4152_5447), id: combo.id),
                        GetApplicationEventTarget(), 0, &hotKeyRefs[i])
}

// MARK: - Settings window

// Three controls, no OK button. A menu bar utility's settings should be a
// glance and a click, so every change writes the file immediately — the scripts
// re-read it on each run, and the next hotkey press already uses the new value.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private var config = Config.load()

    private let agentPicker = NSSegmentedControl(
        labels: agents.map { $0.label }, trackingMode: .selectOne,
        target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let locateButton = NSButton(title: "Locate…", target: nil, action: nil)
    private let gridPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let yoloCheck = NSButton(checkboxWithTitle: "Skip approval prompts",
                                     target: nil, action: nil)
    private let commandLabel = NSTextField(labelWithString: "")

    // Column count, row count. Anything from 1x1 to 8x8 is legal in the config
    // file; these are the shapes that actually tile a screen sensibly.
    private let gridChoices: [(Int, Int)] = [(2, 2), (3, 2), (3, 3), (4, 3), (4, 4)]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Claude Steroids — Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        // Let the content decide the size — a fixed frame squeezed the mono
        // labels into ellipses no matter how much room the window had.
        let content = buildContent()
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildContent() -> NSView {
        agentPicker.target = self
        agentPicker.action = #selector(agentChanged)
        agentPicker.segmentDistribution = .fillEqually

        for (c, r) in gridChoices {
            gridPicker.addItem(withTitle: "\(c) × \(r)  —  \(c * r) sessions")
        }
        gridPicker.target = self
        gridPicker.action = #selector(gridChanged)

        yoloCheck.target = self
        yoloCheck.action = #selector(yoloChanged)

        locateButton.target = self
        locateButton.action = #selector(locateOrClear)
        locateButton.bezelStyle = .rounded
        locateButton.controlSize = .small
        locateButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        // A path and a command line are both things you read character by
        // character, so: monospaced, and wide enough for the longest one either
        // agent can produce (codex's bypass flag). Anything longer than that —
        // a hand-picked binary buried deep in a home directory — truncates in
        // the middle rather than stretching the window, which is why the low
        // compression resistance and the minimum width work as a pair.
        for (label, minWidth) in [(statusLabel, 280.0), (commandLabel, 380.0)] {
            label.font = NSFont.monospacedSystemFont(
                ofSize: NSFont.smallSystemFontSize, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingMiddle
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
        }

        let statusRow = NSStackView(views: [statusLabel, locateButton])
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .firstBaseline

        let footer = NSTextField(labelWithString:
            "⌃⌥C session   ⌃⌥S grid   ⌃⌥T arrange"
            + "\nFinder right-click and the hotkeys all run the selected agent.")
        footer.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        footer.textColor = .tertiaryLabelColor

        let grid = NSGridView(views: [
            [caption("Agent"), agentPicker],
            [NSGridCell.emptyContentView, statusRow],
            [caption("Grid"), gridPicker],
            [caption("Autonomy"), yoloCheck],
            [NSGridCell.emptyContentView, commandLabel],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.row(at: 1).topPadding = -2
        grid.row(at: 2).topPadding = 10
        grid.row(at: 3).topPadding = 10
        grid.row(at: 4).topPadding = -2

        let divider = NSBox()
        divider.boxType = .separator

        let root = NSStackView(views: [grid, divider, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)

        // The divider is the only thing that should span the window; a stack
        // view aligned .leading would otherwise leave it at its own tiny width.
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.leadingAnchor.constraint(
            equalTo: root.leadingAnchor, constant: root.edgeInsets.left).isActive = true
        divider.trailingAnchor.constraint(
            equalTo: root.trailingAnchor, constant: -root.edgeInsets.right).isActive = true
        return root
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    // MARK: state

    func show() {
        config = Config.load()      // the file may have been hand-edited meanwhile
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        let spec = config.spec
        agentPicker.selectedSegment = agents.firstIndex { $0.id == spec.id } ?? 0
        gridPicker.selectItem(at: gridChoices.firstIndex {
            $0.0 == config.columns && $0.1 == config.rows
        } ?? gridChoices.firstIndex { $0 == (3, 3) } ?? 0)
        yoloCheck.state = config.yolo ? .on : .off
        commandLabel.stringValue = "Runs:  " + spec.bin
            + (config.yolo ? " " + spec.yoloFlag : "")

        // Locating the binary shells out to a login shell, which reads the whole
        // profile — fast, but not "while the window draws" fast.
        statusLabel.stringValue = "Looking for \(spec.bin)…"
        statusLabel.textColor = .tertiaryLabelColor
        locateButton.title = config.explicitPath.isEmpty ? "Locate…" : "Use PATH"
        let explicit = config.explicitPath
        DispatchQueue.global().async { [weak self] in
            let found: String?
            if !explicit.isEmpty {
                found = FileManager.default.isExecutableFile(atPath: explicit) ? explicit : nil
            } else {
                found = loginShellWhich(spec.bin)
            }
            DispatchQueue.main.async {
                guard let self = self, self.config.agent == spec.id else { return }
                if let path = found {
                    self.statusLabel.stringValue = "✓ " + path
                    self.statusLabel.textColor = .secondaryLabelColor
                } else if !explicit.isEmpty {
                    self.statusLabel.stringValue = "✗ not executable: " + explicit
                    self.statusLabel.textColor = .systemRed
                } else {
                    self.statusLabel.stringValue = "✗ not found — " + spec.installHint
                    self.statusLabel.textColor = .systemRed
                }
            }
        }
    }

    // MARK: actions

    @objc private func agentChanged() {
        let idx = agentPicker.selectedSegment
        guard idx >= 0 && idx < agents.count else { return }
        config.agent = agents[idx].id
        config.save()
        refresh()
    }

    @objc private func gridChanged() {
        let idx = gridPicker.indexOfSelectedItem
        guard idx >= 0 && idx < gridChoices.count else { return }
        (config.columns, config.rows) = gridChoices[idx]
        config.save()
    }

    @objc private func yoloChanged() {
        config.yolo = (yoloCheck.state == .on)
        config.save()
        refresh()
    }

    // One button, two jobs: point at a binary that is not on PATH, or forget
    // that choice again. A "Locate…" with no way back would strand anyone who
    // picked the wrong file.
    @objc private func locateOrClear() {
        if !config.explicitPath.isEmpty {
            config.paths[config.agent] = ""
            config.save()
            refresh()
            return
        }
        let spec = config.spec
        let panel = NSOpenPanel()
        panel.title = "Choose the \(spec.label) executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            self.config.paths[self.config.agent] = url.path
            self.config.save()
            self.refresh()
        }
    }

    // Accessory apps keep no Dock icon, so nothing takes focus back when the
    // window closes — hand it to whatever the user was in before.
    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }
}

// MARK: - Menu bar

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    let mainMenu = NSMenu()
    let permMenu = NSMenu()
    let autoItem = NSMenuItem()
    let sessionItem = NSMenuItem()
    let steroidsItem = NSMenuItem()
    let closeAgentsItem = NSMenuItem()
    var settings: SettingsWindowController?

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

        // Titles name the selected agent and the configured grid size, so the
        // menu answers "what will this actually launch?" without opening
        // Settings. menuNeedsUpdate refreshes them on every open.
        mainMenu.delegate = self
        configure(sessionItem, #selector(newSession), "c")
        configure(steroidsItem, #selector(steroids), "s")
        mainMenu.addItem(sessionItem)
        mainMenu.addItem(steroidsItem)
        mainMenu.addItem(makeItem("Arrange Terminals", #selector(arrange), "t"))
        mainMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings),
                                      keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        mainMenu.addItem(settingsItem)

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
        mainMenu.setSubmenu(permMenu, for: permItem)
        mainMenu.addItem(permItem)
        mainMenu.addItem(.separator())

        // "Quit" submenu — closes Terminal windows cleanly (processes killed
        // first, so Terminal never shows a confirmation dialog).
        let quitMenu = NSMenu()
        quitMenu.addItem(makeItem("Close Terminals on This Desktop", #selector(closeSpace), ""))
        configure(closeAgentsItem, #selector(closeAgents), "")
        quitMenu.addItem(closeAgentsItem)
        quitMenu.addItem(.separator())
        quitMenu.addItem(NSMenuItem(title: "Quit Menu Bar App",
                                    action: #selector(NSApplication.terminate(_:)),
                                    keyEquivalent: ""))
        let quitItem = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "")
        mainMenu.setSubmenu(quitMenu, for: quitItem)
        mainMenu.addItem(quitItem)

        item.menu = mainMenu
        retitle()
    }

    private func configure(_ item: NSMenuItem, _ action: Selector, _ key: String) {
        item.action = action
        item.keyEquivalent = key
        if !key.isEmpty { item.keyEquivalentModifierMask = [.control, .option] }
        item.target = self
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

    private func retitle() {
        let config = Config.load()
        let label = config.spec.label
        sessionItem.title = "New Session — \(label)"
        steroidsItem.title = "Steroids Mode — \(config.sessionCount)× \(label)"
        closeAgentsItem.title = "Close ALL Agent Sessions"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === mainMenu {
            retitle()
            return
        }
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

    @objc func openSettings() {
        if settings == nil { settings = SettingsWindowController() }
        settings?.show()
    }

    @objc func newSession()  { runScript("claude-session.sh") }
    @objc func steroids()    { runScript("steroids-grid.sh") }
    @objc func arrange()     { runScript("arrange-terminals.sh") }
    @objc func closeSpace()  { runScript("close-terminals.sh", ["space"]) }
    @objc func closeAgents() { runScript("close-terminals.sh", ["agents"]) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar icon only — no Dock icon
app.run()
