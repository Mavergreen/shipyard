#!/bin/sh
# platform: host-agnostic
#   usage: assert_update_trusted.sh --pkg PKG --signature SIG --verifier ED25519_VERIFY [--key FILE]
#          Does SIG over PKG verify against the family key, the public key every installed client
#          trusts? --key defaults to keys/feed-ed25519.pub beside these scripts. Nothing is fetched.
#          Messages go to stderr. Exit 0 trusted, 1 not, 2 usage.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
chk_ran update-trusted

PKG=""; SIG=""; VERIFIER=""; KEYFILE="${SELF%/*}/keys/feed-ed25519.pub"
while [ $# -gt 0 ]; do
  case "$1" in
    --pkg) PKG="$2"; shift 2;;
    --signature) SIG="$2"; shift 2;;
    --verifier) VERIFIER="$2"; shift 2;;
    --key) KEYFILE="$2"; shift 2;;
    --pubkey|--allow-key-change)
      echo "assert_update_trusted: $1 is refused: the trusted key is keys/feed-ed25519.pub; rotate it there" >&2; exit 2;;
    *) echo "assert_update_trusted: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$PKG" ] && [ -n "$SIG" ] && [ -n "$VERIFIER" ] \
  || { echo "assert_update_trusted: need --pkg --signature --verifier" >&2; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/assert_update_trusted.XXXXXX")"; trap 'rm -rf "$T"' EXIT
bad() {  # $1 = what is wrong, $2 = the fix
  chk_fail update-trusted "the signature verifies against the family key" "$1" "$2"
  exit 1
}
[ -r "$KEYFILE" ] || bad "there is no family key at $KEYFILE" "restore keys/feed-ed25519.pub in shipyard"
KEY="$(tr -d '[:space:]' < "$KEYFILE")"
[ -n "$KEY" ] || bad "the family key file $KEYFILE is empty" "restore keys/feed-ed25519.pub in shipyard"

set +e; "$VERIFIER" -p "$KEY" "$PKG" "$SIG" >/dev/null 2>"$T/verify.err"; rc=$?; set -e
case "$rc" in
  0) echo "assert_update_trusted: ok -- signed by $KEY, the family key ($KEYFILE)" >&2; exit 0 ;;
  1) bad "the signature does not verify against $KEY, the family key ($KEYFILE), so installed clients would reject this update" \
       "set SPARKLE_PRIVATE_KEY to the private half of keys/feed-ed25519.pub; a rotation is a commit to that file" ;;
  *) bad "could not check the signature (ed25519-verify exit $rc): $(cat "$T/verify.err")" "pass a well-formed key and signature" ;;
esac
