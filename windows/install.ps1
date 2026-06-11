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

# Tray app + global hotkeys (Ctrl+Alt+C / Ctrl+Alt+S / Ctrl+Alt+T) — one lean
# exe compiled locally with the csc.exe that ships with Windows, started at
# login via HKCU Run.
$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (Test-Path $csc) {
    Write-Host "Compiling tray app (Ctrl+Alt+C session / Ctrl+Alt+S steroids / Ctrl+Alt+T arrange)..."
    Stop-Process -Name "steroids-tray" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
    & $csc /nologo /target:winexe /out:"$dest\steroids-tray.exe" `
        /r:System.Windows.Forms.dll /r:System.Drawing.dll `
        (Join-Path $PSScriptRoot "scripts\steroids-tray.cs")
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name "ClaudeSteroidsTray" -Value "`"$dest\steroids-tray.exe`""
    Start-Process "$dest\steroids-tray.exe"
} else {
    Write-Host "csc.exe not found - skipping the tray app and hotkeys." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Installed." -ForegroundColor Green
Write-Host "Right-click any folder (or inside one) to see the new menu items."
Write-Host "On Windows 11 they may appear under 'Show more options'."
Write-Host ""
Write-Host "Tray icon (by the clock) + global hotkeys, from any app:"
Write-Host "  Ctrl+Alt+C  New Claude Session       (one window, in your user folder)"
Write-Host "  Ctrl+Alt+S  Steroids Mode (3x3 grid) (nine panes, in your user folder)"
Write-Host "  Ctrl+Alt+T  Arrange Terminals        (grid: 4 -> 2x2, 9 -> 3x3, 10 -> 4x3 ...)"
Write-Host "The tray app starts automatically at every login."
Write-Host ""
Write-Host "Requires: Windows Terminal + Claude Code CLI on your PATH."
Write-Host "          https://claude.com/claude-code"
