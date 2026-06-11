# Claude Code — Steroids Mode :: Windows uninstaller
$ErrorActionPreference = "SilentlyContinue"

foreach ($root in @("Directory", "Directory\Background")) {
    Remove-Item -Path "HKCU:\Software\Classes\$root\shell\OpenInClaude"  -Recurse -Force
    Remove-Item -Path "HKCU:\Software\Classes\$root\shell\ClaudeSteroids" -Recurse -Force
}

Stop-Process -Name "steroids-tray" -Force
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ClaudeSteroidsTray"

Remove-Item -Path (Join-Path $env:LOCALAPPDATA "claude-code-steroids") -Recurse -Force

Write-Host "Uninstalled." -ForegroundColor Green
