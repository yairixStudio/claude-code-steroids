# Claude Code — Steroids Mode (Windows)
# Tears a swarm down again. The counterpart to macOS's close-terminals.sh.
#
# Usage: close-terminals.ps1 [-Mode agents|desktop] [-WhatIf]
#   agents   (default) end every agent session hosted by Windows Terminal --
#            Claude Code or OpenAI Codex, whichever a pane happens to hold, so a
#            mixed desktop tears down in one go -- on any virtual desktop,
#            leaving other panes alone, and leaving the pane this script is
#            running in alone too, so closing a swarm from inside one of its own
#            sessions does not close that session. ("claude" is the old name for
#            this mode and still works.)
#   desktop  close all Windows Terminal windows on the CURRENT virtual desktop.
#            All of them: one Windows Terminal process owns every window, so a
#            window cannot be attributed to the pane running this script the way
#            claude mode can. Run it from the tray, not from a terminal you want
#            to keep.
#
# Neither mode disturbs a session with a package install in flight: claude mode
# spares that pane, desktop mode defers the sweep entirely. Killing Claude's own
# `npm install -g` partway through breaks the install for good, not just for now
# -- see Test-ShellRunsPackageInstall in steroids-common.ps1.
#
# Neither mode ever produces a confirmation dialog:
#   * Claude panes are ended with an exit code of 0, which is what Terminal's
#     default "graceful" close-on-exit waits for — the pane retires itself, and
#     a window whose last pane goes closes itself too.
#   * Whole windows are closed with WM_CLOSE, which Terminal handles by tearing
#     the panes down for us.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('agents', 'claude', 'desktop')]
    [string]$Mode = 'agents',

    [string]$ProcessName = 'WindowsTerminal'
)

. (Join-Path $PSScriptRoot 'steroids-common.ps1')

Initialize-SteroidsInterop

if ($Mode -ne 'desktop') {
    $found = @(Get-TerminalPaneShell -ProcessName $ProcessName | Where-Object { Test-ShellRunsAgent $_ })

    # Never sweep away the pane we are running in. Invoked from the tray there
    # is no such pane; invoked from a Claude session in Windows Terminal this is
    # the difference between closing the swarm and closing yourself.
    $mine = @($found | Where-Object { -not (Test-ShellHostsSelf $_) })
    $self = $found.Count - $mine.Count

    # Nor a pane that is updating Claude -- ending that one costs the whole
    # install, permanently. See Test-ShellRunsPackageInstall.
    $busy    = @($mine | Where-Object { Test-ShellRunsPackageInstall $_ })
    $targets = @($mine | Where-Object { -not (Test-ShellRunsPackageInstall $_) })
    $note    = if ($busy.Count -gt 0) { ", leaving $($busy.Count) mid-install" } else { '' }

    if ($targets.Count -eq 0) {
        if ($busy.Count -gt 0) {
            Write-Host "Left $($busy.Count) agent session(s) alone - still installing"
        } elseif ($self -gt 0) {
            Write-Host 'The only agent session running is this one - left alone'
        } else {
            Write-Host 'No agent sessions running in Windows Terminal'
        }
        return
    }
    $ended = 0
    foreach ($t in $targets) {
        if ($PSCmdlet.ShouldProcess("pid $($t.ProcessId) ($($t.Name))", 'end agent session')) {
            Stop-PaneSession $t
            $ended++
        }
    }
    if ($self -gt 0) {
        Write-Host "Closed $ended agent session(s), leaving this one running$note"
    } else {
        Write-Host "Closed $ended agent session(s)$note"
    }
    return
}

# --- desktop mode ---------------------------------------------------------
# WM_CLOSE tears the panes down for us, which is exactly as fatal to an install
# in flight as ending it outright. Agent mode can spare the one pane that is
# updating; here a pane cannot be told which window it belongs to, so the only
# safe answer is to leave the sweep for a few seconds. An install is a two-minute
# window that comes round rarely; a bricked one waits for a hand to fix it.
$installing = @(Get-TerminalPaneShell -ProcessName $ProcessName |
                Where-Object { Test-ShellRunsPackageInstall $_ })
if ($installing.Count -gt 0) {
    Write-Host "Closed nothing - $($installing.Count) session(s) still installing (pid $($installing.ProcessId -join ', ')). Try again once they finish."
    return
}

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
