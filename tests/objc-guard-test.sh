#!/bin/sh
# platform: macOS-only -- links x86_64 fixtures against the pinned 10.9 SDK and runs the real guard and analyzer on them
# spec: scripts/assert_binary_compatible.sh header -- opted in (MAVERGREEN_OBJC_STRICT=1), the guard fails any binary whose x86_64 slice
#       sends an Objective-C message the 10.9 floor cannot answer, as the strict analyzer
#       (scripts/objc-compat.sh) measures it against the versioned reference set, with no selector
#       list anywhere; it keeps its SDK, floor, architecture and import checks; it passes a
#       measured C-only binary and prose that merely spells a later selector; and it never reuses
#       an earlier verdict. MAVERGREEN_OBJC_CODEX_ARTIFACT, when set, is the original Codex 0.165.0
#       binary, which must fail on its NSWorkspace launch. MAVERGREEN_OBJC_RECAULK_PREFIX and
#       MAVERGREEN_OBJC_RECAULK_RECEIPT, when both set, are a staged Recaulk provider and its source
#       receipt (Drydock's tests/objc/objc-provider-test.sh header): the guard on a consumer linked with it must
#       agree with its report, passing exactly when no finding blocks and otherwise naming each
#       one. A consumer linked with the fixture provider (tests/lib/objc_fixture_provider.sh) must
#       pass on every host. Nothing built here is executed.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
FX="$HERE/fixtures/objc-api"
G="$ROOT/scripts/assert_binary_compatible.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/objc-guard-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; [ ! -f "$T/out" ] || tail -12 "$T/out" >&2; exit 1; }
unset MAVERGREEN_ALLOW_SELECTORS MAVERGREEN_POST_10_9_SELECTORS MAVERGREEN_ALLOW_ARCHS MAVERGREEN_POST_10_9_SYMBOLS \
  MAVERGREEN_OBJC_ROOT MAVERGREEN_OBJC_BUILD_EVIDENCE MAVERGREEN_OBJC_PROVIDER_PREFIX MAVERGREEN_OBJC_SOURCE_RECEIPT \
  MAVERGREEN_OBJC_REPORT_DIR MAVERGREEN_OBJC_REFERENCES OBJC_COMPAT MAVERGREEN_DEVIATIONS_ROOT MAVERGREEN_OBJC_STRICT

unset MAVERGREEN_DRYDOCK_PREFIX
SDK=$(sh "$ROOT/scripts/fetch_sdk.sh" --arch x86_64)
# spec: scripts/objc-reference-dir.sh header -- the reference set the guard defaults to, named where a test needs it.
REFS=$(sh "$ROOT/scripts/objc-reference-dir.sh")
# platform: env -i keeps CPATH and SDKROOT from steering the fixtures away from the pinned SDK.
cc() { env -i PATH=/usr/bin:/bin /usr/bin/clang -arch x86_64 -isysroot "$SDK" -mmacosx-version-min=10.9 -O1 "$@"; }
sha() { shasum -a 256 "$1" | cut -c1-64; }
mkdir -p "$T/root/bin" "$T/repo"
# spec: scripts/assert_binary_compatible.sh header -- guard [ENV=VALUE ...] -- BINARY...: rc and $T/out, opted in to
#       the strict analyzer; runs where no .mavergreen/deviations/ declares anything. plain_guard is the same, not opted in.
plain_guard() {
  rc=0
  (cd "$T/repo" && env "$@" sh "$G" "$BIN" ${BIN2:+"$BIN2"}) >"$T/out" 2>&1 || rc=$?
}
guard() { plain_guard MAVERGREEN_OBJC_STRICT=1 "$@"; }
passes() { guard "$@"; [ "$rc" = 0 ] || fail "$label: exit $rc, want 0"; }
# spec: scripts/assert_binary_compatible.sh header -- cannot-measure fails its check closed (exit 1) and says so; want=4
#       names that verdict, so a cannot-measure is never mistaken for a blocking finding.
fails() {
  guard "$@"
  if [ "$want" = 4 ]; then
    [ "$rc" = 1 ] && grep -F 'CANNOT MEASURE' "$T/out" >/dev/null || fail "$label: exit $rc, want cannot-measure (exit 1, CANNOT MEASURE)"
  else [ "$rc" = "$want" ] || fail "$label: exit $rc, want $want"; fi
}
says() { grep -F -- "$1" "$T/out" >/dev/null || fail "$label: the guard does not say '$1'"; }

cc "$FX/plain.c" -o "$T/root/bin/plain"
cc -DFORM=1 "$FX/guard.c" -o "$T/root/bin/later" -lobjc
cc -DFORM=2 "$FX/guard.c" -o "$T/root/bin/outside" -lobjc
cc -DFORM=3 "$FX/guard.c" -o "$T/root/bin/prose" -lobjc
cc "$FX/provider-consumer.m" -o "$T/root/bin/consumer" -framework AppKit
cc -DFORM=1 "$FX/unsupported.c" -o "$T/root/bin/computed" -lobjc
BIN2=

# spec: scripts/assert_binary_compatible.sh header -- the real missing method: a 10.10 NSWorkspace launch sent by a binary
#       linked with no provider. No list names it; the old guard's raw-selector scan passed it.
label='missing NSWorkspace method'; BIN="$T/root/bin/consumer"; want=1
fails X=1; says 'openURLs:withApplicationAtURL:options:configuration:error:'; says 'unsupported'
# spec: scripts/assert_binary_compatible.sh header -- a measured binary with no Objective-C passes, and says it was measured.
label='C-only binary'; BIN="$T/root/bin/plain"
passes X=1; says 'binaries clean'; says 'Objective-C sends'
# spec: scripts/assert_binary_compatible.sh header -- an analogous later method, cataloged by the reference set, on no list.
label='later method'; BIN="$T/root/bin/later"; want=1
fails X=1; says 'containsString:'; says 'unsupported'
# spec: scripts/assert_binary_compatible.sh header -- unresolved blocks too.
label='unresolved send'; BIN="$T/root/bin/outside"; want=1
fails X=1; says 'unresolved'
# spec: scripts/assert_binary_compatible.sh header -- prose that spells a later selector is not a send of it.
label='incidental prose'; BIN="$T/root/bin/prose"
passes X=1
# spec: scripts/assert_binary_compatible.sh header -- a dispatch form the analyzer cannot examine is cannot-measure.
label='computed selector'; BIN="$T/root/bin/computed"; want=4
fails X=1; says 'CANNOT MEASURE'

# spec: scripts/assert_binary_compatible.sh header -- the existing checks stay: architecture, floor, imports.
label='arch set'; BIN="$T/root/bin/plain"; want=1
fails MAVERGREEN_ALLOW_ARCHS=arm64; says "arches 'x86_64' != 'arm64'"
cc -mmacosx-version-min=10.10 "$FX/plain.c" -o "$T/root/bin/floor1010"
label='minos above the floor'; BIN="$T/root/bin/floor1010"; want=1
fails X=1; says 'minos 10.10'
printf 'extern int mav_test_post109(void);\nint main(void){return mav_test_post109();}\n' >"$T/leak.c"
cc -Wl,-undefined,dynamic_lookup "$T/leak.c" -o "$T/root/bin/leak"
label='post-10.9 import'; BIN="$T/root/bin/leak"; want=1
fails MAVERGREEN_POST_10_9_SYMBOLS=_mav_test_post109; says '_mav_test_post109'
label='a failing reader is still cannot-measure'; BIN="$T/root/bin/plain"; want=4
fails NM=false; says 'CANNOT MEASURE'

# spec: scripts/assert_binary_compatible.sh header -- the retired selector knobs fail with a migration diagnostic.
label='MAVERGREEN_ALLOW_SELECTORS'; BIN="$T/root/bin/plain"; want=2
fails MAVERGREEN_ALLOW_SELECTORS=labelColor; says 'MAVERGREEN_ALLOW_SELECTORS is retired'; says 'objc-api'
label='MAVERGREEN_POST_10_9_SELECTORS'; want=2
fails MAVERGREEN_POST_10_9_SELECTORS=labelColor; says 'MAVERGREEN_POST_10_9_SELECTORS is retired'; says 'reference/objc'

# spec: scripts/assert_binary_compatible.sh header -- the analyzer is opt-in: without MAVERGREEN_OBJC_STRICT=1 the guard
#       keeps its selector list (so the missing NSWorkspace method, on no list, passes as it always has), an analyzer
#       knob is misuse rather than silently ignored, and any value but 1 or empty is misuse.
label='not opted in'; BIN="$T/root/bin/consumer"
plain_guard X=1; [ "$rc" = 0 ] || fail "$label: exit $rc, want 0"; says 'binaries clean'
! grep -F 'Objective-C sends measured' "$T/out" >/dev/null || fail "$label: the analyzer ran without the opt-in"
label='an analyzer knob without the opt-in'; BIN="$T/root/bin/plain"
plain_guard MAVERGREEN_OBJC_BUILD_EVIDENCE="$T/e.json"; [ "$rc" = 2 ] || fail "$label: exit $rc, want 2"
says 'MAVERGREEN_OBJC_BUILD_EVIDENCE needs MAVERGREEN_OBJC_STRICT=1'
label='MAVERGREEN_OBJC_STRICT=yes'
plain_guard MAVERGREEN_OBJC_STRICT=yes; [ "$rc" = 2 ] || fail "$label: exit $rc, want 2"; says 'MAVERGREEN_OBJC_STRICT is 1 or unset'

# spec: scripts/assert_binary_compatible.sh header -- evidence is the analyzer's input: missing or malformed is cannot-measure,
#       and one artifact-bound evidence file cannot speak for two binaries.
label='missing build evidence'; BIN="$T/root/bin/consumer"; want=4
fails MAVERGREEN_OBJC_BUILD_EVIDENCE="$T/no such evidence.json"; says 'CANNOT MEASURE'
printf '{"schema": 1, "kind": "objc-build-evidence",\n' >"$T/malformed.json"
label='malformed build evidence'; want=4
fails MAVERGREEN_OBJC_BUILD_EVIDENCE="$T/malformed.json"; says 'CANNOT MEASURE'
label='one evidence file, two binaries'; BIN2="$T/root/bin/plain"; want=2
fails MAVERGREEN_OBJC_BUILD_EVIDENCE="$T/malformed.json"; says 'one binary'
BIN2=
label='a binary outside the shipped root'; BIN="$T/root/bin/plain"; want=2
mkdir -p "$T/elsewhere"
fails MAVERGREEN_OBJC_ROOT="$T/elsewhere"; says 'not inside'

# spec: scripts/assert_binary_compatible.sh header -- paths with spaces and quotes reach the analyzer intact.
q="$T/root/it's a \"dir\""
mkdir -p "$q"; cp "$T/root/bin/consumer" "$q/bin x"; cp "$T/root/bin/plain" "$q/plain x"
label='quoted paths'; BIN="$q/plain x"
passes MAVERGREEN_OBJC_ROOT="$T/root"
BIN="$q/bin x"; want=1
fails MAVERGREEN_OBJC_ROOT="$T/root"; says 'openURLs:'

# spec: scripts/assert_binary_compatible.sh header -- an analyzer or a reference set that is missing or cannot be fetched is
#       cannot-measure, never a skip.
label='missing analyzer'; BIN="$T/root/bin/consumer"; want=4
fails OBJC_COMPAT="$T/no-analyzer"; says 'CANNOT MEASURE'
label='an analyzer that cannot be fetched'; want=4
fails MAVERGREEN_OBJC_REFERENCES="$REFS" MAVERGREEN_DRYDOCK_PREFIX="$T/no-drydock"; says 'CANNOT MEASURE'; says 'the pinned Drydock could not be had'
label='no reference set to be had'
fails MAVERGREEN_DRYDOCK_PREFIX="$T/no-drydock"; says 'CANNOT MEASURE'; says 'no Objective-C reference set'

# spec: scripts/assert_binary_compatible.sh header -- every run measures afresh: a kept clean report is never reused, and the
#       same path holding new bytes gets the new verdict.
mkdir -p "$T/reports" "$T/root/swap"
cp "$T/root/bin/plain" "$T/root/swap/tool"
label='kept report'; BIN="$T/root/swap/tool"
passes MAVERGREEN_OBJC_REPORT_DIR="$T/reports"
ls "$T/reports"/* >/dev/null 2>&1 || fail 'kept report: MAVERGREEN_OBJC_REPORT_DIR holds no report'
grep -F "\"sha256\": \"$(sha "$BIN")\"" "$T/reports"/* >/dev/null || fail 'kept report: it does not name the binary'
# spec: scripts/objc-compat.sh header -- the analyzer is the pinned Drydock's drydock-objc, and its report says so.
DRYDOCK_V=$(sed -n '1s/^v//p' "$ROOT/.mavergreen/ingredients/drydock/VERSION")
grep -F "\"analyzer\": \"drydock-$DRYDOCK_V-objc-src-" "$T/reports"/* >/dev/null ||
  fail "kept report: its analyzer is not drydock-$DRYDOCK_V's ($(grep -o '"analyzer": "[^"]*"' "$T/reports"/* | head -1))"
grep -o '"analyzer": "[^"]*"' "$T/reports"/* | head -1 | sed 's/^/objc-guard: /'
cp "$T/root/bin/consumer" "$T/root/swap/tool"
label='the same path, new bytes'; want=1
fails X=1; says 'openURLs:'
label='a stale report in the report directory'; want=2
fails MAVERGREEN_OBJC_REPORT_DIR="$T/reports"

# spec: scripts/assert_binary_compatible.sh header -- an objc-api deviation excuses one blocking finding of one artifact:
#       its declared artifact glob and its evidence record's artifact_glob must both match the artifact path relative to
#       the shipped root, and the record must name that finding's site, receiver, kind and selector and the artifact's own
#       digest, with a concrete basis, a reviewer, the declared review reason and a retirement condition. The finding
#       stays in the report, marked, and the guard says it applied the deviation.
D="$T/dev"
mkdir -p "$D/compat" "$D/rep"
cp "$T/root/bin/consumer" "$T/root/bin/launch"
BIN="$T/root/bin/launch"
guard MAVERGREEN_OBJC_ROOT="$T/root" MAVERGREEN_OBJC_REPORT_DIR="$D/rep"
[ "$rc" = 1 ] || fail "deviation setup: exit $rc, want 1"
OPEN='openURLs:withApplicationAtURL:options:configuration:error:'
L=$(grep -F "\"selector\": \"$OPEN\"" "$D/rep"/*)
FID=$(printf '%s\n' "$L" | sed -n 's/.*"id": "\([^"]*\)".*/\1/p')
SITE=$(printf '%s\n' "$L" | sed -n 's/.*"site": "\([^"]*\)".*/\1/p')
FN=$(printf '%s\n' "$L" | sed -En 's/.*"function": ("[^"]*"|null).*/\1/p')
[ -n "$FID" ] && [ -n "$SITE" ] && [ -n "$FN" ] || fail "deviation setup: no openURLs finding in the report"
REC=$(printf '{"id": "ws-launch", "artifact_glob": "bin/launch", "class": "NSWorkspace", "kind": "-", "selector": "%s", "finding": {"id": "%s", "site": "%s", "function": %s}, "evidence": {"artifact_sha256": "%s", "build_evidence_sha256": null, "source_revision": null, "patches_sha256": null}, "basis": {"kind": "false-positive", "proof": "main returns before the send unless argc > 99"}, "reviewer": "A. Reviewer", "review_reason": "test-only review", "retire_when": "the fixture is removed"}' \
  "$OPEN" "$FID" "$SITE" "$FN" "$(sha "$BIN")")
SCOPE='bin/launch'
WHY='evidence=compat/objc-exceptions.json#ws-launch test-only review'
records() { printf '{"schema": 1, "kind": "objc-exceptions", "records": [%s]}\n' "$1" >"$D/compat/objc-exceptions.json"; }
. "$HERE/lib/deviation_tree.sh"
declare_dev() { rm -rf "$D/.mavergreen"; deviation "$D" objc-api ws-launch "$1" "$2"; }
# spec: scripts/assert_binary_compatible.sh header -- excused LABEL WANT SED [SCOPE [REASON]]: the guard on $BIN with the record
#       edited by SED (none: '') under .mavergreen/deviations/objc-api/ws-launch/ (default scope $SCOPE, reason $WHY).
excused() {
  label=$1 want=$2
  records "$(printf '%s\n' "$REC" | sed "$3")"
  declare_dev "${4:-$SCOPE}" "${5:-$WHY}"
  fails MAVERGREEN_DEVIATIONS_ROOT="$D" MAVERGREEN_OBJC_ROOT="$T/root"
}
excused 'a matching reviewed record' 0 ''
says "objc-api deviation ws-launch applies to $FID"; says 'test-only review'
rm -rf "$D/rep2"; mkdir -p "$D/rep2"
fails MAVERGREEN_DEVIATIONS_ROOT="$D" MAVERGREEN_OBJC_ROOT="$T/root" MAVERGREEN_OBJC_REPORT_DIR="$D/rep2"
grep -F "\"id\": \"$FID\"" "$D/rep2"/* | grep '"verdict": "unsupported"' | grep -F '"deviation": "ws-launch"' >/dev/null ||
  fail 'the excused finding is not kept, unsupported and marked, in the report'
grep -A1 -F '"deviations": [' "$D/rep2"/* | grep -F '{"id": "ws-launch", "evidence_sha256": ' | grep -F "\"applied_to\": [\"$FID\"]" >/dev/null ||
  fail 'the report does not list the applied deviation'
# spec: scripts/assert_binary_compatible.sh header -- nothing unrelated inherits it: another API, artifact, site, receiver,
#       digest or declared scope.
excused 'another selector' 1 "s/\"selector\": \"$OPEN\"/\"selector\": \"isVoiceOverEnabled\"/"
excused 'another receiver class' 1 's/"class": "NSWorkspace"/"class": "NSString"/'
excused 'another artifact in the record' 1 's/"artifact_glob": "bin\/launch"/"artifact_glob": "bin\/other"/'
excused 'another site' 1 "s/\"site\": \"$SITE\"/\"site\": \"0x1\"/"
excused 'another artifact digest' 1 "s/\"artifact_sha256\": \"[0-9a-f]*\"/\"artifact_sha256\": \"$(printf '%064d' 0)\"/"
excused 'another declared artifact' 1 '' 'bin/other'
# spec: scripts/assert_binary_compatible.sh header -- the evidence must be a file inside MAVERGREEN_DEVIATIONS_ROOT.
echo '{}' >"$T/outside.json"; ln -s "$T/outside.json" "$D/compat/link.json"
excused 'absent evidence' 4 '' '' 'evidence=compat/missing.json#ws-launch test-only review'
excused 'escaping evidence' 4 '' '' 'evidence=../outside.json#ws-launch test-only review'
excused 'absolute evidence' 4 '' '' "evidence=$T/outside.json#ws-launch test-only review"
excused 'symlinked evidence' 4 '' '' 'evidence=compat/link.json#ws-launch test-only review'
# spec: scripts/assert_binary_compatible.sh header -- a malformed, wildcard or unreviewed record is cannot-measure.
excused 'no reviewer' 4 's/"reviewer": "A. Reviewer", //'
excused 'no retirement condition' 4 's/"retire_when": "the fixture is removed"/"retire_when": ""/'
excused 'an installed-provider basis' 4 's/"kind": "false-positive"/"kind": "installed-provider"/'
excused 'a wildcard selector' 4 "s/\"selector\": \"$OPEN\"/\"selector\": \"*\"/"
excused 'a wildcard artifact' 4 's/"artifact_glob": "bin\/launch"/"artifact_glob": "*"/'
excused 'an unknown key' 4 's/"reviewer": /"scope": "all", "reviewer": /'
excused 'another record id' 4 's/"id": "ws-launch"/"id": "ws-other"/'
excused 'another review reason' 4 '' '' 'evidence=compat/objc-exceptions.json#ws-launch some other reason'
excused 'an unscoped declaration' 4 '' '*'

# spec: scripts/assert_binary_compatible.sh header -- the real defect: original Codex 0.165.0 fails on its launch.
if [ -n "${MAVERGREEN_OBJC_CODEX_ARTIFACT:-}" ]; then
  [ "$(sha "$MAVERGREEN_OBJC_CODEX_ARTIFACT")" = 1d056b0d4ada3d74b4c0f4c5450bc06856bfdbc504320fa430a4249f640f6c40 ] ||
    fail 'unexpected Codex artifact'
  mkdir -p "$T/root/codex"
  ln "$MAVERGREEN_OBJC_CODEX_ARTIFACT" "$T/root/codex/codex" 2>/dev/null || cp "$MAVERGREEN_OBJC_CODEX_ARTIFACT" "$T/root/codex/codex"
  label='original Codex 0.165.0'; BIN="$T/root/codex/codex"; want=1
  fails MAVERGREEN_OBJC_ROOT="$T/root" MAVERGREEN_OBJC_BUILD_EVIDENCE="$FX/codex-0.165.0-build-evidence.json"
  says 'x86_64@0x10d52d65f:-[NSWorkspace openURLs:withApplicationAtURL:options:configuration:error:] unsupported'
  echo "objc-guard: original Codex 0.165.0: exit $rc; $(grep -c ' unsupported\| unresolved' "$T/out") blocking findings named"
  rm -f "$T/root/codex/codex"
fi

# spec: scripts/objc-provider-link-args.sh header -- linked_consumer DIR PREFIX: the fixture consumer linked with PREFIX's
#       provider at DIR/root/bin/rooted, with its link map and build evidence at DIR/{rooted.map,ev.json}.
linked_consumer() {
  lc_dir=$1 lc_pfx=$2
  mkdir -p "$lc_dir/root/bin"
  sh "$ROOT/scripts/objc-provider-link-args.sh" --prefix "$lc_pfx" --link-map "$lc_dir/rooted.map" >"$lc_dir/args"
  set --
  while IFS= read -r line; do set -- "$@" "$line"; done <"$lc_dir/args"
  cc "$FX/provider-consumer.m" "$@" -o "$lc_dir/root/bin/rooted"
  set --
  sh "$ROOT/scripts/objc-build-evidence.sh" --artifact "$lc_dir/root/bin/rooted" --prestrip "$lc_dir/root/bin/rooted" --source-root "$FX" \
    --link-map "$lc_dir/rooted.map" --provider-prefix "$lc_pfx" --references "$REFS" --output "$lc_dir/ev.json"
}
# spec: tests/lib/objc_fixture_provider.sh -- fixture_prefix DIR [CC-FLAGS] and declare_prefix DIR RECEIPT.
. "$HERE/lib/objc_fixture_provider.sh"
# spec: scripts/assert_binary_compatible.sh header -- a consumer linked with the fixture provider, with its build evidence,
#       passes the whole guard on every host: every send of its body closes.
fixture_prefix "$T/fixture-prefix"
linked_consumer "$T/fx" "$T/fixture-prefix"
label='consumer linked with the fixture provider'; BIN="$T/fx/root/bin/rooted"
passes MAVERGREEN_OBJC_ROOT="$T/fx/root" MAVERGREEN_OBJC_BUILD_EVIDENCE="$T/fx/ev.json" MAVERGREEN_OBJC_PROVIDER_PREFIX="$T/fixture-prefix"
says 'binaries clean'
label='the same consumer without its build evidence'; want=4
fails MAVERGREEN_OBJC_ROOT="$T/fx/root" MAVERGREEN_OBJC_PROVIDER_PREFIX="$T/fixture-prefix"
# spec: scripts/assert_binary_compatible.sh header -- a consumer linked with the staged Recaulk provider, with its build evidence
#       and the provider's source receipt: the guard agrees with the report it keeps. It passes exactly when no finding is
#       unsupported or unresolved; otherwise it exits 1 and names every such finding. Which holds depends on the provider's
#       codegen (Apple clang 21 -Os merges two sends of its body into one call site), never on an exemption.
if [ -n "${MAVERGREEN_OBJC_RECAULK_PREFIX:-}" ] && [ -n "${MAVERGREEN_OBJC_RECAULK_RECEIPT:-}" ]; then
  PFX=$MAVERGREEN_OBJC_RECAULK_PREFIX
  linked_consumer "$T/rk" "$PFX"
  label='consumer linked with the Recaulk provider'; BIN="$T/rk/root/bin/rooted"
  mkdir -p "$T/rk/rep"
  guard MAVERGREEN_OBJC_ROOT="$T/rk/root" MAVERGREEN_OBJC_BUILD_EVIDENCE="$T/rk/ev.json" MAVERGREEN_OBJC_PROVIDER_PREFIX="$PFX" \
    MAVERGREEN_OBJC_SOURCE_RECEIPT="$MAVERGREEN_OBJC_RECAULK_RECEIPT" MAVERGREEN_OBJC_REPORT_DIR="$T/rk/rep"
  rep=$(ls "$T/rk/rep"/* 2>/dev/null | head -1)
  [ -n "$rep" ] || fail "$label: the guard kept no report (exit $rc)"
  grep -E '"verdict": "(unsupported|unresolved)"' "$rep" | sed -n 's/^ *{"id": "\([^"]*\)".*/\1/p' >"$T/rk/blocking"
  if [ -s "$T/rk/blocking" ]; then
    [ "$rc" = 1 ] || fail "$label: $(wc -l <"$T/rk/blocking" | tr -d ' ') blocking findings, exit $rc, want 1"
    while IFS= read -r id; do says "$id"; done <"$T/rk/blocking"
    ! grep '"function": "_main"' "$rep" | grep -E '"verdict": "(unsupported|unresolved)"' >/dev/null ||
      fail "$label: the consumer's own send blocks"
    echo "objc-guard: Recaulk consumer: exit 1, $(wc -l <"$T/rk/blocking" | tr -d ' ') blocking findings of its provider body named"
  else
    [ "$rc" = 0 ] || fail "$label: no blocking finding, exit $rc, want 0"
    echo "objc-guard: Recaulk consumer: $(grep 'binaries clean' "$T/out")"
  fi
  label='the same consumer without its build evidence'; want=4
  fails MAVERGREEN_OBJC_ROOT="$T/rk/root" MAVERGREEN_OBJC_PROVIDER_PREFIX="$PFX"
fi
echo 'objc-guard: strict Objective-C verdicts, kept checks, migration failures, evidence, paths, tools, freshness and scoped deviations pass'
