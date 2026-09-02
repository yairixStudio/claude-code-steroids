# Windows Testing Guide

Everything in `windows/` was written and reviewed on a Mac, where PowerShell and
`csc.exe` do not exist. It has now been run on Windows once — see
[FIRST-RUN-REPORT.md](FIRST-RUN-REPORT.md), which found that **no launch worked at
all** and fixed it. Read that first; it tells you which parts are now verified and
which are still exactly as untested as they were.

Short version of what is still untouched: **Parts 3, 4 and 5 below have never been
run by anyone**, the live suite has never completed a clean pass, and the Settings
window has never been opened. The macOS half is fully tested (91 automated tests,
plus live checks); this half is not. That is what this guide is for.

Take about **30 minutes**. Parts 1–2 are automated and take five. Parts 3–5 are manual,
and they cover the surfaces no test can reach.

Report back with the template at the bottom. **A failure is a useful result** — please
send the exact error text rather than trying to fix it.

---

## What this project is

Right-click a folder → open a coding-agent session (Claude Code or OpenAI Codex) in it.
Or open **nine at once**, tiled in a grid. Plus a tray icon and global hotkeys.

Recent work made the agent a **setting** rather than a hardcode, added a **Settings
window**, and added **six** context-menu entries: two that follow whichever agent is
selected, and four that pin one agent regardless.

---

## Before you start

### Requirements

| | |
|---|---|
| Windows 10 or 11 | — |
| [Windows Terminal](https://aka.ms/terminal) | `wt.exe` must be on `PATH` |
| At least one agent CLI | `npm i -g @anthropic-ai/claude-code` and/or `npm i -g @openai/codex` |
| .NET Framework `csc.exe` | Ships with Windows — nothing to install |

No administrator rights are needed. Everything is written under your user (`HKCU`,
`%LOCALAPPDATA%`, `%APPDATA%`).

Check your starting point:

```powershell
wt.exe --version
Get-Command claude, codex -ErrorAction SilentlyContinue | Select-Object Name, Source
$PSVersionTable.PSVersion
```

You need Windows Terminal and **at least one** agent. Having both is better — four of the
six context-menu entries are agent-specific. If you only have one, say so in your report
and skip the checks for the other.

### Safety — read this one

Both launch actions default to the agent's **skip-all-approvals** flag
(`--dangerously-skip-permissions` for Claude, `--dangerously-bypass-approvals-and-sandbox`
for Codex). An agent started that way reads, edits and runs commands **without asking**,
and Codex's flag drops its sandbox as well.

**Before any manual test, turn that off** (Part 3, step 2 shows you where) and do every
launch test in a **throwaway folder**:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\steroids-scratch" | Out-Null
```

You are testing whether a window opens in the right place with the right command on its
prompt. You never need to let an agent actually do anything.

### What the tests do to your machine

| | |
|---|---|
| Part 1 (offline suite) | Nothing. Reads the repo, uses a throwaway config in `%TEMP%`. |
| Part 2 (live suite) | **Really installs and uninstalls.** Opens and closes Terminal windows using a placeholder command — never a real agent. Backs up and restores your settings file. |
| Parts 3–5 | Install for real, then uninstall at the end. |

If you already use this project, Part 2 will uninstall it. Part 5 reinstalls it.

---

## Part 1 — The offline test suite

```powershell
cd <wherever you cloned it>
powershell -ExecutionPolicy Bypass -File .\windows\tests\run-tests.ps1
```

**Expected:** a list of `PASS` lines and, at the end, `All N tests passed.` — and exit
code 0. Anything other than that last line is a failure worth reporting.

If PowerShell refuses to run the file at all, that is your execution policy — the
`-ExecutionPolicy Bypass` above should already handle it, but see Troubleshooting.

What it covers, and why each section exists:

| Section | Why it is there |
|---|---|
| **Encoding** | Every `.ps1` and `.cs` must be ASCII-only or carry a UTF-8 BOM. Windows PowerShell reads a BOM-less file in the ANSI code page, and an em dash decoding into three characters once closed a string early and crashed the installer before it registered anything. |
| **Resolve-TargetDir** | Explorer hands the clicked folder over as `%V`. At a drive root that is `C:\`, whose trailing backslash escapes the closing quote, so the script receives `C:"`. |
| **Grid construction** | A session must be a *window*, never a pane: no `split-pane`, no `focus-pane`, no `-M`, and one `new-tab` per launch. Session count tracks columns × rows, and a grid session runs byte for byte the command line a single right-click runs. |
| **Tiling maths** | Cells fill the work area exactly — every seam meets, the last cell lands on the far edge, and no two differ by more than a pixel. Rounding one cell width and adding it *n* times leaves a strip of wallpaper down the right of any screen that does not divide evenly. |
| **Command-line quoting** | Built by hand and checked against Windows' own `CommandLineToArgvW`, not against a second reading of the rules. Includes a drive root with a pinned agent, and non-ASCII folder names. |
| **Agent session detection** | What the close actions fire at — and, more importantly, what they must leave alone. |
| **What a close action must not interrupt** | A pane running `npm install -g` is spared: killing Claude's own updater mid-rename breaks the install permanently, not just for now. |
| **Tray menu — the per-agent grid picker** | The tray's *Steroids Mode* submenus must offer exactly the shapes the Settings dropdown offers, and spell them the same way. There is no shared list to rely on — Settings is PowerShell, the tray is a C# exe — so the suite holds the two tables side by side and fails if either drifts. It also checks that a submenu pick pins agent *and* shape, that the hotkeys pin neither, and that a pick never rewrites the settings file. |
| **Settings** | Reading, saving, and surviving a config hand-edited into nonsense. |

### If something fails here

Send the failing lines verbatim. Every test prints what it expected and what it got.

---

## Part 2 — The live test suite

This one installs for real, compiles the tray app, opens Terminal windows and closes them
again. Close anything you care about in Windows Terminal first.

> **Run this from a plain PowerShell window, not from inside Windows Terminal.** The
> suite tiles, resizes and closes Terminal windows on the current virtual desktop, and
> it cannot tell the window you launched it from apart from the ones it opened. Two
> attempts to run it from a Windows Terminal pane ended with that pane gone.

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\tests\run-tests.ps1 -IncludeLive
```

**Expected:** `All N tests passed.` again, with a higher N than Part 1. Takes a couple of
minutes, and windows will open and close on their own — that is the point.

It additionally checks that the installer completes, that all twelve context-menu
registry entries appear, that the four pinned entries really pin their agent, that the
tray app compiles with the Windows C# compiler, that the uninstaller removes every trace,
and that uninstalling twice is harmless.

> The panes it opens run `cmd /k prompt STEROIDS_TEST_PANE$` — a marker, never an agent.
> Every window it closes is looked up by that marker.

**The most likely thing to fail here is the tray app compile.** If it does, send the whole
`csc` error block.

---

## Part 3 — Install and first look

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\install.ps1
```

**Expected:** `Installed.` in green, then a summary of the hotkeys and Settings. A tray
icon — a small 3×3 grid of white squares — appears next to the clock.

### 1. Tray menu

Right-click the tray icon.

- [ ] The menu opens
- [ ] It leads with a block **per agent**: **New Session - Claude Code**, then **Steroids Mode - Claude Code** with a submenu arrow, a separator, then the same pair for **OpenAI Codex**
- [ ] The **selected** agent (Settings) is the block on top, and it is the one showing **Ctrl+Alt+C**
- [ ] Opening **Steroids Mode - Claude Code** lists five shapes: `2 x 2 - 4 sessions` through `4 x 4 - 16 sessions`
- [ ] The configured shape (`3 x 3 - 9 sessions` out of the box) carries a **check mark**, and it is the only row showing **Ctrl+Alt+S** — and only under the selected agent
- [ ] The Codex submenu lists the same five shapes, with the same one checked, but **no** hotkey on any row
- [ ] **Arrange Terminals**, **Settings...**, and a **Quit** submenu are present below the blocks
- [ ] Hovering the icon shows a tooltip naming the selected agent and the configured grid

Now click **Steroids Mode - OpenAI Codex ▸ 2 x 2 - 4 sessions**:

- [ ] **Four** windows open, running `codex`, whatever Settings says
- [ ] Open Settings again — **Agent** is still Claude Code and **Grid** is still 3 x 3. A submenu pick is a one-off and must never write the file
- [ ] Close the four windows

> The whole block is rebuilt from the settings file every time the menu opens — not
> just retitled, because its *order* and its check mark come from the file. Later,
> after you change the agent in Settings, the blocks must swap places and the
> hotkeys must move with them.

### 2. Settings window — **please spend the most time here**

This is the least-verified part of the whole project: a WinForms dialog whose event
wiring has never run. Click **Settings...**.

- [ ] A window titled **Claude Steroids - Settings** opens
- [ ] It shows: **Agent** (two radio buttons), **Grid** (a dropdown), **Autonomy** (a checkbox), a hotkey reminder, and a **Close** button
- [ ] Under the radio buttons, a line reads `OK  C:\...\claude.exe` (or similar). Two other states are possible and both are correct: `found off PATH  C:\...` when the CLI was located by the fallback search rather than on `PATH`, and `not found - npm i -g ...` in red when it is genuinely absent
- [ ] Under the checkbox, a line reads `Runs:  claude --dangerously-skip-permissions`

Now exercise it. **There is no OK button — every change saves the moment you click.**

- [ ] Click **OpenAI Codex**. The status line and the `Runs:` line both update immediately
- [ ] **Untick "Skip approval prompts."** The `Runs:` line drops the flag entirely, leaving just `Runs:  codex` — *leave it unticked for the rest of this guide*
- [ ] Change **Grid** to `2 x 2 - 4 sessions`
- [ ] Click **Close**
- [ ] Reopen Settings — every choice is still there
- [ ] Right-click the tray icon — the titles now say **OpenAI Codex** and **4x**

Confirm it reached disk:

```powershell
Get-Content "$env:APPDATA\claude-code-steroids\config.json"
```

- [ ] Shows `"agent": "codex"`, `"columns": 2`, `"rows": 2`, `"yolo": false`

Then set it back to **Claude Code**, grid **3 x 3**, and leave Autonomy **off**.

### 3. Global hotkeys

From any app — a browser, Notepad, anything:

- [ ] **Ctrl+Alt+C** opens one Windows Terminal window in your user folder
- [ ] **Ctrl+Alt+S** opens nine separate windows, tiled three by three over the screen
- [ ] **Ctrl+Alt+T** retiles the Terminal windows on this virtual desktop into a grid

With Autonomy off, each session sits at the agent's normal approval prompt — nothing runs
unattended. Close the windows when done.

> If a hotkey does nothing, another app already owns that combination. The tray app shows
> a balloon tip saying so at startup. Note which one and move on — the menu still works.

---

## Part 4 — The context menu

Right-click a folder in Explorer. **On Windows 11 these live under "Show more options."**

- [ ] All six entries are present:
  - Open Coding Agent Here
  - Steroids Mode (9x Grid)
  - Open in Claude
  - Open in Claude — Steroids (9x)
  - Open in Codex
  - Open in Codex — Steroids (9x)
- [ ] They also appear when right-clicking the **empty background** inside an open folder

### 1. The neutral pair follows Settings

With the agent set to **Claude Code**, on your scratch folder:

- [ ] **Open Coding Agent Here** → a window opens **in that folder**, running `claude`. It should arrive **centred**, at roughly two thirds of the screen width and four fifths of its height — not at Terminal's default size off to one side
- [ ] The tab is titled after the agent, not after `cmd` — panes are hosted by PowerShell now, so when the agent exits you are left at a PowerShell prompt in that folder
- [ ] Switch the agent to **OpenAI Codex** in Settings, then click it again → same folder, now `codex`
- [ ] Set it back to **Claude Code**

### 2. The pinned four ignore Settings

That is the whole point of them. With the agent set to **Claude Code**:

- [ ] **Open in Codex** → opens **codex**, not claude
- [ ] **Open in Claude** → opens claude

Now set the agent to **OpenAI Codex** and repeat:

- [ ] **Open in Claude** → still opens **claude**
- [ ] **Open in Codex** → opens codex

Set it back to **Claude Code**.

> If you only have one CLI installed, the entry for the missing one should show a message
> box that names the agent, lists **where it looked**, gives the `npm i -g ...` command,
> and points out that Explorer may simply be running with a stale environment — not fail
> silently, and not blame `PATH` without saying what it checked. Please confirm that.

### 3. Folder names that break things — **these are regression checks**

These two cases have each caused a real bug in this project.

**A drive root.** Open `C:\` in Explorer and right-click the **empty background inside
the window** — not the drive icon in *This PC*. The entries are registered for folders
(`Directory` and `Directory\Background`), not for drives, so the drive icon deliberately
shows nothing. The background of an open drive window is a `Directory\Background`
right-click whose `%V` is `C:\`, which is the case we need to exercise.

- [ ] **Open in Codex** opens a window whose prompt is at `C:\` — *not* at your user folder
- [ ] and it really is **codex**, not claude

> Why this matters: `%V` becomes `C:\`, and that trailing backslash escapes the closing
> quote on the command line. Until recently the pinned agent was appended *after* the
> folder, and Windows' parser swallowed it into the path — so this exact click silently
> lost the pin **and** landed in the wrong folder. The fix was to put `-Agent` first.

**A non-ASCII name.** Create a folder with Hebrew (or Japanese, or accented) characters:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\steroids-scratch\אתר שאולי" | Out-Null
```

- [ ] **Open Coding Agent Here** on it opens a window **in that folder**, with the name intact on the prompt

> Why this matters: the macOS side had exactly this bug. Its shell escaped one byte out of
> the middle of each Hebrew character, and `~/Desktop/אתר` reached the terminal as
> `~/Desktop/◊$'\220'◊™◊®` — `cd` failed on a folder sitting right there. Windows should be
> immune (PowerShell is UTF-16 end to end, never raw bytes), and Part 1 asserts that
> against Windows' own parser. This confirms it for real.

### 4. The grid

On your scratch folder:

- [ ] **Steroids Mode (9x Grid)** opens **nine separate windows**, tiled three by three
- [ ] **They really are separate windows.** This is the one to look at hardest, because a pane grid draws the same picture. Drag one by its title bar — it should come away on its own. Close one with its **×** — the other eight should stay exactly where they are. Maximize one, then restore it. None of that was possible when the grid was one window split into nine panes, and that is the whole reason this changed
- [ ] **All nine are the same size**, in three equal columns of three, filling the screen right up to the taskbar with no strip of wallpaper down the side. Try it a few times, and on a loaded machine: windows are placed as they appear, and a slow one taking its cell late is the failure to watch for
- [ ] Every window is in the right folder
- [ ] Set Grid to `2 x 2` in Settings, click it again → **four** windows

### 5. Arrange and close

Open three or four Terminal windows, then:

- [ ] **Ctrl+Alt+T** tiles them into a grid over the work area, taskbar excluded
- [ ] Minimized windows and windows on other virtual desktops are left alone
- [ ] Tray → **Quit** → **Close Terminals on This Desktop** closes them **with no "close all panes?" confirmation dialog**
- [ ] Tray → **Quit** → **Close ALL Agent Sessions** ends agent sessions on any desktop and leaves other terminals alone

> "Close ALL Agent Sessions" is agent-blind on purpose: it ends Claude *and* Codex panes,
> so a swarm you started under one agent is still yours to close after switching.

---

## Part 5 — Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\uninstall.ps1
```

- [ ] Prints what it removed, then `Uninstalled.` in green
- [ ] The tray icon disappears
- [ ] All six context-menu entries are gone
- [ ] Running it a second time prints `Nothing to uninstall` and does not error

Verify nothing is left:

```powershell
Test-Path "$env:LOCALAPPDATA\claude-code-steroids"
Test-Path "$env:APPDATA\claude-code-steroids"
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name ClaudeSteroidsTray -ErrorAction SilentlyContinue
```

- [ ] All three come back empty / `False`

Then reinstall if you want to keep using it, and clean up:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\install.ps1
Remove-Item -Recurse -Force "$env:USERPROFILE\steroids-scratch"
```

---

## Reporting back

Copy this, fill it in, send it:

```
ENVIRONMENT
  Windows version   :  (winver)
  PowerShell        :  ($PSVersionTable.PSVersion)
  Windows Terminal  :
  Agents installed  :  claude / codex / both
  Display scaling   :  (100% / 125% / 150% ...)
  Multiple monitors :  yes / no

PART 1  offline suite      :  PASS (N tests)  /  FAIL
PART 2  live suite         :  PASS (N tests)  /  FAIL  /  skipped
PART 3  tray + settings    :  PASS / FAIL
PART 4  context menu       :  PASS / FAIL
PART 5  uninstall          :  PASS / FAIL

FAILURES  (exact text, one block each)


ANYTHING THAT FELT WRONG
  (slow, ugly, confusing, in the wrong place — say so even if nothing errored)
```

Gather the environment lines in one go:

```powershell
"Windows : " + (Get-CimInstance Win32_OperatingSystem).Caption + " " + [Environment]::OSVersion.Version
"PS      : " + $PSVersionTable.PSVersion
"wt      : " + (Get-Command wt.exe -ErrorAction SilentlyContinue).Source
Get-Command claude, codex -ErrorAction SilentlyContinue | Select-Object Name, Source
```

---

## Known and expected

Not bugs — no need to report these:

- **Windows 11 hides the entries under "Show more options."** Getting into the top-level
  menu needs a signed packaged shell extension, which this project deliberately is not.
- **Six flat entries, not a nested submenu.** A cascading flyout would be nicer; it was
  not written because a mistake in that mechanism produces a menu that opens and does
  nothing, and nobody could test it. Worth doing once someone can.
- **No "Locate…" button in Settings**, unlike macOS — a hand-typed path would have to
  survive `cmd`'s quote-stripping rules to reach the pane intact. It is less needed than
  it was: the launch scripts now look past the `PATH` they inherited, into the PATH
  persisted for your account and into `%USERPROFILE%\.local\bin` and `%APPDATA%\npm`,
  which covers both the native installer and npm. Settings reports `found off PATH` when
  that fallback is what located the CLI.
- **A hotkey may be dead** if another app claimed the combination first. The tray app says
  so with a balloon tip at startup.
- **A grid window may settle a fraction of a second after it opens.** Windows Terminal is
  still sizing itself to your profile when its window first exists, and a window caught
  mid-way through ignores the first move — so the grid places every window a second time
  once they are all up. On a loaded machine you can see the last one snap into its cell.

---

## Troubleshooting

**"running scripts is disabled on this system"** — you dropped the `-ExecutionPolicy
Bypass`. Put it back; it applies to that one process and changes nothing permanently.

**Context-menu entries don't appear** — restart Explorer:

```powershell
Stop-Process -Name explorer -Force
```

It relaunches itself. Check the registry directly:

```powershell
Get-ChildItem 'HKCU:\Software\Classes\Directory\shell' | Select-Object PSChildName
(Get-ItemProperty 'HKCU:\Software\Classes\Directory\shell\OpenInCodex\command').'(default)'
```

**Tray icon missing** — check whether it is running and whether it compiled:

```powershell
Get-Process steroids-tray -ErrorAction SilentlyContinue
Test-Path "$env:LOCALAPPDATA\claude-code-steroids\steroids-tray.exe"
```

Windows also hides tray icons by default: check the `^` overflow area, and
**Settings → Personalization → Taskbar → Other system tray icons**.

**"An Application Control policy has blocked this file"** (or *"blocked by your
organization's Device Guard policy"*) when the installer starts the tray app —
Windows 11's **Smart App Control**, which refuses executables it has no reputation
for. The tray app is compiled on your own machine at install time, so every install
produces a file the world has never seen, and the first launch is exactly the one it
stops. Confirm it with:

```powershell
(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy').VerifiedAndReputablePolicyState  # 1 = on
Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 5 | Select TimeCreated, Id
```

Nothing else is affected — the context-menu entries are plain PowerShell and work
either way, and the tray app is already registered to start at your next login. The
same file is usually allowed once its cloud check comes back, so try again:

```powershell
Start-Process "$env:LOCALAPPDATA\claude-code-steroids\steroids-tray.exe"
```

The installer reports this and finishes rather than aborting; if you ever see it die
with a stack trace here instead, that is a regression.

**A script does nothing when clicked** — they run hidden, so run one by hand to see the
error:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\claude-code-steroids\open-in-claude.ps1" "$env:USERPROFILE\steroids-scratch"
```

Or ask it what it *would* do, without launching anything:

```powershell
& "$env:LOCALAPPDATA\claude-code-steroids\steroids-grid.ps1" -Dir "C:\Temp" -Agent codex -DryRun
```

That prints the exact `wt.exe` command line — very useful in a bug report.

**Settings window won't open** — run it in the foreground so its error is visible:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\claude-code-steroids\steroids-settings.ps1"
```

**Anything else** — send the command you ran and the complete output. Do not clean it up.
