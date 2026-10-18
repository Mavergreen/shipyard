#!/bin/sh
# platform: host-agnostic
#   usage: check-fixtures-run.sh [--strict] [--no-git] [--jobs N] [id...]
#          Runs every tests/fixtures/checks/<id>/{pass,pass-*,fail,fail-*}/ through the check that owns
#          <id>, on whatever host this is, with no git unless a fixture says it needs it. A pass
#          fixture exits 0. A fail fixture exits 1 and prints a message that opens with "<id>: " and
#          carries a fix line, and the ids it fails are exactly <id> plus those its ALSO file lists.
#          A fixture that cannot run here prints "SKIP <id>/<name>: <why>" and is counted; --strict
#          makes a skip a failure, except a host-bound one (NEEDS bash32 off a bash 3.2 /bin/sh: no
#          install helps, so it is counted apart). --no-git hides git (the fixtures that need it skip), which is how
#          a host without git runs them: it proves the rest need none. Zero fixtures is a failure. --jobs N runs N fixtures at once
#          (default: the CPU count, at most 8).
#          A fixture is a copy of its directory, and these files configure the run (they are not in
#          the copy):
#            ENV    VAR=value lines exported for the run ($FIXTURE is the copy; a bare NAME is NAME=$FIXTURE)
#            FILES  the tracked-file list: SHIPYARD_CHECK_FILES, or git's index when NEEDS says git
#            NEEDS  what the fixture cannot run without, one per line: a tool (git also makes the copy a git
#                   repo), or bash32, a bash 3.2 /bin/sh and /bin/bash
#            ALSO   other ids the fixture legitimately fails too, one per line, which the run selects
#                   beside <id> (* for any: an unparseable workflow trips every rule that reads workflows)
#            ARGS   the arguments of the id's own script, which then runs directly rather than through
#                   shipyard-check ($REMOTE is the copy, as a git remote)
#            TAGS   tags to create, one per line, in the copy's git repo (implies git)
#            RUN    tree-clean: record, then lay AFTER/ over the copy, then check (implies git)
#            dist/  shipyard-check --dist over it
# spec: scripts/shipyard-check -- every registered check has a passing and a failing fixture, and one
#       runner runs them all on all three hosts, so a new id's fixtures need no wiring.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
fx="$here/fixtures/checks"
reg="$root/scripts/check-ids.tsv"
. "$root/scripts/lib/macho-tools.sh"

strict=0; nogit=0; jobs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) strict=1; shift ;;
    --no-git) nogit=1; shift ;;
    --jobs) [ $# -ge 2 ] || { echo "usage: check-fixtures-run.sh [--strict] [--no-git] [--jobs N] [id...]" >&2; exit 2; }; jobs="$2"; shift 2 ;;
    -*) echo "usage: check-fixtures-run.sh [--strict] [--no-git] [--jobs N] [id...]" >&2; exit 2 ;;
    *) break ;;
  esac
done
want="$*"
if [ -z "$jobs" ]; then
  for probe in "getconf _NPROCESSORS_ONLN" "sysctl -n hw.ncpu" nproc; do
    jobs="$($probe 2>/dev/null)" || jobs=""
    case "$jobs" in ''|*[!0-9]*|0) jobs="" ;; *) break ;; esac
  done
  : "${jobs:=1}"
  [ "$jobs" -le 8 ] || jobs=8
fi
case "$jobs" in ''|*[!0-9]*|0) echo "check-fixtures-run: --jobs wants a positive integer" >&2; exit 2 ;; esac

unset GITHUB_REPOSITORY SHIPYARD_CHECK_FILES SHIPYARD_CHECK_RUNLOG SHIPYARD_CHECK_FAILLOG SHIPYARD_CHECK_NOTRUNLOG SHIPYARD_CHECK_SELECTED \
  SHIPYARD_CHECK_DIST SHIPYARD_CHECK_REPO SHIPYARD_CHECK_VERSION SHIPYARD_CHECK_ROOT SHIPYARD_CHECK_REGISTRY
w="$(mktemp -d "${TMPDIR:-/tmp}/check-fixtures-run.XXXXXX")"; trap 'rm -rf "$w"' EXIT
GIT_CEILING_DIRECTORIES="$w"; export GIT_CEILING_DIRECTORIES
mkdir "$w/bin"; cp "$here/lib/gh-stub.sh" "$w/bin/gh"; chmod +x "$w/bin/gh"

# platform: 10.9's /usr/bin/git is a shim that fails without the Command Line Tools, and a git that cannot run is no git.
have_git=0; git --version >/dev/null 2>&1 && have_git=1
if [ "$nogit" -eq 1 ]; then
  have_git=0
  mkdir "$w/nogit"; printf '#!/bin/sh\necho "git: hidden by check-fixtures-run --no-git" >&2\nexit 127\n' > "$w/nogit/git"
  chmod +x "$w/nogit/git"; PATH="$w/nogit:$PATH"; export PATH
fi
have_bash32=1
for sh_ in /bin/sh /bin/bash; do
  case "$("$sh_" -c 'printf %s "$BASH_VERSION"' 2>/dev/null || true)" in 3.2.*) ;; *) have_bash32=0 ;; esac
done
have_llvm=1
mach_tool OTOOL 2>/dev/null && mach_tool LIPO 2>/dev/null && mach_tool NM 2>/dev/null && mach_tool STRINGS 2>/dev/null || have_llvm=0

script_of() { awk -F'\t' -v i="$1" '$1 == i { print $3 }' "$reg"; }
mode_of() { awk -F'\t' -v i="$1" '$1 == i { print $2 }' "$reg"; }

apply_env() {  # $1 = fixture dir, $2 = the copy
  [ -f "$1/ENV" ] || return 0
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    case "$l" in
      *=*) v="$(printf '%s' "${l#*=}" | sed 's|\$FIXTURE|'"$2"'|g')"; export "${l%%=*}=$v" ;;
      *) export "$l=$2" ;;
    esac
  done < "$1/ENV"
}

make_repo() {  # $1 = fixture dir, $2 = the copy: a git repo holding FILES (or everything), with TAGS
  (
    cd "$2"
    git init -q || exit 1
    if [ -f "$1/FILES" ]; then
      while IFS= read -r f; do [ -z "$f" ] || git add -f -- "$f"; done < "$1/FILES"
    else
      git add -f -A .
    fi
    git -c user.email=fixture@example.invalid -c user.name=fixture commit -q --allow-empty -m fixture || exit 1
    if [ -f "$1/TAGS" ]; then
      while IFS= read -r t; do [ -z "$t" ] || git tag "$t"; done < "$1/TAGS"
    fi
  ) > /dev/null 2>&1
}

run_fixture() {  # $1 = id, $2 = mode, $3 = fixture dir, $4 = scratch dir; sets $rc, output in $4/out
  _id="$1"; _mode="$2"; d="$3"; s="$4"
  rm -rf "$s/copy"; mkdir "$s/copy"
  (cd "$d" && tar cf - .) | (cd "$s/copy" && tar xf -)
  for m in ENV FILES NEEDS ALSO ARGS TAGS RUN AFTER; do rm -rf "${s:?}/copy/$m"; done
  c="$s/copy"
  usegit=0
  [ ! -f "$d/TAGS" ] && [ ! -f "$d/RUN" ] || usegit=1
  if [ -f "$d/NEEDS" ] && grep -qx git "$d/NEEDS"; then usegit=1; fi
  if [ "$usegit" -eq 1 ]; then
    make_repo "$d" "$c" || { echo "git could not make the fixture's repo" > "$s/out"; rc=125; return 0; }
  fi
  sel="$_id"
  if [ -f "$d/ALSO" ]; then sel="$sel $(grep -vx '\*' "$d/ALSO" | tr '\n' ' ')"; fi
  rc=0
  (
    cd "$c"
    RUNNER_TEMP="$s/rt"; export RUNNER_TEMP; rm -rf "$RUNNER_TEMP"; mkdir "$RUNNER_TEMP"
    apply_env "$d" "$c"
    if [ -f "$d/FILES" ] && [ "$usegit" -eq 0 ]; then SHIPYARD_CHECK_FILES="$d/FILES"; export SHIPYARD_CHECK_FILES; fi
    if [ -d "$d/dist" ]; then
      SHIPYARD_CHECK_REPO="$c"; export SHIPYARD_CHECK_REPO
      exec sh "$root/scripts/shipyard-check" --dist "$c/dist" --only $sel
    fi
    if [ -f "$d/RUN" ]; then
      sh "$root/scripts/assert-tree-clean.sh" --record > /dev/null
      if [ -d "$d/AFTER" ]; then (cd "$d/AFTER" && tar cf - .) | tar xf -; fi
      exec sh "$root/scripts/shipyard-check" --only $sel
    fi
    if [ "$_mode" = repo-state ]; then
      GH_STUB="$c"; PATH="$w/bin:$PATH"; export GH_STUB PATH
      exec sh "$root/scripts/shipyard-check" --only $sel
    fi
    if [ -f "$d/ARGS" ]; then
      REMOTE="$c"; export REMOTE
      eval "set -- $(cat "$d/ARGS")"
      exec sh "$root/$(script_of "$_id")" "$@"
    fi
    exec sh "$root/scripts/shipyard-check" --only $sel
  ) > "$s/out" 2>&1 < /dev/null || rc=$?
}

check_one() {  # $1 = scratch dir, $2 = "<id> <name>"; prints FAIL or SKIP lines and one of F, S, R on fd 3
  s="$1"; id="${2%% *}"; name="${2#* }"
  d="$fx/$id/$name"; mode="$(mode_of "$id")"
  : > "$s/out"; hostbound=0
  bad() { echo "FAIL $id/$name: $1"; if [ -s "$s/out" ]; then sed 's/^/    | /' "$s/out"; fi; echo F >&3; }
  skip() { echo "SKIP $id/$name: $1"; if [ "${hostbound:-0}" -eq 1 ]; then echo H >&3; else echo S >&3; fi; }
  if [ -z "$mode" ]; then bad "tests/fixtures/checks/$id is not a registered check id"; return 0; fi
  case "$name" in
    pass|pass-*) kind=pass ;;
    fail|fail-*) kind=fail ;;
    *) bad "a fixture is named pass, pass-*, fail or fail-*"; return 0 ;;
  esac
  if [ -f "$d/NEEDS" ]; then
    miss=""
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      if [ "$t" = git ] && [ "$have_git" -eq 0 ]; then miss="$miss git"; continue; fi
      if [ "$t" = bash32 ]; then
        [ "$have_bash32" -eq 1 ] || { miss="$miss a bash 3.2 /bin/sh and /bin/bash"; hostbound=1; }
        continue
      fi
      command -v "$t" >/dev/null 2>&1 || miss="$miss $t"
    done < "$d/NEEDS"
    if [ -n "$miss" ]; then skip "needs${miss}"; return 0; fi
  fi
  if [ "$have_git" -eq 0 ] && { [ -f "$d/TAGS" ] || [ -f "$d/RUN" ]; }; then skip "needs git"; return 0; fi
  if [ -d "$d/dist" ] && [ "$have_llvm" -eq 0 ] && ls "$d"/dist/*.tar.gz >/dev/null 2>&1; then
    skip "needs LLVM's Mach-O readers"; return 0
  fi
  run_fixture "$id" "$mode" "$d" "$s"
  if [ "$rc" -eq 77 ]; then skip "$(sed -n 's/^SKIP: //p' "$s/out" | head -n 1)"; return 0; fi
  if [ "$kind" = pass ]; then
    if [ "$rc" -ne 0 ]; then bad "should pass, exit $rc"; else echo R >&3; fi
    return 0
  fi
  if [ "$rc" -ne 1 ]; then bad "should exit 1, got $rc"; return 0; fi
  if ! awk -v id="$id" 'index($0, id ": ") == 1 { hit = 1; next } hit && /^  fix: / { ok = 1; exit } { hit = 0 } END { exit !ok }' "$s/out"; then
    bad "should print a message that opens with '$id: ' and carries a fix line"; return 0
  fi
  got="$(sed -n 's/^  more: shipyard-check --explain //p' "$s/out" | sort -u)"
  expect="$( { echo "$id"; [ ! -f "$d/ALSO" ] || cat "$d/ALSO"; } | sort -u)"
  if [ -f "$d/ALSO" ] && grep -qx '\*' "$d/ALSO"; then
    printf '%s\n' "$got" | grep -qx "$id" || { bad "should fail $id, failed: $(echo $got)"; return 0; }
  elif [ "$got" != "$expect" ]; then
    bad "should fail $(echo $expect), failed: $(echo $got)"; return 0
  fi
  echo R >&3
}

: > "$w/list"
for idd in "$fx"/*/; do
  id="$(basename "$idd")"
  if [ -n "$want" ]; then case " $want " in *" $id "*) ;; *) continue ;; esac; fi
  n=0
  for d in "$idd"*/; do
    [ -d "$d" ] || continue
    printf '%s %s\n' "$id" "$(basename "$d")" >> "$w/list"; n=$((n + 1))
  done
  [ "$n" -gt 0 ] || printf '%s -\n' "$id" >> "$w/list"
done
total="$(wc -l < "$w/list" | tr -d ' ')"
if [ "$total" -eq 0 ]; then echo "FAIL no fixtures found under tests/fixtures/checks"; exit 1; fi

worker() {  # $1 = worker number
  k="$1"; s="$w/w$k"; mkdir "$s"
  awk -v k="$k" -v n="$jobs" '(NR - 1) % n == k' "$w/list" | while IFS= read -r entry; do
    case "$entry" in
      *" -") echo "FAIL ${entry% -}: has no fixtures" ;;
      *) check_one "$s" "$entry" ;;
    esac
  done > "$w/log.$k" 3> "$w/res.$k"
}
k=0
while [ "$k" -lt "$jobs" ]; do worker "$k" & k=$((k + 1)); done
wait

k=0
while [ "$k" -lt "$jobs" ]; do cat "$w/log.$k"; k=$((k + 1)); done
cat "$w"/res.* > "$w/res.all"
ran="$(grep -c '^R$' "$w/res.all" || true)"
skipped="$(grep -c '^S$' "$w/res.all" || true)"
hostbound="$(grep -c '^H$' "$w/res.all" || true)"
failed="$(grep -c '^F$' "$w/res.all" || true)"
if [ $((ran + skipped + hostbound + failed)) -ne "$total" ]; then
  echo "FAIL accounting: $total fixtures, but $ran ran, $skipped skipped, $hostbound host-bound, $failed failed"; failed=$((failed + 1))
fi
if [ "$strict" -eq 1 ] && [ "$skipped" -gt 0 ]; then
  echo "FAIL --strict: $skipped fixture(s) skipped"; failed=$((failed + 1))
fi
if [ "$failed" -gt 0 ]; then
  echo "check-fixtures-run: $total fixtures, $ran ran, $skipped skipped, $hostbound host-bound, $failed failed"
  exit 1
fi
echo "PASS check-fixtures-run: $total fixtures, $ran ran, $skipped skipped, $hostbound host-bound"
