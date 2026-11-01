# platform: host-agnostic
# fixture_tree FIXTURES_DIR FIXTURE DEST: DEST becomes FIXTURE laid over FIXTURES_DIR/_base, minus the
# paths FIXTURE's DELETE lists (its other config files, like FILES, stay).
fixture_tree() {
  mkdir -p "$3"
  cp -R "$1/_base/." "$3/"
  cp -R "$2/." "$3/"
  [ -f "$2/DELETE" ] || return 0
  rm -f "${3:?}/DELETE"
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    rm -rf "${3:?}/$_p"
    (cd "$3" && rmdir -p "$(dirname "$_p")" 2>/dev/null) || true
  done < "$2/DELETE"
}
