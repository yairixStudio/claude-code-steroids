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

It adds **two** entries to your folder right-click menu:

| Menu item | What happens |
|-----------|--------------|
| **Open in Claude** | Opens one terminal in that folder and starts Claude Code (YOLO mode). |
| **Open in Claude — Steroids (9×)** | Opens **9 Claude Code sessions at once**, tiled in a **3×3 grid** over your screen, all pointed at that folder (YOLO mode). |

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

**Requirements:** macOS, the [Claude Code CLI](https://claude.com/claude-code) on your `PATH`, and the built-in Terminal.app.

```bash
git clone https://github.com/yairixStudio/claude-code-steroids.git
cd claude-code-steroids/macos
zsh install.sh
```

Then: **right-click any folder in Finder → Quick Actions →**
**“Open in Claude”** or **“Open in Claude — Steroids (9×)”**.

- The first run asks for **Automation** permission (to let Terminal arrange windows) — click **OK**.
- If the items don't appear, log out/in or relaunch Finder (Option-right-click the Finder dock icon → **Relaunch**).

**Uninstall:** `zsh macos/uninstall.sh`

---

## 📦 Install — Windows

**Requirements:** Windows 10/11, [Windows Terminal](https://aka.ms/terminal), and the
[Claude Code CLI](https://claude.com/claude-code) on your `PATH`.

```powershell
git clone https://github.com/yairixStudio/claude-code-steroids.git
cd claude-code-steroids\windows
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Then: **right-click any folder → “Open in Claude”** or **“Open in Claude — Steroids (9x)”**.
On Windows 11 they may live under **“Show more options.”** The Steroids grid is a single
Windows Terminal window split into nine panes.

No administrator rights are needed — everything is written under your user (`HKCU`).

**Uninstall:** `powershell -ExecutionPolicy Bypass -File .\windows\uninstall.ps1`

---

## ⚙️ How it works

- **macOS** uses native **Finder Quick Actions** (Automator “Run Shell Script” services).
  The Steroids action calls a small AppleScript that reads your screen size via
  `NSScreen` (no extra permissions), opens nine Terminal windows running
  `claude --dangerously-skip-permissions`, and tiles them into a 3×3 grid.
- **Windows** uses **registry context-menu entries** under `HKCU` that call PowerShell,
  which drives **Windows Terminal** (`wt.exe`) split-pane commands to build the grid.

Everything is plain text and easy to audit — read the `macos/` and `windows/` folders.

---

## ⚠️ A note on `--dangerously-skip-permissions`

**Both** actions — *Open in Claude* and *Steroids (9×)* — launch Claude with
`--dangerously-skip-permissions` (a.k.a. **“YOLO mode”**). That means Claude will **read,
edit, and execute commands in that folder without stopping to ask for permission** — and in
Steroids Mode, nine agents do it at once.

**Use it only on folders and projects you trust.** Don't point it at code you just
downloaded, a client's repo you haven't reviewed, or anything where an unattended command
could do damage.

Prefer the normal, prompt-on-each-action behavior? Remove `--dangerously-skip-permissions`
from the scripts — it's a one-line edit, clearly marked in:
- `macos/quick-actions/Open in Claude*.workflow/Contents/document.wflow` (and `macos/scripts/steroids-grid.sh`)
- `windows/scripts/open-in-claude.ps1` and `windows/scripts/steroids-grid.ps1`

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

---

## 🤝 Contributing

Issues and PRs welcome — especially Linux support, iTerm/Warp support, and configurable
grid sizes.

## 📄 License

[MIT](LICENSE) © yairixStudio

---

<sub>Keywords: Claude Code, Anthropic, open folder in Claude, right-click Claude, Finder Quick Action,
Windows context menu, parallel Claude sessions, multiple Claude agents, 3x3 terminal grid, AI coding
assistant, macOS, Windows, PowerShell, developer productivity.</sub>
