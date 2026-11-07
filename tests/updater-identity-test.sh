#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/updater-identity.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/updater-identity.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
mkdir -p "$w/repo/.mavergreen/products/widget"
printf 'Widget\n' > "$w/repo/.mavergreen/products/widget/noun"
MAVERGREEN_REPO_ROOT="$w/repo"; export MAVERGREEN_REPO_ROOT
GITHUB_REPOSITORY=Someone/widget-repo; export GITHUB_REPOSITORY
fact() { sh "$S" "$@"; }
[ "$(fact bundle-id widget)" = dev.mavergreen.widget.updater ] || fail "bundle-id is the identifier plus .updater: $(fact bundle-id widget)"
[ "$(fact agent-label widget)" = dev.mavergreen.widget-updatecheck ] || fail "agent-label is the identifier plus -updatecheck: $(fact agent-label widget)"
[ "$(fact app widget)" = "Library/Application Support/Mavergreen/widget-updater.app" ] || fail "app is the short name's updater under Application Support/Mavergreen: $(fact app widget)"
[ "$(fact feed widget)" = https://github.com/Mavergreen/widget-repo/releases/latest/download/widget.xml ] \
  || fail "feed is the repo's name under Mavergreen, whatever the owner, and <short>.xml: $(fact feed widget)"
for f in bundle-id agent-label app feed; do
  rc=0; fact "$f" gadget 2>"$w/err" >/dev/null || rc=$?
  [ "$rc" -eq 1 ] || fail "$f for an undeclared product exits 1, got $rc"
  grep -q 'declare it in .mavergreen/products/gadget/' "$w/err" || fail "$f says where to declare the product: $(cat "$w/err")"
done
mkdir -p "$w/bare/.mavergreen/products/widget"; printf 'Widget\n' > "$w/bare/.mavergreen/products/widget/noun"
rc=0; ( cd "$w/bare" && MAVERGREEN_REPO_ROOT="$w/bare" GITHUB_REPOSITORY= sh "$S" feed widget ) 2>"$w/err" >/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "feed with no repo to learn exits 2, got $rc"
grep -q GITHUB_REPOSITORY "$w/err" || fail "feed with no repo says to set GITHUB_REPOSITORY: $(cat "$w/err")"
[ "$(cd "$w/bare" && MAVERGREEN_REPO_ROOT="$w/bare" GITHUB_REPOSITORY= sh "$S" bundle-id widget)" = dev.mavergreen.widget.updater ] \
  || fail "only feed needs the repo"
for bad in "" "nope widget" "bundle-id" "bundle-id Widget" "bundle-id widget extra"; do
  rc=0; sh "$S" $bad >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "'$bad' is a usage error (2), got $rc"
done
echo "PASS: updater-identity"
