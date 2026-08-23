#!/bin/zsh
# Claude Code — Steroids Mode (macOS)
# Shared settings, dot-sourced by the other scripts.
#
# One small JSON file drives every entry point — the menu bar app, its global
# hotkeys, and the Finder Quick Actions — so switching agent in Settings changes
# all of them at once:
#
#   ~/.config/claude-code-steroids/config.json
#   { "version": 1, "agent": "claude", "yolo": true,
#     "columns": 3, "rows": 3, "paths": { "claude": "", "codex": "" } }
#
# Every field is optional. A missing, unreadable or half-written file falls back
# to the defaults below rather than failing — a broken config must never be the
# reason a hotkey stops opening a session.

STEROIDS_CONFIG="${STEROIDS_CONFIG:-$HOME/.config/claude-code-steroids/config.json}"

# ------------------------------------------------------------------ agents --
# Adding an agent is one line here plus one in the Swift settings window.
# The YOLO flag is per-agent because each CLI spells it differently; with YOLO
# off we pass nothing at all, so each CLI behaves exactly as it does on its own.
steroids_agent_bin()    { [[ "$1" == codex ]] && print -r -- codex || print -r -- claude }
steroids_agent_label()  { [[ "$1" == codex ]] && print -r -- "OpenAI Codex" || print -r -- "Claude Code" }
steroids_agent_yolo()   {
  [[ "$1" == codex ]] && print -r -- "--dangerously-bypass-approvals-and-sandbox" \
                      || print -r -- "--dangerously-skip-permissions"
}

# ------------------------------------------------------------------- args --
# Every entry point passes a folder; the per-agent Quick Actions add
# "--agent claude" or "--agent codex" to pin one regardless of the setting.
# Sets STEROIDS_DIR and STEROIDS_AGENT_OVERRIDE.
steroids_parse_args() {
	STEROIDS_DIR=""
	STEROIDS_AGENT_OVERRIDE=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--agent)   STEROIDS_AGENT_OVERRIDE="$2"; shift 2 ;;
			--agent=*) STEROIDS_AGENT_OVERRIDE="${1#--agent=}"; shift ;;
			# First non-flag wins. Finder hands a Quick Action every selected
			# item, and opening nine sessions per file you happened to have
			# highlighted is nobody's intention.
			*)         [ -z "$STEROIDS_DIR" ] && STEROIDS_DIR="$1"; shift ;;
		esac
	done
	[ -z "$STEROIDS_DIR" ] && STEROIDS_DIR="$HOME"
}

# ------------------------------------------------------------------- read ---
# JXA is the only JSON parser guaranteed to be on a stock macOS (python3 is not
# — it needs the Command Line Tools). It reads the file, clamps every value into
# range, and emits plain "key<TAB>value" lines so nothing here has to eval.
_steroids_read_config() {
  /usr/bin/osascript -l JavaScript -e '
    function run(argv) {
      ObjC.import("Foundation");
      var cfg = {};
      try {
        var s = $.NSString.stringWithContentsOfFileEncodingError(
          argv[0], $.NSUTF8StringEncoding, $());
        if (s && s.js) { cfg = JSON.parse(s.js) || {}; }
      } catch (e) { cfg = {}; }
      if (typeof cfg !== "object" || cfg === null) cfg = {};

      // argv[1] is the --agent override: an explicit Quick Action names its
      // agent and must get that one whatever the settings file says.
      var want = argv[1] || "";
      var agent = (want === "claude" || want === "codex")
        ? want
        : ((cfg.agent === "codex") ? "codex" : "claude");
      var grid = function (v, d) {
        v = parseInt(v, 10);
        return (v >= 1 && v <= 8) ? v : d;
      };
      var paths = (cfg.paths && typeof cfg.paths === "object") ? cfg.paths : {};
      var p = (typeof paths[agent] === "string") ? paths[agent] : "";

      return [
        "agent\t" + agent,
        "yolo\t"  + (cfg.yolo === false ? "0" : "1"),
        "cols\t"  + grid(cfg.columns, 3),
        "rows\t"  + grid(cfg.rows, 3),
        "path\t"  + p
      ].join("\n");
    }' "$STEROIDS_CONFIG" "${1:-}" 2>/dev/null
}

# ---------------------------------------------------------------- resolve ---
# Where the agent actually lives. An explicit path from Settings wins; otherwise
# ask a LOGIN shell, because launchd starts the menu bar app with a bare PATH
# that has never heard of /opt/homebrew/bin. Resolving to a full path also means
# the AppleScript below does not depend on Terminal's own PATH.
# Falling back to the bare name keeps a session openable even when detection
# fails — the login shell inside Terminal may still find it.
steroids_resolve_bin() {
  local explicit="$1" bin="$2" found
  if [[ -n "$explicit" && -x "$explicit" ]]; then
    print -r -- "$explicit"
    return
  fi
  found="$(command -v "$bin" 2>/dev/null)"
  [[ -z "$found" ]] && found="$(/bin/zsh -lc "command -v ${bin}" 2>/dev/null)"
  print -r -- "${found:-$bin}"
}

# ----------------------------------------------------------------- quoting --
# A settings field and a folder name are both user text on their way into an
# AppleScript string literal that itself contains a shell command line. Both
# layers have to be escaped or a folder like  don't/  ends the literal early.
#
# Single quotes, with any embedded single quote closed-escaped-reopened, and
# deliberately NOT zsh's ${(q)}: (q) escapes whatever the CURRENT locale calls
# unprintable, and launchd hands Quick Actions and the menu bar app an
# environment with no LANG at all. In that C locale every byte of a Hebrew (or
# Japanese, or accented) folder name is "unprintable", so ${(q)} shredded
# ~/Desktop/אתר into a run of $'\220' escapes and cd failed on a folder that
# was sitting right there. This form never looks at the bytes at all.
steroids_shell_quote() {
	local s="$1" q="'"
	s="${s//$q/$q\\$q$q}"     # ' becomes '\''
	print -r -- "$q$s$q"
}

steroids_applescript_quote() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  print -r -- "\"$s\""
}

# -------------------------------------------------------------------- load --
# steroids_load_config [<agent-id>]
#
# Sets: STEROIDS_AGENT STEROIDS_LABEL STEROIDS_YOLO STEROIDS_COLS STEROIDS_ROWS
#       STEROIDS_BIN STEROIDS_CMD (a ready-to-run, shell-quoted command line)
#
# The optional agent id pins one agent for this run. Only the agent is pinned —
# grid size and the autonomy toggle still come from Settings, because those are
# preferences about how you work, not about which CLI you picked.
steroids_load_config() {
  local override="${1:-}"
  STEROIDS_AGENT=claude
  STEROIDS_YOLO=1
  STEROIDS_COLS=3
  STEROIDS_ROWS=3
  local configured_path=""

  local key value
  while IFS=$'\t' read -r key value; do
    case "$key" in
      agent) STEROIDS_AGENT="$value" ;;
      yolo)  STEROIDS_YOLO="$value" ;;
      cols)  STEROIDS_COLS="$value" ;;
      rows)  STEROIDS_ROWS="$value" ;;
      path)  configured_path="$value" ;;
    esac
  done < <(_steroids_read_config "$override")

  STEROIDS_LABEL="$(steroids_agent_label "$STEROIDS_AGENT")"
  STEROIDS_BIN="$(steroids_resolve_bin "$configured_path" "$(steroids_agent_bin "$STEROIDS_AGENT")")"

  STEROIDS_CMD="$(steroids_shell_quote "$STEROIDS_BIN")"
  if [[ "$STEROIDS_YOLO" == 1 ]]; then
    STEROIDS_CMD="$STEROIDS_CMD $(steroids_agent_yolo "$STEROIDS_AGENT")"
  fi
}
