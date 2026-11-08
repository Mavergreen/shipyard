#!/bin/sh
# platform: host-agnostic
#   usage: compat-guard-cmake-test.sh
#          mavergreen_assert_binary_compatible() hands the guard MAVERGREEN_DEVIATIONS_ROOT = the
#          project's CMAKE_SOURCE_DIR. A POST_BUILD command runs in the build tree, so without it the
#          guard would look there for .mavergreen/deviations/ and honour no sdk-pin exemption at all.
#          With OBJC_STRICT it also sets MAVERGREEN_OBJC_STRICT=1 and forwards the analyzer's reference
#          set and evidence knobs only when set, and a retired
#          selector knob stops the configure. Without it the guard is called as before, and an
#          analyzer knob stops the configure rather than be ignored. An install stages
#          the Drydock pin the guard's analyzer is fetched by and that release's reference set.
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
include("$root/MavergreenCompatGuard.cmake")
$1
mavergreen_assert_binary_compatible(foo ${2:-})
EOF
  rc=0; out="$(cd "$src" && cmake -P probe.cmake 2>&1)" || rc=$?
}
unset MAVERGREEN_ALLOW_SELECTORS MAVERGREEN_POST_10_9_SELECTORS
probe ''
[ "$rc" = 0 ] || { echo "FAIL: the probe did not run:"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q ";MAVERGREEN_DEVIATIONS_ROOT=$src;" \
  || { echo "FAIL: the guard is not given MAVERGREEN_DEVIATIONS_ROOT=$src (CMAKE_SOURCE_DIR):"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q ";-E;env;.*;sh;.*/assert_binary_compatible.sh;" \
  || { echo "FAIL: the variable must reach the guard's own environment:"; echo "$out"; exit 1; }
# spec: MavergreenCompatGuard.cmake header -- without OBJC_STRICT the guard runs as before: no analyzer knob reaches it,
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
# spec: MavergreenCompatGuard.cmake header -- with OBJC_STRICT and no reference set named, none is forwarded: the guard
#       defaults to the pinned Drydock's (scripts/objc-reference-dir.sh).
! printf '%s\n' "$out" | grep -q 'MAVERGREEN_OBJC_REFERENCES' \
  || { echo "FAIL: a reference set was forwarded when none was set:"; echo "$out"; exit 1; }
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
# spec: MavergreenCompatGuard.cmake header -- with OBJC_STRICT, a retired selector knob, in CMake or the environment, stops
#       the configure.
probe 'set(MAVERGREEN_ALLOW_SELECTORS labelColor)' OBJC_STRICT
[ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q 'MAVERGREEN_ALLOW_SELECTORS is retired' \
  || { echo "FAIL: MAVERGREEN_ALLOW_SELECTORS did not stop the configure:"; echo "$out"; exit 1; }
MAVERGREEN_POST_10_9_SELECTORS=labelColor; export MAVERGREEN_POST_10_9_SELECTORS
probe '' OBJC_STRICT
unset MAVERGREEN_POST_10_9_SELECTORS
[ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q 'MAVERGREEN_POST_10_9_SELECTORS is retired' \
  || { echo "FAIL: MAVERGREEN_POST_10_9_SELECTORS in the environment did not stop the configure:"; echo "$out"; exit 1; }

# spec: scripts/objc-reference-dir.sh header -- CMakeLists.txt installs the Drydock pin beside the wrappers that fetch it, and
#       stages the pinned Drydock's reference set, byte for byte, as reference/objc, where objc-reference-dir.sh looks first.
b="$w/build"; p="$w/prefix"
cmake -S "$root" -B "$b" >"$w/configure.log" 2>&1 || { echo "FAIL: shipyard did not configure:"; tail -20 "$w/configure.log"; exit 1; }
# spec: scripts/fetch_drydock.sh header -- an unverified Drydock in the environment is never what the install stages.
mkdir -p "$w/fake-drydock/bin" "$w/fake-drydock/share/drydock/objc/reference"
printf '#!/bin/sh\n' >"$w/fake-drydock/bin/drydock-objc"; chmod +x "$w/fake-drydock/bin/drydock-objc"
echo fake >"$w/fake-drydock/share/drydock/objc/reference/fake.tsv"
MAVERGREEN_DRYDOCK_PREFIX="$w/fake-drydock" cmake --install "$b" --prefix "$p" >"$w/install.log" 2>&1 || { echo "FAIL: shipyard did not install:"; tail -20 "$w/install.log"; exit 1; }
d="$p/share/cmake/MavergreenShipyard"
for f in components/drydock/version components/drydock/linux-sha256 components/objc-receipt-clang/version \
  components/objc-receipt-clang/linux-sha256 scripts/objc-compat.sh scripts/objc-build-evidence.sh scripts/objc-provider-link-args.sh \
  scripts/objc-source-inventory.sh scripts/objc-reference-dir.sh scripts/fetch_drydock.sh scripts/fetch_product_pkg.sh; do
  cmp -s "$root/$f" "$d/$f" || { echo "FAIL: the install does not stage $f"; exit 1; }
done
refs="$(env -u MAVERGREEN_DRYDOCK_PREFIX MAVERGREEN_DRYDOCK_INSTALLED=/nonexistent sh "$root/scripts/fetch_drydock.sh" "$root/components/drydock")/share/drydock/objc/reference" \
  || { echo "FAIL: the pinned Drydock could not be fetched to compare with"; exit 1; }
diff -r "$refs" "$d/reference/objc" >"$w/refs.diff" 2>&1 \
  || { echo "FAIL: the staged reference/objc is not the pinned Drydock's:"; cat "$w/refs.diff"; exit 1; }
[ -f "$d/reference/objc/manifest.json" ] || { echo "FAIL: the staged reference/objc holds no manifest.json"; exit 1; }
[ "$(sh "$d/scripts/objc-reference-dir.sh")" = "$(cd "$d/reference/objc" && pwd -P)" ] \
  || { echo "FAIL: the installed objc-reference-dir.sh does not answer with the staged set"; exit 1; }
for gone in tools/objc-compat components/objc-reader-drydock components/objc-reference-clang scripts/objc-compat-build.sh; do
  [ ! -e "$d/$gone" ] || { echo "FAIL: the install still stages $gone"; exit 1; }
done
echo "PASS: compat-guard-cmake"
