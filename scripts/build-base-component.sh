#!/bin/sh
#   usage: build-base-component.sh [--version V] --out COMP.pkg
#          build-base-component.sh --emit-postinstall FILE --version V
#          Builds dev.mavergreen.base: the mavergreen helper and the paths.d/manpaths.d entries,
#          staged under /usr/local/mavergreen/.base/<V>/ and installed by its postinstall only over a
#          missing or older helper. Every product archive carries it first (set_install_floor.sh).
# spec: tests/base-component-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
VER=""; OUT=""; EMIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VER="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --emit-postinstall) EMIT="$2"; shift 2 ;;
    *) echo "build-base-component: unknown option $1" >&2; exit 2 ;;
  esac
done
if [ -z "$VER" ]; then
  if [ -f "$SELF/../MavericksShipyardConfigVersion.cmake" ]; then
    VER="$(sed -n 's/.*set(PACKAGE_VERSION "\([^"]*\)").*/\1/p' "$SELF/../MavericksShipyardConfigVersion.cmake" | head -1)"
  else
    VER="$(sh "$SELF/shipyard-version.sh" | sed -n 's/^FULL=//p')"
  fi
fi
case "$VER" in ''|*[!0-9.]*|.*|*.|*..*) echo "build-base-component: version must be dotted numeric, got '$VER'" >&2; exit 2 ;; esac
render_post() { sed "s/@MAVERGREEN_VERSION@/$VER/" "$SELF/templates/base-postinstall.sh" > "$1"; chmod +x "$1"; }
if [ -n "$EMIT" ]; then render_post "$EMIT"; exit 0; fi
: "${OUT:?build-base-component: --out required}"
W="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-base.XXXXXX")"; trap 'rm -rf "$W"' EXIT
B="$W/root/usr/local/mavergreen/.base/$VER"; mkdir -p "$B" "$W/scripts" "$(dirname "$OUT")"
sed "s/@MAVERGREEN_VERSION@/$VER/" "$SELF/mavergreen.sh" > "$B/mavergreen"; chmod 755 "$B/mavergreen"
printf '/usr/local/mavergreen/bin\n/usr/local/mavergreen/sbin\n' > "$B/paths"
printf '/usr/local/mavergreen/share/man\n' > "$B/manpaths"
render_post "$W/scripts/postinstall"
sh "$SELF/build_component_pkg.sh" --root "$W/root" --identifier dev.mavergreen.base --version "$VER" \
  --install-location / --scripts "$W/scripts" --out "$OUT" >&2
