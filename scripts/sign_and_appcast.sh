#!/bin/sh
# platform: host-agnostic
#   usage: sign_and_appcast.sh --product P --feed-dir DIR --channel-title T --version V --pkg-url URL \
#            --notes-file FILE --pkg PKG [--signer BIN] [--verifier BIN] [--min-os 10.9.5] \
#            [--pubkey B64] [--allow-key-change]
#          (SPARKLE_PRIVATE_KEY must be in the environment)
#          Signs a .pkg with the native EdDSA signer and writes its Sparkle feed to DIR/P.xml, in one
#          call. P.xml is the file P's updater polls (scripts/product-name.sh feed P), so its name is
#          P's, never the caller's; nothing goes to stdout.
#            --product   the registered short name the pkg ships
#            --feed-dir  where P.xml is written; nothing is written when the run refuses
#            --signer    the ed25519-sign binary; OPTIONAL -- defaults to the prebuilt ed25519-sign
#                        fetched from the ed25519 release ed25519.pin names, verified against its SHA256SUMS:
#                        its linux-x86_64 tarball on Linux, its .pkg (read by stevedore) elsewhere.
#                        ED25519_HOST replaces `uname -s` (test-only)
#            --verifier  the ed25519-verify binary; OPTIONAL -- defaults to the one beside the signer
#            --pkg       the .pkg to sign
#            --pkg-url   the URL the enclosure will point at (the release-asset download URL)
#            --pubkey, --allow-key-change   passed to assert_update_trusted.sh
#            others      passed through to gen_appcast.sh
#          After signing, assert_update_trusted.sh proves the clients ALREADY INSTALLED will accept
#          the signature -- against the key in the live release's updater, not the repo's .pub -- and
#          no appcast is emitted if they would not.
# platform: the signer's own self-check cannot answer that question -- it verifies against the
#           public half of whatever key it was handed, so a signature made with a key no installed
#           client trusts still passes it.
# platform: a public repo's Actions logs are public, and GitHub masks only the literal secret -- a
#           shell trace prints every expanded command, and argv is visible to anything that can list
#           processes.
# spec: tests/sign_and_appcast_key.bats -- runs this script under `sh -x` and fails on any piece of
#       the key in the output. The private key reaches the signer only on its stdin
#       (`printenv SPARKLE_PRIVATE_KEY |`), never expanded into a command.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/registry-lookup.sh"

PRODUCT=""; FEEDDIR=""
SIGNER=""; VERIFIER=""; PUBKEY=""; ALLOW_CHANGE=no; CHANNEL=""; VER=""; URL=""; NOTES=""; PKG=""; MINOS="${MAVERICKS_MIN_OS:-10.9.5}"
while [ $# -gt 0 ]; do
  case "$1" in
    --product) PRODUCT="$2"; shift 2;;
    --feed-dir) FEEDDIR="${2%/}"; shift 2;;
    --signer) SIGNER="$2"; shift 2;;
    --verifier) VERIFIER="$2"; shift 2;;
    --pubkey) PUBKEY="$2"; shift 2;;
    --allow-key-change) ALLOW_CHANGE=yes; shift;;
    --channel-title) CHANNEL="$2"; shift 2;;
    --version) VER="$2"; shift 2;;
    --pkg-url) URL="$2"; shift 2;;
    --notes-file) NOTES="$2"; shift 2;;
    --pkg) PKG="$2"; shift 2;;
    --min-os) MINOS="$2"; shift 2;;
    *) echo "sign_and_appcast: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$PRODUCT" ] && [ -n "$FEEDDIR" ] && [ -n "$CHANNEL" ] && [ -n "$VER" ] && [ -n "$URL" ] && [ -n "$NOTES" ] && [ -n "$PKG" ] \
  || { echo "sign_and_appcast: need --product --feed-dir --channel-title --version --pkg-url --notes-file --pkg" >&2; exit 2; }
(registry_need sign_and_appcast identifier "$PRODUCT") || exit 2
[ -f "$PKG" ] || { echo "sign_and_appcast: no pkg: $PKG" >&2; exit 1; }
printenv SPARKLE_PRIVATE_KEY | grep -q . \
  || { echo "sign_and_appcast: SPARKLE_PRIVATE_KEY not set" >&2; exit 1; }

# spec: SKILL.md "Family conventions" check 28 -- the signer of every release is pinned in ed25519.pin
#       and verified against its release's SHA256SUMS, never whatever ed25519 release is newest.
if [ -z "$SIGNER" ]; then
  _v="$(sed -n 's/^ED25519_VERSION=//p' "$SELF/ed25519.pin")"
  [ -n "$_v" ] || { echo "sign_and_appcast: $SELF/ed25519.pin names no ED25519_VERSION" >&2; exit 1; }
  _dl=$(mktemp -d "${TMPDIR:-/tmp}/sign_and_appcast.XXXXXX")
  trap 'rm -rf "$_dl"' EXIT
  if [ "${ED25519_HOST:-$(uname -s)}" = Linux ]; then
    _asset="ed25519-$_v-linux-x86_64.tar.gz"
    _tar="$(sh "$SELF/fetch-release-pkg.sh" ed25519 "$_v" "$_asset" "$_dl")" \
      || { echo "sign_and_appcast: could not fetch and verify $_asset from ed25519 $_v; on Linux the signer comes only from that tarball, so pin an ed25519 release that ships one" >&2; exit 1; }
    mkdir "$_dl/x"
    tar -xzf "$_tar" -C "$_dl/x" opt/mavergreen/ed25519/bin/ed25519-sign opt/mavergreen/ed25519/bin/ed25519-verify \
      || { echo "sign_and_appcast: could not unpack the signer from $_asset" >&2; exit 1; }
    SIGNER="$_dl/x/opt/mavergreen/ed25519/bin/ed25519-sign"
  else
    _pkg="$(sh "$SELF/fetch-release-pkg.sh" ed25519 "$_v" "ed25519-$_v.pkg" "$_dl")" \
      || { echo "sign_and_appcast: could not fetch and verify ed25519 $_v's pkg" >&2; exit 1; }
    _stevedore="$(sh "$SELF/fetch_stevedore.sh")" || { echo "sign_and_appcast: could not fetch stevedore" >&2; exit 1; }
    "$_stevedore" expand "$_pkg" "$_dl/expanded" >/dev/null \
      || { echo "sign_and_appcast: could not expand the ed25519 .pkg" >&2; exit 1; }
    mkdir "$_dl/x"
    for _payload in "$_dl/expanded/Payload" "$_dl"/expanded/*/Payload; do
      [ -f "$_payload" ] || continue
      ( cd "$_dl/x" && gzip -dc "$_payload" | cpio -id ) >/dev/null 2>&1 \
        || { echo "sign_and_appcast: could not unpack $_payload from the ed25519 .pkg" >&2; exit 1; }
    done
    SIGNER=$(find "$_dl/x" -type f -name ed25519-sign | head -1)
  fi
  [ -n "$SIGNER" ] && chmod +x "$SIGNER"
  [ -f "$(dirname "$SIGNER")/ed25519-verify" ] && chmod +x "$(dirname "$SIGNER")/ed25519-verify"
fi
[ -x "$SIGNER" ] || { echo "sign_and_appcast: signer not executable: $SIGNER" >&2; exit 1; }
[ -n "$VERIFIER" ] || VERIFIER="$(dirname "$SIGNER")/ed25519-verify"
[ -x "$VERIFIER" ] || { echo "sign_and_appcast: no ed25519-verify at $VERIFIER (pass --verifier)" >&2; exit 1; }

# platform: ed25519-sign -f - <pkg> (key on stdin) prints the bare base64 signature.
SIG=$(printenv SPARKLE_PRIVATE_KEY | "$SIGNER" -f - "$PKG")
[ -n "$SIG" ] || { echo "sign_and_appcast: signer produced no signature" >&2; exit 1; }
set -- --pkg "$PKG" --signature "$SIG" --verifier "$VERIFIER"
[ -z "$PUBKEY" ] || set -- "$@" --pubkey "$PUBKEY"
[ "$ALLOW_CHANGE" = no ] || set -- "$@" --allow-key-change
sh "$SELF/assert_update_trusted.sh" "$@" \
  || { echo "sign_and_appcast: no appcast -- installed clients would not accept this signature" >&2; exit 1; }
LEN=$(wc -c < "$PKG" | tr -d '[:space:]')
ENC="sparkle:edSignature=\"$SIG\" length=\"$LEN\""

mkdir -p "$FEEDDIR"
_feed="$(mktemp "$FEEDDIR/.$PRODUCT.xml.XXXXXX")"
sh "$SELF/gen_appcast.sh" "$CHANNEL" "$VER" "$URL" "$MINOS" "$NOTES" "$ENC" > "$_feed" \
  || { rm -f "$_feed"; echo "sign_and_appcast: gen_appcast.sh failed; no feed written" >&2; exit 1; }
chmod 644 "$_feed"
mv "$_feed" "$FEEDDIR/$PRODUCT.xml"
echo "sign_and_appcast: wrote $FEEDDIR/$PRODUCT.xml" >&2
