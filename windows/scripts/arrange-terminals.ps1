# Claude Code — Steroids Mode (Windows)
# Arranges all Windows Terminal windows on the CURRENT virtual desktop into a
# grid sized to the window count: 4 -> 2x2, 9 -> 3x3, 10 -> 4x3, 16 -> 4x4 ...
#
# Current-desktop detection: IVirtualDesktopManager (a documented shell COM
# interface) reports whether a window lives on the active virtual desktop.
# Minimized windows and windows on other desktops are left alone.
#
# Usage: arrange-terminals.ps1   (no arguments, no admin rights)

$src = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Tiler {
    delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] static extern bool MoveWindow(IntPtr hWnd, int x, int y, int w, int h, bool repaint);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint p, ref RECT rect, uint winIni);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [ComImport, Guid("a5cd92ff-29be-454c-8d04-d82879fb3f1b"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IVirtualDesktopManager {
        bool IsWindowOnCurrentVirtualDesktop(IntPtr topLevelWindow);
        Guid GetWindowDesktopId(IntPtr topLevelWindow);
        void MoveWindowToDesktop(IntPtr topLevelWindow, ref Guid desktopId);
    }
    [ComImport, Guid("aa509086-5ca9-4c25-8f95-589d3c07b48a")]
    class VirtualDesktopManager { }

    public static string Arrange(string processName) {
        var pids = new HashSet<uint>();
        foreach (var p in System.Diagnostics.Process.GetProcessesByName(processName))
            pids.Add((uint)p.Id);
        if (pids.Count == 0) return processName + " is not running";

        IVirtualDesktopManager vdm = null;
        try { vdm = (IVirtualDesktopManager)new VirtualDesktopManager(); } catch { }

        var wins = new List<IntPtr>();
        EnumWindows((hWnd, lParam) => {
            if (!IsWindowVisible(hWnd) || IsIconic(hWnd)) return true;
            if (GetWindowTextLength(hWnd) == 0) return true;
            uint pid; GetWindowThreadProcessId(hWnd, out pid);
            if (!pids.Contains(pid)) return true;
            if (vdm != null) {
                try { if (!vdm.IsWindowOnCurrentVirtualDesktop(hWnd)) return true; } catch { }
            }
            wins.Add(hWnd);
            return true;
        }, IntPtr.Zero);

        int n = wins.Count;
        if (n == 0) return "No " + processName + " windows on this desktop";

        // Primary monitor work area (excludes the taskbar). 0x0030 = SPI_GETWORKAREA.
        var area = new RECT();
        SystemParametersInfo(0x0030, 0, ref area, 0);

        // Grid: square-ish, wider before taller (10 -> 4 cols x 3 rows).
        int cols = (int)Math.Ceiling(Math.Sqrt(n));
        int rows = (int)Math.Ceiling((double)n / cols);
        int cw = (area.Right - area.Left) / cols;
        int ch = (area.Bottom - area.Top) / rows;

        for (int i = 0; i < n; i++) {
            if (IsZoomed(wins[i])) ShowWindow(wins[i], 9); // SW_RESTORE first
            MoveWindow(wins[i],
                       area.Left + (i % cols) * cw,
                       area.Top + (i / cols) * ch,
                       cw, ch, true);
        }
        return "Arranged " + n + " windows in a " + cols + "x" + rows + " grid";
    }
}
'@

Add-Type -TypeDefinition $src
Write-Host ([Tiler]::Arrange("WindowsTerminal"))
