# Claude Code — Steroids Mode (Windows)
# Opens a single Claude Code session in the given folder, using Windows Terminal.
#
# Usage: open-in-claude.ps1 "<folder>"   (defaults to the user profile folder)

param(
    [string]$Dir = $env:USERPROFILE,

    # Return the Windows Terminal command line instead of launching it.
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

# -w new forces a brand-new window: without it, a "windowingBehavior" of
# useExisting would drop this session into the terminal you are already working
# in, which is never what a right-click on a folder means.
$wtArgs = @('-w', 'new', 'new-tab', '-d', $Dir) + (Get-ClaudePaneCommand)

if ($DryRun) { return $wtArgs }

Start-WindowsTerminal $wtArgs
