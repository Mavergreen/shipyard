#!/bin/sh
# spec: SKILL.md "A release is a declared state, not an event" -- ruling 16. The answer must
#       depend on the digest and never on the version: version.sh's `auto` mode maps every
#       declared state of a given upstream to ONE version, so "a release exists for this version"
#       does not mean "a release exists for this state". The four version/digest QUADRANTS below
#       are the cases that matter, and writing them down is what would have caught the defect.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/release-needed.sh"
_tmp="${TMPDIR:-/tmp}"                    # macOS sets TMPDIR with a trailing slash
w="$(mktemp -d "${_tmp%/}/release-needed-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
D1='v1:sha256:8c5fc85c689b60ccc9a3ed0120fa949e2bd9c0f9a121ac572fa11ba148312be7'
D2='v1:sha256:405b7fdda86a03f4ef636aceb3c7c819fe5d93208118cd365a0b962cb37c8004'
TAB="$(printf '\t')"

# spec: scripts/release-needed.sh -- two injection points, deliberately. $MAVERICKS_RELEASES is
#       the finished records: it exercises the DECISION. $MAVERICKS_RELEASES_RAW is the API's own
#       shape -- "<tag><TAB><draft><TAB><body>", the body escaped the way jq's @tsv escapes it --
#       so the code that PARSES the outside world is code these cases run too. It once was not,
#       and the two bugs that hid behind the higher injection point were both reproduced: an
#       invalid --json field made every night answer PUBLISH in all 14 repos, and any gh failure
#       answered PUBLISH too.
run() { MAVERICKS_RELEASES="$1" sh "$S" --digest "$2" --version "$3"; }
raw() { MAVERICKS_RELEASES_RAW="$1" sh "$S" --digest "$2" --version "$3"; }

got="$(run "" "$D1" 1.2.3-mavericks.1)"
[ "$got" = PUBLISH ] || { echo "FAIL: nothing released yet must publish: got '$got'"; exit 1; }

got="$(run "1.2.3-mavericks.1${TAB}${D1}" "$D1" 1.2.3-mavericks.1)"
[ "$got" = "SKIP=already-released/1.2.3-mavericks.1" ] || { echo "FAIL: a release carrying this digest must skip, naming the tag that has it: got '$got'"; exit 1; }

got="$(run "1.2.3-mavericks.1${TAB}" "$D1" 1.2.3-mavericks.1)"
[ "$got" = PUBLISH ] \
  || { echo "FAIL: THE QUADRANT THAT PROVES THE RULING -- a release exists for this very VERSION but carries no digest, so it must PUBLISH; inferring \"already released\" here is what lost a release, since an unreleased ingredient bump gets version.sh auto's existing tag, making this shape indistinguishably both the pre-migration past AND a released state, which is why the version cannot decide: a digest-less release for this version decided: got '$got'"; exit 1; }

got="$(run "1.2.3-mavericks.1${TAB}${D2}" "$D1" 1.2.3-mavericks.1)"
[ "$got" = PUBLISH ] || { echo "FAIL: the same version with a DIFFERENT readable digest is an earlier state of it and must block nothing -- the state changed, the version did not, and the state is what a release realises: same version, different digest: got '$got'"; exit 1; }

got="$(run "1.2.3-mavericks.4${TAB}${D1}" "$D1" 1.2.3-mavericks.1)"
[ "$got" = "SKIP=already-released/1.2.3-mavericks.4" ] \
  || { echo "FAIL: the fourth quadrant -- a different version carrying THIS digest is already released: different version, this digest: got '$got'"; exit 1; }

got="$(run "1.2.3-mavericks.1${TAB}${D1}" "$D2" 1.2.3-mavericks.2)"
[ "$got" = PUBLISH ] || { echo "FAIL: an ordinary ingredient bump (a release exists with a different digest and a different version) must publish: got '$got'"; exit 1; }

got="$(run "9.9.9-mavericks.7${TAB}${D1}" "$D1" 1.2.3-mavericks.1)"
[ "$got" = "SKIP=already-released/9.9.9-mavericks.7" ] || { echo "FAIL: the digest must win over the version -- the same state already out under another version (a hand-cut repackage, say) must not be published again: got '$got'"; exit 1; }

got="$(run "1.2.3-mavericks.1${TAB}v0:sha256:deadbeef" "$D1" 1.2.3-mavericks.2)"
[ "$got" = "SKIP=unreadable-marker/1.2.3-mavericks.1" ] \
  || { echo "FAIL: a marker in an older FORMAT is not this digest, and is not \"no marker\" either -- publishing would be exactly how a bump to v2 republishes all 14 products (\"recompute, never republish\"), so it must get its own answer naming the tag that needs recomputing, and must not crash: old-format marker: got '$got'"; exit 1; }

got="$(run "1.2.3-mavericks.1${TAB}${D2}" "$D1" 9.9.9-mavericks.9)"
[ "$got" = PUBLISH ] || { echo "FAIL: a READABLE digest that merely differs is an ordinary earlier state and must block nothing: got '$got'"; exit 1; }

got="$(run "8.0.0-mavericks.1${TAB}v0:sha256:deadbeef
1.2.3-mavericks.1${TAB}${D1}" "$D1" 1.2.3-mavericks.1)"
[ "$got" = "SKIP=already-released/1.2.3-mavericks.1" ] \
  || { echo "FAIL: a digest match must WIN over an unreadable marker elsewhere -- the state demonstrably is released, so there is nothing for a human to recompute before anything can proceed: an unreadable marker outranked a real match: got '$got'"; exit 1; }

got="$(run "9.0.0-mavericks.1${TAB}
1.2.3-mavericks.1${TAB}${D1}
8.0.0-mavericks.3${TAB}v1:sha256:abc" "$D1" 1.2.3-mavericks.1)"
[ "$got" = "SKIP=already-released/1.2.3-mavericks.1" ] || { echo "FAIL middle match: got '$got'"; exit 1; }

got="$(run "9.9.9-mavericks.7${TAB}${D1}
1.2.3-mavericks.1${TAB}" "$D1" 1.2.3-mavericks.1)"
[ "$got" = "SKIP=already-released/9.9.9-mavericks.7" ] \
  || { echo "FAIL: a digest match and a same-version release land on TWO DIFFERENT tags -- the answer must name the tag that actually HAS this state, since naming the version-tag would lie about which release realises it: priority, two tags: got '$got'"; exit 1; }

rc=0; MAVERICKS_RELEASES="" sh "$S" --digest "$D1" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: usage errors are exit 2, distinct from a decision -- a caller that forgot an argument must never be told \"publish\": missing --version should exit 2, got $rc"; exit 1; }
rc=0; MAVERICKS_RELEASES="" sh "$S" --version 1.2.3-mavericks.1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL missing --digest should exit 2, got $rc"; exit 1; }

rc=0; MAVERICKS_RELEASES="" sh "$S" --digest sha256:nope --version 1.2.3-mavericks.1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: a malformed digest is a usage error too -- it can only come from a caller bug, and treating it as \"no match\" would publish: should exit 2, got $rc"; exit 1; }

# spec: scripts/release-needed.sh -- everything below injects the RAW API shape, so the
#       transform that PARSES the outside world actually runs.
P11="$(printf '%s\n' \
  "9.0.0-mavericks.1${TAB}false${TAB}## 9.0.0-mavericks.1\n\n- old news\n" \
  "1.2.3-mavericks.1${TAB}false${TAB}## 1.2.3-mavericks.1\n\n- a thing\n\nModernMavericks-State: ${D1}\n" \
  "8.0.0-mavericks.3${TAB}false${TAB}## 8.0.0-mavericks.3\n\n- nothing recorded here\n")"
got="$(raw "$P11" "$D1" 7.7.7-mavericks.1)"
[ "$got" = "SKIP=already-released/1.2.3-mavericks.1" ] \
  || { echo "FAIL: bodies are real notes -- multi-line, with the marker its own paragraph, exactly as release-state-record.sh writes it -- and the digest must be attributed to the tag whose body carries it, and to no other: raw payload: got '$got'"; exit 1; }

got="$(raw "$P11" "$D2" 7.7.7-mavericks.1)"
[ "$got" = PUBLISH ] || { echo "FAIL: a body with NO marker is digest-less, not a match: raw payload, no marker for this digest: got '$got'"; exit 1; }

got="$(raw "1.2.3-mavericks.9${TAB}true${TAB}ModernMavericks-State: ${D1}" "$D1" 7.7.7-mavericks.1)"
[ "$got" = PUBLISH ] || { echo "FAIL: a DRAFT is not a release -- publish-release.yml creates a draft per attempt and delete-draft-release.sh cleans them up, so a leftover draft carrying the current digest is a real shape, and counting it would answer already-released forever while the real release silently never happened: a draft counted as released: got '$got'"; exit 1; }

got="$(raw "$(printf '%s\n' \
  "2.0.0-mavericks.1${TAB}true${TAB}ModernMavericks-State: ${D1}" \
  "3.0.0-mavericks.1${TAB}false${TAB}ModernMavericks-State: ${D2}")" "$D2" 7.7.7-mavericks.1)"
[ "$got" = "SKIP=already-released/3.0.0-mavericks.1" ] \
  || { echo "FAIL: the filter must drop ONLY drafts -- a published release alongside one still counts: got '$got'"; exit 1; }

got="$(raw "$(printf '%s\n' \
  "1.2.3-mavericks.1${TAB}false${TAB}| ingredient\tpinned |\n\nModernMavericks-State: ${D1}" \
  "4.0.0-mavericks.1${TAB}false${TAB}plain notes")" "$D1" 7.7.7-mavericks.1)"
[ "$got" = "SKIP=already-released/1.2.3-mavericks.1" ] \
  || { echo "FAIL: a TAB inside a body must not invent a record -- the old transform started a new record at any \"^[^\\t]+\\t\", so a body containing a tab attributed the digest to prose and left the real tag reading as digest-less; @tsv escapes it, and the split takes exactly the first two tabs: a tab inside a body moved the digest: got '$got'"; exit 1; }

# platform: `gh release list --json tagName,body` FAILS -- `body` is a `gh release view` field
#           -- and a failed list read as "no releases", which answers PUBLISH every night, in
#           every repo. @tsv is what makes a record exactly one line, which cases above rely on
#           being true of the real API. This is the one clause the offline cases above cannot
#           reach, so it is pinned directly here. Full-line comments are stripped first: the
#           script explains the trap it avoids, and the prose naming it must not read as the
#           trap itself.
code="$(sed 's/^[[:space:]]*#.*//' "$S")"
case "$code" in
  *"release list"*) echo "FAIL the fetch is back on gh release list, which has no body field"; exit 1 ;;
esac
case "$code" in
  *@tsv*) : ;;
  *) echo "FAIL the fetch no longer asks jq for @tsv, so a body can span records"; exit 1 ;;
esac

# platform: auth expiry, a rate limit, a 5xx, a network blip and a renamed repo all produce
#           empty gh output -- and empty output means PUBLISH, so a gh FAILURE IS A FAILURE,
#           never a decision. The seam is $MAVERICKS_GH, an explicit path, not a stub on PATH: a
#           stub on PATH is invisible at the call site and would shadow gh for anything else the
#           script ran.
printf '%s\n' '#!/bin/sh' 'echo "gh: HTTP 401: Bad credentials" >&2' 'exit 4' > "$w/gh-fails"
chmod +x "$w/gh-fails"
rc=0
out="$(MAVERICKS_GH="$w/gh-fails" sh "$S" --digest "$D1" --version 1.2.3-mavericks.1 2>"$w/e16")" || rc=$?
[ "$rc" != 0 ] || { echo "FAIL a failing gh exited 0"; exit 1; }
case "$out" in
  *PUBLISH*) echo "FAIL a failing gh answered PUBLISH: '$out'"; exit 1 ;;
  *SKIP*)    echo "FAIL a failing gh answered a SKIP: '$out'"; exit 1 ;;
esac
grep -q 'Bad credentials' "$w/e16" || { echo "FAIL gh's own error was swallowed"; exit 1; }

printf '%s\n' '#!/bin/sh' 'exit 0' > "$w/gh-empty"; chmod +x "$w/gh-empty"
got="$(MAVERICKS_GH="$w/gh-empty" sh "$S" --digest "$D1" --version 1.2.3-mavericks.1)"
[ "$got" = PUBLISH ] || { echo "FAIL: a fetch that SUCCEEDS with no output is a real answer though -- a repo with no releases yet: got '$got'"; exit 1; }

rc=0
out="$(MAVERICKS_RELEASES_RAW="1.2.3-mavericks.1${TAB}maybe${TAB}notes" \
  sh "$S" --digest "$D1" --version 1.2.3-mavericks.1 2>"$w/e18")" || rc=$?
[ "$rc" != 0 ] || { echo "FAIL: a raw record whose draft flag is neither true nor false means the API shape moved under us -- guessing would either count a draft or drop a release, so it must refuse to decide: a malformed draft flag exited 0"; exit 1; }
case "$out" in *PUBLISH*) echo "FAIL a malformed draft flag answered PUBLISH"; exit 1;; esac

rc=0
out="$(MAVERICKS_RELEASES_RAW="${TAB}false${TAB}ModernMavericks-State: ${D1}" \
  sh "$S" --digest "$D1" --version 1.2.3-mavericks.1 2>"$w/e19")" || rc=$?
[ "$rc" != 0 ] || { echo "FAIL: AN EMPTY TAG IS A SHAPE CHANGE TOO, and the dangerous one -- @tsv renders a null or RENAMED field as the empty string, so .tag_name going away empties the tag on EVERY record, and dropping those records answers PUBLISH in every repo every night (exactly the failure the body field already caused once, in the one field that had no shape guard): a record with no tag exited 0"; exit 1; }
case "$out" in *PUBLISH*) echo "FAIL a record with no tag answered PUBLISH"; exit 1;; esac
grep -q 'shape changed' "$w/e19" || { echo "FAIL the no-tag refusal does not say what went wrong"; exit 1; }

got="$(raw "1.2.3-mavericks.1${TAB}false${TAB}ModernMavericks-State: v0:stale\n\nnotes\n\nModernMavericks-State: ${D1}" \
  "$D1" 9.9.9-mavericks.9)"
[ "$got" = "SKIP=already-released/1.2.3-mavericks.1" ] \
  || { echo "FAIL: THE WEDGE, removed -- an unreadable marker ABOVE a valid one in the same body must not decide; first-marker-wins made this read as unreadable, so release-needed.sh refused to publish a state that was demonstrably already released two lines further down, a silent failure to release: an unreadable marker above a valid one wedged the lookup: got '$got'"; exit 1; }
got="$(raw "1.2.3-mavericks.1${TAB}false${TAB}ModernMavericks-State: v0:a\n\nModernMavericks-State: v0:b" \
  "$D1" 9.9.9-mavericks.9)"
[ "$got" = "SKIP=unreadable-marker/1.2.3-mavericks.1" ] \
  || { echo "FAIL: with no readable marker anywhere it must still block -- \"prefer readable\" must not become \"ignore unreadable\": two unreadable markers stopped blocking: got '$got'"; exit 1; }

# spec: scripts/release-needed.sh -- THROUGH REAL jq, WITH THE SCRIPT'S OWN FILTER, so the raw
#       shape the cases above inject is the shape the API actually produces. Skipped where jq is
#       absent (10.9 has none); CI has it.
if command -v jq >/dev/null 2>&1; then
  filter="$(sed -n "s/^ *--jq '\(.*\)'.*/\1/p" "$S")"
  [ -n "$filter" ] || { echo "FAIL could not read the fetch's jq filter out of the script"; exit 1; }

  cat > "$w/rel.json" <<JSON
[{"tag_name":"1.2.3-mavericks.1","draft":false,"body":"## Notes\n\n| a\tb |\n\nModernMavericks-State: $D1\n"},
 {"tag_name":"1.2.3-mavericks.2","draft":true,"body":"ModernMavericks-State: $D2"},
 {"tag_name":"1.2.3-mavericks.0","draft":false,"body":null}]
JSON
  RAWJ="$(jq -r "$filter" "$w/rel.json")"
  got="$(MAVERICKS_RELEASES_RAW="$RAWJ" sh "$S" --digest "$D1" --version 9.9.9-mavericks.9 2>/dev/null)"
  [ "$got" = "SKIP=already-released/1.2.3-mavericks.1" ] \
    || { echo "FAIL real jq, real filter: got '$got'"; exit 1; }
  got="$(MAVERICKS_RELEASES_RAW="$RAWJ" sh "$S" --digest "$D2" --version 9.9.9-mavericks.9 2>/dev/null)"
  [ "$got" = PUBLISH ] || { echo "FAIL real jq: the draft's digest counted: got '$got'"; exit 1; }

  # platform: a RENAMED tag field is how the empty-tag case above breaks in practice: jq yields
  #           null, @tsv renders it empty, and every release disappears.
  cat > "$w/renamed.json" <<JSON
[{"tagName":"1.2.3-mavericks.1","draft":false,"body":"ModernMavericks-State: $D1"}]
JSON
  RAWR="$(jq -r "$filter" "$w/renamed.json")"
  rc=0
  out="$(MAVERICKS_RELEASES_RAW="$RAWR" sh "$S" --digest "$D1" --version 1.2.3-mavericks.1 2>/dev/null)" || rc=$?
  [ "$rc" != 0 ] || { echo "FAIL real jq, renamed tag field: exited 0"; exit 1; }
  case "$out" in *PUBLISH*) echo "FAIL real jq, renamed tag field: answered PUBLISH"; exit 1;; esac

  # platform: @tsv escapes `\` as well as newlines, so prose containing a literal backslash-n
  #           before the key must not FORGE a marker -- the tempting one-line unescape (gsub of
  #           \n alone) would turn this into a real line break and read a digest out of a
  #           sentence.
  cat > "$w/forge.json" <<JSON
[{"tag_name":"9.9.9-mavericks.1","draft":false,"body":"prose saying \\\\nModernMavericks-State: $D1 inline"}]
JSON
  RAWF="$(jq -r "$filter" "$w/forge.json")"
  got="$(MAVERICKS_RELEASES_RAW="$RAWF" sh "$S" --digest "$D1" --version 9.9.9-mavericks.9 2>/dev/null)"
  [ "$got" = PUBLISH ] || { echo "FAIL prose forged a state marker: got '$got'"; exit 1; }
else
  echo "note: jq absent, skipping the real-jq cases"
fi

echo "PASS: release-needed"
