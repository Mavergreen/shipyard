#!/bin/sh
# platform: host-agnostic
#   usage: . pkg-tree.sh     (sourced after $SELF names the scripts directory; defines the af_* functions)
#          af_pkg_tree <pkg> <scratch>     expands a .pkg with stevedore into AF_TREE, once: under
#                                          shipyard-check --dist ($SHIPYARD_CHECK_PKGS set) into
#                                          $SHIPYARD_CHECK_PKGS/<name> and every later reader finds it
#                                          there; otherwise into <scratch>/<name>. Returns 3, AF_WHY set,
#                                          when stevedore cannot be fetched; 1 when it cannot expand the pkg.
#          af_unpack_payload <Payload>     extracts it to <its directory>.root (once), and sets AF_ROOT to
#                                          that tree and AF_LOC to its install-location ("" or "a/b/")
#          af_unpack_scripts <Scripts> <dir>  extracts a component's Scripts archive into the existing <dir>
#          af_extract <tarball> <dir>      extracts a release tarball into the existing <dir>
#          af_macho_kind <file>            prints strict (a Mach-O magic, or a fat one af_fat_macho
#                                          accepts), loose (an ar archive, Mach-O only if the readers say
#                                          so) or nothing (a Java class file shares the fat magic)
#          af_fat_macho <file>             0 when the file is a fat Mach-O: the fat magic, then an arch
#                                          count from 1 to 29, where a class file has its version (45+)
#          af_enc                          stdin to stdout, with "%" as %25 and " " as %20
#          af_rm <dir>                     removes a tree extraction left read-only
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact conformance" --
#       one reader of a built pkg on every host: stevedore expands the xar, whose Payload and Scripts
#       are gzip'd cpio archives, so neither bsdtar nor pkgutil is needed.

af_stevedore() {
  [ -z "${AF_STEVEDORE_OK:-}" ] || return 0
  STEVEDORE="$(sh "$SELF/fetch_stevedore.sh" 2>/dev/null)" || {
    AF_WHY="stevedore, which reads the pkgs, cannot be fetched ($(sh "$SELF/fetch_stevedore.sh" 2>&1 >/dev/null | tail -1))"
    return 1
  }
  export STEVEDORE
  AF_STEVEDORE_OK=1
}

af_pkg_tree() {
  af_stevedore || return 3
  _at_name="${1##*/}"
  if [ -n "${SHIPYARD_CHECK_PKGS:-}" ]; then AF_TREE="$SHIPYARD_CHECK_PKGS/$_at_name"; else AF_TREE="$2/$_at_name"; fi
  [ ! -d "$AF_TREE" ] || return 0
  mkdir -p "${AF_TREE%/*}"
  if "$STEVEDORE" expand "$1" "$AF_TREE.part" >/dev/null 2>&1; then
    mv "$AF_TREE.part" "$AF_TREE"
  else
    af_rm "$AF_TREE.part"
    return 1
  fi
}

af_cpio() {
  _ac_tmp="$2.cpio"
  gzip -dc "$1" > "$_ac_tmp" 2>/dev/null || { rm -f "$_ac_tmp"; return 1; }
  _ac_rc=0; ( cd "$2" && cpio -id < "$_ac_tmp" >/dev/null 2>&1 ) || _ac_rc=$?
  rm -f "$_ac_tmp"
  return "$_ac_rc"
}

af_extract() {
  tar -xf "$1" -C "$2" >/dev/null 2>&1
}

af_unpack_scripts() {
  af_cpio "$1" "$2"
}

af_unpack_payload() {
  _au_dir="${1%/Payload}"
  AF_LOC="$(sed -n '/<pkg-info/ s/.*[[:space:]]install-location="\([^"]*\)".*/\1/p' "$_au_dir/PackageInfo" 2>/dev/null | head -1)"
  AF_LOC="${AF_LOC:-/}"; AF_LOC="${AF_LOC#/}"; AF_LOC="${AF_LOC%/}"
  [ -z "$AF_LOC" ] || AF_LOC="$AF_LOC/"
  AF_ROOT="$_au_dir.root"
  [ ! -f "$AF_ROOT.done" ] || return 0
  mkdir -p "$AF_ROOT"
  if [ -s "$1" ]; then af_cpio "$1" "$AF_ROOT" || return 1; fi
  : > "$AF_ROOT.done"
}

af_fat_macho() {
  _afm="$(head -c 8 "$1" | od -An -tx1 | tr -d ' \n')"
  case "$_afm" in cafebabe????????|cafebabf????????) ;; *) return 1 ;; esac
  _afm=$((0x${_afm#cafebab?}))
  [ "$_afm" -ge 1 ] && [ "$_afm" -le 29 ]
}

af_macho_kind() {
  case "$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')" in
    cffaedfe|cefaedfe|feedfacf|feedface) echo strict ;;
    cafebabe|cafebabf) if af_fat_macho "$1"; then echo strict; fi ;;
    213c6172) echo loose ;;
  esac
}

af_enc() { sed -e 's/%/%25/g' -e 's/ /%20/g'; }

af_rm() { chmod -R u+rwX "$1" 2>/dev/null || :; rm -rf "$1"; }
