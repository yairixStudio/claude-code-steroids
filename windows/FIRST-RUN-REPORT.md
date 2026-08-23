# First run on Windows — report

`TESTING.md` opens by saying that nothing in `windows/` had ever been executed:
it was written and reviewed on a Mac, where PowerShell and `csc.exe` do not
exist. This is the report it asks for, from the first machine to actually run it.

**Headline: the product did not work at all.** Every launch — all six
context-menu entries, both tray items, both launch hotkeys — failed with the same
message box:

```
 was not found on your PATH.

Install it with:


Then reopen Explorer so it picks up the new PATH, or pick the other agent in the
tray menu's Settings.
```

Note the two blanks. The agent's name and the install command are both missing,
because the object they came from was never built. The message blamed `PATH`;
`PATH` was fine.

---

## Environment

| | |
|---|---|
| Windows | 11 Home 10.0.26200, 25H2 |
| PowerShell | 5.1.26100.9168 (Desktop) |
| Windows Terminal | 1.24.11911.0 |
| Agents installed | Claude Code 2.1.241 only — **native installer**, `%USERPROFILE%\.local\bin\claude.exe`. No Codex. |
| `csc.exe` | present, both Framework and Framework64 |
| Display | one 1920×1080, 100% scaling |
| Locale | `en-US`, decimal `.`, **ANSI code page 1255 (Hebrew)** |

Two details of this machine did real work in this pass. The Hebrew ANSI code
page is exactly the hazard the encoding tests were written against, and they
pass — the BOMs are doing their job. And Claude Code arrived through the native
installer rather than npm, which is what exposed the `PATH` assumption in
finding 2.

---

## Results

| | |
|---|---|
| Part 1 — offline suite | **64 passed, 12 FAILED** → **99 passed, 0 failed** after the fixes |
| Steroids Mode, nine real agents | **broken** (finding 5) → **correct 3×3**, verified by screenshot |
| Single session window | default size, off to one side → centred at 62% × 80% of the work area |
| Part 2 — live suite | **partial.** Found finding 3, which stopped it running the installer at all. Not completed — see *What is still unverified*. |
| Parts 3–5 — tray, Settings, hotkeys, manual context menu, uninstall | **not run** — see *What is still unverified*. |
| End-to-end launch, by hand | **PASS** after the fixes — a real right-click command opened a real session |

---

## Finding 1 — a name collision broke every launch

**Severity: total. Nothing the product offers worked.**

`open-in-claude.ps1` and `steroids-grid.ps1` both declare a pinned-agent
parameter and then, a few lines later, keep the agent record in a local variable:

```powershell
param(
    [ValidateSet('', 'claude', 'codex')]
    [string]$Agent = ''
)
...
$agent = Get-SteroidsAgent $config.Agent      # <-- same variable as -Agent
```

PowerShell matches variable names case-insensitively, so `$agent` and `$Agent`
are one variable. Assigning to a parameter re-runs its validation attribute — and
a `pscustomobject` is not a member of `('', 'claude', 'codex')`, so
`[ValidateSet]` threw:

```
The variable cannot be validated because the value @{Id=claude; Label=Claude Code;
Bin=claude; YoloFlag=--dangerously-skip-permissions; InstallHint=npm i -g
@anthropic-ai/claude-code} is not a valid value for the Agent variable.
```

The assignment failed, so `$agent` was still the *string* `'claude'`.
`$agent.Bin` on a string is `$null`, `Get-Command $null` errors, `Test-AgentCli`
returned `$false`, and the script reported the agent as missing — using
`$agent.Label` and `$agent.InstallHint`, which are also `$null`. That is where
the two blanks in the message came from.

The shape is worth naming, because nothing about the offending line looks wrong:

* it is invisible at the call site — the bug is the *name*, not the statement
* it never fails at parse time, only at run time
* it can hit **any** parameter carrying a validation attribute

`steroids-grid.ps1` had the same trap set twice more, on `$Columns` and `$Rows`.
Those happened not to fire only because `Get-SteroidsConfig` clamps both to
`1..8` and the parameters accept `0..8`.

**Fix.** Distinct local names (`$selected`, `$gridColumns`, `$gridRows`), with a
comment at each site saying why the obvious name is not available.

**Test.** A static check, one per `.ps1`, that walks the AST and fails if any
script assigns to a variable whose name matches — case-insensitively, the same
comparison PowerShell itself makes — one of its own parameters that carries a
`Validate*` attribute. Nine tests, and they encode the bug class rather than this
one instance of it.

### Why the suite did not catch this

It did. It was never run.

Every grid test called the script the way the two *neutral* menu entries do. The
four *pinned* entries pass `-Agent`, and no test did — so even a run of the suite
would have missed the pinned half. Both gaps are now covered: the launchers are
exercised with each agent pinned and with no pin, through both scripts.

---

## Finding 2 — "not on your PATH" was almost never the actual problem

**Severity: the difference between a real diagnosis and a wrong one.**

Explorer hands every process it launches a copy of the environment it captured
when *it* started. Install an agent after logging in and the right-click entries
keep failing while the same `claude` works perfectly in every terminal you open.
The old message told you to install software you already had.

The old message was also stale about *how* you install it. It named
`npm i -g @anthropic-ai/claude-code`; on this machine Claude Code came from the
native installer and lives in `%USERPROFILE%\.local\bin`, which npm knows nothing
about.

**Fix.** `Resolve-AgentCommand` now looks past the inherited environment before
giving up:

1. `Get-Command` — the PATH we were handed. Unchanged behaviour, and when it hits
   the pane command is byte for byte what it always was.
2. The PATH **as persisted** for the account (`HKCU\Environment`, then the
   machine list). This is what a fresh login would have given us, so it is what
   separates *stale Explorer* from *genuinely missing*.
3. The two directories the agents actually install into: `%USERPROFILE%\.local\bin`
   (Claude Code's native installer) and `%APPDATA%\npm` (npm's shims).

When it has to fall back to 2 or 3, the pane runs the full path instead of the
bare name, in call-operator form (`& 'C:\…\claude.exe'`) so PowerShell runs it
rather than printing it as a string. It still arrives as one argument, asserted
against `CommandLineToArgvW`.

And when it genuinely finds nothing, it now says what it looked for:

```
OpenAI Codex was not found.

Looked on your PATH, on the PATH stored for your account, and in:
    C:\Users\yaira\.local\bin
    C:\Users\yaira\AppData\Roaming\npm

If it is not installed yet:
    npm i -g @openai/codex

If it IS installed, Explorer is still running with the environment it
started with. Sign out and back in, or restart Explorer:
    Stop-Process -Name explorer -Force

Or pick the other agent in the tray menu's Settings.
```

The Settings window uses the same resolver, so its status line reports what a
right-click would really do rather than what that window's own `PATH` contains.
It has a third state now — `found off PATH  <path>` — for exactly the case above.

> This supersedes the "No Locate… button in Settings" note in TESTING.md, which
> said *"on Windows an npm global install puts the binary on PATH … fixing PATH
> is the Windows answer."* The first half is no longer the only install shape,
> and the second half was the assumption that produced the wrong error message.

---

## Finding 3 — the live suite never ran the installer

**Severity: three live tests silently tested nothing.**

`run-tests.ps1` sets the repository path at the top:

```powershell
$root = Split-Path -Parent $PSScriptRoot
```

and then, seven hundred lines later, loops over the two registry roots:

```powershell
$menuKeys = foreach ($root in @('Directory', 'Directory\Background')) { ... }
```

A `foreach` variable is an ordinary assignment. After that loop `$root` is
`Directory\Background`, so:

```powershell
$installer = Join-Path $root 'install.ps1'   # -> Directory\Background\install.ps1
```

Every live test that ran a script by path invoked one that does not exist:

```
The argument 'Directory\Background\install.ps1' to the -File parameter does not
exist.
```

`the installer completes without errors` and both uninstaller tests failed. Worse,
`the installer seeds settings, and re-running keeps your choices` **passed** —
against whatever happened to be installed on the machine already, having never
run the installer at all.

The same family as finding 1: a name reused, invisible at the point of use.

**Fix.** Rename the loop variable to `$menuRoot`, and add a test that runs first
and asserts the suite is pointed at files that exist — so a path mistake reads as
a path mistake rather than as "the installer failed".

---

## Finding 4 — a stderr line could abort the installer

**Severity: latent. Not triggered on this machine.**

`install.ps1` runs under `$ErrorActionPreference = 'Stop'` and compiles the tray
app with:

```powershell
$out = & $csc ... 2>&1
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) {
    Write-Host 'Tray app failed to compile - continuing without it.'
```

In Windows PowerShell, `2>&1` on a **native** command wraps each stderr line in an
ErrorRecord, and under `Stop` that is a terminating error. Verified directly:

```powershell
$ErrorActionPreference = 'Stop'
& cmd /c "echo hello 1>&2 & exit /b 0" 2>&1     # throws; exit code was 0
```

So a single line on `csc`'s stderr would abort the installer *after* the context
menu is registered and *before* anything is reported — and the graceful
"continuing without it" branch could never run.

It has not bitten because `csc` puts its diagnostics on stdout; a deliberately
broken source file was confirmed to reach the graceful branch with the compiler
errors intact. That is luck, not design.

**Fix.** Drop the preference for the length of the call, in `install.ps1` and in
the equivalent line in the test suite.

---

## Finding 5 — the grid built itself on the wrong panes, but only under load

**Severity: Steroids Mode came out visibly broken. Reported from real use.**

Nine sessions opened, and the layout was wrong: one column had never been divided
at all and sat full height next to a column that had been divided one time too
many. Screenshots of both the broken and the fixed layout were taken on this
machine.

The columns were built by splitting vertically, then the rows by splitting each
column in turn — and the way the script got from one column to the next was:

```powershell
$wt.Add(';'); $wt.Add('move-focus'); $wt.Add('left')
```

`move-focus left` describes a *route through the layout*, and it is only correct
if every split before it has already landed. Usually it has. Nine agents starting
at once is the case where it has not: `claude.exe` is a 337 MB binary, nine of
them come up at the same moment, the terminal's UI thread falls behind its own
command list, and `move-focus` reads a layout one or two splits out of date. Every
split after that goes to the wrong pane.

That is why it looked like a working feature for so long. **The bug needs the
machine to be busy, which is exactly the moment nine agents make it busy.** A
probe grid of nine trivial processes lays out perfectly every time; the same
layout with nine real agents does not.

**Fix.** Address the pane instead of walking to it:

```powershell
$wt.Add(';'); $wt.Add('focus-pane'); $wt.Add('--target'); $wt.Add("$index")
```

`wt` numbers panes in creation order. Because every vertical split puts its new
pane on the right, the columns come out numbered `0..n-1` left to right — and
splitting a column appends its rows to the end of the numbering, so those indices
never move. An index cannot go stale the way a direction can.

Both facts were confirmed on this machine before the change was written:
`focus-pane --target 1` split the middle column of three and left the others
alone, and a full 3×3 built entirely from indices came out correct.

**Verified after the fix** with nine real Claude Code sessions on the folder this
report lives in: a clean 3×3, every pane the same size, every one in the right
folder, every one rendering properly.

**Tests.** The grid must emit no `move-focus` at all; it must emit exactly one
`focus-pane --target` per column, with targets `0..columns-1` in order; and no
target may be ≥ the column count. Checked at 3×3, 2×2, 4×3 and 1×4.

---

## The UI pass

### Panes are hosted by PowerShell now, not `cmd`

`cmd /k claude` became `powershell -NoLogo -NoExit -Command claude`.

`-NoExit` is `/k` respelled — it keeps the pane alive after the agent ends.
`-NoLogo` drops the banner, which otherwise eats the top of a pane that in a 3×3
grid is only sixteen lines tall. The profile is deliberately left to load: this
pane becomes your shell afterwards, so it should be your shell.

One consequence is visible immediately: the tab is titled **Claude Code** with the
agent's own icon, where the `cmd`-hosted pane showed a `cmd` icon and the folder
name.

This changes how a full path has to be written when the CLI is not on `PATH`. On a
`cmd` line a quoted path is a command; on a PowerShell line it is a *string*, and
PowerShell would print it and sit there. Hence `ConvertTo-PowerShellCommand`, which
produces `& 'C:\…\claude.exe'` — call operator, single quotes, doubled to escape
one.

### A single session gets a shape

Windows Terminal opened it at whatever size the profile last used, wherever the OS
put it — on this 1920×1080 screen, a 1113×620 box parked off to one side. It is now
centred at 62% × 80% of the work area (1190×825 here), using the same DPI-aware
`WorkArea`/`Place` code the tiler already had.

The window has to be found after the fact, because one Windows Terminal process
owns every window and `Start-Process` hands back the launcher rather than anything
on screen. So: snapshot the windows, launch, take whatever is new — and if that is
not *exactly one* window, do nothing at all. Moving a window somebody else opened
is much worse than leaving ours at the default size. Compiling the interop to do
this costs 173 ms, measured, which is well inside the time Terminal takes to
appear.

The grid does not need any of this; it asks `wt` for `-M` and fills the screen.

---

## What was verified, and how

**Automated.** The offline suite: 96 tests, all passing, up from 64 passing and 12
failing. New coverage: the parameter-shadowing check (9), the launchers driven
with each agent pinned and with no pin (6), and agent resolution including the
off-PATH path (5).

**The right-click path, for real.** Not a dry run — the exact command line out of
the registry, `%V` substituted, executed:

```
powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File
"...\open-in-claude.ps1" -Agent claude "C:\Users\yaira\steroids-scratch\אתר שאולי"
```

A Windows Terminal window opened, and the process tree showed the pane and its
agent:

```
PANE  15316  cmd.exe      cmd /k claude
CHILD 10616  claude.exe   claude
```

(That was before the pane host changed; it now reads `powershell -NoLogo -NoExit
-Command claude`.)

Right folder, right agent, no flag (autonomy was off for the test, per the safety
note in TESTING.md), and no error dialog.

**Parameter binding, every shape.** The four registry command lines that differ
(`OpenAgentHere`, `OpenInClaude`, `OpenInCodex`, `ClaudeSteroids`) × three folder
shapes, with the script swapped for a probe that echoes what it bound:

| `%V` | binds `-Dir` | binds `-Agent` |
|---|---|---|
| `...\steroids-scratch\אתר שאולי` | `...\steroids-scratch\אתר שאולי` | as pinned |
| `C:\` | `C:"` → repaired to `C:\` | as pinned |
| `...\steroids-scratch` | `...\steroids-scratch` | as pinned |

The drive-root regression holds: `%V` still arrives as `C:"`, `Resolve-TargetDir`
still repairs it, and the pin still survives ahead of it.

**The stale-PATH fallback.** Simulated by running with a `PATH` stripped of
`.local\bin` — the state Explorer is in after a mid-session install:

```
Get-Command claude visible? False
Found  : True
OnPath : False
Path   : C:\Users\yaira\.local\bin\claude.exe
pane   : C:\Users\yaira\.local\bin\claude.exe --dangerously-skip-permissions
```

**Install.** `install.ps1` completed, `csc` compiled the tray app, the tray
process is running and registered under `HKCU\...\Run`.

---

## What is still unverified

Two of these are ordinary "nobody has looked yet". One is a real observation with
no explanation, and it should not be lost.

**The live suite has not completed a clean run.** It was started twice from a
Claude Code session that was itself living in a Windows Terminal pane — and the
suite tiles, resizes and closes Terminal windows on the current virtual desktop.
Both attempts ended with the session gone. That is not evidence of a bug in the
suite; it is the suite doing what it says it does, to the wrong window. **Run it
from a plain PowerShell window, not from inside a terminal you care about:**

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\tests\run-tests.ps1 -IncludeLive
```

Before it was interrupted it got as far as `Live windows` and reported these,
which are worth knowing about:

* `a nine-pane grid really opens, and really is nine panes` — **PASS**
* `a pane really opens in a folder whose name needs quoting` — **PASS**
* `arranging leaves every terminal inside the work area` — **FAIL**, on
  `arranging closed a window`: a window present before `arrange-terminals.ps1`
  ran was not found afterwards.

**That last one is unexplained.** `arrange-terminals.ps1` only calls `ShowWindow`
and `MoveWindow`; it has no path that closes anything. The plausible readings are
that `Find` legitimately stopped matching a window mid-move (it filters on
visible, non-minimized, non-cloaked, non-empty title), or that a window really did
go away for an unrelated reason — a probe window from an earlier test still
winding down, despite the wait the test does first. It was seen once, on a run
that also had finding 3 corrupting the tests before it. **Re-run and see whether
it reproduces before treating it as a bug.**

**Parts 3, 4 and 5 have not been run at all.** Everything below is untouched by
this pass:

* the tray menu — whether it opens, and whether the two launch items re-read the
  agent and grid size each time it does
* **the Settings window** — TESTING.md calls this "the least-verified part of the
  whole project", a WinForms dialog whose event wiring has never run. It still has
  not. Its resolver call was changed in this pass, which is one more reason to
  open it. It has never been opened on any machine.
* the three global hotkeys, and the balloon tip when another app owns a combo
* the context menu clicked by hand, in Explorer, under *Show more options*
* `Arrange Terminals`, and both `Quit` submenu actions
* `uninstall.ps1` — including that running it twice is harmless

**Only one agent is installed here.** Every Codex assertion in this pass is about
what the code *would* do, taken from the not-found path. Nobody has watched a
Codex pane open.

---

## Changed files

| | |
|---|---|
| `scripts/open-in-claude.ps1` | finding 1; the not-found path; `-DryRun` no longer stops behind a modal; centres and sizes the new window |
| `scripts/steroids-grid.ps1` | the same, plus `$Columns`/`$Rows`; finding 5 |
| `scripts/steroids-common.ps1` | `Resolve-AgentCommand`, `Get-PersistedPathDirectory`, `Get-AgentMissingMessage`; `Get-AgentPaneCommand -Executable`; `Show-SteroidsError -Quiet`; the PowerShell pane host, `ConvertTo-PowerShellCommand`, `Set-NewTerminalWindowShape` |
| `scripts/steroids-settings.ps1` | status line and `Runs:` line now come from the shared resolver |
| `install.ps1` | finding 4 |
| `tests/run-tests.ps1` | finding 3; the off-by-two in the drive-root test; +35 tests (64 → 99) |

One test was wrong rather than the code: `a drive root keeps both its backslash
and the pinned agent` read `CommandLineToArgvW`'s output from index 1, which is
the launcher's own `-File` switch, and reported it as a missing pin. The product
was doing the right thing all along. Indices now start after `-File` and its
script, and the argument count is asserted so the next off-by-two says so.

## Note on `-DryRun`

`-DryRun` used to stop at a modal message box if Windows Terminal or the agent was
missing, which is a hang rather than a message to anything unattended. It now
reports the same text as a warning and carries on building the command line, so
`-DryRun` is a true "tell me what you would run" — which is how TESTING.md's
troubleshooting section already described it, and what makes the pinned-agent
tests runnable on a machine that has only one agent.
