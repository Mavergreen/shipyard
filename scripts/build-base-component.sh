#!/bin/sh
# platform: host-agnostic
#   usage: build-base-component.sh [--version V] --out COMP.pkg
#          With no --version: the installed shipyard's version, else $SHIPYARD_VERSION (install@v1 sets it
#          off macOS), else shipyard-version.sh from the checkout's git history.
#          build-base-component.sh --emit-preinstall FILE | --emit-postinstall FILE
#                                  | --emit-helper FILE | --emit-vercmp FILE  [--version V]
#          Builds dev.mavergreen.base: the mavergreen helper, mavergreen-vercmp and the paths.d/manpaths.d
#          entries, staged under /opt/mavergreen/.base/<V>/. Its preinstall creates /opt and /opt/mavergreen
#          and checks their root chain; its postinstall writes the path entries on every install and the
#          helper only over a missing or older one.
#          Every product archive carries it first (set_install_floor.sh). Each --emit-* writes one
#          stamped script: its version filled in and each `. "$SELF/lib/X.sh"` line replaced by that file.
# spec: tests/base-component-test.sh
set -eu
umask 022
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
VER=""; OUT=""; EMIT=""; WHAT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VER="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --emit-preinstall) WHAT=templates/base-preinstall.sh; EMIT="$2"; shift 2 ;;
    --emit-postinstall) WHAT=templates/base-postinstall.sh; EMIT="$2"; shift 2 ;;
    --emit-helper) WHAT=mavergreen.sh; EMIT="$2"; shift 2 ;;
    --emit-vercmp) WHAT=mavergreen-vercmp; EMIT="$2"; shift 2 ;;
    *) echo "build-base-component: unknown option $1" >&2; exit 2 ;;
  esac
done
if [ -z "$VER" ]; then
  if [ -f "$SELF/../MavergreenShipyardConfigVersion.cmake" ]; then
    VER="$(sed -n 's/.*set(PACKAGE_VERSION "\([^"]*\)").*/\1/p' "$SELF/../MavergreenShipyardConfigVersion.cmake" | head -1)"
  elif [ -n "${SHIPYARD_VERSION:-}" ]; then
    VER="$SHIPYARD_VERSION"
  else
    VER="$(sh "$SELF/shipyard-version.sh" | sed -n 's/^FULL=//p')"
  fi
fi
case "$VER" in ''|*[!0-9.]*|.*|*.|*..*) echo "build-base-component: version must be dotted numeric, got '$VER'" >&2; exit 2 ;; esac
stamp() {
  LC_ALL=C awk -v lib="$SELF/lib" -v ver="$VER" '
    /^\. "\$SELF\/lib\/[a-z-]+\.sh"$/ {
      f = $0; sub(/^\. "\$SELF\/lib\//, "", f); sub(/"$/, "", f); f = lib "/" f
      while ((r = (getline l < f)) > 0) print l
      if (r < 0) { print "build-base-component: cannot read " f > "/dev/stderr"; exit 1 }
      close(f); next
    }
    { gsub(/@MAVERGREEN_VERSION@/, ver); print }' "$SELF/$1" > "$2"
  ! grep -n 'SELF/lib' "$2" >&2 || { echo "build-base-component: $1 still sources a lib after stamping" >&2; exit 1; }
  chmod 755 "$2"
}
if [ -n "$EMIT" ]; then stamp "$WHAT" "$EMIT"; exit 0; fi
: "${OUT:?build-base-component: --out required}"
P="$(mavergreen_prefix)"
W="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-base.XXXXXX")"; trap 'rm -rf "$W"' EXIT
B="$W/root$P/.base/$VER"; mkdir -p "$B" "$W/scripts" "$(dirname "$OUT")"
stamp mavergreen.sh "$B/mavergreen"
stamp mavergreen-vercmp "$B/mavergreen-vercmp"
printf '%s/bin\n%s/sbin\n' "$P" "$P" > "$B/paths"
printf '%s/share/man\n' "$P" > "$B/manpaths"
stamp templates/base-preinstall.sh "$W/scripts/preinstall"
stamp templates/base-postinstall.sh "$W/scripts/postinstall"
sh "$SELF/build_component_pkg.sh" --root "$W/root" --identifier dev.mavergreen.base --version "$VER" \
  --install-location / --scripts "$W/scripts" --out "$OUT" >&2
