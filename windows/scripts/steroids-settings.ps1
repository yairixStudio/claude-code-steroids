# Claude Code - Steroids Mode (Windows)
# The Settings window, opened from the tray icon.
#
# Three controls, no OK button: a tray utility's settings should be a glance and
# a click, so every change writes the config file immediately. The scripts read
# it on each run, so the next hotkey press already uses the new value.
#
# This is a PowerShell script rather than part of the tray exe on purpose. The
# tray app is a thin launcher for .ps1 files; keeping the settings here means the
# config logic lives once, in steroids-common.ps1, where run-tests.ps1 can reach
# it -- instead of being reimplemented in C# where nothing can.
#
# Usage: steroids-settings.ps1        (no arguments)

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'steroids-common.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$config = Get-SteroidsConfig

# Column count, row count. Anything from 1x1 to 8x8 is legal in the config file;
# these are the shapes that actually tile a screen sensibly.
$gridChoices = @(
    [pscustomobject]@{ Columns = 2; Rows = 2 },
    [pscustomobject]@{ Columns = 3; Rows = 2 },
    [pscustomobject]@{ Columns = 3; Rows = 3 },
    [pscustomobject]@{ Columns = 4; Rows = 3 },
    [pscustomobject]@{ Columns = 4; Rows = 4 }
)

# ------------------------------------------------------------------ layout --

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = 'Claude Steroids - Settings'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.StartPosition   = 'CenterScreen'
$form.ClientSize      = New-Object System.Drawing.Size(520, 250)
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 9)
$form.TopMost         = $true   # launched from the tray, with no window to own it

function New-Caption {
    param([string]$Text, [int]$Top)

    $label           = New-Object System.Windows.Forms.Label
    $label.Text      = $Text
    $label.AutoSize  = $false
    $label.TextAlign = 'MiddleRight'
    $label.Location  = New-Object System.Drawing.Point(20, $Top)
    $label.Size      = New-Object System.Drawing.Size(80, 22)
    $label.ForeColor = [System.Drawing.SystemColors]::GrayText
    return $label
}

# A path and a command line are both read character by character, so both get a
# monospaced face.
$mono = New-Object System.Drawing.Font('Consolas', 9)

# -- Agent -------------------------------------------------------------------
$form.Controls.Add((New-Caption 'Agent' 20))

$agentButtons = @{}
$x = 112
foreach ($agent in $script:SteroidsAgents) {
    $radio           = New-Object System.Windows.Forms.RadioButton
    $radio.Text      = $agent.Label
    $radio.Location  = New-Object System.Drawing.Point($x, 20)
    $radio.Size      = New-Object System.Drawing.Size(150, 24)
    $radio.Checked   = ($agent.Id -eq $config.Agent)
    $radio.Tag       = $agent.Id
    $form.Controls.Add($radio)
    $agentButtons[$agent.Id] = $radio
    $x += 160
}

$statusLabel           = New-Object System.Windows.Forms.Label
$statusLabel.Location  = New-Object System.Drawing.Point(114, 48)
$statusLabel.Size      = New-Object System.Drawing.Size(386, 20)
$statusLabel.Font      = $mono
$statusLabel.AutoEllipsis = $true
$form.Controls.Add($statusLabel)

# -- Grid --------------------------------------------------------------------
$form.Controls.Add((New-Caption 'Grid' 84))

$gridBox               = New-Object System.Windows.Forms.ComboBox
$gridBox.DropDownStyle = 'DropDownList'
$gridBox.Location      = New-Object System.Drawing.Point(112, 82)
$gridBox.Size          = New-Object System.Drawing.Size(220, 24)
foreach ($choice in $gridChoices) {
    [void]$gridBox.Items.Add(
        ('{0} x {1}  -  {2} sessions' -f $choice.Columns, $choice.Rows, ($choice.Columns * $choice.Rows)))
}
$form.Controls.Add($gridBox)

# -- Autonomy ----------------------------------------------------------------
$form.Controls.Add((New-Caption 'Autonomy' 120))

$yoloBox          = New-Object System.Windows.Forms.CheckBox
$yoloBox.Text     = 'Skip approval prompts'
$yoloBox.Location = New-Object System.Drawing.Point(112, 118)
$yoloBox.Size     = New-Object System.Drawing.Size(250, 24)
$yoloBox.Checked  = [bool]$config.Yolo
$form.Controls.Add($yoloBox)

$commandLabel           = New-Object System.Windows.Forms.Label
$commandLabel.Location  = New-Object System.Drawing.Point(114, 146)
$commandLabel.Size      = New-Object System.Drawing.Size(386, 20)
$commandLabel.Font      = $mono
$commandLabel.ForeColor = [System.Drawing.SystemColors]::GrayText
$commandLabel.AutoEllipsis = $true
$form.Controls.Add($commandLabel)

# -- Footer ------------------------------------------------------------------
$divider          = New-Object System.Windows.Forms.Label
$divider.AutoSize = $false
$divider.Height   = 2
$divider.BorderStyle = 'Fixed3D'
$divider.Location = New-Object System.Drawing.Point(20, 180)
$divider.Size     = New-Object System.Drawing.Size(480, 2)
$form.Controls.Add($divider)

$footer           = New-Object System.Windows.Forms.Label
$footer.Text      = "Ctrl+Alt+C session   Ctrl+Alt+S grid   Ctrl+Alt+T arrange`r`n" +
                    'Explorer right-click and the hotkeys all run the selected agent.'
$footer.Location  = New-Object System.Drawing.Point(20, 192)
$footer.Size      = New-Object System.Drawing.Size(480, 36)
$footer.ForeColor = [System.Drawing.SystemColors]::GrayText
$form.Controls.Add($footer)

$closeButton          = New-Object System.Windows.Forms.Button
$closeButton.Text     = 'Close'
$closeButton.Location = New-Object System.Drawing.Point(420, 214)
$closeButton.Size     = New-Object System.Drawing.Size(80, 26)
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)
$form.CancelButton = $closeButton
$form.AcceptButton = $closeButton

# ----------------------------------------------------------------- wiring ---

function Sync-Display {
    $agent = Get-SteroidsAgent $config.Agent

    $resolved = Get-Command $agent.Bin -ErrorAction SilentlyContinue
    if ($resolved) {
        # A command can resolve to an alias or a function; Source is empty for
        # those, so fall back to the name rather than showing a blank tick.
        $where = if ($resolved.Source) { $resolved.Source } else { $resolved.Name }
        $statusLabel.Text      = "OK  $where"
        $statusLabel.ForeColor = [System.Drawing.SystemColors]::GrayText
    } else {
        $statusLabel.Text      = "not found - $($agent.InstallHint)"
        $statusLabel.ForeColor = [System.Drawing.Color]::Firebrick
    }

    $line = $agent.Bin
    if ($config.Yolo) { $line += ' ' + $agent.YoloFlag }
    $commandLabel.Text = "Runs:  $line"
}

# Whichever grid the config asks for, land on a real entry: a hand-edited 5x7
# is legal in the file but has no item here, and selecting -1 would wipe it on
# the next click.
$index = 0
for ($i = 0; $i -lt $gridChoices.Count; $i++) {
    if ($gridChoices[$i].Columns -eq $config.Columns -and $gridChoices[$i].Rows -eq $config.Rows) {
        $index = $i
        break
    }
}
$gridBox.SelectedIndex = $index

# Capture the id per iteration rather than reading $this: a closure created with
# GetNewClosure carries its own scope, and depending on $this to still mean the
# sender inside it is a subtlety this does not need.
foreach ($id in @($agentButtons.Keys)) {
    $agentButtons[$id].Add_CheckedChanged({
        # Selecting one radio clears the other, so the pair fires twice.
        if (-not $agentButtons[$id].Checked) { return }
        $config.Agent = $id
        Save-SteroidsConfig $config
        Sync-Display
    }.GetNewClosure())
}

$gridBox.Add_SelectedIndexChanged({
    $choice = $gridChoices[$gridBox.SelectedIndex]
    $config.Columns = $choice.Columns
    $config.Rows    = $choice.Rows
    Save-SteroidsConfig $config
}.GetNewClosure())

$yoloBox.Add_CheckedChanged({
    $config.Yolo = $yoloBox.Checked
    Save-SteroidsConfig $config
    Sync-Display
}.GetNewClosure())

Sync-Display
[void]$form.ShowDialog()
$form.Dispose()
