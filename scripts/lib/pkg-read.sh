#!/bin/sh
# platform: host-agnostic
#   usage: . pkg-read.sh     (sourced; defines the af_* functions)
#          af_extract <archive> <dir>      extracts a .pkg (a xar), a gzip'd cpio Payload or Scripts,
#                                          or a tarball into the existing <dir>; non-zero when it cannot
#          af_unpack_payload <Payload>     extracts it to <its directory>.root, and sets AF_ROOT to that
#                                          tree and AF_LOC to its install-location ("" or "a/b/")
#          af_macho_kind <file>            prints strict (a Mach-O magic), loose (a fat magic or an ar
#                                          archive, Mach-O only if the readers say so) or nothing
#          af_enc                          stdin to stdout, with "%" as %25 and " " as %20
#          af_rm <dir>                     removes a tree extraction left read-only
#          Returns 2 and says so when no bsdtar is found.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact conformance" --
#       one reader of a built pkg on every host: bsdtar reads the xar container and the gzip'd cpio of
#       every family pkg (10.9's bsdtar 2.8.3 included), so pkgutil leaves the checks. This function is
#       the seam: a host that needed another extractor would change it here only.

af_bsdtar() {
  if [ -n "${BSDTAR:-}" ]; then _ab="$BSDTAR"; else _ab="$(command -v bsdtar 2>/dev/null || true)"; fi
  if [ -z "$_ab" ] && tar --version 2>/dev/null | grep -Eqi 'bsdtar|libarchive'; then _ab="$(command -v tar)"; fi
  [ -n "$_ab" ] && [ -x "$_ab" ] || { echo "pkg-read: no bsdtar found${BSDTAR:+ at BSDTAR=$BSDTAR} -- install libarchive-tools, or set BSDTAR to its path" >&2; return 2; }
  printf '%s\n' "$_ab"
}

af_extract() {
  _ae_tool="$(af_bsdtar 2>/dev/null)" || return 2
  "$_ae_tool" -xf "$1" -C "$2" >/dev/null 2>&1
}

af_unpack_payload() {
  _au_dir="${1%/Payload}"
  AF_LOC="$(sed -n '/<pkg-info/ s/.*[[:space:]]install-location="\([^"]*\)".*/\1/p' "$_au_dir/PackageInfo" 2>/dev/null | head -1)"
  AF_LOC="${AF_LOC:-/}"; AF_LOC="${AF_LOC#/}"; AF_LOC="${AF_LOC%/}"
  [ -z "$AF_LOC" ] || AF_LOC="$AF_LOC/"
  AF_ROOT="$_au_dir.root"
  mkdir -p "$AF_ROOT"
  [ -s "$1" ] || return 0
  af_extract "$1" "$AF_ROOT"
}

af_macho_kind() {
  case "$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')" in
    cffaedfe|cefaedfe|feedfacf|feedface) echo strict ;;
    cafebabe|cafebabf|213c6172) echo loose ;;
  esac
}

af_enc() { sed -e 's/%/%25/g' -e 's/ /%20/g'; }

af_rm() { chmod -R u+rwX "$1" 2>/dev/null || :; rm -rf "$1"; }
