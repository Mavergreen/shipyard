# platform: host-agnostic
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Consolidation
#       backlog" -- promoted here from three byte-identical per-repo copies (golang,
#       macports-legacy-support, ed25519); sourced, no side effects. $MAVERGREEN_REPO_ROOT defaults to the
#       git toplevel so a plain `sh build/version.sh` still works from anywhere in a repo.
: "${MAVERGREEN_REPO_ROOT:=$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
export MAVERGREEN_REPO_ROOT

upstream_version() {
  if ! _uv_kind="$(mg_upstream_kind)"; then
    echo "upstream_version: $(mg_dir)/upstream/ needs exactly one of VERSION, COMMIT or PIN" >&2
    return 1
  fi
  if [ "$_uv_kind" = VERSION ]; then
    mg_value upstream/VERSION
    return
  fi
  _uv_hook="$(mg_dir)/hooks/derive-upstream-version"
  [ -f "$_uv_hook" ] || {
    echo "upstream_version: upstream/$_uv_kind is not a version, and there is no $_uv_hook to derive one" >&2
    return 1
  }
  _uv="$(cd "$MAVERGREEN_REPO_ROOT" && sh "$_uv_hook")" || {
    echo "upstream_version: $_uv_hook failed" >&2
    return 1
  }
  [ -n "$_uv" ] || { echo "upstream_version: $_uv_hook printed no version" >&2; return 1; }
  printf '%s\n' "$_uv"
}

# spec: tests/version-lib-test.sh -- lib/vercmp.sh and mavergreen-meta.sh are found via $SELF,
#       $SHIPYARD or $SHIPYARD_SCRIPTS: a sourced file cannot learn its own path in POSIX sh.
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
. "$_lib_d/mavergreen-meta.sh"
unset _lib_vercmp _lib_d
