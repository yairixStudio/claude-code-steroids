#!/bin/zsh
# Claude Code — Steroids Mode (macOS)
# Arranges all Terminal windows on the CURRENT desktop (Space) into a grid
# sized to the window count: 4 → 2×2, 9 → 3×3, 10 → 4×3, 16 → 4×4 …
#
# Current-Space detection: CGWindowList's "on screen only" option returns only
# windows on the active Space — and reading window BOUNDS (unlike names) needs
# no Accessibility or Screen Recording permission. We match those bounds to
# Terminal's scriptable windows and retile the matches via Terminal scripting.
# Only permission needed: Automation → Terminal (auto-prompts once).

/usr/bin/osascript -l JavaScript <<'JXA'
(function () {
ObjC.import("AppKit");
ObjC.import("CoreGraphics");

// Visible screen area (excludes menu bar + Dock). AppKit y-axis is bottom-up;
// window bounds are top-down, so convert.
const screen = $.NSScreen.mainScreen;
const full = screen.frame, vis = screen.visibleFrame;
const X = Math.round(vis.origin.x);
const Y = Math.round(full.size.height - (vis.origin.y + vis.size.height)); // top inset (menu bar / notch)
const W = Math.round(vis.size.width);
const H = Math.round(vis.size.height);

const term = Application("Terminal");
if (!term.running()) return "Terminal is not running";

// Bounds of Terminal windows on the current Space (1 = OnScreenOnly,
// 16 = ExcludeDesktopElements; 0 = NullWindowID). Layer 0 = real windows.
// CFMakeCollectable bridges the raw CFArrayRef into something deepUnwrap groks.
ObjC.bindFunction("CFMakeCollectable", ["id", ["void *"]]);
const cgInfo = ObjC.deepUnwrap(
  $.CFMakeCollectable($.CGWindowListCopyWindowInfo(1 | 16, 0))
) || [];
const onSpace = cgInfo
  .filter(w => w.kCGWindowOwnerName === "Terminal" && w.kCGWindowLayer === 0)
  .map(w => w.kCGWindowBounds)
  .filter(Boolean);

// Match Terminal's scriptable windows (which span ALL Spaces) to the
// current-Space bounds. Tolerant one-to-one matching, so duplicates pair up.
const pool = onSpace.map(b => ({ x: b.X, y: b.Y, w: b.Width, h: b.Height, used: false }));
const near = (a, b) => Math.abs(a - b) <= 2;
const targets = [];
term.windows().forEach(w => {
  try {
    if (w.miniaturized()) return;
    const b = w.bounds();
    const hit = pool.find(p => !p.used &&
      near(p.x, b.x) && near(p.y, b.y) && near(p.w, b.width) && near(p.h, b.height));
    if (!hit) return;
    hit.used = true;
    targets.push(w);
  } catch (e) {}
});

const n = targets.length;
if (n === 0) return "No Terminal windows on this desktop";

// Grid: square-ish, wider before taller (10 → 4 cols × 3 rows).
const cols = Math.ceil(Math.sqrt(n));
const rows = Math.ceil(n / cols);
const cw = Math.floor(W / cols);
const ch = Math.floor(H / rows);

targets.forEach((w, idx) => {
  const col = idx % cols;
  const row = Math.floor(idx / cols);
  const x1 = X + col * cw;
  const y1 = Y + row * ch;
  try { w.bounds = { x: x1, y: y1, width: cw, height: ch }; } catch (e) {}
});

term.activate();
return `Arranged ${n} windows in a ${cols}×${rows} grid`;
})();
JXA
