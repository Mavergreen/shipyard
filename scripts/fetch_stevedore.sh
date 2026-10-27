#!/bin/sh
# platform: host-agnostic
#   usage: fetch_stevedore.sh
#          Prints the absolute path of the pinned stevedore (scripts/stevedore.pin), whose --version has
#          been checked to say "stevedore <pinned version>". An exported STEVEDORE wins, after the same
#          check, and fails when it names another version. Linux fetches the release's linux-x86_64
#          tarball, Darwin its .pkg, each verified against the release's SHA256SUMS by
#          fetch-release-pkg.sh, and keeps the binary in
#          ${STEVEDORE_CACHE:-$HOME/Library/Caches/mavergreen-pkgs/stevedore}/VERSION (Darwin) or
#          ${STEVEDORE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/mavergreen-pkgs/stevedore}/VERSION (Linux); as root (euid 0, so sudo, sudo -i and a root
#          shell alike) the same paths under root's own home from the passwd entry, never the caller's HOME, which sudo
#          may keep. STEVEDORE_EUID and STEVEDORE_ROOT_HOME replace the euid and that home (test-only). A
#          cached binary of another version is replaced. Needs no python. Exit 1 on a failed fetch, checksum
#          or version check. STEVEDORE_RELEASES replaces https://github.com (the tests serve file://). It
#          never reads MAVERGREEN_RELEASES or MAVERGREEN_PKG_CACHE, which belong to the product being
#          fetched and may point at a fixture tree that holds no stevedore. STEVEDORE_HOST
#          replaces `uname -s` and is a test-only override, so a macOS host can exercise the Linux branch.
#          Runs on 10.9: pkgutil --expand only, never --expand-full.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
V="$(sed -n 's/^STEVEDORE_VERSION=//p' "$SELF/stevedore.pin")"
case "$V" in ''|latest|*/*|*[!0-9A-Za-z._-]*) echo "fetch_stevedore: $SELF/stevedore.pin names no STEVEDORE_VERSION" >&2; exit 1 ;; esac

confirm() {
  [ -x "$1" ] && [ "$("$1" --version 2>/dev/null || :)" = "stevedore $V" ]
}
absolute() { printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"; }

if [ -n "${STEVEDORE:-}" ]; then
  confirm "$STEVEDORE" || { echo "fetch_stevedore: $STEVEDORE does not report stevedore $V" >&2; exit 1; }
  absolute "$STEVEDORE"; exit 0
fi

OS="${STEVEDORE_HOST:-$(uname -s)}"
if [ "${STEVEDORE_EUID:-$(id -u)}" = 0 ]; then
  home="${STEVEDORE_ROOT_HOME:-$(eval "printf %s ~root")}"
  xdg="$home/.cache"
else
  home="$HOME"
  xdg="${XDG_CACHE_HOME:-$HOME/.cache}"
fi
case "$OS" in
  Darwin) default="$home/Library/Caches/mavergreen-pkgs/stevedore" ;;
  Linux) default="$xdg/mavergreen-pkgs/stevedore" ;;
  *) echo "fetch_stevedore: no stevedore release for $OS" >&2; exit 1 ;;
esac
CACHE="${STEVEDORE_CACHE:-$default}/$V"
BIN="$CACHE/stevedore"
if confirm "$BIN"; then absolute "$BIN"; exit 0; fi

mkdir -p "$CACHE"
MAVERGREEN_RELEASES="${STEVEDORE_RELEASES:-https://github.com}"; export MAVERGREEN_RELEASES
tmp="$(mktemp -d "$CACHE.tmp.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
if [ "$OS" = Linux ]; then
  member=opt/mavergreen/stevedore/bin/stevedore
  asset="stevedore-$V-linux-x86_64.tar.gz"
  file="$(sh "$SELF/fetch-release-pkg.sh" stevedore "$V" "$asset" "$tmp/dl")" || exit 1
  tar -xzf "$file" -C "$tmp" "$member" || { echo "fetch_stevedore: could not unpack $member from $asset" >&2; exit 1; }
  src="$tmp/$member"
else
  member=usr/local/mavergreen/stevedore/bin/stevedore
  asset="stevedore-$V.pkg"
  file="$(sh "$SELF/fetch-release-pkg.sh" stevedore "$V" "$asset" "$tmp/dl")" || exit 1
  # platform: guarded macOS-only call -- this branch runs only when OS is Darwin
  pkgutil --expand "$file" "$tmp/expanded" >&2 || { echo "fetch_stevedore: could not expand $asset" >&2; exit 1; }
  mkdir "$tmp/payload"
  for payload in "$tmp/expanded/Payload" "$tmp"/expanded/*/Payload; do
    [ -f "$payload" ] || continue
    ( cd "$tmp/payload" && gzip -dc "$payload" | cpio -id --quiet 2>/dev/null ) || :
  done
  src="$tmp/payload/$member"
fi
[ -f "$src" ] || { echo "fetch_stevedore: $asset installs no $member" >&2; exit 1; }
cp "$src" "$tmp/stevedore" && chmod +x "$tmp/stevedore"
confirm "$tmp/stevedore" || { echo "fetch_stevedore: $asset's stevedore does not report stevedore $V" >&2; exit 1; }
mv -f "$tmp/stevedore" "$BIN"
absolute "$BIN"
