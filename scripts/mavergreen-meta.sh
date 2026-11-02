# platform: host-agnostic

mg_dir() {
  if [ -n "${MAVERGREEN_ROOT:-}" ]; then
    printf '%s/.mavergreen\n' "$MAVERGREEN_ROOT"
  elif [ -n "${MAVERICKS_ROOT:-}" ]; then
    printf '%s/.mavergreen\n' "$MAVERICKS_ROOT"
  else
    printf '%s/.mavergreen\n' "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
}

mg_value() {
  _mg_f="$(mg_dir)/$1"
  [ -f "$_mg_f" ] || return 1
  _mg_v=
  IFS= read -r _mg_v < "$_mg_f" || [ -n "$_mg_v" ] || :
  printf '%s\n' "${_mg_v%"$(printf '\r')"}"
}

mg_has() {
  test -e "$(mg_dir)/$1"
}

mg_list() {
  _mg_d="$(mg_dir)/$1"
  [ -d "$_mg_d" ] || return 0
  LC_ALL=C ls -1 "$_mg_d"
}

mg_lines() {
  _mg_f="$(mg_dir)/$1"
  [ -f "$_mg_f" ] || return 1
  _mg_n=0
  while IFS= read -r _mg_l || [ -n "$_mg_l" ]; do
    _mg_n=$((_mg_n + 1))
    _mg_l="${_mg_l%"$(printf '\r')"}"
    if [ "$_mg_n" -eq 2 ]; then
      case "$_mg_l" in '# renovate:'*) continue;; esac
    fi
    printf '%s\n' "$_mg_l"
  done < "$_mg_f"
}

mg_pin_ref() {
  _mg_p="$(mg_value "$1/PIN")" || return 1
  case "$_mg_p" in *@*) ;; *) return 1;; esac
  printf '%s\n' "${_mg_p%%@*}"
}

mg_pin_commit() {
  _mg_p="$(mg_value "$1/PIN")" || return 1
  case "$_mg_p" in *@*) ;; *) return 1;; esac
  printf '%s\n' "${_mg_p#*@}"
}

mg_glob_hits() {
  while IFS= read -r _mg_f || [ -n "$_mg_f" ]; do
    case "$_mg_f" in $1) printf '%s\n' "$_mg_f" ;; esac
  done < "$2"
}

mg_upstream_kind() {
  _mg_k=
  _mg_c=0
  for _mg_x in VERSION COMMIT PIN; do
    if mg_has "upstream/$_mg_x"; then
      _mg_k="$_mg_x"
      _mg_c=$((_mg_c + 1))
    fi
  done
  [ "$_mg_c" -eq 1 ] || return 1
  printf '%s\n' "$_mg_k"
}

mg_renovate() {
  _mg_f="$(mg_dir)/$1"
  [ -f "$_mg_f" ] || return 1
  _mg_r=
  { IFS= read -r _mg_r && IFS= read -r _mg_r || _mg_r=; } < "$_mg_f" || :
  _mg_r="${_mg_r%"$(printf '\r')"}"
  case "$_mg_r" in '# renovate:'*) _mg_r="${_mg_r#'# renovate:'}";; *) return 1;; esac
  case "$-" in *f*) _mg_nf=1;; *) _mg_nf=; set -f;; esac
  set -- $_mg_r
  [ -n "$_mg_nf" ] || set +f
  [ "$#" -gt 0 ] || return 1
  printf '%s\n' "$@"
}
