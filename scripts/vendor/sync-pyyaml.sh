#!/bin/sh
# platform: host-agnostic
#   usage: sync-pyyaml.sh [--check | --verify]
#          no argument: fetch the pinned PyYAML sdist, verify its sha256, and replace
#          scripts/vendor/yaml with its lib/yaml plus LICENSE, and rewrite yaml.sha256.
#          --verify: offline; the vendored tree matches yaml.sha256 and the pin's version.
#          --check: --verify, then the tree matches a fresh extraction of the pinned sdist.
#          Exit 0 clean, 1 on a mismatch, 2 when the sdist cannot be fetched (--check).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../mavericks_fetch.sh"
. "$here/../mavergreen-meta.sh"
pin=.mavergreen/ingredients/pyyaml
tree="$here/yaml"
list="$here/yaml.sha256"
mode="${1:-sync}"
case "$mode" in sync|--check|--verify) ;; *) echo "usage: sync-pyyaml.sh [--check | --verify]" >&2; exit 2 ;; esac

PYYAML_VERSION="$(MAVERGREEN_ROOT="$here/../.." mg_value ingredients/pyyaml/VERSION)" || PYYAML_VERSION=
PYYAML_SHA256="$(MAVERGREEN_ROOT="$here/../.." mg_value ingredients/pyyaml/SHA256)" || PYYAML_SHA256=

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else openssl dgst -sha256 "$1" | sed 's/.*= *//'
  fi
}

hashes_of() {
  (cd "$1" && find . -name __pycache__ -prune -o -type f -print | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s  %s\n' "$(sha256_of "$f")" "$f"
  done)
}

verify() {
  [ -d "$tree" ] || { echo "sync-pyyaml: $tree is missing" >&2; return 1; }
  got="$(hashes_of "$tree")"
  want="$(cat "$list")"
  [ "$got" = "$want" ] || {
    echo "sync-pyyaml: scripts/vendor/yaml differs from yaml.sha256" >&2
    printf '%s\n' "$got" | diff "$list" - >&2 || :
    return 1
  }
  have="$(sed -n "s/^__version__ *= *'\(.*\)'.*/\1/p" "$tree/__init__.py")"
  [ "$have" = "$PYYAML_VERSION" ] || {
    echo "sync-pyyaml: $pin/VERSION says $PYYAML_VERSION, scripts/vendor/yaml is $have -- run: sh scripts/vendor/sync-pyyaml.sh" >&2
    return 1
  }
}

work="$(mktemp -d "${TMPDIR:-/tmp}/sync-pyyaml.XXXXXX")"
trap 'rm -rf "$work"' EXIT

extract() {
  shipyard_curl "https://files.pythonhosted.org/packages/source/P/PyYAML/pyyaml-$PYYAML_VERSION.tar.gz" "$work/sdist.tar.gz" || return 2
  [ "$(sha256_of "$work/sdist.tar.gz")" = "$PYYAML_SHA256" ] || {
    echo "sync-pyyaml: the sdist for $PYYAML_VERSION does not match $pin/SHA256" >&2
    return 1
  }
  mkdir "$work/src" "$work/out"
  tar -xzf "$work/sdist.tar.gz" -C "$work/src"
  cp -R "$work/src/pyyaml-$PYYAML_VERSION/lib/yaml/." "$work/out/"
  cp "$work/src/pyyaml-$PYYAML_VERSION/LICENSE" "$work/out/LICENSE"
}

case "$mode" in
  --verify) verify ;;
  --check)
    verify || exit 1
    rc=0; extract || rc=$?
    [ "$rc" -eq 0 ] || exit "$rc"
    diff -r -x __pycache__ "$work/out" "$tree" >&2 || { echo "sync-pyyaml: scripts/vendor/yaml differs from the pinned sdist" >&2; exit 1; }
    ;;
  sync)
    rc=0; extract || rc=$?
    [ "$rc" -eq 0 ] || exit "$rc"
    rm -rf "$tree"
    mkdir "$tree"
    cp -R "$work/out/." "$tree/"
    find "$tree" -name __pycache__ -prune -exec rm -rf {} +
    hashes_of "$tree" > "$list"
    ;;
esac
