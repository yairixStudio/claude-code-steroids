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

# -DryRun is "tell me what you would run", so it reports a problem and carries
# on building the command line instead of stopping behind a modal dialog that
# nothing unattended can dismiss.
if (-not (Test-WindowsTerminal)) {
    Show-SteroidsError "Windows Terminal (wt.exe) was not found.`n`nInstall it from the Microsoft Store: https://aka.ms/terminal" -Quiet:$DryRun
    if (-not $DryRun) { exit 1 }
}
$config = Get-SteroidsConfig
if ($Agent) { $config.Agent = $Agent }

# NOT $agent. PowerShell matches variable names case-insensitively, so $agent
# and the -Agent parameter above are one variable -- and assigning an object to
# it re-runs the parameter's [ValidateSet], which throws. $agent then stayed the
# string it already was, $agent.Bin came back $null, and every launch died with
# "was not found on your PATH" on machines where the CLI was right there on it.
# Keep this name distinct.
$selected = Get-SteroidsAgent $config.Agent
if (-not (Test-AgentCli $selected)) {
    Show-SteroidsError "$($selected.Label) was not found on your PATH.`n`nInstall it with:`n    $($selected.InstallHint)`n`nThen reopen Explorer so it picks up the new PATH, or pick the other agent in the tray menu's Settings." -Quiet:$DryRun
    if (-not $DryRun) { exit 1 }
}

# -w new forces a brand-new window: without it, a "windowingBehavior" of
# useExisting would drop this session into the terminal you are already working
# in, which is never what a right-click on a folder means.
$wtArgs = @('-w', 'new', 'new-tab', '-d', $Dir) + (Get-AgentPaneCommand $config)

if ($DryRun) { return $wtArgs }

Start-WindowsTerminal $wtArgs
