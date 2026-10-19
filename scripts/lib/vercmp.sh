# platform: host-agnostic
# spec: tests/version-lib-test.sh -- the family's ONE version comparator. Definitions only (no
#       exit, no $0, no set), because generated installer scripts inline this file verbatim and the
#       same text must also be sourced by lib.sh; a second copy would drift the way gen_appcast.sh's
#       and previous-release-tag.sh's key derivations once did.

# platform: 10.9's BSD sort has no -V, so any script relying on it works in CI and dies on the
#           platform this family targets. A version is in the comparator's orderable domain iff it
#           is purely dotted-numeric.
# spec: scripts/assert_appcast_upgradeable.sh -- one comparator serves both this and
#       previous-release-tag.sh, so "which tag is highest" cannot drift between them.
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

# spec: tests/version-lib-test.sh "comparison_key()" -- the ONE dotted-numeric-key derivation for
#       the family (mirrored in MavericksSparkle.cmake, which cannot source sh); gen_appcast.sh and
#       previous-release-tag.sh each carried their own copy, and when the pN rule (OpenSSH-portable's
#       9.9pN, monotonic: p2 is newer than p1) was added to only one side, no openssh release ever
#       found its baseline. A NON-monotonic suffix (-rc1, beta) must NOT be folded here -- left
#       unmapped so callers' numeric() checks fail closed. -mavergreen. is the same build-number
#       suffix as -mavericks., so a product renamed between the two stays comparable.
comparison_key() {
  printf '%s' "$1" | sed -e 's/-mavericks\./\./' -e 's/-mavergreen\./\./' -e 's/\([0-9]\)p\([0-9]\)/\1.\2/'
}

# spec: tests/version-lib-test.sh "mavergreen_vercmp" -- status 2 (nothing printed) when either key is
#       unorderable, so a caller can refuse rather than guess; 1.0-rc1 has no place in the order.
mavergreen_vercmp() {
  _mv_a="$(comparison_key "$1")"
  _mv_b="$(comparison_key "$2")"
  numeric "$_mv_a" && numeric "$_mv_b" || return 2
  ver_cmp "$_mv_a" "$_mv_b"
}
