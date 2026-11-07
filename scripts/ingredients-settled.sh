#!/bin/sh
# platform: host-agnostic
#   usage: ingredients-settled.sh --repo OWNER/NAME --base REV --head REV [--labels L1,L2]
#                                 [--branch NAME] [--now EPOCH]
#          Run inside a checkout holding both revs. Exit 0 = settled (status success), 1 = waiting
#          (pending), 2 = could not tell (failure). One line per decision on stdout.
# spec: tests/ingredients-settled.bats
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"

work=""; _decided=""
finish() { _decided=1; exit "$1"; }
fail() { printf 'FAILED %s\n' "$*"; finish 2; }
on_exit() {
  _rc=$?
  [ -z "$work" ] || rm -rf "$work"
  if [ -z "$_decided" ] && [ "$_rc" -ne 0 ]; then
    printf 'FAILED unexpected error (exit %s)\n' "$_rc"
    exit 2
  fi
}
trap on_exit EXIT

repo=""; base=""; head=""; labels=""; branch=""; now=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || fail "usage: $1 needs a value"
  case "$1" in
    --repo) repo="$2" ;;
    --base) base="$2" ;;
    --head) head="$2" ;;
    --labels) labels="$2" ;;
    --branch) branch="$2" ;;
    --now) now="$2" ;;
    *) fail "usage: unknown argument $1" ;;
  esac
  shift 2
done
[ -n "$repo" ] && [ -n "$base" ] && [ -n "$head" ] || fail "usage: --repo, --base and --head are required"
self_repo="${repo#*/}"
[ -n "$now" ] || now="$(date +%s)"
case "$now" in ''|*[!0-9]*) fail "usage: --now '$now' is not an epoch" ;; esac

if [ -n "$branch" ]; then
  case "$branch" in
    renovate/*) ;;
    *) echo "NOT-CHECKED $branch is not a Renovate branch"; finish 0 ;;
  esac
fi

_old_ifs="$IFS"; IFS=,
for l in $labels; do
  l="$(printf '%s' "$l" | tr -d '[:space:]')"
  case "$l" in
    urgent|security)
      echo "::notice::ingredients-settled: labelled $l, so not waiting for upstreams"
      echo "SETTLED labelled $l"
      finish 0 ;;
  esac
done
IFS="$_old_ifs"

base="$(git rev-parse --verify --quiet "$base^{commit}" 2>/dev/null)" || fail "--base $base is not a revision of this checkout"
head="$(git rev-parse --verify --quiet "$head^{commit}" 2>/dev/null)" || fail "--head $head is not a revision of this checkout"

_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/ingredients-settled.XXXXXX")"
mkdir -p "$work/cache"
TAB="$(printf '\t')"

value_of() { head -n 1 "$1" | tr -d '[:space:]'; }

ingredients_at() {
  git cat-file -e "$1:.mavergreen/ingredients" 2>/dev/null || return 1
  git ls-tree -d --name-only "$1:.mavergreen/ingredients" || fail "cannot list .mavergreen/ingredients at $1"
}

ingredient_file() {
  git cat-file -e "$1:.mavergreen/ingredients/$2/$3" 2>/dev/null || return 1
  git show "$1:.mavergreen/ingredients/$2/$3" > "$work/if" 2>/dev/null || fail "cannot read .mavergreen/ingredients/$2/$3 at $1"
  IF="$(value_of "$work/if")"
  [ -n "$IF" ]
}

local_pin() {
  LPIN=""
  ingredient_file "$1" "$2" product || return 1
  ingredient_file "$1" "$2" REPO || return 2
  case "$IF" in Mavergreen/?*) ;; *) fail "$2's REPO at $1 is '$IF', not Mavergreen/<repo>" ;; esac
  LREPO="${IF#*/}"
  ingredient_file "$1" "$2" VERSION || fail "$2 has a product and a REPO at $1, but no VERSION"
  LPIN="$IF"
}

is_version() { _iv=0; mavergreen_vercmp "$1" "$1" >/dev/null || _iv=$?; [ "$_iv" -ne 2 ]; }

GH_OUT=""
gh_get() {
  _key="$(printf '%s' "$2" | sed 's|/|__|g; s|?|_Q_|g; s|=|_E_|g; s|[^A-Za-z0-9._-]|_|g')"
  GH_OUT="$work/cache/$_key"
  [ ! -f "$GH_OUT.404" ] || return 1
  [ ! -f "$GH_OUT" ] || return 0
  _rc=0
  if [ "$1" = raw ]; then
    gh api -H 'Accept: application/vnd.github.raw' "$2" < /dev/null > "$GH_OUT.part" 2> "$work/gh-err" || _rc=$?
  else
    gh api "$2" < /dev/null > "$GH_OUT.part" 2> "$work/gh-err" || _rc=$?
  fi
  if [ "$_rc" -eq 0 ]; then mv "$GH_OUT.part" "$GH_OUT"; return 0; fi
  if grep -q '(HTTP 404)' "$work/gh-err"; then : > "$GH_OUT.404"; return 1; fi
  fail "gh api $2: $(tr '\n' ' ' < "$work/gh-err")"
}

release_of() {
  python3 - "$1" "$2" <<'PY'
import calendar, json, sys, time
mode, path = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        d = json.load(f)
except ValueError:
    sys.exit("not JSON")
if not isinstance(d, dict):
    sys.exit("not a release object")
tag, pub = d.get("tag_name"), d.get("published_at")
if not isinstance(tag, str) or not tag or not isinstance(pub, str):
    sys.exit("no tag_name or published_at")
if mode == "latest" and (d.get("draft") is not False or d.get("prerelease") is not False):
    sys.exit("draft or prerelease")
try:
    epoch = calendar.timegm(time.strptime(pub, "%Y-%m-%dT%H:%M:%SZ"))
except ValueError:
    sys.exit("published_at %r is not a timestamp" % pub)
print("%s %d" % (tag, epoch))
PY
}

dir_names() {
  python3 - "$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except ValueError:
    sys.exit("not JSON")
if not isinstance(d, list):
    sys.exit("not a directory listing")
for e in d:
    if isinstance(e, dict) and e.get("type") == "dir" and isinstance(e.get("name"), str):
        print(e["name"])
PY
}

: > "$work/bumped"; : > "$work/pinned"
if ingredients_at "$base" > "$work/base.names"; then :; else
  echo "::notice::ingredients-settled: no family pin at $base"
fi
ingredients_at "$head" > "$work/head.names" || : > "$work/head.names"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  _lp=0; local_pin "$head" "$name" || _lp=$?
  case "$_lp" in
    0) ;;
    2) echo "::warning::ingredients-settled: $name has a product and no REPO at $head; not checked"; continue ;;
    *) continue ;;
  esac
  nrepo="$LREPO"; new="$LPIN"
  printf '%s\t%s\t%s\n' "$name" "$nrepo" "$new" >> "$work/pinned"
  local_pin "$base" "$name" || continue
  [ "$LPIN" != "$new" ] || continue
  is_version "$new" || fail "$name is pinned at '$new' in $head, which is not a version"
  printf '%s\t%s\t%s\n' "$name" "$nrepo" "$new" >> "$work/bumped"
done < "$work/head.names"

[ -s "$work/bumped" ] || { echo "SETTLED no Mavergreen ingredient changed"; finish 0; }

YTAG=""
y_release() {
  if [ -f "$work/cache/$1.tag" ]; then YTAG="$(cat "$work/cache/$1.tag")"; return 0; fi
  gh_get json "repos/Mavergreen/$1/releases/latest" || fail "Mavergreen/$1 has no published release"
  _r="$(release_of latest "$GH_OUT" 2>&1)" || fail "Mavergreen/$1's latest release: $_r"
  YTAG="${_r% *}"
  printf '%s\n' "$YTAG" > "$work/cache/$1.tag"
}

YPIN=""; YPIN_NAME=""
y_pin() {
  YPIN=""; YPIN_NAME=""
  _d="$work/y-$1"
  if [ ! -f "$_d.pins" ]; then
    : > "$_d.pins.part"
    if gh_get json "repos/Mavergreen/$1/contents/.mavergreen/ingredients?ref=$YTAG"; then
      dir_names "$GH_OUT" > "$_d.names" 2> "$_d.err" || fail "Mavergreen/$1's .mavergreen/ingredients at $YTAG: $(tr '\n' ' ' < "$_d.err")"
      while IFS= read -r _n; do
        _b="repos/Mavergreen/$1/contents/.mavergreen/ingredients/$_n"
        gh_get raw "$_b/product?ref=$YTAG" < /dev/null || continue
        _r=""
        if gh_get raw "$_b/REPO?ref=$YTAG" < /dev/null; then _r="$(value_of "$GH_OUT")"; fi
        if [ -z "$_r" ]; then
          echo "::warning::$1: ingredient $_n has a product and no REPO; its pin is not checked"
          continue
        fi
        case "$_r" in Mavergreen/?*) ;; *) fail "Mavergreen/$1's ingredient $_n at $YTAG has REPO '$_r', not Mavergreen/<repo>" ;; esac
        gh_get raw "$_b/VERSION?ref=$YTAG" < /dev/null \
          || fail "Mavergreen/$1's ingredient $_n at $YTAG has a REPO but no VERSION"
        _v="$(value_of "$GH_OUT")"
        [ -n "$_v" ] || fail "Mavergreen/$1's ingredient $_n at $YTAG has an empty VERSION"
        is_version "$_v" || fail "Mavergreen/$1's $YTAG pins $_n at '$_v', which is not a version"
        printf '%s\t%s\t%s\n' "$_n" "${_r#*/}" "$_v" >> "$_d.pins.part"
      done < "$_d.names"
    else
      echo "::notice::ingredients-settled: no family pin at $YTAG ($1)"
    fi
    mv "$_d.pins.part" "$_d.pins"
  fi
  while IFS="$TAB" read -r _n _pr _v; do
    [ "$_pr" = "$2" ] || continue
    if [ -z "$YPIN" ] || [ "$(mavergreen_vercmp "$_v" "$YPIN")" -lt 0 ]; then YPIN="$_v"; YPIN_NAME="$_n"; fi
  done < "$_d.pins"
  return 0
}

: > "$work/settled"; : > "$work/lagging"
while IFS="$TAB" read -r x xrepo xv; do
  seen=" "
  while IFS="$TAB" read -r y yrepo ypr; do
    [ "$y" != "$x" ] && [ "$yrepo" != "$xrepo" ] && [ "$yrepo" != "$self_repo" ] || continue
    case "$seen" in *" $yrepo "*) continue ;; esac
    seen="$seen$yrepo "
    y_release "$yrepo"
    y_pin "$yrepo" "$xrepo"
    [ -n "$YPIN" ] || continue
    c=0; cmp="$(mavergreen_vercmp "$YPIN" "$xv")" || c=$?
    [ "$c" -eq 0 ] || fail "$y's $YTAG pins $YPIN_NAME at '$YPIN', which is not a version"
    if [ "$cmp" -lt 0 ]; then
      printf '%s\t%s\n' "$y for $x $xv ($y $YTAG pins $YPIN_NAME $YPIN)" \
        "$y has not caught up with $x $xv ($y $YTAG pins $YPIN_NAME $YPIN)" >> "$work/lagging"
      continue
    fi
    c=0; took="$(mavergreen_vercmp "$ypr" "${YTAG#v}")" || c=$?
    [ "$c" -eq 0 ] || fail "this PR pins $y at '$ypr', or its latest release is tagged '$YTAG': not both versions"
    if [ "$took" -lt 0 ]; then
      printf '%s\t%s\n' "$repo to take $y ${YTAG#v} (it carries $x $xv)" \
        "$repo has not taken $y ${YTAG#v} (it carries $x $xv)" >> "$work/lagging"
      continue
    fi
    echo "SETTLED $y for $x $xv ($y $YTAG pins $YPIN_NAME $YPIN)" >> "$work/settled"
  done < "$work/pinned"
done < "$work/bumped"

if [ ! -s "$work/lagging" ]; then
  if [ -s "$work/settled" ]; then cat "$work/settled"; else
    echo "SETTLED no other pinned product pins $(cut -f1 "$work/bumped" | tr '\n' ' ' | sed 's/ $//')"
  fi
  finish 0
fi

newest=0; newest_what=""
while IFS="$TAB" read -r x xrepo xv; do
  found=""
  for t in "$xv" "v$xv"; do
    if gh_get json "repos/Mavergreen/$xrepo/releases/tags/$t"; then found="$GH_OUT"; break; fi
  done
  [ -n "$found" ] || fail "Mavergreen/$xrepo has no release tagged $xv or v$xv"
  _r="$(release_of tag "$found" 2>&1)" || fail "Mavergreen/$xrepo's release $xv: $_r"
  if [ "${_r#* }" -gt "$newest" ]; then newest="${_r#* }"; newest_what="$x $xv"; fi
done < "$work/bumped"
deadline=$((newest + 86400))

if [ "$now" -ge "$deadline" ]; then
  cut -f2 "$work/lagging" | sed 's/^/::warning::ingredients-settled: /'
  echo "RELEASED-ANYWAY 24h after $newest_what was published"
  finish 0
fi
cut -f1 "$work/lagging" | sed 's/^/WAITING /'
left=$((deadline - now))
echo "WAITING at most $((left / 3600))h$(printf '%02d' $((left % 3600 / 60)))m more (24h after $newest_what was published)"
finish 1
