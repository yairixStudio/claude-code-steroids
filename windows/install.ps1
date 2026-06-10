# Claude Code — Steroids Mode :: Windows installer
# Adds two right-click context-menu items for folders:
#   "Open in Claude"  and  "Open in Claude — Steroids (9x)"
#
# Run in PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#
# No admin rights needed — everything goes under HKCU (current user).

$ErrorActionPreference = "Stop"

$dest = Join-Path $env:LOCALAPPDATA "claude-code-steroids"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $PSScriptRoot "scripts\*") $dest -Force

function Add-FolderMenu([string]$keyName, [string]$label, [string]$scriptFile) {
    $target = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest\$scriptFile`" `"%V`""

    # Right-click ON a folder, and right-click on a folder's empty background.
    foreach ($root in @("Directory", "Directory\Background")) {
        $base = "HKCU:\Software\Classes\$root\shell\$keyName"
        New-Item -Path $base -Force | Out-Null
        Set-ItemProperty -Path $base -Name "MUIVerb" -Value $label
        Set-ItemProperty -Path $base -Name "Icon"    -Value "powershell.exe"

        $cmd = Join-Path $base "command"
        New-Item -Path $cmd -Force | Out-Null
        Set-ItemProperty -Path $cmd -Name "(default)" -Value $target
    }
}

Add-FolderMenu "OpenInClaude"  "Open in Claude"                "open-in-claude.ps1"
Add-FolderMenu "ClaudeSteroids" "Open in Claude — Steroids (9x)" "steroids-grid.ps1"

Write-Host ""
Write-Host "Installed." -ForegroundColor Green
Write-Host "Right-click any folder (or inside one) to see the new menu items."
Write-Host "On Windows 11 they may appear under 'Show more options'."
Write-Host ""
Write-Host "Requires: Windows Terminal + Claude Code CLI on your PATH."
Write-Host "          https://claude.com/claude-code"
