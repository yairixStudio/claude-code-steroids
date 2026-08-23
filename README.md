# Claude Code — Steroids Mode 💉🚀

> **Right-click any folder → open it in [Claude Code](https://claude.com/claude-code). Or launch _nine_ parallel Claude sessions in a 3×3 grid — "Steroids Mode".**

A tiny, no-dependency add-on for **macOS** and **Windows** that puts Claude Code one
right-click away. Stop opening a terminal, `cd`-ing into your project, and typing
`claude` every single time. Just right-click the folder.

> [!WARNING]
> **Both** menu items launch Claude with `--dangerously-skip-permissions` ("YOLO mode") —
> Claude can read, edit, and run commands **without asking for confirmation**.
> Only use this on folders and projects you trust. See [the safety note](#-a-note-on---dangerously-skip-permissions) below.

[![Platform: macOS](https://img.shields.io/badge/macOS-Quick%20Actions-black?logo=apple)](#-install--macos)
[![Platform: Windows](https://img.shields.io/badge/Windows-PowerShell-blue?logo=windows)](#-install--windows)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## ✨ What it does

It adds **six** entries to your folder right-click menu — a neutral pair that
follows whichever agent you picked in [Settings](#-settings), plus a pinned pair
per agent so one folder can go to Claude and the next to Codex without changing
anything:

| Menu item | What happens |
|-----------|--------------|
| **Open Coding Agent Here** | One terminal in that folder, running your selected agent. |
| **Steroids Mode (9× Grid)** | **9 sessions at once** of your selected agent, tiled in a 3×3 grid over your screen. |
| **Open in Claude** | One terminal — always Claude Code. |
| **Open in Claude — Steroids (9×)** | A grid of Claude Code sessions. |
| **Open in Codex** | One terminal — always OpenAI Codex. |
| **Open in Codex — Steroids (9×)** | A grid of OpenAI Codex sessions. |

Pinning is only about *which CLI*: grid size and the autonomy toggle still come
from Settings, because those are preferences about how you work rather than
about which agent you reached for.

On macOS it also installs a lean **menu bar app** — a small grid icon (⊞) next to the
clock, started at every login — with three actions, each also on a **true global hotkey**
that works from any app:

| Hotkey | Action |
|--------|--------|
| **⌃⌥C** | New session (one Terminal window, in `~`) |
| **⌃⌥S** | Steroids Mode — a grid of sessions (3×3 by default) |
| **⌃⌥T** | Arrange Terminals — tile **all Terminal windows on the current desktop** into a grid sized to the count: 4 → 2×2, 9 → 3×3, 10 → 4×3, 16 → 4×4 … |

Either Option/Control key works (left or right). Windows on other desktops/Spaces and
minimized windows are left alone. New sessions open on the Space you're **currently
looking at**, so triggering a hotkey never yanks you to another desktop.

Tearing a swarm down is one click too — the menu bar's **Quit** submenu offers
**Close Terminals on This Desktop** and **Close ALL Agent Sessions**. Both kill the
running processes first, so macOS never interrupts you with "Do you want to terminate
running processes?" dialogs nine times in a row. A session that happens to be
**updating Claude** is left open on purpose — see the FAQ.

**Windows gets the same trio**: a system tray icon next to the clock with the three
actions and global hotkeys **Ctrl+Alt+C / Ctrl+Alt+S / Ctrl+Alt+T** — Steroids Mode
there is nine panes in one Windows Terminal window, and Arrange tiles the Windows
Terminal windows on the current virtual desktop. Starts automatically at every login.

> Both run with `--dangerously-skip-permissions`. See the [safety note](#-a-note-on---dangerously-skip-permissions).

```
   Steroids Mode = 9 Claude sessions, one folder, one click

   ┌─────────┬─────────┬─────────┐
   │ claude  │ claude  │ claude  │
   ├─────────┼─────────┼─────────┤
   │ claude  │ claude  │ claude  │
   ├─────────┼─────────┼─────────┤
   │ claude  │ claude  │ claude  │
   └─────────┴─────────┴─────────┘
```

Why nine? When you want to throw a swarm of agents at a codebase — parallel
refactors, parallel investigations, multiple worktrees, or just brute-forcing a
problem from nine angles — one click sets up the whole battlefield.

---

## 📦 Install — macOS

**Requirements:** macOS, the built-in Terminal.app, and at least one agent CLI on your `PATH` —
[Claude Code](https://claude.com/claude-code) (`npm i -g @anthropic-ai/claude-code`) or
[OpenAI Codex](https://developers.openai.com/codex) (`npm i -g @openai/codex`).

```bash
git clone https://github.com/yairixStudio/claude-code-steroids.git
cd claude-code-steroids/macos
zsh install.sh
```

Then: **right-click any folder in Finder → Quick Actions →** and pick one of the
six entries (**Open Coding Agent Here**, **Steroids Mode (9× Grid)**, or a
pinned **Claude** / **Codex** one).

You'll also get the menu bar icon (⊞) and the global hotkeys **⌃⌥C / ⌃⌥S / ⌃⌥T**
(to change a combo, edit `macos/scripts/steroids-menubar.swift` and re-run the
installer). Compiling them needs Xcode Command Line Tools (`xcode-select --install`).
Optional: drag **Arrange Terminals** from **~/Applications** to your Dock for a
one-click tile button.

- **Permissions:** nothing is requested at install or launch. The first time an
  action runs, macOS asks once for **Automation → Terminal** (“Claude Steroids
  wants to control Terminal”) — click **Allow**; that's the only permission the
  app needs. The menu bar's **Permissions** submenu shows a live ✓ for that
  grant and lets you revoke it, re-request it, jump to Privacy & Security, or
  reset every grant the app holds.
- If the items don't appear, log out/in or relaunch Finder (Option-right-click the Finder dock icon → **Relaunch**).

**Uninstall:** `zsh macos/uninstall.sh`

---

## 📦 Install — Windows

**Requirements:** Windows 10/11, [Windows Terminal](https://aka.ms/terminal), and at least one
agent CLI on your `PATH` — [Claude Code](https://claude.com/claude-code)
(`npm i -g @anthropic-ai/claude-code`) or [OpenAI Codex](https://developers.openai.com/codex)
(`npm i -g @openai/codex`).

```powershell
git clone https://github.com/yairixStudio/claude-code-steroids.git
cd claude-code-steroids\windows
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Then: **right-click any folder** and pick one of the six entries. On Windows 11 they
live under **“Show more options.”** The Steroids grid is a single Windows Terminal window
split into nine panes.

You'll also get the tray icon (by the clock) and the global hotkeys
**Ctrl+Alt+C / Ctrl+Alt+S / Ctrl+Alt+T** (to change a combo, edit
`windows/scripts/steroids-tray.cs` and re-run the installer).

No administrator rights are needed — everything is written under your user (`HKCU`),
and the tray app is compiled locally with the `csc.exe` that ships with Windows.

**Uninstall:** `powershell -ExecutionPolicy Bypass -File .\windows\uninstall.ps1`

---

## ⚙️ Settings

**macOS:** menu bar icon (⊞) → **Settings…**
**Windows:** tray icon → **Settings…**

Three controls, saved the moment you click — there is no OK button, and the next
hotkey press already uses the new value.

| | |
|---|---|
| **Agent** | **Claude Code** or **OpenAI Codex**. A live ✓ shows the path it resolved to, or a ✗ with the one-line install command if the CLI isn't there yet. |
| **Grid** | 2×2 through 4×4. The file accepts anything up to 8×8 if you'd rather type it. |
| **Autonomy** | *Skip approval prompts*, on or off. **Off passes no flag at all**, so each CLI behaves exactly as it does when you run it yourself. |

The choice reaches the hotkeys, the menu/tray items, and the two **neutral**
right-click entries at once. The four pinned right-click entries ignore it by
design — that is what they are for.

Behind it is one small JSON file, safe to hand-edit:

| | |
|---|---|
| macOS | `~/.config/claude-code-steroids/config.json` |
| Windows | `%APPDATA%\claude-code-steroids\config.json` |

```json
{ "version": 1, "agent": "claude", "yolo": true, "columns": 3, "rows": 3 }
```

Every field is optional and out-of-range values fall back to the default, so a
config edited into nonsense can never be the reason a hotkey stops working.
Reinstalling never overwrites it.

`paths` is a fourth, macOS-only key — the **Locate…** button stores a CLI that
isn't on `PATH` there. Windows has no equivalent: an npm global install puts the
binary on `PATH`, and a hand-typed path would have to survive `cmd`'s
quote-stripping rules to reach the pane intact.

### What each agent is launched with

| Agent | Autonomy on | Autonomy off |
|---|---|---|
| Claude Code | `claude --dangerously-skip-permissions` | `claude` |
| OpenAI Codex | `codex --dangerously-bypass-approvals-and-sandbox` | `codex` |

Closing a swarm is agent-blind on purpose: **Close ALL Agent Sessions** ends
Claude *and* Codex panes, so a swarm you started this morning is still yours to
close after switching agent this afternoon.

> **macOS note.** A workflow in `~/Library/Services` is not the same thing as a
> menu item: macOS keeps a separate on/off switch per service in `pbs.plist`
> (System Settings ▸ Extensions ▸ Finder). The installer writes those switches
> explicitly — keyed by each service's *menu item* name, which is not always its
> bundle filename. A Quick Action with no switch is at the mercy of whatever
> macOS decides the default is, which is how an item can be installed, valid,
> and completely invisible.

---

## ⚙️ How it works

- **macOS** uses native **Finder Quick Actions** (Automator “Run Shell Script” services).
  The Steroids action calls a small AppleScript that reads your screen size via
  `NSScreen` (no extra permissions), opens nine Terminal windows running
  `claude --dangerously-skip-permissions`, and tiles them into a 3×3 grid.
  The menu bar app is a single Swift file (`NSStatusItem` + Carbon's
  `RegisterEventHotKey` — true global hotkeys that beat the frontmost app's own
  shortcuts, no Accessibility permission needed), compiled locally by the installer
  into **Claude Steroids.app** (a signed bundle with a stable bundle ID, so
  permission prompts show a real app name and its **Permissions** menu can manage
  grants via `tccutil`) and started at login as a LaunchAgent. On macOS 26
  (Tahoe), closing swarms kills processes by tty-scoped PID lookup rather than a
  system-wide `pkill` sweep — the sweep is what used to make Tahoe's new
  App-Data protection fire a permission prompt for every unrelated app
  (WhatsApp, Music, …). **Arrange Terminals** is a JXA script: it
  reads on-screen window bounds via `CGWindowList` (which only reports the current
  Space), matches them to Terminal's scriptable windows, and retiles them into a
  `ceil(√n)`-column grid over the visible screen area.
- **Windows** uses **registry context-menu entries** under `HKCU` that call PowerShell,
  which drives **Windows Terminal** (`wt.exe`) split-pane commands to build the grid.
  The tray app is a single C# file (`NotifyIcon` + `RegisterHotKey`) compiled locally
  by the installer and started at login via the `HKCU` Run key. **Arrange Terminals**
  enumerates Windows Terminal windows with Win32 `EnumWindows`, keeps only those on
  the current virtual desktop (`IVirtualDesktopManager`), and retiles them into a
  `ceil(√n)`-column grid over the primary work area.

- **Settings** on both platforms is the same small JSON file (see
  [Settings](#-settings)). Nothing caches it: every script re-reads it on each run
  and every menu re-reads it on each open, which is why switching agent takes
  effect on the very next hotkey press with nothing to restart. On macOS the
  window is part of the Swift menu bar app; on Windows it is a WinForms dialog in
  `steroids-settings.ps1`, so the read/write logic lives once — in
  `steroids-common.ps1`, where the test suite can reach it — instead of being
  reimplemented in C#.

Everything is plain text and easy to audit — read the `macos/` and `windows/` folders.

---

## ⚠️ A note on YOLO mode

Out of the box, **both** actions — *Open in Claude* and *Steroids (9×)* — launch the
agent with its skip-all-approvals flag:

| Agent | Flag |
|---|---|
| Claude Code | `--dangerously-skip-permissions` |
| OpenAI Codex | `--dangerously-bypass-approvals-and-sandbox` |

That means the agent will **read, edit, and execute commands in that folder without
stopping to ask** — and in Steroids Mode, nine of them do it at once. Codex's flag goes
further than Claude's: it drops the *sandbox* as well as the approvals, so there is no
filesystem boundary left to contain a mistake.

**Use it only on folders and projects you trust.** Don't point it at code you just
downloaded, a client's repo you haven't reviewed, or anything where an unattended command
could do damage.

Prefer the normal, prompt-on-each-action behavior? Turn **Autonomy → Skip approval
prompts** off in [Settings](#-settings). No flag is passed at all then, so each CLI
behaves exactly as it does when you run it yourself.

---

## ❓ FAQ

**What is Claude Code Steroids Mode?**
A right-click add-on that opens a folder in Claude Code, or launches nine parallel
Claude Code sessions in a 3×3 grid, on macOS and Windows.

**Do I need to know how to script anything?**
No. Run the one-line installer, then use the right-click menu.

**Does it work with iTerm / Warp / other terminals?**
The macOS version targets the built-in Terminal.app; the Windows version targets Windows
Terminal. PRs for other terminals are welcome.

**Why does Claude still ask “Is this folder trusted?” the first time?**
That's Claude Code's own one-time per-folder trust prompt — separate from this tool.
Accept it once per folder and you won't see it again.

**Can I change the grid to 2×2 or 4×4?**
Yes — the grid math lives in `macos/scripts/steroids-grid.sh` and
`windows/scripts/steroids-grid.ps1`.

**How do I close nine Claude sessions without nine confirmation dialogs?**
Use the menu bar (macOS) or tray (Windows) **Quit** submenu → *Close Terminals on This
Desktop* or *Close ALL Agent Sessions*. It terminates the agent processes before
closing the windows, so the terminal has nothing left to warn about
(`macos/scripts/close-terminals.sh`, `windows/scripts/close-terminals.ps1`).

**Will "Close ALL Agent Sessions" close the session I run it from?**
On Windows, no — that pane is detected and spared, so you can tear a swarm down from
inside one of its own sessions. *Close Terminals on This Desktop* is the blunt one: a
single Windows Terminal process owns every window, so it cannot tell them apart and
closes all of them, the one you are sitting in included.

**Why did a close action leave one window open?**
Because Claude was updating itself in it. Claude Code keeps current by shelling out to
`npm install -g`, which unpacks to a staging directory and only renames it into place at
the very end. Killing it in between doesn't just fail the update — the staging directory
left behind makes *every later install* fail with `ENOTEMPTY`, so `claude` reports
`command not found` until someone deletes it by hand. The close actions therefore skip a
session with a package install in flight and tell you they did (on Windows, *Close
Terminals on This Desktop* can't tell panes and windows apart, so it defers the whole
sweep instead). Long-running `npm exec` / `npx` processes such as MCP servers are **not**
installs and never hold a window open.

**Does any of this work if I installed Claude Code through npm?**
Yes. An npm install runs the CLI as `node.exe`, which the close actions recognise by the
package on its command line rather than by process name — so unrelated Node processes are
never touched.

---

## 🧪 Tests

Both suites are plain shell — no framework, nothing to install — and neither opens a
window, touches your settings, or goes near a running session:

```bash
zsh macos/tests/run-tests.sh
powershell -ExecutionPolicy Bypass -File .\windows\tests\run-tests.ps1
```

The macOS suite runs every path-quoting check three times: in a UTF-8 shell, in the C
locale, and with `LANG`/`LC_*` unset entirely — because that last one is what launchd
hands a Quick Action, and it is where quoting broke. `zsh`'s `${(q)}` escapes whatever
the *current* locale calls unprintable, which in C is `0x90` sitting in the middle of
`א`. A shell still reassembles that correctly, so a round-trip test stayed green — but
what it left behind was no longer valid UTF-8, and `osascript` downstream re-read the
orphaned bytes as Mac Roman and re-encoded them, turning `~/Desktop/אתר` into
`~/Desktop/◊$'\220'◊™◊®`. So the suite asserts the property that actually matters:
quoting never takes a multi-byte character apart.

Add `-IncludeLive` on Windows to also install for real, open Terminal windows and close
them again; those tests use a placeholder command and never launch a real agent.

**The Windows half has never been executed.** It was written and reviewed on a Mac, where
neither PowerShell nor `csc.exe` exists — so the automated suite above is the only thing
standing behind it. If you are on Windows and willing to shake it out, there is a full
walkthrough in **[windows/TESTING.md](windows/TESTING.md)**: the two suites, then the
manual checks no test can reach (the Settings dialog, the tray menu, the six context-menu
entries, a drive root, a non-ASCII folder name), and a template for reporting back.

## 🤝 Contributing

Issues and PRs welcome — especially Linux support, iTerm/Warp support, and a nested
flyout for the Windows context menu (its six entries are currently flat).

## 📄 License

[MIT](LICENSE) © yairixStudio

---

<sub>Keywords: Claude Code, Anthropic, open folder in Claude, right-click Claude, Finder Quick Action,
Windows context menu, parallel Claude sessions, multiple Claude agents, 3x3 terminal grid, AI coding
assistant, agentic coding, swarm of AI agents, macOS menu bar app, Windows tray app, global hotkeys,
tile terminal windows, macOS, Windows, PowerShell, Swift, developer productivity.</sub>
