#!/bin/sh
# platform: host-agnostic
#   usage: ingredient-notes.sh [--watched <file>] <prev-tag>
#          Compares .mavergreen/ingredients/ at <prev-tag> with the working tree, as the release
#          notes' "### Build ingredients" section: a bullet per changed value file (VERSION, PIN,
#          COMMIT, REPO, SHA256, any other uppercase file, and from), one per added or removed
#          ingredient, and one per changed file an ingredient's watch matches. Each changed or added
#          ingredient's description follows its first bullet. A link comes from the line-2 Renovate
#          annotation (github-releases, github-tags, git-tags) or else from REPO, and otherwise
#          there is none. Prints nothing when nothing moved or <prev-tag> is empty, and one line when
#          <prev-tag> has no .mavergreen/. --watched writes the watched paths it reported to <file>,
#          one per line, so the caller leaves exactly those out of "Our patches".
set -eu
# platform: modern macOS collates en_US.UTF-8 so that [A-Z] also matches b-z; 10.9 and Linux do not.
LC_ALL=C; export LC_ALL
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"

watched_out=
if [ "${1:-}" = --watched ]; then watched_out="$2"; shift 2; : > "$watched_out"; fi
prev="${1:-}"
[ -n "$prev" ] || exit 0
git rev-parse -q --verify "$prev^{commit}" >/dev/null \
  || { echo "ingredient-notes: cannot read $prev, so what moved since it is unknown" >&2; exit 1; }
MAVERGREEN_ROOT="$(git rev-parse --show-toplevel)"
if ! git cat-file -e "$prev:.mavergreen" 2>/dev/null; then
  [ -z "$(mg_list ingredients)" ] \
    || echo '- Ingredients moved to .mavergreen/; no per-pin changes listed for this release.'
  exit 0
fi
CR="$(printf '\r')"
I=.mavergreen/ingredients

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/bullets"
git -c core.quotepath=off diff --name-only "$prev" -- > "$tmp/changed"

first_line() {
  _l=
  IFS= read -r _l || :
  printf '%s' "${_l%"$CR"}"
}
is_value() { case "$1" in [A-Z]*|from) return 0 ;; esac; return 1; }
old_names() { git ls-tree "$prev:$I" 2>/dev/null | awk -F'\t' '$1 ~ / tree / { print $2 }'; }
old_keys() { git ls-tree "$prev:$I/$1" 2>/dev/null | awk -F'\t' '$1 ~ / blob / { print $2 }'; }
old_value() { git show "$prev:$I/$1/$2" 2>/dev/null | first_line; }
new_keys() { for _k in $(mg_list "ingredients/$1"); do [ ! -f "$MAVERGREEN_ROOT/$I/$1/$_k" ] || printf '%s\n' "$_k"; done; }

show() {
  case "$1" in
    PIN) _c="${2#*@}"; printf '%s@%.12s' "${2%%@*}" "$_c"; return ;;
  esac
  case "$2" in
    *[!0-9a-fA-F]*|'') printf '%s' "$2"; return ;;
  esac
  if [ "${#2}" -ge 32 ]; then printf '%.12s...' "$2"; else printf '%s' "$2"; fi
}

github_repo() {
  _r="${1#https://github.com/}"
  _r="${_r%.git}"
  case "$_r" in
    */*/*|/*|*/|*[!A-Za-z0-9_./-]*) return 1 ;;
    */*) printf '%s' "$_r" ;;
    *) return 1 ;;
  esac
}

tag_affix() {
  _e="$1"
  case "$_e" in '^'*'(?<version>'*')'*'$') ;; *) return 1 ;; esac
  _pre="${_e#^}"; _pre="${_pre%%'(?<version>'*}"
  _post="${_e#*'(?<version>'}"; _post="${_post#*)}"; _post="${_post%\$}"
  for _x in "$_pre" "$_post"; do
    case "$(printf '%s' "$_x" | sed 's/\\[./_-]//g')" in *[!A-Za-z0-9_-]*) return 1 ;; esac
  done
  PRE="$(printf '%s' "$_pre" | sed 's/\\\(.\)/\1/g')"
  POST="$(printf '%s' "$_post" | sed 's/\\\(.\)/\1/g')"
}

compare_link() {
  if [ -n "$2" ] && [ "$2" != "$3" ]; then
    printf ' ([changes](https://github.com/%s/compare/%s...%s))' "$1" "$2" "$3"
  else
    printf ' ([source](https://github.com/%s/tree/%s))' "$1" "$3"
  fi
}

renovate_link() {
  for k in $(new_keys "$1"); do
    is_value "$k" || continue
    words="$(mg_renovate "ingredients/$1/$k")" || continue
    ds=; dep=; ev=
    while IFS= read -r w; do
      case "$w" in
        datasource=*) ds="${w#datasource=}" ;;
        depName=*) dep="${w#depName=}" ;;
        extractVersion=*) ev="${w#extractVersion=}" ;;
      esac
    done <<EOF
$words
EOF
    repo="$(github_repo "$dep")" || return 1
    new="$(mg_value "ingredients/$1/$k")"; old="$(old_value "$1" "$k")"
    if [ "$k" = PIN ]; then
      new="${new#*@}"; old="${old#*@}"; PRE=; POST=
    elif [ -n "$ev" ]; then
      tag_affix "$ev" || return 1
    else
      PRE=; POST=
    fi
    case "$ds" in
      github-releases|github-release-attachments)
        printf ' ([release notes](https://github.com/%s/releases/tag/%s%s%s))' "$repo" "$PRE" "$new" "$POST" ;;
      github-tags|git-tags)
        compare_link "$repo" "${old:+$PRE$old$POST}" "$PRE$new$POST" ;;
      *) return 1 ;;
    esac
    return 0
  done
  return 1
}

repo_link() {
  r="$(mg_value "ingredients/$1/REPO")" || return 1
  repo="$(github_repo "$r")" || return 1
  for k in PIN COMMIT VERSION; do
    new="$(mg_value "ingredients/$1/$k")" || continue
    old="$(old_value "$1" "$k")"
    [ "$k" != PIN ] || { new="${new#*@}"; old="${old#*@}"; }
    compare_link "$repo" "$old" "$new"
    return 0
  done
  printf ' ([source](https://github.com/%s))' "$repo"
}

link_for() { renovate_link "$1" || repo_link "$1" || :; }

primary() {
  for k in VERSION PIN COMMIT from; do
    v="$(mg_value "ingredients/$1/$k")" || continue
    show "$k" "$v"; return 0
  done
  return 1
}

{ old_names; mg_list ingredients; } | LC_ALL=C sort -u > "$tmp/names"
while IFS= read -r n; do
  in_old=no; in_new=no
  old_names | grep -qxF -- "$n" && in_old=yes
  [ -d "$MAVERGREEN_ROOT/$I/$n" ] && in_new=yes
  : > "$tmp/mine"
  if [ "$in_new" = no ]; then
    printf -- '- **%s**: removed\n' "$n" >> "$tmp/bullets"
    continue
  fi
  lnk="$(link_for "$n")"
  if [ "$in_old" = no ]; then
    if v="$(primary "$n")"; then
      printf -- '- **%s**: added (%s)%s\n' "$n" "$v" "$lnk" >> "$tmp/mine"
    else
      printf -- '- **%s**: added%s\n' "$n" "$lnk" >> "$tmp/mine"
    fi
  else
    { old_keys "$n"; new_keys "$n"; } | LC_ALL=C sort -u | while IFS= read -r k; do
      is_value "$k" || continue
      if new="$(mg_value "ingredients/$n/$k")"; then has_new=yes; else has_new=no; fi
      if git cat-file -e "$prev:$I/$n/$k" 2>/dev/null; then
        old="$(old_value "$n" "$k")"
        if [ "$has_new" = no ]; then
          printf -- '- **%s / %s**: removed\n' "$n" "$k"
        elif [ "$old" != "$new" ]; then
          printf -- '- **%s / %s**: %s -> %s%s\n' "$n" "$k" "$(show "$k" "$old")" "$(show "$k" "$new")" "$lnk"
        fi
      elif [ "$has_new" = yes ]; then
        printf -- '- **%s / %s**: added (%s)%s\n' "$n" "$k" "$(show "$k" "$new")" "$lnk"
      fi
    done >> "$tmp/mine"
    if watch="$(mg_lines "ingredients/$n/watch")"; then
      printf '%s\n' "$watch" | while IFS= read -r g; do
        [ -z "$g" ] || mg_glob_hits "$g" "$tmp/changed"
      done | LC_ALL=C sort -u | while IFS= read -r f; do
        printf -- '- **%s / watch**: `%s` changed\n' "$n" "$f"
        [ -z "$watched_out" ] || printf '%s\n' "$f" >> "$watched_out"
      done >> "$tmp/mine"
    fi
  fi
  [ -s "$tmp/mine" ] || continue
  sed -n 1p "$tmp/mine" >> "$tmp/bullets"
  if d="$(mg_value "ingredients/$n/description")" && [ -n "$d" ]; then
    printf '  %s\n' "$d" >> "$tmp/bullets"
  fi
  sed 1d "$tmp/mine" >> "$tmp/bullets"
done < "$tmp/names"

if [ -s "$tmp/bullets" ]; then
  printf '### Build ingredients\n\nChanged since %s:\n\n' "$prev"
  cat "$tmp/bullets"
fi
