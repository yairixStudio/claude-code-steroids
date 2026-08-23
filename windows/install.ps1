# Claude Code — Steroids Mode :: Windows installer
# Adds two right-click context-menu items for folders:
#   "Open in Claude"  and  "Open in Claude — Steroids (9x)"
# plus a tray app with global hotkeys.
#
# Run in PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#
# No admin rights needed — everything goes under HKCU (current user).

[CmdletBinding()]
param(
    # Skip compiling the tray app; context-menu entries only.
    [switch]$NoTray
)

$ErrorActionPreference = 'Stop'

$dest = Join-Path $env:LOCALAPPDATA 'claude-code-steroids'
$scriptSource = Join-Path $PSScriptRoot 'scripts'

# Settings live under APPDATA, not beside the scripts, so that reinstalling --
# which clears the script folder -- never resets the agent you picked.
$configDir = Join-Path $env:APPDATA 'claude-code-steroids'
$config = Join-Path $configDir 'config.json'

Write-Host 'Installing Claude Code — Steroids Mode (Windows)...'

# ---------------------------------------------------------------- 1. scripts --
# Clear the old scripts out first: a copy on its own leaves anything renamed or
# dropped since the last install sitting in place, and the tray app would go on
# calling a script this version no longer ships.
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Remove-Item (Join-Path $dest '*.ps1') -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $scriptSource '*.ps1') $dest -Force

# ------------------------------------------------------------- 1b. settings --
# Seeded only when absent, so re-running the installer to pick up a new version
# leaves your choices alone.
New-Item -ItemType Directory -Force -Path $configDir | Out-Null
if (-not (Test-Path -LiteralPath $config)) {
    @'
{
    "version":  1,
    "agent":  "claude",
    "columns":  3,
    "rows":  3,
    "yolo":  true
}
'@ | Set-Content -LiteralPath $config -Encoding UTF8
}

# ----------------------------------------------------------- 2. context menu --
function Add-FolderMenu {
    param([string]$KeyName, [string]$Label, [string]$ScriptFile, [string]$Agent = '')

    # "%V" is the clicked folder, and it MUST be the last thing on the line.
    # Right-click a drive root and Explorer expands it to C:\ -- whose trailing
    # backslash escapes the closing quote, so CommandLineToArgvW swallows
    # everything after it into the same argument. With the pin trailing, a
    # right-click on C:\ produced the single argument  C:" -Agent claude  : the
    # pin silently lost, and a path too mangled for Resolve-TargetDir to repair.
    # Named parameters bind before positional ones, so -Agent leads and "%V"
    # still lands on -Dir.
    $pin = if ($Agent) { "-Agent $Agent " } else { '' }
    $target = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ' +
              "`"$dest\$ScriptFile`" $pin`"%V`""

    # Right-click ON a folder, and right-click on a folder's empty background.
    foreach ($root in @('Directory', 'Directory\Background')) {
        $base = "HKCU:\Software\Classes\$root\shell\$KeyName"
        New-Item -Path $base -Force | Out-Null
        Set-ItemProperty -Path $base -Name 'MUIVerb' -Value $Label
        Set-ItemProperty -Path $base -Name 'Icon'    -Value 'powershell.exe'

        $cmd = Join-Path $base 'command'
        New-Item -Path $cmd -Force | Out-Null
        Set-ItemProperty -Path $cmd -Name '(default)' -Value $target
    }
}

# Six entries, mirroring the macOS Quick Actions: a neutral pair that follows
# whichever agent Settings names, plus a pinned pair per agent so a right-click
# can send one folder to Claude and the next to Codex without going through
# Settings. On Windows 11 they live under "Show more options".
Add-FolderMenu 'OpenAgentHere'  'Open Coding Agent Here'         'open-in-claude.ps1'
Add-FolderMenu 'AgentSteroids'  'Steroids Mode (9x Grid)'        'steroids-grid.ps1'
Add-FolderMenu 'OpenInClaude'   'Open in Claude'                 'open-in-claude.ps1' 'claude'
Add-FolderMenu 'ClaudeSteroids' 'Open in Claude — Steroids (9x)' 'steroids-grid.ps1'  'claude'
Add-FolderMenu 'OpenInCodex'    'Open in Codex'                  'open-in-claude.ps1' 'codex'
Add-FolderMenu 'CodexSteroids'  'Open in Codex — Steroids (9x)'  'steroids-grid.ps1'  'codex'

# -------------------------------------------------------------- 3. tray app --
# One lean exe compiled locally with the csc.exe that ships with Windows,
# started at login via the HKCU Run key.
$trayInstalled = $false
if (-not $NoTray) {
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $csc)) {
        $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    }

    if (Test-Path $csc) {
        Write-Host 'Compiling tray app (Ctrl+Alt+C session / Ctrl+Alt+S steroids / Ctrl+Alt+T arrange)...'
        Stop-Process -Name 'steroids-tray' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 400

        $exe = Join-Path $dest 'steroids-tray.exe'
        $out = & $csc /nologo /target:winexe /out:"$exe" `
                 /r:System.Windows.Forms.dll /r:System.Drawing.dll `
                 (Join-Path $scriptSource 'steroids-tray.cs') 2>&1

        # csc reports failures through its exit code; without this check a
        # broken build would still be registered to run at every login.
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) {
            Write-Host 'Tray app failed to compile - continuing without it.' -ForegroundColor Yellow
            $out | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
        } else {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
                -Name 'ClaudeSteroidsTray' -Value "`"$exe`""
            Start-Process $exe
            $trayInstalled = $true
        }
    } else {
        Write-Host 'csc.exe not found - skipping the tray app and hotkeys.' -ForegroundColor Yellow
    }
}

# ----------------------------------------------------------------- 4. report --
Write-Host ''
Write-Host 'Installed.' -ForegroundColor Green
Write-Host 'Right-click any folder (or inside one) to see the new menu items.'
Write-Host "On Windows 11 they may appear under 'Show more options'."

if ($trayInstalled) {
    Write-Host ''
    Write-Host 'Tray icon (by the clock) + global hotkeys, from any app:'
    Write-Host '  Ctrl+Alt+C  New Session       (one window, in your user folder)'
    Write-Host '  Ctrl+Alt+S  Steroids Mode     (a grid of panes, in your user folder)'
    Write-Host '  Ctrl+Alt+T  Arrange Terminals (grid: 4 -> 2x2, 9 -> 3x3, 10 -> 4x3 ...)'
    Write-Host "The tray menu's Quit submenu closes a swarm again, without confirmation dialogs."
    Write-Host 'The tray app starts automatically at every login.'
}

Write-Host ''
Write-Host 'Settings - tray icon -> Settings... (three things, saved as you click):'
Write-Host '  Agent      Claude Code or OpenAI Codex. Every entry point above - hotkeys,'
Write-Host '             tray menu, Explorer right-click - runs whichever one is selected.'
Write-Host '  Grid       2x2 through 4x4 (the config file accepts anything up to 8x8).'
Write-Host '  Autonomy   Skip approval prompts, on or off. Off passes no flag at all, so'
Write-Host '             each CLI behaves exactly as it does when you run it yourself.'
Write-Host "  Stored in $config - reinstalling keeps it."

Write-Host ''
if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
    Write-Host 'Windows Terminal was not found - install it from https://aka.ms/terminal' -ForegroundColor Yellow
}
$haveAgent = $false
foreach ($cli in @(
    @{ Name = 'claude'; Label = 'Claude Code';  Hint = 'npm i -g @anthropic-ai/claude-code' },
    @{ Name = 'codex';  Label = 'OpenAI Codex'; Hint = 'npm i -g @openai/codex' })) {
    if (Get-Command $cli.Name -ErrorAction SilentlyContinue) { $haveAgent = $true }
}
if (-not $haveAgent) {
    Write-Host 'Neither agent CLI was found on your PATH. Install at least one:' -ForegroundColor Yellow
    Write-Host '  Claude Code   npm i -g @anthropic-ai/claude-code' -ForegroundColor Yellow
    Write-Host '  OpenAI Codex  npm i -g @openai/codex' -ForegroundColor Yellow
}
