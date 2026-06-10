# Claude Code — Steroids Mode :: Windows uninstaller
$ErrorActionPreference = "SilentlyContinue"

foreach ($root in @("Directory", "Directory\Background")) {
    Remove-Item -Path "HKCU:\Software\Classes\$root\shell\OpenInClaude"  -Recurse -Force
    Remove-Item -Path "HKCU:\Software\Classes\$root\shell\ClaudeSteroids" -Recurse -Force
}

Remove-Item -Path (Join-Path $env:LOCALAPPDATA "claude-code-steroids") -Recurse -Force

Write-Host "Uninstalled." -ForegroundColor Green
