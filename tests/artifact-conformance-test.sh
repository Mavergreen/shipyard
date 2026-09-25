#!/bin/sh
# platform: host-agnostic
# spec: scripts/check-artifact-conformance.sh consumes a fact stream so it can be tested without
#       fabricating real .pkg files; the extraction that produces those facts
#       (scripts/artifact-facts.sh) is exercised for real in CI at package time.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-artifact-conformance.sh"

# spec: both helpers append the completion sentinel that artifact-facts.sh ends a successful run
#       with, so every fixture below stays about the one fact it is probing rather than restating
#       the sentinel. The sentinel's own behaviour is tested at the end of this file, by fixtures
#       that bypass these helpers -- appending it here would otherwise make "the checker requires
#       a sentinel" untestable through them.
ok() {  # facts on stdin must pass
  printf '%s\nend-of-facts\n' "$2" | sh "$S" >/dev/null 2>&1 || { echo "FAIL $1: expected pass"; exit 1; }
}
no() {  # facts on stdin must fail, and name the check
  out="$(printf '%s\nend-of-facts\n' "$3" | sh "$S" 2>&1)" && { echo "FAIL $1: expected failure"; exit 1; }
  printf '%s\n' "$out" | grep -qi "$2" || { echo "FAIL $1: should mention '$2', got: $out"; exit 1; }
}

GOOD='expected 1.26.5-mavericks.5
pkg golang-1.26.5-native-mavericks.5.pkg 1.26.5-mavericks.5 10.9.5 dev.mavergreen.golang.go126
appcast appcast.xml 1.26.5-mavericks.5 golang-1.26.5-native-mavericks.5.pkg 4096 10.9.5
asset golang-1.26.5-native-mavericks.5.pkg 4096
asset appcast.xml 700'
ok "a coherent release" "$GOOD"

# spec: SKILL.md "SDK pinning" -- the sdk-pin rule over every shipped Mach-O slice.
M='macho golang-1.26.5-native-mavericks.5.pkg usr/local/go/bin/go'
ok "a pinned x86_64 slice" "$GOOD
$M x86_64 EXECUTE 10.9 10.9 aa"
no "an x86_64 slice linked against the runner's SDK" "sdk-pin" "$GOOD
$M x86_64 EXECUTE 10.9 26.5 aa"
ok "a pinned arm64 slice" "$GOOD
$M arm64 EXECUTE 11.0 11.3 aa"
no "an arm64 slice on the runner's SDK" "sdk-pin" "$GOOD
$M arm64 EXECUTE 11.0 26.5 aa"
ok "a kext records no version" "$GOOD
$M x86_64 KEXTBUNDLE - - aa"
ok "a 10.9-SDK archive member records sdk n/a" "$GOOD
$M x86_64 OBJECT 10.9 n/a aa"
no "an i386 slice has no pin" "sdk-pin" "$GOOD
$M i386 OBJECT 10.7 26.5 aa"
ok "pinned Sparkle passes on its content" "$GOOD
macho p.pkg Library/X.app/Contents/Frameworks/Sparkle.framework/Versions/A/Sparkle x86_64 DYLIB 10.9 12.0 95ad6ce1558b1ffef550455bf9aa05ad6686d434279631d170ab92fb3747c93f"
no "a different Sparkle does not" "sdk-pin" "$GOOD
macho p.pkg Library/X.app/Contents/Frameworks/Sparkle.framework/Versions/A/Sparkle x86_64 DYLIB 10.9 12.0 bb"
ok "a declared sdk-pin deviation excuses the files its glob names" "$GOOD
deviation sdk-pin:usr/local/go/src/* Go's own race-detector and testdata objects, shipped verbatim in src/
macho p.pkg usr/local/go/src/runtime/race/race_darwin.syso x86_64 OBJECT 10.12 14.4 aa"
no "and only those" "sdk-pin" "$GOOD
deviation sdk-pin:usr/local/go/src/* Go's own race-detector and testdata objects, shipped verbatim in src/
macho p.pkg usr/local/go/bin/go x86_64 EXECUTE 10.9 26.5 aa"

no "pkg version disagrees with the tag" "version" 'expected 1.26.5-mavericks.5
pkg p.pkg 1.26.5-mavericks.4 10.9.5 dev.mavergreen.golang.go126
asset p.pkg 10'

no "appcast version disagrees with the pkg" "version" 'expected 1.26.5-mavericks.5
pkg p.pkg 1.26.5-mavericks.5 10.9.5 dev.mavergreen.golang.go126
appcast appcast.xml 1.26.5-mavericks.4 p.pkg 10
asset p.pkg 10
asset appcast.xml 700'

no "appcast points at an asset that was not published" "enclosure" 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 10.9.5 dev.mavergreen.x
appcast appcast.xml 1.0.0-mavericks.1 ghost.pkg 10
asset p.pkg 10
asset appcast.xml 700'

no "appcast enclosure length disagrees with the real file" "length" 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 10.9.5 dev.mavergreen.x
appcast appcast.xml 1.0.0-mavericks.1 p.pkg 999
asset p.pkg 10
asset appcast.xml 700'

no "a .pkg without the 10.9.5 floor" "floor" 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 10.13 dev.mavergreen.x
asset p.pkg 10'

no "an identifier outside the family scheme" "identifier" 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 10.9.5 com.example.thing
asset p.pkg 10'

no "a version outside the family scheme" "scheme" 'expected 1.0.0
pkg p.pkg 1.0.0 10.9.5 dev.mavergreen.x
asset p.pkg 10'

no "two pkgs of one release disagree about the version" "version" 'expected 1.0.0-mavericks.1
pkg native.pkg 1.0.0-mavericks.1 10.9.5 dev.mavergreen.x
pkg cross.pkg 1.0.0-mavericks.2 10.9.5 dev.mavergreen.x-cross
asset native.pkg 10
asset cross.pkg 10'

ok "a tools product with no updater ships no appcast, and that is fine" 'expected 20221003-mavericks.2
pkg ed25519-20221003-mavericks.2.pkg 20221003-mavericks.2 10.9.5 dev.mavergreen.ed25519
asset ed25519-20221003-mavericks.2.pkg 10'

# platform: a component .pkg (PackageInfo, no Distribution) has no os-version floor by
#           construction -- floors are a productbuild concept. Its effective minimum lives in
#           the appcast that ships it. golang's cross product is exactly this: it TARGETS 10.9
#           but RUNS on 11.0+, so demanding 10.9.5 of it would be wrong.
ok "a component pkg whose appcast declares the minimum" 'expected 1.26.5-mavericks.5
pkg golang-cross.pkg 1.26.5-mavericks.5 none dev.mavergreen.golang.go126-cross
appcast appcast-cross.xml 1.26.5-mavericks.5 golang-cross.pkg 10 11.0
asset golang-cross.pkg 10
asset appcast-cross.xml 700'

no "a pkg with no floor and no appcast to declare one" "floor" 'expected 1.0.0-mavericks.1
pkg orphan.pkg 1.0.0-mavericks.1 none dev.mavergreen.x
asset orphan.pkg 10'

ok "a product archive that does declare 10.9.5" 'expected 1.0.0-mavericks.1
pkg native.pkg 1.0.0-mavericks.1 10.9.5 dev.mavergreen.x
asset native.pkg 10'

no "an undeclared floor deviation still fails" "floor" 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 11.0 dev.mavergreen.x
asset p.pkg 10'

ok "a declared floor deviation passes" 'expected 1.0.0-mavericks.1
deviation floor the cross toolchain runs on modern macOS and targets 10.9; it is not itself a 10.9 install
pkg p.pkg 1.0.0-mavericks.1 11.0 dev.mavergreen.x
asset p.pkg 10'

no "a deviation with no reason is not a deviation" "reason" 'expected 1.0.0-mavericks.1
deviation floor
pkg p.pkg 1.0.0-mavericks.1 11.0 dev.mavergreen.x
asset p.pkg 10'

no "a floor deviation is scoped to its own check and does not excuse a bad identifier" "identifier" 'expected 1.0.0-mavericks.1
deviation floor targets 10.9 rather than running on it
pkg p.pkg 1.0.0-mavericks.1 11.0 com.example.thing
asset p.pkg 10'

# spec: scripts/check-artifact-conformance.sh's scoped deviations -- swift-toolchain
#       republishes swift.org's .pkg verbatim so the correspondence with download.swift.org
#       stays checkable. Its version, floor and identifier are UPSTREAM's and must stay that way
#       -- but that must not excuse the artifacts we do build alongside it.
MIRROR='expected 6.3.3-mavericks.2
deviation version:upstream-swift-*.pkg mirrored verbatim from swift.org; the version is upstream own
deviation floor:upstream-swift-*.pkg same mirror
deviation identifier:upstream-swift-*.pkg same mirror
pkg upstream-swift-6.3.3-RELEASE-osx.pkg 6.3.3.20260625101 10.11 org.swift.633202606251a
asset upstream-swift-6.3.3-RELEASE-osx.pkg 10'
ok "a scoped deviation excuses the mirrored pkg" "$MIRROR"

no "the same scoped deviation does NOT excuse our own artifact" "version" 'expected 6.3.3-mavericks.2
deviation version:upstream-swift-*.pkg mirrored verbatim from swift.org
pkg ours.pkg 6.3.3-mavericks.1 10.9.5 dev.mavergreen.swift
asset ours.pkg 10'

# platform: an enclosure URL carries the release tag. If it names another release, Sparkle
#           serves users a different build than the one just published -- the feed and the
#           release silently disagree, and every other check still passes because both
#           artifacts are individually fine.
ok "an enclosure pointing at this release" 'expected 1.26.5-mavericks.5
pkg p.pkg 1.26.5-mavericks.5 10.9.5 dev.mavergreen.golang.go126
appcast appcast.xml 1.26.5-mavericks.5 p.pkg 10 10.9.5
enclosure-url appcast.xml https://github.com/Mavergreen/golang/releases/download/1.26.5-mavericks.5/p.pkg
asset p.pkg 10
asset appcast.xml 700'

no "an enclosure pointing at a DIFFERENT release" "enclosure-url" 'expected 1.26.5-mavericks.5
pkg p.pkg 1.26.5-mavericks.5 10.9.5 dev.mavergreen.golang.go126
appcast appcast.xml 1.26.5-mavericks.5 p.pkg 10 10.9.5
enclosure-url appcast.xml https://github.com/Mavergreen/golang/releases/download/1.26.5-mavericks.4/p.pkg
asset p.pkg 10
asset appcast.xml 700'

# spec: scripts/check-artifact-conformance.sh's build-info records -- the artifacts cannot
#       answer this: golang's native .pkg carries the CA bundle and the shim, its cross .pkg
#       legitimately does not (cross-built apps look at the native prefix). "Same shim, same CA"
#       is a claim about INPUTS, so each variant records what it used and conformance compares
#       the records.
ok "variants agreeing on their ingredients" 'expected 1.26.5-mavericks.5
build-info build-info-native.txt mls_version 1.5.2-mavericks.2
build-info build-info-native.txt ca_sha256 3ff344e30b9b
build-info build-info-cross.txt mls_version 1.5.2-mavericks.2
build-info build-info-cross.txt ca_sha256 3ff344e30b9b
pkg n.pkg 1.26.5-mavericks.5 10.9.5 dev.mavergreen.golang.go126
asset n.pkg 10'

no "variants built from DIFFERENT shim pins" "mls_version" 'expected 1.26.5-mavericks.5
build-info build-info-native.txt mls_version 1.5.2-mavericks.2
build-info build-info-cross.txt mls_version 1.5.2-mavericks.1
pkg n.pkg 1.26.5-mavericks.5 10.9.5 dev.mavergreen.golang.go126
asset n.pkg 10'

no "variants built from different CA bundles" "ca_sha256" 'expected 1.26.5-mavericks.5
build-info build-info-native.txt ca_sha256 3ff344e30b9b
build-info build-info-cross.txt ca_sha256 9a1c72b4aa0f
pkg n.pkg 1.26.5-mavericks.5 10.9.5 dev.mavergreen.golang.go126
asset n.pkg 10'

ok "keys that SHOULD differ per variant are not evidence of disagreement" 'expected 1.26.5-mavericks.5
build-info build-info-native.txt variant native
build-info build-info-native.txt arch x86_64
build-info build-info-native.txt prefix /usr/local/go126
build-info build-info-cross.txt variant cross
build-info build-info-cross.txt arch arm64
build-info build-info-cross.txt prefix /usr/local/go126-cross
pkg n.pkg 1.26.5-mavericks.5 10.9.5 dev.mavergreen.golang.go126
asset n.pkg 10'

ok "a single-variant product has nothing to compare against" 'expected 1.5.2-mavericks.2
build-info build-info.txt mls_version 1.5.2-mavericks.2
pkg p.pkg 1.5.2-mavericks.2 10.9.5 dev.mavergreen.legacysupport
asset p.pkg 10'

ok "a declared disagreement, with a reason" 'expected 1.26.5-mavericks.5
deviation ingredients the cross variant is deliberately built against the previous shim this once
build-info build-info-native.txt mls_version 1.5.2-mavericks.2
build-info build-info-cross.txt mls_version 1.5.2-mavericks.1
pkg n.pkg 1.26.5-mavericks.5 10.9.5 dev.mavergreen.golang.go126
asset n.pkg 10'

# spec: scripts/check-artifact-conformance.sh -- "ok" must not be indistinguishable from
#       "compared nothing". A check whose silence means both "agreed" and "there was nothing to
#       look at" cannot be trusted the day the records stop shipping.
out="$(printf '%s\n' 'expected 1.0.0-mavericks.1
build-info build-info-a.txt commit abc
build-info build-info-b.txt commit abc
pkg p.pkg 1.0.0-mavericks.1 10.9.5 dev.mavergreen.x
asset p.pkg 10
end-of-facts' | sh "$S")"
printf '%s\n' "$out" | grep -qi 'compared 2' \
  || { echo "FAIL should say how many records it compared; got: $out"; exit 1; }

out="$(printf '%s\n' 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 10.9.5 dev.mavergreen.x
asset p.pkg 10
end-of-facts' | sh "$S")"
printf '%s\n' "$out" | grep -qi 'no build records' \
  || { echo "FAIL should say when there was nothing to compare; got: $out"; exit 1; }

AF="$here/../scripts/artifact-facts.sh"

# spec: both the appcast <description> and the Release body are built from dist/RELEASE_NOTES.md
#       today, which is exactly why the assertion is cheap and why a future change that breaks
#       the coupling should be loud: a 10.9 user reading the update dialog must not be told a
#       different story than the Release page.
ok "notes: agreement passes" 'expected 9.9p2-mavericks.6
notes-render RELEASE_NOTES.md aaaa1111
appcast-notes appcast.xml aaaa1111'

no "notes: disagreement fails" "notes" 'expected 9.9p2-mavericks.6
notes-render RELEASE_NOTES.md aaaa1111
appcast-notes appcast.xml bbbb2222'

no "notes: an appcast with no description fails, since an empty one is a defect (what a 10.9 user reads in the update dialog) not an absence to skip" "notes" 'expected 9.9p2-mavericks.6
notes-render RELEASE_NOTES.md aaaa1111
appcast-notes appcast.xml'

ok "notes: a product with no appcast at all (a component-only release) has nothing to compare" 'expected 9.9p2-mavericks.6
notes-render RELEASE_NOTES.md aaaa1111'

ok "notes: a declared deviation excuses it, with a reason, like every other check" 'expected 9.9p2-mavericks.6
deviation notes the swift.org pkg is republished verbatim with its own notes
notes-render RELEASE_NOTES.md aaaa1111
appcast-notes appcast.xml bbbb2222'

# spec: the notes file's basename is a per-repo INPUT (release-assets.sh's --notes-file), so a
#       product staging its body under a name artifact-facts.sh's RELEASE_NOTES.md case does not
#       recognize must not get a green run with this whole layer silently disabled. An
#       appcast-notes fact with NO notes-render to compare against is the same "records stopped
#       shipping" shape as an outright disagreement, and must not be quietly skipped.
no "notes: an appcast-notes fact with no notes-render is not silently skipped" "notes" 'expected 9.9p2-mavericks.6
appcast-notes appcast.xml aaaa1111'

# spec: scripts/gen_appcast.sh + scripts/artifact-facts.sh -- not a hand-written fixture. A
#       fixture that does not match what the renderer actually emits would let this check pass
#       while proving nothing about the real coupling. Build a real notes file, render a real
#       appcast from it with gen_appcast.sh (the same tool a release uses), then ask
#       artifact-facts.sh for both digests.
GA="$here/../scripts/gen_appcast.sh"
_nr="$(mktemp -d "${TMPDIR:-/tmp}/af-notes.XXXXXX")"
mkdir -p "$_nr/dist"
cat > "$_nr/dist/RELEASE_NOTES.md" <<'NOTES'
## Summary

Some bug fixes.

- Fixed a thing
- Fixed another thing

**Note:** upgrade recommended.

---

Requires 10.9.5 or later.
NOTES
sh "$GA" "Test Channel" "9.9p2-mavericks.6" "https://example.com/x.pkg" "10.9.5" \
  "$_nr/dist/RELEASE_NOTES.md" 'sparkle:edSignature="x" length="10"' > "$_nr/dist/appcast.xml"
_facts="$(sh "$AF" "$_nr/dist" 9.9p2-mavericks.6 "$_nr")"
_render_digest="$(printf '%s\n' "$_facts" | sed -n 's/^notes-render [^ ]* \(..*\)$/\1/p')"
_appcast_digest="$(printf '%s\n' "$_facts" | sed -n 's/^appcast-notes [^ ]* \(..*\)$/\1/p')"
[ -n "$_render_digest" ] \
  || { echo "FAIL: artifact-facts emitted no notes-render fact for a real notes file"; exit 1; }
[ "$_render_digest" = "$_appcast_digest" ] \
  || { echo "FAIL: notes-render and appcast-notes digests should agree for a real rendered pair; got '$_render_digest' vs '$_appcast_digest'"; exit 1; }

# spec: scripts/artifact-facts.sh -- a REAL appcast with its <description> emptied must extract
#       as "no digest". Not a hand-written appcast: start from the real one just built and
#       remove only its CDATA
#       content, leaving the <description></description> tags in place. This is the specific
#       shape that distinguishes "probe for a CDATA section" from "probe for a <description> tag"
#       (the latter would find the empty tags present, compute a digest of nothing, and fail for
#       the wrong reason -- a mismatch -- rather than reporting no digest at all). Assert directly
#       on the FACT LINE artifact-facts.sh emits, not just on the checker's downstream pass/fail,
#       since both probes lead to failure either way; only the fact itself tells them apart.
mkdir -p "$_nr/dist-nodesc"
cp "$_nr/dist/RELEASE_NOTES.md" "$_nr/dist-nodesc/RELEASE_NOTES.md"
awk '
  /<description>/ && /<!\[CDATA\[/ { print "      <description></description>"; skip = 1; next }
  skip && /<\/description>/ { skip = 0; next }
  skip { next }
  { print }
' "$_nr/dist/appcast.xml" > "$_nr/dist-nodesc/appcast.xml"
grep -q '<description></description>' "$_nr/dist-nodesc/appcast.xml" \
  || { echo "FAIL: test setup did not produce an empty <description> fixture"; exit 1; }
_nodesc_facts="$(sh "$AF" "$_nr/dist-nodesc" 9.9p2-mavericks.6 "$_nr")"
_nodesc_line="$(printf '%s\n' "$_nodesc_facts" | grep '^appcast-notes ')"
[ "$_nodesc_line" = "appcast-notes appcast.xml" ] \
  || { echo "FAIL: an emptied <description> should emit 'appcast-notes appcast.xml' with no digest field; got: $_nodesc_line"; exit 1; }
no "notes: a real appcast with an emptied description fails" "notes" "$_nodesc_facts"

# spec: scripts/artifact-facts.sh -- a REAL appcast built from genuinely DIFFERENT notes must be
#       detected as a mismatch. Two real renders, not a hand-typed hash: this pins the digest
#       computation's sensitivity to actual content, not just its plumbing.
cat > "$_nr/dist/RELEASE_NOTES_B.md" <<'NOTES'
## Summary

Some bug fixes.

- Fixed a totally different thing

Requires 10.9.5 or later.
NOTES
sh "$GA" "Test Channel" "9.9p2-mavericks.6" "https://example.com/x.pkg" "10.9.5" \
  "$_nr/dist/RELEASE_NOTES_B.md" 'sparkle:edSignature="x" length="10"' > "$_nr/dist/appcast-b.xml"
mkdir -p "$_nr/dist-mismatch"
cp "$_nr/dist/RELEASE_NOTES.md" "$_nr/dist-mismatch/RELEASE_NOTES.md"     # notes-render from A
cp "$_nr/dist/appcast-b.xml" "$_nr/dist-mismatch/appcast.xml"             # appcast rendered from B
_mismatch_facts="$(sh "$AF" "$_nr/dist-mismatch" 9.9p2-mavericks.6 "$_nr")"
_a_digest="$(printf '%s\n' "$_mismatch_facts" | sed -n 's/^notes-render [^ ]* \(..*\)$/\1/p')"
_b_digest="$(printf '%s\n' "$_mismatch_facts" | sed -n 's/^appcast-notes [^ ]* \(..*\)$/\1/p')"
[ "$_a_digest" != "$_b_digest" ] \
  || { echo "FAIL: rendering two genuinely different notes files should not produce equal digests"; exit 1; }
no "notes: a real appcast rendered from DIFFERENT notes is a mismatch" "notes" "$_mismatch_facts"

# spec: scripts/artifact-facts.sh -- the style line must be stripped by TAG, not by its literal
#       CSS text. Change the injected
#       <style>...</style> line's content in a real appcast (same tag, different CSS) and confirm
#       the digests still agree. If the extraction ever regresses to matching gen_appcast.sh's
#       specific "Helvetica Neue" string instead of the <style ...>...</style> shape, this is what
#       catches it -- gen_appcast.sh is free to change that CSS without this check caring.
mkdir -p "$_nr/dist-css"
cp "$_nr/dist/RELEASE_NOTES.md" "$_nr/dist-css/RELEASE_NOTES.md"
sed 's#<style>body{font-family:"Helvetica Neue",Helvetica,Arial,sans-serif;font-size:13px;}</style>#<style>body{color:red}</style>#' \
  "$_nr/dist/appcast.xml" > "$_nr/dist-css/appcast.xml"
grep -q '<style>body{color:red}</style>' "$_nr/dist-css/appcast.xml" \
  || { echo "FAIL: test setup did not change the injected CSS"; exit 1; }
_css_facts="$(sh "$AF" "$_nr/dist-css" 9.9p2-mavericks.6 "$_nr")"
_css_render_digest="$(printf '%s\n' "$_css_facts" | sed -n 's/^notes-render [^ ]* \(..*\)$/\1/p')"
_css_appcast_digest="$(printf '%s\n' "$_css_facts" | sed -n 's/^appcast-notes [^ ]* \(..*\)$/\1/p')"
[ "$_css_render_digest" = "$_css_appcast_digest" ] \
  || { echo "FAIL: changing the injected CSS content should not change the digest (tag-based stripping regressed to a literal string match)"; exit 1; }

rm -rf "$_nr"

# spec: scripts/artifact-facts.sh -- the style-line strip must be anchored, so it cannot
#       over-strip real content. esc()
#       HTML-escapes '<' before any of our own tags are injected, so no notes-derived line can
#       ever start with a literal "<style" -- but a legitimate content line CAN contain that
#       substring somewhere in the MIDDLE (e.g. prose mentioning an inline style). Hand-built, not
#       from the renderer: this probes the extraction awk's own precision (the ^ anchor), a
#       property the renderer's escaping makes it impossible to exercise through --render-notes
#       itself. Without the anchor, an unanchored /<style/ would strip this legitimate line too,
#       silently losing real content from the digest.
_m14="$(mktemp -d "${TMPDIR:-/tmp}/af-notes-m14.XXXXXX")"
mkdir -p "$_m14/dist"
# spec: no RELEASE_NOTES.md here -- this probes only appcast.xml's extraction, and an empty one
#       would now be refused outright by the F4 fix below (correctly) rather than silently
#       ignored.
ASIDE='<p>An aside: <style>tiny</style> shown inline, deliberately not at line start.</p>'
cat > "$_m14/dist/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:shortVersionString>9.9p2-mavericks.6</sparkle:shortVersionString>
      <description><![CDATA[
<style>body{font-family:"Helvetica Neue",Helvetica,Arial,sans-serif;font-size:13px;}</style>
<p>Ordinary paragraph line one.</p>
$ASIDE
]]></description>
    </item>
  </channel>
</rss>
XML
_m14_facts="$(sh "$AF" "$_m14/dist" 9.9p2-mavericks.6 "$_m14")"
_m14_digest="$(printf '%s\n' "$_m14_facts" | sed -n 's/^appcast-notes [^ ]* \(..*\)$/\1/p')"
_m14_expected="$(printf '%s\n%s\n' '<p>Ordinary paragraph line one.</p>' "$ASIDE" | shasum -a 256 | cut -d' ' -f1)"
rm -rf "$_m14"
[ -n "$_m14_digest" ] \
  || { echo "FAIL: M14 fixture emitted no appcast-notes digest at all"; exit 1; }
[ "$_m14_digest" = "$_m14_expected" ] \
  || { echo "FAIL: the boilerplate <style> line should be stripped but a mid-line '<style' occurrence in real content must survive; got '$_m14_digest', expected '$_m14_expected'"; exit 1; }

# spec: scripts/artifact-facts.sh -- a renderer failure must not be swallowed into a quiet
#       sha256-of-empty. `render-notes | shasum` (a pipeline) would let gen_appcast.sh's own
#       refusal of an empty notes file exit
#       non-zero while the pipeline's LAST command (shasum) still exits 0, so set -eu never fires
#       and artifact-facts.sh would keep going with a notes-render fact for nothing at all -- one
#       of two ways "both sides empty, therefore equal, therefore pass" could happen.
#       artifact-facts.sh itself must fail.
_empty="$(mktemp -d "${TMPDIR:-/tmp}/af-notes-empty.XXXXXX")"
mkdir -p "$_empty/dist"
: > "$_empty/dist/RELEASE_NOTES.md"
_empty_out="$(mktemp "${TMPDIR:-/tmp}/af-notes-empty-out.XXXXXX")"
if sh "$AF" "$_empty/dist" 9.9p2-mavericks.6 "$_empty" >"$_empty_out" 2>&1; then
  rm -rf "$_empty"; rm -f "$_empty_out"
  echo "FAIL: artifact-facts.sh should refuse an empty RELEASE_NOTES.md, not emit a notes-render fact for it"
  exit 1
fi
grep -qi 'render-notes' "$_empty_out" \
  || { echo "FAIL: artifact-facts.sh's failure on an empty notes file should name the renderer; got: $(cat "$_empty_out")"; rm -rf "$_empty"; rm -f "$_empty_out"; exit 1; }
rm -rf "$_empty"; rm -f "$_empty_out"

# platform: refusing the producer's known-bad exits is not enough -- the consumers run
#           `artifact-facts.sh dist "$VER" | check-artifact-conformance.sh` and a pipeline's exit
#       status is its LAST command's, with no consumer setting pipefail. The producer's exit
#       status is DISCARDED; dying only TRUNCATES the stream, and every check in the checker is a
#       "stay quiet when there are no records" check. So the checker requires the sentinel a
#       successful producer run ends with, and these fixtures bypass ok()/no() (which append it)
#       to say so. Every record present and correct, but the stream just stops: that must not be
#       a pass.
_trunc_out="$(printf '%s\n' 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 10.9.5 dev.mavergreen.x
asset p.pkg 10' | sh "$S" 2>&1)" \
  && { echo "FAIL: a stream with no end-of-facts sentinel must not pass; got: $_trunc_out"; exit 1; }

# spec: scripts/check-artifact-conformance.sh -- an `abort` record means the producer gave up,
#       so the stream is untrustworthy no matter what else it carries -- including a sentinel.
#       The two normally cannot coexist (a producer
#       that aborts never reaches its sentinel), so a stream with both has a completion marker
#       that did not come from a completed run: a dist/ file whose NAME contains a newline splits
#       its own `asset` record and forges a bare `end-of-facts`. Keying only on the sentinel read
#       that as "conformance: ok" while the producer was reporting failure.
_ab="$(printf 'expected 1.0.0-mavericks.1\nabort gen_appcast.sh --render-notes failed for RELEASE_NOTES.md\nend-of-facts\n' | sh "$S" 2>&1)" \
  && { echo "FAIL: a stream carrying an abort record must not pass, sentinel or not; got: $_ab"; exit 1; }
printf '%s\n' "$_ab" | grep -q 'aborted' \
  || { echo "FAIL: an aborted stream must name the producer's reason; got: $_ab"; exit 1; }

# spec: scripts/check-artifact-conformance.sh -- and the forged-sentinel shape itself, as a
#       real dist/ would emit it.
_fg="$(printf 'expected 1.0.0-mavericks.1\nasset A\nend-of-facts\nZ 0\nasset RELEASE_NOTES.md 0\nabort gen_appcast.sh --render-notes failed for RELEASE_NOTES.md\n' | sh "$S" 2>&1)" \
  && { echo "FAIL: a forged end-of-facts must not pass while an abort is present; got: $_fg"; exit 1; }
printf '%s\n' "$_trunc_out" | grep -qi 'incomplete' \
  || { echo "FAIL: a truncated stream should say it is incomplete; got: $_trunc_out"; exit 1; }

# spec: scripts/check-artifact-conformance.sh -- the human-readable cause must survive the
#       pipe. "The stream stopped" is true and useless; the operator needs to read WHY, which is
#       what the producer's `abort` record carries.
_abort_out="$(printf '%s\n' 'expected 1.0.0-mavericks.1
abort gen_appcast.sh --render-notes failed for RELEASE_NOTES.md' | sh "$S" 2>&1)" \
  && { echo "FAIL: a stream carrying an abort record must not pass; got: $_abort_out"; exit 1; }
printf '%s\n' "$_abort_out" | grep -qi 'render-notes failed for RELEASE_NOTES.md' \
  || { echo "FAIL: the checker should surface the abort reason; got: $_abort_out"; exit 1; }

# spec: INGREDIENTS.md -- a deviation must not be able to switch this off. Deviations are
#       emitted EARLY (before dist/ is walked) so they SURVIVE a truncation -- a product could
#       otherwise declare its way out of the one check that notices every other check was
#       skipped.
_dev_out="$(printf '%s\n' 'expected 1.0.0-mavericks.1
deviation end-of-facts we would rather not be checked, thanks
pkg p.pkg 1.0.0-mavericks.1 10.9.5 dev.mavergreen.x
asset p.pkg 10' | sh "$S" 2>&1)" \
  && { echo "FAIL: a deviation must not excuse a truncated stream; got: $_dev_out"; exit 1; }

# spec: scripts/artifact-facts.sh -- and the producer really does end a successful run with it,
#       as the LAST line.
_sent="$(mktemp -d "${TMPDIR:-/tmp}/af-sentinel.XXXXXX")"
mkdir -p "$_sent/dist"
printf 'a\n' > "$_sent/dist/some-asset.txt"
_sent_facts="$(sh "$AF" "$_sent/dist" 1.0.0-mavericks.1 "$_sent")"
rm -rf "$_sent"
[ "$(printf '%s\n' "$_sent_facts" | tail -1)" = "end-of-facts" ] \
  || { echo "FAIL: artifact-facts.sh must end a successful run with the sentinel; got: $(printf '%s\n' "$_sent_facts" | tail -1)"; exit 1; }

_ext="$(mktemp -d "${TMPDIR:-/tmp}/af-extract.XXXXXX")"
mkdir -p "$_ext/dist"
cat > "$_ext/dist/appcast.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:version>1000</sparkle:version>
      <sparkle:shortVersionString>1.0.0-mavericks.1</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>10.9.5</sparkle:minimumSystemVersion>
      <enclosure url="https://example.com/d/1.0.0-mavericks.1/p.pkg" length="4096" sparkle:edSignature="x" />
    </item>
  </channel>
</rss>
XML
_ext_facts="$(sh "$AF" "$_ext/dist" 1.0.0-mavericks.1 "$_ext")"
rm -rf "$_ext"
printf '%s\n' "$_ext_facts" | grep -qxF 'appcast appcast.xml 1.0.0-mavericks.1 p.pkg 4096 10.9.5' \
  || { echo "FAIL: the identifying version and the OS floor are ELEMENTS while the URL and the length are enclosure ATTRIBUTES, so reading either from the wrong half yields unknown/0 -- and the element to read is shortVersionString, not <sparkle:version> 1000, which is the orderable comparison key and deliberately not the release version. Expected 'appcast appcast.xml 1.0.0-mavericks.1 p.pkg 4096 10.9.5', got: $_ext_facts"; exit 1; }

# spec: RELEASE_NOTES.md -- END TO END, on the real failure rather than a fixture: the exact
#       dist that regressed. An empty RELEASE_NOTES.md kills the producer before dist/*'s later
#       entries (RELEASE_NOTES.md sorts first), so the appcast's unrelated description and its
#       enclosure naming a file in
#       ANOTHER release were never even described -- and the checker printed "conformance: ok".
#       Piped exactly as release.yml pipes it, with no pipefail, this must now be loud.
_e2e="$(mktemp -d "${TMPDIR:-/tmp}/af-e2e.XXXXXX")"
mkdir -p "$_e2e/dist"
: > "$_e2e/dist/RELEASE_NOTES.md"
cat > "$_e2e/dist/appcast.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:shortVersionString>9.9p2-mavericks.6</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>10.9.5</sparkle:minimumSystemVersion>
      <description><![CDATA[
<p>Text that is not this release's notes at all.</p>
]]></description>
      <enclosure url="https://github.com/Mavergreen/openssh/releases/download/9.9p2-mavericks.5/ghost.pkg" length="4096" sparkle:edSignature="x" />
    </item>
  </channel>
</rss>
XML
_e2e_out="$(sh "$AF" "$_e2e/dist" 9.9p2-mavericks.6 "$_e2e" 2>/dev/null | sh "$S" 2>&1)" \
  && { rm -rf "$_e2e"; echo "FAIL: a dist whose producer aborts must fail the pipeline, not pass it; got: $_e2e_out"; exit 1; }
printf '%s\n' "$_e2e_out" | grep -qi 'render-notes' \
  || { rm -rf "$_e2e"; echo "FAIL: the end-to-end failure should name the cause; got: $_e2e_out"; exit 1; }

# spec: scripts/artifact-facts.sh -- and a NORMAL dist still passes end to end, so the sentinel
#       is not just a way to fail everything.
mkdir -p "$_e2e/good"
cat > "$_e2e/good/RELEASE_NOTES.md" <<'NOTES'
## Summary

A real body.

- Fixed a thing
NOTES
# platform: a text file with a .pkg name would be reported `unreadable` by pkgutil and fail for
#           a reason this fixture is not about, so it uses a .tgz instead. What it proves is
#           that a COMPLETE run reaches the sentinel and the checker accepts it -- the pkg
#           records have their own fixtures above. A real (if trivial) tarball, not a text file
#           wearing a .tgz name: artifact-facts.sh now extracts every shipped tarball looking for
#           Mach-O slices, and a non-tarball masquerading as one would abort for a reason this
#           fixture is not about, the same trap the comment above already names for .pkg.
mkdir -p "$_e2e/good-src"
printf 'payload\n' > "$_e2e/good-src/payload.txt"
( cd "$_e2e/good-src" && tar -czf "$_e2e/good/thing-9.9p2-mavericks.6.tgz" payload.txt )
rm -rf "$_e2e/good-src"
_good_len="$(wc -c < "$_e2e/good/thing-9.9p2-mavericks.6.tgz" | tr -d ' ')"
sh "$GA" "Test Channel" "9.9p2-mavericks.6" \
  "https://github.com/Mavergreen/openssh/releases/download/9.9p2-mavericks.6/thing-9.9p2-mavericks.6.tgz" \
  "10.9.5" "$_e2e/good/RELEASE_NOTES.md" "sparkle:edSignature=\"x\" length=\"$_good_len\"" \
  > "$_e2e/good/appcast.xml"
_good_out="$(sh "$AF" "$_e2e/good" 9.9p2-mavericks.6 "$_e2e" 2>&1 | sh "$S" 2>&1)" \
  || { rm -rf "$_e2e"; echo "FAIL: a normal dist must still pass end to end; got: $_good_out"; exit 1; }
printf '%s\n' "$_good_out" | grep -qi 'conformance: ok' \
  || { rm -rf "$_e2e"; echo "FAIL: a normal dist should report ok; got: $_good_out"; exit 1; }
rm -rf "$_e2e"

# spec: scripts/artifact-facts.sh "macho_facts" -- three ways a shipped Mach-O slice can be
#       unreadable, each of which must ABORT the stream (a record plus no end-of-facts) rather
#       than silently dropping the file and reporting a clean release.

# spec: scripts/macho-slices.sh -- a 5-byte "file" carrying the FEEDFACF magic and nothing else
#       is not a valid Mach-O anywhere: lipo -info rejects it on macOS, and lipo does not even
#       exist on Linux -- either way macho-slices.sh exits non-zero, and that failure must survive
#       as an abort record, not vanish as a skipped file.
_fc1="$(mktemp -d "${TMPDIR:-/tmp}/af-failclosed-a.XXXXXX")"
mkdir -p "$_fc1/src" "$_fc1/dist"
printf '\317\372\355\376x' > "$_fc1/src/tiny"
( cd "$_fc1/src" && tar -czf "$_fc1/dist/broken.tar.gz" tiny )
_fc1_facts="$(sh "$AF" "$_fc1/dist" 1.0.0-mavericks.1 "$_fc1" 2>/dev/null)" \
  && { rm -rf "$_fc1"; echo "FAIL: a tarball holding an unreadable Mach-O-magic file must abort, not succeed; got: $_fc1_facts"; exit 1; }
printf '%s\n' "$_fc1_facts" | grep -q '^abort cannot read a Mach-O' \
  || { rm -rf "$_fc1"; echo "FAIL: expected an 'abort cannot read a Mach-O' record; got: $_fc1_facts"; exit 1; }
printf '%s\n' "$_fc1_facts" | grep -qx 'end-of-facts' \
  && { rm -rf "$_fc1"; echo "FAIL: an aborted stream must not also carry end-of-facts; got: $_fc1_facts"; exit 1; }
printf '%s\n' "$_fc1_facts" | sh "$S" >/dev/null 2>&1 \
  && { rm -rf "$_fc1"; echo "FAIL: piping an aborted stream to the checker must not exit 0"; exit 1; }
rm -rf "$_fc1"

# spec: scripts/artifact-facts.sh "macho_facts" -- a file named *.tgz that is not actually a
#       tarball must abort extraction, not be silently skipped as though it carried no Mach-O.
_fc2="$(mktemp -d "${TMPDIR:-/tmp}/af-failclosed-b.XXXXXX")"
mkdir -p "$_fc2/dist"
printf 'not a tarball\n' > "$_fc2/dist/fake.tgz"
_fc2_facts="$(sh "$AF" "$_fc2/dist" 1.0.0-mavericks.1 "$_fc2" 2>/dev/null)" \
  && { rm -rf "$_fc2"; echo "FAIL: a .tgz that is not really a tarball must abort, not succeed; got: $_fc2_facts"; exit 1; }
printf '%s\n' "$_fc2_facts" | grep -q '^abort cannot extract' \
  || { rm -rf "$_fc2"; echo "FAIL: expected an 'abort cannot extract' record; got: $_fc2_facts"; exit 1; }
printf '%s\n' "$_fc2_facts" | grep -qx 'end-of-facts' \
  && { rm -rf "$_fc2"; echo "FAIL: an aborted stream must not also carry end-of-facts; got: $_fc2_facts"; exit 1; }
printf '%s\n' "$_fc2_facts" | sh "$S" >/dev/null 2>&1 \
  && { rm -rf "$_fc2"; echo "FAIL: piping an aborted stream to the checker must not exit 0"; exit 1; }
rm -rf "$_fc2"

# spec: scripts/artifact-facts.sh "macho_facts" -- a Mach-O-magic file this process cannot even
#       open (mode 000) must abort too, via the [ -r ] guard checked before reading the magic.
#       Skipped as root, which can read anything regardless of mode, so the fixture would prove
#       nothing there. Also skipped where `tar` is not GNU tar: building the fixture needs
#       --mode=000 (GNU-only) to record a mode-000 member without reading an unreadable source
#       file at archive time, and macOS's bsdtar has no such flag -- erroring there would redden
#       the whole test on the one host this rule most needs to hold on, for a reason unrelated to
#       what this fixture tests. The Linux strict run (GNU tar) still exercises it.
if [ "$(id -u)" = 0 ]; then
  echo "artifact-conformance: running as root -- skipping the mode-000 fail-closed fixture (root can read anything)"
elif ! tar --version 2>/dev/null | grep -q 'GNU tar'; then
  echo "artifact-conformance: skip: mode-000 fixture needs GNU tar's --mode"
else
  _fc3="$(mktemp -d "${TMPDIR:-/tmp}/af-failclosed-c.XXXXXX")"
  mkdir -p "$_fc3/src" "$_fc3/dist"
  printf '\317\372\355\376xxxxxxxxxxxx' > "$_fc3/src/noperm"
  # platform: --mode overrides the archived permission bits without needing to actually read a
  #           mode-000 source file at archive time (which even its owner cannot do); GNU tar
  #           (this host) restores that exact mode on extraction.
  ( cd "$_fc3/src" && tar --mode=000 -czf "$_fc3/dist/noperm.tar.gz" noperm )
  _fc3_facts="$(sh "$AF" "$_fc3/dist" 1.0.0-mavericks.1 "$_fc3" 2>/dev/null)" \
    && { rm -rf "$_fc3"; echo "FAIL: a tarball holding an unreadable (mode 000) Mach-O-magic file must abort, not succeed; got: $_fc3_facts"; exit 1; }
  printf '%s\n' "$_fc3_facts" | grep -q '^abort ' \
    || { rm -rf "$_fc3"; echo "FAIL: expected an abort record; got: $_fc3_facts"; exit 1; }
  printf '%s\n' "$_fc3_facts" | grep -qx 'end-of-facts' \
    && { rm -rf "$_fc3"; echo "FAIL: an aborted stream must not also carry end-of-facts; got: $_fc3_facts"; exit 1; }
  printf '%s\n' "$_fc3_facts" | sh "$S" >/dev/null 2>&1 \
    && { rm -rf "$_fc3"; echo "FAIL: piping an aborted stream to the checker must not exit 0"; exit 1; }
  rm -rf "$_fc3"
fi


# spec: scripts/check-artifact-conformance.sh -- a self-upstream product tags vX.Y.Z, so its
#       enclosure URL carries the v while the version does not; that is the same release.
ok "enclosure-url: a v-prefixed release tag is this release" 'expected 0.5.5
pkg p.pkg 0.5.5 10.9.5 dev.mavergreen.x
deviation scheme self-upstream, versioned vX.Y.Z
appcast appcast.xml 0.5.5 p.pkg 10 10.9.5
asset p.pkg 10
enclosure-url appcast.xml https://github.com/Mavergreen/magic-trackpad2/releases/download/v0.5.5/p.pkg'

no "enclosure-url: another release is still caught, v or no v" "enclosure-url" 'expected 0.5.5
pkg p.pkg 0.5.5 10.9.5 dev.mavergreen.x
deviation scheme self-upstream, versioned vX.Y.Z
appcast appcast.xml 0.5.5 p.pkg 10 10.9.5
asset p.pkg 10
enclosure-url appcast.xml https://github.com/Mavergreen/magic-trackpad2/releases/download/v0.5.4/p.pkg'

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Install layout and
#       identity" -- what a pkg installs carries the family's identity and lands where the family puts
#       things, unless a deviation scoped to that identifier or path says why not.
REL='expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 10.9.5 dev.mavergreen.x
asset p.pkg 10'

LAYOUT='component p.pkg dev.mavergreen.base
component p.pkg dev.mavergreen.x
manifest p.pkg x dev.mavergreen.x x
registered x dev.mavergreen.x
installs p.pkg usr/local/mavergreen/.base/1.0.9/mavergreen
installs p.pkg usr/local/mavergreen/x/mavergreen.plist'

alone() {  # facts must fail, and every failure reported must be check $2's -- no other check trips
  _err="$(printf '%s\nend-of-facts\n' "$3" | sh "$S" 2>&1 >/dev/null)" && { echo "FAIL $1: expected failure"; exit 1; }
  printf '%s\n' "$_err" | grep -v "^conformance: $2: " | grep -q . \
    && { echo "FAIL $1: only the $2 check should fail here, got: $_err"; exit 1; }
  return 0
}

ok "identity: family bundle, job and paths pass" "$REL
$LAYOUT
manifest-outside p.pkg Applications/Mavericks%20X.app
manifest-outside p.pkg Library/Application%20Support/Mavergreen/XUpdater.app
manifest-outside p.pkg Library/LaunchAgents/dev.mavergreen.x-updatecheck.plist
manifest-outside p.pkg Library/LaunchDaemons/dev.mavergreen.xd.plist
installs p.pkg usr/local/mavergreen/x/bin/x
installs p.pkg Applications/Mavericks%20X.app/Contents/MacOS/X
installs p.pkg Library/Application%20Support/Mavergreen/XUpdater.app/Contents/Info.plist
installs p.pkg Library/LaunchAgents/dev.mavergreen.x-updatecheck.plist
installs p.pkg Library/LaunchDaemons/dev.mavergreen.xd.plist
bundle p.pkg Library/Application%20Support/Mavergreen/XUpdater.app dev.mavergreen.XUpdater
launchd p.pkg Library/LaunchAgents/dev.mavergreen.x-updatecheck.plist dev.mavergreen.x-updatecheck"

no "install-path: loose files in /usr/local are no longer the family's" "install-path" "$REL
$LAYOUT
installs p.pkg usr/local/bin/x"

no "install-path: another product's tree is not this pkg's" "install-path" "$REL
$LAYOUT
installs p.pkg usr/local/mavergreen/y/bin/y"

no "install-path: .base is only for a pkg that carries the base component" "install-path" 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 10.9.5 dev.mavergreen.x
component p.pkg dev.mavergreen.x
manifest p.pkg x dev.mavergreen.x x
registered x dev.mavergreen.x
installs p.pkg usr/local/mavergreen/x/mavergreen.plist
installs p.pkg usr/local/mavergreen/.base/1.0.9/mavergreen'

no "manifest: a pkg that installs a product must carry its manifest" "manifest" "$REL
component p.pkg dev.mavergreen.base
component p.pkg dev.mavergreen.x
installs p.pkg usr/local/mavergreen/x/bin/x"

no "manifest: the product must be registered to this identifier" "registered" "$REL
component p.pkg dev.mavergreen.base
component p.pkg dev.mavergreen.x
manifest p.pkg x dev.mavergreen.x x
registered x none
installs p.pkg usr/local/mavergreen/x/mavergreen.plist"

no "manifest: the manifest's product must match the tree it sits in" "manifest" "$REL
component p.pkg dev.mavergreen.base
component p.pkg dev.mavergreen.x
manifest p.pkg y dev.mavergreen.x x
registered y dev.mavergreen.x
installs p.pkg usr/local/mavergreen/x/mavergreen.plist"

no "manifest: something installed outside the tree must be listed in outside" "outside" "$REL
component p.pkg dev.mavergreen.base
component p.pkg dev.mavergreen.x
manifest p.pkg x dev.mavergreen.x x
registered x dev.mavergreen.x
installs p.pkg usr/local/mavergreen/x/mavergreen.plist
installs p.pkg Applications/X.app/Contents/MacOS/X"

no "manifest: an outside entry must name something the pkg installs" "outside" "$REL
component p.pkg dev.mavergreen.base
component p.pkg dev.mavergreen.x
manifest p.pkg x dev.mavergreen.x x
registered x dev.mavergreen.x
manifest-outside p.pkg Applications/Gone.app
installs p.pkg usr/local/mavergreen/x/mavergreen.plist"

no "manifest: a whole unlisted directory is reported capped, not once per file" "5 more files outside its tree" "$REL
$LAYOUT
$(awk 'BEGIN { for (i = 0; i < 25; i++) print "installs p.pkg usr/local/bin/f" i }')"

alone "manifest: an outside directory that is not a bundle covers nothing beneath it -- uninstall refuses to remove it" "manifest" "$REL
$LAYOUT
manifest-outside p.pkg Applications
installs p.pkg Applications/Stray.app/Contents/MacOS/Stray"

alone "manifest: a launchd directory listed as outside covers none of its jobs" "manifest" "$REL
$LAYOUT
manifest-outside p.pkg Library/LaunchDaemons
installs p.pkg Library/LaunchDaemons/dev.mavergreen.xd.plist"

alone "manifest: a plain support directory listed as outside covers none of its files" "manifest" "$REL
$LAYOUT
manifest-outside p.pkg Library/Application%20Support/Mavergreen/x
installs p.pkg Library/Application%20Support/Mavergreen/x/data"

for _bad in /Applications/X.app 'Applications/../X.app' 'Applications/./X.app' usr/local/mavergreen/x/bin/x usr/local/mavergreen ''; do
  _facts="$REL
$LAYOUT
manifest-outside p.pkg Applications/X.app
manifest-outside p.pkg $_bad
installs p.pkg Applications/X.app/Contents/MacOS/X"
  no "manifest: outside entry '$_bad' has a shape the helper refuses to uninstall" "shape the helper refuses" "$_facts"
  alone "manifest: outside entry '$_bad' has a shape the helper refuses to uninstall" "manifest" "$_facts"
done

ok "manifest: a bundle entry covers the files beneath it, and a file entry covers itself" "$REL
$LAYOUT
manifest-outside p.pkg Applications/X.app
manifest-outside p.pkg Library/LaunchDaemons/dev.mavergreen.xd.plist
installs p.pkg Applications/X.app/Contents/MacOS/X
installs p.pkg Applications/X.app/Contents/Info.plist
installs p.pkg Library/LaunchDaemons/dev.mavergreen.xd.plist"

no "base: a product archive must carry dev.mavergreen.base first" "base" "$REL
component p.pkg dev.mavergreen.x
component p.pkg dev.mavergreen.base
manifest p.pkg x dev.mavergreen.x x
registered x dev.mavergreen.x
installs p.pkg usr/local/mavergreen/x/mavergreen.plist"

no "base: a bare component pkg cannot carry the helper, so it cannot install a product" "base" 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 none dev.mavergreen.x
appcast appcast.xml 1.0.0-mavericks.1 p.pkg 10 11.0
asset p.pkg 10
asset appcast.xml 10
component p.pkg dev.mavergreen.x
manifest p.pkg x dev.mavergreen.x x
registered x dev.mavergreen.x
installs p.pkg usr/local/mavergreen/x/mavergreen.plist'

no "identity: a bundle outside the family" "bundle-id" "$REL
$LAYOUT
bundle p.pkg Applications/X.app com.example.x"
alone "identity: a bundle outside the family" "bundle-id" "$REL
$LAYOUT
bundle p.pkg Applications/X.app com.example.x"

ok "identity: a bundle deviation scoped to its identifier excuses it" "$REL
$LAYOUT
deviation bundle-id:com.example.* upstream's own kext, loaded by upstream's identifier
bundle p.pkg Applications/X.app com.example.x"

alone "identity: a bundle deviation for a DIFFERENT identifier excuses nothing" "bundle-id" "$REL
$LAYOUT
deviation bundle-id:org.other.* some other bundle
bundle p.pkg Applications/X.app com.example.x"

alone "identity: a launchd job outside the family" "launchd-label" "$REL
$LAYOUT
launchd p.pkg Library/LaunchDaemons/com.example.xd.plist com.example.xd"

no "identity: a launchd plist not named for its Label" "named <Label>.plist" "$REL
$LAYOUT
launchd p.pkg Library/LaunchDaemons/dev.mavergreen.a.plist dev.mavergreen.b"
alone "identity: a launchd plist not named for its Label" "launchd-label" "$REL
$LAYOUT
launchd p.pkg Library/LaunchDaemons/dev.mavergreen.a.plist dev.mavergreen.b"

alone "install-path: another vendor's shared dir is outside the family" "install-path" "$REL
$LAYOUT
manifest-outside p.pkg Library/Application%20Support/SomeoneElse/XUpdater.app
installs p.pkg Library/Application%20Support/SomeoneElse/XUpdater.app/Contents/Info.plist"

alone "install-path: a launchd plist with a foreign name is outside the family" "install-path" "$REL
$LAYOUT
manifest-outside p.pkg Library/LaunchDaemons/com.example.xd.plist
installs p.pkg Library/LaunchDaemons/com.example.xd.plist"

alone "install-path: an arbitrary system location" "install-path" "$REL
$LAYOUT
manifest-outside p.pkg Library/Extensions/X.kext
installs p.pkg Library/Extensions/X.kext/Contents/Info.plist"

ok "install-path: a deviation scoped to the path excuses it, and the glob spans spaces" "$REL
$LAYOUT
deviation install-path:Library/Extensions/* 10.9 loads kexts only from here
deviation install-path:Library/Some*Place/* where upstream expects it
manifest-outside p.pkg Library/Extensions/X.kext
manifest-outside p.pkg Library/Some%20Place/y
installs p.pkg Library/Extensions/X.kext/Contents/Info.plist
installs p.pkg Library/Some%20Place/y"

no "install-path: a path deviation excuses only the paths it names" "Library/PreferencePanes" "$REL
$LAYOUT
deviation install-path:Library/Extensions/* 10.9 loads kexts only from here
manifest-outside p.pkg Library/Extensions/X.kext
manifest-outside p.pkg Library/PreferencePanes/X.prefPane
installs p.pkg Library/Extensions/X.kext/Contents/Info.plist
installs p.pkg Library/PreferencePanes/X.prefPane/Contents/Info.plist"
alone "install-path: a path deviation excuses only the paths it names" "install-path" "$REL
$LAYOUT
deviation install-path:Library/Extensions/* 10.9 loads kexts only from here
manifest-outside p.pkg Library/Extensions/X.kext
manifest-outside p.pkg Library/PreferencePanes/X.prefPane
installs p.pkg Library/Extensions/X.kext/Contents/Info.plist
installs p.pkg Library/PreferencePanes/X.prefPane/Contents/Info.plist"

alone "install-path: a path deviation with no reason excuses nothing" "install-path" "$REL
$LAYOUT
deviation install-path
manifest-outside p.pkg Library/Extensions/X.kext
installs p.pkg Library/Extensions/X.kext/Contents/Info.plist"

ok "manifest: a scoped, reasoned deviation excuses a pkg with no manifest, like any other check" "$REL
deviation manifest:p.pkg upstream's own pkg, mirrored unmodified
deviation install-path:usr/local/upstream/* upstream's own layout
installs p.pkg usr/local/upstream/bin/u"

ok "manifest: a generated entry need not be in the payload" "$REL
$LAYOUT
manifest-generated p.pkg Applications/Linux%20X.app"

alone "manifest: an absolute generated entry fails manifest" "manifest" "$REL
$LAYOUT
manifest-generated p.pkg /Applications/X.app"

alone "manifest: a generated entry under usr/local/mavergreen fails manifest" "manifest" "$REL
$LAYOUT
manifest-generated p.pkg usr/local/mavergreen/y/bin/y"

alone "manifest: a generated entry ending in / fails manifest" "manifest" "$REL
$LAYOUT
manifest-generated p.pkg Applications/X.app/"

alone "manifest: a generated entry with an empty segment fails manifest" "manifest" "$REL
$LAYOUT
manifest-generated p.pkg Applications//X.app"

alone "manifest: an outside entry ending in / fails manifest" "manifest" "$REL
$LAYOUT
manifest-outside p.pkg Applications/X.app/"

# spec: scripts/artifact-facts.sh "payload_facts" -- read from a REAL pkg, because the facts above
#       are only as good as the extraction: install-location, a nested framework that is not a
#       top-level bundle, a symlink, and a path with a space are each a way to report the wrong thing.
if command -v pkgbuild >/dev/null 2>&1 && command -v productbuild >/dev/null 2>&1 && [ -x /usr/libexec/PlistBuddy ]; then
  _pk="$(mktemp -d "${TMPDIR:-/tmp}/conformance-pkg.XXXXXX")"   # template: 10.9 BSD mktemp requires one
  _st="$_pk/stage"; _ap="$_st/Library/Application Support/Mavergreen/XUpdater.app/Contents"
  mkdir -p "$_ap/Frameworks/Sparkle.framework/Resources" "$_st/Library/LaunchAgents" "$_st/usr/local/mavergreen/x/bin" "$_pk/dist" "$_pk/comp" "$_pk/archive"
  _plist() { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>%s</key><string>%s</string></dict></plist>\n' "$1" "$2" > "$3"; }
  _plist CFBundleIdentifier dev.mavergreen.XUpdater "$_ap/Info.plist"
  _plist CFBundleIdentifier org.sparkle-project.Sparkle "$_ap/Frameworks/Sparkle.framework/Resources/Info.plist"
  _plist Label dev.mavergreen.x-updatecheck "$_st/Library/LaunchAgents/dev.mavergreen.x-updatecheck.plist"
  echo x > "$_st/usr/local/mavergreen/x/bin/x"; ln -s bin/x "$_st/usr/local/mavergreen/x/link"
  printf 'int main(void){return 0;}\n' > "$_pk/h.c"
  # platform: the runner's SDK would make this fixture fail the sdk-pin rule the archive assertion below now enforces; clang honours SDKROOT
  SDKROOT="$(sh "$here/../scripts/fetch_sdk.sh")" cc -arch x86_64 -mmacosx-version-min=10.9 "$_pk/h.c" -o "$_st/usr/local/mavergreen/x/bin/hello"
  ( cd "$_st/usr/local/mavergreen/x" && tar -czf "$_pk/dist/x-tools.tar.gz" bin/hello )
  # platform: guarded macOS-only call -- the enclosing `if command -v pkgbuild` skips this block without it
  /usr/libexec/PlistBuddy -c "Add :product string x" -c "Add :identifier string dev.mavergreen.x" \
    -c "Add :outside array" -c "Add :outside:0 string Library/Application Support/Mavergreen/XUpdater.app" \
    -c "Add :outside:1 string Library/LaunchAgents/dev.mavergreen.x-updatecheck.plist" \
    -c "Add :generated array" -c "Add :generated:0 string Applications/Linux X.app" \
    "$_st/usr/local/mavergreen/x/mavergreen.plist" >/dev/null
  printf 'x dev.mavergreen.x\n' > "$_pk/product-names"
  # platform: guarded macOS-only call -- the same `if command -v pkgbuild` as above
  pkgbuild --quiet --root "$_st" --identifier dev.mavergreen.x --version 1.0.0-mavericks.1 --install-location / \
    "$_pk/dist/x-1.0.0-mavericks.1.pkg"
  # platform: guarded macOS-only call -- the same `if command -v pkgbuild` as above
  pkgbuild --quiet --root "$_st/usr/local/mavergreen/x" --identifier dev.mavergreen.y --version 1.0.0-mavericks.1 \
    --install-location /usr/local/y "$_pk/dist/y-1.0.0-mavericks.1.pkg"
  # platform: guarded macOS-only call -- the same `if command -v pkgbuild` as above
  pkgbuild --quiet --root "$_st" --identifier dev.mavergreen.z --version 1.0.0-mavericks.1 --install-location /opt/z \
    "$_pk/dist/z-1.0.0-mavericks.1.pkg"
  cp "$_pk/dist/x-1.0.0-mavericks.1.pkg" "$_pk/comp/x-component.pkg"
  sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --base-version 1.0.9 \
    --component "$_pk/comp/x-component.pkg" --out "$_pk/archive/x-1.0.0-mavericks.1.pkg" >/dev/null 2>&1 \
    || { echo "FAIL: set_install_floor.sh could not build the archive this fixture reads"; exit 1; }
  _f="$(MAVERGREEN_PRODUCT_NAMES="$_pk/product-names" sh "$AF" "$_pk/dist" 1.0.0-mavericks.1 "$_pk")"
  _fa="$(MAVERGREEN_PRODUCT_NAMES="$_pk/product-names" sh "$AF" "$_pk/archive" 1.0.0-mavericks.1 "$_pk")"
  rm -rf "$_pk"
  for want in \
    'installs x-1.0.0-mavericks.1.pkg Library/Application%20Support/Mavergreen/XUpdater.app/Contents/Info.plist' \
    'installs x-1.0.0-mavericks.1.pkg usr/local/mavergreen/x/link' \
    'installs y-1.0.0-mavericks.1.pkg usr/local/y/bin/x' \
    'bundle x-1.0.0-mavericks.1.pkg Library/Application%20Support/Mavergreen/XUpdater.app dev.mavergreen.XUpdater' \
    'launchd x-1.0.0-mavericks.1.pkg Library/LaunchAgents/dev.mavergreen.x-updatecheck.plist dev.mavergreen.x-updatecheck' \
    'manifest x-1.0.0-mavericks.1.pkg x dev.mavergreen.x x' \
    'component x-1.0.0-mavericks.1.pkg dev.mavergreen.x' \
    'registered x dev.mavergreen.x' \
    'manifest-outside x-1.0.0-mavericks.1.pkg Library/Application%20Support/Mavergreen/XUpdater.app' \
    'manifest-outside x-1.0.0-mavericks.1.pkg Library/LaunchAgents/dev.mavergreen.x-updatecheck.plist' \
    'manifest-generated x-1.0.0-mavericks.1.pkg Applications/Linux%20X.app'
  do
    printf '%s\n' "$_f" | grep -qxF "$want" || { echo "FAIL: payload facts should include: $want -- got: $_f"; exit 1; }
  done
  printf '%s\n' "$_f" | grep -qE '^macho x-1\.0\.0-mavericks\.1\.pkg usr/local/mavergreen/x/bin/hello x86_64 EXECUTE 10\.9 10\.9 [0-9a-f]{64}$' \
    || { echo "FAIL: a Mach-O in a pkg payload must yield a macho fact -- got: $_f"; exit 1; }
  printf '%s\n' "$_f" | grep -qE '^macho x-tools\.tar\.gz bin/hello x86_64 EXECUTE 10\.9 10\.9 [0-9a-f]{64}$' \
    || { echo "FAIL: a Mach-O in a shipped tarball must yield a macho fact -- got: $_f"; exit 1; }
  printf '%s\n' "$_f" | grep -q '^macho .* usr/local/mavergreen/x/bin/x ' \
    && { echo "FAIL: a non-Mach-O file must not yield a macho fact: $_f"; exit 1; }
  printf '%s\n' "$_f" | grep -q 'org.sparkle-project' \
    && { echo "FAIL: a framework nested inside the updater is not a top-level bundle; its identifier is not the product's: $_f"; exit 1; }
  printf '%s\n' "$_f" | grep -q '^installs y-1.0.0-mavericks.1.pkg bin/' \
    && { echo "FAIL: payload paths must be read relative to the component's install-location, not to /: $_f"; exit 1; }
  printf '%s\n' "$_f" | grep -q '^manifest z-1.0.0-mavericks.1.pkg ' \
    && { echo "FAIL: a manifest is read only from a payload installed at /, where a product tree always lands: $_f"; exit 1; }
  for want in \
    'pkg x-1.0.0-mavericks.1.pkg 1.0.0-mavericks.1 10.9.5 dev.mavergreen.x' \
    'installs x-1.0.0-mavericks.1.pkg usr/local/mavergreen/.base/1.0.9/mavergreen'
  do
    printf '%s\n' "$_fa" | grep -qxF "$want" \
      || { echo "FAIL: a product archive's version and identity are the product's, not the base component's that precedes it: want $want -- got: $_fa"; exit 1; }
  done
  [ "$(printf '%s\n' "$_fa" | sed -n 's/^component x-1.0.0-mavericks.1.pkg //p' | tr '\n' ' ')" = 'dev.mavergreen.base dev.mavergreen.x ' ] \
    || { echo "FAIL: an archive's components are reported in Distribution order, base first: $_fa"; exit 1; }
  _ca="$(printf '%s\n' "$_fa" | sh "$S" 2>&1)" \
    || { echo "FAIL: an archive set_install_floor.sh built from a laid-out stage must pass conformance: $_ca"; exit 1; }
else
  echo "artifact-conformance: no pkgbuild/productbuild/PlistBuddy here -- the real-pkg payload fixture is skipped" >&2
fi

echo "PASS: artifact-conformance"
