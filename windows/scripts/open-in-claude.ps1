# Claude Code — Steroids Mode (Windows)
# Opens a single Claude Code session in the given folder, using Windows Terminal.
#
# Usage: open-in-claude.ps1 "<folder>"

param(
    [Parameter(Mandatory = $true)]
    [string]$Dir
)

if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Windows Terminal (wt.exe) was not found. Install it from the Microsoft Store.",
        "Claude Code — Steroids") | Out-Null
    exit 1
}

# Open Windows Terminal in $Dir, running Claude inside cmd (/k keeps it open).
# NOTE: uses --dangerously-skip-permissions ("YOLO mode"). Only point at folders you trust.
Start-Process wt.exe -ArgumentList @("-d", $Dir, "cmd", "/k", "claude --dangerously-skip-permissions")
