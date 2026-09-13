#!/bin/sh
set -eu
# spec: scripts/run-repo-tests.sh -- exit 77 is the family's SKIP idiom, not a failure. Called
#       bare, as the shared runner does when it globs tests/*.sh, there is no root to test
#       against; ctest itself always supplies the source root (see add_test in CMakeLists.txt).
[ "$#" -ge 1 ] || { echo "no source root given (ctest supplies it) -- skipping" >&2; exit 77; }
ROOT="$1"
T=$(mktemp -d "${TMPDIR:-/tmp}/mav-stageupd.XXXXXX")
trap 'rm -rf "$T"' EXIT

# spec: the install dir contains a SPACE, as the real one does -- this pins that the rendered
#       paths survive it.
APPDIR="/Library/Application Support/ModernMavericks"
LABEL=dev.modernmavericks.test-updatecheck
APP="$T/TestUpdater.app"
mkdir -p "$APP/Contents/MacOS"
printf '#!/bin/sh\n' > "$APP/Contents/MacOS/TestUpdater"
chmod +x "$APP/Contents/MacOS/TestUpdater"

fail() { echo "stage_updater test: $1" >&2; exit 1; }
no_token() { if grep -q '@MAVERICKS' "$1"; then fail "unsubstituted token in $1"; fi; }

STAGE="$T/stage"; SCR="$T/scripts"
sh "$ROOT/scripts/stage_updater.sh" --stage "$STAGE" --app "$APP" \
  --app-dir "$APPDIR" --agent-label "$LABEL" --scripts-out "$SCR"

installed_exe="$APPDIR/TestUpdater.app/Contents/MacOS/TestUpdater"
[ -x "$STAGE$installed_exe" ] || fail "app not staged"

PL="$STAGE/Library/LaunchAgents/$LABEL.plist"
[ -f "$PL" ] || fail "no agent plist"
grep -q "<string>$LABEL</string>" "$PL" || fail "agent label not set"
grep -q "<string>$installed_exe</string>" "$PL" \
  || fail "agent exec path not set to the INSTALLED path (the staged file lives under \$STAGE, but the plist must reference the path with no \$STAGE prefix)"
plutil -lint "$PL" >/dev/null || fail "agent plist is not valid"
no_token "$PL"

PI="$SCR/postinstall"
[ -x "$PI" ] || fail "no postinstall"
grep -q "$LABEL.plist" "$PI" || fail "postinstall label wrong"
sh -n "$PI" || fail "rendered postinstall is not valid sh"
no_token "$PI"

[ ! -d "$STAGE/usr/local/bin" ] || fail "staged something into /usr/local/bin -- the daily agent is the only check, with no manual-trigger shim"

STAGE2="$T/stage2"; SNIP="$T/snips/agent-load.sh"
sh "$ROOT/scripts/stage_updater.sh" --stage "$STAGE2" --app "$APP" \
  --app-dir "$APPDIR" --agent-label "$LABEL" --snippet-out "$SNIP"
[ -f "$SNIP" ] || fail "no snippet"
no_token "$SNIP"
sh -n "$SNIP" || fail "snippet is not valid sh"
[ ! -f "$T/snips/postinstall" ] || fail "wrote a postinstall when only a snippet was asked for"
CONSOLE_USER=mine; PLIST=mine
. "$SNIP"
echo reached-the-end > "$T/sourced"
[ -f "$T/sourced" ] || fail "sourcing the snippet must not exit the caller, but it did"
[ "$CONSOLE_USER" = mine ] && [ "$PLIST" = mine ] || fail "sourcing the snippet must not clobber a caller variable, but it did"

grep -q 'MAV_AGENT_PLIST' "$PI" || fail "postinstall does not carry the shared agent-load logic -- both outputs must render the same logic (the postinstall is the snippet plus a shebang and exit)"

STAGE3="$T/stage3"
sh "$ROOT/scripts/stage_updater.sh" --stage "$STAGE3" --app "$APP" \
  --app-dir "$APPDIR" --agent-label "$LABEL"
[ -x "$STAGE3$installed_exe" ] || fail "app not staged in payload-only mode"

if sh "$ROOT/scripts/stage_updater.sh" --stage "$T/s4" --app "$APP" --app-dir "$APPDIR" \
     --agent-label x --no-such-flag whatever 2>/dev/null; then
  fail "an unknown argument was accepted -- a caller asking for something this script does not do should fail loudly rather than get a payload quietly missing it"
fi

echo "stage_updater OK"
