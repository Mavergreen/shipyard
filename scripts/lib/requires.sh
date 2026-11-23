# platform: host-agnostic
#   usage: . scripts/lib/requires.sh; mavergreen_requires STEVEDORE PLIST ERRFILE
#          . scripts/lib/requires.sh; mavergreen_require_short SPEC
#          Prints the `requires` of a mavergreen.plist, one SHORT or SHORT>=FLOOR per line; none when it
#          has no requires. A flag-day manifest's requires is a dict, SHORT to {kind, min}; a pinned
#          pre-flag-day release's is an array of SHORT or SHORT>=FLOOR strings. Returns 1 with the
#          reason in ERRFILE, to follow the product's short name: the plist cannot be read, the requires
#          is neither, an array entry is not a string, or one names no product.
#          mavergreen_require_short prints the SHORT of one entry, SHORT or SHORT>=FLOOR; it returns 1,
#          printing nothing, when the entry names no product.
# spec: tests/install-products-test.sh, tests/check-standalone-archive-test.sh, tests/derive-pkg-tree-test.sh

mavergreen_require_short() {
  case "${1%%>=*}" in ''|-*|*[!a-z0-9-]*) return 1 ;; esac
  printf '%s\n' "${1%%>=*}"
}

mavergreen_requires() {
  "$1" plist xml1 "$2" > "$3.xml" 2> "$3" || {
    _rq_e="$(cat "$3")"; printf ': cannot read %s: %s\n' "$2" "$_rq_e" > "$3"; rm -f "$3.xml"; return 1; }
  : > "$3"
  awk -v err="$3" -v f="$2" '
    function bad(m) { printf ": the requires in %s %s\n", f, m > err; failed = 1; exit 1 }
    function val(l) { sub(/^[^>]*>/, "", l); sub(/<.*$/, "", l); gsub(/&lt;/, "<", l); gsub(/&gt;/, ">", l); gsub(/&amp;/, "\\&", l); return l }
    { l = $0; gsub(/^[ \t]+|[ \t]+$/, "", l) }
    rd && mode == "array" && d == rd && l !~ /^<string>/ && l != "</array>" { bad("is not an array of strings") }
    l == "<dict/>" || l == "<array/>" {
      if (pend) pend = 0
      else if (rd && mode == "dict" && d == rd && cur != "") { print cur; cur = "" }
      next
    }
    l == "<dict>" || l == "<array>" {
      d++
      if (pend) { pend = 0; rd = d; mode = (l == "<dict>") ? "dict" : "array" }
      next
    }
    l == "</dict>" || l == "</array>" {
      if (rd && mode == "dict" && d == rd + 1 && cur != "") { print cur (mn != "" ? ">=" mn : ""); cur = ""; mn = "" }
      if (rd && d == rd) rd = 0
      d--; next
    }
    pend { bad("is neither a dict nor an array") }
    d == 1 && !rd && l == "<key>requires</key>" { pend = 1; next }
    rd && mode == "array" && d == rd { print val(l); next }
    rd && mode == "dict" && d == rd && l ~ /^<key>/ { cur = val(l); mn = ""; next }
    rd && mode == "dict" && d == rd + 1 && l == "<key>min</key>" { wantmin = 1; next }
    wantmin { wantmin = 0; mn = val(l); next }
  ' "$3.xml" > "$3.out" || { rm -f "$3.xml" "$3.out"; return 1; }
  rm -f "$3.xml"
  while IFS= read -r _rq_r; do
    case "${_rq_r%%>=*}" in
      ''|-*|*[!a-z0-9-]*) printf " requires '%s', which names no product\n" "$_rq_r" > "$3"; rm -f "$3.out"; return 1 ;;
    esac
  done < "$3.out"
  cat "$3.out"; rm -f "$3.out"
}
