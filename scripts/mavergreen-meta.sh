# platform: host-agnostic

mg_dir() {
  if [ -n "${MAVERGREEN_REPO_ROOT:-}" ]; then
    printf '%s/.mavergreen\n' "$MAVERGREEN_REPO_ROOT"
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
  { IFS= read -r _mg_r && { IFS= read -r _mg_r || [ -n "$_mg_r" ]; } || _mg_r=; } < "$_mg_f" || :
  _mg_r="${_mg_r%"$(printf '\r')"}"
  case "$_mg_r" in '# renovate:'*) _mg_r="${_mg_r#'# renovate:'}";; *) return 1;; esac
  case "$-" in *f*) _mg_nf=1;; *) _mg_nf=; set -f;; esac
  set -- $_mg_r
  [ -n "$_mg_nf" ] || set +f
  [ "$#" -gt 0 ] || return 1
  printf '%s\n' "$@"
}

mg_repo() {
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    printf '%s\n' "$GITHUB_REPOSITORY"
    return 0
  fi
  _mg_root="$(mg_dir)"
  _mg_u="$(cd "${_mg_root%/.mavergreen}" 2>/dev/null && git config --get remote.origin.url 2>/dev/null)" || return 1
  _mg_u="${_mg_u%/}"
  _mg_u="${_mg_u%.git}"
  case "$_mg_u" in
    https://github.com/*) _mg_u="${_mg_u#https://github.com/}" ;;
    ssh://git@github.com/*) _mg_u="${_mg_u#ssh://git@github.com/}" ;;
    git@github.com:*) _mg_u="${_mg_u#git@github.com:}" ;;
    *) return 1 ;;
  esac
  case "$_mg_u" in
    ''|/*|*/|*/*/*|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/-]*) return 1 ;;
    */*) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$_mg_u"
}

mavergreen_name() {
  _mn_surface="${1:-}"
  _mn_short="${2:-}"
  _mn_version="${3:-}"
  case "$_mn_short" in
    ''|-*|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*)
      echo "mavergreen_name: \"$_mn_short\" is not a short name (lowercase ASCII letters, digits and hyphens)" >&2
      return 2 ;;
  esac
  case "$_mn_surface" in
    name|installer-title|channel-title|manifest-name|link-suffix|component|feed|identifier) ;;
    title|pkg|release-title|item-title|notes-heading)
      if [ -z "$_mn_version" ]; then
        echo "mavergreen_name: $_mn_surface needs a version" >&2
        return 2
      fi ;;
    *)
      echo "mavergreen_name: \"$_mn_surface\" is not a name surface" >&2
      return 2 ;;
  esac
  _mn_noun="$(mg_value "products/$_mn_short/noun" 2>/dev/null)" || _mn_noun=
  if [ -z "$_mn_noun" ]; then
    echo "mavergreen_name: .mavergreen/products/$_mn_short/noun is missing or empty" >&2
    return 1
  fi
  _mn_line="$(mg_value "products/$_mn_short/line" 2>/dev/null)" || _mn_line=
  _mn_name="$_mn_noun"
  [ -z "$_mn_line" ] || _mn_name="$_mn_noun $_mn_line"
  _mn_bare="${_mn_version#v}"
  _mn_upstream="$_mn_bare"
  case "$_mn_upstream" in *-mavergreen.*) _mn_upstream="${_mn_upstream%-mavergreen.*}" ;; esac
  case "$_mn_surface" in
    name|channel-title|manifest-name) printf '%s\n' "$_mn_name" ;;
    installer-title) printf 'Mavergreen %s\n' "$_mn_name" ;;
    title|release-title|item-title) printf '%s %s\n' "$_mn_noun" "$_mn_upstream" ;;
    notes-heading) printf '## %s %s\n' "$_mn_noun" "$_mn_upstream" ;;
    pkg) printf '%s-%s.pkg\n' "$_mn_short" "$_mn_bare" ;;
    component) printf '%s.pkg\n' "$_mn_short" ;;
    feed) printf '%s.xml\n' "$_mn_short" ;;
    identifier) printf 'dev.mavergreen.%s\n' "$_mn_short" ;;
    link-suffix)
      _mn_s=
      _mn_rest="$_mn_line"
      while [ -n "$_mn_rest" ]; do
        case "$_mn_rest" in
          .*) _mn_rest="${_mn_rest#.}" ;;
          *) _mn_s="$_mn_s${_mn_rest%"${_mn_rest#?}"}"; _mn_rest="${_mn_rest#?}" ;;
        esac
      done
      printf '%s\n' "$_mn_s" ;;
  esac
}

mg_port_or_own() {
  if mg_has hooks/derive-upstream-version; then
    echo port
  elif _mg_vf="$(mg_upstream_kind)" && mg_renovate "upstream/$_mg_vf" >/dev/null; then
    echo port
  else
    echo own
  fi
}
