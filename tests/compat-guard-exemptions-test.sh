#!/bin/sh
# platform: host-agnostic
#   usage: compat-guard-exemptions-test.sh
#          assert_binary_compatible.sh honours a declared sdk-pin:<glob> deviation, read from
#          $MAVERICKS_DEVIATIONS_ROOT/INGREDIENTS.md (default: the current directory), for the
#          minos/sdk rule ONLY. The Mach-O readers are stubbed: a fixture "binary" is the slice
#          lines macho-slices.sh would print, so the guard's own logic runs on any host;
#          tests/compat_guard.bats covers the same cases on real binaries. The Objective-C analyzer
#          is stubbed too (OBJC_COMPAT): it writes a complete strict report and passes or, while
#          bin/objc-blocks exists, names one blocking finding and exits 1. tests/objc-guard-test.sh
#          runs the real one. It runs opted in to the analyzer (MAVERGREEN_OBJC_STRICT=1) throughout.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/guard-exempt-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
# spec: scripts/objc-reference-dir.sh header -- laid out as an install, with a staged reference set, so nothing is fetched.
mkdir -p "$w/scripts" "$w/bin" "$w/repo" "$w/build/bin" "$w/reference/objc"
for s in assert_binary_compatible.sh sdk-pins.sh deviations.sh deviation-reason.sh objc-reference-dir.sh; do
  cp "$here/../scripts/$s" "$w/scripts/"
done
cat > "$w/scripts/macho-slices.sh" <<'EOF'
cat "$1"
EOF
cat > "$w/bin/shasum" <<'EOF'
#!/bin/sh
echo "0000000000000000000000000000000000000000000000000000000000000000  $3"
EOF
printf '#!/bin/sh\nexit 0\n' > "$w/bin/nm"
# spec: scripts/assert_binary_compatible.sh OBJC_COMPAT knob -- the strict analyzer's contract, a report at --report.
cat > "$w/bin/objc-compat" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do [ "$1" = --report ] && rep=$2; shift 2; done
printf '{"schema": 1, "mode": "strict", "complete_within_boundary": true, "findings": []}\n' > "$rep"
[ -e "$(dirname "$0")/objc-blocks" ] || exit 0
echo 'objc-compat: blocking: x86_64@0x1:+[NSColor labelColor] unsupported: introduced 10.10' >&2
exit 1
EOF
chmod +x "$w/bin/shasum" "$w/bin/nm" "$w/bin/objc-compat"
PATH="$w/bin:$PATH"; OBJC_COMPAT="$w/bin/objc-compat"; export PATH OBJC_COMPAT
unset MAVERICKS_DEVIATIONS_ROOT MAVERICKS_ALLOW_ARCHS MAVERICKS_ALLOW_SELECTORS MAVERICKS_POST_10_9_SELECTORS MAVERICKS_ALLOW_GUARDED_WEAK \
  MAVERGREEN_OBJC_ROOT MAVERGREEN_OBJC_BUILD_EVIDENCE MAVERGREEN_OBJC_PROVIDER_PREFIX MAVERGREEN_OBJC_SOURCE_RECEIPT MAVERGREEN_OBJC_REPORT_DIR
MAVERGREEN_OBJC_STRICT=1; export MAVERGREEN_OBJC_STRICT
G="$w/scripts/assert_binary_compatible.sh"

echo 'x86_64 EXECUTE 10.9 26.5' > "$w/build/bin/tool"
echo 'x86_64 EXECUTE 10.9 10.9' > "$w/build/bin/good"
echo 'arm64 EXECUTE 11.0 26.5' > "$w/build/bin/armtool"
ingredients() { printf '## Conformance deviations\n%s\n' "$1" > "$w/repo/INGREDIENTS.md"; }

run() {  # sets rc and out; $root, when set, is MAVERICKS_DEVIATIONS_ROOT, and $cwd where the guard runs
  rc=0
  if [ -n "$root" ]; then out="$(cd "${cwd:-$w}" && MAVERICKS_DEVIATIONS_ROOT="$root" sh "$G" "$@" 2>&1)" || rc=$?
  else out="$(cd "${cwd:-$w}" && sh "$G" "$@" 2>&1)" || rc=$?; fi
}
passes() { run "$@"; [ "$rc" -eq 0 ] || { echo "FAIL ($label): should pass, exit $rc:"; echo "$out"; exit 1; }; }
fails()  { run "$@"; [ "$rc" -ne 0 ] || { echo "FAIL ($label): should fail:"; echo "$out"; exit 1; }; }
says()   { printf '%s\n' "$out" | grep -qF -- "$1" || { echo "FAIL ($label): output lacks '$1':"; echo "$out"; exit 1; }; }

label="no INGREDIENTS.md: the rule applies"; root=""; cwd=""
fails "$w/build/bin/tool"; says 'sdk 26.5'
passes "$w/build/bin/good"

label="a matching glob excuses the sdk rule, and says so"; root="$w/repo"
ingredients '- sdk-pin:*/bin/tool: prebuilt upstream, shipped verbatim'
passes "$w/build/bin/tool"
says "compat guard: $w/build/bin/tool is excused from sdk-pin: prebuilt upstream, shipped verbatim"

label="a glob matches the path as given on the command line"
cwd="$w"; passes build/bin/tool
cwd="$w/build/bin"; fails tool; cwd=""

label="MAVERICKS_DEVIATIONS_ROOT defaults to the current directory"; root=""; cwd="$w/repo"
passes "$w/build/bin/tool"; cwd=""; root="$w/repo"

label="a non-matching glob excuses nothing"
ingredients '- sdk-pin:*/bin/other: prebuilt upstream'
fails "$w/build/bin/tool"; says 'sdk 26.5'

label="a deviation for another check excuses nothing"
ingredients '- install-path:*/bin/tool: somewhere odd'
fails "$w/build/bin/tool"

label="an unscoped sdk-pin deviation excuses every file"
ingredients '- sdk-pin: every binary here is prebuilt'
passes "$w/build/bin/tool"; says 'is excused from sdk-pin: every binary here is prebuilt'

label="a glob with no reason fails the guard closed"
ingredients '- sdk-pin:*/bin/tool:'
fails "$w/build/bin/tool"
label="a malformed entry for ANY check fails the guard closed, even for a clean binary"
ingredients '- scheme:no space after the colon'
fails "$w/build/bin/good"

label="an excuse covers only the sdk rule: an arch outside MAVERICKS_ALLOW_ARCHS still fails"
ingredients '- sdk-pin:*/bin/armtool: prebuilt upstream'
fails "$w/build/bin/armtool"; says "arches 'arm64' != 'x86_64'"
run_arm() { MAVERICKS_ALLOW_ARCHS=arm64; export MAVERICKS_ALLOW_ARCHS; passes "$@"; unset MAVERICKS_ALLOW_ARCHS; }
label="the same excuse passes once the arch is allowed"; run_arm "$w/build/bin/armtool"

label="an excuse covers only the sdk rule: a post-10.9 import still fails"
ingredients '- sdk-pin:*/bin/tool: prebuilt upstream'
printf '#!/bin/sh\necho "                 (undefined) external _clock_gettime (from libSystem)"\n' > "$w/bin/nm"
fails "$w/build/bin/tool"; says '_clock_gettime'
printf '#!/bin/sh\nexit 0\n' > "$w/bin/nm"

label="an excuse covers only the sdk rule: a blocking Objective-C send still fails"
: > "$w/bin/objc-blocks"
fails "$w/build/bin/tool"; says 'labelColor'
rm "$w/bin/objc-blocks"

label="an excused file does not excuse its neighbour on the same command line"
fails "$w/build/bin/tool" "$w/build/bin/armtool"; says 'armtool'
echo "PASS: compat-guard-exemptions"
