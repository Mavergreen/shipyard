#!/bin/sh
# platform: macOS-only -- tests a lipo-based assertion, and on Linux shipyard refuses no cmake
#   usage: assert-installed-shipyard-test.sh
#          Drives scripts/assert-installed-shipyard.sh against a FIXTURE root shaped like the pkg's
#          layout, built from this box's own cmake. Three of its four assertions run for real here;
#          the two universal-binary ones cannot (making an x86_64+arm64 Mach-O needs a cross
#          toolchain this suite's 10.9 box has none of), so lipo is stubbed per argument, which
#          proves the script's READING of lipo -info and nothing more. Exit 0 clean, 1 on failure,
#          77 when there is no cmake to build a fixture from.
# spec: R-P1-17 -- scripts/assert-installed-shipyard.sh is the ONE statement release.yml's install
#       smoke and ci.yml's packaging rehearsal share, and a shared assertion nothing exercises is
#       worse than an inline one: both callers would go green on a script that stopped asserting.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
. "$here/lib/cmake_fixture.sh"
S="$root/scripts/assert-installed-shipyard.sh"

real="$(command -v cmake 2>/dev/null)" || { echo "SKIP: no cmake to build a fixture prefix from"; exit 77; }
# platform: macOS sets TMPDIR with a trailing slash. The fixture root is passed as --root and
#           greped for verbatim in cmake's own STATUS output, and cmake normalizes "//" away when it
#           prints MavericksShipyard_DIR -- so an unstripped slash fails on every real macOS session
#           while looking fine here with TMPDIR unset.
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/assert-installed.XXXXXX")"; trap 'rm -rf "$w"' EXIT

ver="$("$real" --version 2>&1 | sed -n 's/^cmake version //p' | head -1)"
[ -n "$ver" ] || { echo "SKIP: cannot read this cmake's version"; exit 77; }

fails=0
check() {  # $1 = what  $2 = expected exit (0 or 1)  $3 = substring the output must contain ("" = any)
  _what="$1"; _want="$2"; _sub="$3"; shift 3
  _rc=0; _out="$("$@" 2>&1)" || _rc=$?
  if [ "$_rc" -ne "$_want" ]; then
    echo "FAIL: $_what -- expected exit $_want, got $_rc:"; printf '%s\n' "$_out" | sed 's/^/    | /'
    fails=$((fails + 1)); return 0
  fi
  # platform: the expected substrings include ones starting with "--", which grep reads as its own
  #           option and dies on ("unrecognized option") unless they come after -e -- a green-looking
  #           crash rather than a comparison.
  if [ -n "$_sub" ] && ! printf '%s\n' "$_out" | grep -q -e "$_sub"; then
    echo "FAIL: $_what -- output does not mention '$_sub':"; printf '%s\n' "$_out" | sed 's/^/    | /'
    fails=$((fails + 1)); return 0
  fi
  echo "ok: $_what"
}

# platform: a cmake finds CMAKE_ROOT relative to its REAL path, so the binary and its CMAKE_ROOT
#           must be COPIED, never symlinked: a symlink would report the host's prefix and leave the
#           whole point -- shipyard-cmake finding shipyard in its OWN prefix -- untested.
croot="$(printf 'message("${CMAKE_ROOT}")\n' > "$w/r.cmake"; "$real" -P "$w/r.cmake" 2>&1)"
fx="$w/root"
prefix="$fx/usr/local/mavergreen-shipyard"
mkdir -p "$prefix/bin" "$prefix/share" "$fx/usr/local/bin"
cp "$real" "$prefix/bin/cmake"
# spec: tests/lib/cmake_fixture.sh -- the two ways a copied CMAKE_ROOT goes wrong (Homebrew's is a
#       symlink AND read-only, and cp -R preserves both) are written out there and proven by
#       tests/cmake-fixture-test.sh.
copy_cmake_root "$croot" "$prefix/share/$(basename "$croot")"
ln -s ../mavergreen-shipyard/bin/cmake "$fx/usr/local/bin/shipyard-cmake"
for c in ctest cpack; do
  if [ -x "$(dirname "$real")/$c" ]; then
    cp "$(dirname "$real")/$c" "$prefix/bin/$c"
  else
    printf '#!/bin/sh\nexit 0\n' > "$prefix/bin/$c"; chmod +x "$prefix/bin/$c"
  fi
  ln -s "../mavergreen-shipyard/bin/$c" "$fx/usr/local/bin/shipyard-$c"
done
# platform: keep this output. Sent to /dev/null, a failure here killed the script under set -e
#           having said NOTHING, and a real macos-26 run could only report "exit 1" -- hiding the
#           read-only-CMAKE_ROOT cause for a whole round.
"$real" -S "$root" -B "$w/sb" > "$w/configure.log" 2>&1 \
  || { echo "FAIL: could not configure shipyard for the fixture:"; sed 's/^/    | /' "$w/configure.log"; exit 1; }
HOME="$w/home-install" "$real" --install "$w/sb" --prefix "$prefix" > "$w/install.log" 2>&1 \
  || { echo "FAIL: could not install shipyard into the fixture prefix:"; sed 's/^/    | /' "$w/install.log"; exit 1; }

updir="$fx/Library/Application Support/Mavergreen/MavericksShipyardUpdater.app/Contents/MacOS"
mkdir -p "$updir"
printf 'not a real Mach-O; lipo is stubbed below\n' > "$updir/MavericksShipyardUpdater"

# platform: a scratch HOME for every run -- this box may carry a stale ~/.cmake user-registry entry
#           from an older shipyard, and an ambient entry would outrank the fixture in find_package.
run_home="$w/home-run"; mkdir -p "$run_home"

stub="$w/stub"; mkdir -p "$stub"
lipo_says() {  # $1 = the -info line for shipyard-cmake  $2 = the -info line for the updater
  cat > "$stub/lipo" <<EOF
#!/bin/sh
case "\$2" in
  *MavericksShipyardUpdater) printf '%s\n' "$2" ;;
  *) printf '%s\n' "$1" ;;
esac
EOF
  chmod +x "$stub/lipo"
}
UNIVERSAL_CMAKE="shipyard-cmake: architecture x86_64 arm64"
UNIVERSAL_APP="MavericksShipyardUpdater: architecture x86_64 arm64"
assert() {  # remaining args are appended to the script's own
  HOME="$run_home" PATH="$stub:$PATH" sh "$S" --root "$fx" "$@"
}

lipo_says "$UNIVERSAL_CMAKE" "$UNIVERSAL_APP"
check "a correctly installed shipyard passes" 0 "finds shipyard in" \
  assert --cmake-version "$ver"

check "a shipyard-cmake that is not the pinned CMake fails" 1 "is not CMake" \
  assert --cmake-version 0.0.0-not-this-one

lipo_says "shipyard-cmake: is architecture: arm64" "$UNIVERSAL_APP"
check "a shipyard-cmake with no x86_64 slice fails (it could not run on 10.9)" 1 "shipyard-cmake has no x86_64 slice" \
  assert --cmake-version "$ver"
lipo_says "shipyard-cmake: is architecture: x86_64" "$UNIVERSAL_APP"
check "a shipyard-cmake with no arm64 slice fails (it could not run on Apple Silicon)" 1 "shipyard-cmake has no arm64 slice" \
  assert --cmake-version "$ver"
lipo_says "$UNIVERSAL_CMAKE" "$UNIVERSAL_APP"

for c in shipyard-ctest shipyard-cpack; do
  mv "$fx/usr/local/bin/$c" "$w/cmd-aside"
  check "a missing $c fails (both workflows and every consumer run it by name)" 1 "no executable .*$c" \
    assert --cmake-version "$ver"
  mv "$w/cmd-aside" "$fx/usr/local/bin/$c"
done

lipo_says "$UNIVERSAL_CMAKE" "MavericksShipyardUpdater: is architecture: arm64"
check "an updater with no x86_64 slice fails" 1 "no x86_64 slice" \
  assert --cmake-version "$ver"
lipo_says "$UNIVERSAL_CMAKE" "MavericksShipyardUpdater: is architecture: x86_64"
check "an updater with no arm64 slice fails" 1 "no arm64 slice" \
  assert --cmake-version "$ver"
lipo_says "$UNIVERSAL_CMAKE" "$UNIVERSAL_APP"

mv "$updir/MavericksShipyardUpdater" "$w/updater-aside"
check "a missing updater fails" 1 "no installed updater executable" \
  assert --cmake-version "$ver"
mv "$w/updater-aside" "$updir/MavericksShipyardUpdater"

mv "$prefix/share/cmake/MavericksShipyard" "$w/shipyard-aside"
check "a prefix whose shipyard is missing fails the stripped-environment probe" 1 "under a stripped environment" \
  assert --cmake-version "$ver"
mv "$w/shipyard-aside" "$prefix/share/cmake/MavericksShipyard"

mv "$fx/usr/local/bin/shipyard-cmake" "$w/link-aside"
check "a missing /usr/local/bin/shipyard-cmake fails" 1 "no executable shipyard-cmake" \
  assert --cmake-version "$ver"
mv "$w/link-aside" "$fx/usr/local/bin/shipyard-cmake"

cat > "$stub/cmake" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$stub/cmake"
check "a foreign cmake that configures against shipyard fails" 1 "must be refused" \
  assert --cmake-version "$ver"
cat > "$stub/cmake" <<'STUB'
#!/bin/sh
echo "some unrelated configure error" >&2
exit 1
STUB
chmod +x "$stub/cmake"
check "a refusal that never names shipyard-cmake fails" 1 "does not name shipyard-cmake" \
  assert --cmake-version "$ver"
rm -f "$stub/cmake"

check "--cmake-version is required" 2 "--cmake-version required" \
  assert
check "an unknown option is refused rather than ignored" 2 "unknown option" \
  assert --cmake-version "$ver" --install-it-for-me
check "a root that does not exist is refused" 2 "no such root" \
  env HOME="$run_home" PATH="$stub:$PATH" sh "$S" --root "$w/no-such-root" --cmake-version "$ver"

[ "$fails" -eq 0 ] || { echo "FAIL: $fails case(s) in assert-installed-shipyard"; exit 1; }
echo "PASS: assert-installed-shipyard"
