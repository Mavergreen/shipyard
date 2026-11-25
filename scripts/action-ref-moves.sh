#!/bin/sh
# platform: host-agnostic
#   usage: action-ref-moves.sh [--root DIR] FROM TO
#          Prints, one per line and sorted, "OWNER/REPO<TAB>OLD<TAB>NEW" for each GitHub Action whose
#          ref moved in .github/ between the commits FROM and TO: a changed line
#          "uses: OWNER/REPO[/PATH]@REF [# VERSION]" whose old and new lines differ only after the "@".
#          OLD and NEW are the line's "# VERSION" when it has one, else its REF.
#          Exit 0 when every change under .github/ is such a move, 1 when another change is there too
#          (it names those files on stderr, and still prints the moves), 2 on a usage or git error.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Release notes"
# spec: tests/check-release-version-test.sh
# spec: tests/release-notes-test.sh
set -eu

usage() { echo "usage: action-ref-moves.sh [--root DIR] FROM TO" >&2; exit 2; }

ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage; ROOT="${2%/}"; shift 2 ;;
    -*) echo "action-ref-moves: unknown option $1" >&2; usage ;;
    *) break ;;
  esac
done
[ $# -eq 2 ] || usage

# platform: these variables turn the :(glob) pathspec magic off.
unset GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/action-ref-moves.XXXXXX")"; trap 'rm -rf "$work"' EXIT

git -C "$ROOT" diff --no-color --no-ext-diff --no-renames --src-prefix=a/ --dst-prefix=b/ -U0 "$1" "$2" -- ':(glob).github/**' > "$work/diff" \
  || { echo "action-ref-moves: cannot diff $1 and $2 in $ROOT" >&2; exit 2; }

LC_ALL=C awk -v others="$work/others" '
  function parse(l) {
    if (l !~ /^[ \t]*(-[ \t]+)?uses:[ \t]*[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(\/[^@ \t]*)?@[^ \t#]+([ \t]+#.*)?$/) return 0
    at = index(l, "@"); head = substr(l, 1, at - 1); rest = substr(l, at + 1)
    ref = rest; sub(/[ \t].*$/, "", ref)
    ver = ""
    if (index(rest, "#")) { ver = substr(rest, index(rest, "#") + 1); sub(/^[ \t]+/, "", ver); sub(/[ \t]+$/, "", ver) }
    repo = head; sub(/^.*uses:[ \t]*/, "", repo)
    split(repo, part, "/"); repo = part[1] "/" part[2]
    return 1
  }
  function hunk(   i, oh, orepo, oshown) {
    if (nm != np) bad[file] = 1
    for (i = 1; i <= nm && !(file in bad); i++) {
      if (!parse(m[i])) { bad[file] = 1; break }
      oh = head; orepo = repo; oshown = (ver != "" ? ver : ref)
      if (!parse(p[i]) || head != oh) { bad[file] = 1; break }
      moved[orepo "\t" oshown "\t" (ver != "" ? ver : ref)] = 1
    }
    nm = 0; np = 0
  }
  function done() {
    if (inhunk) hunk()
    if (file != "" && !hunks) bad[file] = 1
    inhunk = 0; hunks = 0
  }
  /^diff --git / { done(); file = $0; sub(/^diff --git a\/.* b\//, "", file); next }
  /^@@/ { if (inhunk) hunk(); inhunk = 1; hunks++; next }
  /^\\/ { next }
  inhunk && /^-/ { m[++nm] = substr($0, 2); next }
  inhunk && /^\+/ { p[++np] = substr($0, 2); next }
  END {
    done()
    for (k in moved) print k
    for (f in bad) print f > others
  }' "$work/diff" > "$work/moves" || exit 2
LC_ALL=C sort -u "$work/moves"

if [ -s "$work/others" ]; then
  echo "action-ref-moves: .github/ changed other than an action's ref: $(LC_ALL=C sort "$work/others" | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')" >&2
  exit 1
fi
