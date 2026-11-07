#!/bin/sh
# platform: host-agnostic
#   usage: package-system-replace.sh --product P --version V --dist DIR [--base-version V]
#          package-system-replace.sh --emit-postinstall FILE --product P
#          The optional second pkg of a product whose manifest declares `replaces`: installing it
#          swaps the declared system paths for the product's own, on 10.9 only. Prints the path of
#          DIR/P-system-replace-V.pkg; set_install_floor.sh --system-replace derives its names.
# spec: tests/package-system-replace-test.sh -- the generated postinstall only ever runs the
#       helper's own system-replace, which already validates every entry and refuses a volume
#       that isn't 10.9; this script's own job is just wrapping that call as a payload-free
#       component behind set_install_floor.sh's base-first product archive.
set -eu
umask 022
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
P=""; VER=""; DISTDIR=""; BASEVER=""; EMIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --title) echo "package-system-replace: --title is refused; write .mavergreen/products/<short>/noun" >&2; exit 2 ;;
    --out) echo "package-system-replace: --out is refused; the filename is derived, <short>-system-replace-<version>.pkg; pass --dist" >&2; exit 2 ;;
    --product|--version|--dist|--base-version|--emit-postinstall)
      [ $# -ge 2 ] || { echo "package-system-replace: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --product) P="$2"; shift 2 ;;
    --version) VER="$2"; shift 2 ;;
    --dist) DISTDIR="$2"; shift 2 ;;
    --base-version) BASEVER="$2"; shift 2 ;;
    --emit-postinstall) EMIT="$2"; shift 2 ;;
    *) echo "package-system-replace: unknown option $1" >&2; exit 2 ;;
  esac
done
case "$P" in
  ''|-*|*[!a-z0-9-]*) echo "package-system-replace: not a product name: '$P'" >&2; exit 2 ;;
esac
ID="$(mavergreen_name identifier "$P")" || exit $?
emit() {
  { printf '#!/bin/sh\n'
    printf '[ -n "${3:-}" ] || { echo "%s: system-replace got no target volume" >&2; exit 1; }\n' "$P"
    printf 'ROOT="${3%%/}"\n'
    printf '[ -x "$ROOT/usr/local/bin/mavergreen" ] || { echo "%s: install %s before its System Replace" >&2; exit 1; }\n' "$P" "$P"
    printf 'exec "$ROOT/usr/local/bin/mavergreen" --root "$ROOT/" system-replace %s\n' "$P"
  } > "$1"; chmod +x "$1"
}
if [ -n "$EMIT" ]; then emit "$EMIT"; exit 0; fi
[ -n "$VER" ] && [ -n "$DISTDIR" ] || { echo "package-system-replace: need --version --dist" >&2; exit 2; }
W="$(mktemp -d "${TMPDIR:-/tmp}/system-replace.XXXXXX")"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/root" "$W/scripts" "$W/c"; emit "$W/scripts/postinstall"
EPOCH="$(sh "$SELF/source-date-epoch.sh")"
STEVEDORE="$(sh "$SELF/fetch_stevedore.sh")"
"$STEVEDORE" component --nopayload --scripts "$W/scripts" --identifier "$ID.system-replace" --version "$VER" \
  --install-location / --mtime "$EPOCH" --out "$W/c/system-replace.pkg" >&2
set -- --short "$P" --system-replace --version "$VER" --component "$W/c/system-replace.pkg" --dist "$DISTDIR" --require-scripts --host-arch x86_64,arm64
[ -z "$BASEVER" ] || set -- "$@" --base-version "$BASEVER"
sh "$SELF/set_install_floor.sh" "$@"
