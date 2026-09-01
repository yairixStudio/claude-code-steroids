// Claude Code — Steroids Mode (Windows)
// Lean system tray app: a small grid icon by the clock with three actions, each
// also bound to a global hotkey (RegisterHotKey — works from any app):
//
//   Ctrl+Alt+C  New Session        (one Windows Terminal window, in %USERPROFILE%)
//   Ctrl+Alt+S  Steroids Mode      (a tiled grid of independent windows, in %USERPROFILE%)
//   Ctrl+Alt+T  Arrange Terminals  (retile this virtual desktop's Terminal windows)
//
// Which agent those sessions run - Claude Code or OpenAI Codex - is a setting,
// not a hardcode. "Settings..." opens steroids-settings.ps1, which writes
// %APPDATA%\claude-code-steroids\config.json; the scripts read the same file,
// so one switch there changes every entry point at once.
//
// The Quit submenu tears a swarm back down: it ends each session's shell first, so
// Terminal retires the window without ever asking "close all panes?".
//
// Compiled at install time by install.ps1 (csc.exe, ships with Windows) and
// started at login via HKCU\...\Run. To change a combo: edit the Combos table
// below and re-run install.ps1.

using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

class SteroidsTray : Form
{
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr hIcon);

    const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_NOREPEAT = 0x4000;
    const int WM_HOTKEY = 0x0312;

    // id, key, what it runs, arguments. Ids match the macOS menu bar app.
    static readonly object[][] Combos = new object[][] {
        new object[] { 1, Keys.T, "arrange-terminals.ps1", "" },
        new object[] { 2, Keys.C, "open-in-claude.ps1",    "" },
        new object[] { 3, Keys.S, "steroids-grid.ps1",     "" },
    };

    readonly string scriptsDir =
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)
        + @"\claude-code-steroids";
    readonly string configPath =
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)
        + @"\claude-code-steroids\config.json";
    readonly NotifyIcon trayIcon;
    IntPtr iconHandle = IntPtr.Zero;
    ToolStripMenuItem sessionItem, steroidsItem;

    SteroidsTray()
    {
        ShowInTaskbar = false;

        var menu = new ContextMenuStrip();
        sessionItem  = AddItem(menu, "New Session",    "Ctrl+Alt+C", "open-in-claude.ps1",    "");
        steroidsItem = AddItem(menu, "Steroids Mode",  "Ctrl+Alt+S", "steroids-grid.ps1",     "");
        AddItem(menu, "Arrange Terminals",             "Ctrl+Alt+T", "arrange-terminals.ps1", "");
        menu.Items.Add(new ToolStripSeparator());
        AddItem(menu, "Settings...", "", "steroids-settings.ps1", "");
        menu.Items.Add(new ToolStripSeparator());

        // The two launch items name the selected agent and the configured grid
        // size, so the menu answers "what will this actually open?" without
        // going into Settings first. Re-read on every open, because Settings is
        // a separate process and nothing tells us when it saved.
        menu.Opening += delegate { Retitle(); };

        var quitMenu = new ContextMenuStrip();
        AddItem(quitMenu, "Close Terminals on This Desktop", "", "close-terminals.ps1", "-Mode desktop");
        AddItem(quitMenu, "Close ALL Agent Sessions",        "", "close-terminals.ps1", "-Mode agents");
        quitMenu.Items.Add(new ToolStripSeparator());
        var quitApp = new ToolStripMenuItem("Quit Tray App");
        quitApp.Click += delegate { ExitApp(); };
        quitMenu.Items.Add(quitApp);

        var quit = new ToolStripMenuItem("Quit");
        quit.DropDown = quitMenu;
        menu.Items.Add(quit);

        trayIcon = new NotifyIcon();
        trayIcon.Icon = BuildGridIcon();
        trayIcon.ContextMenuStrip = menu;
        trayIcon.Visible = true;
        trayIcon.DoubleClick += delegate { RunScript("open-in-claude.ps1", ""); };

        Retitle();
        RegisterHotKeys();
    }

    // Just enough of the config to label two menu items. The full read/write
    // lives in steroids-common.ps1 where the test suite can reach it, so this
    // stays a display detail: anything it cannot find falls back to what the
    // PowerShell side defaults to, and nothing here ever writes the file.
    string ConfigValue(string key, string fallback)
    {
        try
        {
            if (!File.Exists(configPath)) return fallback;
            var json = File.ReadAllText(configPath);
            var m = Regex.Match(json, "\"" + key + "\"\\s*:\\s*\"?([A-Za-z0-9_.-]+)\"?");
            return m.Success ? m.Groups[1].Value : fallback;
        }
        catch { return fallback; }
    }

    int ConfigInt(string key, int fallback)
    {
        int v;
        if (!int.TryParse(ConfigValue(key, ""), out v)) return fallback;
        return (v >= 1 && v <= 8) ? v : fallback;
    }

    void Retitle()
    {
        string label = ConfigValue("agent", "claude") == "codex" ? "OpenAI Codex" : "Claude Code";
        int sessions = ConfigInt("columns", 3) * ConfigInt("rows", 3);
        sessionItem.Text  = "New Session - " + label;
        steroidsItem.Text = "Steroids Mode - " + sessions + "x " + label;
        trayIcon.Text = "Claude Code - Steroids (" + label + ")";
    }

    // A 3x3 grid of squares, matching the macOS menu bar's square.grid.3x3 —
    // drawn here so the app stays a single file with no icon resource to ship.
    Icon BuildGridIcon()
    {
        var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.Transparent);
            using (var brush = new SolidBrush(Color.White))
            {
                for (int row = 0; row < 3; row++)
                    for (int col = 0; col < 3; col++)
                        g.FillRectangle(brush, 2 + col * 10, 2 + row * 10, 8, 8);
            }
        }
        iconHandle = bmp.GetHicon();
        bmp.Dispose();
        return Icon.FromHandle(iconHandle);
    }

    void RegisterHotKeys()
    {
        string failed = "";
        foreach (var c in Combos)
        {
            if (!RegisterHotKey(Handle, (int)c[0], MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, (uint)(Keys)c[1]))
                failed += (failed.Length > 0 ? ", " : "") + "Ctrl+Alt+" + ((Keys)c[1]);
        }
        // RegisterHotKey fails when another app already owns the combo. Say so
        // rather than leaving the user pressing a key that silently does nothing.
        if (failed.Length > 0)
        {
            trayIcon.BalloonTipTitle = "Claude Code — Steroids";
            trayIcon.BalloonTipText =
                "Another app already owns " + failed + ", so those shortcuts are inactive. "
                + "The tray menu still works; edit steroids-tray.cs and re-run install.ps1 to pick another combo.";
            trayIcon.BalloonTipIcon = ToolTipIcon.Warning;
            trayIcon.ShowBalloonTip(8000);
        }
    }

    ToolStripMenuItem AddItem(ContextMenuStrip menu, string title, string shortcut, string script, string args)
    {
        var item = new ToolStripMenuItem(title);
        if (shortcut.Length > 0) item.ShortcutKeyDisplayString = shortcut;
        string s = script, a = args;
        item.Click += delegate { RunScript(s, a); };
        menu.Items.Add(item);
        return item;
    }

    void RunScript(string name, string args)
    {
        try
        {
            var psi = new ProcessStartInfo(
                "powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \""
                + scriptsDir + "\\" + name + "\" " + args);
            psi.WindowStyle = ProcessWindowStyle.Hidden;
            psi.CreateNoWindow = true;
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Could not run " + name + ":\n" + ex.Message,
                            "Claude Code — Steroids",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY)
        {
            int id = (int)m.WParam;
            foreach (var c in Combos)
                if ((int)c[0] == id) { RunScript((string)c[2], (string)c[3]); break; }
        }
        base.WndProc(ref m);
    }

    // Keep the form permanently invisible — tray icon only.
    protected override void SetVisibleCore(bool value) { base.SetVisibleCore(false); }

    void ExitApp()
    {
        trayIcon.Visible = false;
        Application.Exit();
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        foreach (var c in Combos) UnregisterHotKey(Handle, (int)c[0]);
        trayIcon.Visible = false;
        trayIcon.Dispose();
        if (iconHandle != IntPtr.Zero) DestroyIcon(iconHandle);
        base.OnFormClosed(e);
    }

    [STAThread]
    static void Main()
    {
        // The installer starts the app and so does the Run key at login. Without
        // this, the second instance would silently fail to claim the hotkeys and
        // leave a duplicate icon in the tray.
        bool isFirst;
        using (var mutex = new Mutex(true, @"Local\ClaudeCodeSteroidsTray", out isFirst))
        {
            if (!isFirst) return;
            Application.EnableVisualStyles();
            Application.Run(new SteroidsTray());
            GC.KeepAlive(mutex);
        }
    }
}
