# Claude Code — Steroids Mode (Windows)
# Tears a swarm down again. The counterpart to macOS's close-terminals.sh.
#
# Usage: close-terminals.ps1 [-Mode claude|desktop] [-WhatIf]
#   claude   (default) end every Claude session hosted by Windows Terminal, on
#            any virtual desktop, leaving other panes alone -- and leaving the
#            pane this script is running in alone too, so closing a swarm from
#            inside one of its own sessions does not close that session
#   desktop  close all Windows Terminal windows on the CURRENT virtual desktop.
#            All of them: one Windows Terminal process owns every window, so a
#            window cannot be attributed to the pane running this script the way
#            claude mode can. Run it from the tray, not from a terminal you want
#            to keep.
#
# Neither mode ever produces a confirmation dialog:
#   * Claude panes are ended with an exit code of 0, which is what Terminal's
#     default "graceful" close-on-exit waits for — the pane retires itself, and
#     a window whose last pane goes closes itself too.
#   * Whole windows are closed with WM_CLOSE, which Terminal handles by tearing
#     the panes down for us.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('claude', 'desktop')]
    [string]$Mode = 'claude',

    [string]$ProcessName = 'WindowsTerminal'
)

. (Join-Path $PSScriptRoot 'steroids-common.ps1')

Initialize-SteroidsInterop

if ($Mode -eq 'claude') {
    $claude = @(Get-TerminalPaneShell -ProcessName $ProcessName | Where-Object { Test-ShellRunsClaude $_ })

    # Never sweep away the pane we are running in. Invoked from the tray there
    # is no such pane; invoked from a Claude session in Windows Terminal this is
    # the difference between closing the swarm and closing yourself.
    $targets = @($claude | Where-Object { -not (Test-ShellHostsSelf $_) })
    $self    = $claude.Count - $targets.Count

    if ($targets.Count -eq 0) {
        if ($self -gt 0) {
            Write-Host 'The only Claude session running is this one - left alone'
        } else {
            Write-Host 'No Claude sessions running in Windows Terminal'
        }
        return
    }
    $ended = 0
    foreach ($t in $targets) {
        if ($PSCmdlet.ShouldProcess("pid $($t.ProcessId) ($($t.Name))", 'end Claude session')) {
            Stop-PaneSession $t
            $ended++
        }
    }
    if ($self -gt 0) {
        Write-Host "Closed $ended Claude session(s), leaving this one running"
    } else {
        Write-Host "Closed $ended Claude session(s)"
    }
    return
}

# --- desktop mode ---------------------------------------------------------
$here = @([SteroidsWin]::Find($ProcessName, $true))
if ($here.Count -eq 0) {
    Write-Host "No $ProcessName windows on this desktop"
    return
}

$closed = 0
foreach ($h in $here) {
    if ($PSCmdlet.ShouldProcess("window $h", 'close')) {
        [SteroidsWin]::CloseWindow($h)
        $closed++
    }
}
Write-Host "Closed $closed window(s) on this desktop"
