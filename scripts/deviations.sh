#!/bin/sh
# platform: host-agnostic
#   usage: deviations.sh <repo>
#          Prints the deviations in <repo>/.mavergreen/deviations/<check>/<label>/, one per line as
#          "<check> <scope> <reason>": scope is line 1 of scope (* for repo-wide), with "%" written
#          %25, a space %20 and a tab %09 so it stays one column; reason is reason's lines joined
#          by single spaces. A deviation without a one-line scope, a reason and a revisit, under a
#          label matching ^[a-z0-9][a-z0-9.-]*$, or with a scope its check cannot honour, is refused
#          on stderr and the exit is 1: an exception without them is indistinguishable from drift.
set -eu
LC_ALL=C; export LC_ALL
root="${1:-.}"
_here="$(cd "$(dirname "$0")" && pwd)"
. "$_here/mavergreen-meta.sh"
MAVERGREEN_ROOT="$root"
base="$(mg_dir)"
tab="$(printf '\t')"
bad=0

refuse() { printf 'deviations.sh: deviations/%s: %s\n' "$1" "$2" >&2; bad=1; }

prose() {
  mg_lines "$1" | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "") { printf "%s%s", sep, $0; sep = " " } } END { if (sep != "") print "" }'
}

wild() { case "$1" in *[*?[]*) return 0 ;; esac; return 1; }
only() { case "$1" in *[!$2]*) return 1 ;; esac; return 0; }

scope_refusal() {
  _c="$1"; _s="$2"
  if [ "$_c" != unlinked ]; then
    case "$_s" in
      *:*)
        _k="${_s##*:}"
        case "$_k" in
          [A-Z*]*) if only "$_k" 'A-Z0-9_*'; then echo "the :$_k in scope \"$_s\" is a KEY, and only unlinked takes a :KEY scope"; return 0; fi ;;
        esac ;;
    esac
  fi
  case "$_c" in
    unlinked)
      [ "$_s" != '*' ] || echo "unlinked must name the pins it excuses: a scope of <pin path>[:KEY], never *" ;;
    self-upstream-exclude)
      ! only "$_s" '*/' || echo "self-upstream-exclude must name what it excludes, never a scope of nothing but * and /" ;;
    on-target)
      if [ "$_s" != '*' ] && wild "$_s"; then
        echo "an on-target scope of \"$_s\" -- an on-target part is one word naming what stays untested in the guest, never a glob; a scope of * is the one that stands in for the job"
      fi ;;
    macos-runner)
      _f="${_s%%:*}"; _j="${_s#*:}"
      case "$_j" in *:*) _j="" ;; esac
      if wild "$_s" || [ "$_f" = "$_s" ] || [ -z "$_f" ] || [ -z "$_j" ]; then
        echo "macos-runner names one job: a scope of <workflow file>:<job>, never a wildcard"
      fi ;;
    arm64|cxxabi)
      ! only "$_s" '*?/' || echo "$_c names the install paths it covers: a scope of <install-path glob>, never * or a glob of nothing but wildcards" ;;
    packager)
      ! wild "$_s" || echo "packager names one path: a scope of <path>, never a wildcard" ;;
  esac
  return 0
}

one() {
  _id="$1/$2"; _d="deviations/$1/$2"
  case "$2" in
    [a-z0-9]*) case "$2" in *[!a-z0-9.-]*) refuse "$_id" "the label \"$2\" does not match ^[a-z0-9][a-z0-9.-]*\$"; return 0 ;; esac ;;
    *) refuse "$_id" "the label \"$2\" does not match ^[a-z0-9][a-z0-9.-]*\$"; return 0 ;;
  esac
  [ -d "$base/$_d" ] || { refuse "$_id" "is not a directory; a deviation is deviations/<check>/<label>/{scope,reason,revisit}"; return 0; }
  _ok=1; _scope=""
  if ! mg_has "$_d/scope"; then refuse "$_id" "has no scope; write the glob it covers, or * for repo-wide"; _ok=0
  else
    _scope="$(mg_value "$_d/scope")"
    case "$_scope" in *[!" $tab"]*) ;; *) refuse "$_id" "has an empty scope; write the glob it covers, or * for repo-wide"; _ok=0 ;; esac
    [ "$(mg_lines "$_d/scope" | wc -l | tr -d ' ')" -le 1 ] || { refuse "$_id" "scope has a second line; a scope is one glob, on line 1"; _ok=0; }
  fi
  _reason=""
  if mg_has "$_d/reason"; then _reason="$(prose "$_d/reason")"; fi
  [ -n "$_reason" ] || { refuse "$_id" "declares no reason; say why the default does not fit here"; _ok=0; }
  _revisit=""
  if mg_has "$_d/revisit"; then _revisit="$(prose "$_d/revisit")"; fi
  [ -n "$_revisit" ] || { refuse "$_id" "has no revisit; say what evidence would end the deviation"; _ok=0; }
  [ "$_ok" -eq 1 ] || return 0
  _why="$(scope_refusal "$1" "$_scope")"
  [ -z "$_why" ] || { refuse "$_id" "$_why"; return 0; }
  printf '%s %s %s\n' "$1" "$(printf '%s\n' "$_scope" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e "s/$tab/%09/g")" "$_reason"
}

while IFS= read -r check; do
  [ -n "$check" ] || continue
  case "$check" in
    [a-z]*) case "$check" in *[!a-z0-9_-]*) refuse "$check" "\"$check\" cannot be a check id"; continue ;; esac ;;
    *) refuse "$check" "\"$check\" cannot be a check id"; continue ;;
  esac
  [ -d "$base/deviations/$check" ] || { refuse "$check" "is not a directory; a deviation is deviations/<check>/<label>/{scope,reason,revisit}"; continue; }
  while IFS= read -r label; do
    [ -n "$label" ] || continue
    one "$check" "$label"
  done <<EOF
$(mg_list "deviations/$check")
EOF
done <<EOF
$(mg_list deviations)
EOF

exit "$bad"
