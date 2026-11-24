#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
RD="$here/../scripts/release-decision.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/release-decision.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
MAVERGREEN_RELEASES="file://$w/srv"; SHIPYARD_FETCH_BACKOFF=0; SHIPYARD_FETCH_TRIES=1
export MAVERGREEN_RELEASES SHIPYARD_FETCH_BACKOFF SHIPYARD_FETCH_TRIES
R="$w/repo"; mkdir -p "$R/.mavergreen"

W='file w.pkg opt/mavergreen/w/bin/w 0755 aaaa
meta w feed-min-os 10.9.5
meta w.pkg identifier dev.mavergreen.w'
X='file x.pkg opt/mavergreen/x/bin/x 0755 bbbb
meta x feed-min-os 10.9.5
meta x.pkg identifier dev.mavergreen.x'
Y='file y.pkg opt/mavergreen/y/bin/y 0755 cccc
meta y feed-min-os 10.9.5'

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
serve() {
  _d="$w/srv/Mavergreen/w/releases/download/$1"; rm -rf "$_d"; mkdir -p "$_d"
  printf '%s\n' "$2" | LC_ALL=C sort -u > "$_d/CONTENT-MANIFEST.txt"
  shift 2
  for _f in "$@"; do printf '<rss/>\n' > "$_d/$_f"; done
  : > "$w/sums"
  for _f in "$_d"/*; do printf '%s  %s\n' "$(sha "$_f")" "${_f##*/}" >> "$w/sums"; done
  mv "$w/sums" "$_d/SHA256SUMS"
}
cand() { printf '%s\n' "$1" | LC_ALL=C sort -u > "$w/cand"; }
run() {
  rc=0; sh "$RD" "$@" > "$w/out" 2> "$w/err" || rc=$?
  out="$(cat "$w/out")"; err="$(cat "$w/err")"
  first="$(head -n 1 "$w/out")"
}
decide() { run --manifest "$w/cand" --repo Mavergreen/w --line '*-mavergreen.*' --repo-root "$R" "$@"; }
has() { printf '%s\n' "$out" | grep -qxF -- "$2" || fail "$1: the output has the line '$2': $out (stderr: $err)"; }
says() { printf '%s\n' "$out" | grep -qF -- "$2" || fail "$1: the output says '$2': $out (stderr: $err)"; }

TAGS='1.0-mavergreen.1
0.9-mavergreen.3'
RELEASE_DECISION_TAGS="$TAGS"; export RELEASE_DECISION_TAGS
T=1.0-mavergreen.1

serve "$T" "$W" w.xml; cand "$W"; decide
[ "$rc" -eq 0 ] || fail "identical: exit 0, got $rc: $err"
[ "$first" = skip ] || fail "identical content is skip: $out"
has identical "product w carry $T"
says identical "Not published: content identical to $T."
echo "ok: identical content skips, carrying the product"

cand "$(printf '%s\n' "$W" | sed 's/aaaa/abab/')"; decide
[ "$first" = publish ] || fail "one row differs: publish: $out"
has "one row" "product w changed"
says "one row" '### Installed files changed'
says "one row" '-file w.pkg opt/mavergreen/w/bin/w 0755 aaaa'
says "one row" '+file w.pkg opt/mavergreen/w/bin/w 0755 abab'
echo "ok: a changed row publishes and is listed"

serve "$T" "$W
$X" w.xml x.xml
cand "$W
$(printf '%s\n' "$X" | sed 's/bbbb/bcbc/')"; decide
[ "$first" = publish ] || fail "two products, one changed: publish: $out"
has "two products" "product w carry $T"
has "two products" "product x changed"
echo "ok: per product, an unchanged one is carried and a changed one is not"

serve "$T" "$W" ; cand "$W"; decide
has "no w.xml in SHA256SUMS" "product w changed"
[ "$first" = publish ] || fail "a product whose feed can't be carried publishes: $out"
echo "ok: a product whose feed the previous release lacks is changed"

serve "$T" "$W
$Y" w.xml y.xml; cand "$W"; decide
[ "$first" = publish ] || fail "a product dropped since the previous release publishes: $out"
has "dropped product" "product w carry $T"
echo "ok: a dropped product publishes"

serve "$T" "$W" w.xml; cand "$W
$X"; decide
[ "$first" = publish ] || fail "a product new to this release publishes: $out"
has "new product" "product x new"
echo "ok: a new product is new"

serve "$T" "$W" w.xml; cand "$W"; decide --force-reason 'notes typo'
[ "$first" = publish ] || fail "--force-reason publishes: $out"
has forced "product w changed"
says forced '### Forced: notes typo'
decide --force-reason '   '
[ "$first" = skip ] || fail "a blank --force-reason is absent: $out"
echo "ok: a reason forces a publish, and a blank one is no reason"

mkdir -p "$R/.mavergreen/deviations/publish-unchanged/developer-tool"
printf '*\n' > "$R/.mavergreen/deviations/publish-unchanged/developer-tool/scope"
printf 'developers should always get the latest\n' > "$R/.mavergreen/deviations/publish-unchanged/developer-tool/reason"
printf 'consumers stop taking shipyard through a moving @v1\n' > "$R/.mavergreen/deviations/publish-unchanged/developer-tool/revisit"
decide
[ "$first" = publish ] || fail "publish-unchanged publishes: $out"
has publish-unchanged "product w changed"
says publish-unchanged "the content is identical to $T"
rm -rf "$R/.mavergreen/deviations"
echo "ok: publish-unchanged publishes, and says the content is unchanged"

RELEASE_DECISION_TAGS='0.9-mavericks.3'; decide; RELEASE_DECISION_TAGS="$TAGS"
[ "$first" = publish ] || fail "no tag on the line publishes: $out"
has "no previous" "product w new"
echo "ok: no previous release publishes every product new"

d="$w/srv/Mavergreen/w/releases/download/$T"
grep -v CONTENT-MANIFEST "$d/SHA256SUMS" > "$w/s" && mv "$w/s" "$d/SHA256SUMS"; decide
[ "$first" = publish ] || fail "a manifest SHA256SUMS lacks publishes: $out"
has "unlisted manifest" "product w changed"
printf '%s\n' "$out" | awk 'b { print; exit } $0 == "" { b = 1 }' | grep -q "^::warning::.*$T" || fail "the summary's first line warns, naming the tag: $out"
rm -rf "$d"; decide
[ "$first" = publish ] || fail "a release that can't be fetched publishes: $out"
printf '%s\n' "$out" | awk 'b { print; exit } $0 == "" { b = 1 }' | grep -q "^::warning::.*$T" || fail "an unfetchable release warns, naming the tag: $out"
echo "ok: a manifest that can't be had publishes, with a warning"

serve "$T" "$W" w.xml; cand "$W"
run --compare-only --manifest "$w/cand" --repo Mavergreen/w --against "$T"
[ "$rc" -eq 0 ] || fail "--compare-only identical: exit 0, got $rc: $out $err"
cand "$(printf '%s\n' "$W" | sed 's/aaaa/abab/')"
run --compare-only --manifest "$w/cand" --repo Mavergreen/w --against "$T"
[ "$rc" -eq 1 ] || fail "--compare-only different: exit 1, got $rc"
has "--compare-only rows" '-file w.pkg opt/mavergreen/w/bin/w 0755 aaaa'
has "--compare-only rows" '+file w.pkg opt/mavergreen/w/bin/w 0755 abab'
run --compare-only --manifest "$w/cand" --repo Mavergreen/w --against 9.9-mavergreen.9
[ "$rc" -eq 2 ] || fail "--compare-only with no manifest at the tag: exit 2, got $rc"
echo "ok: --compare-only exits 0, 1 or 2"

many="$(i=0; while [ $i -lt 45 ]; do printf 'file w.pkg opt/mavergreen/w/f%02d 0644 aaaa\n' "$i"; i=$((i + 1)); done)"
serve "$T" "$W" w.xml; cand "$W
$many"; decide
[ "$(printf '%s\n' "$out" | grep -c '^+file w.pkg opt/mavergreen/w/f')" -eq 40 ] || fail "45 differing rows print 40: $out"
says "45 rows" 'and 5 more'
echo "ok: the row list is capped at 40"

run --manifest "$w/cand"
[ "$rc" -eq 2 ] || fail "a usage error exits 2, got $rc"
echo "PASS: release-decision"
