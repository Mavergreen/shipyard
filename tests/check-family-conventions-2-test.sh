#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/conventions_fixture.sh"

# spec: scripts/check-family-conventions.sh -- a release shipping a new upstream links upstream's notes: the repo commits the hook that
#       says where, or a deviations/upstream-notes/ says why there is nothing to link.
mkrepo "$work/u1"; (cd "$work/u1" && git rm -q --cached .mavergreen/hooks/upstream-release-notes-url && rm .mavergreen/hooks/upstream-release-notes-url)
if out="$(cd "$work/u1" && sh "$S" 2>&1)"; then echo "FAIL no hook and no reason should fail"; exit 1; fi
first_is "$out" upstream-notes || { echo "FAIL should be an upstream-notes failure: $out"; exit 1; }
deviation "$work/u1" upstream-notes own '*' 'this repo is its own upstream.'
(cd "$work/u1" && sh "$S" >/dev/null) || { echo "FAIL: the deviation, with a reason (a self-upstream repo; a bundle), is the other way to comply -- should pass"; exit 1; }
: > "$work/u1/.mavergreen/deviations/upstream-notes/own/reason"
if (cd "$work/u1" && sh "$S" >/dev/null 2>&1); then echo "FAIL: an empty reason is not a reason -- a reasonless deviation should fail"; exit 1; fi
mkrepo "$work/u2"; (cd "$work/u2" && mkdir -p build && git mv .mavergreen/hooks/upstream-release-notes-url build/upstream-release-notes-url.sh)
if out="$(cd "$work/u2" && sh "$S" 2>&1)"; then echo "FAIL: build/upstream-release-notes-url.sh is no longer read, so a hook only there should fail"; exit 1; fi
first_is "$out" upstream-notes || { echo "FAIL should be an upstream-notes failure: $out"; exit 1; }
# spec: scripts/check-family-conventions.sh -- a hook that exists but is not committed is the trap: CI's fresh checkout never sees it.
mkrepo "$work/u3"; (cd "$work/u3" && git rm -q --cached .mavergreen/hooks/upstream-release-notes-url)
if out="$(cd "$work/u3" && sh "$S" 2>&1)"; then echo "FAIL an uncommitted hook should fail"; exit 1; fi
first_is "$out" upstream-notes || { echo "FAIL should be an upstream-notes failure: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'exists but is not committed' || { echo "FAIL: the uncommitted hook is named as uncommitted: $out"; exit 1; }

# spec: a workflow that signs must call scan-for-key.yml -- publish-release.yml refuses a signed
#       release without its record, and a missing job should fail a PR here, not a release there.
mkrepo "$work/k"
# spec: scripts/check-family-conventions.sh check 23 -- a signing workflow builds a pkg too
#       (check 21's fallback), so it needs stage_product.sh the same as a direct pkgbuild caller.
printf '      - run: sh "$SHIPYARD_SCRIPTS/sign_and_appcast.sh" --product w --feed-dir dist --pkg dist/x.pkg\n      - run: SHIPYARD_CHECK_VERSION="$FULL" shipyard-check --dist dist\n      - run: sh "$SHIPYARD_SCRIPTS/stage_product.sh" --stage stage --product w --name W --version 1 --scripts-out scr\n' \
  >> "$work/k/.github/workflows/release.yml"
(cd "$work/k" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/k" && sh "$S" 2>&1)"; then echo "FAIL a signing workflow with no scan job should fail"; exit 1; fi
first_is "$out" signing-scans-for-key || { echo "FAIL should be a signing-scans-for-key failure: $out"; exit 1; }
cat >> "$work/k/.github/workflows/release.yml" <<'YML'
  scan:
    needs: [build]
    if: always()
    uses: Mavergreen/shipyard/.github/workflows/scan-for-key.yml@v1
    with: { artifact: dist }
YML
(cd "$work/k" && git add -A) >/dev/null 2>&1
(cd "$work/k" && sh "$S" >/dev/null) || { echo "FAIL a signing workflow with a scan job should pass: $(cd "$work/k" && sh "$S" 2>&1)"; exit 1; }

SA='sh "$SHIPYARD_SCRIPTS/sign_and_appcast.sh"'
signs "$work/sa1" "$SA --product w --feed-dir dist --pkg dist/x.pkg"
(cd "$work/sa1" && sh "$S" >/dev/null 2>&1) || { echo "FAIL: check 12: a one-line call with --product and --feed-dir passes: $(cd "$work/sa1" && sh "$S" 2>&1)"; exit 1; }
signs "$work/sa2" "# $SA --pkg x > dist/appcast.xml
$SA \\
  --product w --channel-title W \\
  --feed-dir dist --pkg dist/x.pkg 2>&1
echo signed > dist/log.txt"
(cd "$work/sa2" && sh "$S" >/dev/null 2>&1) || { echo "FAIL: check 12: a call continued over lines passes, and a later command's redirect is not its: $(cd "$work/sa2" && sh "$S" 2>&1)"; exit 1; }
signs "$work/sa3" "$SA --pkg dist/x.pkg > dist/appcast.xml"
sa_refused "$work/sa3" "the retired '--pkg ... > dist/appcast.xml' call"
signs "$work/sa4" "$SA \\
  --product w \\
  --pkg dist/x.pkg"
sa_refused "$work/sa4" "a continued call with no --feed-dir"
signs "$work/sa5" "$SA --product w --feed-dir dist --pkg dist/x.pkg > dist/w.xml"
sa_refused "$work/sa5" "a call that redirects its stdout"
signs "$work/sa6" "$SA --product w --feed-dir dist --pkg dist/x.pkg
$SA --product w-cross --pkg dist/y.pkg"
sa_refused "$work/sa6" "a second call without --feed-dir"

# spec: SKILL.md "Renovate & automerge" -- a pin on a -mavericks.N release must be read with
#       versioning that COMPARES N. Renovate's default coerces the suffix away, so .1 and .4
#       compare equal and the bot proposes nothing: swift-runtime's swift-toolchain pin sat at
#       6.3.3-mavericks.1 while .4 shipped, with a manager wired and green.
MMVER='regex:^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)-mavericks\.(?<build>\d+)$'
mkrepo "$work/mv"
printf '6.3.3-mavericks.1\n# renovate: datasource=github-releases depName=Mavergreen/swift-toolchain\n' > "$work/mv/.mavergreen/upstream/VERSION"
(cd "$work/mv" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/mv" && sh "$S" 2>&1)"; then echo "FAIL a -mavericks.N pin with default versioning should fail"; exit 1; fi
first_is "$out" renovate-suffix-versioning || { echo "FAIL should be a renovate-suffix-versioning failure: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'Mavergreen/swift-toolchain = 6.3.3-mavericks.1 (.mavergreen/upstream/VERSION)' || { echo "FAIL the failure names the dependency, its pin and its file: $out"; exit 1; }
printf '6.3.3-mavericks.1\n# renovate: datasource=github-releases depName=Mavergreen/swift-toolchain versioning=%s\n' "$MMVER" > "$work/mv/.mavergreen/upstream/VERSION"
(cd "$work/mv" && git add -A) >/dev/null 2>&1
(cd "$work/mv" && sh "$S" >/dev/null) || { echo "FAIL a -mavericks.N pin with the family versioning should pass"; exit 1; }
mkrepo "$work/mv2"
mkdir -p "$work/mv2/.mavergreen/ingredients/x"
printf 'v6.3.3-mavericks.1@%s\n# renovate: datasource=git-tags depName=https://example.com/x versioning=regex:^v(?<major>\\d+)\\.(?<minor>\\d+)\\.(?<patch>\\d+)\n' 0123456789abcdef0123456789abcdef01234567 > "$work/mv2/.mavergreen/ingredients/x/PIN"
(cd "$work/mv2" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/mv2" && sh "$S" 2>&1)"; then echo "FAIL versioning that ignores N should fail, on a PIN's ref too"; exit 1; fi
first_is "$out" renovate-suffix-versioning || { echo "FAIL should be a renovate-suffix-versioning failure: $out"; exit 1; }
mkrepo "$work/mv3"
printf 'V_9_9_P2\n# renovate: datasource=github-tags depName=openssh/openssh-portable\n' > "$work/mv3/.mavergreen/upstream/VERSION"
(cd "$work/mv3" && git add -A) >/dev/null 2>&1
(cd "$work/mv3" && sh "$S" >/dev/null) || { echo "FAIL a non-mavericks pin should pass"; exit 1; }
mkrepo "$work/mv4"
printf '6.3.3-mavericks.1\n# renovate: datasource=github-releases versioning=%s depName=Mavergreen/swift-toolchain\n' "$MMVER" > "$work/mv4/.mavergreen/upstream/VERSION"
(cd "$work/mv4" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/mv4" && sh "$S" 2>&1)"; then echo "FAIL a line 2 the preset's manager cannot read should fail"; exit 1; fi
first_is "$out" renovate-suffix-versioning || { echo "FAIL should be a renovate-suffix-versioning failure: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'cannot read line 2 of .mavergreen/upstream/VERSION' || { echo "FAIL the failure names the file whose line 2 is unreadable: $out"; exit 1; }

# spec: SKILL.md "Family conventions" check 14 -- the release body comes from the shared
#       generator, and every consumer reads that same file. Before Plan 2 six products published
#       "Automated release for Mac OS X 10.9 (Mavericks)." as their entire notes and tailscale
#       published an empty body; all 13 now call release-notes.sh. Check 5 only asks whether SOME
#       notes reached the release, which --generate-notes and a printf redirect both satisfy.
#       This is the strong form, and it fails on the PR rather than at release time. mkrepo's
#       baseline already IS the compliant shape (generator --out dist/RELEASE_NOTES.md, publisher
#       --notes-file dist/RELEASE_NOTES.md), so `mkrepo` alone covers the passing case; each
#       fixture below breaks exactly one thing -- starting with no generator at all: a repo that
#       publishes some body, but not this family's.
mkrepo "$work/g1"
grep -v 'release-notes\.sh' "$work/ok/.github/workflows/release.yml" > "$work/g1/.github/workflows/release.yml"
if out="$(cd "$work/g1" && sh "$S" 2>&1)"; then echo "FAIL a repo with no generator call should fail"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: check-release-notes.sh is the PUBLISHER's shape gate, a different script. A substring
#       match on "release-notes.sh" would let a repo that only runs the shape gate pass while
#       writing no body.
mkrepo "$work/g1b"
sed -e 's|sh "$SHIPYARD_SCRIPTS/release-notes\.sh" .*|sh "$SHIPYARD_SCRIPTS/check-release-notes.sh" dist/RELEASE_NOTES.md|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g1b/.github/workflows/release.yml"
if out="$(cd "$work/g1b" && sh "$S" 2>&1)"; then echo "FAIL check-release-notes.sh must not count as the generator"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a hand-written body is the exact regression this check exists for, in the printf-redirect
#       shape.
mkrepo "$work/g2"
sed -e 's|sh "$SHIPYARD_SCRIPTS/release-notes\.sh" .*|printf "## %s\\n\\nAutomated release.\\n" "$FULL" > dist/RELEASE_NOTES.md|' \
  -e '/--product Widget --min-os/d' "$work/ok/.github/workflows/release.yml" > "$work/g2/.github/workflows/release.yml"
if out="$(cd "$work/g2" && sh "$S" 2>&1)"; then echo "FAIL a hand-written body should fail"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: and in the copy-a-committed-file shape (porthole shipped its README.md as the body of
#       every release). The generator call stays, so this is caught by the redirect/cp clause and
#       nothing else.
mkrepo "$work/g3"
cat >> "$work/g3/.github/workflows/release.yml" <<'YML'
      - run: cp release-notes/README.md dist/RELEASE_NOTES.md
YML
if out="$(cd "$work/g3" && sh "$S" 2>&1)"; then echo "FAIL copying a committed file in as the body should fail"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: and in the directory that is NOT dist/. magic-trackpad2 stages its body at
#       build/RELEASE_NOTES.md, so a hand-write check anchored on dist/ passes every test above
#       while leaving the one repo that uses another directory completely uncovered -- which is
#       what a mutation run found here. The directory is the caller's business; the FILE is what
#       only the generator may write.
mkrepo "$work/g3b"
cat >> "$work/g3b/.github/workflows/release.yml" <<'YML'
      - run: printf '## %s\n\nAutomated release.\n' "$FULL" > build/RELEASE_NOTES.md
YML
if out="$(cd "$work/g3b" && sh "$S" 2>&1)"; then echo "FAIL a hand-written body outside dist/ should fail"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- but COPYING the generated body somewhere else is reading it, not writing it. A repo
#       staging the file into an artifact does exactly this, and flagging it would fail a correct
#       repo.
mkrepo "$work/g3c"
cat >> "$work/g3c/.github/workflows/release.yml" <<'YML'
      - run: cp dist/RELEASE_NOTES.md "$RUNNER_TEMP/keep.md"
YML
(cd "$work/g3c" && sh "$S" >/dev/null) || { echo "FAIL copying the generated body OUT must not be read as hand-writing it"; exit 1; }

# spec: scripts/check-family-conventions.sh -- GitHub's autogenerated notes are a commit list, not the Sparkle <description> a 10.9 user
#       reads. It satisfies check 5, which is exactly why 14 has to reject it by name.
mkrepo "$work/g4"
cat >> "$work/g4/.github/workflows/release.yml" <<'YML'
      - run: gh release create "$TAG" --generate-notes
YML
if out="$(cd "$work/g4" && sh "$S" 2>&1)"; then echo "FAIL --generate-notes should fail"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- the appcast must read the file the generator wrote, or the Release page and the update
#       dialog tell two different stories.
mkrepo "$work/g5"
sed 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file release-notes/README.md|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g5/.github/workflows/release.yml"
if out="$(cd "$work/g5" && sh "$S" 2>&1)"; then echo "FAIL a notes file the generator never wrote should fail"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- now the four shapes the REAL repos use, each of which a plausible check gets wrong.
#       magic-trackpad2 stages its body at build/RELEASE_NOTES.md and QUOTES the value. A check
#       anchored on dist/ fails it; a character class that excludes the quote captures an EMPTY
#       value and fails it too (and swift-runtime, which quotes a dist/ path).
mkrepo "$work/g6"
sed -e 's|--out dist/RELEASE_NOTES\.md|--out build/RELEASE_NOTES.md|' \
    -e 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file "build/RELEASE_NOTES.md"|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g6/.github/workflows/release.yml"
(cd "$work/g6" && sh "$S" >/dev/null) || { echo "FAIL a quoted build/ notes path should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and the quote must actually be STRIPPED, not merely survived. A pattern that excludes the
#       quote from the value captures an EMPTY string, which word-splits away to nothing and
#       leaves the subset loop with no members at all -- so the case above would keep passing for
#       entirely the wrong reason, with the comparison silently switched off for the two repos
#       that quote. A mutation run found this. A WRONG quoted path is what tells the two apart.
mkrepo "$work/g6b"
sed 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file "release-notes/README.md"|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g6b/.github/workflows/release.yml"
if out="$(cd "$work/g6b" && sh "$S" 2>&1)"; then echo "FAIL a quoted notes path the generator never wrote should fail"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: --out is not release-notes.sh's flag alone -- container-tools and tailscale pass --out
#       "$PKG" to cmake/package_pkg.sh. That must not make "$PKG" an acceptable --notes-file.
mkrepo "$work/g7"
cat >> "$work/g7/.github/workflows/release.yml" <<'YML'
      - run: sh cmake/package_pkg.sh --out "$PKG" --version "$VER"
YML
(cd "$work/g7" && sh "$S" >/dev/null) || { echo "FAIL a packaging step's --out must not fail the repo"; exit 1; }
# spec: the .md filter is what stops a packaging --out from vouching for a notes file. Spelled
#       with a LITERAL .pkg: a "$PKG" on the --notes-file side is skipped as unresolvable (see
#       g12 below) and would prove nothing about the filter.
mkrepo "$work/g7b"
cat >> "$work/g7b/.github/workflows/release.yml" <<'YML'
      - run: sh cmake/package_pkg.sh --out dist/tool.pkg --version "$VER"
      - run: sh "$SHIPYARD_SCRIPTS/gen_appcast.sh" --notes-file dist/tool.pkg
YML
if out="$(cd "$work/g7b" && sh "$S" 2>&1)"; then echo "FAIL a packaging --out must not vouch for a non-.md notes file"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- the comparison is between WHOLE values. A --notes-file that is a strict SUFFIX of a real
#       --out value is a genuinely different file, and a substring match would wave it through.
mkrepo "$work/g5c"
sed 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file NOTES.md|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g5c/.github/workflows/release.yml"
if out="$(cd "$work/g5c" && sh "$S" 2>&1)"; then echo "FAIL a notes file that is only a SUFFIX of the --out path should fail"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a repo that routes ONE path through a variable is more self-consistent than one spelling
#       it twice, and the two sides simply cannot be compared as text. Failing it would tell a
#       correct repo to "pass the same path release-notes.sh was given as --out" -- which it did.
#       Unresolvable values are skipped.
mkrepo "$work/g12"
sed -e 's|--out dist/RELEASE_NOTES\.md|--out "$NOTES"|' \
    -e 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file "$NOTES"|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g12/.github/workflows/release.yml"
(cd "$work/g12" && sh "$S" >/dev/null) || { echo "FAIL a notes path routed through a variable should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and a workflow expression the same way. Unskipped, the value stops at the first space and
#       the failure message named the garbage '${{'.
mkrepo "$work/g12b"
sed 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file "${{ steps.notes.outputs.path }}"|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g12b/.github/workflows/release.yml"
(cd "$work/g12b" && sh "$S" >/dev/null) || { echo "FAIL a notes path from a workflow expression should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- but skipping the unresolvable ones must not switch the comparison off: a LITERAL mismatch
#       in the same repo still fails.
mkrepo "$work/g12c"
sed 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file "$NOTES" --notes-file release-notes/README.md|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g12c/.github/workflows/release.yml"
if out="$(cd "$work/g12c" && sh "$S" 2>&1)"; then echo "FAIL a literal mismatch alongside a variable one should still fail"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a flag and its value need not share a line. Reproduced against openssh's real main by
#       changing nothing but whitespace: the captured --out value became the backslash, the .md
#       filter dropped it, and the repo was told to "pass the same path release-notes.sh was
#       given as --out" -- which it did. No repo wraps this way today, so this is a cosmetic
#       reformat away, not live; a reformat must not redden a repo.
mkrepo "$work/g17"
sed 's|--product Widget --min-os 10.9.5 --out dist/RELEASE_NOTES\.md|--product Widget --min-os 10.9.5 \\\
            --out \\\
            dist/RELEASE_NOTES.md|' "$work/ok/.github/workflows/release.yml" > "$work/g17/.github/workflows/release.yml"
grep -q '^ *--out \\$' "$work/g17/.github/workflows/release.yml" \
  || { echo "FAIL test setup did not produce a line-wrapped --out"; exit 1; }
(cd "$work/g17" && sh "$S" >/dev/null) || { echo "FAIL a line-wrapped --out value should pass"; exit 1; }

mkrepo "$work/g18"
sed -e 's|--out dist/RELEASE_NOTES\.md|--out=dist/RELEASE_NOTES.md|' \
    "$work/ok/.github/workflows/release.yml" > "$work/g18/.github/workflows/release.yml"
grep -q -e '--out=dist/RELEASE_NOTES\.md' "$work/g18/.github/workflows/release.yml" \
  || { echo "FAIL test setup did not produce an --out=VALUE form"; exit 1; }
(cd "$work/g18" && sh "$S" >/dev/null) \
  || { echo "FAIL --out=VALUE is the same command as --out VALUE, and a repo that writes the equals form must not be told it reads a notes file the generator does not write: the flag/value separator is a character class, not a literal space"; exit 1; }

# spec: scripts/check-family-conventions.sh -- the same on the reading side, which wraps just as legally. A block scalar, because that
#       is where a wrapped shell command can legally live: folding a plain `run:` scalar over two
#       lines would change what the shell is handed, and a fixture has to be a repo someone could
#       really write.
mkrepo "$work/g17b"
grep -v 'notes-file' "$work/ok/.github/workflows/release.yml" > "$work/g17b/.github/workflows/release.yml"
cat >> "$work/g17b/.github/workflows/release.yml" <<'YML'
      - run: |
          gh release create "$TAG" dist/* --notes-file \
            dist/RELEASE_NOTES.md
YML
(cd "$work/g17b" && sh "$S" >/dev/null) || { echo "FAIL a line-wrapped --notes-file value should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and joining the continuation must not be a way to switch the comparison off: a WRONG
#       path, wrapped, still fails and is still named. Without this, "wrapped values are skipped"
#       would pass the two cases above while checking nothing.
mkrepo "$work/g17c"
grep -v 'notes-file' "$work/ok/.github/workflows/release.yml" > "$work/g17c/.github/workflows/release.yml"
cat >> "$work/g17c/.github/workflows/release.yml" <<'YML'
      - run: |
          gh release create "$TAG" dist/* --notes-file \
            release-notes/README.md
YML
if out="$(cd "$work/g17c" && sh "$S" 2>&1)"; then echo "FAIL a wrapped notes path the generator never wrote should fail"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- 1password, ed25519, signal-desktop and swift-toolchain pass no --notes-file at all: they
#       stage no appcast from the notes. The subset loop is then empty, which is correct and not
#       a gap.
mkrepo "$work/g8" novm
grep -v 'notes-file' "$work/g8/.github/workflows/release.yml" > "$work/g8/release.yml"
mv "$work/g8/release.yml" "$work/g8/.github/workflows/release.yml"
cat >> "$work/g8/.github/workflows/release.yml" <<'YML'
  publish:
    uses: Mavergreen/shipyard/.github/workflows/publish-release.yml@v1
YML
(cd "$work/g8" && sh "$S" >/dev/null) || { echo "FAIL a repo that stages no appcast from the notes should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- porthole's feed-porthole moving-tag release passes a bare --notes "<text>" to gh release.
#       That is a feed pointer, not a product release body, and failing it would redden a
#       correct repo. golang does the same for each go-line feed.
mkrepo "$work/g9"
cat >> "$work/g9/.github/workflows/release.yml" <<'YML'
      - run: |
          gh release create feed-porthole --title 'Porthole appcast' \
            --notes "Sparkle appcast for Porthole; asset replaced every release, tag never moves."
YML
(cd "$work/g9" && sh "$S" >/dev/null) || { echo "FAIL a bare --notes on a moving-tag feed release must not fail"; exit 1; }

# spec: scripts/check-family-conventions.sh -- golang renders TWO appcasts from one body. The comparison is between SETS, so the same
#       path read twice is one member, not a duplicate to complain about.
mkrepo "$work/g10"
cat >> "$work/g10/.github/workflows/release.yml" <<'YML'
      - run: |
          sh "$SHIPYARD_SCRIPTS/gen_appcast.sh" --notes-file dist/RELEASE_NOTES.md --out-x dist/x.xml
          sh "$SHIPYARD_SCRIPTS/gen_appcast.sh" --notes-file dist/RELEASE_NOTES.md --out-n dist/n.xml
YML
(cd "$work/g10" && sh "$S" >/dev/null) || { echo "FAIL two appcasts from one body should pass"; exit 1; }

# spec: scripts/check-family-conventions.sh -- prose about a rule is not the rule being obeyed or broken. This family documents its
#       conventions in the very workflows they govern, so every clause here false-POSITIVES on
#       comments unless comment lines are dropped: appending any ONE of these four to openssh's
#       real main reddened it, and @v1 would have carried that to twelve repos within minutes. A
#       maintainer writing the rule down must not be the thing that breaks the rule.
mkrepo "$work/g13"
cat >> "$work/g13/.github/workflows/release.yml" <<'YML'
      - run: |
          # was: printf "x" > dist/RELEASE_NOTES.md -- never again
          # never: cp release-notes/README.md dist/RELEASE_NOTES.md
          # NOT --generate-notes here: it cannot say which ingredient moved
          # do not write --notes-file release-notes/README.md
          true
YML
(cd "$work/g13" && sh "$S" >/dev/null) || { echo "FAIL comments describing the banned shapes must not fail a correct repo"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and the other direction, which is the reason to filter in ci_mentions rather than only
#       where a false positive stung: a repo whose ONLY mention of the generator is a comment is
#       not wired up. magic-trackpad2 carries five such comment mentions beside its one real
#       invocation, so an unfiltered clause 1 kept printing "ok" with that invocation replaced by
#       `:`.
mkrepo "$work/g14"
sed 's|sh "$SHIPYARD_SCRIPTS/release-notes\.sh" .*|# TODO: rewire sh "$SHIPYARD_SCRIPTS/release-notes.sh" here|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g14/.github/workflows/release.yml"
if out="$(cd "$work/g14" && sh "$S" 2>&1)"; then echo "FAIL a generator mentioned only in a comment is not wired up"; exit 1; fi
first_is "$out" release-notes-generated || { echo "FAIL should be a release-notes-generated failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- and the residual the filter deliberately accepts, which is load-bearing rather than a
#       tolerated wart: container-tools writes
#       `--out dist/RELEASE_NOTES.md   # becomes the Release body`. A line that carries CODE plus
#       a trailing comment is not a comment line, and dropping it would drop a real --out.
mkrepo "$work/g15"
sed 's|--out dist/RELEASE_NOTES\.md|--out dist/RELEASE_NOTES.md   # becomes the Release body|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g15/.github/workflows/release.yml"
(cd "$work/g15" && sh "$S" >/dev/null) || { echo "FAIL a trailing inline comment must not hide a real --out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- the comment filter lives in ci_mentions, so checks 2, 5 and 12 get it too -- a comment
#       should not vouch for wiring anywhere. A repo whose only mention of the test runner is a
#       comment has unrun tests.
mkrepo "$work/g16"
sed 's|- run: sh "$SHIPYARD_SCRIPTS/run-repo-tests\.sh"|# we should run: sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"|' \
  "$work/ok/.github/workflows/release.yml" > "$work/g16/.github/workflows/release.yml"
if out="$(cd "$work/g16" && sh "$S" 2>&1)"; then echo "FAIL a test runner mentioned only in a comment should fail check 2"; exit 1; fi
first_is "$out" tests-run-in-ci || { echo "FAIL should be a tests-run-in-ci failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a check-14 failure must ACCUMULATE like every other, not abort the run: this gate reports
#       all its failures at once, and a check 14 that killed the script under set -eu would take
#       the "ok" guard and any future check 15 with it. So a repo that breaks 14 AND an earlier
#       check must report both.
mkrepo "$work/g11"
sed 's|--notes-file dist/RELEASE_NOTES\.md|--notes-file release-notes/README.md|' \
  "$work/ok/.github/workflows/release.yml" | grep -v 'run-repo-tests' > "$work/g11/.github/workflows/release.yml"
out="$(cd "$work/g11" && sh "$S" 2>&1 || true)"
has_id "$out" tests-run-in-ci || { echo "FAIL check 2 should still be reported: $out"; exit 1; }
has_id "$out" release-notes-generated || { echo "FAIL check 14 should still be reported: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- a failing run must NOT also print "ok". The success line used to sit mid-script, so
#       checks appended after it (7, 8, 9) printed "check-family-conventions: ok" and THEN failed
#       -- the exact "output says it passed while it did not" shape these gates exist to prevent.
mkrepo "$work/ok2"; (cd "$work/ok2" && git rm -q --cached .mavergreen/hooks/upstream-release-notes-url && rm .mavergreen/hooks/upstream-release-notes-url)
out="$(cd "$work/ok2" && sh "$S" 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'check-family-conventions: ok' \
  && { echo "FAIL a failing run printed ok: $out"; exit 1; }

# spec: SKILL.md "Family conventions" check 15 -- delegates to check-comments.sh, so these
#       fixtures prove the WIRING, not the scanner (tests/check-comments-test.sh already covers the
#       scanner's rules in detail). comment-reasons here mirrors this repo's own .mavergreen/config file
#       (platform, spec) so the fixture reasons match what check-comments.sh actually ships with.
mkrepo "$work/cm1"
mkdir -p "$work/cm1/scripts"
printf '#!/bin/sh\n# an untagged comment\nexit 0\n' > "$work/cm1/scripts/x.sh"
mkdir -p "$work/cm1/.mavergreen/config"
printf 'platform\nspec\n' > "$work/cm1/.mavergreen/config/comment-reasons"
(cd "$work/cm1" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/cm1" && sh "$S" 2>&1)"; then echo "FAIL: an untagged comment, with comment-reasons present, should fail"; exit 1; fi
first_is "$out" comments || { echo "FAIL should be a comments failure: $out"; exit 1; }

# spec: scripts/check-family-conventions.sh -- the same fixture, tagged, must pass: the check is
#       satisfied by a reason, not by removing the comment.
mkrepo "$work/cm2"
mkdir -p "$work/cm2/scripts"
printf '#!/bin/sh\n# platform: a fact about the platform or a tool\nexit 0\n' > "$work/cm2/scripts/x.sh"
mkdir -p "$work/cm2/.mavergreen/config"
printf 'platform\nspec\n' > "$work/cm2/.mavergreen/config/comment-reasons"
(cd "$work/cm2" && git add -A) >/dev/null 2>&1
(cd "$work/cm2" && sh "$S" >/dev/null) || { echo "FAIL: a comment tagged # platform: should pass"; exit 1; }

# spec: SKILL.md "Comments cite a reason" -- check-comments.sh itself exits 0 with
#       no comment-reasons file; this fixture is the load-bearing proof that the WIRING preserves
#       that opt-in. check-family-conventions.sh runs in 14 consumers through a moving @v1 tag --
#       without this passing, the day check 15 lands is the day all 14 go red on an untagged
#       comment nobody there has swept yet.
mkrepo "$work/cm3"
mkdir -p "$work/cm3/scripts"
printf '#!/bin/sh\n# an untagged comment\nexit 0\n' > "$work/cm3/scripts/x.sh"
(cd "$work/cm3" && git add -A) >/dev/null 2>&1
(cd "$work/cm3" && sh "$S" >/dev/null) || { echo "FAIL: no comment-reasons file at all must pass despite an untagged comment -- this is the opt-in promise"; exit 1; }

echo "PASS: check-family-conventions-2"
