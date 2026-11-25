#!/bin/sh
# platform: host-agnostic
#   usage: release-version.sh --product SHORT [--root DIR] [--ref REV] [--mode auto|local] [--previous]
#          Prints the release tag the product's declared versioning scheme gives for REV (default
#          HEAD) in the repo at DIR (default .), and on stderr one line "release-version: <tag>: <why>".
#            port              <upstream>-mavericks.N from the declared upstream file (else
#                              UPSTREAM_VERSION), via version.sh MODE (auto|local, default auto);
#                              an untracked upstream file is first made by a tracked
#                              build/derive-upstream-version.sh or scripts/derive-upstream-version.sh.
#            self-upstream-date  self-upstream-version.sh's YYYYMMDD.N.
#            date-semver       self-upstream-version.sh --prefix v0.0.: v0.0.YYYYMMDD.N.
#            counter           v<L>.N for line L, line 1 of the upstream file (X.Y); N is one more than
#                              the largest N among the v<L>.N tags merged into REV, else 1.
#            semver            not yet derived.
#          --previous prints instead the newest tag of the scheme's shape merged into REV, excluding
#          the derived tag, or nothing. Shapes: port *-mavericks.N; self-upstream-date YYYYMMDD.N;
#          date-semver v0.0.YYYYMMDD.N; counter vX.Y.Z; semver vX.Y.Z or X.Y.Z. Order is lib.sh's
#          comparison_key/ver_cmp.
#          Exit 2 on a usage error, a non-repo, a shallow clone, an unknown REV, or a REV other than
#          HEAD for a scheme that reads the tree (port, counter, semver); 1 when versioning.sh refuses
#          or the scheme cannot derive.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Versioning"
# spec: tests/release-version-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"          # numeric(), ver_cmp(), comparison_key()

usage() { echo "usage: release-version.sh --product SHORT [--root DIR] [--ref REV] [--mode auto|local] [--previous]" >&2; exit 2; }

ROOT="."; REF="HEAD"; MODE="auto"; PRODUCT=""; PREVIOUS=no
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage; ROOT="${2%/}"; shift 2 ;;
    --ref) [ $# -ge 2 ] || usage; REF="$2"; shift 2 ;;
    --mode) [ $# -ge 2 ] || usage; MODE="$2"; shift 2 ;;
    --product) [ $# -ge 2 ] || usage; PRODUCT="$2"; shift 2 ;;
    --previous) PREVIOUS=yes; shift ;;
    *) echo "release-version: unknown option $1" >&2; usage ;;
  esac
done
[ -n "$PRODUCT" ] || usage
case "$MODE" in auto|local) : ;; *) echo "release-version: --mode must be auto or local" >&2; usage ;; esac

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "release-version: $ROOT is not a git repository" >&2
  exit 2
}
if [ "$(git -C "$ROOT" rev-parse --is-shallow-repository)" = true ]; then
  echo "release-version: the repo at $ROOT is a shallow clone, which hides the history and tags the version comes from" >&2
  echo "    release work needs fetch-depth: 0 and visible tags" >&2
  exit 2
fi
rev="$(git -C "$ROOT" rev-parse --verify -q "$REF^{commit}" 2>/dev/null)" || {
  echo "release-version: --ref '$REF' is not a revision of the repo at $ROOT" >&2
  exit 2
}

_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/release-version.XXXXXX")"; trap 'rm -rf "$work"' EXIT

sh "$SELF/versioning.sh" --root "$ROOT" --product "$PRODUCT" > "$work/decl" || exit 1
scheme="$(cut -f1 "$work/decl")"
upfile="$(cut -f2 "$work/decl")"

case "$scheme" in
  port|counter|semver)
    [ "$rev" = "$(git -C "$ROOT" rev-parse HEAD)" ] || {
      echo "release-version: $scheme reads the working tree, so --ref must be HEAD (got '$REF')" >&2
      exit 2
    } ;;
esac

[ -n "$upfile" ] || upfile=UPSTREAM_VERSION
shape=""
case "$scheme" in
  port)
    ROOT_ABS="$(cd "$ROOT" && pwd)"
    if ! git -C "$ROOT" ls-files --error-unmatch -- "$upfile" >/dev/null 2>&1; then
      for d in build/derive-upstream-version.sh scripts/derive-upstream-version.sh; do
        if git -C "$ROOT" ls-files --error-unmatch -- "$d" >/dev/null 2>&1; then
          (cd "$ROOT_ABS" && MAVERICKS_ROOT="$ROOT_ABS" SHIPYARD_SCRIPTS="$SELF" sh "$d" >&2) || exit 1
          break
        fi
      done
    fi
    [ -f "$ROOT_ABS/$upfile" ] || {
      echo "release-version: $PRODUCT is a port and $upfile does not exist, and no tracked derive-upstream-version.sh makes it" >&2
      exit 1
    }
    up="$(tr -d '[:space:]' < "$ROOT_ABS/$upfile")"
    [ -n "$up" ] || { echo "release-version: $upfile is empty" >&2; exit 1; }
    ( unset MAVERICKS_TAGS; MAVERICKS_ROOT="$ROOT_ABS" MAVERICKS_UPSTREAM_FILE="$ROOT_ABS/$upfile" sh "$SELF/version.sh" "$MODE" ) > "$work/v" || exit 1
    tag="$(sed -n 's/^FULL=//p' "$work/v")"
    case "$MODE" in
      auto) if [ "${tag##*.}" = 1 ] && [ -z "$(git -C "$ROOT" tag --list "$tag")" ]; then why="upstream $up has no -mavericks tag yet"; else why="upstream $up, current $tag"; fi ;;
      local) why="upstream $up, one past the newest -mavericks tag" ;;
    esac
    shape='-mavericks\.[0-9]+$'
    ;;
  self-upstream-date|date-semver)
    pfx=""; [ "$scheme" = date-semver ] && pfx="v0.0."
    _rc=0; sh "$SELF/self-upstream-version.sh" --root "$ROOT" --ref "$rev" --prefix "$pfx" >"$work/v" 2>"$work/e" || _rc=$?
    [ "$_rc" = 0 ] || { cat "$work/e" >&2; exit "$_rc"; }
    tag="$(cat "$work/v")"
    why="$(tail -n 1 "$work/e" | sed "s/^self-upstream-version: $tag: //")"
    if [ "$scheme" = date-semver ]; then shape='^v0\.0\.[0-9]{8}\.[0-9]+$'; else shape='^[0-9]{8}\.[0-9]+$'; fi
    ;;
  counter)
    [ -f "$ROOT/$upfile" ] || { echo "release-version: counter: $upfile does not exist" >&2; exit 1; }
    line="$(sed -n '1p' "$ROOT/$upfile" | tr -d '[:space:]')"
    case "$line" in
      [0-9]*.[0-9]*) case "$line" in *[!0-9.]*|*.*.*|.*|*.) line="" ;; esac ;;
      *) line="" ;;
    esac
    [ -n "$line" ] || {
      echo "release-version: counter: line 1 of $upfile must be X.Y (digits, one dot), got '$(sed -n '1p' "$ROOT/$upfile")'" >&2
      exit 1
    }
    git -C "$ROOT" tag --merged "$rev" > "$work/tags"
    maxn="$(LINE="$line" awk '
      BEGIN { p = "v" ENVIRON["LINE"] "."; max = 0 }
      index($0, p) == 1 { r = substr($0, length(p) + 1); if (r ~ /^[1-9][0-9]*$/ && r + 0 > max) max = r + 0 }
      END { print max }' "$work/tags")"
    tag="v$line.$((maxn + 1))"
    if [ "$maxn" = 0 ]; then why="no v$line tag merged into $REF yet"; else why="v$line.$maxn is the newest v$line tag merged into $REF"; fi
    shape='^v[0-9]+\.[0-9]+\.[0-9]+$'
    ;;
  semver)
    echo "release-version: semver: not yet" >&2
    exit 1 ;;
esac

if [ "$PREVIOUS" = yes ]; then
  git -C "$ROOT" tag --merged "$rev" | grep -E -- "$shape" > "$work/shape" || true
  best_tag=""; best_key=""
  while IFS= read -r t; do
    [ "$t" = "$tag" ] && continue
    k="$(comparison_key "${t#v}")"
    numeric "$k" || continue
    if [ -z "$best_key" ] || [ "$(ver_cmp "$k" "$best_key")" = 1 ]; then best_key="$k"; best_tag="$t"; fi
  done < "$work/shape"
  [ -z "$best_tag" ] || printf '%s\n' "$best_tag"
  exit 0
fi

echo "release-version: $tag: $why" >&2
printf '%s\n' "$tag"
