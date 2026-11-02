#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "Release notes" -- before this generator, notes were best-effort prose: every
#       generated section was appended with `|| true` and 2>/dev/null, so a broken hook, an
#       unfindable baseline or a shallow clone all produced a SHORTER body and a green run.
#       openssh never listed an ingredient; signal-desktop shipped a new upstream with no link;
#       swift-runtime's repackage failed at signing instead, for want of a committed file. This
#       generator is one shape for every product, and a fatal error for every gap it cannot fill.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/deviation_tree.sh"
S="$here/../scripts/release-notes.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/release-notes.XXXXXX")"; trap 'rm -rf "$work"' EXIT

mkrepo() {  # a product repo fixture: a git repo with a hook, a pin, and a repackage caller naming that pin. $1 = dir
  mkdir -p "$1/.mavergreen/hooks" "$1/.mavergreen/ingredients/libressl" "$1/.github/workflows" "$1/release-notes"
  ( cd "$1" && git init -q -b main . && git config user.email t@example.com && git config user.name tester )
  printf '3.8.2\n' > "$1/.mavergreen/ingredients/libressl/VERSION"
  cat > "$1/.github/workflows/repackage-on-ingredient-bump.yml" <<'YML'
on:
  push:
    branches: [main]
    paths:
      - .mavergreen/ingredients/libressl/VERSION
jobs:
  repackage:
    uses: Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
    with:
      own-upstream-paths: UPSTREAM_VERSION
YML
  printf '#!/bin/sh\nprintf "https://example.com/notes/%%s\\n" "$1"\n' > "$1/.mavergreen/hooks/upstream-release-notes-url"
  printf '9.9p2\n' > "$1/UPSTREAM_VERSION"
  cat > "$1/.github/renovate.json" <<'JSON'
{
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["/^.mavergreen/ingredients/libressl/VERSION$/"],
      "matchStrings": ["^(?<currentValue>\\S+)\\s*$"],
      "packageNameTemplate": "libressl/portable",
      "datasourceTemplate": "github-releases",
      "extractVersionTemplate": "^v(?<version>.+)$"
    }
  ]
}
JSON
  ( cd "$1" && git add -A && git commit -qm base )
}

gen() {  # $1 = repo, $2 = tag/version, rest = extra args
  r="$1"; v="$2"; shift 2
  ( cd "$r" && MAVERICKS_ROOT="$r" \
      GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=Mavergreen/mavericks-openssh \
      sh "$S" --tag "$v" --version "$v" \
      --product OpenSSH --min-os 10.9.5 --out "$r/OUT.md" "$@" )
}

# spec: scripts/release-notes.sh -- a new upstream must name the upstream, link its notes, and
#       say what it replaced.
r="$work/new"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 )
gen "$r" 9.9p2-mavericks.1 >/dev/null
grep -q '^## OpenSSH 9.9p2 for Mavericks (9.9p2-mavericks.1)$' "$r/OUT.md" \
  || { echo "FAIL new: title"; cat "$r/OUT.md"; exit 1; }
grep -q 'First release of OpenSSH 9.9p2' "$r/OUT.md" || { echo "FAIL new: first-release wording"; exit 1; }
grep -q 'https://example.com/notes/9.9p2' "$r/OUT.md" || { echo "FAIL new: upstream link"; exit 1; }
grep -q 'Requires Mac OS X 10.9.5 or later' "$r/OUT.md" || { echo "FAIL new: floor"; exit 1; }
sh "$here/../scripts/check-release-notes.sh" "$r/OUT.md" 9.9p2-mavericks.1 >/dev/null \
  || { echo "FAIL new: own output fails the shape check"; exit 1; }

# spec: scripts/release-notes.sh -- an ingredient repackage must name the pin that moved, and
#       the baseline it moved from.
r="$work/ing"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null
grep -q 'rebuilt because build ingredients moved' "$r/OUT.md" || { echo "FAIL ing: kind"; cat "$r/OUT.md"; exit 1; }
grep -q '3.8.2 -> 3.9.2' "$r/OUT.md" || { echo "FAIL ing: pin diff (the openssh pN bug)"; cat "$r/OUT.md"; exit 1; }
grep -q '3.8.2 -> 3.9.2 (\[release notes\](https://github.com/libressl/portable/releases/tag/v3.9.2))$' "$r/OUT.md" \
  || { echo "FAIL ing: the moved pin must link its change notes"; cat "$r/OUT.md"; exit 1; }

# spec: SKILL.md "Release notes" -- a moved pin with no link source and no declared reason cannot
#       ship: release-notes.sh's self-check is check-release-notes.sh, which refuses the bare bullet.
#       A KEY a manager owns but cannot link (here a ^v? template, which cannot say which tag exists)
#       is not this repo's diff to describe, so it is bare.
r="$work/bare"; mkrepo "$r"
cat > "$r/.github/renovate.json" <<'JSON'
{"customManagers": [{"customType": "regex", "managerFilePatterns": ["/^.mavergreen/ingredients/libressl/VERSION$/"],
  "matchStrings": ["VERSION=(?<currentValue>\\S+)"], "packageNameTemplate": "libressl/portable",
  "datasourceTemplate": "github-tags", "extractVersionTemplate": "^v?(?<version>.+)$"}]}
JSON
printf 'VERSION=3.8.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
( cd "$r" && git add -A && git commit -qm "no manager" && git tag 9.9p2-mavericks.1 )
printf 'VERSION=3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavericks.2 )
if out="$(gen "$r" 9.9p2-mavericks.2 2>&1)"; then echo "FAIL bare: a link-less moved pin must not ship"; cat "$r/OUT.md"; exit 1; fi
printf '%s\n' "$out" | grep -q 'libressl' || { echo "FAIL bare: the complaint must name the pin: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'deviations/unlinked/' || { echo "FAIL bare: the complaint must name the fix: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'bug in release-notes.sh' \
  && { echo "FAIL bare: a pin with no link source is this repo's to fix, not a generator bug: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'the fix is in this repo' \
  || { echo "FAIL bare: the generator must say where the fix goes: $out"; exit 1; }
deviation "$r" unlinked libressl .mavergreen/ingredients/libressl/VERSION:VERSION 'a fixture with no notes'
( cd "$r" && git add -A && git commit -qm declare )
gen "$r" 9.9p2-mavericks.2 >/dev/null || { echo "FAIL bare: a declared reason must let it ship"; exit 1; }
grep -q '3.8.2 -> 3.9.2 (no change notes: a fixture with no notes)$' "$r/OUT.md" \
  || { echo "FAIL bare: the declared reason must be in the bullet"; cat "$r/OUT.md"; exit 1; }
grep -q '9.9p2-mavericks.1\.\{0,\}9.9p2-mavericks.2' "$r/OUT.md" \
  || grep -q 'compare/9.9p2-mavericks.1' "$r/OUT.md" || { echo "FAIL ing: compare link"; exit 1; }
grep -q 'Upstream release notes' "$r/OUT.md" && { echo "FAIL ing: a repackage must not claim a new upstream"; exit 1; }

# spec: scripts/release-notes.sh -- a packaging-only release has no upstream change and no pin
#       moved.
r="$work/pkgonly"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 && echo x >> .mavergreen/hooks/upstream-release-notes-url \
    && git commit -qam "ci: unrelated" && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null
grep -q 'packaging changes only' "$r/OUT.md" || { echo "FAIL pkgonly: kind"; cat "$r/OUT.md"; exit 1; }
grep -q '### Build ingredients' "$r/OUT.md" && { echo "FAIL pkgonly: no pin moved, no section"; exit 1; }

# spec: scripts/release-notes.sh -- committed prose must be slotted in verbatim, never
#       rewritten.
r="$work/prose"; mkrepo "$r"
printf 'Hand-written paragraph.\n\n- a bullet a human wrote\n<!-- edited by a human -->\n' > "$r/release-notes/9.9p2-mavericks.1.md"
( cd "$r" && git add -A && git commit -qm notes && git tag 9.9p2-mavericks.1 )
gen "$r" 9.9p2-mavericks.1 >/dev/null
grep -q 'Hand-written paragraph.' "$r/OUT.md" || { echo "FAIL prose: not included"; exit 1; }
grep -q '^- a bullet a human wrote$' "$r/OUT.md" || { echo "FAIL prose: mangled"; exit 1; }
grep -q '^### What changed$' "$r/OUT.md" || { echo "FAIL prose: generated sections dropped"; exit 1; }

# spec: SKILL.md "Release notes" -- committed prose
#       publishes only once a human has added the mark, and readers never see the mark.
M='<!-- edited by a human -->'
hp() {  # $1 = case, $2 = printf format of release-notes/9.9p2-mavericks.1.md; leaves $r and $rc
  r="$work/hp-$1"; mkrepo "$r"
  printf "$2" > "$r/release-notes/9.9p2-mavericks.1.md"
  ( cd "$r" && git add -A && git commit -qm notes && git tag 9.9p2-mavericks.1 )
  rc=0; gen "$r" 9.9p2-mavericks.1 >/dev/null 2>"$r/ERR" || rc=$?
}
hp unmarked 'Some prose.\n'
[ "$rc" -ne 0 ] || { echo "FAIL unmarked prose is refused"; exit 1; }
[ ! -e "$r/OUT.md" ] || { echo "FAIL unmarked prose is refused: --out was written"; exit 1; }
grep -qF "$M" "$r/ERR" && grep -qF 'release-notes/9.9p2-mavericks.1.md' "$r/ERR" \
  || { echo "FAIL unmarked prose is refused: the complaint names the file and the line"; cat "$r/ERR"; exit 1; }
hp marked "Some prose.\n$M\n"
[ "$rc" -eq 0 ] || { echo "FAIL marked prose ships"; cat "$r/ERR"; exit 1; }
grep -q 'edited by a human' "$r/OUT.md" && { echo "FAIL marked prose ships without the mark"; exit 1; }
grep -q '^Some prose\.$' "$r/OUT.md" || { echo "FAIL marked prose ships its prose"; exit 1; }
[ "$(awk 'f{print;n++} /^Some prose\.$/{f=1} n==2{exit}' "$r/OUT.md")" = "$(printf '\n### What changed')" ] \
  || { echo "FAIL marked prose ships: the mark's line leaves no trace"; cat "$r/OUT.md"; exit 1; }
hp crlf "Some prose.\n$M  \r\n"
[ "$rc" -eq 0 ] || { echo "FAIL mark with CR or trailing spaces counts"; cat "$r/ERR"; exit 1; }
grep -q 'edited by a human' "$r/OUT.md" && { echo "FAIL mark with CR or trailing spaces is stripped"; exit 1; }
hp indented "Some prose.\n    $M\n"
[ "$rc" -ne 0 ] || { echo "FAIL indented mark does not count"; exit 1; }
hp nearmiss 'Some prose.\n<!-- Edited by a human -->\n'
[ "$rc" -ne 0 ] || { echo "FAIL near-miss mark is refused"; exit 1; }
grep -qF "$M" "$r/ERR" || { echo "FAIL near-miss mark is refused: the complaint prints the exact line"; exit 1; }
hp markonly "$M\n"
[ "$rc" -eq 0 ] || { echo "FAIL mark-only file inserts nothing"; cat "$r/ERR"; exit 1; }
r1="$r"; r="$work/hp-none"; mkrepo "$r"; ( cd "$r" && git tag 9.9p2-mavericks.1 ); gen "$r" 9.9p2-mavericks.1 >/dev/null
[ "$(cat "$r1/OUT.md")" = "$(cat "$r/OUT.md")" ] || { echo "FAIL mark-only file inserts nothing: body differs from no prose"; diff "$r/OUT.md" "$r1/OUT.md"; exit 1; }
hp twice "$M\nSome prose.\n$M\n"
[ "$rc" -eq 0 ] || { echo "FAIL every mark line is stripped"; cat "$r/ERR"; exit 1; }
grep -q 'edited by a human' "$r/OUT.md" && { echo "FAIL every mark line is stripped"; exit 1; }

# spec: scripts/release-notes.sh -- self-upstream has no -mavericks axis, so no upstream claim
#       and a plain title.
r="$work/self"; mkrepo "$r"; rm "$r/.mavergreen/hooks/upstream-release-notes-url"
deviation "$r" upstream-notes self '*' 'this repo is its own upstream.'
( cd "$r" && git add -A && git commit -qm self && git tag 20260802.5 )
( cd "$r" && MAVERICKS_ROOT="$r" sh "$S" --tag 20260802.6 --version 20260802.6 \
    --product Porthole --out "$r/OUT.md" ) >/dev/null
grep -q '^## Porthole 20260802.6$' "$r/OUT.md" || { echo "FAIL self: title"; cat "$r/OUT.md"; exit 1; }
grep -q 'for Mavericks (' "$r/OUT.md" && { echo "FAIL self: port-shaped title"; exit 1; }

# spec: Porthole/shipyard/magic-trackpad2 have no -mavericks axis, so SELF_UPSTREAM is decided
#       from VER alone; that must not also mean "never gets a baseline" -- self-upstream also gets
#       the same compare-link footer everyone else gets. gen() hard-codes --product/--min-os but
#       appends "$@" after them, and release-notes.sh's argument loop lets a later flag win, so
#       this overrides both to exercise the porthole (YYYYMMDD.N) tag shape through the shared
#       fixture.
r="$work/selfglob"; mkrepo "$r"
( cd "$r" && git tag 20260802.4 && git tag 20260802.5 )
gen "$r" 20260802.6 --product Porthole --min-os 10.9 >/dev/null
grep -q '^## Porthole 20260802.6$' "$r/OUT.md" \
  || { echo "FAIL selfglob: title"; cat "$r/OUT.md"; exit 1; }
grep -q '^- Repackage of Porthole 20260802; packaging changes only\.$' "$r/OUT.md" \
  || { echo "FAIL selfglob: what-changed"; cat "$r/OUT.md"; exit 1; }
grep -q '^\[All changes since 20260802\.5\](.*compare/20260802\.5\.\.\.20260802\.6)$' "$r/OUT.md" \
  || { echo "FAIL selfglob: compare link missing"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh's SELF_GLOB derivation -- the date-shaped case above alone
#       leaves the v-shaped branch (shipyard/magic-trackpad2) uncovered: deleting the v[0-9]*
#       case left the whole suite green until this was added.
r="$work/selfvglob"; mkrepo "$r"
( cd "$r" && git tag v0.5.1 && git tag v0.5.2 )
gen "$r" v0.5.3 --product MagicTrackpad2 --min-os 10.9 >/dev/null
grep -q '^## MagicTrackpad2 v0.5.3$' "$r/OUT.md" \
  || { echo "FAIL selfvglob: title"; cat "$r/OUT.md"; exit 1; }
grep -q '^- New release of MagicTrackpad2 v0.5.3 (was v0.5.2)\.$' "$r/OUT.md" \
  || { echo "FAIL selfvglob: what-changed"; cat "$r/OUT.md"; exit 1; }
grep -q '^\[All changes since v0\.5\.2\](.*compare/v0\.5\.2\.\.\.v0\.5\.3)$' "$r/OUT.md" \
  || { echo "FAIL selfvglob: compare link missing"; cat "$r/OUT.md"; exit 1; }

r="$work/badhook"; mkrepo "$r"
printf '#!/bin/sh\nexit 1\n' > "$r/.mavergreen/hooks/upstream-release-notes-url"
( cd "$r" && git commit -qam badhook && git tag 9.9p2-mavericks.1 )
if gen "$r" 9.9p2-mavericks.1 >/dev/null 2>&1; then echo "FAIL badhook: should be fatal"; exit 1; fi
out="$(gen "$r" 9.9p2-mavericks.1 2>&1 || true)"
printf '%s\n' "$out" | grep -qi 'upstream' || { echo "FAIL badhook: cause not named: $out"; exit 1; }

r="$work/nohook"; mkrepo "$r"; rm "$r/.mavergreen/hooks/upstream-release-notes-url"
( cd "$r" && git add -A && git commit -qm nohook && git tag 9.9p2-mavericks.1 )
if gen "$r" 9.9p2-mavericks.1 >/dev/null 2>&1; then echo "FAIL: a new upstream with no hook and no declared reason must be fatal"; exit 1; fi

# spec: scripts/release-notes.sh -- but a declared upstream-notes deviation is the sanctioned way to have none.
deviation "$r" upstream-notes none '*' 'upstream publishes none.'
( cd "$r" && git add -A && git commit -qm declare )
gen "$r" 9.9p2-mavericks.1 >/dev/null || { echo "FAIL nohook+declared: should pass"; exit 1; }

# spec: scripts/release-notes.sh -- whether this repo owns an upstream-notes hook and whether
#       this RELEASE is even due an upstream link are independent questions, and the second is
#       answerable from the tags alone. Resolving the hook first conflated them: every hookless
#       repo reported "new
#       upstream" regardless of its tags, so the fleet preview found 1password's -mavericks.2,
#       swift-toolchain's -mavericks.4 and container-tools' -mavericks.23 -- all of them the Nth
#       repackage of an upstream already shipped N-1 times -- classified as brand-new upstreams.
#       That surfaced two ways: without a declared reason, a FALSE REFUSAL (a legitimate
#       repackage cannot be published at all, demanding a hook for an upstream link this release
#       was never owed -- 1password, swift-toolchain); with a declared reason, WORSE -- a green
#       run whose body asserts "New upstream: X" over a release that changed no upstream at all,
#       a false claim in the GitHub Release and the Sparkle dialog at exit 0 (container-tools).
#       The existing nohook cases above cannot catch either: both publish -mavericks.1, where "no
#       other tag of this upstream exists" makes new-upstream the correct answer and the ordering
#       unobservable. A repo with NO hook can still be publishing a repackage, and a repackage is
#       due no link.
r="$work/nohook-repack"; mkrepo "$r"; rm "$r/.mavergreen/hooks/upstream-release-notes-url"
( cd "$r" && git add -A && git commit -qm nohook && git tag 9.9p2-mavericks.1 \
    && echo x >> README.md && git add -A && git commit -qm "ci: unrelated" && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null \
  || { echo "FAIL nohook-repack: a repackage is due no upstream link, so a missing hook must not block it"; exit 1; }
grep -q 'Repackage of upstream OpenSSH 9.9p2' "$r/OUT.md" \
  || { echo "FAIL nohook-repack: kind"; cat "$r/OUT.md"; exit 1; }
grep -q 'New upstream' "$r/OUT.md" \
  && { echo "FAIL nohook-repack: claims a new upstream over an upstream already shipped"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- and the declared-reason variant must not turn that false
#       claim into a GREEN one.
deviation "$r" upstream-notes none '*' 'upstream publishes none.'
( cd "$r" && git add -A && git commit -qm declare )
gen "$r" 9.9p2-mavericks.2 >/dev/null || { echo "FAIL nohook-repack+declared: should pass"; exit 1; }
grep -q 'Repackage of upstream OpenSSH 9.9p2' "$r/OUT.md" \
  || { echo "FAIL nohook-repack+declared: kind"; cat "$r/OUT.md"; exit 1; }
grep -q 'New upstream' "$r/OUT.md" \
  && { echo "FAIL nohook-repack+declared: a declared reason must not license a false new-upstream claim"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/upstream-notes.sh -- a shallow clone hides the tags, so the kind cannot be
#       decided, and this must be fatal. The assertion checks the MESSAGE, not just a nonzero
#       exit: with the shallow guard removed,
#       this fixture still exits 1 (via upstream-notes.sh's own shallow-clone bail, mapped to the
#       catch-all die), so "some die fired" is not enough to prove the shallow guard itself is
#       doing anything.
r="$work/shallow"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 )
sr="$work/shallow-clone"
git clone -q --depth 1 "file://$r" "$sr" 2>/dev/null || git clone -q --depth 1 "$r" "$sr"
if ( cd "$sr" && MAVERICKS_ROOT="$sr" sh "$S" --tag 9.9p2-mavericks.2 --version 9.9p2-mavericks.2 \
       --product OpenSSH --out "$sr/OUT.md" ) >/dev/null 2>&1; then
  echo "FAIL shallow: should be fatal (this is signal-desktop's silent-drop shape)"; exit 1
fi
shallow_out="$(cd "$sr" && MAVERICKS_ROOT="$sr" sh "$S" --tag 9.9p2-mavericks.2 --version 9.9p2-mavericks.2 \
       --product OpenSSH --out "$sr/OUT.md" 2>&1 || true)"
printf '%s\n' "$shallow_out" | grep -qi shallow \
  || { echo "FAIL shallow: cause not named as shallow: $shallow_out"; exit 1; }

# platform: a non-shallow checkout can still hide tags (git clone --no-tags) -- the shallow
#           guard above does not fire here at all -- so a repackage (-mavericks.2) must not be
#           silently read as a first release with no baseline.
r="$work/notags"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 )
nr="$work/notags-clone"
git clone -q --no-tags "$r" "$nr" 2>/dev/null
if ( cd "$nr" && MAVERICKS_ROOT="$nr" sh "$S" --tag 9.9p2-mavericks.2 --version 9.9p2-mavericks.2 \
       --product OpenSSH --out "$nr/OUT.md" ) >/dev/null 2>&1; then
  echo "FAIL notags: -mavericks.2 with no visible upstream tags should be fatal"; exit 1
fi
# spec: scripts/release-notes.sh -- but -mavericks.1 with no visible tags stays a legitimate
#       first release (or a not-yet-tagged dispatch-cut build): the plan accepts that false
#       negative rather than block every real first release.
if ! ( cd "$nr" && MAVERICKS_ROOT="$nr" GITHUB_SERVER_URL=https://github.com \
       GITHUB_REPOSITORY=Mavergreen/mavericks-openssh sh "$S" \
       --tag 9.9p2-mavericks.1 --version 9.9p2-mavericks.1 \
       --product OpenSSH --out "$nr/OUT.md" ) >/dev/null 2>&1; then
  echo "FAIL notags: -mavericks.1 with no visible upstream tags should still succeed"; exit 1
fi

# spec: scripts/previous-release-tag.sh takes a GLOB -- golang ships parallel lines; 1.26.7's
#       baseline must be 1.26.5 (same line), not 1.27.0 (a newer line that shipped in between) --
#       --line must scope the baseline to its own line, not the numerically-highest tag. Both
#       spellings of --line must work: the human-friendly "1.26" (the original bug: a bare prefix
#       matched nothing) and the already-a-glob "1.26.*".
r="$work/golang"; mkrepo "$r"
( cd "$r" && git tag 1.26.5-mavericks.1 && git tag 1.27.0-mavericks.1 )
for line in "1.26" "1.26.*"; do
  ( cd "$r" && GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=Mavergreen/mavericks-golang \
      MAVERICKS_ROOT="$r" sh "$S" --tag 1.26.7-mavericks.1 --version 1.26.7-mavericks.1 \
      --product Go --line "$line" --out "$r/OUT.md" ) >/dev/null \
    || { echo "FAIL golang ($line): should succeed"; exit 1; }
  grep -q 'was 1.26.5' "$r/OUT.md" \
    || { echo "FAIL golang ($line): baseline should be 1.26.5"; cat "$r/OUT.md"; exit 1; }
  grep -q '1.27.0' "$r/OUT.md" \
    && { echo "FAIL golang ($line): must not pick the newer 1.27.0 line as baseline"; cat "$r/OUT.md"; exit 1; }
done

# spec: the original openssh bug -- a real ingredient bump (.mavergreen/ingredients/libressl/VERSION) reported
#       as "packaging changes only" because the caller was under a name ingredient-pins.sh did not
#       look for, or its own crash was swallowed. Reproduce both against this script directly, not
#       just ingredient-pins.sh: an ingredient repackage caller whose pins cannot be derived must
#       not ship as packaging-only.
r="$work/badcaller"; mkrepo "$r"
mv "$r/.github/workflows/repackage-on-ingredient-bump.yml" "$r/.github/workflows/renovate-repackage.yml"
( cd "$r" && git add -A && git commit -qm "rename caller" && git tag 9.9p2-mavericks.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null \
  || { echo "FAIL badcaller: should succeed once the caller is discovered by content, not by name"; exit 1; }
grep -q 'rebuilt because build ingredients moved' "$r/OUT.md" \
  || { echo "FAIL badcaller: a moved pin under a differently-named caller must not read as packaging-only"; cat "$r/OUT.md"; exit 1; }

r="$work/nopins"; mkrepo "$r"
cat > "$r/.github/workflows/repackage-on-ingredient-bump.yml" <<'YML'
on:
  push:
    branches: [main]
jobs:
  repackage:
    uses: Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
YML
rm -rf "$r/.mavergreen/ingredients"
( cd "$r" && git add -A && git commit -qm "caller with no ingredients" && git tag 9.9p2-mavericks.1 )
if gen "$r" 9.9p2-mavericks.1 >/dev/null 2>&1; then
  echo "FAIL nopins: a wired-up caller deriving zero pins should be fatal"; exit 1
fi

# spec: the path .github/workflows/repackage-on-ingredient-bump.yml is a convention, not a
#       guarantee: a repo that scaffolded it as a placeholder (or disabled it) has NOT actually
#       wired itself to repackage on ingredient bumps, even though the file exists there.
#       Preferring it by existence alone reintroduces a false FATAL on an otherwise legitimate
#       release -- a repo with a real libressl bump that this half-wired file was never watching
#       must still ship as "packaging changes only", exactly as it did before the
#       caller-discovery work started. A scaffolded/half-wired file at the CONVENTIONAL path must
#       not be trusted by name alone.
r="$work/unwired"; mkrepo "$r"
cat > "$r/.github/workflows/repackage-on-ingredient-bump.yml" <<'YML'
# placeholder -- not yet wired up
on:
  workflow_dispatch: {}
YML
( cd "$r" && git add -A && git commit -qm "scaffold placeholder caller" && git tag 9.9p2-mavericks.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null \
  || { echo "FAIL unwired: a half-wired placeholder at the conventional path must not be fatal"; exit 1; }
grep -q 'packaging changes only' "$r/OUT.md" \
  || { echo "FAIL unwired: an unwired placeholder must not claim ingredients moved"; cat "$r/OUT.md"; exit 1; }

# spec: release.yml sorts before repackage-on-ingredient-bump.yml in glob order, and a comment
#       naming the caller (a plausible thing to write, e.g. documenting a dispatch trigger) must
#       not be mistaken for a call to it. If it is, the real caller sitting right next to it is
#       never consulted: either a legitimate release goes FATAL (decoy paths name an untracked
#       file -> zero pins) or, worse, it ships with the WRONG ingredient section (decoy paths name
#       a tracked file -> that file's own history is reported instead of the real moved pin). A
#       decoy workflow that only MENTIONS the caller must not outrank the real caller.
r="$work/decoytrap"; mkrepo "$r"
cat > "$r/.github/workflows/release.yml" <<'YML'
# Dispatched by repackage-on-ingredient-bump.yml with local_release=true.
on:
  push:
    tags:
      - '*-mavericks.*'
    paths:
      - CMakeLists.txt
jobs:
  release:
    uses: ./.github/workflows/publish-release.yml
YML
( cd "$r" && git add -A && git commit -qm "add release.yml" && git tag 9.9p2-mavericks.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
printf 'cmake_minimum_required(VERSION 3.10)\n' > "$r/CMakeLists.txt"
( cd "$r" && git add -A && git commit -qm "bump libressl, add CMakeLists" && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null \
  || { echo "FAIL decoytrap: should succeed (the real caller sits right next to the decoy)"; exit 1; }
grep -q '3.8.2 -> 3.9.2' "$r/OUT.md" \
  || { echo "FAIL decoytrap: real moved pin (libressl) not reported -- decoy caller won"; cat "$r/OUT.md"; exit 1; }
grep -q 'CMakeLists.txt' "$r/OUT.md" \
  && { echo "FAIL decoytrap: decoy caller's unrelated path leaked into the ingredient section"; cat "$r/OUT.md"; exit 1; }

# platform: `uses: >-` with the reusable workflow's URI on the CONTINUATION line is valid YAML
#           and a real call, but the word `uses:` and the filename are then on different lines,
#           so a
#       `uses:.*<filename>` regex never matches. This repo IS wired up and its libressl pin really
#       moved; reading it as "no caller" ships "packaging changes only" at exit 0 -- the exact
#       original openssh bug, silently, for nothing but a formatting choice. A genuinely-wired
#       caller written as a YAML folded scalar is still a caller.
r="$work/foldedcaller"; mkrepo "$r"
cat > "$r/.github/workflows/repackage-on-ingredient-bump.yml" <<'YML'
on:
  push:
    branches: [main]
    paths:
      - .mavergreen/ingredients/libressl/VERSION
jobs:
  repackage:
    uses: >-
      Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
    with:
      own-upstream-paths: UPSTREAM_VERSION
YML
( cd "$r" && git add -A && git commit -qm "folded-scalar caller" && git tag 9.9p2-mavericks.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null \
  || { echo "FAIL foldedcaller: a folded-scalar 'uses:' is a real call and must not be fatal"; exit 1; }
grep -q '### Build ingredients' "$r/OUT.md" \
  || { echo "FAIL foldedcaller: wired caller's moved pin dropped, no ingredient section"; cat "$r/OUT.md"; exit 1; }
grep -q '3.8.2 -> 3.9.2' "$r/OUT.md" \
  || { echo "FAIL foldedcaller: a real libressl bump must not read as packaging-only"; cat "$r/OUT.md"; exit 1; }

# spec: aaa-release.yml -- decoytrap above is guarded by two rules at once (the default-path
#       preference AND the comment filter), so deleting either one alone leaves it passing -- it
#       proves nothing about the comment filter by itself. Here there is no file at the
#       conventional path at all, so only the comment filter stands between the earlier-sorting
#       decoy and the real caller: without it aaa-release.yml wins discovery outright and the
#       notes report ITS path instead of the libressl bump that actually moved. A comment
#       mention must not win DISCOVERY either,
#       not just the default-path race.
r="$work/commentonly"; mkrepo "$r"
mv "$r/.github/workflows/repackage-on-ingredient-bump.yml" "$r/.github/workflows/renovate-repackage.yml"
cat > "$r/.github/workflows/aaa-release.yml" <<'YML'
# Dispatched by repackage-on-ingredient-bump.yml with local_release=true.
on:
  push:
    tags:
      - '*-mavericks.*'
    paths:
      - CMakeLists.txt
jobs:
  release:
    uses: ./.github/workflows/publish-release.yml
YML
( cd "$r" && git add -A && git commit -qm "rename caller, add commenting decoy" && git tag 9.9p2-mavericks.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
printf 'cmake_minimum_required(VERSION 3.10)\n' > "$r/CMakeLists.txt"
( cd "$r" && git add -A && git commit -qm "bump libressl, add CMakeLists" && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null \
  || { echo "FAIL commentonly: a comment mention is not a second caller, so discovery is unambiguous"; exit 1; }
grep -q '3.8.2 -> 3.9.2' "$r/OUT.md" \
  || { echo "FAIL commentonly: real moved pin not reported -- the commenting decoy won discovery"; cat "$r/OUT.md"; exit 1; }
grep -q 'CMakeLists.txt' "$r/OUT.md" \
  && { echo "FAIL commentonly: the decoy's unrelated path leaked into the ingredient section"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh's caller discovery -- with no workflow at the conventional
#       path, an earlier-sorting file naming the reusable workflow on a NON-comment line is
#       indistinguishable from the real caller by content: it
#       yields pins of its own, and a genuine caller written as a folded scalar is the weaker
#       textual match. Picking the first in glob order shipped the decoy's own file as "the
#       ingredient that moved" and dropped the real libressl bump -- confidently wrong notes.
#       Which workflow defines the ingredient set is a gap, so discovery that finds two
#       candidates must not guess which one owns the pins -- it stops here.
r="$work/twocallers"; mkrepo "$r"
mv "$r/.github/workflows/repackage-on-ingredient-bump.yml" "$r/.github/workflows/renovate-repackage.yml"
cat > "$r/.github/workflows/aaa-release.yml" <<'YML'
on:
  push:
    paths:
      - CMakeLists.txt
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - run: echo "dispatched by repackage-on-ingredient-bump.yml"
YML
( cd "$r" && git add -A && git commit -qm "rename caller, add mentioning decoy" && git tag 9.9p2-mavericks.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
printf 'cmake_minimum_required(VERSION 3.10)\n' > "$r/CMakeLists.txt"
( cd "$r" && git add -A && git commit -qm "bump libressl, add CMakeLists" && git tag 9.9p2-mavericks.2 )
if gen "$r" 9.9p2-mavericks.2 >/dev/null 2>&1; then
  echo "FAIL twocallers: two discovery candidates must not be resolved by glob order"; cat "$r/OUT.md"; exit 1
fi
out="$(gen "$r" 9.9p2-mavericks.2 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'aaa-release.yml' \
  || { echo "FAIL twocallers: the die must name the candidates: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'renovate-repackage.yml' \
  || { echo "FAIL twocallers: the die must name the candidates: $out"; exit 1; }

# spec: scripts/release-notes.sh -- a release that is BOTH a new upstream AND an ingredient
#       repackage must show both
#       sections, with the upstream content FIRST. Neither existing case covers this: `new` above
#       is a first release with no baseline (so no ingredient diff is even possible), and `ing`
#       above is a same-upstream repackage that explicitly asserts NO upstream claim. A real
#       release can be both at once (a new upstream tarball that also bumps a vendored ingredient
#       in the same cut), and nothing else here exercises that combination or its ordering.
r="$work/combo"; mkrepo "$r"
( cd "$r" && git tag 9.9p1-mavericks.1 )                       # baseline: a DIFFERENT upstream (9.9p1)
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"            # an ingredient pin moves too
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavericks.1 )  # this cut ships new upstream 9.9p2
gen "$r" 9.9p2-mavericks.1 >/dev/null
grep -q 'New upstream: OpenSSH 9.9p2 (was 9.9p1)' "$r/OUT.md" \
  || { echo "FAIL combo: missing new-upstream bullet"; cat "$r/OUT.md"; exit 1; }
grep -q '### Build ingredients' "$r/OUT.md" \
  || { echo "FAIL combo: missing ingredient section"; cat "$r/OUT.md"; exit 1; }
grep -q '3.8.2 -> 3.9.2' "$r/OUT.md" || { echo "FAIL combo: pin delta missing"; cat "$r/OUT.md"; exit 1; }
u="$(grep -n 'New upstream:' "$r/OUT.md" | cut -d: -f1)"
i="$(grep -n '### Build ingredients' "$r/OUT.md" | cut -d: -f1)"
[ -n "$u" ] && [ -n "$i" ] && [ "$u" -lt "$i" ] \
  || { echo "FAIL combo: upstream content should precede ingredients"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/previous-release-tag.sh -- the only remaining `|| true` on a fact-bearing call:
#       a nonzero exit from this script (e.g. it cannot list tags) used to be swallowed into
#       PREV="",
#       which reads exactly like a genuine first release, silently dropping the ingredient
#       section and the compare link on a release that may have both. An EMPTY result must stay
#       legitimate; only a NONZERO exit is fatal, so this stubs the script to fail outright rather
#       than to print nothing: previous-release-tag.sh itself failing must not read as "no
#       baseline".
r="$work/prevtagfails"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 )
scripts_stub="$work/scripts-stub"
cp -R "$here/../scripts" "$scripts_stub"
printf '#!/bin/sh\necho "previous-release-tag.sh: boom, cannot list tags" >&2\nexit 7\n' \
  > "$scripts_stub/previous-release-tag.sh"
chmod +x "$scripts_stub/previous-release-tag.sh"
if ( cd "$r" && MAVERICKS_ROOT="$r" sh "$scripts_stub/release-notes.sh" --tag 9.9p2-mavericks.1 \
       --version 9.9p2-mavericks.1 --product OpenSSH --out "$r/OUT.md" ) >/dev/null 2>&1; then
  echo "FAIL prevtagfails: a failing previous-release-tag.sh must be fatal, not read as no baseline"; exit 1
fi
prevtag_out="$(cd "$r" && MAVERICKS_ROOT="$r" sh "$scripts_stub/release-notes.sh" --tag 9.9p2-mavericks.1 \
       --version 9.9p2-mavericks.1 --product OpenSSH --out "$r/OUT.md" 2>&1 || true)"
printf '%s\n' "$prevtag_out" | grep -qi 'previous-release-tag' \
  || { echo "FAIL prevtagfails: cause not named: $prevtag_out"; exit 1; }

r="$work/args"; mkrepo "$r"; ( cd "$r" && git tag 9.9p2-mavericks.1 )
if ( cd "$r" && MAVERICKS_ROOT="$r" sh "$S" --tag 9.9p2-mavericks.1 --version 9.9p2-mavericks.1 \
       --out "$r/OUT.md" ) >/dev/null 2>&1; then echo "FAIL args: --product must be required"; exit 1; fi

# spec: scripts/release-notes.sh -- a release with no --min-os floor and no compare link (e.g.,
#       swift-toolchain in a fixture with no remote). The old code printed the footer rule
#       unconditionally and then
#       conditionally appended the floor/link, so a body with neither ended in a dangling <hr>
#       and nothing after it -- the footer '---' must not be emitted with nothing after it.
r="$work/nofooter"; mkdir -p "$r/release-notes"
( cd "$r" && git init -q -b main . && git config user.email t@example.com && git config user.name tester )
( cd "$r" && echo x > README.md && git add -A && git commit -qm base && git tag v1.0.0 )
( cd "$r" && MAVERICKS_ROOT="$r" sh "$S" --tag v1.0.0 --version 1.0.0 \
    --product Shipyard --out "$r/OUT.md" ) >/dev/null
grep -q -- '^---$' "$r/OUT.md" \
  && { echo "FAIL G3: a footer rule with nothing after it was emitted"; cat "$r/OUT.md"; exit 1; }
[ -n "$(tail -1 "$r/OUT.md")" ] \
  || { echo "FAIL: the body must still end with real content, not a blank trailer left behind by the buffering: body ends with a blank line"; cat "$r/OUT.md"; exit 1; }
sh "$here/../scripts/check-release-notes.sh" "$r/OUT.md" 1.0.0 >/dev/null \
  || { echo "FAIL G3: no-footer body should still pass the family shape check"; exit 1; }

# spec: scripts/release-notes.sh -- but when a floor line applies, the rule must still be
#       emitted, right above it.
r="$work/withfooter"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 )
gen "$r" 9.9p2-mavericks.1 >/dev/null
grep -q -- '^---$' "$r/OUT.md" || { echo "FAIL G3: footer rule missing when a floor line applies"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- "126" is the shape a human reaches for (it's golang's own
#       product id, GO_LINE) but the line glob is a PREFIX of the real tags
#       (1.26.7-mavericks.N), so it must be "1.26" -- "126"
#       matches nothing. The existing "no visible tags" guard above only checks $UP-mavericks.*
#       (1.26.7-mavericks.*, which this fixture's own tag satisfies), so it does not cover this:
#       LINE is the one input it never looks at. Without this check PREV comes back empty, the
#       ingredient section and compare link both vanish, and the release ships shorter than the
#       truth at exit 0 -- a --line glob that matches no tag would silently ship a repackage
#       short.
r="$work/linefatal"; mkrepo "$r"
( cd "$r" && git tag 1.26.7-mavericks.1 )
if gen "$r" 1.26.7-mavericks.2 --product Go --line 126 --min-os 10.9.5 >/dev/null 2>&1; then
  echo "FAIL linefatal: --line matching no tag must be fatal for a repackage"; exit 1
fi
out="$(gen "$r" 1.26.7-mavericks.2 --product Go --line 126 --min-os 10.9.5 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'matches no' \
  || { echo "FAIL linefatal: error must name the unmatched line glob: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '1\.26' \
  || { echo "FAIL linefatal: error must show the shape the tags actually carry: $out"; exit 1; }

gen "$r" 1.26.7-mavericks.2 --product Go --line 1.26 --min-os 10.9.5 >/dev/null
grep -q 'compare/1\.26\.7-mavericks\.1\.\.\.1\.26\.7-mavericks\.2' "$r/OUT.md" \
  || { echo "FAIL linefatal: a correct --line still yields a compare link"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- N=1 is a genuine first release of a line and has no
#       baseline, so an unmatched --line must NOT be fatal for it -- that IS what a first release
#       of a new line looks like.
r="$work/linefatal-first"; mkrepo "$r"
gen "$r" 1.27.0-mavericks.1 --product Go --line 1.27 --min-os 10.9.5 >/dev/null
grep -q '^## Go 1.27.0 for Mavericks' "$r/OUT.md" \
  || { echo "FAIL linefatal-first: first release of a line still generates"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/gen_appcast.sh's renderer is what a 10.9 user's Sparkle dialog actually shows.
#       Markdown joins consecutive lines into ONE <p> (that is correct Markdown), but
#       release-notes.sh used to emit the floor line and the compare link back-to-back with no
#       blank line between them. Rendered, that is one run-on sentence whose second half is a
#       link ("Requires Mac OS X 10.9.5 or later. All changes since 9.9p2-mavericks.5"). An
#       assertion on the MARKDOWN would pass whether or not this is fixed -- the markdown was
#       never the problem -- so this asserts on the rendered HTML, via gen_appcast.sh
#       --render-notes, not on OUT.md: the footer's lines are separate statements and must
#       render as separate paragraphs.
r="$work/footerpara"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 )
gen "$r" 9.9p2-mavericks.2 >/dev/null
html="$(sh "$here/../scripts/gen_appcast.sh" --render-notes "$r/OUT.md")"
printf '%s\n' "$html" | grep -q '<p>Requires Mac OS X 10\.9\.5 or later\.</p>' \
  || { echo "FAIL footerpara: the install floor must be its own paragraph in the Sparkle dialog"; printf '%s\n' "$html"; exit 1; }
printf '%s\n' "$html" | grep -q 'or later\..*<a href' \
  && { echo "FAIL footerpara: the compare link is welded onto the install-floor sentence"; printf '%s\n' "$html"; exit 1; }

# spec: scripts/release-notes.sh -- a trailing machine-readable marker (the release-doctrine
#       session appends one before packaging) must also stand alone rather than trailing a
#       sentence a human is reading. This script cannot enforce that on an append that happens
#       afterwards in a different
#       repository's script -- it can only get its OWN footer right -- so this simulates that
#       append and checks the marker does not fuse to it either.
printf 'Mavergreen-State: v1:sha256:3f786850e387550fdab836ed7e6dc881de23001b\n' >> "$r/OUT.md"
html="$(sh "$here/../scripts/gen_appcast.sh" --render-notes "$r/OUT.md")"
printf '%s\n' "$html" | grep -q 'or later\..*sha256' \
  && { echo "FAIL footerpara: a state marker must not render inside the install-floor sentence"; printf '%s\n' "$html"; exit 1; }

# spec: scripts/patch-notes.sh -- a repackage that changes OUR modifications to the upstream source
#       is a behaviour change: tailscale 1.102.4-mavericks.7 added patches/darwin-exit-nodes.patch
#       (exit nodes on macOS) and its notes called it "packaging changes only". Patches are the
#       behaviour change, so their section comes FIRST, before any ingredient section.
r="$work/patchadd"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 && mkdir patches && echo p > patches/darwin-exit-nodes.patch \
    && git add -A && git commit -qm "exit nodes" && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null
grep -q 'packaging changes only' "$r/OUT.md" \
  && { echo "FAIL patchadd: a patch change is not packaging-only"; cat "$r/OUT.md"; exit 1; }
grep -q '^- Repackage of upstream OpenSSH 9.9p2 with changes to our patches (below)\.$' "$r/OUT.md" \
  || { echo "FAIL patchadd: kind"; cat "$r/OUT.md"; exit 1; }
grep -q '^  No upstream change\.$' "$r/OUT.md" || { echo "FAIL patchadd: no-upstream line"; cat "$r/OUT.md"; exit 1; }
grep -q '^### Our patches$' "$r/OUT.md" || { echo "FAIL patchadd: section"; cat "$r/OUT.md"; exit 1; }
grep -q '^- Added `patches/darwin-exit-nodes.patch`$' "$r/OUT.md" \
  || { echo "FAIL patchadd: bullet"; cat "$r/OUT.md"; exit 1; }
grep -q '### Build ingredients' "$r/OUT.md" && { echo "FAIL patchadd: no pin moved"; exit 1; }

# spec: scripts/patch-notes.sh -- an overlay is a modification even when it is not a .patch
#       (tailscale's replacement systray_darwin.m); removal and rename count too.
r="$work/patchmisc"; mkrepo "$r"
mkdir -p "$r/overlays" "$r/patches"
echo 'int x;' > "$r/overlays/systray_darwin.m"; echo a > "$r/patches/gone.patch"
printf '1\n2\n3\n4\n5\n6\n' > "$r/patches/before.patch"
( cd "$r" && git add -A && git commit -qm overlays && git tag 9.9p2-mavericks.1 \
    && echo 'int y;' > overlays/systray_darwin.m && git rm -q patches/gone.patch \
    && git mv patches/before.patch patches/after.patch \
    && git add -A && git commit -qm "touch overlays" && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null
grep -q '^- Changed `overlays/systray_darwin.m`$' "$r/OUT.md" || { echo "FAIL patchmisc: changed"; cat "$r/OUT.md"; exit 1; }
grep -q '^- Removed `patches/gone.patch`$' "$r/OUT.md" || { echo "FAIL patchmisc: removed"; cat "$r/OUT.md"; exit 1; }
grep -q '^- Renamed `patches/before.patch` to `patches/after.patch`$' "$r/OUT.md" \
  || { echo "FAIL patchmisc: renamed"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- patches AND ingredients moved -> both named in the summary,
#       patches section first.
r="$work/patching"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 && mkdir patches && echo p > patches/fix.patch \
    && printf '3.9.2\n' > .mavergreen/ingredients/libressl/VERSION \
    && git add -A && git commit -qm "both" && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null
grep -q '^- Repackage of upstream OpenSSH 9.9p2, rebuilt because build ingredients moved and our patches changed (below)\.$' "$r/OUT.md" \
  || { echo "FAIL patching: kind"; cat "$r/OUT.md"; exit 1; }
grep -q '^  No upstream change\.$' "$r/OUT.md" || { echo "FAIL patching: no-upstream line"; cat "$r/OUT.md"; exit 1; }
p="$(grep -n '^### Our patches$' "$r/OUT.md" | cut -d: -f1)"
i="$(grep -n '^### Build ingredients$' "$r/OUT.md" | cut -d: -f1)"
[ -n "$p" ] && [ -n "$i" ] && [ "$p" -lt "$i" ] \
  || { echo "FAIL patching: patches section must precede ingredients"; cat "$r/OUT.md"; exit 1; }
sh "$here/../scripts/check-release-notes.sh" "$r/OUT.md" 9.9p2-mavericks.2 >/dev/null \
  || { echo "FAIL patching: own output fails the shape check"; exit 1; }

# spec: scripts/release-notes.sh -- a new upstream often rebases our patches -- keep the
#       new-upstream line, add the section.
r="$work/patchnewup"; mkrepo "$r"
mkdir -p "$r/patches"; echo v1 > "$r/patches/fix.patch"
( cd "$r" && git add -A && git commit -qm p && git tag 9.9p1-mavericks.1 \
    && echo v2 > patches/fix.patch && git commit -qam rebase && git tag 9.9p2-mavericks.1 )
gen "$r" 9.9p2-mavericks.1 >/dev/null
grep -q 'New upstream: OpenSSH 9.9p2 (was 9.9p1)' "$r/OUT.md" || { echo "FAIL patchnewup: kind"; cat "$r/OUT.md"; exit 1; }
grep -q '^- Changed `patches/fix.patch`$' "$r/OUT.md" || { echo "FAIL patchnewup: section"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/patch-notes.sh -- committed prose under release-notes/ is not a modification of
#       upstream.
r="$work/patchprose"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 && printf 'Words.\n<!-- edited by a human -->\n' > release-notes/9.9p2-mavericks.2.md \
    && git add -A && git commit -qm prose && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null
grep -q '^- Repackage of upstream OpenSSH 9.9p2; packaging changes only\.$' "$r/OUT.md" \
  || { echo "FAIL patchprose: prose alone is packaging-only"; cat "$r/OUT.md"; exit 1; }
grep -q '### Our patches' "$r/OUT.md" && { echo "FAIL patchprose: no section"; exit 1; }

# spec: scripts/release-notes.sh -- with no patch change the body is byte-identical to what it
#       was before patch-notes existed.
r="$work/patchnone"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 && echo x >> README.md && git add -A \
    && git commit -qm unrelated && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null
want="$(printf '%s\n' '## OpenSSH 9.9p2 for Mavericks (9.9p2-mavericks.2)' '' '### What changed' \
  '- Repackage of upstream OpenSSH 9.9p2; packaging changes only.' '' '---' \
  'Requires Mac OS X 10.9.5 or later.' '' \
  '[All changes since 9.9p2-mavericks.1](https://github.com/Mavergreen/mavericks-openssh/compare/9.9p2-mavericks.1...9.9p2-mavericks.2)')"
[ "$(cat "$r/OUT.md")" = "$want" ] || { echo "FAIL patchnone: body changed"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- notes that cannot say whether our patches changed must not
#       ship.
r="$work/patchfails"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavericks.1 && git tag 9.9p2-mavericks.2 )
pstub="$work/scripts-pstub"
cp -R "$here/../scripts" "$pstub"
printf '#!/bin/sh\necho "patch-notes.sh: boom" >&2\nexit 5\n' > "$pstub/patch-notes.sh"
if ( cd "$r" && MAVERICKS_ROOT="$r" sh "$pstub/release-notes.sh" --tag 9.9p2-mavericks.2 \
       --version 9.9p2-mavericks.2 --product OpenSSH --out "$r/OUT.md" ) >/dev/null 2>&1; then
  echo "FAIL patchfails: a failing patch-notes.sh must be fatal"; exit 1
fi
out="$(cd "$r" && MAVERICKS_ROOT="$r" sh "$pstub/release-notes.sh" --tag 9.9p2-mavericks.2 \
       --version 9.9p2-mavericks.2 --product OpenSSH --out "$r/OUT.md" 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'patches' || { echo "FAIL patchfails: cause not named: $out"; exit 1; }

# spec: SKILL.md "Release notes" -- a self-upstream release says why it was cut, as a port's does:
#       an ingredient-only YYYYMMDD.N repackage that read "Release of <product> <version>." looked
#       like new code.
selfgen() {  # $1 = repo, $2 = tag/version, rest = extra env assignments
  r="$1"; v="$2"; shift 2
  ( cd "$r" && env MAVERICKS_ROOT="$r" "$@" sh "$S" --tag "$v" --version "$v" --product Porthole \
      --out "$r/OUT.md" ) >/dev/null
}
r="$work/r3first"; mkrepo "$r"
selfgen "$r" 20260802.1
grep -qx -- '- First release of Porthole 20260802.1\.' "$r/OUT.md" \
  || { echo "FAIL r3first"; cat "$r/OUT.md"; exit 1; }

r="$work/r3ing"; mkrepo "$r"
( cd "$r" && git tag 20260802.1 && printf '3.9.2\n' > .mavergreen/ingredients/libressl/VERSION \
    && git commit -qam "bump libressl" )
selfgen "$r" 20260802.2
grep -qx -- '- Rebuilt because build ingredients moved (below); no change to Porthole itself\.' "$r/OUT.md" \
  || { echo "FAIL r3ing"; cat "$r/OUT.md"; exit 1; }
grep -q '^### Build ingredients$' "$r/OUT.md" || { echo "FAIL r3ing: section"; cat "$r/OUT.md"; exit 1; }

r="$work/r3pkg"; mkrepo "$r"
( cd "$r" && git tag 20260802.1 && echo x >> README.md && git add -A && git commit -qm unrelated )
selfgen "$r" 20260802.2
grep -qx -- '- Repackage of Porthole 20260802; packaging changes only\.' "$r/OUT.md" \
  || { echo "FAIL r3pkg"; cat "$r/OUT.md"; exit 1; }

r="$work/r3new"; mkrepo "$r"
( cd "$r" && git tag 20260802.3 && echo x >> README.md && git add -A && git commit -qm code )
selfgen "$r" 20260815.1 GITHUB_REPOSITORY=Mavergreen/porthole-fork
grep -qx -- '- New release of Porthole 20260815.1 (was 20260802.3)\.' "$r/OUT.md" \
  || { echo "FAIL r3new"; cat "$r/OUT.md"; exit 1; }
grep -qx -- '  \[Changes since 20260802.3\](https://github.com/Mavergreen/porthole-fork/compare/20260802.3...20260815.1)' "$r/OUT.md" \
  || { echo "FAIL r3new: GITHUB_REPOSITORY names the compare"; cat "$r/OUT.md"; exit 1; }

# spec: SKILL.md "Release notes" -- with no GITHUB_REPOSITORY, the registry names the repo; with
#       neither, the link line is left out rather than guessed.
selfgen "$r" 20260815.1 GITHUB_REPOSITORY=
grep -qx -- '  \[Changes since 20260802.3\](https://github.com/Mavergreen/porthole/compare/20260802.3...20260815.1)' "$r/OUT.md" \
  || { echo "FAIL r3new: the registry names the compare"; cat "$r/OUT.md"; exit 1; }
( cd "$r" && env MAVERICKS_ROOT="$r" GITHUB_REPOSITORY= sh "$S" --tag 20260815.1 --version 20260815.1 \
    --product Unregistered --out "$r/OUT.md" ) >/dev/null
grep -qx -- '- New release of Unregistered 20260815.1 (was 20260802.3)\.' "$r/OUT.md" \
  || { echo "FAIL r3new: unregistered"; cat "$r/OUT.md"; exit 1; }
grep -q 'Changes since' "$r/OUT.md" && { echo "FAIL r3new: no repo, so no guessed link"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- a vX.Y.Z self-upstream's tag carries a v its version does not, so
#       the compare names the tags.
r="$work/r3v"; mkrepo "$r"
( cd "$r" && git tag v1.0.208 && echo x >> README.md && git add -A && git commit -qm code )
( cd "$r" && env MAVERICKS_ROOT="$r" GITHUB_REPOSITORY=Mavergreen/shipyard sh "$S" --tag v1.0.209 \
    --version 1.0.209 --product Shipyard --out "$r/OUT.md" ) >/dev/null
grep -qx -- '- New release of Shipyard 1.0.209 (was 1.0.208)\.' "$r/OUT.md" \
  || { echo "FAIL r3v"; cat "$r/OUT.md"; exit 1; }
grep -qx -- '  \[Changes since v1.0.208\](https://github.com/Mavergreen/shipyard/compare/v1.0.208...v1.0.209)' "$r/OUT.md" \
  || { echo "FAIL r3v: link"; cat "$r/OUT.md"; exit 1; }

# spec: SKILL.md "Release notes" -- a moved pin that is a whole file of this repo (our patch, a
#       vendored CA bundle) is described by its own diff, so it links this repo's compare view. Its
#       repo comes from GITHUB_REPOSITORY, else the registry; with neither, nothing is guessed, and the
#       bullet needs a declared reason like any other.
r="$work/r1d"; mkrepo "$r"
mkdir -p "$r/patches" "$r/vendor"
printf 'Subject: [PATCH] one\n' > "$r/patches/x.patch"; printf 'line one\n' > "$r/vendor/cacert.pem"
printf 'patches/*.patch\nvendor/cacert.pem\n' > "$r/.mavergreen/ingredients/libressl/watch"
cat > "$r/.github/workflows/repackage-on-ingredient-bump.yml" <<'YML'
on:
  push:
    branches: [main]
    paths:
      - .mavergreen/ingredients/libressl/VERSION
      - patches/x.patch
      - vendor/cacert.pem
jobs:
  repackage:
    uses: Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
    with:
      own-upstream-paths: UPSTREAM_VERSION
YML
( cd "$r" && git add -A && git commit -qm pins && git tag 9.9p2-mavericks.1 )
printf 'Subject: [PATCH] one\n+x\n' > "$r/patches/x.patch"; printf 'line one\nline two\n' > "$r/vendor/cacert.pem"
( cd "$r" && git commit -qam "move our own pins" && git tag 9.9p2-mavericks.2 )
gen "$r" 9.9p2-mavericks.2 >/dev/null || { echo "FAIL r1d: whole-file pins link the repo's own compare"; exit 1; }
grep -q '^- \*\*x.patch\*\*: updated (.*) (\[diff\](https://github.com/Mavergreen/mavericks-openssh/compare/9.9p2-mavericks.1...9.9p2-mavericks.2))$' "$r/OUT.md" \
  || { echo "FAIL r1d: patch"; cat "$r/OUT.md"; exit 1; }
grep -q '^- \*\*vendor/cacert.pem\*\*: updated (.*) (\[diff\](https://github.com/Mavergreen/mavericks-openssh/compare/9.9p2-mavericks.1...9.9p2-mavericks.2))$' "$r/OUT.md" \
  || { echo "FAIL r1d: blob"; cat "$r/OUT.md"; exit 1; }
( cd "$r" && env MAVERICKS_ROOT="$r" GITHUB_REPOSITORY= sh "$S" --tag 9.9p2-mavericks.2 --version 9.9p2-mavericks.2 \
    --product OpenSSH --out "$r/OUT.md" ) >/dev/null || { echo "FAIL r1d: the registry names the repo"; exit 1; }
grep -q '^- \*\*x.patch\*\*: .*(\[diff\](https://github.com/Mavergreen/openssh/compare/9.9p2-mavericks.1...9.9p2-mavericks.2))$' "$r/OUT.md" \
  || { echo "FAIL r1d: registry"; cat "$r/OUT.md"; exit 1; }
if out="$(cd "$r" && env MAVERICKS_ROOT="$r" GITHUB_REPOSITORY= sh "$S" --tag 9.9p2-mavericks.2 \
    --version 9.9p2-mavericks.2 --product Unregistered --out "$r/OUT.md" 2>&1)"; then
  echo "FAIL r1d: with no repo to name, a bare whole-file bullet is still a violation"; exit 1
fi
printf '%s\n' "$out" | grep -q 'deviations/unlinked/' || { echo "FAIL r1d: complaint: $out"; exit 1; }

# spec: scripts/release-notes.sh -- "First release" is a claim, so a self-upstream checkout that
#       simply lacks its tags must not make it: YYYYMMDD.N with N > 1 says earlier releases exist, and
#       in CI the repo's own releases say so for any scheme.
r="$work/m4"; mkrepo "$r"
if out="$(cd "$r" && env MAVERICKS_ROOT="$r" sh "$S" --tag 20260802.3 --version 20260802.3 \
    --product Porthole --out "$r/OUT.md" 2>&1)"; then
  echo "FAIL m4: 20260802.3 with no tags visible is not a first release"; cat "$r/OUT.md"; exit 1
fi
printf '%s\n' "$out" | grep -q 'fetch-depth: 0' || { echo "FAIL m4: name the fix: $out"; exit 1; }
stub="$work/m4-bin"; mkdir -p "$stub"
printf '#!/bin/sh\nprintf "%%s\\n" "${M4_RELEASE:-}"\n' > "$stub/gh"; chmod +x "$stub/gh"
if out="$(cd "$r" && env PATH="$stub:$PATH" M4_RELEASE=v1.0.208 GITHUB_ACTIONS=true \
    GITHUB_REPOSITORY=Mavergreen/shipyard MAVERICKS_ROOT="$r" sh "$S" --tag v1.0.209 \
    --version 1.0.209 --product Shipyard --out "$r/OUT.md" 2>&1)"; then
  echo "FAIL m4: the repo has releases, so no tags here means unfetched tags"; cat "$r/OUT.md"; exit 1
fi
printf '%s\n' "$out" | grep -q 'fetch-depth: 0' || { echo "FAIL m4: name the fix: $out"; exit 1; }
( cd "$r" && env PATH="$stub:$PATH" M4_RELEASE= GITHUB_ACTIONS=true GITHUB_REPOSITORY=Mavergreen/shipyard \
    MAVERICKS_ROOT="$r" sh "$S" --tag v1.0.0 --version 1.0.0 --product Shipyard --out "$r/OUT.md" ) >/dev/null \
  || { echo "FAIL m4: a repo with no releases yet is a first release"; exit 1; }
grep -qx -- '- First release of Shipyard 1.0.0\.' "$r/OUT.md" || { echo "FAIL m4: first"; cat "$r/OUT.md"; exit 1; }
# spec: tests/release-notes-test.sh "m4" -- a gh that cannot list (no GH_TOKEN on the step) proves
#       nothing, so it warns and trusts the checkout rather than refusing a first release.
printf '#!/bin/sh\necho "gh: To use GitHub CLI in a GitHub Actions workflow, set the GH_TOKEN environment variable" >&2\nexit 4\n' > "$stub/gh"; chmod +x "$stub/gh"
( cd "$r" && env PATH="$stub:$PATH" GITHUB_ACTIONS=true GITHUB_REPOSITORY=Mavergreen/shipyard \
    MAVERICKS_ROOT="$r" sh "$S" --tag v1.0.0 --version 1.0.0 --product Shipyard --out "$r/OUT.md" ) > "$work/m4-gh.out" 2>&1 \
  || { echo "FAIL m4: a gh that cannot list must not refuse a first release: $(cat "$work/m4-gh.out")"; exit 1; }
grep -q 'cannot list' "$work/m4-gh.out" || { echo "FAIL m4: say that the releases could not be checked: $(cat "$work/m4-gh.out")"; exit 1; }

echo "PASS: release-notes"
