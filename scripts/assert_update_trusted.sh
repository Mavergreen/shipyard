#!/bin/sh
# platform: host-agnostic
#   usage: assert_update_trusted.sh --pkg PKG --signature SIG --verifier ED25519_VERIFY
#                                   [--pubkey B64] [--allow-key-change]
#          Messages go to stderr. Exit 0 trusted, 1 not, 2 usage.
#          --pubkey B64          the pkg installs no updater; name the key installed clients trust
#                                 yourself.
#          --allow-key-change    a deliberate hard switch that installed clients will NOT follow;
#                                 the signature must then verify against the new key. Say why in the
#                                 workflow that passes it.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "A signature must
#       satisfy the clients ALREADY INSTALLED" -- a Sparkle client verifies against the SUPublicEDKey
#       of the updater it HAS, which came from the pkg the feed offered LAST TIME, not the repo's
#       .pub and not the key the new pkg ships; ed25519-sign's own self-check can't see a mismatch
#       (it only checks against the public half of the key it was handed). So: read SUFeedURL from
#       the new pkg's updater, fetch that live feed's enclosure pkg, and verify SIG against THAT
#       pkg's updater key. No live feed yet (404, or a file:// that isn't there) is a first release,
#       checked against the new pkg's own key; a feed that can't be READ fails closed rather than
#       guess "first release". A new pkg shipping a different key, signed by the live one, is a
#       bridge release -- trusted, with a notice that the NEXT release must be signed by the new key.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
chk_ran update-trusted

PKG=""; SIG=""; VERIFIER=""; PUBKEY=""; ALLOW_CHANGE=no
while [ $# -gt 0 ]; do
  case "$1" in
    --pkg) PKG="$2"; shift 2;;
    --signature) SIG="$2"; shift 2;;
    --verifier) VERIFIER="$2"; shift 2;;
    --pubkey) PUBKEY="$2"; shift 2;;
    --allow-key-change) ALLOW_CHANGE=yes; shift;;
    *) echo "assert_update_trusted: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$PKG" ] && [ -n "$SIG" ] && [ -n "$VERIFIER" ] \
  || { echo "assert_update_trusted: need --pkg --signature --verifier" >&2; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/assert_update_trusted.XXXXXX")"; trap 'rm -rf "$T"' EXIT
say() { echo "assert_update_trusted: $*" >&2; }
bad() {  # $1 = what is wrong, $2 = the fix
  chk_fail update-trusted "the signature verifies against the key installed clients already trust" "$1" "$2"
  exit 1
}
sign_fix="sign with the private key whose public half the live release's updater ships; to move clients to a new key, ship it in a release signed by the old one (a bridge), and to abandon them pass --allow-key-change"
field() { sed -n "s/^$1=//p" "$2"; }
# spec: tests/assert_update_trusted.bats -- status 0 when SIG over PKG verifies against KEY, 1 when
#       it does not. An ed25519-verify that cannot check at all (exit 2: a malformed key or
#       signature) is neither answer, so that ends the run.
verifies() {
  set +e; "$VERIFIER" -p "$1" "$PKG" "$SIG" >/dev/null 2>"$T/verify.err"; rc=$?; set -e
  case "$rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) bad "could not check the signature (ed25519-verify exit $rc): $(cat "$T/verify.err")" "pass a well-formed key and signature" ;;
  esac
}

if [ -n "$PUBKEY" ]; then
  verifies "$PUBKEY" && { say "ok -- signed by $PUBKEY, the key named by --pubkey"; exit 0; }
  bad "the signature does not verify against $PUBKEY, the key named by --pubkey" "$sign_fix"
fi

sh "$SELF/updater_pubkey.sh" "$PKG" > "$T/new" \
  || bad "$PKG has no readable Sparkle updater" "pass --pubkey <the key installed clients trust>"
NEW_KEY="$(field SUPublicEDKey "$T/new")"
FEED="$(field SUFeedURL "$T/new")"
[ -n "$FEED" ] || bad "the updater in $PKG names no SUFeedURL, so there is no live release to ask" "give the updater a SUFeedURL"

# platform: not -f: a 404 is an answer ("no feed yet"), not a failure. curl reports HTTP 000 for
#           file://.
set +e
code="$(curl -sSL -o "$T/feed.xml" -w '%{http_code}' "$FEED" 2>"$T/curl.err")"; rc=$?
set -e
if { [ "$rc" -eq 0 ] && [ "$code" = 404 ]; } || [ "$rc" -eq 37 ]; then
  verifies "$NEW_KEY" && {
    say "ok -- first release (no live feed at $FEED): signed by $NEW_KEY, the key this pkg's updater ships"
    exit 0
  }
  bad "first release, and the signature does not verify against $NEW_KEY, the key this pkg's updater ships: SPARKLE_PRIVATE_KEY is not its private half, so every install would reject every update signed with it" \
    "set SPARKLE_PRIVATE_KEY to the private half of $NEW_KEY"
fi
if [ "$rc" -ne 0 ] || { [ "$code" != 200 ] && [ "$code" != 000 ]; }; then
  bad "cannot read the live feed $FEED (curl exit $rc, HTTP $code): $(cat "$T/curl.err"), and refusing to guess which key installed clients trust" \
    "check the feed URL and the network, then re-run"
fi

URL="$(sed -n 's/.*<enclosure[^>]* url="\([^"]*\)".*/\1/p' "$T/feed.xml" | head -1)"
[ -n "$URL" ] || bad "the live feed $FEED offers no enclosure, so there is no telling which key installed clients trust" "repair the live feed, or pass --pubkey <the key installed clients trust>"
curl -fsSL -o "$T/live.pkg" "$URL" 2>"$T/curl.err" \
  || bad "cannot download the live release's pkg $URL: $(cat "$T/curl.err")" "check the network, then re-run"
sh "$SELF/updater_pubkey.sh" "$T/live.pkg" > "$T/live" \
  || bad "the live release's pkg ($URL) has no readable Sparkle updater" "pass --pubkey <the key installed clients trust>"
LIVE_KEY="$(field SUPublicEDKey "$T/live")"

if verifies "$LIVE_KEY"; then
  if [ "$NEW_KEY" = "$LIVE_KEY" ]; then
    say "ok -- signed by $LIVE_KEY, the key installed updaters trust"
  else
    say "ok -- signed by $LIVE_KEY, the key installed updaters trust. This release moves them to $NEW_KEY:"
    say "sign the next release with ITS private key (change SPARKLE_PRIVATE_KEY once this one is published)"
  fi
  exit 0
fi
if [ "$ALLOW_CHANGE" = yes ]; then
  verifies "$NEW_KEY" \
    || bad "--allow-key-change, but the signature does not verify against $NEW_KEY (this pkg's key) either" "sign with the private half of $NEW_KEY"
  say "WARNING (--allow-key-change): signed by $NEW_KEY; clients on the live release trust $LIVE_KEY"
  say "and will not accept this update"
  exit 0
fi
bad "installed updaters trust $LIVE_KEY (from the live release's pkg, $URL), and this signature does not verify against it, so they would reject this update" "$sign_fix"
