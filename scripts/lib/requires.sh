# platform: host-agnostic
#   usage: . scripts/lib/requires.sh; mavergreen_requires STEVEDORE PLIST ERRFILE
#          Prints the `requires` array of a mavergreen.plist, one SHORT or SHORT>=FLOOR per line; none
#          when it has no requires. Returns 1 with the reason in ERRFILE, to follow the product's short
#          name: the array is not one of strings, an entry cannot be read, or one names no product.
# spec: tests/install-products-test.sh, tests/check-standalone-archive-test.sh

mavergreen_requires() {
  _rq_i=0
  while :; do
    _rq_rc=0; _rq_r="$("$1" plist get "$2" "requires:$_rq_i" 2> "$3")" || _rq_rc=$?
    if [ "$_rq_rc" -eq 1 ] && grep -q 'no such entry' "$3"; then
      [ "$_rq_i" -gt 0 ] || { _rq_rc=0; "$1" plist get "$2" requires > /dev/null 2>&1 || _rq_rc=$?; }
      case "$_rq_rc" in
        1|3) : > "$3"; return 0 ;;
        *) printf ': the requires in %s is not an array of strings\n' "$2" > "$3"; return 1 ;;
      esac
    fi
    if [ "$_rq_rc" -ne 0 ]; then
      _rq_e="$(cat "$3")"
      printf ': cannot read requires:%s of %s: %s\n' "$_rq_i" "$2" "$_rq_e" > "$3"; return 1
    fi
    case "${_rq_r%%>=*}" in
      ''|-*|*[!a-z0-9-]*) printf " requires '%s', which names no product\n" "$_rq_r" > "$3"; return 1 ;;
    esac
    printf '%s\n' "$_rq_r"
    _rq_i=$((_rq_i + 1))
  done
}
