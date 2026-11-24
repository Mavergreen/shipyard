# platform: host-agnostic
#   usage: . scripts/lib/standalone-tree.sh
#          shipyard_standalone_top ARCHIVE     ARCHIVE's basename, SHORT-VERSION-macos-ARCH.tar.gz (ARCH
#                                              universal, x86_64 or arm64; SHORT runs to the first hyphen
#                                              before a digit), prints "TOP SHORT", TOP its one top directory
#                                              SHORT-VERSION; 1 for any other name
#          shipyard_standalone_pkg_path SHORT REL
#                                              the pkg's path, relative to /, for REL, relative to the
#                                              archive's TOP: <Name>.app at the top and what it holds go to
#                                              Applications/, everything else to the product's tree
#                                              usr/local/mavergreen/SHORT/; an empty REL prints that tree
#          shipyard_standalone_entry_pkg_path ARCHIVE ENTRY
#                                              the pkg's path for ENTRY, a path inside ARCHIVE that starts
#                                              with its TOP/; 1, printing nothing, for any other entry or name
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Standalone archive" -- the archive
#       is the pkg's tree; stage_pkg_from_archive.sh places the tree and its apps by these, and conformance
#       matches deviations against an archive entry by them.

shipyard_standalone_top() {
  case "$1" in
    *-macos-universal.tar.gz|*-macos-x86_64.tar.gz|*-macos-arm64.tar.gz) _st_top="${1%-macos-*.tar.gz}" ;;
    *) return 1 ;;
  esac
  _st_short="$(printf '%s\n' "$_st_top" | sed 's/-[0-9].*//')"
  case "$_st_short" in ''|-*|*[!a-z0-9-]*) return 1 ;; esac
  [ "$_st_short" != "$_st_top" ] || return 1
  printf '%s %s\n' "$_st_top" "$_st_short"
}

shipyard_standalone_pkg_path() {
  case "$2" in
    '') printf 'usr/local/mavergreen/%s\n' "$1" ;;
    *.app|*.app/*)
      case "${2%%/*}" in
        *.app) printf 'Applications/%s\n' "$2" ;;
        *) printf 'usr/local/mavergreen/%s/%s\n' "$1" "$2" ;;
      esac ;;
    *) printf 'usr/local/mavergreen/%s/%s\n' "$1" "$2" ;;
  esac
}

shipyard_standalone_entry_pkg_path() {
  _st_ts="$(shipyard_standalone_top "$1")" || return 1
  _st_t="${_st_ts% *}"
  case "$2" in
    "$_st_t"/?*) shipyard_standalone_pkg_path "${_st_ts#* }" "${2#"$_st_t"/}" ;;
    *) return 1 ;;
  esac
}
