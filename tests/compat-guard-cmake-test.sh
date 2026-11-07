#!/bin/sh
# platform: host-agnostic
#   usage: compat-guard-cmake-test.sh
#          mavericks_assert_binary_compatible() hands the guard MAVERICKS_DEVIATIONS_ROOT = the
#          project's CMAKE_SOURCE_DIR. A POST_BUILD command runs in the build tree, so without it the
#          guard would look there for INGREDIENTS.md and honour no sdk-pin:<glob> exemption at all.
#          With OBJC_STRICT it also sets MAVERGREEN_OBJC_STRICT=1, names the staged Objective-C
#          reference set and forwards the analyzer's evidence knobs only when set, and a retired
#          selector knob stops the configure. Without it the guard is called as before, and an
#          analyzer knob stops the configure rather than be ignored. An install stages
#          what the guard's analyzer is built from and reads, byte for byte.
# platform: script mode (cmake -P) sets CMAKE_SOURCE_DIR to the working directory and cannot run
#           add_custom_command, so the probe stands its own in to record what the module asks for --
#           no compiler, no project, and it runs wherever cmake does.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
command -v cmake >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
w="$(mktemp -d "${TMPDIR:-/tmp}/guard-cmake-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
src="$(cd "$w" && pwd -P)"
probe() {  # $1 extra cmake lines before the call, $2 the call's options; sets out and rc
  cat > "$src/probe.cmake" <<EOF
function(add_custom_command)
  message("ARGS: \${ARGN}")
endfunction()
include("$root/MavericksCompatGuard.cmake")
$1
mavericks_assert_binary_compatible(foo ${2:-})
EOF
  rc=0; out="$(cd "$src" && cmake -P probe.cmake 2>&1)" || rc=$?
}
unset MAVERICKS_ALLOW_SELECTORS MAVERICKS_POST_10_9_SELECTORS
probe ''
[ "$rc" = 0 ] || { echo "FAIL: the probe did not run:"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q ";MAVERICKS_DEVIATIONS_ROOT=$src;" \
  || { echo "FAIL: the guard is not given MAVERICKS_DEVIATIONS_ROOT=$src (CMAKE_SOURCE_DIR):"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q ";-E;env;.*;sh;.*/assert_binary_compatible.sh;" \
  || { echo "FAIL: the variable must reach the guard's own environment:"; echo "$out"; exit 1; }
# spec: MavericksCompatGuard.cmake header -- without OBJC_STRICT the guard runs as before: no analyzer knob reaches it,
#       and one set in CMake stops the configure rather than be ignored.
! printf '%s\n' "$out" | grep -q 'MAVERGREEN_OBJC_' \
  || { echo "FAIL: an analyzer knob reached the guard without OBJC_STRICT:"; echo "$out"; exit 1; }
probe 'set(MAVERGREEN_OBJC_BUILD_EVIDENCE /e.json)'
[ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q 'needs OBJC_STRICT' \
  || { echo "FAIL: build evidence without OBJC_STRICT did not stop the configure:"; echo "$out"; exit 1; }
probe '' OBJC_STRICT
[ "$rc" = 0 ] || { echo "FAIL: the OBJC_STRICT probe did not run:"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q ";MAVERGREEN_OBJC_STRICT=1;" \
  || { echo "FAIL: OBJC_STRICT does not set MAVERGREEN_OBJC_STRICT=1:"; echo "$out"; exit 1; }
# spec: MavericksCompatGuard.cmake header -- with OBJC_STRICT, the reference set staged beside the scripts, by default.
printf '%s\n' "$out" | grep -q ";MAVERGREEN_OBJC_REFERENCES=$root/reference/objc;" \
  || { echo "FAIL: the guard is not given this shipyard's reference set:"; echo "$out"; exit 1; }
! printf '%s\n' "$out" | grep -q 'MAVERGREEN_OBJC_BUILD_EVIDENCE' \
  || { echo "FAIL: build evidence forwarded when none was set:"; echo "$out"; exit 1; }
probe 'set(MAVERGREEN_OBJC_BUILD_EVIDENCE "/e v/ev.json")
set(MAVERGREEN_OBJC_ROOT "/r o")
set(MAVERGREEN_OBJC_PROVIDER_PREFIX /p)
set(MAVERGREEN_OBJC_SOURCE_RECEIPT /p/r.receipt)
set(MAVERGREEN_OBJC_REFERENCES /refs)' OBJC_STRICT
for kv in "MAVERGREEN_OBJC_BUILD_EVIDENCE=/e v/ev.json" "MAVERGREEN_OBJC_ROOT=/r o" MAVERGREEN_OBJC_PROVIDER_PREFIX=/p \
  MAVERGREEN_OBJC_SOURCE_RECEIPT=/p/r.receipt MAVERGREEN_OBJC_REFERENCES=/refs; do
  printf '%s\n' "$out" | grep -qF ";$kv;" || { echo "FAIL: $kv is not forwarded:"; echo "$out"; exit 1; }
done
# spec: MavericksCompatGuard.cmake header -- with OBJC_STRICT, a retired selector knob, in CMake or the environment, stops
#       the configure.
probe 'set(MAVERICKS_ALLOW_SELECTORS labelColor)' OBJC_STRICT
[ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q 'MAVERICKS_ALLOW_SELECTORS is retired' \
  || { echo "FAIL: MAVERICKS_ALLOW_SELECTORS did not stop the configure:"; echo "$out"; exit 1; }
MAVERICKS_POST_10_9_SELECTORS=labelColor; export MAVERICKS_POST_10_9_SELECTORS
probe '' OBJC_STRICT
unset MAVERICKS_POST_10_9_SELECTORS
[ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q 'MAVERICKS_POST_10_9_SELECTORS is retired' \
  || { echo "FAIL: MAVERICKS_POST_10_9_SELECTORS in the environment did not stop the configure:"; echo "$out"; exit 1; }

# spec: scripts/objc-compat-build.sh header -- CMakeLists.txt installs the analyzer sources, the Drydock and toolchain pins
#       and the reference set where that script and MavericksCompatGuard.cmake look for them.
b="$w/build"; p="$w/prefix"
cmake -S "$root" -B "$b" >"$w/configure.log" 2>&1 || { echo "FAIL: shipyard did not configure:"; tail -20 "$w/configure.log"; exit 1; }
cmake --install "$b" --prefix "$p" >"$w/install.log" 2>&1 || { echo "FAIL: shipyard did not install:"; tail -20 "$w/install.log"; exit 1; }
d="$p/share/cmake/MavericksShipyard"
for f in reference/objc/manifest.json reference/objc/floor-runtime.tsv tools/objc-compat/main.m tools/objc-compat/report.h \
  tools/objc-source-inventory.c components/objc-reader-drydock/version components/objc-reference-clang/version \
  scripts/objc-compat.sh scripts/objc-compat-build.sh scripts/fetch_pinned_source.sh scripts/fetch_product_pkg.sh; do
  cmp -s "$root/$f" "$d/$f" || { echo "FAIL: the install does not stage $f"; exit 1; }
done
(cd "$root" && ls tools/objc-compat reference/objc) >"$w/want"
(cd "$d" && ls tools/objc-compat reference/objc) >"$w/got"
cmp -s "$w/want" "$w/got" || { echo "FAIL: the staged analyzer sources or reference set differ:"; diff "$w/want" "$w/got"; exit 1; }
echo "PASS: compat-guard-cmake"
