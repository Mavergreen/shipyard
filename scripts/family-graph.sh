#!/bin/sh
# platform: host-agnostic
#   usage: family-graph.sh [--from-dir DIR]
#          Prints the family's ingredient graph: "<consumer> -> <ingredient>" for each repo that has a
#          family pin (an ingredient holding "product" and "REPO") on another repo, then "DIAMOND
#          <consumer>: <X> via <Y>" where the consumer pins both X and Y and Y reaches X, then
#          "CYCLE a -> b -> ... -> a", each cycle once, starting at its smallest name. Each group is
#          sorted. Nodes are repos.
#          Default: reads each repo of the Mavergreen org at its default branch with read-only `gh api`; a repo without .mavergreen/ingredients (404, or 409 if empty) has no pins
#          (needs gh). --from-dir DIR reads DIR/<repo>/.mavergreen/ingredients instead, for each
#          subdirectory of DIR that holds a .mavergreen.
#          stderr names what could not be read: "SKIP <repo>: <reason>" for an ingredient's repo with no clone
#          (or, without --from-dir, not in the org), "UNMAPPED <repo>: <name>" for an ingredient with a product and no
#          REPO. Exit 0 when everything was read; 3 when anything was skipped or unmapped (the graph
#          still prints); 1 when a REPO is malformed; 2 on a usage error or when gh fails.
# spec: tests/family-graph.bats
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
dir=""
case "$#:${1:-}" in
  0:) ;;
  2:--from-dir) dir="$2"; [ -d "$dir" ] || { echo "family-graph: $dir is not a directory" >&2; exit 2; } ;;
  *) echo "usage: family-graph.sh [--from-dir DIR]" >&2; exit 2 ;;
esac
[ -z "$dir" ] || dir="$(cd "$dir" && pwd)"

_tmp="${TMPDIR:-/tmp}"
tmp="$(mktemp -d "${_tmp%/}/family-graph.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/edges"; : > "$tmp/nodes"
bad=""; partial=""

skip() { partial=1; echo "SKIP $1: $2" >&2; }

gh_read() {
  _rc=0
  gh api "$@" < /dev/null > "$tmp/gh.out" 2> "$tmp/gh.err" || _rc=$?
  [ "$_rc" -ne 0 ] || return 0
  if grep -q 'HTTP 40[49]' "$tmp/gh.err"; then return 1; fi
  echo "family-graph: gh api $*: $(tr '\n' ' ' < "$tmp/gh.err")" >&2
  exit 2
}

fetch() {
  gh_read "repos/Mavergreen/$1/contents/.mavergreen/ingredients" --jq '.[] | select(.type == "dir") | .name' || return 1
  cp "$tmp/gh.out" "$tmp/names"
  mkdir -p "$tmp/clone/$1/.mavergreen/ingredients"
  while IFS= read -r _n; do
    [ -n "$_n" ] || continue
    mkdir -p "$tmp/clone/$1/.mavergreen/ingredients/$_n"
    for _f in product REPO; do
      if gh_read -H 'Accept: application/vnd.github.raw' "repos/Mavergreen/$1/contents/.mavergreen/ingredients/$_n/$_f"; then
        cp "$tmp/gh.out" "$tmp/clone/$1/.mavergreen/ingredients/$_n/$_f"
      fi
    done
  done < "$tmp/names"
}

read_pins() {
  MAVERGREEN_REPO_ROOT="$2"; export MAVERGREEN_REPO_ROOT
  for _n in $(mg_list ingredients); do
    [ -d "$2/.mavergreen/ingredients/$_n" ] || continue
    mg_has "ingredients/$_n/product" || continue
    _r=""
    if mg_has "ingredients/$_n/REPO"; then _r="$(mg_value "ingredients/$_n/REPO")"; fi
    if [ -z "$_r" ]; then
      partial=1
      echo "UNMAPPED $1: $_n" >&2
      continue
    fi
    case "$_r" in
      Mavergreen/?*) ;;
      *) echo "family-graph: $1: ingredient $_n: REPO '$_r' is not Mavergreen/<repo>" >&2; bad=1; continue ;;
    esac
    case "${_r#Mavergreen/}" in */*) echo "family-graph: $1: ingredient $_n: REPO '$_r' is not Mavergreen/<repo>" >&2; bad=1; continue ;; esac
    printf '%s %s\n' "$1" "${_r#Mavergreen/}" >> "$tmp/edges"
  done
}

if [ -n "$dir" ]; then
  for d in "$dir"/*/; do
    [ -d "${d}.mavergreen" ] || continue
    r="$(basename "$d")"
    echo "$r" >> "$tmp/nodes"
    read_pins "$r" "${d%/}"
  done
else
  _rc=0
  gh api --paginate orgs/Mavergreen/repos --jq '.[].name' < /dev/null > "$tmp/repos" 2> "$tmp/gh.err" || _rc=$?
  if [ "$_rc" -ne 0 ]; then
    echo "family-graph: gh api orgs/Mavergreen/repos: $(tr '\n' ' ' < "$tmp/gh.err")" >&2
    exit 2
  fi
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    echo "$r" >> "$tmp/nodes"
    if fetch "$r"; then read_pins "$r" "$tmp/clone/$r"; fi
  done < "$tmp/repos"
fi
[ -z "$bad" ] || exit 1

LC_ALL=C sort -u "$tmp/nodes" -o "$tmp/nodes"
while read -r _c _x; do
  grep -qx "$_x" "$tmp/nodes" && continue
  grep -qx "$_x" "$tmp/skipped" 2>/dev/null && continue
  echo "$_x" >> "$tmp/skipped"
  if [ -n "$dir" ]; then skip "$_x" "no clone in $dir"; else skip "$_x" "not a repo of the Mavergreen org"; fi
done < "$tmp/edges"

LC_ALL=C sort -u "$tmp/edges" | LC_ALL=C awk '
function reach(a, b,   i, n, m, ms) {
  if (seen[a]++) return 0
  n = split(adj[a], ms, " ")
  for (i = 1; i <= n; i++) {
    m = ms[i]
    if (m == b) return 1
    if (reach(m, b)) return 1
  }
  return 0
}
function reaches(a, b,   k) {
  split("", seen)
  return reach(a, b)
}
function walk(n, pl, disp, start,   i, k, ms, m) {
  k = split(adj[n], ms, " ")
  for (i = 1; i <= k; i++) {
    m = ms[i] ""
    if (m == start) cyc[disp " -> " start] = 1
    else if (m > start && index(pl, " " m " ") == 0) walk(m, pl m " ", disp " -> " m, start)
  }
}
{ adj[$1] = adj[$1] " " $2; deps[$1] = deps[$1] " " $2; nodes[$1] = 1; nodes[$2] = 1; print "1\t" $1 " -> " $2 }
END {
  for (c in deps) {
    n = split(deps[c], d, " ")
    for (i = 1; i <= n; i++) for (j = 1; j <= n; j++) {
      x = d[i]; y = d[j]
      if (y != x && y != c && x != c && reaches(y, x)) print "2\tDIAMOND " c ": " x " via " y
    }
  }
  for (s in nodes) walk(s, " " s " ", s, s)
  for (c in cyc) print "3\tCYCLE " c
}' | LC_ALL=C sort -u | cut -f2-
[ -z "$partial" ] || exit 3
exit 0
