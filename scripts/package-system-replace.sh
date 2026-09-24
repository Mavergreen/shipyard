#!/bin/sh
#   usage: package-system-replace.sh --product P --title T --version V --out PKG [--base-version V]
#          package-system-replace.sh --emit-postinstall FILE --product P
#          The optional second pkg of a product whose manifest declares `replaces`: installing it
#          swaps the declared system paths for the product's own, on 10.9 only.
# spec: tests/package-system-replace-test.sh -- the generated postinstall only ever runs the
#       helper's own system-replace, which already validates every entry and refuses a volume
#       that isn't 10.9; this script's own job is just wrapping that call as a payload-free
#       component behind set_install_floor.sh's base-first product archive.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
P=""; TITLE=""; VER=""; OUT=""; BASEVER=""; EMIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --product|--title|--version|--out|--base-version|--emit-postinstall)
      [ $# -ge 2 ] || { echo "package-system-replace: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --product) P="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --version) VER="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --base-version) BASEVER="$2"; shift 2 ;;
    --emit-postinstall) EMIT="$2"; shift 2 ;;
    *) echo "package-system-replace: unknown option $1" >&2; exit 2 ;;
  esac
done
case "$P" in
  [a-z0-9][a-z0-9-]*) : ;;
  *) echo "package-system-replace: not a product name: '$P'" >&2; exit 2 ;;
esac
ID="$(sh "$SELF/product-name.sh" identifier "$P")" || { echo "package-system-replace: $P is not registered" >&2; exit 1; }
emit() {
  { printf '#!/bin/sh\n'
    printf '[ -n "${3:-}" ] || { echo "%s: system-replace got no target volume" >&2; exit 1; }\n' "$P"
    printf 'ROOT="${3%%/}"\n'
    printf '[ -x "$ROOT/usr/local/bin/mavergreen" ] || { echo "%s: install %s before its System Replace" >&2; exit 1; }\n' "$P" "$P"
    printf 'exec "$ROOT/usr/local/bin/mavergreen" --root "$ROOT/" system-replace %s\n' "$P"
  } > "$1"; chmod +x "$1"
}
if [ -n "$EMIT" ]; then emit "$EMIT"; exit 0; fi
[ -n "$TITLE" ] && [ -n "$VER" ] && [ -n "$OUT" ] || { echo "package-system-replace: need --title --version --out" >&2; exit 2; }
W="$(mktemp -d "${TMPDIR:-/tmp}/system-replace.XXXXXX")"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/root" "$W/scripts" "$W/c" "$(dirname "$OUT")"; emit "$W/scripts/postinstall"
pkgbuild --quiet --nopayload --scripts "$W/scripts" --identifier "$ID.system-replace" --version "$VER" "$W/c/system-replace.pkg"
set -- --identifier "$ID.system-replace" --title "$TITLE" --component "$W/c/system-replace.pkg" --out "$OUT" --require-scripts --host-arch x86_64,arm64
[ -z "$BASEVER" ] || set -- "$@" --base-version "$BASEVER"
sh "$SELF/set_install_floor.sh" "$@" >&2
