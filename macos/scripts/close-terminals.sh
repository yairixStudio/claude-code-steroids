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
if (dry) {
  return "[dry-run] would close " + targets.length + " window(s): " +
    targets.map(t => t.ttys.join("+")).join(", ");
}

// Kill the sessions' processes first so closing never pops a dialog.
targets.forEach(t => t.ttys.forEach(tty => {
  try { me.doShellScript("/usr/bin/pkill -t " + tty + " || true"); } catch (e) {}
}));
delay(0.5);

// Close by window id — index-based references shift as windows disappear.
let closed = 0;
targets.forEach(t => {
  try { term.windows.byId(t.id).close(); closed++; } catch (e) {}
});
return "Closed " + closed + " window(s)";
}
JXA
