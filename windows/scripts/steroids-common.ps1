# Claude Code — Steroids Mode (Windows)
# Shared helpers, dot-sourced by the other scripts. Kept deliberately small so
# every script still reads on its own.

# ---------------------------------------------------------------- paths & UI --

# Explorer hands the clicked folder to the context-menu command as "%V". When
# that folder is a drive root the value ends in a backslash ("C:\"), and on the
# resulting command line the pair \" is parsed as an escaped quote — so the
# script receives 'C:"' instead of 'C:\'. A real Windows path can never end in a
# quote, so restoring the backslash is unambiguous.
function Resolve-TargetDir {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $env:USERPROFILE }

    $Path = $Path.Trim()
    if ($Path.EndsWith('"')) { $Path = $Path.Substring(0, $Path.Length - 1) + '\' }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $env:USERPROFILE }
    return (Resolve-Path -LiteralPath $Path).ProviderPath
}

# These scripts are launched with -WindowStyle Hidden (from the context menu and
# from the tray app), so a plain Write-Error would be invisible. Surface real
# problems in a message box instead.
function Show-SteroidsError {
    param([string]$Message)

    Write-Error $Message
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show(
            $Message, 'Claude Code — Steroids',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    } catch { }
}

# Windows Terminal ships as an execution alias (wt.exe under WindowsApps), which
# resolves to a 0-byte reparse point — so ask the command resolver, never the
# file system.
function Test-WindowsTerminal {
    return [bool](Get-Command wt.exe -ErrorAction SilentlyContinue)
}

function Test-ClaudeCli {
    return [bool](Get-Command claude -ErrorAction SilentlyContinue)
}

# Every pane runs Claude inside cmd /k so the pane survives Claude exiting and
# leaves you a shell to work in.
#
# NOTE: --dangerously-skip-permissions ("YOLO mode") lets Claude read, edit and
# run commands without asking. Only point this at folders you trust. Remove the
# flag here to get the normal prompt-on-each-action behaviour.
function Get-ClaudePaneCommand {
    return @('cmd', '/k', 'claude --dangerously-skip-permissions')
}

# ------------------------------------------------------------ command lines --

# Windows PowerShell's Start-Process joins an -ArgumentList array with plain
# spaces and quotes nothing at all, so an everyday folder like "C:\My Projects"
# reaches wt.exe as two separate arguments: the session opens in C:\My, and the
# remainder of the path is parsed as a stray wt subcommand. Build the command
# line here instead, using the quoting rules CommandLineToArgvW reverses.
#
# Doubling the backslashes that run into the closing quote is what keeps a drive
# root intact: "C:\" would otherwise arrive as the literal C:" that
# Resolve-TargetDir exists to repair.
function Format-CommandLineArgument {
    param([string]$Argument)

    if ($Argument.Length -gt 0 -and $Argument -notmatch '[ \t"]') { return $Argument }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $i = 0
    while ($i -lt $Argument.Length) {
        $slashes = 0
        while ($i -lt $Argument.Length -and $Argument[$i] -eq '\') { $i++; $slashes++ }
        if ($i -ge $Argument.Length) {
            [void]$sb.Append('\' * ($slashes * 2))
        } elseif ($Argument[$i] -eq '"') {
            [void]$sb.Append('\' * ($slashes * 2 + 1))
            [void]$sb.Append('"')
            $i++
        } else {
            if ($slashes -gt 0) { [void]$sb.Append('\' * $slashes) }
            [void]$sb.Append($Argument[$i])
            $i++
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Windows Terminal splits its own command list on bare semicolon arguments, so
# the delimiters the grid builder adds stay raw while a semicolon inside a
# folder name is escaped as \; -- without that, "C:\notes; drafts" would end the
# new-tab command early and feed wt the rest of the path as a subcommand.
function ConvertTo-WtCommandLine {
    param([string[]]$Arguments)

    $parts = foreach ($a in $Arguments) {
        if ($a -eq ';') { ';' } else { Format-CommandLineArgument ($a -replace ';', '\;') }
    }
    return ($parts -join ' ')
}

function Start-WindowsTerminal {
    param([string[]]$Arguments)

    Start-Process wt.exe -ArgumentList (ConvertTo-WtCommandLine $Arguments)
}

# ------------------------------------------------------------------ interop --

$script:SteroidsInterop = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class SteroidsWin {
    delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] static extern bool MoveWindow(IntPtr hWnd, int x, int y, int w, int h, bool repaint);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO mi);
    [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint p, ref RECT rect, uint winIni);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("dwmapi.dll")]  static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out int val, int size);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public uint dwFlags; }

    [ComImport, Guid("a5cd92ff-29be-454c-8d04-d82879fb3f1b"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IVirtualDesktopManager {
        bool IsWindowOnCurrentVirtualDesktop(IntPtr topLevelWindow);
        Guid GetWindowDesktopId(IntPtr topLevelWindow);
        void MoveWindowToDesktop(IntPtr topLevelWindow, ref Guid desktopId);
    }
    [ComImport, Guid("aa509086-5ca9-4c25-8f95-589d3c07b48a")]
    class VirtualDesktopManager { }

    // Window metrics and MoveWindow both speak physical pixels. A process that
    // has not declared DPI awareness is fed *virtualised* coordinates instead,
    // so on any display scaled above 100% the grid would be computed against a
    // shrunken desktop and pile up in the top-left corner. Declare awareness
    // before reading anything. -4 = PER_MONITOR_AWARE_V2 (Win10 1703+); the
    // older per-process call is the fallback on anything earlier.
    public static void MakeDpiAware() {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch { }
        try { SetProcessDPIAware(); } catch { }
    }

    static bool IsCloaked(IntPtr hWnd) {
        int cloaked;
        // 14 = DWMWA_CLOAKED: composed but not shown, which is how windows on
        // another virtual desktop and suspended store apps present themselves.
        if (DwmGetWindowAttribute(hWnd, 14, out cloaked, sizeof(int)) != 0) return false;
        return cloaked != 0;
    }

    // All top-level windows of the named process. currentDesktopOnly keeps just
    // the ones on the virtual desktop you are looking at right now.
    public static IntPtr[] Find(string processName, bool currentDesktopOnly) {
        var pids = new HashSet<uint>();
        foreach (var p in System.Diagnostics.Process.GetProcessesByName(processName))
            pids.Add((uint)p.Id);

        var wins = new List<IntPtr>();
        if (pids.Count == 0) return wins.ToArray();

        IVirtualDesktopManager vdm = null;
        if (currentDesktopOnly) {
            try { vdm = (IVirtualDesktopManager)new VirtualDesktopManager(); } catch { }
        }

        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
            if (!IsWindowVisible(hWnd) || IsIconic(hWnd)) return true;
            if (GetWindowTextLength(hWnd) == 0) return true;
            uint pid; GetWindowThreadProcessId(hWnd, out pid);
            if (!pids.Contains(pid)) return true;
            if (currentDesktopOnly) {
                if (IsCloaked(hWnd)) return true;
                if (vdm != null) {
                    try { if (!vdm.IsWindowOnCurrentVirtualDesktop(hWnd)) return true; } catch { }
                }
            }
            wins.Add(hWnd);
            return true;
        }, IntPtr.Zero);

        // EnumWindows hands back z-order, which reshuffles as you click around.
        // Sorting by position keeps tiling stable between runs.
        wins.Sort(delegate(IntPtr a, IntPtr b) {
            RECT ra, rb;
            GetWindowRect(a, out ra); GetWindowRect(b, out rb);
            if (ra.Top != rb.Top) return ra.Top.CompareTo(rb.Top);
            return ra.Left.CompareTo(rb.Left);
        });
        return wins.ToArray();
    }

    // Work area (taskbar excluded) of the monitor the user is currently looking
    // at — the Windows equivalent of macOS's NSScreen.mainScreen.
    public static RECT WorkArea() {
        IntPtr mon = MonitorFromWindow(GetForegroundWindow(), 2 /* MONITOR_DEFAULTTONEAREST */);
        if (mon != IntPtr.Zero) {
            var mi = new MONITORINFO();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
            if (GetMonitorInfo(mon, ref mi)) return mi.rcWork;
        }
        var area = new RECT();
        SystemParametersInfo(0x0030 /* SPI_GETWORKAREA */, 0, ref area, 0);
        return area;
    }

    public static RECT Bounds(IntPtr hWnd) {
        RECT r;
        GetWindowRect(hWnd, out r);
        return r;
    }

    public static void Place(IntPtr hWnd, int x, int y, int w, int h) {
        if (IsZoomed(hWnd)) ShowWindow(hWnd, 9); // SW_RESTORE before moving
        MoveWindow(hWnd, x, y, w, h, true);
    }

    // Terminal tears a whole window down cleanly on WM_CLOSE — panes and their
    // processes included — without any "close all panes?" confirmation.
    public static void CloseWindow(IntPtr hWnd) {
        PostMessage(hWnd, 0x0010 /* WM_CLOSE */, IntPtr.Zero, IntPtr.Zero);
    }

    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, uint exitCode);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    // Terminal's default closeOnExit is "graceful": it retires a pane when the
    // process ends with exit code 0, and leaves a dead pane sitting there for
    // anything else. Stop-Process terminates with a failure code, which is why
    // killing a session used to leave an empty window behind — so end pane
    // processes with an exit code of 0 and the pane retires itself, exactly the
    // way pkill on a tty does on macOS.
    public static bool EndProcess(int pid, uint exitCode) {
        IntPtr h = OpenProcess(0x0001 /* PROCESS_TERMINATE */, false, pid);
        if (h == IntPtr.Zero) return false;
        bool ok = TerminateProcess(h, exitCode);
        CloseHandle(h);
        return ok;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);

    // One Windows Terminal process owns every window, so a window cannot be
    // told apart by its process. The title can: it is what lets the test suite
    // act on a window it opened itself and provably nothing else.
    public static string Title(IntPtr hWnd) {
        int len = GetWindowTextLength(hWnd);
        if (len <= 0) return "";
        var sb = new System.Text.StringBuilder(len + 1);
        GetWindowText(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    [DllImport("shell32.dll", SetLastError = true)]
    static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string cmdLine, out int argc);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr h);

    // The same parser CreateProcess'd programs use to split their command line.
    // Exposing it lets the tests check the quoting against Windows itself rather
    // than against a second reading of the rules. Note that the first token is
    // parsed by the special program-name rules, so callers pass a dummy there.
    public static string[] ParseCommandLine(string commandLine) {
        int argc;
        IntPtr argv = CommandLineToArgvW(commandLine, out argc);
        if (argv == IntPtr.Zero) return new string[0];
        try {
            var result = new string[argc];
            for (int i = 0; i < argc; i++)
                result[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(argv, i * IntPtr.Size));
            return result;
        } finally { LocalFree(argv); }
    }
}
'@

function Initialize-SteroidsInterop {
    if (-not ('SteroidsWin' -as [type])) { Add-Type -TypeDefinition $script:SteroidsInterop }
    [SteroidsWin]::MakeDpiAware()
}

# ------------------------------------------------------------ process trees --

# One Windows Terminal *process* owns every Terminal *window*, and each pane's
# shell is a direct child of it — so panes cannot be attributed to a particular
# window, but they can be attributed to Claude, which is what the close actions
# actually care about.
function Get-TerminalPaneShell {
    param([string]$ProcessName = 'WindowsTerminal')

    $hostPids = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    if ($hostPids.Count -eq 0) { return @() }

    # CIM hands back ParentProcessId as UInt32 while Get-Process reports Int32,
    # and a hashtable compares keys by type as well as value -- so keys stored
    # straight from CIM could never be found by a PID looked up here, every
    # lookup missed, and the close actions reported "no Claude sessions" no
    # matter how many were running. Normalise both sides to Int32.
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $byParent = @{}
    foreach ($p in $all) {
        $parent = [int]$p.ParentProcessId
        if (-not $byParent.ContainsKey($parent)) { $byParent[$parent] = @() }
        $byParent[$parent] += $p
    }

    $shells = @()
    foreach ($hostPid in $hostPids) {
        $hostPid = [int]$hostPid
        if (-not $byParent.ContainsKey($hostPid)) { continue }
        foreach ($child in $byParent[$hostPid]) {
            # OpenConsole is the pty host Terminal spawns alongside each pane,
            # not the shell you typed into.
            if ($child.Name -eq 'OpenConsole.exe') { continue }
            $shells += [pscustomobject]@{
                ProcessId   = $child.ProcessId
                Name        = $child.Name
                CommandLine = $child.CommandLine
                Descendants = (Get-DescendantProcess -Root $child.ProcessId -ByParent $byParent)
            }
        }
    }
    return $shells
}

function Get-DescendantProcess {
    param([int]$Root, [hashtable]$ByParent)

    # $ByParent is keyed by Int32 (see Get-TerminalPaneShell) and every id that
    # goes through this queue is one too, so the lookups actually hit.
    $out = @()
    $seen = New-Object System.Collections.Generic.HashSet[int]
    $queue = New-Object System.Collections.Generic.Queue[int]
    $queue.Enqueue([int]$Root)
    [void]$seen.Add([int]$Root)
    while ($queue.Count -gt 0) {
        $id = $queue.Dequeue()
        if (-not $ByParent.ContainsKey($id)) { continue }
        foreach ($c in $ByParent[$id]) {
            $childId = [int]$c.ProcessId
            # Windows recycles PIDs, so a stale parent link can point back up the
            # tree. Without this guard that becomes an endless walk.
            if (-not $seen.Add($childId)) { continue }
            $out += $c
            $queue.Enqueue($childId)
        }
    }
    return $out
}

# Claude reaches a pane by more than one shape. The native installer leaves a
# claude.exe in the tree, but an npm install runs the CLI as plain node.exe with
# the package path on its command line -- and matching node by name would put
# every unrelated Node process on the machine in the firing line. So match a
# claude command token, or the CLI package in a path, and nothing broader.
$script:ClaudeCommandPatterns = @(
    '(?:^|[\s"])(?:[^\s"]*[\\/])?claude(?:\.(?:exe|cmd|bat|ps1))?(?=$|[\s"])',
    '[\\/](?:@anthropic-ai[\\/])?claude-code[\\/]'
)

function Test-ClaudeProcess {
    param([psobject]$Process)

    if ($Process.Name -like 'claude*') { return $true }
    $cmd = $Process.CommandLine
    if ([string]::IsNullOrEmpty($cmd)) { return $false }
    foreach ($pattern in $script:ClaudeCommandPatterns) {
        if ($cmd -match $pattern) { return $true }
    }
    return $false
}

function Test-ShellRunsClaude {
    param([psobject]$Shell)

    if (Test-ClaudeProcess $Shell) { return $true }
    foreach ($d in $Shell.Descendants) {
        if (Test-ClaudeProcess $d) { return $true }
    }
    return $false
}

# Claude keeps itself current by shelling out to `npm install -g`, whose last act
# is renaming a staging directory into place. Stop-PaneSession ends every
# descendant of a pane, updater included -- and an install killed mid-rename is
# not one retry away from fine: the orphaned staging directory makes every later
# install fail ENOTEMPTY, so `claude` stays "not recognised" until someone clears
# it by hand. A pane with an install in flight is therefore left running. One
# stray window is much the cheaper mistake.
#
# Matching installs rather than package managers is the whole trick. MCP servers
# are launched as `npm exec`/`npx` and sit there for the life of the session, so
# a broader match would spare every pane and turn closing a swarm into a no-op.
# Hence a package manager AND a mutating verb -- plus install.cjs, which is how
# claude-code's own postinstall step (the one that fetches the native binary)
# shows up on a command line.
$script:PackageInstallPatterns = @(
    '(?:^|[\s"\\/])(?:npm-cli\.js|npm(?:\.cmd)?|pnpm(?:\.cmd)?|yarn(?:\.cmd)?|bun(?:\.exe)?)["\s]+(?:\S+\s+)*(?:install|i|ci|add|update|up|upgrade|rebuild|link)(?:\s|$)',
    'install\.[cm]?js(?:$|[\s"])'
)

function Test-PackageInstallProcess {
    param([psobject]$Process)

    $cmd = $Process.CommandLine
    if ([string]::IsNullOrEmpty($cmd)) { return $false }
    foreach ($pattern in $script:PackageInstallPatterns) {
        if ($cmd -match $pattern) { return $true }
    }
    return $false
}

function Test-ShellRunsPackageInstall {
    param([psobject]$Shell)

    if (Test-PackageInstallProcess $Shell) { return $true }
    foreach ($d in $Shell.Descendants) {
        if (Test-PackageInstallProcess $d) { return $true }
    }
    return $false
}

# A close action must never take out the session that asked for it. Run "Close
# ALL Claude Terminals" from a Claude session living in Windows Terminal and the
# sweep would find that pane too -- killing the shell you typed the command into
# and, in the test suite, ending the run partway through.
#
# The pane that hosts us is the one this process descends from, so the check
# reuses the tree Get-TerminalPaneShell already walked. Launched from the tray
# there is no such pane and nothing is skipped.
function Test-ShellHostsSelf {
    param([psobject]$Shell)

    if ([int]$Shell.ProcessId -eq $PID) { return $true }
    foreach ($d in $Shell.Descendants) {
        if ([int]$d.ProcessId -eq $PID) { return $true }
    }
    return $false
}

# End a pane: its descendants first (Claude itself, and anything Claude started),
# then the pane's own shell with an exit code of 0 so Terminal retires the pane
# instead of leaving a dead one on screen. A window whose last pane goes away
# closes itself, so a nine-pane swarm disappears in one step and never raises a
# confirmation dialog.
function Stop-PaneSession {
    param([psobject]$Shell)

    $descendants = @($Shell.Descendants)
    [array]::Reverse($descendants)
    foreach ($p in $descendants) {
        [void][SteroidsWin]::EndProcess([int]$p.ProcessId, 0)
    }
    [void][SteroidsWin]::EndProcess([int]$Shell.ProcessId, 0)
}
