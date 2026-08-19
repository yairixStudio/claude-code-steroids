#!/bin/zsh
# Claude Code — Steroids Mode (macOS)
# Closes Terminal windows cleanly (processes are killed first, so Terminal
# never shows its "terminate running processes?" confirmation dialog).
#
# Usage: close-terminals.sh <mode> [--dry-run]
#   space   close ALL Terminal windows on the CURRENT desktop (Space) only
#   claude  close ALL Terminal windows (every Space) that are running Claude
#
# Current-Space detection: same CGWindowList bounds-matching trick as
# arrange-terminals.sh — needs no Accessibility/Screen Recording permission.
#
# Windows with a package install in flight are left open on purpose — see the
# note above INSTALLER below.

/usr/bin/osascript -l JavaScript - "$@" <<'JXA'
function run(argv) {
ObjC.import("AppKit");
ObjC.import("CoreGraphics");

const mode = argv[0] || "space";
const dry = argv.indexOf("--dry-run") !== -1;

const term = Application("Terminal");
if (!term.running()) return "Terminal is not running";
const me = Application.currentApplication();
me.includeStandardAdditions = true;

const targets = [];   // { id, ttys: ["ttys012", ...] }
const ttysOf = w => {
  const out = [];
  w.tabs().forEach(t => {
    try { const tty = t.tty(); if (tty) out.push(tty.replace("/dev/", "")); } catch (e) {}
  });
  return out;
};

if (mode === "space") {
  // Windows on the current Space only (1 = OnScreenOnly, 16 = ExcludeDesktopElements).
  ObjC.bindFunction("CFMakeCollectable", ["id", ["void *"]]);
  const cgInfo = ObjC.deepUnwrap(
    $.CFMakeCollectable($.CGWindowListCopyWindowInfo(1 | 16, 0))
  ) || [];
  const pool = cgInfo
    .filter(w => w.kCGWindowOwnerName === "Terminal" && w.kCGWindowLayer === 0)
    .map(w => w.kCGWindowBounds).filter(Boolean)
    .map(b => ({ x: b.X, y: b.Y, w: b.Width, h: b.Height, used: false }));
  const near = (a, b) => Math.abs(a - b) <= 2;
  term.windows().forEach(w => {
    try {
      if (w.miniaturized()) return;
      const b = w.bounds();
      const hit = pool.find(p => !p.used &&
        near(p.x, b.x) && near(p.y, b.y) && near(p.w, b.width) && near(p.h, b.height));
      if (!hit) return;
      hit.used = true;
      targets.push({ id: w.id(), ttys: ttysOf(w) });
    } catch (e) {}
  });
} else {
  // Every window (any Space) with a tab whose process list includes "claude".
  term.windows().forEach(w => {
    try {
      const hasClaude = w.tabs().some(t => {
        try { return t.processes().some(p => String(p) === "claude"); }
        catch (e) { return false; }
      });
      if (hasClaude) targets.push({ id: w.id(), ttys: ttysOf(w) });
    } catch (e) {}
  });
}

if (targets.length === 0) return "Nothing to close";

// A window is only ours to take if nothing on its ttys is halfway through a
// package install. Claude Code updates itself by shelling out to `npm install
// -g`, whose last step is renaming a staging directory into place — and pkill
// lands on every process sharing the tty, updater included. What a badly timed
// sweep leaves behind is not one retry away: the orphaned staging directory
// makes every later install fail ENOTEMPTY, so `claude` stays "command not
// found" until someone deletes it by hand. One window left open is the far
// cheaper mistake.
//
// Matching installs and not package managers is the whole trick — MCP servers
// launched as `npm exec`/`npx` sit on a tty for the life of the session, and
// skipping those would make closing a swarm a no-op. So: a package manager AND
// a mutating verb, plus install.cjs, which is how claude-code's own postinstall
// (the part that downloads the 281MB native binary) shows up.
const INSTALLER =
  "(^|[[:space:]/])(npm-cli\\.js|npm|pnpm|yarn|bun)[[:space:]]" +
  "([^[:space:]]+[[:space:]])*" +
  "(install|i|ci|add|update|up|upgrade|rebuild|link)([[:space:]]|$)" +
  "|install\\.[cm]?js";
const installingOn = tty => {
  try {
    return me.doShellScript(
      "/bin/ps -t " + tty + " -o args= 2>/dev/null | " +
      "/usr/bin/grep -Eq '" + INSTALLER + "' && echo busy || true") === "busy";
  } catch (e) { return false; }   // can't tell → treat as idle, as before
};

const busy = [];
const doomed = targets.filter(t => {
  if (t.ttys.some(installingOn)) { busy.push(t); return false; }
  return true;
});
const note = busy.length === 0 ? "" :
  " — left " + busy.length + " installing (" +
  busy.map(t => t.ttys.join("+")).join(", ") + ")";

if (dry) {
  return "[dry-run] would close " + doomed.length + " window(s): " +
    doomed.map(t => t.ttys.join("+")).join(", ") + note;
}
if (doomed.length === 0) return "Nothing to close" + note;

// Kill the sessions' processes first so closing never pops a dialog.
// Kill by explicit PID from a tty-scoped `ps -t` (the kernel filters by tty
// before anything is inspected) — NOT `pkill -t`, which walks every PID on
// the system and, on macOS 26 (Tahoe), makes TCC fire one "access data from
// other apps" prompt per unrelated app it touches (WhatsApp, Music, …).
doomed.forEach(t => t.ttys.forEach(tty => {
  try {
    me.doShellScript(
      "/bin/kill -- $(/bin/ps -t " + tty + " -o pid=) 2>/dev/null || true");
  } catch (e) {}
}));
delay(0.5);

// Close by window id — index-based references shift as windows disappear.
let closed = 0;
doomed.forEach(t => {
  try { term.windows.byId(t.id).close(); closed++; } catch (e) {}
});
return "Closed " + closed + " window(s)" + note;
}
JXA
