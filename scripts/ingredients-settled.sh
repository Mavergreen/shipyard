#!/bin/sh
# platform: host-agnostic
#   usage: ingredients-settled.sh --repo OWNER/NAME --base REV --head REV [--labels L1,L2]
#                                 [--branch NAME] [--now EPOCH]
#          Run inside a checkout holding both revs. Exit 0 = settled (status success), 1 = waiting
#          (pending), 2 = could not tell (failure). One line per decision on stdout.
# spec: tests/ingredients-settled.bats
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/registry-lookup.sh"
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

value_of() {
  if [ -n "$2" ]; then pin_value "$1" "$2"; else tr -d '[:space:]' < "$1"; fi
}

declared_at() {
  mkdir -p "$work/$1"
  if git cat-file -e "$2:INGREDIENTS.md" 2>/dev/null; then
    git show "$2:INGREDIENTS.md" > "$work/$1/INGREDIENTS.md"
  fi
  sh "$SELF/declared-state.sh" "$work/$1" > "$work/$1.decl" 2> "$work/$1.err" \
    || fail "$repo's Declared state at $2: $(tr '\n' ' ' < "$work/$1.err")"
}

spec_of() { awk -F "$TAB" -v n="$1" '$1 == n { print $2; exit }' "$2"; }

local_value() {
  LV=""
  git show "$1:${2%%:*}" > "$work/lv" 2>/dev/null || return 1
  case "$2" in *:*) LV="$(value_of "$work/lv" "${2##*:}")" ;; *) LV="$(value_of "$work/lv" "")" ;; esac
  [ -n "$LV" ]
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

declared_at base "$base"
declared_at head "$head"

: > "$work/bumped"; : > "$work/pinned"
while IFS="$TAB" read -r name spec; do
  [ -n "$name" ] && [ "$name" != upstream ] || continue
  rc=0; registry_lookup repo "$name" || rc=$?
  case "$rc" in
    0) ;;
    1) continue ;;
    *) fail "cannot look up $name in shipyard's registry: $REG_WHY" ;;
  esac
  nrepo="$REG_V"
  local_value "$head" "$spec" || fail "$name is declared from $spec, which $head cannot read"
  new="$LV"
  printf '%s\t%s\t%s\n' "$name" "$nrepo" "$new" >> "$work/pinned"
  old_spec="$(spec_of "$name" "$work/base.decl")"
  local_value "$base" "${old_spec:-$spec}" || continue
  [ "$LV" != "$new" ] || continue
  is_version "$new" || fail "$name is pinned at '$new' in $head, which is not a version"
  printf '%s\t%s\t%s\n' "$name" "$nrepo" "$new" >> "$work/bumped"
done < "$work/head.decl"

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
  if [ ! -f "$_d.repos" ]; then
    mkdir -p "$_d"
    if gh_get raw "repos/Mavergreen/$1/contents/INGREDIENTS.md?ref=$YTAG"; then cp "$GH_OUT" "$_d/INGREDIENTS.md"; fi
    sh "$SELF/declared-state.sh" "$_d" < /dev/null > "$_d.decl" 2> "$_d.err" \
      || fail "Mavergreen/$1's Declared state at $YTAG: $(tr '\n' ' ' < "$_d.err")"
    : > "$_d.repos.part"
    while IFS="$TAB" read -r _n _s; do
      [ "$_n" != upstream ] || continue
      _rc=0; registry_lookup repo "$_n" < /dev/null || _rc=$?
      case "$_rc" in
        0) printf '%s\t%s\t%s\n' "$_n" "$_s" "$REG_V" >> "$_d.repos.part" ;;
        1) echo "::warning::$1: Declared state names $_n, which the registry doesn't know; its pins are not checked" ;;
        *) fail "cannot look up $_n in shipyard's registry: $REG_WHY" ;;
      esac
    done < "$_d.decl"
    mv "$_d.repos.part" "$_d.repos"
  fi
  awk -F "$TAB" -v r="$3" '$3 == r { print $1 "\t" $2 }' "$_d.repos" > "$_d.match"
  while IFS="$TAB" read -r _n _s; do
    gh_get raw "repos/Mavergreen/$1/contents/${_s%%:*}?ref=$YTAG" \
      || fail "Mavergreen/$1 declares $_n from $_s, which $YTAG does not have"
    case "$_s" in *:*) _v="$(value_of "$GH_OUT" "${_s##*:}")" ;; *) _v="$(value_of "$GH_OUT" "")" ;; esac
    [ -n "$_v" ] || fail "Mavergreen/$1 declares $_n from $_s, which is empty at $YTAG"
    is_version "$_v" || fail "Mavergreen/$1's $YTAG pins $_n at '$_v', which is not a version"
    if [ -z "$YPIN" ] || [ "$(mavergreen_vercmp "$_v" "$YPIN")" -lt 0 ]; then YPIN="$_v"; YPIN_NAME="$_n"; fi
  done < "$_d.match"
  [ -z "$YPIN" ] || return 0
  if gh_get raw "repos/Mavergreen/$1/contents/components/$2/version?ref=$YTAG"; then
    YPIN="$(value_of "$GH_OUT" "")"; YPIN_NAME="$2"
    [ -n "$YPIN" ] || fail "Mavergreen/$1's components/$2/version is empty at $YTAG"
  fi
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
    y_pin "$yrepo" "$x" "$xrepo"
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
