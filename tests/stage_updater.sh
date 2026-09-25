#!/bin/sh
# platform: macOS-only -- plutil lints the staged agent
set -eu
# spec: scripts/run-repo-tests.sh -- exit 77 is the family's SKIP idiom, not a failure. Called
#       bare, as the shared runner does when it globs tests/*.sh, there is no root to test
#       against; ctest itself always supplies the source root (see add_test in CMakeLists.txt).
[ "$#" -ge 1 ] || { echo "no source root given (ctest supplies it) -- skipping" >&2; exit 77; }
ROOT="$1"
T=$(mktemp -d "${TMPDIR:-/tmp}/mav-stageupd.XXXXXX")
trap 'rm -rf "$T"' EXIT

# platform: the install dir contains a SPACE, as the real one does -- this pins that the
#           rendered paths survive it.
APPDIR="/Library/Application Support/Mavergreen"
LABEL=dev.mavergreen.openssh-updatecheck
APP="$T/openssh-updater.app"
mkdir -p "$APP/Contents/MacOS"
printf '#!/bin/sh\n' > "$APP/Contents/MacOS/openssh-updater"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.mavergreen.openssh.updater</string></dict></plist>\n' > "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/openssh-updater"

fail() { echo "stage_updater test: $1" >&2; exit 1; }
no_token() { if grep -q '@MAVERICKS' "$1"; then fail "unsubstituted token in $1"; fi; }

STAGE="$T/stage"; SCR="$T/scripts"
sh "$ROOT/scripts/stage_updater.sh" --stage "$STAGE" --app "$APP" --product openssh --scripts-out "$SCR"

installed_exe="$APPDIR/openssh-updater.app/Contents/MacOS/openssh-updater"
[ -x "$STAGE$installed_exe" ] || fail "app not staged where the registry puts openssh's updater"

PL="$STAGE/Library/LaunchAgents/$LABEL.plist"
[ -f "$PL" ] || fail "no agent plist at the registry's label for openssh"
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
sh "$ROOT/scripts/stage_updater.sh" --stage "$STAGE2" --app "$APP" --product openssh --snippet-out "$SNIP"
[ -f "$SNIP" ] || fail "no snippet"
no_token "$SNIP"
sh -n "$SNIP" || fail "snippet is not valid sh"
[ ! -f "$T/snips/postinstall" ] || fail "wrote a postinstall when only a snippet was asked for"
CONSOLE_USER=mine; PLIST=mine
. "$SNIP"
echo reached-the-end > "$T/sourced"
[ -f "$T/sourced" ] || fail "sourcing the snippet must not exit the caller, but it did"
[ "$CONSOLE_USER" = mine ] && [ "$PLIST" = mine ] || fail "sourcing the snippet must not clobber a caller variable, but it did"

sys="$T/sys"; stubs="$T/stubs"; alog="$T/agent.log"
mkdir -p "$sys/Library/LaunchAgents" "$stubs"; : > "$sys/Library/LaunchAgents/$LABEL.plist"; : > "$alog"
for c in launchctl sudo; do printf '#!/bin/sh\necho %s "$@" >> "%s"\n' "$c" "$alog" > "$stubs/$c"; done
printf '#!/bin/sh\ncase "$*" in *%%Su*) echo tester ;; *) echo 501 ;; esac\n' > "$stubs/stat"
chmod +x "$stubs"/*
sed "s#/Library/LaunchAgents/#$sys/Library/LaunchAgents/#" "$SNIP" > "$T/snip-redirected"
grep -q "$sys" "$T/snip-redirected" || fail "the test must redirect the snippet's running-system plist path, or it proves nothing"
PATH="$stubs:$PATH" sh -c '. "$0"' "$T/snip-redirected"
grep -q '^launchctl bootstrap gui/501 ' "$alog" \
  || fail "sourced by a script with no \$3, the snippet acts as for the boot volume: [$(cat "$alog")]"
: > "$alog"
PATH="$stubs:$PATH" sh -c '. "$0"' "$T/snip-redirected" /x.pkg /Volumes/Other /Volumes/Other
[ ! -s "$alog" ] || fail "sourced with \$3 naming another volume, the snippet must not touch the running system: $(cat "$alog")"

grep -q 'MAV_AGENT_PLIST' "$PI" || fail "postinstall does not carry the shared agent-load logic -- both outputs must render the same logic (the postinstall is the snippet plus a shebang and exit)"

STAGE3="$T/stage3"
sh "$ROOT/scripts/stage_updater.sh" --stage "$STAGE3" --app "$APP" --product openssh
[ -x "$STAGE3$installed_exe" ] || fail "app not staged in payload-only mode"

for f in --app-dir --agent-label; do
  rc=0; sh "$ROOT/scripts/stage_updater.sh" --stage "$T/s5" --app "$APP" --product openssh "$f" x 2>/dev/null || rc=$?
  [ "$rc" -eq 2 ] || fail "$f is derived from the registry, so passing it is a usage error (exit 2); got $rc"
done
mkdir -p "$T/other/OpenSSHUpdater.app"
rc=0; sh "$ROOT/scripts/stage_updater.sh" --stage "$T/s6" --app "$T/other/OpenSSHUpdater.app" --product openssh 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "an updater not named openssh-updater.app would install where its LaunchAgent does not look; got $rc"
[ ! -e "$T/s6" ] || fail "a refused updater stages nothing"
sh "$ROOT/scripts/stage_updater.sh" --stage "$T/s7" --app "$APP" --product no-such-product 2>/dev/null \
  && fail "an unregistered product has no updater identity to stage"

if sh "$ROOT/scripts/stage_updater.sh" --stage "$T/s4" --app "$APP" --product openssh \
     --no-such-flag whatever 2>/dev/null; then
  fail "an unknown argument was accepted -- a caller asking for something this script does not do should fail loudly rather than get a payload quietly missing it"
fi

echo "stage_updater OK"
