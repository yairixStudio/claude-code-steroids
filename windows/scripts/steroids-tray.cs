// Claude Code — Steroids Mode (Windows)
// Lean system tray app: a small icon by the clock with three actions, each
// also bound to a global hotkey (RegisterHotKey — works from any app):
//
//   Ctrl+Alt+C  New Claude Session        (one Windows Terminal window, YOLO mode, in %USERPROFILE%)
//   Ctrl+Alt+S  Steroids Mode (3x3 grid)  (nine panes in one window, in %USERPROFILE%)
//   Ctrl+Alt+T  Arrange Terminals         (retile current virtual desktop's WT windows)
//
// Compiled at install time by install.ps1 (csc.exe, ships with Windows) and
// started at login via HKCU\...\Run. To change a combo: edit the RegisterHotKey
// calls below and re-run install.ps1.

using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

class SteroidsTray : Form
{
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_NOREPEAT = 0x4000;
    const int WM_HOTKEY = 0x0312;

    readonly string scriptsDir =
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)
        + @"\claude-code-steroids";
    readonly NotifyIcon trayIcon;

    SteroidsTray()
    {
        ShowInTaskbar = false;

        var menu = new ContextMenuStrip();
        AddItem(menu, "New Claude Session",      "Ctrl+Alt+C", "open-in-claude.ps1");
        AddItem(menu, "Steroids Mode (3x3 Grid)", "Ctrl+Alt+S", "steroids-grid.ps1");
        AddItem(menu, "Arrange Terminals",        "Ctrl+Alt+T", "arrange-terminals.ps1");
        menu.Items.Add(new ToolStripSeparator());
        var quit = new ToolStripMenuItem("Quit");
        quit.Click += (s, e) => { trayIcon.Visible = false; Application.Exit(); };
        menu.Items.Add(quit);

        trayIcon = new NotifyIcon();
        trayIcon.Icon = SystemIcons.Application;
        trayIcon.Text = "Claude Code — Steroids";
        trayIcon.ContextMenuStrip = menu;
        trayIcon.Visible = true;

        // Hotkey ids match the macOS app: 1=arrange(T), 2=session(C), 3=steroids(S)
        RegisterHotKey(Handle, 1, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, (uint)Keys.T);
        RegisterHotKey(Handle, 2, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, (uint)Keys.C);
        RegisterHotKey(Handle, 3, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, (uint)Keys.S);
    }

    void AddItem(ContextMenuStrip menu, string title, string shortcut, string script)
    {
        var item = new ToolStripMenuItem(title);
        item.ShortcutKeyDisplayString = shortcut;
        item.Click += (s, e) => RunScript(script);
        menu.Items.Add(item);
    }

    void RunScript(string name)
    {
        var psi = new ProcessStartInfo(
            "powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \""
            + scriptsDir + "\\" + name + "\"");
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        psi.CreateNoWindow = true;
        Process.Start(psi);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY)
        {
            switch ((int)m.WParam)
            {
                case 1: RunScript("arrange-terminals.ps1"); break;
                case 2: RunScript("open-in-claude.ps1"); break;
                case 3: RunScript("steroids-grid.ps1"); break;
            }
        }
        base.WndProc(ref m);
    }

    // Keep the form permanently invisible — tray icon only.
    protected override void SetVisibleCore(bool value) { base.SetVisibleCore(false); }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        for (int id = 1; id <= 3; id++) UnregisterHotKey(Handle, id);
        trayIcon.Visible = false;
        base.OnFormClosed(e);
    }

    [STAThread]
    static void Main()
    {
        Application.EnableVisualStyles();
        Application.Run(new SteroidsTray());
    }
}
