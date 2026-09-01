# Claude Code — Steroids Mode (Windows)
# Opens a grid of agent sessions — Claude Code or OpenAI Codex, whichever is
# selected in Settings — each in its own Windows Terminal window, tiled to fill
# the screen. 3x3 by default; Settings can make it anything from 1x1 to 8x8.
#
# One window per session, not one window split into panes. They look the same on
# screen and behave nothing alike: a pane belongs to its window, so closing a
# single session, dragging one to the second monitor, or maximizing the one you
# are reading is impossible — the only thing a pane grid can do is close all
# nine at once. This is what macOS has always done, and it is what makes each
# session yours to keep or be rid of on its own.
#
# Usage: steroids-grid.ps1 "<folder>" [-Agent claude|codex] [-Columns 3] [-Rows 3]
#        (folder defaults to the user profile folder; -Columns/-Rows override
#         the configured grid for one run without changing the setting)

param(
    [string]$Dir = $env:USERPROFILE,

    # Pin one agent for this run, whatever Settings says -- what the
    # per-agent context-menu entries pass. Empty means "follow Settings".
    [ValidateSet('', 'claude', 'codex')]
    [string]$Agent = '',

    # 0 means "whatever Settings says" -- PowerShell evaluates default values
    # before the script body, so the config cannot be read here.
    [ValidateRange(0, 8)][int]$Columns = 0,
    [ValidateRange(0, 8)][int]$Rows = 0,

    # Describe the launch instead of performing it — handy for checking what a
    # grid would run before nine agents land on your machine. Reports the shape
    # and the Windows Terminal command line for ONE session, because every
    # window in the grid is launched with exactly those arguments and only where
    # each one lands differs.
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot 'steroids-common.ps1')

$Dir = Resolve-TargetDir $Dir

# -DryRun is "tell me what you would run", so it reports a problem and carries
# on building the command line instead of stopping behind a modal dialog.
if (-not (Test-WindowsTerminal)) {
    Show-SteroidsError "Windows Terminal (wt.exe) was not found.`n`nInstall it from the Microsoft Store: https://aka.ms/terminal" -Quiet:$DryRun
    if (-not $DryRun) { exit 1 }
}
$config = Get-SteroidsConfig
if ($Agent) { $config.Agent = $Agent }

# Local names, deliberately not $Columns/$Rows/$agent. A variable name matches
# its parameter case-insensitively, so writing back to one re-runs that
# parameter's validation attribute -- which is how assigning the agent object to
# $agent used to throw [ValidateSet] and turn every launch into "was not found
# on your PATH". The grid dimensions were the same trap waiting to be sprung.
$gridColumns = if ($Columns -eq 0) { $config.Columns } else { $Columns }
$gridRows    = if ($Rows    -eq 0) { $config.Rows }    else { $Rows }

$selected = Get-SteroidsAgent $config.Agent

$resolved = Resolve-AgentCommand $selected
if (-not $resolved.Found) {
    Show-SteroidsError (Get-AgentMissingMessage $selected) -Quiet:$DryRun
    if (-not $DryRun) { exit 1 }
}

$run = if ($resolved.OnPath) { Get-AgentPaneCommand $config }
       else { Get-AgentPaneCommand $config -Executable $resolved.Launch }

# One session's command line, launched once per cell.
#
# -w new is what makes each one a window of its own: without it a Terminal
# configured to reuse windows would drop every session into the same one as a
# tab, and a right-click on a folder would quietly become nine tabs in whatever
# terminal happened to be open.
#
# There is no -M here on purpose. Maximizing was how the old single-window grid
# filled the screen; nine maximized windows would sit on top of one another
# instead, so the grid places each one in its cell itself.
$wtArgs = @('-w', 'new', 'new-tab', '-d', $Dir) + $run

if ($DryRun) {
    # "Sessions" rather than "Count": PowerShell answers $plan.Count on a
    # one-element array holding an object that has its own Count with the
    # object's value, not the array's. Two readings of the same expression is
    # exactly the kind of trap the rest of this project keeps notes about.
    return [pscustomobject]@{
        Columns   = $gridColumns
        Rows      = $gridRows
        Sessions  = $gridColumns * $gridRows
        Arguments = $wtArgs
    }
}

[void](Start-SteroidsGrid -Arguments $wtArgs -Columns $gridColumns -Rows $gridRows)
