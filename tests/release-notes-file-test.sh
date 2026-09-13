#!/bin/sh
# spec: release-notes-file.sh is a back-compat DELEGATING wrapper around release-notes.sh (the
#       generator); what a generated body actually CONTAINS is release-notes.sh's contract,
#       tested exhaustively in tests/release-notes-test.sh -- duplicating that here would only
#       let the two drift, so this file tests only the wrapper's own narrow job.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/release-notes-file.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/release-notes-file-t.XXXXXX")"; trap 'rm -rf "$w"' EXIT
cd "$w"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p release-notes
printf 'x\n' > UPSTREAM_VERSION
git add -A; git commit -qm base
export MAVERICKS_ROOT="$w"

# spec: release-notes-file.sh -- the calls below use a SELF-upstream tag (TAG == FULL, no
#       "-mavericks." axis) so as to sidestep the generator's hook/tag/ingredient machinery
#       entirely, which is exactly right for a test of the WRAPPER's own plumbing rather than
#       the generator's.
sh "$S" 20260911.1 20260911.1 Porthole >"$w/out.log" 2>"$w/err.log"
[ "$(wc -l < "$w/out.log" | tr -d ' ')" = 1 ] \
  || { echo "FAIL stdout: expected exactly one line"; cat -A "$w/out.log"; exit 1; }
p="$(cat "$w/out.log")"
[ -s "$p" ] || { echo "FAIL stdout: '$p' is not a non-empty file"; exit 1; }
grep -q 'release-notes: wrote' "$w/err.log" \
  || { echo "FAIL stdout: generator's progress line never appeared (on stderr or anywhere)"; exit 1; }
grep -q 'release-notes: wrote' "$w/out.log" \
  && { echo "FAIL: the generator's own progress line must land on the wrapper's STDERR, never mixed into what a caller captures as \$NOTES -- it leaked onto the wrapper's stdout"; exit 1; }
rm -f "$p"

printf '## Hand-written\n\nProse that must survive.\n' > release-notes/20260911.2.md
git add -A; git commit -qm notes
before="$(git hash-object release-notes/20260911.2.md)"
p="$(sh "$S" 20260911.2 20260911.2 Porthole 2>/dev/null)"
case "$p" in */release-notes/*) echo "FAIL: a committed note must be returned as a TEMP copy, never the committed path: $p"; exit 1;; esac
grep -q 'Hand-written' "$p" || { echo "FAIL prose not preserved"; cat "$p"; exit 1; }
grep -q 'Prose that must survive' "$p" || { echo "FAIL prose not preserved"; cat "$p"; exit 1; }
[ "$before" = "$(git hash-object release-notes/20260911.2.md)" ] \
  || { echo "FAIL: a committed release-notes/<TAG>.md must never be edited in place"; exit 1; }
rm -f "$p"

p="$(sh "$S" 20260911.3 20260911.3 'Mavericks Go' 2>/dev/null)"
grep -q '^## Go 20260911.3$' "$p" || { echo "FAIL: the family's older 'Mavericks X' prose phrasing must reduce to the generator's bare noun -- 'Mavericks Go' should strip to 'Go'"; cat "$p"; exit 1; }
rm -f "$p"
p="$(sh "$S" 20260911.4 20260911.4 'OpenSSH for Mavericks' 2>/dev/null)"
grep -q '^## OpenSSH 20260911.4$' "$p" \
  || { echo "FAIL: the family's older 'X for Mavericks' prose phrasing must reduce to the generator's bare noun -- 'OpenSSH for Mavericks' should strip to 'OpenSSH'"; cat "$p"; exit 1; }
rm -f "$p"

p="$(sh "$S" 20260911.5 20260911.5 2>/dev/null)"
grep -q '^## ModernMavericks 20260911.5$' "$p" || { echo "FAIL: omitted PRODUCT must keep the documented default"; cat "$p"; exit 1; }
rm -f "$p"

echo "PASS: release-notes-file (shared)"

w2="$(mktemp -d "${TMPDIR:-/tmp}/rnf-delegate.XXXXXX")"
mkdir -p "$w2/build"
( cd "$w2" && git init -q -b main . && git config user.email t@example.com && git config user.name tester \
   && printf '9.9p2\n' > UPSTREAM_VERSION \
   && printf '#!/bin/sh\nprintf "https://example.com/%%s\\n" "$1"\n' > build/upstream-release-notes-url.sh \
   && git add -A && git commit -qm base && git tag 9.9p2-mavericks.1 )
p="$(cd "$w2" && MAVERICKS_ROOT="$w2" sh "$here/../scripts/release-notes-file.sh" 9.9p2-mavericks.1 9.9p2-mavericks.1 OpenSSH)"
[ -s "$p" ] || { echo "FAIL delegate: empty file at '$p'"; exit 1; }
sh "$here/../scripts/check-release-notes.sh" "$p" 9.9p2-mavericks.1 >/dev/null \
  || { echo "FAIL: the wrapper now delegates to release-notes.sh, so a repo that has not migrated must still get the family shape: wrapper output is not the family shape"; cat "$p"; exit 1; }
rm -rf "$w2"

lw="$(mktemp -d "${TMPDIR:-/tmp}/rnf-line.XXXXXX")"
( cd "$lw" && git init -q -b main . && git config user.email t@example.com && git config user.name tester \
    && mkdir -p build && printf '1.26.7\n' > UPSTREAM_VERSION \
    && printf '#!/bin/sh\nprintf "https://go.dev/doc/devel/release#go%%s\\n" "$1"\n' > build/upstream-release-notes-url.sh \
    && git add -A && git commit -qm base \
    && git tag 1.26.5-mavericks.1 && git tag 1.27.0-mavericks.1 )

p="$(cd "$lw" && MAVERICKS_ROOT="$lw" GITHUB_SERVER_URL=https://github.com \
    GITHUB_REPOSITORY=ModernMavericks/mavericks-golang \
    sh "$here/../scripts/release-notes-file.sh" 1.26.7-mavericks.1 1.26.7-mavericks.1 Go 2>/dev/null)"
grep -q 'was 1.27.0' "$p" \
  || { echo "FAIL: MAVERICKS_NOTES_LINE forwards to the generator's --line, the wrapper's only call path -- unset must add no --line (today's behavior), so the baseline is the numerically highest tag across ALL lines (1.27.0)"; cat "$p"; exit 1; }
rm -f "$p"

p="$(cd "$lw" && MAVERICKS_ROOT="$lw" MAVERICKS_NOTES_LINE=1.26 \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=ModernMavericks/mavericks-golang \
    sh "$here/../scripts/release-notes-file.sh" 1.26.7-mavericks.1 1.26.7-mavericks.1 Go 2>/dev/null)"
grep -q 'was 1.26.5' "$p" \
  || { echo "FAIL: MAVERICKS_NOTES_LINE=1.26 (a parallel-lines repo, golang: lines/126/) should scope the baseline to 1.26.5, not the numerically-highest tag across every line"; cat "$p"; exit 1; }
grep -q '1.27.0' "$p" \
  && { echo "FAIL line: must not pick the newer 1.27.0 line as baseline"; cat "$p"; exit 1; }
rm -f "$p"
rm -rf "$lw"

echo "PASS: release-notes-file (--line pass-through)"

# spec: release-notes-file.sh creates its temp file BEFORE calling the generator; with no trap,
#       a generator die() (any of the many fatal gaps release-notes.sh now enforces) left a
#       zero-byte temp file behind forever.
tw="$(mktemp -d "${TMPDIR:-/tmp}/rnf-trap.XXXXXX")"
nogit="$tw/nogit-root"; mkdir -p "$nogit"
if ( cd "$nogit" && MAVERICKS_ROOT="$nogit" TMPDIR="$tw" \
       sh "$here/../scripts/release-notes-file.sh" 9.9p2-mavericks.1 9.9p2-mavericks.1 OpenSSH \
     ) >/dev/null 2>"$tw/err.log"; then
  echo "FAIL trap: generator should have failed (MAVERICKS_ROOT is not a git repo)"; exit 1
fi
grep -qi 'shallow\|git' "$tw/err.log" || { echo "FAIL trap: unexpected failure cause"; cat "$tw/err.log"; exit 1; }
leaked="$(find "$tw" -maxdepth 1 -type f -name 'release-notes-file.*' | wc -l | tr -d ' ')"
[ "$leaked" = 0 ] \
  || { echo "FAIL trap: generator failure leaked a wrapper temp file"; find "$tw" -maxdepth 1 -type f; exit 1; }
rm -rf "$tw"

echo "PASS: release-notes-file (mktemp trap)"
