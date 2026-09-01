# Claude Code — Steroids Mode (Windows)
# Arranges all Windows Terminal windows on the CURRENT virtual desktop into a
# grid sized to the window count: 4 -> 2x2, 9 -> 3x3, 10 -> 4x3, 16 -> 4x4 ...
#
# Minimized windows, and windows on other virtual desktops, are left alone.
#
# Usage: arrange-terminals.ps1 [-ProcessName WindowsTerminal] [-WhatIf]
#        (no arguments needed, no admin rights)

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ProcessName = 'WindowsTerminal'
)

. (Join-Path $PSScriptRoot 'steroids-common.ps1')

Initialize-SteroidsInterop

$wins = @([SteroidsWin]::Find($ProcessName, $true))
$n = $wins.Count
if ($n -eq 0) {
    Write-Host "No $ProcessName windows on this desktop"
    return
}

$area = [SteroidsWin]::WorkArea()

# Square-ish, wider before taller: 4 -> 2x2, 9 -> 3x3, 10 -> 4x3, 16 -> 4x4.
$cols = [int][Math]::Ceiling([Math]::Sqrt($n))
$rows = [int][Math]::Ceiling($n / [double]$cols)

# The same cell arithmetic Steroids Mode lays its own windows out with, so a
# grid you opened and a grid you retiled land on exactly the same pixels.
$plan = @(Get-SteroidsGridPlan -Columns $cols -Rows $rows `
              -Left $area.Left -Top $area.Top `
              -Width ($area.Right - $area.Left) -Height ($area.Bottom - $area.Top))

for ($i = 0; $i -lt $n; $i++) {
    $cell = $plan[$i]
    if ($PSCmdlet.ShouldProcess("window $($i + 1) of $n",
            "move to $($cell.X),$($cell.Y) ($($cell.Width)x$($cell.Height))")) {
        [SteroidsWin]::Place($wins[$i], $cell.X, $cell.Y, $cell.Width, $cell.Height)
    }
}

Write-Host "Arranged $n windows in a ${cols}x${rows} grid"
