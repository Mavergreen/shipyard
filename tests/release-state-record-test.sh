#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "A release is a declared state, not an event" -- release-state-record.sh is the
#       only writer of a release body outside the publish path, deliberately narrow: it appends
#       one line and touches nothing else, is idempotent so the nightly backstop can run forever,
#       and a conflicting digest stops it rather than overwriting.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/release-state-record.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/record-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
D1='v1:sha256:8c5fc85c689b60ccc9a3ed0120fa949e2bd9c0f9a121ac572fa11ba148312be7'
D2='v1:sha256:405b7fdda86a03f4ef636aceb3c7c819fe5d93208118cd365a0b962cb37c8004'

printf '## What changed\n\n- a thing\n' > "$w/body1"
out="$(sh "$S" --tag 1.2.3-mavericks.1 --digest "$D1" --body-file "$w/body1" --out "$w/new1")"
[ "$out" = "BACKFILLED=1.2.3-mavericks.1" ] || { echo "FAIL append: got '$out'"; exit 1; }
grep -q '^## What changed$' "$w/new1" || { echo "FAIL: appending must preserve every existing byte of the notes users read -- lost the heading"; exit 1; }
grep -q '^- a thing$' "$w/new1" || { echo "FAIL append lost a bullet"; exit 1; }
grep -q "^Mavergreen-State: $D1\$" "$w/new1" || { echo "FAIL append did not add the line"; exit 1; }

out="$(sh "$S" --tag 1.2.3-mavericks.1 --digest "$D1" --body-file "$w/new1" --out "$w/new2")"
[ "$out" = "UNCHANGED=1.2.3-mavericks.1" ] || { echo "FAIL: the same digest again must be idempotent and say so: got '$out'"; exit 1; }
cmp -s "$w/new1" "$w/new2" || { echo "FAIL idempotent run rewrote the body"; exit 1; }

rc=0
sh "$S" --tag 1.2.3-mavericks.1 --digest "$D2" --body-file "$w/new1" --out "$w/new3" >"$w/o3" 2>&1 || rc=$?
[ "$rc" = 3 ] || { echo "FAIL: a DIFFERENT digest already recorded must exit 3 and write nothing -- two declared states claiming one release is a question for a human: got $rc"; exit 1; }
[ ! -f "$w/new3" ] || { echo "FAIL conflict still wrote an output"; exit 1; }
grep -q "$D1" "$w/o3" || { echo "FAIL conflict message does not show the digest already recorded"; exit 1; }

: > "$w/body4"
out="$(sh "$S" --tag 9.9.9-mavericks.1 --digest "$D1" --body-file "$w/body4" --out "$w/new4")"
[ "$out" = "BACKFILLED=9.9.9-mavericks.1" ] || { echo "FAIL: an empty body must be fine -- a release with no notes still gets its marker: got '$out'"; exit 1; }
[ "$(head -1 "$w/new4")" = "Mavergreen-State: $D1" ] \
  || { echo "FAIL empty body got a leading blank line: $(head -2 "$w/new4")"; exit 1; }

rc=0; sh "$S" --tag t --body-file "$w/body4" --out "$w/x" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL missing --digest should exit 2, got $rc"; exit 1; }
rc=0; sh "$S" --digest "$D1" --body-file "$w/body4" --out "$w/x" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL missing --tag should exit 2, got $rc"; exit 1; }
rc=0; sh "$S" --tag t --digest nope --body-file "$w/body4" --out "$w/x" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL malformed digest should exit 2, got $rc"; exit 1; }
rc=0; sh "$S" --tag t --digest v1:sha256:ZZ --body-file "$w/body4" --out "$w/x" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: a valid prefix with a non-hex tail must also be rejected (distinct from the malformed-prefix case above): non-hex digest tail should exit 2, got $rc"; exit 1; }
rc=0; sh "$S" --tag t --digest v1:sha256: --body-file "$w/body4" --out "$w/x" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: a valid prefix with an empty tail must also be rejected: empty digest tail should exit 2, got $rc"; exit 1; }
rc=0; sh "$S" --tag t --digest "$D1" --body-file "$w/body4" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: --body-file without --out would mean \"read a file, write a RELEASE\", which no caller wants -- should exit 2, got $rc"; exit 1; }

# spec: SKILL.md "A release is a declared state, not an event" -- release-state-record.sh's
#       normal path marks a notes file IN PLACE before packaging, which a product's release.yml
#       calls before sign_and_appcast.sh; the appcast's <description> and the Release body are
#       both produced from this one notes file, so marking it before packaging is what keeps
#       them in agreement. It takes no --tag: the notes file is not a release yet, and inventing
#       a tag argument for it would invite passing the wrong one.
printf '## 1.2.3-mavericks.1\n\n### What changed\n\n- a thing\n' > "$w/notes"
out="$(sh "$S" --notes-file "$w/notes" --digest "$D1")"
[ "$out" = "RECORDED=$w/notes" ] || { echo "FAIL notes-file: got '$out'"; exit 1; }
grep -q '^### What changed$' "$w/notes" || { echo "FAIL notes-file lost a section"; exit 1; }
[ "$(tail -1 "$w/notes")" = "Mavergreen-State: $D1" ] \
  || { echo "FAIL marker is not the last line: $(tail -1 "$w/notes")"; exit 1; }

cp "$w/notes" "$w/notes.first"
out="$(sh "$S" --notes-file "$w/notes" --digest "$D1")"
[ "$out" = "UNCHANGED=$w/notes" ] || { echo "FAIL: running twice in place must leave one marker and report UNCHANGED: got '$out'"; exit 1; }
cmp -s "$w/notes" "$w/notes.first" || { echo "FAIL second run rewrote the notes"; exit 1; }
[ "$(grep -c 'Mavergreen-State:' "$w/notes")" = 1 ] || { echo "FAIL two markers"; exit 1; }

cp "$w/notes" "$w/notes.before"
rc=0; sh "$S" --notes-file "$w/notes" --digest "$D2" >"$w/o8" 2>&1 || rc=$?
[ "$rc" = 3 ] || { echo "FAIL: a different digest in place must exit 3 and write nothing, leaving the file exactly as it was: got $rc"; exit 1; }
cmp -s "$w/notes" "$w/notes.before" || { echo "FAIL conflict modified the notes file"; exit 1; }

rc=0; sh "$S" --notes-file "$w/notes" --tag t --digest "$D1" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: --notes-file and --tag are different targets, so asking for both must be a usage error, not a guess: should exit 2, got $rc"; exit 1; }

rc=0; sh "$S" --digest "$D1" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: neither target named must also be a usage error: should exit 2, got $rc"; exit 1; }

rc=0; sh "$S" --notes-file "$w/nope.md" --digest "$D1" >"$w/o11" 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: a missing notes file is an error, never a file this script creates -- the notes are a build product, and a missing one means the caller ran this before generating them: should exit 2, got $rc"; exit 1; }
grep -q 'nope.md' "$w/o11" || { echo "FAIL missing-notes error does not name the file"; exit 1; }

printf '## 1.2.3-mavericks.1\n\n### What changed\n\n- a thing\n\n---\n\nRequires Mac OS X 10.9.5 or later.\n' > "$w/n12"
sh "$S" --notes-file "$w/n12" --digest "$D1" >/dev/null
[ "$(tail -1 "$w/n12")" = "Mavergreen-State: $D1" ] || { echo "FAIL marker not last"; exit 1; }
[ -z "$(tail -2 "$w/n12" | head -1)" ] \
  || { echo "FAIL: THE MARKER IS ITS OWN PARAGRAPH -- markdown joins consecutive lines, so a marker welded to the footer renders in a 10.9 user's Sparkle dialog as one run-on paragraph ending in a raw hash: no blank line before the marker: '$(tail -2 "$w/n12" | head -1)'"; exit 1; }
grep -q '^Requires Mac OS X 10.9.5 or later.$' "$w/n12" \
  || { echo "FAIL the footer line was altered"; exit 1; }

printf 'Requires Mac OS X 10.9.5 or later.' > "$w/n13"      # deliberately no trailing newline
sh "$S" --notes-file "$w/n13" --digest "$D1" >/dev/null
[ "$(tail -1 "$w/n13")" = "Mavergreen-State: $D1" ] || { echo "FAIL marker not last (no-EOL)"; exit 1; }
[ -z "$(tail -2 "$w/n13" | head -1)" ] \
  || { echo "FAIL: even when the notes file does NOT end with a newline, a guaranteed final newline must precede the separator, or it merely terminates the footer's last line and the marker fuses to it (gh --jq .body promises no trailing newline either, so a backfill can hand us this shape too) -- no blank line before the marker"; exit 1; }
[ "$(head -1 "$w/n13")" = 'Requires Mac OS X 10.9.5 or later.' ] \
  || { echo "FAIL the footer line lost its content: '$(head -1 "$w/n13")'"; exit 1; }

cp "$w/n13" "$w/n13.first"
sh "$S" --notes-file "$w/n13" --digest "$D1" >/dev/null
cmp -s "$w/n13" "$w/n13.first" || { echo "FAIL: the paragraph break must not accumulate -- a second run changed the file"; exit 1; }

# spec: SKILL.md "A release is a declared state, not an event" -- --replace-unreadable is the
#       escape release-needed.sh's SKIP=unreadable-marker/<tag> names. Without it that answer was
#       a dead end: release-needed.sh refuses to publish while a release records a marker it
#       cannot read, and a re-record hit "already records a DIFFERENT state" and exited 3 BECAUSE
#       a marker was present -- the very condition that blocked publishing -- and --digest
#       accepts only v1:sha256:<hex>, so a new-format digest could not be offered over an old one
#       either. The only recovery left was hand-editing a release body.
RN="$here/../scripts/release-needed.sh"
TAB="$(printf '\t')"

printf '## 9.9.9-mavericks.2\n\n- a thing\n\nMavergreen-State: v0:sha256:deadbeef\n' > "$w/u15"
rc=0
out="$(sh "$S" --tag 9.9.9-mavericks.2 --digest "$D1" --replace-unreadable \
        --body-file "$w/u15" --out "$w/n15" 2>"$w/o15")" || rc=$?
[ "$rc" = 0 ] || { echo "FAIL --replace-unreadable still refused (rc=$rc): $(cat "$w/o15")"; exit 1; }
[ "$out" = "REPLACED=9.9.9-mavericks.2" ] || { echo "FAIL replace-unreadable: got '$out'"; exit 1; }
grep -q "^Mavergreen-State: $D1\$" "$w/n15" || { echo "FAIL the new digest was not written"; exit 1; }
if grep -q 'v0:sha256:deadbeef' "$w/n15"; then echo "FAIL the unreadable marker survived"; exit 1; fi
[ "$(grep -c 'Mavergreen-State:' "$w/n15")" = 1 ] \
  || { echo "FAIL: it must replace exactly the unreadable marker, in place, preserving every other byte -- left more than one marker"; exit 1; }
grep -q '^- a thing$' "$w/n15" || { echo "FAIL replacing lost a bullet"; exit 1; }
grep -q '^## 9.9.9-mavericks.2$' "$w/n15" || { echo "FAIL replacing lost the heading"; exit 1; }

# spec: scripts/release-needed.sh -- the escape must actually escape, so the blocked answer is
#       reproduced here and the rewritten body is what unblocks it. Asserting the write without
#       asserting the unblocking is how a dead-end instruction ships in the first place.
before="$(MAVERICKS_RELEASES="9.9.9-mavericks.2${TAB}v0:sha256:deadbeef" \
  sh "$RN" --digest "$D1" --version 9.9.9-mavericks.3 2>/dev/null)"
[ "$before" = "SKIP=unreadable-marker/9.9.9-mavericks.2" ] \
  || { echo "FAIL the block this escapes is not reproducible: got '$before'"; exit 1; }
dg="$(sed -n 's/^Mavergreen-State:[[:space:]]*//p' "$w/n15" | head -1)"
after="$(MAVERICKS_RELEASES="9.9.9-mavericks.2${TAB}${dg}" \
  sh "$RN" --digest "$D1" --version 9.9.9-mavericks.3 2>/dev/null)"
[ "$after" = "SKIP=already-released/9.9.9-mavericks.2" ] \
  || { echo "FAIL after replacing, the state still does not read as released: got '$after'"; exit 1; }

printf 'notes\n\nMavergreen-State: %s\n' "$D1" > "$w/u17"
rc=0
sh "$S" --tag t --digest "$D2" --replace-unreadable --body-file "$w/u17" --out "$w/n17" >"$w/o17" 2>&1 || rc=$?
[ "$rc" = 3 ] || { echo "FAIL: a READABLE digest that merely differs must STILL exit 3, flag or no flag -- \"replace whatever is there\" would make every recorded digest overwritable by any caller: --replace-unreadable overwrote a readable digest (rc=$rc)"; exit 1; }
[ ! -f "$w/n17" ] || { echo "FAIL a refused replace still wrote an output"; exit 1; }
grep -q "$D1" "$w/o17" || { echo "FAIL the refusal does not show what is recorded"; exit 1; }

out="$(sh "$S" --tag t --digest "$D1" --replace-unreadable --body-file "$w/u17" --out "$w/n18")"
[ "$out" = "UNCHANGED=t" ] || { echo "FAIL: the flag is not a licence to skip the other paths -- --replace-unreadable broke idempotence: got '$out'"; exit 1; }
printf 'just notes\n' > "$w/u18"
out="$(sh "$S" --tag t --digest "$D1" --replace-unreadable --body-file "$w/u18" --out "$w/n18b")"
[ "$out" = "BACKFILLED=t" ] || { echo "FAIL --replace-unreadable broke the plain append: got '$out'"; exit 1; }

printf 'notes\n\nMavergreen-State: garbage\n' > "$w/u19"
out="$(sh "$S" --notes-file "$w/u19" --digest "$D1" --replace-unreadable)"
[ "$out" = "REPLACED=$w/u19" ] || { echo "FAIL: it must work on a notes file too, and say REPLACED rather than RECORDED (\"recorded\" would imply nothing was there): got '$out'"; exit 1; }
[ "$(tail -1 "$w/u19")" = "Mavergreen-State: $D1" ] \
  || { echo "FAIL notes-file replace, marker not last"; exit 1; }

printf 'Mavergreen-State: v0:old\n\n## notes\n\n- tail bullet\n' > "$w/u20"
sh "$S" --tag t --digest "$D1" --replace-unreadable --body-file "$w/u20" --out "$w/n20" >/dev/null
[ "$(head -1 "$w/n20")" = "Mavergreen-State: $D1" ] \
  || { echo "FAIL: a marker NOT at the end must be rewritten WHERE IT STANDS, not stripped and re-appended, since the notes are what users read and moving a line is a change to them -- the marker moved: '$(head -1 "$w/n20")'"; exit 1; }
[ "$(tail -1 "$w/n20")" = "- tail bullet" ] || { echo "FAIL the body's own tail moved"; exit 1; }

printf 'Mavergreen-State: v0:a\n\nnotes\n\nMavergreen-State: v0:b\n' > "$w/u21"
sh "$S" --tag t --digest "$D1" --replace-unreadable --body-file "$w/u21" --out "$w/n21" >/dev/null
[ "$(grep -c 'Mavergreen-State:' "$w/n21")" = 1 ] \
  || { echo "FAIL: TWO unreadable markers must leave ONE readable one -- one marker per body is the invariant, and a stale unreadable line is litter in notes users read: did not collapse to one"; exit 1; }
grep -q "^Mavergreen-State: $D1\$" "$w/n21" || { echo "FAIL the surviving marker is not the new one"; exit 1; }

# spec: scripts/release-needed.sh -- THE FIRST READABLE MARKER WINS, not simply the first. An
#       unreadable line ABOVE a valid digest used to decide, which made this body "a conflicting
#       record" to this script and (worse) an unreadable one to release-needed.sh -- so a state
#       demonstrably already released, two lines further down, blocked publishing forever.
printf 'Mavergreen-State: v0:stale\n\nnotes\n\nMavergreen-State: %s\n' "$D1" > "$w/u22"
rc=0
out="$(sh "$S" --tag t --digest "$D1" --body-file "$w/u22" --out "$w/n22" 2>/dev/null)" || rc=$?
[ "$rc" = 0 ] \
  || { echo "FAIL a readable marker below an unreadable one was not seen (rc=$rc)"; exit 1; }
[ "$out" = "UNCHANGED=t" ] \
  || { echo "FAIL a readable marker below an unreadable one was ignored: got '$out'"; exit 1; }

echo "PASS: release-state-record"
