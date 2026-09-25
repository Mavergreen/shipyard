#!/bin/sh
# platform: host-agnostic
# spec: 2026-09-11 decision 1 -- the pkg is ONE prefix holding shipyard's own CMake and shipyard
#       itself, three uniquely named commands in /usr/local/bin, and one universal updater. No
#       registration, no arch picking.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
S="$root/scripts/package-pkg.sh"
[ -f "$S" ] || { echo "FAIL: no scripts/package-pkg.sh"; exit 1; }
w="$(mktemp -d "${TMPDIR:-/tmp}/pkg-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
code() { grep -v '^[[:space:]]*#' "$S"; }   # the script minus its comments
PREFIX=usr/local/mavergreen-shipyard

[ "$(code | grep -c -- '--host-arch x86_64,arm64')" = 1 ] || { echo "FAIL: the Distribution must declare BOTH architectures and exactly those -- without arm64, Installer on Apple Silicon offers Rosetta for a pkg with scripts and runs them translated; only one arch would stop the pkg installing on the other box -- package-pkg.sh must pass --host-arch x86_64,arm64 exactly once"; exit 1; }
for gone in register-with-cmake sysctl agent-load-cross uname CrossUpdater modernmavericks mavericks-shipyard/; do
  code | grep -q -- "$gone" && { echo "FAIL: package-pkg.sh still mentions $gone"; exit 1; }
done
for c in cmake ctest cpack; do
  code | grep -q "shipyard-$c" || { echo "FAIL: package-pkg.sh never creates /usr/local/bin/shipyard-$c"; exit 1; }
  code | grep -q "ln -s ../mavergreen-shipyard/bin/$c" \
    || { echo "FAIL: shipyard-$c must be a RELATIVE symlink (ln -s ../mavergreen-shipyard/bin/$c) -- an absolute /usr/local/mavergreen-shipyard/bin/$c target points at the boot volume no matter which volume Installer is writing to, so an install to any other volume gets three dead links"; exit 1; }
done

sh "$S" --emit-preinstall "$w/preinstall"
[ -s "$w/preinstall" ] || { echo "FAIL: --emit-preinstall wrote nothing"; exit 1; }

lay_down_previous() {  # $1 = volume root: a previous install plus the neighbours it must not touch
  rm -rf "$1"
  mkdir -p "$1/$PREFIX/bin" "$1/usr/local/mavergreen-shipyard-other" "$1/usr/local/other" "$1/usr/local/bin"
  touch "$1/$PREFIX/bin/cmake" "$1/$PREFIX/dropped-in-a-newer-version" \
        "$1/usr/local/mavergreen-shipyard-other/keep" "$1/usr/local/other/keep" "$1/usr/local/bin/keep"
}

# platform: Installer passes "/" for the boot volume, so a trailing slash must not double up into
#           "//usr/local/..." -- and a path without one must work too. Only one of the two was
#           covered before.
for volarg in "$w/vol" "$w/vol/"; do
  lay_down_previous "$w/vol"
  rc=0; out="$(sh "$w/preinstall" /fake.pkg "$volarg" "$volarg" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: preinstall ($volarg) exited $rc: $out"; exit 1; }
  [ ! -e "$w/vol/$PREFIX" ] || { echo "FAIL: preinstall ($volarg) must remove the product dir"; exit 1; }
  [ -f "$w/vol/usr/local/mavergreen-shipyard-other/keep" ] \
    || { echo "FAIL: preinstall ($volarg) removed mavericks-shipyard-other, a prefix SIBLING"; exit 1; }
  [ -f "$w/vol/usr/local/other/keep" ] && [ -f "$w/vol/usr/local/bin/keep" ] \
    || { echo "FAIL: preinstall ($volarg) removed a neighbour under usr/local"; exit 1; }
done

lay_down_previous "$w/vol"
rc=0; out="$(sh "$w/preinstall" /fake.pkg "$w/vol" "$w/vol" 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: preinstall over a previous install must exit 0; got $rc: $out"; exit 1; }
[ -z "$out" ] || { echo "FAIL: preinstall that removed everything it meant to must say nothing; got: $out"; exit 1; }

rm -rf "$w/vol"; mkdir -p "$w/vol/usr/local"
rc=0; out="$(sh "$w/preinstall" /fake.pkg "$w/vol" "$w/vol" 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: a first install (nothing to remove) must exit 0; got $rc: $out"; exit 1; }

# platform: an unwritable PARENT is what makes rm -rf fail; the dir's own mode is not enough.
lay_down_previous "$w/vol"; chmod 555 "$w/vol/usr/local"
rc=0; out="$(sh "$w/preinstall" /fake.pkg "$w/vol" "$w/vol" 2>&1)" || rc=$?
chmod 755 "$w/vol/usr/local"
[ "$rc" -eq 0 ] || { echo "FAIL: a removal it cannot do must not fail the install; preinstall exited $rc: $out"; exit 1; }
if [ "$(id -u)" = 0 ]; then
  echo "note: running as root, where chmod 555 cannot block rm -rf -- the failed-removal case ran but proved nothing"
else
  [ -d "$w/vol/$PREFIX" ] || { echo "FAIL: the unwritable parent did not block the removal, so exit 0 proved nothing"; exit 1; }
  printf '%s\n' "$out" | grep -q 'could not clear' \
    || { echo "FAIL: a removal it could not do must SAY so; got '$out'"; exit 1; }
fi

# platform: with $3 unset a broken guard would reach for an unanchored /usr/local/mavergreen-shipyard
#           -- this machine's (or the runner's) OWN install -- so rm is stubbed for this case rather
#           than run for real.
mkdir -p "$w/stub"
cat > "$w/stub/rm" <<'STUB'
#!/bin/sh
for a in "$@"; do printf '[%s]' "$a"; done >> "$FAKE_RM_LOG"
printf '\n' >> "$FAKE_RM_LOG"
STUB
chmod +x "$w/stub/rm"
FAKE_RM_LOG="$w/rm.log"; export FAKE_RM_LOG
# platform: an empty log is also what a stub that never intercepted anything looks like, so a stub
#           that stopped being found would pass this test while a REAL rm ran. Prove PATH reaches it
#           first, through a fresh `sh` so no inherited command hash can shadow it.
: > "$FAKE_RM_LOG"
( PATH="$w/stub:$PATH"; export PATH; sh -c 'rm -rf "$1"' _ "$w/never-existed" )
grep -q 'never-existed' "$FAKE_RM_LOG" \
  || { echo "FAIL: the rm stub is not the rm a script gets, so the no-target-volume case proves nothing"; exit 1; }
: > "$FAKE_RM_LOG"
mkdir -p "$w/vol/$PREFIX"
( PATH="$w/stub:$PATH"; export PATH; sh "$w/preinstall" ) >/dev/null 2>&1 \
  || { echo "FAIL: preinstall with no \$3 must exit 0"; exit 1; }
[ ! -s "$FAKE_RM_LOG" ] || { echo "FAIL: with no target volume the preinstall must remove nothing; it tried $(cat "$FAKE_RM_LOG")"; exit 1; }
[ -d "$w/vol/$PREFIX" ] || { echo "FAIL: with no target volume the preinstall must remove nothing"; exit 1; }

for missing in --cmake-tree --shipyard-prefix --app --version --out; do
  args="--cmake-tree $w/t --shipyard-prefix $w/p --app $w/MavericksShipyardUpdater.app --version 1.0.0 --out $w/o.pkg"
  args="$(printf '%s' "$args" | sed "s|$missing [^ ]*||")"
  # shellcheck disable=SC2086
  if err="$(sh "$S" $args 2>&1 >/dev/null)"; then echo "FAIL: $missing must be required"; exit 1; fi
  printf '%s\n' "$err" | grep -q -- "$missing" \
    || { echo "FAIL: the refusal for a missing $missing must name it; got '$err'"; exit 1; }
done
mkdir -p "$w/Other.app"
if sh "$S" --cmake-tree "$w/t" --shipyard-prefix "$w/p" --app "$w/Other.app" --version 1.0.0 --out "$w/o.pkg" >/dev/null 2>&1; then
  echo "FAIL: an app not named MavericksShipyardUpdater.app must be refused"; exit 1
fi

# spec: 2026-09-11 decision 1 -- both --cmake-tree and --shipyard-prefix BECOME the product prefix
#       verbatim, so a stray file beside a tree (the tarball it was unpacked from, a .DS_Store, a
#       build dir) would otherwise install into /usr/local/mavergreen-shipyard.
mkfixture() {  # $1 = dir: a tree, a shipyard prefix and an app that all pass every other check
  rm -rf "$1"
  mkdir -p "$1/tree/bin" "$1/tree/doc" "$1/tree/man" "$1/tree/share" \
           "$1/sp/share/cmake/MavericksShipyard" "$1/app/MavericksShipyardUpdater.app"
  for c in cmake ctest cpack; do printf '#!/bin/sh\n' > "$1/tree/bin/$c"; chmod +x "$1/tree/bin/$c"; done
  : > "$1/sp/share/cmake/MavericksShipyard/MavericksShipyardConfig.cmake"
  : > "$1/notadir"
}
# platform: --out under a plain FILE, so a fixture that passes every input check stops at the first
#           mkdir after them -- exercising the checks without pkgbuild, and without a special case
#           for valid input.
run_pkg() {  # $1 = fixture dir; sets $rc and $err
  rc=0
  err="$(sh "$S" --cmake-tree "$1/tree" --shipyard-prefix "$1/sp" \
    --app "$1/app/MavericksShipyardUpdater.app" --version 1.0.0 --out "$1/notadir/o.pkg" 2>&1 >/dev/null)" || rc=$?
}
mkfixture "$w/fa"; run_pkg "$w/fa"
[ "$rc" -ne 0 ] || { echo "FAIL: the fixture was built to stop at --out; it did not fail at all"; exit 1; }
if printf '%s\n' "$err" | grep -q 'unexpected top-level entry'; then
  echo "FAIL: bin/doc/man/share are the payload; none may be refused as unexpected; got '$err'"; exit 1
fi
mkfixture "$w/fb"; : > "$w/fb/tree/shipyard-cmake-tree.tar.gz"; run_pkg "$w/fb"
[ "$rc" -ne 0 ] || { echo "FAIL: a stray file at the --cmake-tree root must be refused"; exit 1; }
printf '%s\n' "$err" | grep -q 'shipyard-cmake-tree.tar.gz' \
  || { echo "FAIL: the refusal must name the stray entry; got '$err'"; exit 1; }
printf '%s\n' "$err" | grep -q -- '--cmake-tree' \
  || { echo "FAIL: the refusal must name the flag that carried it; got '$err'"; exit 1; }
mkfixture "$w/fc"; mkdir -p "$w/fc/sp/build"; run_pkg "$w/fc"
[ "$rc" -ne 0 ] || { echo "FAIL: a stray dir at the --shipyard-prefix root must be refused"; exit 1; }
printf '%s\n' "$err" | grep -q 'build' \
  || { echo "FAIL: the refusal must name the stray entry; got '$err'"; exit 1; }
printf '%s\n' "$err" | grep -q -- '--shipyard-prefix' \
  || { echo "FAIL: the refusal must name the flag that carried it; got '$err'"; exit 1; }

echo "PASS: shipyard-package-pkg"
