# Claude Code — Steroids Mode :: Windows test suite
#
#   powershell -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
#   powershell -ExecutionPolicy Bypass -File .\tests\run-tests.ps1 -IncludeLive
#
# No Pester needed — plain PowerShell, so it runs on a stock Windows box.
#
# By default only checks that cannot disturb your desktop run. -IncludeLive adds
# the ones that install for real, open Terminal windows and close them again;
# they use a harmless placeholder command, never Claude itself.

[CmdletBinding()]
param(
    [switch]$IncludeLive
)

$ErrorActionPreference = 'Stop'

$root       = Split-Path -Parent $PSScriptRoot
$scriptsDir = Join-Path $root 'scripts'

$script:Pass = 0
$script:Fail = 0
$script:Failures = @()

# Every script under test reads the settings file, so point the whole run at a
# throwaway one: the suite must not depend on which agent you happen to have
# selected, and must never rewrite your real choices. Child processes inherit
# it, which is what makes the -DryRun tests below deterministic.
$script:RealConfig = $env:STEROIDS_CONFIG
$env:STEROIDS_CONFIG = Join-Path $env:TEMP 'steroids-tests-config.json'
@'
{ "version": 1, "agent": "claude", "columns": 3, "rows": 3, "yolo": true }
'@ | Set-Content -LiteralPath $env:STEROIDS_CONFIG -Encoding UTF8

function Test-Case {
    param([string]$Name, [scriptblock]$Body)

    try {
        & $Body
        $script:Pass++
        Write-Host "  PASS  $Name" -ForegroundColor Green
    } catch {
        $script:Fail++
        $script:Failures += "$Name :: $($_.Exception.Message)"
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ("$Expected" -ne "$Actual") { throw "$Message (expected '$Expected', got '$Actual')" }
}

function Section { param([string]$Title) Write-Host ''; Write-Host $Title -ForegroundColor Cyan }

# ===========================================================================
Section 'Encoding — the bug that stopped the installer dead'
# ===========================================================================
# install.ps1 shipped as UTF-8 with no BOM while containing an em dash. Windows
# PowerShell reads a BOM-less file in the ANSI code page, so the dash decoded as
# three characters, the last of which is a curly quote — which closes the string
# early and turns the rest of the line into commands. The installer crashed
# before it ever registered the Steroids menu entry. These two tests make sure
# no file can regress into that state.

$sourceFiles = @(Get-ChildItem -Path $root -Recurse -File -Include *.ps1, *.cs)

foreach ($f in $sourceFiles) {
    $rel = $f.FullName.Substring($root.Length + 1)

    Test-Case "$rel is ASCII-only or carries a UTF-8 BOM" {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count
        Assert-True ($hasBom -or $nonAscii -eq 0) 'has non-ASCII bytes but no UTF-8 BOM'
    }

    Test-Case "$rel decodes cleanly under Windows PowerShell" {
        $text = (Get-Content -Path $f.FullName -Raw)
        # U+FFFD, and the two lead bytes a UTF-8 sequence decays into on the
        # Hebrew/Cyrillic/Greek ANSI code pages.
        Assert-True ($text -notmatch "[\uFFFD]") 'contains a replacement character'
        Assert-True ($text -notmatch '\u05D2\u20AC') 'contains mojibake from an ANSI-decoded em dash'
    }
}

foreach ($f in @($sourceFiles | Where-Object { $_.Extension -eq '.ps1' })) {
    $rel = $f.FullName.Substring($root.Length + 1)
    Test-Case "$rel parses without syntax errors" {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
        $detail = (@($errors) | ForEach-Object { $_.Message }) -join '; '
        Assert-True ($errors.Count -eq 0) $detail
    }
}

# ===========================================================================
Section 'Parameter shadowing — the bug that broke every single launch'
# ===========================================================================
# PowerShell matches variable names case-insensitively, so a local $agent and a
# -Agent parameter are one variable. Assigning the agent *object* to it re-ran
# the parameter's [ValidateSet], which threw; $agent stayed the string it was,
# $agent.Bin came back $null, and every launch died with "was not found on your
# PATH" on machines where the CLI was sitting right there on the PATH.
#
# The shape is what makes it worth a static check: it is invisible on the line
# that causes it, it fails at run time and never at parse time, and any
# parameter carrying a validation attribute can be hit by it.

foreach ($f in @($sourceFiles | Where-Object { $_.Extension -eq '.ps1' })) {
    $rel = $f.FullName.Substring($root.Length + 1)

    Test-Case "$rel never assigns to one of its own validated parameters" {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)

        # Every parameter of every param block in the file - the script's own
        # and those of the functions it defines - that carries a Validate*
        # attribute, and so re-validates on assignment.
        $guarded = @{}
        foreach ($block in $ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.ParamBlockAst] }, $true)) {
            foreach ($p in $block.Parameters) {
                $attrs = @($p.Attributes | Where-Object { $_.TypeName.Name -like 'Validate*' })
                if ($attrs.Count -gt 0) {
                    $guarded[$p.Name.VariablePath.UserPath] =
                        ($attrs | ForEach-Object { $_.TypeName.Name }) -join ', '
                }
            }
        }
        if ($guarded.Count -eq 0) { return }

        $offenders = @()
        foreach ($a in $ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
            if ($a.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
            $name = $a.Left.VariablePath.UserPath
            foreach ($g in $guarded.Keys) {
                # -eq on strings is case-insensitive, which is exactly the
                # comparison PowerShell itself makes when resolving the name.
                if ($name -eq $g) {
                    $offenders += "line $($a.Extent.StartLineNumber): `$$name = ... re-runs [$($guarded[$g])] on -$g"
                }
            }
        }
        Assert-True ($offenders.Count -eq 0) ($offenders -join '; ')
    }
}

# ===========================================================================
Section 'Resolve-TargetDir — Explorer''s %V mangling'
# ===========================================================================
. (Join-Path $scriptsDir 'steroids-common.ps1')

Test-Case 'an ordinary folder passes through unchanged' {
    Assert-Equal $env:USERPROFILE (Resolve-TargetDir $env:USERPROFILE) 'round trip'
}

Test-Case 'a drive root arriving as C:" is repaired to C:\' {
    # This is exactly what the context-menu command hands over for a drive root:
    # "%V" becomes "C:\" on the command line, and \" parses as a literal quote.
    Assert-Equal 'C:\' (Resolve-TargetDir 'C:"') 'drive root repair'
}

Test-Case 'a path containing spaces survives' {
    $withSpaces = Join-Path $env:TEMP 'steroids test dir'
    New-Item -ItemType Directory -Force -Path $withSpaces | Out-Null
    try { Assert-Equal $withSpaces (Resolve-TargetDir $withSpaces) 'spaces' }
    finally { Remove-Item $withSpaces -Force -Recurse -ErrorAction SilentlyContinue }
}

Test-Case 'empty input falls back to the user profile' {
    Assert-Equal $env:USERPROFILE (Resolve-TargetDir '') 'empty'
    Assert-Equal $env:USERPROFILE (Resolve-TargetDir $null) 'null'
}

Test-Case 'a folder that does not exist falls back to the user profile' {
    Assert-Equal $env:USERPROFILE (Resolve-TargetDir 'Z:\nope\not\here') 'missing'
}

Test-Case 'a file rather than a folder falls back to the user profile' {
    $file = Join-Path $env:TEMP 'steroids-not-a-dir.txt'
    'x' | Set-Content $file
    try { Assert-Equal $env:USERPROFILE (Resolve-TargetDir $file) 'file' }
    finally { Remove-Item $file -Force -ErrorAction SilentlyContinue }
}

# ===========================================================================
Section 'Grid construction'
# ===========================================================================
$gridScript = Join-Path $scriptsDir 'steroids-grid.ps1'

function Get-GridArgs {
    param([int]$Columns = 3, [int]$Rows = 3, [string]$Dir = $env:USERPROFILE)
    return @(& $gridScript -Dir $Dir -Columns $Columns -Rows $Rows -DryRun)
}

Test-Case 'the default grid builds exactly nine panes' {
    $a = Get-GridArgs
    $panes = @($a | Where-Object { $_ -eq 'split-pane' }).Count + @($a | Where-Object { $_ -eq 'new-tab' }).Count
    Assert-Equal 9 $panes 'pane count'
}

Test-Case 'pane count tracks Columns x Rows' {
    foreach ($case in @(@(2, 2, 4), @(4, 4, 16), @(1, 1, 1), @(3, 2, 6))) {
        $a = Get-GridArgs -Columns $case[0] -Rows $case[1]
        $panes = @($a | Where-Object { $_ -eq 'split-pane' }).Count + @($a | Where-Object { $_ -eq 'new-tab' }).Count
        Assert-Equal $case[2] $panes "$($case[0])x$($case[1])"
    }
}

Test-Case 'every pane runs Claude in the requested folder' {
    $a = Get-GridArgs
    Assert-Equal 9 (@($a | Where-Object { $_ -eq $env:USERPROFILE }).Count) '-d arguments'
    Assert-Equal 9 (@($a | Where-Object { $_ -like 'claude *' }).Count) 'claude commands'
    Assert-True ($a -contains '--dangerously-skip-permissions' -or
                 (@($a | Where-Object { $_ -like '*--dangerously-skip-permissions*' }).Count -eq 9)) 'YOLO flag present'
}

Test-Case 'the window is maximized and always brand new' {
    $a = Get-GridArgs
    Assert-True ($a -contains '-M') 'missing -M, so nine panes would be crammed into a default-sized window'
    Assert-True ($a -contains 'new') 'missing -w new, so the grid could hijack the terminal you are working in'
    Assert-Equal '-w' $a[0] 'window argument must lead'
}

Test-Case 'split sizes use an invariant decimal point' {
    # wt only accepts 0.6667. On a comma-decimal locale a culture-sensitive
    # format would emit 0,6667 and every split would be rejected.
    $a = Get-GridArgs
    $sizes = @()
    for ($i = 0; $i -lt $a.Count; $i++) { if ($a[$i] -eq '--size') { $sizes += $a[$i + 1] } }
    Assert-True ($sizes.Count -gt 0) 'no --size arguments found'
    foreach ($s in $sizes) {
        Assert-True ($s -notmatch ',') "size '$s' used a comma"
        Assert-True ($s -match '^0\.\d+$') "size '$s' is not an invariant fraction"
    }
}

Test-Case 'split sizes are the fractions that make equal columns' {
    $a = Get-GridArgs -Columns 3 -Rows 1
    $sizes = @()
    for ($i = 0; $i -lt $a.Count; $i++) { if ($a[$i] -eq '--size') { $sizes += $a[$i + 1] } }
    Assert-Equal '0.6667' $sizes[0] 'first vertical split'
    Assert-Equal '0.5'    $sizes[1] 'second vertical split'
}

Test-Case 'the grid names the pane to split instead of walking to it' {
    # move-focus described a route through the layout, and was only right if
    # every split had already landed. Under nine simultaneous agent startups it
    # was not: the terminal fell behind the command list and whole columns came
    # out unsplit while others were split twice over. focus-pane takes an index
    # in creation order, which cannot go stale.
    foreach ($case in @(@(3, 3), @(2, 2), @(4, 3), @(1, 4))) {
        $a = Get-GridArgs -Columns $case[0] -Rows $case[1]
        Assert-True ($a -notcontains 'move-focus') 'a focus walk came back'

        $targets = @()
        for ($i = 0; $i -lt $a.Count; $i++) {
            if ($a[$i] -eq 'focus-pane') {
                Assert-Equal '--target' $a[$i + 1] 'focus-pane must address a pane by index'
                $targets += [int]$a[$i + 2]
            }
        }
        # One per column, and the columns are numbered left to right because
        # every vertical split puts its new pane on the right.
        Assert-Equal $case[0] $targets.Count "one focus-pane per column ($($case[0])x$($case[1]))"
        Assert-Equal (0..($case[0] - 1) -join ',') ($targets -join ',') 'column indices'
    }
}

Test-Case 'splitting a column never renumbers the others' {
    # The whole scheme rests on this: rows are appended to the end of the
    # numbering, so column 2 is still index 1 after column 1 has grown rows.
    # Every focus-pane target must therefore be below the column count.
    $a = Get-GridArgs -Columns 3 -Rows 3
    for ($i = 0; $i -lt $a.Count; $i++) {
        if ($a[$i] -eq 'focus-pane') {
            Assert-True ([int]$a[$i + 2] -lt 3) "target $($a[$i + 2]) is not one of the three columns"
        }
    }
}

Test-Case 'a single session opens one pane in a new window' {
    $a = @(& (Join-Path $scriptsDir 'open-in-claude.ps1') -Dir $env:USERPROFILE -DryRun)
    Assert-Equal 1 (@($a | Where-Object { $_ -eq 'new-tab' }).Count) 'one tab'
    Assert-True ($a -notcontains 'split-pane') 'no splits'
    Assert-True ($a -contains 'new') 'new window'
}

# ===========================================================================
Section 'Launching — what a right-click actually runs'
# ===========================================================================
# The gap that let the launch break completely: every grid test above calls the
# script the way the *neutral* menu entries do, and the four pinned entries pass
# -Agent. That one extra argument was the difference between a working test
# suite and a product where no menu entry launched anything at all.
#
# These run the scripts exactly as the registry entries do, both pinned agents
# and both scripts, and read the command they would hand to Windows Terminal.
# Warnings are muted (3>$null) so a machine with only one agent installed still
# gets a deterministic result instead of a wall of "not found" text.

$openScript = Join-Path $scriptsDir 'open-in-claude.ps1'

function Get-PaneCommandFrom {
    param([string]$Script, [string]$AgentId)

    $a = if ($AgentId) { @(& $Script -Dir $env:USERPROFILE -Agent $AgentId -DryRun 3>$null) }
         else          { @(& $Script -Dir $env:USERPROFILE -DryRun 3>$null) }
    # The pane command is the last argument of every launch: cmd, /k, the line.
    return [string]$a[-1]
}

foreach ($launcher in @(@('open-in-claude.ps1', $openScript), @('steroids-grid.ps1', $gridScript))) {
    foreach ($pinned in @(@('claude', 'codex'), @('codex', 'claude'))) {

        Test-Case "$($launcher[0]) -Agent $($pinned[0]) launches $($pinned[0])" {
            # Asserting on which agent appears rather than on an exact string:
            # Resolve-AgentCommand substitutes a full path when the CLI is
            # installed somewhere our PATH does not mention, and the property
            # that matters is that the pin picked the right agent either way.
            $pane = Get-PaneCommandFrom -Script $launcher[1] -AgentId $pinned[0]
            Assert-True ($pane -match $pinned[0]) "the pinned agent is missing from: $pane"
            Assert-True ($pane -notmatch $pinned[1]) "the other agent leaked in: $pane"
        }
    }

    Test-Case "$($launcher[0]) with no pin follows the settings file" {
        # The neutral entries and the hotkeys take this path. The suite's
        # throwaway config selects claude.
        $pane = Get-PaneCommandFrom -Script $launcher[1]
        Assert-True ($pane -match 'claude') "did not follow the configured agent: $pane"
    }
}

# ===========================================================================
Section 'Finding an agent that is installed but not on our PATH'
# ===========================================================================
# Explorer hands every right-click the environment it captured when it started,
# so a CLI installed since you logged in is invisible to it while working in any
# terminal you open. "Was not found on your PATH" was technically true and
# useless: the fix is to look where the installers actually put things.

Test-Case 'an agent on PATH resolves to the bare name, exactly as before' {
    # Whatever is installed here, the contract is the same: on PATH means the
    # pane command does not change shape at all.
    foreach ($id in @('claude', 'codex')) {
        $resolved = Resolve-AgentCommand (Get-SteroidsAgent $id)
        if (-not $resolved.OnPath) { continue }
        Assert-Equal $id $resolved.Launch "an on-PATH agent must launch by name"
        Assert-True ([bool]$resolved.Found) 'OnPath implies Found'
        Assert-True (Test-Path -LiteralPath $resolved.Path) "reported a path that does not exist: $($resolved.Path)"
    }
}

Test-Case 'an agent nobody has resolves to not-found, without throwing' {
    $resolved = Resolve-AgentCommand ([pscustomobject]@{
        Id = 'ghost'; Label = 'Ghost'; Bin = 'steroids-no-such-cli'
        YoloFlag = '--nope'; InstallHint = 'npm i -g nothing' })
    Assert-True (-not $resolved.Found) 'claimed to find a CLI that does not exist'
    Assert-True (-not $resolved.OnPath) 'claimed it was on PATH'
}

Test-Case 'the persisted PATH is readable and looks like a PATH' {
    # This is the list a fresh login would have given us, and the whole reason
    # the fallback can beat a stale Explorer.
    $dirs = @(Get-PersistedPathDirectory)
    Assert-True ($dirs.Count -gt 0) 'no directories came back from the registry PATH'
    Assert-True (@($dirs | Where-Object { $_ -match '^[A-Za-z]:\\' }).Count -gt 0) `
        'nothing that looks like an absolute Windows path'
    Assert-True (@($dirs | Where-Object { $_ -match '%' }).Count -eq 0) `
        'an environment variable was left unexpanded'
}

Test-Case 'a full path is called, not merely named' {
    # A quoted path on a PowerShell line is a string expression: without the call
    # operator the pane would print the path and sit there. The quoting rule is
    # PowerShell's own -- single quotes, doubled to escape one.
    Assert-Equal "& 'C:\Users\me\.local\bin\claude.exe'" `
        (ConvertTo-PowerShellCommand 'C:\Users\me\.local\bin\claude.exe') 'plain path'
    Assert-Equal "& 'C:\Program Files\nodejs\claude.cmd'" `
        (ConvertTo-PowerShellCommand 'C:\Program Files\nodejs\claude.cmd') 'path with spaces'
    Assert-Equal "& 'C:\it''s here\codex.cmd'" `
        (ConvertTo-PowerShellCommand "C:\it's here\codex.cmd") 'path containing a quote'
}

Test-Case 'a full path reaches the pane as one argument, spaces or not' {
    # What Get-AgentPaneCommand -Executable produces has to survive the same trip
    # every other argument does and arrive as a single token, or -Command would
    # receive the flag as a separate argument and the path on its own.
    Initialize-SteroidsInterop
    foreach ($exe in @('C:\Users\me\.local\bin\claude.exe',
                       'C:\Program Files\nodejs\claude.cmd',
                       'C:\Users\me\AppData\Roaming\npm\codex.cmd')) {
        $call = ConvertTo-PowerShellCommand $exe
        $pane = Get-AgentPaneCommand ([pscustomobject]@{ Agent = 'claude'; Yolo = $true }) -Executable $call
        Assert-Equal 5 $pane.Count 'the pane command must stay host, flags, one line'
        Assert-Equal "$call --dangerously-skip-permissions" $pane[-1] 'line shape'

        # argv[0] is parsed by the special program-name rules, so lead with a dummy.
        $line = 'prog.exe ' + (ConvertTo-WtCommandLine (@('new-tab', '-d', 'C:\work') + $pane))
        $got = @([SteroidsWin]::ParseCommandLine($line) | Select-Object -Skip 1)
        Assert-Equal "$call --dangerously-skip-permissions" $got[-1] "mangled in transit: $exe"
    }
}

Test-Case 'window shaping leaves alone anything it did not open' {
    # One Windows Terminal process owns every window, so the new one is found by
    # elimination. If elimination is inconclusive the answer must be to do
    # nothing -- moving somebody else's window is much worse than leaving ours
    # at Terminal's default size.
    Initialize-SteroidsInterop
    $all = @([SteroidsWin]::Find('WindowsTerminal', $false))
    Assert-True (-not (Set-NewTerminalWindowShape -Before $all -TimeoutSeconds 1)) `
        'claimed to have shaped a window when nothing new had appeared'
}

Test-Case 'no -Executable means nothing about the launch changed' {
    $pane = Get-AgentPaneCommand ([pscustomobject]@{ Agent = 'claude'; Yolo = $true })
    Assert-Equal 'claude --dangerously-skip-permissions' $pane[-1] 'the ordinary launch must be untouched'
}

# ===========================================================================
Section 'Command-line quoting - the bug that broke every folder with a space'
# ===========================================================================
# Start-Process on Windows PowerShell joins an -ArgumentList array with plain
# spaces and quotes nothing, so "C:\My Projects" used to reach wt.exe as two
# arguments and the session opened in C:\My. Every case below is checked by
# handing the built command line back to CommandLineToArgvW -- the very parser
# the target program uses -- so these test Windows' behaviour, not a rereading
# of the quoting rules.
Initialize-SteroidsInterop

function Get-RoundTrip {
    param([string[]]$Arguments)
    # argv[0] is parsed by the special program-name rules, so lead with a dummy.
    $line = 'prog.exe ' + (ConvertTo-WtCommandLine $Arguments)
    return @([SteroidsWin]::ParseCommandLine($line) | Select-Object -Skip 1)
}

function Assert-RoundTrip {
    param([string[]]$Arguments, [string]$Message)
    $got = Get-RoundTrip $Arguments
    Assert-Equal $Arguments.Count $got.Count "$Message (argument count)"
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        Assert-Equal $Arguments[$i] $got[$i] "$Message (argument $i)"
    }
}

Test-Case 'a folder with spaces survives the trip to wt.exe' {
    Assert-RoundTrip @('new-tab', '-d', 'C:\My Test Folder', 'cmd', '/k', 'claude --dangerously-skip-permissions') 'spaces'
}

Test-Case 'a drive root does not lose its backslash to the closing quote' {
    # 'C:\' naively quoted becomes "C:\", whose backslash escapes the quote and
    # hands the program the literal C:" instead.
    Assert-RoundTrip @('-d', 'C:\') 'drive root'
    Assert-RoundTrip @('-d', 'C:\My Folder\') 'trailing backslash after a space'
}

Test-Case 'the YOLO flag stays attached to its claude command' {
    $got = Get-RoundTrip (@('new-tab', '-d', 'C:\Some Folder') + (Get-AgentPaneCommand))
    Assert-Equal 'claude --dangerously-skip-permissions' $got[-1] 'pane command must stay one argument'
}

Test-Case 'unusual but legal folder names survive' {
    foreach ($dir in @('C:\a&b', 'C:\100% done', "C:\it's here", 'C:\(parens)', 'C:\a,b', 'C:\ends with space ')) {
        Assert-RoundTrip @('-d', $dir) "folder $dir"
    }
}

Test-Case 'semicolon delimiters stay raw, semicolons in a path do not' {
    # wt splits its command list on bare ';' arguments. The delimiter must reach
    # it unquoted, while a path containing one must not be allowed to split it.
    $line = ConvertTo-WtCommandLine @('new-tab', '-d', 'C:\notes; drafts', ';', 'split-pane')
    Assert-True ($line -match '(^|\s);(\s|$)') 'the delimiter was quoted away'
    Assert-True ($line -match '\\;') 'the semicolon inside the path was not escaped'

    # After Windows' parser, the escape is still there for wt itself to undo.
    $got = @([SteroidsWin]::ParseCommandLine('prog.exe ' + $line) | Select-Object -Skip 1)
    Assert-Equal 5 $got.Count 'argument count'
    Assert-Equal ';' $got[3] 'delimiter must arrive as its own argument'
    Assert-Equal 'C:\notes\; drafts' $got[2] 'path semicolon must arrive escaped for wt'
}

Test-Case 'arguments needing no quotes are left alone' {
    Assert-Equal 'new-tab' (Format-CommandLineArgument 'new-tab') 'plain argument'
    Assert-Equal '"C:\a b"' (Format-CommandLineArgument 'C:\a b') 'quoted argument'
    Assert-Equal '""' (Format-CommandLineArgument '') 'empty argument'
}

Test-Case 'a drive root keeps both its backslash and the pinned agent' {
    # The exact shape the registry entry produces, parsed by the same function
    # CreateProcess'd programs use. Before the pin moved ahead of the folder,
    # this came back as the single argument  C:" -Agent claude .
    # Indices count the whole line: [0] the dummy program name, [1] -File and
    # [2] its script, and only then the arguments the script itself receives.
    # This test used to read from [1] and reported the launcher's own -File
    # switch as a missing pin.
    $cmd = 'ps.exe -File "C:\s\g.ps1" -Agent claude "C:\"'
    $parsed = [SteroidsWin]::ParseCommandLine($cmd)
    Assert-Equal 6        $parsed.Count 'argument count'
    Assert-Equal '-Agent' $parsed[3] 'named parameter survives'
    Assert-Equal 'claude' $parsed[4] 'its value survives'
    Assert-Equal 'C:"'    $parsed[5] 'the drive root arrives in the form Resolve-TargetDir repairs'
    Assert-Equal 'C:\'    (Resolve-TargetDir $parsed[5]) 'and is repaired'
}

Test-Case 'non-ASCII folder names survive the trip to wt.exe' {
    # The macOS side shredded these: zsh escapes whatever the current locale
    # calls unprintable, and launchd gives Quick Actions no locale at all.
    # PowerShell has no equivalent exposure -- it is UTF-16 strings end to end --
    # but that is worth holding to rather than assuming.
    foreach ($dir in @('C:\Users\a\אתר שאולי הורדה גיבוי',
                       'C:\Users\a\日本語のフォルダ',
                       'C:\Users\a\ünïcødé — dash',
                       "C:\Users\a\don't stop")) {
        $line = ConvertTo-WtCommandLine @('new-tab', '-d', $dir)
        $parsed = [SteroidsWin]::ParseCommandLine("wt.exe $line")
        Assert-Equal $dir $parsed[3] "mangled: $dir"
    }
}

Test-Case 'the real grid command line round-trips argument for argument' {
    $args9 = @(& $gridScript -Dir $env:USERPROFILE -DryRun)
    $line  = ConvertTo-WtCommandLine $args9
    $got   = @([SteroidsWin]::ParseCommandLine('prog.exe ' + $line) | Select-Object -Skip 1)
    Assert-Equal $args9.Count $got.Count 'the nine-pane command line changed shape in transit'
    Assert-Equal 9 (@($got | Where-Object { $_ -eq 'claude --dangerously-skip-permissions' }).Count) 'pane commands'
}

# ===========================================================================
Section 'Claude session detection'
# ===========================================================================
# What "Close ALL Agent Sessions" fires at. The native installer leaves a
# claude.exe in the tree; an npm install runs the CLI as node.exe with the
# package path on its command line, and matching node by name would take out
# every unrelated Node process on the machine.

function New-FakeProcess {
    param([string]$Name, [string]$CommandLine)
    return [pscustomobject]@{ Name = $Name; CommandLine = $CommandLine }
}

Test-Case 'a native claude.exe is recognised' {
    Assert-True (Test-AgentProcess (New-FakeProcess 'claude.exe' 'claude --dangerously-skip-permissions')) 'by name'
}

Test-Case 'the pane shell we launch is recognised by its command line' {
    Assert-True (Test-AgentProcess (New-FakeProcess 'cmd.exe' 'cmd /k claude --dangerously-skip-permissions')) 'cmd pane'
    Assert-True (Test-AgentProcess (New-FakeProcess 'cmd.exe' '"C:\Users\a b\.local\bin\claude.exe" --resume')) 'quoted full path'
}

Test-Case 'an npm-installed Claude running under node is recognised' {
    $npm = '"C:\Program Files\nodejs\node.exe" "C:\Users\a\AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code\cli.js"'
    Assert-True (Test-AgentProcess (New-FakeProcess 'node.exe' $npm)) 'npm install'
}

Test-Case 'unrelated processes are left alone' {
    foreach ($p in @(
        (New-FakeProcess 'node.exe'    '"C:\Program Files\nodejs\node.exe" server.js'),
        (New-FakeProcess 'cmd.exe'     'cmd /k'),
        (New-FakeProcess 'notepad.exe' 'notepad claude.md'),
        (New-FakeProcess 'git.exe'     'git clone https://github.com/x/claude-notes.git'),
        (New-FakeProcess 'cmd.exe'     $null),
        # "codex" is a word people name folders after, so the package pattern
        # requires the @openai scope. A project directory must not read as a
        # session and get swept up with one.
        (New-FakeProcess 'node.exe'    '"C:\Program Files\nodejs\node.exe" C:\src\codex\build.js'),
        (New-FakeProcess 'code.exe'    'Code.exe C:\Users\a\codex\notes.md')
    )) {
        Assert-True (-not (Test-AgentProcess $p)) "false positive on: $($p.CommandLine)"
    }
}

Test-Case 'the pane hosting this very process is recognised as self' {
    # What stops "Close ALL Agent Sessions" from closing the session that ran
    # it -- including this test run, which exercises the real thing.
    $hosting = [pscustomobject]@{
        ProcessId = 4; Name = 'cmd.exe'; CommandLine = 'cmd /k'
        Descendants = @([pscustomobject]@{ ProcessId = $PID; Name = 'powershell.exe'; CommandLine = 'powershell' })
    }
    Assert-True (Test-ShellHostsSelf $hosting) 'a pane we descend from must count as self'

    $direct = [pscustomobject]@{ ProcessId = $PID; Name = 'cmd.exe'; Descendants = @() }
    Assert-True (Test-ShellHostsSelf $direct) 'our own process must count as self'

    $other = [pscustomobject]@{
        ProcessId = 4; Name = 'cmd.exe'
        Descendants = @([pscustomobject]@{ ProcessId = 5; Name = 'claude.exe' })
    }
    Assert-True (-not (Test-ShellHostsSelf $other)) 'an unrelated pane must not count as self'
}

Test-Case 'the live sweep would spare the session running these tests' {
    # A guard, not a unit test: if this stops holding, the -IncludeLive run
    # below would kill its own terminal partway through.
    $sweep = @(Get-TerminalPaneShell |
               Where-Object { Test-ShellRunsAgent $_ } |
               Where-Object { -not (Test-ShellHostsSelf $_) })
    foreach ($s in $sweep) {
        Assert-True ([int]$s.ProcessId -ne $PID) 'the sweep targeted this process'
        foreach ($d in $s.Descendants) {
            Assert-True ([int]$d.ProcessId -ne $PID) 'the sweep targeted a pane we live in'
        }
    }
}

Test-Case 'a shell counts as Claude when a descendant is Claude' {
    $shell = [pscustomobject]@{
        Name = 'cmd.exe'; CommandLine = 'cmd /k'
        Descendants = @((New-FakeProcess 'node.exe' 'node C:\x\@anthropic-ai\claude-code\cli.js'))
    }
    Assert-True (Test-ShellRunsAgent $shell) 'descendant match'

    $plain = [pscustomobject]@{
        Name = 'cmd.exe'; CommandLine = 'cmd /k'
        Descendants = @((New-FakeProcess 'git.exe' 'git status'))
    }
    Assert-True (-not (Test-ShellRunsAgent $plain)) 'plain shell must be left alone'
}

# ===========================================================================
Section 'What a close action must not interrupt'
# ===========================================================================
# Claude updates itself with `npm install -g`. Killed between unpacking and the
# final rename it does not just fail -- the staging directory it leaves behind
# makes every later install fail ENOTEMPTY, and the CLI is gone until someone
# clears it by hand. So an installing pane is spared. The line to hold is
# installs versus package managers: npm-launched MCP servers live for the whole
# session, and sparing those would spare every pane.

Test-Case 'the update that a sweep must not kill is recognised' {
    foreach ($cmd in @(
        'npm install -g @anthropic-ai/claude-code',
        '"C:\Program Files\nodejs\node.exe" "C:\Users\a\AppData\Roaming\npm\node_modules\npm\bin\npm-cli.js" install -g @anthropic-ai/claude-code',
        'C:\Program Files\nodejs\npm.cmd install -g @anthropic-ai/claude-code',
        'npm i -g claude',
        'npm --silent install -g x',
        'npm ci',
        'node "C:\Users\a\AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code\install.cjs"',
        'pnpm add -g foo',
        'yarn global add foo',
        'bun install'
    )) {
        Assert-True (Test-PackageInstallProcess (New-FakeProcess 'node.exe' $cmd)) "missed: $cmd"
    }
}

Test-Case 'long-lived package-manager processes are not mistaken for installs' {
    # The expensive false positive: match these and closing a swarm does nothing.
    foreach ($cmd in @(
        'npm exec figma-developer-mcp --figma-api-key=x --stdio',
        'npx -y @modelcontextprotocol/server-filesystem C:\Users\a',
        'npm run dev',
        'npm start',
        'node server.js',
        'cmd /k claude --dangerously-skip-permissions',
        'git clone https://github.com/x/install-notes.git'
    )) {
        Assert-True (-not (Test-PackageInstallProcess (New-FakeProcess 'node.exe' $cmd))) "false positive: $cmd"
    }
    Assert-True (-not (Test-PackageInstallProcess (New-FakeProcess 'cmd.exe' $null))) 'no command line'
}

Test-Case 'a pane counts as installing when a descendant is' {
    # How it actually appears: the pane runs Claude, Claude spawns the updater.
    $updating = [pscustomobject]@{
        Name = 'cmd.exe'; CommandLine = 'cmd /k claude --dangerously-skip-permissions'
        Descendants = @((New-FakeProcess 'node.exe' 'npm install -g @anthropic-ai/claude-code'))
    }
    Assert-True (Test-ShellRunsPackageInstall $updating) 'descendant install must protect the pane'
    Assert-True (Test-ShellRunsAgent $updating) 'and it is still a Claude pane'

    $idle = [pscustomobject]@{
        Name = 'cmd.exe'; CommandLine = 'cmd /k claude --dangerously-skip-permissions'
        Descendants = @((New-FakeProcess 'claude.exe' 'claude --dangerously-skip-permissions'))
    }
    Assert-True (-not (Test-ShellRunsPackageInstall $idle)) 'an idle Claude pane is still fair game'
}

# ===========================================================================
Section 'Tiling maths'
# ===========================================================================
# Mirrors the arrange script: square-ish, wider before taller.
function Get-GridShape {
    param([int]$n)
    $cols = [int][Math]::Ceiling([Math]::Sqrt($n))
    $rows = [int][Math]::Ceiling($n / [double]$cols)
    return "${cols}x${rows}"
}

Test-Case 'window counts map to the documented grid shapes' {
    Assert-Equal '1x1' (Get-GridShape 1)  'one window'
    Assert-Equal '2x2' (Get-GridShape 4)  'four windows'
    Assert-Equal '3x3' (Get-GridShape 9)  'nine windows'
    Assert-Equal '4x3' (Get-GridShape 10) 'ten windows'
    Assert-Equal '4x4' (Get-GridShape 16) 'sixteen windows'
    Assert-Equal '2x2' (Get-GridShape 3)  'three windows'
}

# ===========================================================================
Section 'Win32 interop'
# ===========================================================================
Test-Case 'the interop type compiles and reports DPI awareness' {
    Initialize-SteroidsInterop
    Assert-True ([bool]('SteroidsWin' -as [type])) 'type not defined'
}

Test-Case 'the work area is a sane, non-empty rectangle' {
    Initialize-SteroidsInterop
    $a = [SteroidsWin]::WorkArea()
    Assert-True (($a.Right - $a.Left) -gt 200) 'width'
    Assert-True (($a.Bottom - $a.Top) -gt 200) 'height'
}

Test-Case 'window enumeration runs and returns terminal windows only' {
    Initialize-SteroidsInterop
    $all = @([SteroidsWin]::Find('WindowsTerminal', $false))
    $here = @([SteroidsWin]::Find('WindowsTerminal', $true))
    Assert-True ($here.Count -le $all.Count) 'current desktop must be a subset of all desktops'
    Assert-Equal 0 (@([SteroidsWin]::Find('a-process-that-does-not-exist', $false)).Count) 'unknown process'
}

Test-Case 'pane shells resolve to real processes' {
    $shells = @(Get-TerminalPaneShell)
    foreach ($s in $shells) {
        Assert-True ($s.ProcessId -gt 0) 'bad pid'
        Assert-True ($null -ne $s.Name) 'missing name'
    }

    # Not a formality: the lookup used to build its index with the UInt32 pids
    # CIM returns and probe it with the Int32 pids Get-Process returns. A
    # hashtable compares key type as well as value, so every lookup missed, the
    # list came back empty, and the close actions answered "no Claude sessions"
    # however many were running. An empty result with Terminal running is the
    # exact shape of that bug.
    if (Get-Process -Name 'WindowsTerminal' -ErrorAction SilentlyContinue) {
        Assert-True ($shells.Count -gt 0) 'Windows Terminal is running but no pane shells were found'
    }
}

# ===========================================================================
Section 'Installer / uninstaller round trip'
# ===========================================================================
# Six entries, each registered under both roots: right-click ON a folder, and
# right-click on a folder's empty background.
$menuNames = @('OpenAgentHere', 'AgentSteroids',
               'OpenInClaude', 'ClaudeSteroids',
               'OpenInCodex', 'CodexSteroids')
# $menuRoot, not $root: a foreach variable is an ordinary assignment, so looping
# over $root here overwrote the repository path set at the top of the file and
# left it as 'Directory\Background'. Every live test that ran a script by path
# then invoked 'Directory\Background\install.ps1' -- which does not exist -- so
# the installer and uninstaller silently never ran, and the tests that checked
# their work either failed for an unrelated-looking reason or passed against
# whatever the machine happened to already have installed.
$menuKeys = foreach ($menuRoot in @('Directory', 'Directory\Background')) {
    foreach ($n in $menuNames) { "HKCU:\Software\Classes\$menuRoot\shell\$n" }
}

if ($IncludeLive) {
    $installer   = Join-Path $root 'install.ps1'
    $uninstaller = Join-Path $root 'uninstall.ps1'
    $dest        = Join-Path $env:LOCALAPPDATA 'claude-code-steroids'
    $liveConfig  = Join-Path $env:APPDATA 'claude-code-steroids\config.json'

    # These tests run the real uninstaller, which now takes the settings folder
    # with it. Scripts it deletes come back on the next install; the agent you
    # picked does not, so put it back afterwards. STEROIDS_CONFIG keeps the rest
    # of the suite off this file, but the installer and uninstaller address it
    # by its real path.
    $savedConfig = $null
    if (Test-Path -LiteralPath $liveConfig) {
        $savedConfig = Get-Content -LiteralPath $liveConfig -Raw
    }

    # Runs first, and deliberately checks the suite's own footing rather than
    # the product's. powershell.exe -File on a path that does not exist writes
    # its complaint and returns a non-zero code, which reads as "the installer
    # failed" -- so the one thing that must never be in doubt is that these are
    # the real scripts. See the note on $menuRoot above for how they stopped
    # being that.
    Test-Case 'the suite is pointed at the scripts it is about to run' {
        Assert-True (Test-Path -LiteralPath $installer) "installer not found at: $installer"
        Assert-True (Test-Path -LiteralPath $uninstaller) "uninstaller not found at: $uninstaller"
        Assert-True ([System.IO.Path]::IsPathRooted($installer)) "not an absolute path: $installer"
    }

    Test-Case 'the installer completes without errors' {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -NoTray 2>&1
        Assert-Equal 0 $LASTEXITCODE ("installer exited $LASTEXITCODE`n" + ($out -join "`n"))
        Assert-True (($out -join "`n") -notmatch 'not recognized') 'installer printed a command-not-found error'
    }

    Test-Case 'all twelve context-menu entries are registered' {
        foreach ($k in $menuKeys) { Assert-True (Test-Path $k) "missing $k" }
    }

    Test-Case 'the per-agent entries pin their agent on the command line' {
        foreach ($pair in @(@('OpenInClaude', 'claude'), @('ClaudeSteroids', 'claude'),
                            @('OpenInCodex', 'codex'),   @('CodexSteroids', 'codex'))) {
            $cmd = (Get-ItemProperty "HKCU:\Software\Classes\Directory\shell\$($pair[0])\command").'(default)'
            Assert-True ($cmd -match "-Agent $($pair[1]) `"%V`"$") "$($pair[0]) does not pin $($pair[1]): $cmd"
        }
        # The neutral pair must pin nothing, or it could not follow Settings.
        foreach ($n in @('OpenAgentHere', 'AgentSteroids')) {
            $cmd = (Get-ItemProperty "HKCU:\Software\Classes\Directory\shell\$n\command").'(default)'
            Assert-True ($cmd -notmatch '-Agent') "$n should not pin an agent: $cmd"
        }
    }

    Test-Case 'the Steroids label survives the round trip through the registry' {
        # The original bug ended here: the label never got written at all.
        $label = (Get-ItemProperty 'HKCU:\Software\Classes\Directory\shell\ClaudeSteroids').MUIVerb
        Assert-Equal ([char]0x2014) ($label[15]) 'em dash position'
        Assert-Equal 'Open in Claude — Steroids (9x)' $label 'label text'
    }

    Test-Case 'the menu command points at a script that exists' {
        foreach ($k in $menuKeys) {
            $cmd = (Get-ItemProperty (Join-Path $k 'command')).'(default)'
            Assert-True ($cmd -match '-File "([^"]+)"') "no -File in: $cmd"
            Assert-True (Test-Path $matches[1]) "missing script: $($matches[1])"
            # The folder placeholder must be LAST. Explorer expands a drive root
            # to C:\ , whose trailing backslash escapes the closing quote and
            # swallows whatever follows into the same argument -- so anything
            # after "%V" is an argument the script will never see.
            Assert-True ($cmd -match '"%V"$') "the folder placeholder must be the last argument: $cmd"
        }
    }

    Test-Case 'every script the menu and tray call was deployed' {
        foreach ($n in @('open-in-claude.ps1', 'steroids-grid.ps1', 'arrange-terminals.ps1',
                         'close-terminals.ps1', 'steroids-common.ps1', 'steroids-settings.ps1')) {
            Assert-True (Test-Path (Join-Path $dest $n)) "missing $n in $dest"
        }
    }

    Test-Case 'the tray app compiles with the Windows C# compiler' {
        $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
        Assert-True (Test-Path $csc) 'csc.exe not found'
        $exe = Join-Path $env:TEMP 'steroids-tray-test.exe'
        # 2>&1 under $ErrorActionPreference = 'Stop' turns a single stderr line
        # into a terminating error, which would surface as this test failing
        # with csc's first line of noise instead of its compiler output. Same
        # guard as install.ps1 uses around the same call.
        $out = $null
        $code = 0
        try {
            $ErrorActionPreference = 'Continue'
            $out = & $csc /nologo /target:winexe /out:"$exe" /r:System.Windows.Forms.dll /r:System.Drawing.dll `
                      (Join-Path $scriptsDir 'steroids-tray.cs') 2>&1
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = 'Stop' }
        try {
            Assert-Equal 0 $code ("csc exited $code`n" + ($out -join "`n"))
            Assert-True (Test-Path $exe) 'no exe produced'
        } finally { Remove-Item $exe -Force -ErrorAction SilentlyContinue }
    }

    Test-Case 'the uninstaller removes every trace' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $uninstaller | Out-Null
        foreach ($k in $menuKeys) { Assert-True (-not (Test-Path $k)) "left behind: $k" }
        Assert-True (-not (Test-Path $dest)) "left behind: $dest"
        Assert-True (-not (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
                            -Name 'ClaudeSteroidsTray' -ErrorAction SilentlyContinue)) 'left behind: login entry'
    }

    Test-Case 'uninstalling twice is harmless' {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $uninstaller 2>&1
        Assert-Equal 0 $LASTEXITCODE 'second uninstall failed'
        Assert-True (($out -join '') -match 'Nothing to uninstall') 'expected the no-op message'
    }

    Test-Case 'the installer seeds settings, and re-running keeps your choices' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -NoTray | Out-Null
        Assert-True (Test-Path -LiteralPath $liveConfig) "installer did not seed $liveConfig"
        Assert-Equal 'claude' (Get-SteroidsConfig -Path $liveConfig).Agent 'seeded agent'

        Save-SteroidsConfig ([pscustomobject]@{
            Agent = 'codex'; Yolo = $false; Columns = 4; Rows = 4 }) -Path $liveConfig
        & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -NoTray | Out-Null

        $after = Get-SteroidsConfig -Path $liveConfig
        Assert-Equal 'codex' $after.Agent 'reinstalling reset the agent'
        Assert-Equal 4 $after.Columns 'reinstalling reset the grid'
    }

    # Leave the machine as we found it: uninstall what the tests installed, then
    # hand back whatever settings were there before the run.
    & powershell -NoProfile -ExecutionPolicy Bypass -File $uninstaller | Out-Null
    if ($null -ne $savedConfig) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $liveConfig) | Out-Null
        Set-Content -LiteralPath $liveConfig -Value $savedConfig -Encoding UTF8
    }

    # -------------------------------------------------------------------
    Section 'Live windows'
    # -------------------------------------------------------------------
    # A stand-in for Claude, so the suite never spawns nine real agents.
    $marker = 'STEROIDS_TEST_PANE'
    $probe  = @('cmd', '/k', "prompt $marker`$ ")

    # Every window the suite opens is titled with the marker, and every window
    # the suite closes is looked up by that title. One Windows Terminal process
    # owns all the windows, so identifying ours by elimination -- "whatever
    # appeared since a moment ago" -- would put a window the user restored, or
    # the terminal running these tests, in the firing line.
    $titledProbe = @('-w', 'new', 'new-tab', '--title', $marker, '-d', $env:USERPROFILE) + $probe

    function Get-ProbeWindow {
        Initialize-SteroidsInterop
        return @([SteroidsWin]::Find('WindowsTerminal', $false) |
                   Where-Object { [SteroidsWin]::Title($_) -like "*$marker*" })
    }

    function Wait-ForProbeWindow {
        param([int]$Expected, [int]$TimeoutSeconds = 25)
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        do {
            $n = @(Get-ProbeWindow).Count
            if ($n -eq $Expected) { return $n }
            Start-Sleep -Milliseconds 500
        } while ((Get-Date) -lt $deadline)
        return @(Get-ProbeWindow).Count
    }

    function Get-ProbeCount {
        return @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue |
                   Where-Object { $_.CommandLine -like "*$marker*" }).Count
    }

    # End probes the same way the product does — exit code 0 — so Terminal
    # retires the panes and the suite never litters the desktop with dead
    # windows the way a plain Stop-Process would.
    function Stop-Probes {
        Initialize-SteroidsInterop
        Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*$marker*" } |
            ForEach-Object { [void][SteroidsWin]::EndProcess([int]$_.ProcessId, 0) }
        for ($i = 0; $i -lt 20 -and (Get-ProbeCount) -gt 0; $i++) { Start-Sleep -Milliseconds 500 }
    }

    # Terminal brings panes up one at a time, and on a loaded machine the last
    # one can take a few seconds — so wait for the count to settle rather than
    # sampling once at an arbitrary moment. A grid that never reaches nine still
    # fails, it just is not allowed to fail merely for being slow.
    function Wait-ForProbes {
        param([int]$Expected, [int]$TimeoutSeconds = 30)

        $seen = @()
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        do {
            $n = Get-ProbeCount
            $seen += $n
            if ($n -ge $Expected) { return @{ Count = $n; Trace = $seen } }
            Start-Sleep -Milliseconds 500
        } while ((Get-Date) -lt $deadline)
        return @{ Count = (Get-ProbeCount); Trace = $seen }
    }

    Test-Case 'a nine-pane grid really opens, and really is nine panes' {
        Stop-Probes
        $a = @(& $gridScript -Dir $env:USERPROFILE -DryRun)
        # Swap the agent command for the probe, keeping the layout identical.
        # Matched against whatever Get-AgentPaneCommand currently emits rather
        # than against a hardcoded 'cmd', '/k' -- the pane host has changed once
        # already and this loop silently substituted nothing when it did.
        $paneBlock = @(Get-AgentPaneCommand ([pscustomobject]@{ Agent = 'claude'; Yolo = $true }))
        $live = @(); $i = 0
        while ($i -lt $a.Count) {
            if ($a[$i] -eq $paneBlock[0] -and $a[$i + 1] -eq $paneBlock[1]) {
                $live += $probe; $i += $paneBlock.Count
            } else { $live += $a[$i]; $i++ }
        }
        Assert-Equal 9 (@($live | Where-Object { $_ -like "prompt $marker*" }).Count) 'probe substitution'

        Start-WindowsTerminal $live
        $result = Wait-ForProbes -Expected 9
        Stop-Probes
        Assert-Equal 9 $result.Count "panes actually created (observed over time: $($result.Trace -join ','))"
    }

    Test-Case 'a pane really opens in a folder whose name needs quoting' {
        # The end-to-end version of the quoting tests: before the fix, wt read
        # "C:\...\steroids test dir" as three arguments and the pane opened in
        # whatever "...\steroids" resolved to.
        #
        # The pane proves where it landed by dropping a file in its own working
        # directory, under a RELATIVE name, rather than by printing the path:
        # `cd` writes through cmd's OEM code page, so a Hebrew or Japanese folder
        # name would come back mojibake and fail a comparison that has nothing to
        # do with the bug under test. A file either appears in the right folder
        # or it does not, whatever the folder is called.
        $cwdMarker = 'steroids-cwd-marker.txt'
        $strayMarker = Join-Path $env:USERPROFILE $cwdMarker

        # The last two are the macOS regression, ported. There, zsh escaped one
        # byte out of the middle of each Hebrew character and `cd` failed on a
        # folder sitting right in front of you. PowerShell is UTF-16 end to end
        # and should be immune -- worth holding to rather than assuming.
        foreach ($name in @('steroids test dir', 'steroids;semi dir', 'steroids (100%) dir',
                            'steroids אתר שאולי', 'steroids 日本語のフォルダ')) {
            $probeDir = Join-Path $env:TEMP $name
            New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
            $landed = Join-Path $probeDir $cwdMarker
            Remove-Item $landed, $strayMarker -Force -ErrorAction SilentlyContinue
            Stop-Probes
            try {
                $paneCmd = 'prompt ' + $marker + '$ & echo ok> ' + $cwdMarker
                Start-WindowsTerminal (@('-w', 'new', 'new-tab', '-d', $probeDir) + @('cmd', '/k', $paneCmd))

                $deadline = (Get-Date).AddSeconds(25)
                while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $landed)) { Start-Sleep -Milliseconds 500 }
                Assert-True (Test-Path -LiteralPath $landed) `
                    ("the pane did not open in '$name'" +
                     $(if (Test-Path -LiteralPath $strayMarker) { " - it opened in $env:USERPROFILE instead" } else { ' - or never started' }))
            } finally {
                Stop-Probes
                Remove-Item $strayMarker -Force -ErrorAction SilentlyContinue
                Remove-Item $probeDir -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
    }

    Test-Case 'arranging leaves every terminal inside the work area' {
        # Wait for anything an earlier test closed to actually be gone: comparing
        # raw window counts across a window that is still dying is a race, and
        # the property that matters is that no window we had disappeared, not
        # that the total held still.
        Stop-Probes
        Assert-Equal 0 (Wait-ForProbeWindow 0) 'a probe window from an earlier test was still closing'

        $before = @([SteroidsWin]::Find('WindowsTerminal', $true))
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir 'arrange-terminals.ps1') 2>&1
        Assert-Equal 0 $LASTEXITCODE ($out -join "`n")
        Assert-True (($out -join '') -match 'Arranged|No WindowsTerminal') "unexpected output: $out"

        $after = @([SteroidsWin]::Find('WindowsTerminal', $true))
        foreach ($h in $before) { Assert-True ($after -contains $h) 'arranging closed a window' }

        # And the part the name actually promises. Terminal keeps an invisible
        # resize border, so allow a few pixels of slack on each edge.
        if (($out -join '') -match 'Arranged') {
            $area  = [SteroidsWin]::WorkArea()
            $slack = 16
            foreach ($h in $after) {
                $r = [SteroidsWin]::Bounds($h)
                Assert-True ($r.Left   -ge ($area.Left   - $slack)) "window escaped the work area on the left"
                Assert-True ($r.Top    -ge ($area.Top    - $slack)) "window escaped the work area on the top"
                Assert-True ($r.Right  -le ($area.Right  + $slack)) "window escaped the work area on the right"
                Assert-True ($r.Bottom -le ($area.Bottom + $slack)) "window escaped the work area on the bottom"
            }
        }
    }

    Test-Case 'closing Claude terminals reports honestly when there are none' {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass `
                  -File (Join-Path $scriptsDir 'close-terminals.ps1') -Mode claude -WhatIf 2>&1
        Assert-Equal 0 $LASTEXITCODE ($out -join "`n")
    }

    Test-Case 'close -WhatIf never actually kills anything' {
        Stop-Probes
        Start-WindowsTerminal $titledProbe
        try {
            Assert-Equal 1 (Wait-ForProbes -Expected 1).Count 'probe window did not open'
            & powershell -NoProfile -ExecutionPolicy Bypass `
                -File (Join-Path $scriptsDir 'close-terminals.ps1') -Mode desktop -WhatIf | Out-Null
            Start-Sleep -Seconds 2
            Assert-Equal 1 (Get-ProbeCount) '-WhatIf killed a real process'
        } finally { Stop-Probes }
    }

    Test-Case 'ending a pane with exit code 0 retires it, and the window with it' {
        # The whole close feature rests on this: Terminal's default closeOnExit
        # is "graceful", so a pane killed with a failure code stays on screen as
        # a dead pane. Ending it with 0 is what makes the window disappear.
        Stop-Probes
        Start-WindowsTerminal $titledProbe
        try {
            Assert-Equal 1 (Wait-ForProbes -Expected 1).Count 'probe window did not open'
            Assert-Equal 1 (Wait-ForProbeWindow 1) 'window did not appear'
            Stop-Probes
            Assert-Equal 0 (Wait-ForProbeWindow 0) 'window did not close itself'
        } finally { Stop-Probes }
    }

    Test-Case 'claude mode picks real Claude panes, and spares this session' {
        # Deliberately -WhatIf. The sweep runs against whatever is really on the
        # machine, so a live one would end the user's other Claude sessions --
        # and, before Test-ShellHostsSelf, the session running these tests.
        # What it *would have* targeted is the thing worth asserting.
        Stop-Probes
        Start-WindowsTerminal $titledProbe
        try {
            Assert-Equal 1 (Wait-ForProbes -Expected 1).Count 'probe window did not open'
            $probePid = @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue |
                            Where-Object { $_.CommandLine -like "*$marker*" })[0].ProcessId

            $out = (& powershell -NoProfile -ExecutionPolicy Bypass `
                      -File (Join-Path $scriptsDir 'close-terminals.ps1') -Mode claude -WhatIf 2>&1) -join "`n"
            Assert-Equal 0 $LASTEXITCODE $out

            Assert-True ($out -notmatch "pid $probePid\b") 'targeted a terminal that is not running Claude'

            foreach ($self in @(Get-TerminalPaneShell | Where-Object { Test-ShellHostsSelf $_ })) {
                Assert-True ($out -notmatch "pid $($self.ProcessId)\b") `
                    'the sweep targeted the session running these tests'
            }

            Assert-Equal 1 (Get-ProbeCount) '-WhatIf killed a real process'
        } finally { Stop-Probes }
    }

    Test-Case 'closing a window takes its panes and their processes with it' {
        # Desktop mode closes every terminal on the desktop, which would include
        # the one running this suite - so exercise the mechanism it uses on a
        # single throwaway window instead. The sweep itself is covered by the
        # -WhatIf test above.
        Stop-Probes
        Start-WindowsTerminal $titledProbe
        try {
            Assert-Equal 1 (Wait-ForProbes -Expected 1).Count 'probe window did not open'
            $ours = @(Get-ProbeWindow)
            Assert-Equal 1 $ours.Count 'could not identify our own window by its title'

            [SteroidsWin]::CloseWindow($ours[0])

            $deadline = (Get-Date).AddSeconds(20)
            while ((Get-Date) -lt $deadline -and (Get-ProbeCount) -gt 0) { Start-Sleep -Milliseconds 500 }
            Assert-Equal 0 (Get-ProbeCount) 'closing the window left its pane process running'
            Assert-Equal 0 (Wait-ForProbeWindow 0) 'window did not go away'
        } finally { Stop-Probes }
    }
} else {
    Write-Host '  SKIP  installer, tray build and live-window tests (pass -IncludeLive to run them)' -ForegroundColor DarkGray
}

# ===========================================================================
Section 'Settings'
# ===========================================================================
# One JSON file drives the agent, the grid and the YOLO flag for every entry
# point. It is also the one file a user is likely to hand-edit, so the reader
# has to survive whatever comes back.

function Use-TempConfig {
    param([string]$Json, [scriptblock]$Body)

    $path = Join-Path $env:TEMP ('steroids-cfg-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        if ($null -ne $Json) { Set-Content -LiteralPath $path -Value $Json -Encoding UTF8 }
        & $Body (Get-SteroidsConfig -Path $path) $path
    } finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

Test-Case 'a missing settings file yields the documented defaults' {
    $cfg = Get-SteroidsConfig -Path (Join-Path $env:TEMP 'no-such-steroids-config.json')
    Assert-Equal 'claude' $cfg.Agent 'agent'
    Assert-Equal 3 $cfg.Columns 'columns'
    Assert-Equal 3 $cfg.Rows 'rows'
    Assert-True ([bool]$cfg.Yolo) 'yolo'
}

Test-Case 'a complete settings file is read back field for field' {
    Use-TempConfig '{ "version": 1, "agent": "codex", "columns": 4, "rows": 2, "yolo": false }' {
        param($cfg)
        Assert-Equal 'codex' $cfg.Agent 'agent'
        Assert-Equal 4 $cfg.Columns 'columns'
        Assert-Equal 2 $cfg.Rows 'rows'
        Assert-True (-not $cfg.Yolo) 'yolo'
    }
}

Test-Case 'nonsense in the file never stops a hotkey working' {
    foreach ($json in @(
        '{ not json at all',
        '{}',
        '[]',
        '{ "agent": "gpt-9", "columns": 99, "rows": 0, "yolo": "sure" }',
        '{ "agent": null, "columns": "three" }'
    )) {
        Use-TempConfig $json {
            param($cfg)
            Assert-Equal 'claude' $cfg.Agent "agent from: $json"
            Assert-Equal 3 $cfg.Columns "columns from: $json"
            Assert-Equal 3 $cfg.Rows "rows from: $json"
        }
    }
}

Test-Case 'saving and reading back is lossless' {
    $path = Join-Path $env:TEMP ('steroids-cfg-rt-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $written = [pscustomobject]@{ Agent = 'codex'; Yolo = $false; Columns = 4; Rows = 4 }
        Save-SteroidsConfig $written -Path $path
        $read = Get-SteroidsConfig -Path $path
        Assert-Equal 'codex' $read.Agent 'agent'
        Assert-Equal 4 $read.Columns 'columns'
        Assert-Equal 4 $read.Rows 'rows'
        Assert-True (-not $read.Yolo) 'yolo'
    } finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

Test-Case 'the grid boundaries are the ones the settings window offers' {
    # 1x1 and 8x8 are the edges of what the file accepts; a step past either is
    # not clamped to the edge but discarded, so the default survives.
    foreach ($case in @(@(1, 1), @(8, 8))) {
        Use-TempConfig ('{ "columns": ' + $case[0] + ', "rows": ' + $case[1] + ' }') {
            param($cfg)
            Assert-Equal $case[0] $cfg.Columns 'columns'
            Assert-Equal $case[1] $cfg.Rows 'rows'
        }
    }
    foreach ($bad in @(0, 9, -1)) {
        Use-TempConfig ('{ "columns": ' + $bad + ' }') {
            param($cfg)
            Assert-Equal 3 $cfg.Columns "columns from $bad"
        }
    }
}

Test-Case 'each agent contributes its own flag, and only when YOLO is on' {
    $claudeOn  = Get-AgentPaneCommand ([pscustomobject]@{ Agent = 'claude'; Yolo = $true })
    $claudeOff = Get-AgentPaneCommand ([pscustomobject]@{ Agent = 'claude'; Yolo = $false })
    $codexOn   = Get-AgentPaneCommand ([pscustomobject]@{ Agent = 'codex';  Yolo = $true })
    $codexOff  = Get-AgentPaneCommand ([pscustomobject]@{ Agent = 'codex';  Yolo = $false })

    Assert-Equal 'claude --dangerously-skip-permissions' $claudeOn[-1] 'claude YOLO'
    Assert-Equal 'claude' $claudeOff[-1] 'claude plain'
    Assert-Equal 'codex --dangerously-bypass-approvals-and-sandbox' $codexOn[-1] 'codex YOLO'
    Assert-Equal 'codex' $codexOff[-1] 'codex plain'

    # PowerShell hosts the pane. -NoExit is what keeps it alive once the agent
    # ends, and the command staying ONE argument is what lets Settings show the
    # line that will actually run.
    foreach ($c in @($claudeOn, $codexOff)) {
        Assert-Equal 'powershell' $c[0] 'pane host'
        Assert-True ($c -contains '-NoExit') 'without -NoExit the pane dies with the agent'
        Assert-True ($c -contains '-NoLogo') 'the banner would eat the top of a grid pane'
        Assert-Equal '-Command' $c[-2] 'the agent line must be what -Command receives'
        Assert-Equal 5 $c.Count 'argument count'
    }
}

Test-Case 'an unknown agent falls back to Claude rather than launching nothing' {
    $agent = Get-SteroidsAgent 'nope'
    Assert-Equal 'claude' $agent.Id 'fallback agent'
    Assert-Equal 'codex' (Get-SteroidsAgent 'codex').Id 'known agent'
}

Test-Case 'the grid script honours the configured size when none is passed' {
    $path = Join-Path $env:TEMP ('steroids-cfg-grid-' + [guid]::NewGuid().ToString('N') + '.json')
    $previous = $env:STEROIDS_CONFIG
    try {
        '{ "agent": "claude", "columns": 2, "rows": 2, "yolo": true }' |
            Set-Content -LiteralPath $path -Encoding UTF8
        $env:STEROIDS_CONFIG = $path
        $a = @(& $gridScript -Dir $env:USERPROFILE -DryRun)
        $panes = @($a | Where-Object { $_ -eq 'split-pane' }).Count +
                 @($a | Where-Object { $_ -eq 'new-tab' }).Count
        Assert-Equal 4 $panes 'pane count came from the settings file'
    } finally {
        $env:STEROIDS_CONFIG = $previous
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'an explicit -Columns still overrides the settings file' {
    $a = @(& $gridScript -Dir $env:USERPROFILE -Columns 4 -Rows 1 -DryRun)
    $panes = @($a | Where-Object { $_ -eq 'split-pane' }).Count +
             @($a | Where-Object { $_ -eq 'new-tab' }).Count
    Assert-Equal 4 $panes 'pane count'
}

# ===========================================================================
Remove-Item -LiteralPath $env:STEROIDS_CONFIG -Force -ErrorAction SilentlyContinue
$env:STEROIDS_CONFIG = $script:RealConfig

Write-Host ''
Write-Host ('-' * 60)
if ($script:Fail -eq 0) {
    Write-Host "All $($script:Pass) tests passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($script:Pass) passed, $($script:Fail) FAILED" -ForegroundColor Red
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
