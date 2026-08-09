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
$cw = [int](($area.Right - $area.Left) / $cols)
$ch = [int](($area.Bottom - $area.Top) / $rows)

for ($i = 0; $i -lt $n; $i++) {
    $x = $area.Left + ($i % $cols) * $cw
    $y = $area.Top + [int][Math]::Floor($i / $cols) * $ch
    if ($PSCmdlet.ShouldProcess("window $($i + 1) of $n", "move to $x,$y (${cw}x${ch})")) {
        [SteroidsWin]::Place($wins[$i], $x, $y, $cw, $ch)
    }
}

Write-Host "Arranged $n windows in a ${cols}x${rows} grid"
