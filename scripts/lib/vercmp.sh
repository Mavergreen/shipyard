# platform: host-agnostic
# spec: tests/version-lib-test.sh -- the family's one comparator: definitions only (no exit, $0 or
#       set), so lib.sh sources it and generated preinstalls inline it verbatim.

# platform: 10.9's BSD sort has no -V; a key is orderable iff it is purely dotted-numeric.
numeric() {
  case "$1" in ''|.*|*.|*..*|*[!0-9.]*) return 1;; *) return 0;; esac
}

ver_cmp() {
  awk -v a="$1" -v b="$2" 'BEGIN{
    na=split(a,A,"."); nb=split(b,B,"."); n=(na>nb)?na:nb;
    for(i=1;i<=n;i++){ x=(i<=na)?A[i]+0:0; y=(i<=nb)?B[i]+0:0;
      if(x>y){print 1; exit} if(x<y){print -1; exit} }
    print 0 }'
}

# spec: tests/version-lib-test.sh "comparison_key()" -- maps only monotonic suffixes (-mavericks.N,
#       -mavergreen.N, pN), so -rc1 stays unorderable; MavericksSparkle.cmake mirrors it.
comparison_key() {
  printf '%s' "$1" | sed -e 's/-mavericks\./\./' -e 's/-mavergreen\./\./' -e 's/\([0-9]\)p\([0-9]\)/\1.\2/'
}

# spec: tests/version-lib-test.sh "mavergreen_vercmp" -- status 2, printing nothing, when either key is
#       unorderable; a subshell body, so it sets no caller variable.
mavergreen_vercmp() (
  a="$(comparison_key "$1")"
  b="$(comparison_key "$2")"
  numeric "$a" && numeric "$b" || return 2
  ver_cmp "$a" "$b"
)
