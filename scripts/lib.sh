# spec: claude-plugins/modernmavericks/skills/modernmavericks-conventions/SKILL.md "Consolidation
#       backlog" -- promoted here from three byte-identical per-repo copies (golang,
#       macports-legacy-support, ed25519); sourced, no side effects. $MAVERICKS_ROOT defaults to the
#       git toplevel so a plain `sh build/version.sh` still works from anywhere in a repo.
: "${MAVERICKS_ROOT:=$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# spec: SKILL.md "A release is a declared state, not an event" -- $MAVERICKS_UPSTREAM_FILE overrides
#       the path; a repo shipping parallel upstream lines keeps one per line
#       (mavericks-golang: lines/126/UPSTREAM_VERSION), so which file to read is an input, not a
#       fixed location.
upstream_version() {
  tr -d '[:space:]' < "${MAVERICKS_UPSTREAM_FILE:-$MAVERICKS_ROOT/UPSTREAM_VERSION}"
}

# spec: SKILL.md "A release is a declared state, not an event" -- a marker in another format is NOT
#       "no marker"; release-needed.sh must refuse to publish rather than treat it as absent, or a
#       future format bump would republish every product.
state_digest_readable() {
  case "${1:-}" in
    v1:sha256:*) case "${1#v1:sha256:}" in ''|*[!0-9a-f]*) return 1;; *) return 0;; esac ;;
    *) return 1 ;;
  esac
}

# spec: SKILL.md "A release is a declared state, not an event" -- marker format is
#       "ModernMavericks-State: <value>" (spec 2026-09-12, decision 2). ONE reader for the family:
#       release-needed.sh once recognised only `v1:sha256:<hex>` while release-state-record.sh took
#       anything after the key, so an older-format marker was "no digest recorded" to the first and
#       "a CONFLICTING digest" to the second (ruling 1: the second exits 3 and fails the job) -- every
#       migrated repo would have gone red nightly with no self-healing path. See
#       tests/release-needed-test.sh "THE FIRST READABLE MARKER WINS" for why the first READABLE
#       marker wins, not simply the first: release-needed.sh refuses to publish while the marker it
#       reads is unreadable, so plain first-wins would let an unreadable line earlier in a body WEDGE
#       a repo whose valid digest sat two lines below it.
state_marker() {
  _sm_all="$(sed -n 's/^ModernMavericks-State:[[:space:]]*//p' | sed 's/[[:space:]]*$//')"
  _sm_pick=""
  while IFS= read -r _sm_one || [ -n "$_sm_one" ]; do
    [ -n "$_sm_one" ] || continue
    [ -n "$_sm_pick" ] || _sm_pick="$_sm_one"
    if state_digest_readable "$_sm_one"; then _sm_pick="$_sm_one"; break; fi
  done <<EOF
$_sm_all
EOF
  printf '%s\n' "$_sm_pick"
}

# spec: SKILL.md "shipyard: consume its facilities, never hand-roll them" -- never a hard-coded
#       prefix, never a vendored copy.
msc_scripts() {
  if [ -n "${MAVERICKS_SCRIPTS:-}" ]; then printf '%s\n' "$MAVERICKS_SCRIPTS"; return 0; fi
  if [ -n "${SHIPYARD_SCRIPTS:-}" ] && [ -d "$SHIPYARD_SCRIPTS" ]; then printf '%s\n' "$SHIPYARD_SCRIPTS"; return 0; fi
  echo "msc_scripts: SHIPYARD_SCRIPTS is not set -- source the product's msc.sh first (it asks shipyard-cmake)," >&2
  echo "  or set MAVERICKS_SCRIPTS" >&2
  return 1
}

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
#       unmapped so callers' numeric() checks fail closed.
comparison_key() {
  printf '%s' "$1" | sed -e 's/-mavericks\./\./' -e 's/\([0-9]\)p\([0-9]\)/\1.\2/'
}
