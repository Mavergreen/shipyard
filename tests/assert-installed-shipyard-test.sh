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
# platform: the launcher resolves its prefix physically, and macOS's TMPDIR is under /var, a link to
#           /private/var, so the root is the physical one.
w="$(cd -P "$w" && pwd)"

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

fx="$w/root"
prefix="$fx/usr/local/mavergreen/shipyard"
farm="$fx/usr/local/mavergreen/bin"
mkdir -p "$farm"
# spec: tests/lib/cmake_fixture.sh -- the fixture is a pair <root>/{shipyard,cmake}, as installed.
copy_cmake_product "$real" "$fx/usr/local/mavergreen/cmake"
for c in cmake ctest cpack; do
  ln -s "../shipyard/bin/shipyard-$c" "$farm/shipyard-$c"
done
ln -s ../shipyard/bin/shipyard-check "$farm/shipyard-check"
# platform: keep this output. Sent to /dev/null, a failure here killed the script under set -e
#           having said NOTHING, and a real macos-26 run could only report "exit 1" -- hiding the
#           read-only-CMAKE_ROOT cause for a whole round.
"$real" -S "$root" -B "$w/sb" -DSHIPYARD_CMAKE_MIN="$ver" > "$w/configure.log" 2>&1 \
  || { echo "FAIL: could not configure shipyard for the fixture:"; sed 's/^/    | /' "$w/configure.log"; exit 1; }
HOME="$w/home-install" "$real" --install "$w/sb" --prefix "$prefix" > "$w/install.log" 2>&1 \
  || { echo "FAIL: could not install shipyard into the fixture prefix:"; sed 's/^/    | /' "$w/install.log"; exit 1; }

updir="$fx/Library/Application Support/Mavergreen/shipyard-updater.app/Contents/MacOS"
mkdir -p "$updir"
printf 'not a real Mach-O; lipo is stubbed below\n' > "$updir/shipyard-updater"

# platform: a scratch HOME for every run -- this box may carry a stale ~/.cmake user-registry entry
#           from an older shipyard, and an ambient entry would outrank the fixture in find_package.
run_home="$w/home-run"; mkdir -p "$run_home"

stub="$w/stub"; mkdir -p "$stub"
# spec: 2026-10-09 C4 -- the farm's shipyard-cmake is a launcher script with no slices, so only the
#       cmake product's own binary can answer lipo; any other path gets lipo's own refusal.
lipo_says() {  # $1 = the -info line for the cmake product  $2 = the -info line for the updater
  cat > "$stub/lipo" <<EOF
#!/bin/sh
case "\$2" in
  *shipyard-updater) printf '%s\n' "$2" ;;
  */usr/local/mavergreen/cmake/bin/cmake) printf '%s\n' "$1" ;;
  *) echo "fatal error: lipo: can't figure out the architecture type of: \$2" >&2; exit 1 ;;
esac
EOF
  chmod +x "$stub/lipo"
}
UNIVERSAL_CMAKE="cmake: architecture x86_64 arm64"
UNIVERSAL_APP="shipyard-updater: architecture x86_64 arm64"
assert() {  # remaining args are appended to the script's own
  HOME="$run_home" PATH="$stub:$PATH" sh "$S" --root "$fx" "$@"
}

lipo_says "$UNIVERSAL_CMAKE" "$UNIVERSAL_APP"
check "a correctly installed shipyard passes" 0 "finds shipyard in" \
  assert --cmake-version "$ver"

check "a cmake product that is not the pinned CMake fails" 1 "is not CMake" \
  assert --cmake-version 0.0.0-not-this-one

product="$fx/usr/local/mavergreen/cmake"
mv "$farm/shipyard-cmake" "$w/link-aside"
printf '#!/bin/sh\necho "cmake version 9.9.9"\n' > "$farm/shipyard-cmake"; chmod +x "$farm/shipyard-cmake"
check "the version is the cmake product's own, not whatever shipyard-cmake prints" 1 "is not CMake 9.9.9" \
  assert --cmake-version 9.9.9
rm "$farm/shipyard-cmake"; mv "$w/link-aside" "$farm/shipyard-cmake"

mv "$product" "$w/product-aside"
check "a shipyard with no cmake product beside it fails, naming the product" 1 "no executable cmake product" \
  assert --cmake-version "$ver"
mv "$w/product-aside" "$product"

lipo_says "cmake: is architecture: arm64" "$UNIVERSAL_APP"
check "a cmake product with no x86_64 slice fails (it could not run on 10.9)" 1 "cmake product has no x86_64 slice" \
  assert --cmake-version "$ver"
lipo_says "cmake: is architecture: x86_64" "$UNIVERSAL_APP"
check "a cmake product with no arm64 slice fails (it could not run on Apple Silicon)" 1 "cmake product has no arm64 slice" \
  assert --cmake-version "$ver"
lipo_says "$UNIVERSAL_CMAKE" "$UNIVERSAL_APP"

for c in shipyard-ctest shipyard-cpack shipyard-check; do
  mv "$farm/$c" "$w/cmd-aside"
  check "a missing $c fails (both workflows and every consumer run it by name)" 1 "no executable .*$c" \
    assert --cmake-version "$ver"
  mv "$w/cmd-aside" "$farm/$c"
done
chmod -x "$prefix/bin/shipyard-cpack"
check "a farm shipyard-cpack whose launcher is not executable fails" 1 "no executable .*shipyard-cpack" \
  assert --cmake-version "$ver"
chmod +x "$prefix/bin/shipyard-cpack"

lipo_says "$UNIVERSAL_CMAKE" "shipyard-updater: is architecture: arm64"
check "an updater with no x86_64 slice fails" 1 "no x86_64 slice" \
  assert --cmake-version "$ver"
lipo_says "$UNIVERSAL_CMAKE" "shipyard-updater: is architecture: x86_64"
check "an updater with no arm64 slice fails" 1 "no arm64 slice" \
  assert --cmake-version "$ver"
lipo_says "$UNIVERSAL_CMAKE" "$UNIVERSAL_APP"

mv "$updir/shipyard-updater" "$w/updater-aside"
check "a missing updater fails" 1 "no installed updater executable" \
  assert --cmake-version "$ver"
mv "$w/updater-aside" "$updir/shipyard-updater"

mv "$prefix/share/cmake/MavericksShipyard" "$w/shipyard-aside"
check "a prefix whose shipyard is missing fails the stripped-environment probe" 1 "under a stripped environment" \
  assert --cmake-version "$ver"
mv "$w/shipyard-aside" "$prefix/share/cmake/MavericksShipyard"

mv "$farm/shipyard-cmake" "$w/link-aside"
check "a missing /usr/local/mavergreen/bin/shipyard-cmake fails" 1 "no executable shipyard-cmake" \
  assert --cmake-version "$ver"
mv "$w/link-aside" "$farm/shipyard-cmake"

mkdir -p "$fx/usr/local/bin"
ln -s ../mavergreen/shipyard/bin/cmake "$fx/usr/local/bin/shipyard-cmake"
check "a /usr/local/bin/shipyard-cmake beside the new layout fails" 1 "left over from the old layout" \
  assert --cmake-version "$ver"
rm "$fx/usr/local/bin/shipyard-cmake"
ln -s ../mavergreen-shipyard/bin/cmake "$fx/usr/local/bin/shipyard-cmake"
check "a DANGLING /usr/local/bin/shipyard-cmake (its old prefix removed by hand) still fails" 1 "left over from the old layout" \
  assert --cmake-version "$ver"
rm "$fx/usr/local/bin/shipyard-cmake"

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
# spec: 2026-10-09 C5 -- the cmake product is the one cmake the config accepts, so a cmake on PATH
#       that resolves under the root's /usr/local/mavergreen/ is not foreign, whatever it is called.
ln -s "$product/bin/cmake" "$stub/cmake"
check "the cmake product reached as a bare cmake on PATH is not probed as foreign" 0 "finds shipyard in" \
  assert --cmake-version "$ver"
rm -f "$stub/cmake"
ln -s "$prefix/bin/cmake" "$stub/cmake"
check "shipyard's compatibility cmake on PATH is not probed as foreign" 0 "finds shipyard in" \
  assert --cmake-version "$ver"
rm -f "$stub/cmake"

cp "$root/scripts/mavergreen.sh" "$fx/usr/local/bin/mavergreen"; chmod +x "$fx/usr/local/bin/mavergreen"
check "an installed helper whose check fails fails the assertion (farm links into a product with no manifest)" 1 "mavergreen check failed" \
  assert --cmake-version "$ver"
ms="$w/manifest-stage"; mkdir -p "$ms/usr/local/mavergreen/shipyard"
sh "$root/scripts/render-manifest.sh" --stage "$ms" --product shipyard --name "Mavericks Shipyard" --version 0.0.0 \
  --exclude bin/cmake --exclude bin/ctest --exclude bin/cpack
cp "$ms/usr/local/mavergreen/shipyard/mavergreen.plist" "$prefix/mavergreen.plist"
mkdir -p "$fx/usr/local/mavergreen/var/mavergreen/selections"
echo shipyard > "$fx/usr/local/mavergreen/var/mavergreen/selections/shipyard"
mkdir -p "$ms/usr/local/mavergreen/cmake"
sh "$root/scripts/render-manifest.sh" --stage "$ms" --product cmake --name "CMake for Mavericks" --version 4.4.4-mavericks.1 \
  --exclude bin/cmake --exclude bin/ctest --exclude bin/cpack
cp "$ms/usr/local/mavergreen/cmake/mavergreen.plist" "$product/mavergreen.plist"
echo cmake > "$fx/usr/local/mavergreen/var/mavergreen/selections/cmake"
check "with the helper and the cmake product installed and shipyard linked, a correct install passes mavergreen check too" 0 "finds shipyard in" \
  assert --cmake-version "$ver"

check "--cmake-version is required" 2 "--cmake-version required" \
  assert
check "an unknown option is refused rather than ignored" 2 "unknown option" \
  assert --cmake-version "$ver" --install-it-for-me
check "a root that does not exist is refused" 2 "no such root" \
  env HOME="$run_home" PATH="$stub:$PATH" sh "$S" --root "$w/no-such-root" --cmake-version "$ver"

[ "$fails" -eq 0 ] || { echo "FAIL: $fails case(s) in assert-installed-shipyard"; exit 1; }
echo "PASS: assert-installed-shipyard"
