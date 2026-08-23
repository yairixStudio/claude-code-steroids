# Claude Code — Steroids Mode (Windows)
# Opens a single session of the agent selected in Settings — Claude Code or
# OpenAI Codex — in the given folder, using Windows Terminal.
#
# Usage: open-in-claude.ps1 "<folder>" [-Agent claude|codex]
#        (folder defaults to the user profile folder; -Agent pins one agent for
#         this run, which is what the per-agent context-menu entries pass)

param(
    [string]$Dir = $env:USERPROFILE,

    # Pin one agent for this run, whatever Settings says -- what the
    # per-agent context-menu entries pass. Empty means "follow Settings".
    [ValidateSet('', 'claude', 'codex')]
    [string]$Agent = '',

    # Return the Windows Terminal command line instead of launching it.
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot 'steroids-common.ps1')

$Dir = Resolve-TargetDir $Dir

if (-not (Test-WindowsTerminal)) {
    Show-SteroidsError "Windows Terminal (wt.exe) was not found.`n`nInstall it from the Microsoft Store: https://aka.ms/terminal"
    exit 1
}
$config = Get-SteroidsConfig
if ($Agent) { $config.Agent = $Agent }
$agent = Get-SteroidsAgent $config.Agent
if (-not (Test-AgentCli $agent)) {
    Show-SteroidsError "$($agent.Label) was not found on your PATH.`n`nInstall it with:`n    $($agent.InstallHint)`n`nThen reopen Explorer so it picks up the new PATH, or pick the other agent in the tray menu's Settings."
    exit 1
}

# -w new forces a brand-new window: without it, a "windowingBehavior" of
# useExisting would drop this session into the terminal you are already working
# in, which is never what a right-click on a folder means.
$wtArgs = @('-w', 'new', 'new-tab', '-d', $Dir) + (Get-AgentPaneCommand $config)

if ($DryRun) { return $wtArgs }

Start-WindowsTerminal $wtArgs
