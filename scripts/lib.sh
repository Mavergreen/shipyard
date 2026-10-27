# platform: host-agnostic
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Consolidation
#       backlog" -- promoted here from three byte-identical per-repo copies (golang,
#       macports-legacy-support, ed25519); sourced, no side effects. $MAVERICKS_ROOT defaults to the
#       git toplevel so a plain `sh build/version.sh` still works from anywhere in a repo.
: "${MAVERICKS_ROOT:=$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# spec: SKILL.md "A release is a declared state, not an event" -- $MAVERICKS_UPSTREAM_FILE overrides
#       the path; a repo whose upstream is not UPSTREAM_VERSION points elsewhere
#       (container-tools and tailscale: components/<name>/version), so which file to read is an
#       input, not a fixed location.
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
#       "Mavergreen-State: <value>" (spec 2026-09-12, decision 2). ONE reader for the family:
#       release-needed.sh once recognised only `v1:sha256:<hex>` while release-state-record.sh took
#       anything after the key, so an older-format marker was "no digest recorded" to the first and
#       "a CONFLICTING digest" to the second (ruling 1: the second exits 3 and fails the job) -- every
#       migrated repo would have gone red nightly with no self-healing path. See
#       tests/release-needed-test.sh "THE FIRST READABLE MARKER WINS" for why the first READABLE
#       marker wins, not simply the first: release-needed.sh refuses to publish while the marker it
#       reads is unreadable, so plain first-wins would let an unreadable line earlier in a body WEDGE
#       a repo whose valid digest sat two lines below it.
state_marker() {
  _sm_all="$(sed -n 's/^Mavergreen-State:[[:space:]]*//p' | sed 's/[[:space:]]*$//')"
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

# spec: tests/release-state-test.sh -- a "path:KEY" Declared-state entry's value: KEY's first
#       assignment in the file, one pair of surrounding double quotes dropped, whitespace removed.
pin_value() {
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1 | sed 's/^"//; s/"$//' | tr -d '[:space:]'
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

# spec: tests/version-lib-test.sh -- lib/vercmp.sh is found via $SELF, $SHIPYARD or $SHIPYARD_SCRIPTS:
#       a sourced file cannot learn its own path in POSIX sh.
_lib_vercmp=""
for _lib_d in "${SELF:-}" "${SHIPYARD:-}" "${SHIPYARD_SCRIPTS:-}"; do
  if [ -n "$_lib_d" ] && [ -f "$_lib_d/lib/vercmp.sh" ]; then _lib_vercmp="$_lib_d/lib/vercmp.sh"; break; fi
done
if [ -z "$_lib_vercmp" ]; then
  unset _lib_vercmp _lib_d
  echo "lib.sh: cannot find lib/vercmp.sh beside it; set SHIPYARD_SCRIPTS to shipyard's scripts directory" >&2
  return 1
fi
. "$_lib_vercmp"
unset _lib_vercmp _lib_d
