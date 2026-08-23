# Claude Code — Steroids Mode (Windows)
# Opens a grid of agent sessions — Claude Code or OpenAI Codex, whichever is
# selected in Settings — as panes in a single, maximized Windows Terminal
# window. 3x3 by default; Settings can make it anything from 1x1 to 8x8.
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

    # Return the Windows Terminal command line instead of launching it — handy
    # for checking a custom grid before nine agents land on your machine.
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot 'steroids-common.ps1')

$Dir = Resolve-TargetDir $Dir

# -DryRun is "tell me what you would run", so it reports a problem and carries
# on building the command line instead of stopping behind a modal dialog that
# nothing unattended can dismiss.
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
$wt = New-Object System.Collections.Generic.List[string]

# wt's --size is a fraction of the pane being split, and it always parses with a
# dot — so format it invariantly rather than with the current locale, which
# would emit "0,6667" on a comma-decimal system and make wt reject the split.
function Format-Size([double]$value) {
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.####}', $value)
}

function Add-FirstPane {
    $wt.Add('new-tab'); $wt.Add('-d'); $wt.Add($Dir); $wt.AddRange([string[]]$run)
}
function Add-Split([string]$direction, [double]$size) {
    $wt.Add(';'); $wt.Add('split-pane'); $wt.Add($direction)
    $wt.Add('--size'); $wt.Add((Format-Size $size))
    $wt.Add('-d'); $wt.Add($Dir); $wt.AddRange([string[]]$run)
}
function Add-MoveLeft {
    $wt.Add(';'); $wt.Add('move-focus'); $wt.Add('left')
}

# 1) Slice the window into $Columns equal columns. Splitting off (n-1)/n of the
#    remaining pane each time leaves every column exactly 1/$Columns wide, and
#    ends with the focus in the rightmost one.
Add-FirstPane
for ($i = 1; $i -lt $gridColumns; $i++) {
    Add-Split '-V' (($gridColumns - $i) / ($gridColumns - $i + 1))
}

# 2) Same trick vertically inside each column, walking right-to-left. After the
#    last row of a column the focus sits in its bottom pane, so move-focus left
#    lands in the next (still unsplit, full-height) column.
for ($c = $gridColumns; $c -ge 1; $c--) {
    for ($j = 1; $j -lt $gridRows; $j++) {
        Add-Split '-H' (($gridRows - $j) / ($gridRows - $j + 1))
    }
    if ($c -gt 1) { Add-MoveLeft }
}

# -w new: never hijack a terminal you are already working in.
# -M     : maximize, so the grid actually covers the screen the way it does on
#          macOS instead of cramming nine panes into a default-sized window.
$wtArgs = @('-w', 'new', '-M') + $wt.ToArray()

if ($DryRun) { return $wtArgs }

Start-WindowsTerminal $wtArgs
