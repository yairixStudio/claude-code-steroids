// Claude Code — Steroids Mode (Windows)
// Lean system tray app: a small grid icon by the clock. The menu leads with a
// block per agent — "New Session" plus a "Steroids Mode" submenu of grid shapes
// (2x2 … 4x4) — so one click launches any agent in any grid without a detour
// through Settings. Three of those actions are also bound to a global hotkey
// (RegisterHotKey — works from any app):
//
//   Ctrl+Alt+C  New Session        (one Windows Terminal window, in %USERPROFILE%)
//   Ctrl+Alt+S  Steroids Mode      (a tiled grid of independent windows, in %USERPROFILE%)
//   Ctrl+Alt+T  Arrange Terminals  (retile this virtual desktop's Terminal windows)
//
// Which agent and which grid the hotkeys use - Claude Code or OpenAI Codex, 3x3
// or something else - is a setting, not a hardcode. "Settings..." opens
// steroids-settings.ps1, which writes %APPDATA%\claude-code-steroids\config.json;
// the scripts read the same file, so one switch there changes every entry point
// at once. The submenu rows are one-run overrides (-Agent / -Columns / -Rows on
// the command line) and never write it.
//
// The Quit submenu tears a swarm back down: it ends each session's shell first, so
// Terminal retires the window without ever asking "close all panes?".
//
// Compiled at install time by install.ps1 (csc.exe, ships with Windows) and
// started at login via HKCU\...\Run. To change a combo: edit the Combos table
// below and re-run install.ps1.

using System;
using System.Collections.Generic;
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
    // Agent id as the scripts spell it, and the label a person reads. Adding an
    // agent is one row here and one in $script:SteroidsAgents; the suite checks
    // that the two lists still agree.
    static readonly string[][] Agents = new string[][] {
        new string[] { "claude", "Claude Code" },
        new string[] { "codex",  "OpenAI Codex" },
    };

    // Columns, rows. The same shapes the Settings dropdown offers. The canonical
    // list is $script:SteroidsGridChoices in steroids-common.ps1, which this exe
    // cannot read -- so run-tests.ps1 holds the two side by side and fails if a
    // shape is added to one and forgotten in the other.
    static readonly int[][] GridShapes = new int[][] {
        new int[] { 2, 2 }, new int[] { 3, 2 }, new int[] { 3, 3 },
        new int[] { 4, 3 }, new int[] { 4, 4 },
    };

    readonly NotifyIcon trayIcon;
    readonly ContextMenuStrip menu = new ContextMenuStrip();
    IntPtr iconHandle = IntPtr.Zero;

    // The block at the top of the menu: per agent, "New Session - <agent>" and a
    // "Steroids Mode - <agent>" submenu with one row per grid shape. Rebuilt on
    // every open rather than retitled, because its ORDER depends on Settings --
    // the selected agent leads and is the one showing Ctrl+Alt+C / Ctrl+Alt+S,
    // and the configured grid carries the check mark. That is what lets the menu
    // still answer "what will the hotkey launch?" at a glance now that it also
    // offers eight other things.
    readonly List<ToolStripItem> agentBlock = new List<ToolStripItem>();

    SteroidsTray()
    {
        ShowInTaskbar = false;

        RebuildAgentBlock();
        AddItem(menu.Items, "Arrange Terminals", "Ctrl+Alt+T", "arrange-terminals.ps1", "");
        menu.Items.Add(new ToolStripSeparator());
        AddItem(menu.Items, "Settings...", "", "steroids-settings.ps1", "");
        menu.Items.Add(new ToolStripSeparator());

        // Re-read on every open: Settings is a separate process and nothing
        // tells us when it saved.
        menu.Opening += delegate { RebuildAgentBlock(); };

        var quitMenu = new ContextMenuStrip();
        AddItem(quitMenu.Items, "Close Terminals on This Desktop", "", "close-terminals.ps1", "-Mode desktop");
        AddItem(quitMenu.Items, "Close ALL Agent Sessions",        "", "close-terminals.ps1", "-Mode agents");
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

        RebuildAgentBlock();   // again, now that there is a tray icon to retitle
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

    void RebuildAgentBlock()
    {
        // Disposed, not just removed: this runs on every menu open, and the
        // discarded items own submenus of their own.
        foreach (var old in agentBlock) { menu.Items.Remove(old); old.Dispose(); }
        agentBlock.Clear();

        string selectedId = ConfigValue("agent", "claude");
        int cols = ConfigInt("columns", 3), rows = ConfigInt("rows", 3);

        // Selected agent first, the rest after. An id the file names that we do
        // not know falls back to the first agent, the way Get-SteroidsAgent does
        // -- a hand-edited config must never be the reason the menu comes up
        // empty.
        var ordered = new List<string[]>();
        foreach (var a in Agents) if (a[0] == selectedId) ordered.Add(a);
        if (ordered.Count == 0) ordered.Add(Agents[0]);
        foreach (var a in Agents) if (a[0] != ordered[0][0]) ordered.Add(a);

        var block = new List<ToolStripItem>();
        for (int i = 0; i < ordered.Count; i++)
        {
            string id = ordered[i][0], label = ordered[i][1];
            bool lead = (i == 0);

            block.Add(MakeItem("New Session - " + label, lead ? "Ctrl+Alt+C" : "",
                               "open-in-claude.ps1", "-Agent " + id));

            var steroids = new ToolStripMenuItem("Steroids Mode - " + label);
            foreach (var row in GridItems(id, cols, rows, lead)) steroids.DropDownItems.Add(row);
            block.Add(steroids);
            block.Add(new ToolStripSeparator());
        }

        for (int i = 0; i < block.Count; i++) menu.Items.Insert(i, block[i]);
        agentBlock.AddRange(block);

        // Called once before the tray icon exists, to fill the menu, and again
        // after — and on every open thereafter.
        if (trayIcon != null)
            trayIcon.Text = "Claude Code - Steroids (" + ordered[0][1] + ", " + cols + "x" + rows + ")";
    }

    // One row per shape, and the configured shape first if a hand-edited config
    // names one the table does not offer (5x5, say). It still gets a row, with
    // the check mark, because it is what Ctrl+Alt+S will launch -- a menu that
    // hides that is a menu that lies.
    //
    // Every row pins BOTH the agent and the shape on the command line, so a pick
    // here is a one-run override: steroids-grid.ps1 never writes what it was
    // passed back to the settings file. The hotkey passes nothing and keeps
    // launching whatever Settings says, which is why the checked row is also the
    // row that shows the hotkey.
    List<ToolStripItem> GridItems(string agentId, int cols, int rows, bool hotkeyed)
    {
        var shapes = new List<int[]>();
        bool listed = false;
        foreach (var g in GridShapes) if (g[0] == cols && g[1] == rows) listed = true;
        if (!listed) shapes.Add(new int[] { cols, rows });
        shapes.AddRange(GridShapes);

        var items = new List<ToolStripItem>();
        foreach (var g in shapes)
        {
            bool isDefault = (g[0] == cols && g[1] == rows);
            var it = MakeItem(GridLabel(g[0], g[1]),
                              (isDefault && hotkeyed) ? "Ctrl+Alt+S" : "",
                              "steroids-grid.ps1",
                              "-Agent " + agentId + " -Columns " + g[0] + " -Rows " + g[1]);
            it.Checked = isDefault;
            items.Add(it);
        }
        return items;
    }

    // Spelled exactly as Get-SteroidsGridLabel spells it in steroids-common.ps1,
    // so a shape reads the same in the submenu and in the Settings dropdown.
    static string GridLabel(int cols, int rows)
    {
        return cols + " x " + rows + "  -  " + (cols * rows) + " sessions";
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

    // Split in two because the agent block builds its items before it knows
    // where they go: a submenu row lands in a DropDownItems collection, a
    // top-level one in the menu's own, and the block is inserted as a unit.
    ToolStripMenuItem MakeItem(string title, string shortcut, string script, string args)
    {
        var item = new ToolStripMenuItem(title);
        if (shortcut.Length > 0) item.ShortcutKeyDisplayString = shortcut;
        string s = script, a = args;
        item.Click += delegate { RunScript(s, a); };
        return item;
    }

    ToolStripMenuItem AddItem(ToolStripItemCollection items, string title, string shortcut, string script, string args)
    {
        var item = MakeItem(title, shortcut, script, args);
        items.Add(item);
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
