# Claude Code — Steroids Mode (Windows)
# Opens 9 Claude Code sessions in a single, maximized Windows Terminal window,
# arranged as a 3x3 grid of panes. Each pane runs:
#   claude --dangerously-skip-permissions
#
# Usage: steroids-grid.ps1 "<folder>" [-Columns 3] [-Rows 3]
#        (folder defaults to the user profile folder)
#
# Want a 2x2 or 4x4 swarm instead? Pass -Columns/-Rows — the split maths below
# is general, nothing is hard-coded to nine.

param(
    [string]$Dir = $env:USERPROFILE,
    [ValidateRange(1, 8)][int]$Columns = 3,
    [ValidateRange(1, 8)][int]$Rows = 3,

    # Return the Windows Terminal command line instead of launching it — handy
    # for checking a custom grid before nine agents land on your machine.
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot 'steroids-common.ps1')

$Dir = Resolve-TargetDir $Dir

if (-not (Test-WindowsTerminal)) {
    Show-SteroidsError "Windows Terminal (wt.exe) was not found.`n`nInstall it from the Microsoft Store: https://aka.ms/terminal"
    exit 1
}
if (-not (Test-ClaudeCli)) {
    Show-SteroidsError "The Claude Code CLI was not found on your PATH.`n`nInstall it from https://claude.com/claude-code and reopen Explorer so it picks up the new PATH."
    exit 1
}

$run = Get-ClaudePaneCommand
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
for ($i = 1; $i -lt $Columns; $i++) {
    Add-Split '-V' (($Columns - $i) / ($Columns - $i + 1))
}

# 2) Same trick vertically inside each column, walking right-to-left. After the
#    last row of a column the focus sits in its bottom pane, so move-focus left
#    lands in the next (still unsplit, full-height) column.
for ($c = $Columns; $c -ge 1; $c--) {
    for ($j = 1; $j -lt $Rows; $j++) {
        Add-Split '-H' (($Rows - $j) / ($Rows - $j + 1))
    }
    if ($c -gt 1) { Add-MoveLeft }
}

# -w new: never hijack a terminal you are already working in.
# -M     : maximize, so the grid actually covers the screen the way it does on
#          macOS instead of cramming nine panes into a default-sized window.
$wtArgs = @('-w', 'new', '-M') + $wt.ToArray()

if ($DryRun) { return $wtArgs }

Start-WindowsTerminal $wtArgs
