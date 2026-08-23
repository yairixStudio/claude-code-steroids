#!/bin/zsh
# Claude Code — Steroids Mode :: macOS test suite
#
#   zsh macos/tests/run-tests.sh
#
# No framework, no dependencies, and nothing here opens a window, touches your
# settings, or goes near a running session — it all runs against the sources in
# this repo with a throwaway config.
#
# The locale tests are the reason this file exists. launchd hands Quick Actions
# and the menu bar app an environment with no LANG at all, so anything that
# quotes a path has to behave identically in a UTF-8 shell and in the C locale.
# It did not: zsh's ${(q)} escapes whatever the current locale calls
# unprintable, which in C is every byte of a Hebrew, Japanese or accented folder
# name — and a right-click on ~/Desktop/אתר produced a cd that failed on a
# folder sitting right there. Nothing caught it because nothing ran the scripts
# the way launchd does.

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"
SCRIPTS="$ROOT/scripts"
QUICK_ACTIONS="$ROOT/quick-actions"

PASS=0
FAIL=0
FAILURES=()

CYAN=$'\033[36m'; GREEN=$'\033[32m'; RED=$'\033[31m'; OFF=$'\033[0m'

section() { print -r -- ""; print -r -- "${CYAN}$1${OFF}" }

ok()   { PASS=$((PASS + 1)); print -r -- "  ${GREEN}PASS${OFF}  $1" }
bad()  { FAIL=$((FAIL + 1)); FAILURES+=("$1 :: $2")
         print -r -- "  ${RED}FAIL${OFF}  $1"; print -r -- "        $2" }

assert_eq() {  # <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi
}

assert_true() {  # <name> <condition-result 0/1> <message>
  if [[ "$2" == 0 ]]; then ok "$1"; else bad "$1" "$3"; fi
}

TMPDIR_TESTS="$(mktemp -d)"
CONFIG="$TMPDIR_TESTS/config.json"
trap 'rm -rf "$TMPDIR_TESTS"' EXIT
print -r -- '{"version":1,"agent":"claude","columns":3,"rows":3,"yolo":true,"paths":{}}' > "$CONFIG"

# ===========================================================================
section 'Syntax'
# ===========================================================================
for f in "$ROOT"/*.sh "$SCRIPTS"/*.sh; do
  if zsh -n "$f" 2>/dev/null; then ok "${f:t} parses"; else bad "${f:t} parses" "zsh -n failed"; fi
done

# ===========================================================================
section 'Shell quoting — the bug that broke every non-ASCII folder'
# ===========================================================================
# A quoted path has to survive being handed back to a shell byte for byte, in
# every locale. These are the names that actually break things: Hebrew (the
# reported failure), an apostrophe (which single quotes alone cannot hold), and
# the pile-up of quote, backslash and space.
paths=(
  '/Users/x/Desktop/אתר שאולי הורדה גיבוי'
  "/Users/x/don't stop"
  '/Users/x/say "hi" \there'
  '/Users/x/ünïcødé — dash'
  '/Users/x/日本語のフォルダ'
  '/Volumes/Drive/plain'
)
for loc in utf8 c clean; do
  for p in "${paths[@]}"; do
    print -r -- "#!/bin/zsh
source ${(q)SCRIPTS}/steroids-config.sh
q=\$(steroids_shell_quote \"\$1\")
/bin/zsh -c \"printf %s \$q\"" > "$TMPDIR_TESTS/q.sh"
    case "$loc" in
      utf8)  got="$(LC_ALL=en_US.UTF-8 /bin/zsh "$TMPDIR_TESTS/q.sh" "$p")" ;;
      c)     got="$(LC_ALL=C /bin/zsh "$TMPDIR_TESTS/q.sh" "$p")" ;;
      clean) got="$(env -u LANG -u LC_ALL -u LC_CTYPE /bin/zsh "$TMPDIR_TESTS/q.sh" "$p")" ;;
    esac
    assert_eq "[$loc] round-trips: ${p:t}" "$p" "$got"

    # Round-tripping through a shell is not enough, and believing it was is how
    # the original bug shipped. ${(q)} escaped only the bytes the C locale
    # called unprintable — 0x90 out of the middle of א — which a shell still
    # reassembles correctly, so a round-trip test stayed green. What it left
    # behind was no longer valid UTF-8, and the osascript layer downstream
    # re-read those orphaned bytes as Mac Roman and helpfully re-encoded them:
    # D7 became ◊, AA became ™. So assert the property that actually matters —
    # quoting never takes a multi-byte character apart.
    quoted="$(case "$loc" in
      utf8)  LC_ALL=en_US.UTF-8 /bin/zsh -c "source ${(q)SCRIPTS}/steroids-config.sh; steroids_shell_quote \"\$1\"" _ "$p" ;;
      c)     LC_ALL=C           /bin/zsh -c "source ${(q)SCRIPTS}/steroids-config.sh; steroids_shell_quote \"\$1\"" _ "$p" ;;
      clean) env -u LANG -u LC_ALL -u LC_CTYPE /bin/zsh -c "source ${(q)SCRIPTS}/steroids-config.sh; steroids_shell_quote \"\$1\"" _ "$p" ;;
    esac)"
    case "$quoted" in
      *\$\'*) bad "[$loc] quotes without byte escapes: ${p:t}" \
                 "quoting emitted a \$'..' escape, which splits UTF-8: $quoted" ;;
      *)       ok  "[$loc] quotes without byte escapes: ${p:t}" ;;
    esac
  done
done

# ===========================================================================
section 'AppleScript quoting'
# ===========================================================================
# The shell command line then goes inside an AppleScript string literal, and
# osascript has to hand back exactly what went in. Two layers, both byte-exact.
print -r -- "#!/bin/zsh
source ${(q)SCRIPTS}/steroids-config.sh
inner=\"cd \$(steroids_shell_quote \"\$1\") && exec agent\"
/usr/bin/osascript -e \"return \$(steroids_applescript_quote \"\$inner\")\"" > "$TMPDIR_TESTS/as.sh"

for p in '/Users/x/אתר שאולי' "/Users/x/don't" '/Users/x/say "hi" \there'; do
  want="cd $(source "$SCRIPTS/steroids-config.sh"; steroids_shell_quote "$p") && exec agent"
  got="$(env -u LANG -u LC_ALL -u LC_CTYPE /bin/zsh "$TMPDIR_TESTS/as.sh" "$p")"
  assert_eq "osascript returns the command unchanged: ${p:t}" "$want" "$got"
done

# ===========================================================================
section 'Settings'
# ===========================================================================
print -r -- "#!/bin/zsh
source ${(q)SCRIPTS}/steroids-config.sh
steroids_load_config \"\${1:-}\"
print -r -- \"\$STEROIDS_AGENT|\$STEROIDS_COLS|\$STEROIDS_ROWS|\$STEROIDS_YOLO\"" > "$TMPDIR_TESTS/cfg.sh"

read_cfg() { STEROIDS_CONFIG="$CONFIG" /bin/zsh "$TMPDIR_TESTS/cfg.sh" "$1" }

print -r -- '{"version":1,"agent":"codex","columns":4,"rows":2,"yolo":false}' > "$CONFIG"
assert_eq 'a complete file is read field for field' 'codex|4|2|0' "$(read_cfg)"

# A config edited into nonsense must never be why a hotkey stops working.
for junk in '{ not json' '{}' '[]' '"hello"' '{"agent":"gpt-9","columns":99,"rows":0}' \
            '{"agent":null,"columns":"three","yolo":"sure"}'; do
  print -r -- "$junk" > "$CONFIG"
  assert_eq "nonsense falls back to defaults: $junk" 'claude|3|3|1' "$(read_cfg)"
done

rm -f "$CONFIG"
assert_eq 'a missing file falls back to defaults' 'claude|3|3|1' "$(read_cfg)"

# --agent pins the CLI and nothing else: grid and autonomy stay yours.
print -r -- '{"version":1,"agent":"codex","columns":2,"rows":2,"yolo":false}' > "$CONFIG"
assert_eq 'an override pins the agent'            'claude|2|2|0' "$(read_cfg claude)"
assert_eq 'an override leaves grid and YOLO alone' 'codex|2|2|0'  "$(read_cfg codex)"
assert_eq 'an unknown override is ignored'         'codex|2|2|0'  "$(read_cfg martian)"

# ===========================================================================
section 'Argument parsing'
# ===========================================================================
print -r -- "#!/bin/zsh
source ${(q)SCRIPTS}/steroids-config.sh
steroids_parse_args \"\$@\"
print -r -- \"\$STEROIDS_DIR|\$STEROIDS_AGENT_OVERRIDE\"" > "$TMPDIR_TESTS/args.sh"
args() { /bin/zsh "$TMPDIR_TESTS/args.sh" "$@" }

assert_eq 'folder only'          "/tmp/x|"       "$(args /tmp/x)"
assert_eq 'folder then --agent'  "/tmp/x|codex"  "$(args /tmp/x --agent codex)"
assert_eq '--agent= form'        "/tmp/x|claude" "$(args /tmp/x --agent=claude)"
assert_eq 'no folder means home' "$HOME|"        "$(args)"
# Finder hands a Quick Action every selected item; only the first may win, or a
# multi-select would open a swarm per file.
assert_eq 'extra items are ignored' "/tmp/a|codex" "$(args /tmp/a /tmp/b /tmp/c --agent codex)"

# ===========================================================================
section 'Grid generation'
# ===========================================================================
# Build the AppleScript without running it, and check the loop bounds match the
# configured grid rather than a hard-coded nine.
sed 's|/usr/bin/osascript <<APPLESCRIPT|/bin/cat <<APPLESCRIPT|' \
    "$SCRIPTS/steroids-grid.sh" > "$TMPDIR_TESTS/grid.sh"
cp "$SCRIPTS/steroids-config.sh" "$TMPDIR_TESTS/steroids-config.sh"

for spec in "3 3 8" "2 2 3" "4 3 11" "1 1 0"; do
  read -r cols rows last <<< "$spec"
  print -r -- "{\"agent\":\"claude\",\"columns\":$cols,\"rows\":$rows,\"yolo\":true}" > "$CONFIG"
  out="$(STEROIDS_CONFIG="$CONFIG" /bin/zsh "$TMPDIR_TESTS/grid.sh" /tmp 2>/dev/null)"
  got="$(print -r -- "$out" | grep -o 'repeat with idx from 0 to [0-9-]*' | grep -o '[0-9-]*$')"
  assert_eq "${cols}x${rows} builds $((cols * rows)) panes" "$last" "$got"
  got_div="$(print -r -- "$out" | grep -c "idx mod $cols")"
  assert_eq "${cols}x${rows} columns reach the AppleScript" "1" "$got_div"
done

print -r -- '{"agent":"claude","columns":3,"rows":3,"yolo":true}' > "$CONFIG"
out="$(STEROIDS_CONFIG="$CONFIG" /bin/zsh "$TMPDIR_TESTS/grid.sh" /tmp --agent codex 2>/dev/null)"
case "$out" in
  *codex*) ok 'the grid honours --agent codex' ;;
  *)       bad 'the grid honours --agent codex' "no codex in the generated AppleScript" ;;
esac

# ===========================================================================
section 'Quick Actions'
# ===========================================================================
# Six Finder entries: a neutral pair that follows Settings, and a pinned pair
# per agent. The switch macOS keeps for each one is keyed by its MENU ITEM name,
# which for the grids is not its bundle filename — so the installer reads that
# name out of the bundle, and so does this test.
typeset -A expect=(
  'Open Coding Agent Here'    'claude-session.sh|'
  'Steroids Mode'             'steroids-grid.sh|'
  'Open in Claude'            'claude-session.sh|--agent claude'
  'Open in Claude Steroids'   'steroids-grid.sh|--agent claude'
  'Open in Codex'             'claude-session.sh|--agent codex'
  'Open in Codex Steroids'    'steroids-grid.sh|--agent codex'
)

for bundle in "${(@k)expect}"; do
  wf="$QUICK_ACTIONS/$bundle.workflow"
  if [[ ! -d "$wf" ]]; then bad "$bundle exists" "missing $wf"; continue; fi

  name="$(/usr/libexec/PlistBuddy -c 'Print :NSServices:0:NSMenuItem:default' \
          "$wf/Contents/Info.plist" 2>/dev/null)"
  assert_true "$bundle advertises a menu name" $([[ -n "$name" ]] && print 0 || print 1) \
    "no NSMenuItem default in Info.plist"

  cmd="$(python3 -c "
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
out = []
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == 'COMMAND_STRING' and isinstance(v, str) and v.strip(): out.append(v)
            else: walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(d)
print(out[0] if out else '')" "$wf/Contents/document.wflow")"

  want_script="${expect[$bundle]%%|*}"
  want_pin="${expect[$bundle]##*|}"

  case "$cmd" in
    *"$want_script"*) ok "$bundle calls $want_script" ;;
    *)                bad "$bundle calls $want_script" "command was: ${cmd//$'\n'/ ; }" ;;
  esac

  if [[ -n "$want_pin" ]]; then
    case "$cmd" in
      *"$want_pin"*) ok "$bundle pins: $want_pin" ;;
      *)             bad "$bundle pins: $want_pin" "command was: ${cmd//$'\n'/ ; }" ;;
    esac
  else
    case "$cmd" in
      *--agent*) bad "$bundle pins nothing" "it should follow Settings, but pins an agent" ;;
      *)         ok "$bundle pins nothing" ;;
    esac
  fi
done

# The installer must ship every bundle in the folder, and register every one it
# ships — a Quick Action with no switch can be installed, valid, and invisible.
for check in 'quick-actions/' 'NSServicesStatus'; do
  if grep -q "$check" "$ROOT/install.sh"; then
    ok "install.sh still handles $check"
  else
    bad "install.sh still handles $check" "no mention of $check"
  fi
done

# ===========================================================================
print -r -- ""
print -r -- "------------------------------------------------------------"
if (( FAIL == 0 )); then
  print -r -- "${GREEN}All $PASS tests passed.${OFF}"
  exit 0
else
  print -r -- "${RED}$PASS passed, $FAIL FAILED${OFF}"
  for f in "${FAILURES[@]}"; do print -r -- "  - $f"; done
  exit 1
fi
