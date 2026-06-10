# Claude Code — Steroids Mode (Windows)
# Opens 9 Claude Code sessions in a single Windows Terminal window, arranged as a
# 3x3 grid of panes. Each pane runs: claude --dangerously-skip-permissions
#
# Usage: steroids-grid.ps1 "<folder>"

param(
    [Parameter(Mandatory = $true)]
    [string]$Dir
)

if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Windows Terminal (wt.exe) was not found. Install it from the Microsoft Store.",
        "Claude Code — Steroids") | Out-Null
    exit 1
}

# The command each pane runs. cmd /k keeps the pane alive after Claude exits.
$run = @("cmd", "/k", "claude --dangerously-skip-permissions")

# Build an even 3x3 grid:
#   1. Three equal columns (two vertical splits with explicit sizes).
#   2. Each column split into three equal rows (two horizontal splits each),
#      walking left with move-focus between columns.
$wt = New-Object System.Collections.Generic.List[string]

function Add-Pane([string]$splitFlag, [string]$size) {
    if ($splitFlag) {
        $wt.Add(";"); $wt.Add("split-pane"); $wt.Add($splitFlag)
        if ($size) { $wt.Add("--size"); $wt.Add($size) }
        $wt.Add("-d"); $wt.Add($Dir); $wt.AddRange([string[]]$run)
    } else {
        $wt.Add("new-tab"); $wt.Add("-d"); $wt.Add($Dir); $wt.AddRange([string[]]$run)
    }
}
function Move-Left() { $wt.Add(";"); $wt.Add("move-focus"); $wt.Add("left") }

# Columns
Add-Pane $null  $null      # P1  (full width)
Add-Pane "-V"   "0.6667"   # split off the right 2/3
Add-Pane "-V"   "0.5"      # split that into two -> three equal columns (focus = right col)

# Right column -> 3 rows
Add-Pane "-H"   "0.6667"
Add-Pane "-H"   "0.5"
Move-Left                  # -> middle column
Add-Pane "-H"   "0.6667"
Add-Pane "-H"   "0.5"
Move-Left                  # -> left column
Add-Pane "-H"   "0.6667"
Add-Pane "-H"   "0.5"

Start-Process wt.exe -ArgumentList $wt.ToArray()
