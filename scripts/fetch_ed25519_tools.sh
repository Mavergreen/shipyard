#!/bin/sh
# platform: host-agnostic -- the Linux tarball on Linux, the pkg read with stevedore elsewhere
#   usage: fetch_ed25519_tools.sh DIR
#          Fetches the ed25519 release ed25519.pin names, verified against its SHA256SUMS, and unpacks
#          it under DIR. Prints the directory holding ed25519-sign and ed25519-verify (and
#          ed25519-keygen). ED25519_HOST replaces `uname -s` (test-only).
# spec: SKILL.md "Family conventions" check 28 -- the signer of every release is pinned in ed25519.pin
#       and verified against its release's SHA256SUMS, never whatever ed25519 release is newest.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 1 ] || { echo "usage: fetch_ed25519_tools.sh DIR" >&2; exit 2; }
_dl="$1"
_v="$(sed -n 's/^ED25519_VERSION=//p' "$SELF/ed25519.pin")"
[ -n "$_v" ] || { echo "fetch_ed25519_tools: $SELF/ed25519.pin names no ED25519_VERSION" >&2; exit 1; }
mkdir -p "$_dl/x"
if [ "${ED25519_HOST:-$(uname -s)}" = Linux ]; then
  _asset="ed25519-$_v-linux-x86_64.tar.gz"
  _tar="$(sh "$SELF/fetch-release-pkg.sh" ed25519 "$_v" "$_asset" "$_dl")" \
    || { echo "fetch_ed25519_tools: could not fetch and verify $_asset from ed25519 $_v; on Linux the signer comes only from that tarball, so pin an ed25519 release that ships one" >&2; exit 1; }
  tar -xzf "$_tar" -C "$_dl/x" opt/mavergreen/ed25519/bin \
    || { echo "fetch_ed25519_tools: could not unpack the signer from $_asset" >&2; exit 1; }
  _bin="$_dl/x/opt/mavergreen/ed25519/bin"
else
  _pkg="$(sh "$SELF/fetch-release-pkg.sh" ed25519 "$_v" "ed25519-$_v.pkg" "$_dl")" \
    || { echo "fetch_ed25519_tools: could not fetch and verify ed25519 $_v's pkg" >&2; exit 1; }
  _stevedore="$(sh "$SELF/fetch_stevedore.sh")" || { echo "fetch_ed25519_tools: could not fetch stevedore" >&2; exit 1; }
  "$_stevedore" expand "$_pkg" "$_dl/expanded" >/dev/null \
    || { echo "fetch_ed25519_tools: could not expand the ed25519 .pkg" >&2; exit 1; }
  for _payload in "$_dl/expanded/Payload" "$_dl"/expanded/*/Payload; do
    [ -f "$_payload" ] || continue
    ( cd "$_dl/x" && gzip -dc "$_payload" | cpio -id ) >/dev/null 2>&1 \
      || { echo "fetch_ed25519_tools: could not unpack $_payload from the ed25519 .pkg" >&2; exit 1; }
  done
  _s="$(find "$_dl/x" -type f -name ed25519-sign | head -1)"
  [ -n "$_s" ] || { echo "fetch_ed25519_tools: no ed25519-sign in the ed25519 $_v release's pkg" >&2; exit 1; }
  _bin="$(dirname "$_s")"
fi
[ -f "$_bin/ed25519-sign" ] || { echo "fetch_ed25519_tools: no ed25519-sign in the ed25519 $_v release" >&2; exit 1; }
chmod +x "$_bin"/ed25519-*
printf '%s\n' "$_bin"
