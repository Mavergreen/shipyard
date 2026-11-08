#!/bin/sh
# platform: host-agnostic
#   usage: compat-guard-exemptions-test.sh
#          assert_binary_compatible.sh honours a declared sdk-pin:<glob> deviation, read from
#          $MAVERGREEN_DEVIATIONS_ROOT/.mavergreen/deviations/ (default: the current directory), for the
#          minos/sdk rule ONLY. The Mach-O readers are stubbed: a fixture "binary" is the slice
#          lines macho-slices.sh would print, so the guard's own logic runs on any host;
#          tests/compat_guard.bats covers the same cases on real binaries. The Objective-C analyzer
#          is stubbed too (OBJC_COMPAT): it writes a complete strict report and passes or, while
#          bin/objc-blocks exists, names one blocking finding and exits 1. tests/objc-guard-test.sh
#          runs the real one. The cases that say so run opted in to it (MAVERGREEN_OBJC_STRICT=1).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/guard-exempt-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
# spec: scripts/objc-reference-dir.sh header -- laid out as an install, with a staged reference set, so nothing is fetched.
mkdir -p "$w/scripts/lib" "$w/bin" "$w/repo" "$w/build/bin" "$w/reference/objc"
for s in assert_binary_compatible.sh sdk-pins.sh deviations.sh deviation-reason.sh mavergreen-meta.sh check-lib.sh check-ids.tsv lib/macho-tools.sh lib/pkg-tree.sh \
  objc-reference-dir.sh fetch_drydock.sh objc-compat.sh; do
  cp "$here/../scripts/$s" "$w/scripts/$s"
done
cat > "$w/scripts/macho-slices.sh" <<'EOF'
cat "$1"
EOF
cat > "$w/bin/shasum" <<'EOF'
#!/bin/sh
echo "0000000000000000000000000000000000000000000000000000000000000000  $3"
EOF
printf '#!/bin/sh\nexit 0\n' > "$w/bin/nm"
printf '#!/bin/sh\nexit 0\n' > "$w/bin/strings"
# spec: scripts/assert_binary_compatible.sh OBJC_COMPAT knob -- the strict analyzer's contract, a report at --report.
cat > "$w/bin/objc-compat" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do [ "$1" = --report ] && rep=$2; shift 2; done
printf '{"schema": 1, "mode": "strict", "complete_within_boundary": true, "findings": []}\n' > "$rep"
[ -e "$(dirname "$0")/objc-blocks" ] || exit 0
echo 'objc-compat: blocking: x86_64@0x1:+[NSColor labelColor] unsupported: introduced 10.10' >&2
exit 1
EOF
chmod +x "$w/bin/shasum" "$w/bin/nm" "$w/bin/strings" "$w/bin/objc-compat"
PATH="$w/bin:$PATH"; export PATH
NM="$w/bin/nm"; STRINGS="$w/bin/strings"; export NM STRINGS
unset MAVERGREEN_DEVIATIONS_ROOT MAVERGREEN_ALLOW_ARCHS MAVERGREEN_ALLOW_SELECTORS MAVERGREEN_POST_10_9_SELECTORS \
  MAVERGREEN_ALLOW_GUARDED_WEAK MAVERGREEN_OBJC_STRICT OBJC_COMPAT MAVERGREEN_OBJC_ROOT MAVERGREEN_OBJC_BUILD_EVIDENCE \
  MAVERGREEN_OBJC_PROVIDER_PREFIX MAVERGREEN_OBJC_SOURCE_RECEIPT MAVERGREEN_OBJC_REPORT_DIR
strict() {
  MAVERGREEN_OBJC_STRICT=1; OBJC_COMPAT="$w/bin/objc-compat"; export MAVERGREEN_OBJC_STRICT OBJC_COMPAT
  "$@"
  unset MAVERGREEN_OBJC_STRICT OBJC_COMPAT
}
G="$w/scripts/assert_binary_compatible.sh"

echo 'x86_64 EXECUTE 10.9 26.5' > "$w/build/bin/tool"
echo 'x86_64 EXECUTE 10.9 10.9' > "$w/build/bin/good"
echo 'arm64 EXECUTE 11.0 26.5' > "$w/build/bin/armtool"
. "$here/lib/deviation_tree.sh"
deviations_are() {  # groups of four: check label scope reason
  rm -rf "$w/repo/.mavergreen"
  while [ "$#" -ge 4 ]; do deviation "$w/repo" "$1" "$2" "$3" "$4"; shift 4; done
}

run() {  # sets rc and out; $root, when set, is MAVERGREEN_DEVIATIONS_ROOT, and $cwd where the guard runs
  rc=0
  if [ -n "$root" ]; then out="$(cd "${cwd:-$w}" && MAVERGREEN_DEVIATIONS_ROOT="$root" sh "$G" "$@" 2>&1)" || rc=$?
  else out="$(cd "${cwd:-$w}" && sh "$G" "$@" 2>&1)" || rc=$?; fi
}
passes() { run "$@"; [ "$rc" -eq 0 ] || { echo "FAIL ($label): should pass, exit $rc:"; echo "$out"; exit 1; }; }
fails()  { run "$@"; [ "$rc" -ne 0 ] || { echo "FAIL ($label): should fail:"; echo "$out"; exit 1; }; }
says()   { printf '%s\n' "$out" | grep -qF -- "$1" || { echo "FAIL ($label): output lacks '$1':"; echo "$out"; exit 1; }; }

label="no deviations: the rule applies"; root=""; cwd=""
fails "$w/build/bin/tool"; says 'sdk 26.5'
passes "$w/build/bin/good"

label="a matching glob excuses the sdk rule, and says so"; root="$w/repo"
deviations_are sdk-pin tool '*/bin/tool' 'prebuilt upstream, shipped verbatim'
passes "$w/build/bin/tool"
says "compat guard: $w/build/bin/tool is excused from sdk-pin: prebuilt upstream, shipped verbatim"

label="a glob matches the path as given on the command line"
cwd="$w"; passes build/bin/tool
cwd="$w/build/bin"; fails tool; cwd=""

label="MAVERGREEN_DEVIATIONS_ROOT defaults to the current directory"; root=""; cwd="$w/repo"
passes "$w/build/bin/tool"; cwd=""; root="$w/repo"

label="a non-matching glob excuses nothing"
deviations_are sdk-pin other '*/bin/other' 'prebuilt upstream'
fails "$w/build/bin/tool"; says 'sdk 26.5'

label="a deviation for another check excuses nothing"
deviations_are install-path tool '*/bin/tool' 'somewhere odd'
fails "$w/build/bin/tool"

label="an unscoped sdk-pin deviation excuses every file"
deviations_are sdk-pin all '*' 'every binary here is prebuilt'
passes "$w/build/bin/tool"; says 'is excused from sdk-pin: every binary here is prebuilt'

label="a glob with no reason fails the guard closed"
deviations_are sdk-pin tool '*/bin/tool' ''
fails "$w/build/bin/tool"
label="a malformed entry for ANY check fails the guard closed, even for a clean binary"
deviations_are version-scheme x '*' 'a reason'; : > "$w/repo/.mavergreen/deviations/version-scheme/x/revisit"
fails "$w/build/bin/good"

label="an excuse covers only the sdk rule: an arch outside MAVERGREEN_ALLOW_ARCHS still fails"
deviations_are sdk-pin armtool '*/bin/armtool' 'prebuilt upstream'
fails "$w/build/bin/armtool"; says "arches 'arm64' != 'x86_64'"
run_arm() { MAVERGREEN_ALLOW_ARCHS=arm64; export MAVERGREEN_ALLOW_ARCHS; passes "$@"; unset MAVERGREEN_ALLOW_ARCHS; }
label="the same excuse passes once the arch is allowed"; run_arm "$w/build/bin/armtool"

label="an excuse covers only the sdk rule: a post-10.9 import still fails"
deviations_are sdk-pin tool '*/bin/tool' 'prebuilt upstream'
printf '#!/bin/sh\necho "                 (undefined) external _clock_gettime (from libSystem)"\n' > "$w/bin/nm"
fails "$w/build/bin/tool"; says '_clock_gettime'
printf '#!/bin/sh\nexit 0\n' > "$w/bin/nm"

label="an excuse covers only the sdk rule: a post-10.9 selector still fails"
printf '#!/bin/sh\necho labelColor\n' > "$w/bin/strings"
fails "$w/build/bin/tool"; says 'labelColor'
printf '#!/bin/sh\nexit 0\n' > "$w/bin/strings"

label="opted in, an excuse covers only the sdk rule: a blocking Objective-C send still fails"
: > "$w/bin/objc-blocks"
strict fails "$w/build/bin/tool"; says 'labelColor'
label="opted in, a compat-selectors deviation does not excuse a blocking send: only objc-api does"
deviations_are sdk-pin tool '*/bin/tool' 'prebuilt upstream' compat-selectors tool '*/bin/tool' 'guarded'
strict fails "$w/build/bin/tool"; says 'labelColor'
rm "$w/bin/objc-blocks"
label="opted in, a clean analyzer passes and says it measured"
deviations_are sdk-pin tool '*/bin/tool' 'prebuilt upstream'
strict passes "$w/build/bin/tool"; says 'Objective-C sends measured floor-answerable in 1'

label="an excused file does not excuse its neighbour on the same command line"
fails "$w/build/bin/tool" "$w/build/bin/armtool"; says 'armtool'
# spec: scripts/assert_binary_compatible.sh header -- the reference set is resolved where the analyzer runs: misuse is still
#       misuse (2) when no Drydock can be had, and a binary's other findings are still said before the guard fails closed
#       as cannot-measure (1, "CANNOT MEASURE").
rmdir "$w/reference/objc"
MAVERGREEN_DRYDOCK_PREFIX="$w/no-drydock"; export MAVERGREEN_DRYDOCK_PREFIX
label="evidence for two binaries, with no Drydock to be had, is misuse"; deviations_are
MAVERGREEN_OBJC_BUILD_EVIDENCE="$w/ev.json"; export MAVERGREEN_OBJC_BUILD_EVIDENCE
strict run "$w/build/bin/good" "$w/build/bin/tool"; unset MAVERGREEN_OBJC_BUILD_EVIDENCE
[ "$rc" -eq 2 ] || { echo "FAIL ($label): exit $rc, want 2:"; echo "$out"; exit 1; }; says 'one binary'
label="with no Drydock to be had, a binary's sdk finding is still said, and the guard cannot measure"
strict run "$w/build/bin/tool"
[ "$rc" -eq 1 ] || { echo "FAIL ($label): exit $rc, want 1:"; echo "$out"; exit 1; }
says 'sdk 26.5'; says 'no Objective-C reference set'; says 'CANNOT MEASURE'
unset MAVERGREEN_DRYDOCK_PREFIX
mkdir "$w/reference/objc"
# spec: scripts/objc-compat.sh header -- with the real wrapper on a host other than macOS, strict is cannot-measure.
label="strict, with the real analyzer wrapper, on a host other than macOS"
run_linux() { (MAVERGREEN_OBJC_STRICT=1; MAVERGREEN_DRYDOCK_HOST=linux; export MAVERGREEN_OBJC_STRICT MAVERGREEN_DRYDOCK_HOST; unset OBJC_COMPAT
  run "$@"; echo "$rc"; printf '%s\n' "$out") > "$w/linux.out"; }
run_linux "$w/build/bin/good"; rc="$(head -1 "$w/linux.out")"; out="$(tail -n +2 "$w/linux.out")"
[ "$rc" -eq 1 ] || { echo "FAIL ($label): exit $rc, want 1:"; echo "$out"; exit 1; }
says 'CANNOT MEASURE'; says 'drydock-objc analyze runs on macOS only'

# spec: assert_binary_compatible.sh's usage -- under --dist one environment covers every Mach-O, so the
#       per-binary allowance a CMake target passes in the knobs is a path-scoped deviation instead.
printf 'LC_ALL=C grep -aE "^(x86_64|arm64) " "$1"\n' > "$w/scripts/macho-slices.sh"
printf '#!/bin/sh\ncase "$1" in -m) LC_ALL=C sed -n "s/^NM //p" "$2" ;; *) LC_ALL=C sed -n "s/^DEF //p" "$1" ;; esac\n' > "$w/bin/nm"
printf '#!/bin/sh\nLC_ALL=C sed -n "s/^STR //p" "$2"\n' > "$w/bin/strings"
printf '#!/bin/sh\ncp "$3" "$5"\n' > "$w/bin/lipo"; chmod +x "$w/bin/nm" "$w/bin/strings" "$w/bin/lipo"
LIPO="$w/bin/lipo"; export LIPO
r="$w/tree/usr/local/mavergreen/demo"; mkdir -p "$r/bin" "$w/dist"
macho() { printf '\317\372\355\376\n'; printf '%s\n' "$@"; }
macho 'x86_64 EXECUTE 10.9 10.9' 'STR labelColor' 'DEF _shim' > "$r/bin/demo"
macho 'x86_64 EXECUTE 10.9 10.9' 'arm64 EXECUTE 11.0 11.3' 'DEF _shim' > "$r/bin/updater"
macho 'x86_64 EXECUTE 10.9 10.9' 'NM                  (undefined) weak external _os_log_create (from libSystem)' 'DEF _shim' > "$r/bin/weak"
macho 'x86_64 EXECUTE 10.9 10.9' > "$r/bin/noshim"
(cd "$w/tree" && tar czf "$w/dist/demo-1.0.0-mavergreen.1.tar.gz" usr)
dist() { rc=0; out="$(cd "$w" && SHIPYARD_CHECK_DIST="$w/dist" MAVERGREEN_DEVIATIONS_ROOT="$w/repo" MAVERGREEN_REQUIRE_DEFINED_SYMBOLS=_shim sh "$G" 2>&1)" || rc=$?; }
label="--dist with no deviation: each binary's own allowance is missing"
deviations_are
dist; [ "$rc" -ne 0 ] || { echo "FAIL ($label): should fail"; echo "$out"; exit 1; }
for id in compat-selectors compat-archs compat-imports compat-required-defined; do
  says "more: shipyard-check --explain $id"
done
label="--dist honours a path-scoped deviation for each compat id"
deviations_are \
  compat-selectors demo usr/local/mavergreen/demo/bin/demo 'it sends labelColor only after respondsToSelector:. Revisit when 10.9 leaves.' \
  compat-archs updater usr/local/mavergreen/demo/bin/updater 'the updater is universal. Revisit when P5 reads arm64.' \
  compat-imports weak usr/local/mavergreen/demo/bin/weak 'weak, NULL-checked. Revisit when the shim lands.' \
  compat-required-defined noshim usr/local/mavergreen/demo/bin/noshim 'a helper with no shim. Revisit when it links one.'
dist; [ "$rc" -eq 0 ] || { echo "FAIL ($label): should pass, exit $rc:"; echo "$out"; exit 1; }
for id in compat-selectors compat-archs compat-imports compat-required-defined; do
  says "is excused from $id:"
done
label="--dist: a deviation scoped to one binary excuses no other"
deviations_are compat-archs demo usr/local/mavergreen/demo/bin/demo 'wrong file. Revisit never.'
dist; [ "$rc" -ne 0 ] || { echo "FAIL ($label): should fail"; echo "$out"; exit 1; }
says "usr/local/mavergreen/demo/bin/updater arches"
echo "PASS: compat-guard-exemptions"
