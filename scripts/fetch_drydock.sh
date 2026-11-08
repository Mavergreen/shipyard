#!/bin/sh
# platform: host-agnostic
#   usage: fetch_drydock.sh PIN_DIR
#          Prints the prefix of the Drydock release PIN_DIR/version names (its tag, vX.Y.Z), for this host: a
#          prefix holding bin/drydock-objc and share/drydock/objc/reference. PIN_DIR is shipyard's
#          components/drydock. MAVERGREEN_DRYDOCK_PREFIX, when set, is that prefix instead: it is checked for
#          bin/drydock-objc, and nothing is fetched. On x86_64 Linux: the release's
#          drydock-X.Y.Z-linux-x86_64.tar.gz, verified against PIN_DIR/linux-sha256 (the archive's line of the
#          release's SHA256SUMS). fetch_product_tar.sh cannot take it -- its asset is named for the tag and its
#          root must be opt/mavergreen/SHORT, while Drydock's tag has a v and its archive's root is
#          drydock-X.Y.Z/ -- so the archive is fetched with mavericks_fetch.sh's shipyard_fetch_verified, the
#          downloader fetch_product_tar.sh uses, and unpacked here. On a Mac: an installed
#          /usr/local/mavergreen/drydock at that release (MAVERGREEN_DRYDOCK_INSTALLED replaces the path), else
#          the release's drydock-X.Y.Z.pkg through fetch_product_pkg.sh and stevedore, verified against the
#          release's SHA256SUMS. A fetch is unpacked once into $MAVERGREEN_DRYDOCK_CACHE (default
#          ~/Library/Caches/mavergreen-drydock on a Mac, ~/.cache/mavergreen-drydock elsewhere)/TAG and kept.
#          MAVERGREEN_DRYDOCK_HOST (linux or mac) replaces the host's own answer. Exit 1 on a failed fetch or
#          a missing digest, 2 on a usage error or a malformed pin.
set -eu
S="$(cd "$(dirname "$0")" && pwd)"
die() { echo "fetch_drydock: $*" >&2; exit 1; }
has_objc() { [ -x "$1/bin/drydock-objc" ]; }
if [ -n "${MAVERGREEN_DRYDOCK_PREFIX:-}" ]; then
  has_objc "$MAVERGREEN_DRYDOCK_PREFIX" || die "MAVERGREEN_DRYDOCK_PREFIX $MAVERGREEN_DRYDOCK_PREFIX holds no bin/drydock-objc"
  (cd "$MAVERGREEN_DRYDOCK_PREFIX" && pwd -P); exit 0
fi
[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: fetch_drydock.sh PIN_DIR (a components/drydock directory)" >&2; exit 2; }
P="$(cd "$1" && pwd)"
[ -f "$P/version" ] || { echo "fetch_drydock: $P has no version file" >&2; exit 2; }
V="$(tr -d ' \t\n' < "$P/version")"
case "$V" in v[0-9]*) ;; *) echo "fetch_drydock: $P/version holds '$V', not a release tag (vX.Y.Z)" >&2; exit 2 ;; esac
case "$V" in *[!a-zA-Z0-9._-]*) echo "fetch_drydock: $P/version holds '$V', not a release tag (vX.Y.Z)" >&2; exit 2 ;; esac
N="${V#v}"
host="${MAVERGREEN_DRYDOCK_HOST:-}"
if [ -z "$host" ]; then
  case "$(uname -s)" in
    Linux)
      [ "$(uname -m)" = x86_64 ] || die "Drydock publishes a Linux archive for x86_64 hosts only, not $(uname -m)"
      host=linux ;;
    Darwin) host=mac ;;
    *) die "Drydock runs on Linux and on a Mac, not on $(uname -s)" ;;
  esac
fi
case "$host" in
  linux) def="$HOME/.cache/mavergreen-drydock" ;;
  mac) def="$HOME/Library/Caches/mavergreen-drydock" ;;
  *) echo "fetch_drydock: MAVERGREEN_DRYDOCK_HOST is '$host', not linux or mac" >&2; exit 2 ;;
esac
W="${MAVERGREEN_DRYDOCK_CACHE:-$def}/$V"
manifest_version() {
  awk '/<key>version<\/key>/ { getline; sub(/.*<string>/, ""); sub(/<\/string>.*/, ""); print; exit }' "$1/mavergreen.plist" 2>/dev/null
}
case "$host" in
  linux)
    asset="drydock-$N-linux-x86_64.tar.gz"
    [ -f "$P/linux-sha256" ] || die "$P has no linux-sha256 for $asset"
    sha="$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1 }' "$P/linux-sha256")"
    case "$sha" in ''|*[!0-9a-f]*) die "$P/linux-sha256 names no SHA-256 for $asset (copy its line from https://github.com/Mavergreen/drydock/releases/download/$V/SHA256SUMS)" ;; esac
    [ "${#sha}" -eq 64 ] || die "$P/linux-sha256's digest for $asset is not a SHA-256"
    d="$W/linux"
    kept() { has_objc "$d" && [ "$(cat "$d.stamp" 2>/dev/null || :)" = "$sha" ]; }
    if ! kept; then
      mkdir -p "$W"
      tmp=""; locked=""
      trap 'rm -rf ${tmp:+"$tmp"}; [ -z "$locked" ] || rmdir "$d.lock" 2>/dev/null || :' EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      # spec: scripts/fetch_product_tar.sh -- calls for one prefix take turns through a lock directory.
      waited=0
      until mkdir "$d.lock" 2>/dev/null; do
        [ "$waited" -lt "${SHIPYARD_LOCK_WAIT:-900}" ] || die "$d.lock is still held after ${waited}s; remove it if no fetch of $d is running"
        sleep 1; waited=$((waited + 1))
      done
      locked=1
    fi
    if ! kept; then
      . "$S/mavericks_fetch.sh"
      BASE="${MAVERGREEN_RELEASES:-https://github.com}/Mavergreen/drydock/releases/download/$V"
      shipyard_fetch_verified "$BASE/$asset" "$sha" "$W" "$asset" >&2 || die "could not fetch and verify $BASE/$asset"
      tmp="$(mktemp -d "$W/linux.tmp.XXXXXX")"
      tar -xzf "$W/$asset" -C "$tmp" "drydock-$N" || die "could not unpack drydock-$N from $asset"
      has_objc "$tmp/drydock-$N" || die "$asset holds no drydock-$N/bin/drydock-objc"
      rm -rf "$d" "$d.stamp"
      mv "$tmp/drydock-$N" "$d" || die "could not move the unpacked release to $d"
      printf '%s\n' "$sha" > "$d.stamp"
    fi ;;
  mac)
    inst="${MAVERGREEN_DRYDOCK_INSTALLED:-/usr/local/mavergreen/drydock}"
    if has_objc "$inst" && [ "$(manifest_version "$inst")" = "$N" ]; then
      printf '%s\n' "$inst"; exit 0
    fi
    d="$W/mac"
    sh "$S/fetch_product_pkg.sh" --asset "drydock-$N.pkg" drydock "$V" "$d" >/dev/null || die "could not fetch and verify drydock-$N.pkg" ;;
esac
has_objc "$d" || die "$d holds no bin/drydock-objc"
printf '%s\n' "$d"
