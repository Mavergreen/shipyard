#!/bin/sh
# platform: macOS-only -- pkgutil expands the ed25519 pkg
#   usage: sign_and_appcast.sh --channel-title T --version V --pkg-url URL \
#            --notes-file FILE --pkg PKG [--signer BIN] [--verifier BIN] [--min-os 10.9.5] \
#            [--pubkey B64] [--allow-key-change]  > appcast.xml
#          (SPARKLE_PRIVATE_KEY must be in the environment)
#          Signs a .pkg with the native EdDSA signer and emits its Sparkle appcast.xml to stdout, in
#          one call.
#            --signer    the ed25519-sign binary; OPTIONAL -- defaults to the prebuilt ed25519-sign
#                        fetched from the latest mavericks-ed25519 release (needs gh)
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

SIGNER=""; VERIFIER=""; PUBKEY=""; ALLOW_CHANGE=no; CHANNEL=""; VER=""; URL=""; NOTES=""; PKG=""; MINOS="${MAVERICKS_MIN_OS:-10.9.5}"
while [ $# -gt 0 ]; do
  case "$1" in
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
[ -n "$CHANNEL" ] && [ -n "$VER" ] && [ -n "$URL" ] && [ -n "$NOTES" ] && [ -n "$PKG" ] \
  || { echo "sign_and_appcast: need --channel-title --version --pkg-url --notes-file --pkg" >&2; exit 2; }
[ -f "$PKG" ] || { echo "sign_and_appcast: no pkg: $PKG" >&2; exit 1; }
printenv SPARKLE_PRIVATE_KEY | grep -q . \
  || { echo "sign_and_appcast: SPARKLE_PRIVATE_KEY not set" >&2; exit 1; }

# platform: ed25519 signatures are standard and deterministic, so which build of ed25519-sign
#           produces them does not change the output -- fetching "latest" is safe.
if [ -z "$SIGNER" ]; then
  command -v gh >/dev/null 2>&1 || { echo "sign_and_appcast: no --signer, and gh unavailable to fetch ed25519-sign" >&2; exit 1; }
  # platform: an unauthenticated `gh api` releases call is anonymous (60 req/hr) and 403s under CI
  #           load.
  if [ -z "${GH_TOKEN:-}" ] && [ -z "${GITHUB_TOKEN:-}" ] && ! gh auth status >/dev/null 2>&1; then
    echo "sign_and_appcast: gh is unauthenticated; set GH_TOKEN (e.g. GH_TOKEN: \${{ github.token }}) so the ed25519-sign fetch isn't rate-limited" >&2
    exit 1
  fi
  _dl=$(mktemp -d "${TMPDIR:-/tmp}/sign_and_appcast.XXXXXX")
  gh release download -R Mavergreen/ed25519 -p '*.pkg' -D "$_dl" \
    || { echo "sign_and_appcast: could not download the ed25519 .pkg from mavericks-ed25519 releases (is GH_TOKEN set on this step?)" >&2; exit 1; }
  pkgutil --expand-full "$_dl"/*.pkg "$_dl/x" \
    || { echo "sign_and_appcast: could not expand the ed25519 .pkg" >&2; exit 1; }
  SIGNER=$(find "$_dl/x" -type f -name ed25519-sign | head -1)
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

sh "$SELF/gen_appcast.sh" "$CHANNEL" "$VER" "$URL" "$MINOS" "$NOTES" "$ENC"
