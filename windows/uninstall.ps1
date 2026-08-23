# Claude Code — Steroids Mode :: Windows uninstaller
# Removes everything install.ps1 created. Nothing here needs admin rights.
#
#   powershell -ExecutionPolicy Bypass -File .\uninstall.ps1

[CmdletBinding()]
param()

$removed = @()

foreach ($root in @('Directory', 'Directory\Background')) {
    # Every key this project has ever registered, the pre-2.1 pair included --
    # a leftover entry keeps answering right-clicks long after its script is gone.
    foreach ($key in @('OpenAgentHere', 'AgentSteroids',
                       'OpenInClaude', 'ClaudeSteroids',
                       'OpenInCodex', 'CodexSteroids')) {
        $path = "HKCU:\Software\Classes\$root\shell\$key"
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            $removed += "context menu: $root\$key"
        }
    }
}

if (Get-Process -Name 'steroids-tray' -ErrorAction SilentlyContinue) {
    Stop-Process -Name 'steroids-tray' -Force -ErrorAction SilentlyContinue
    # Wait for the process to actually go: Windows keeps a lock on a running
    # exe, so deleting the folder below fails while it is still winding down.
    for ($i = 0; $i -lt 25; $i++) {
        if (-not (Get-Process -Name 'steroids-tray' -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 200
    }
    $removed += 'tray app (stopped)'
}

$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if ((Get-ItemProperty -Path $runKey -Name 'ClaudeSteroidsTray' -ErrorAction SilentlyContinue)) {
    Remove-ItemProperty -Path $runKey -Name 'ClaudeSteroidsTray' -ErrorAction SilentlyContinue
    $removed += 'login entry'
}

$configDir = Join-Path $env:APPDATA 'claude-code-steroids'
if (Test-Path $configDir) {
    Remove-Item -Path $configDir -Recurse -Force -ErrorAction SilentlyContinue
    $removed += "settings: $configDir"
}

$dest = Join-Path $env:LOCALAPPDATA 'claude-code-steroids'
if (Test-Path $dest) {
    Remove-Item -Path $dest -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $dest) {
        Write-Host "Could not delete $dest - is the tray app still running?" -ForegroundColor Yellow
    } else {
        $removed += "files: $dest"
    }
}

if ($removed.Count -eq 0) {
    Write-Host 'Nothing to uninstall - it was not installed.'
} else {
    $removed | ForEach-Object { Write-Host "  removed $_" }
    Write-Host 'Uninstalled.' -ForegroundColor Green
}
