# platform: host-agnostic
mavergreen_reserved_names='var bin sbin share mavergreen system-replace base'

mavergreen_name_ok() {
  case "$1" in
    ''|-*|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;;
  esac
  for _nr in $mavergreen_reserved_names; do
    [ "$1" != "$_nr" ] || return 2
  done
}
