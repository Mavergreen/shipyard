#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/release-assets.sh"
. "$here/../scripts/stand-in-marker.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/release-assets-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT

mkd() { d="$w/$1"; mkdir -p "$d"; printf 'notes\n' > "$d/RELEASE_NOTES.md"; printf 'pkg\n' > "$d/x.pkg"; printf 'xml\n' > "$d/x.xml"; }

mkd ok
out="$(sh "$S" "$w/ok")"
printf '%s\n' "$out" | grep -q 'x.pkg'      || { echo "FAIL asset missing: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'x.xml'    || { echo "FAIL asset missing: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'RELEASE_NOTES' && { echo "FAIL: assets must exclude the notes file, but it was attached as one: $out"; exit 1; }

mkd sums; printf 'old\n' > "$w/sums/SHA256SUMS"
sh "$S" "$w/sums" | grep -q 'SHA256SUMS' && { echo "FAIL: a pre-existing SHA256SUMS is not an asset, since the workflow regenerates it -- stale SHA256SUMS attached"; exit 1; }

mkd nonotes; rm "$w/nonotes/RELEASE_NOTES.md"
if err="$(sh "$S" "$w/nonotes" 2>&1)"; then echo "FAIL missing notes must fail"; exit 1; fi
printf '%s\n' "$err" | grep -qi 'RELEASE_NOTES' || { echo "FAIL should name the notes file: $err"; exit 1; }

mkd emptynotes; : > "$w/emptynotes/RELEASE_NOTES.md"
if sh "$S" "$w/emptynotes" >/dev/null 2>&1; then echo "FAIL: an empty notes body is the defect this exists to prevent, so empty notes must fail"; exit 1; fi

mkdir -p "$w/bare"; printf 'notes\n' > "$w/bare/RELEASE_NOTES.md"
if sh "$S" "$w/bare" >/dev/null 2>&1; then echo "FAIL: publishing nothing is a mistake, not a release -- no assets at all must fail"; exit 1; fi

mkdir -p "$w/custom"; printf 'n\n' > "$w/custom/NOTES.md"; printf 'p\n' > "$w/custom/y.pkg"
out="$(sh "$S" "$w/custom" NOTES.md)"
printf '%s\n' "$out" | grep -q 'y.pkg' || { echo "FAIL: a custom notes name must be honoured: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'NOTES.md' && { echo "FAIL custom notes attached: $out"; exit 1; }

mkd retired; printf 'xml\n' > "$w/retired/appcast.xml"
if err="$(sh "$S" "$w/retired" 2>&1)"; then echo "FAIL: appcast.xml is a retired feed name -- no installed updater polls it"; exit 1; fi
printf '%s\n' "$err" | grep -q '<short name>.xml' || { echo "FAIL: the refusal should name the feed's real shape: $err"; exit 1; }

mkd standinsig; printf 'sparkle:edSignature="%s" length="10"\n' "$STAND_IN_SIGNATURE" > "$w/standinsig/x.xml"
if err="$(sh "$S" "$w/standinsig" 2>&1)"; then echo "FAIL: an unsigned stand-in feed must never be published"; exit 1; fi
printf '%s\n' "$err" | grep -q 'x.xml' || { echo "FAIL: the refusal should name the stand-in asset: $err"; exit 1; }

mkd standinnotes; printf '%s\n\n- nothing is published from it\n' "$STAND_IN_NOTES_HEADING" > "$w/standinnotes/RELEASE_NOTES.md"
if err="$(sh "$S" "$w/standinnotes" 2>&1)"; then echo "FAIL: stand-in release notes must never be published"; exit 1; fi
printf '%s\n' "$err" | grep -qi 'RELEASE_NOTES' || { echo "FAIL: the refusal should name the notes file: $err"; exit 1; }

mkd realsigned; printf 'sparkle:edSignature="RealBase64SignatureNotAStandIn==" length="10"\n' > "$w/realsigned/x.xml"
out="$(sh "$S" "$w/realsigned")"
printf '%s\n' "$out" | grep -q 'x.xml' || { echo "FAIL: a real signed feed must still be published: $out"; exit 1; }

echo "PASS: release-assets"
