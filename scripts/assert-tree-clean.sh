#!/bin/sh
#   usage: assert-tree-clean.sh --record   (before the build)
#          assert-tree-clean.sh            (after the build)

# spec: SKILL.md "Build OUT of the source tree, onto fast local storage" --
#       this asks only what the source tree looks like, never how the build
#       ran, so it holds for CMake, make, a shell script, or anything else
set -eu

if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "assert-tree-clean: $PWD is not a git checkout, or git is unavailable -- refusing to certify a tree nothing could read" >&2
  exit 1
fi

# spec: SKILL.md "Build OUT of the source tree, onto fast local storage" -- a manifest is
#       one checkout's pre-build state, so key it on that checkout: two clones, two jobs
#       sharing a runner, or one developer's second run must not inherit each other's.
key="$(printf '%s' "$root" | shasum -a 256 | cut -d' ' -f1)"
MANIFEST="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/mavericks-tree-manifest-$key"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/atc.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT INT TERM

# platform: `git status --porcelain -z` prints a rename as two NUL-separated
#           paths (old, then new); a build renaming a tracked file is not
#           the case this guards against, and a mislabelled entry is still
#           reported here, not silently passed.
# platform: `--ignored=traditional -uall` enumerates the files INSIDE an untracked or
#           ignored directory. Bare `--ignored` and `--ignored=matching` both collapse
#           such a directory to a single entry, so one that already existed at --record
#           would hide every file the build then wrote beneath it.
# platform: a pipeline's status is its LAST command's, so `git status | ... | sort` in a
#           command substitution turns any git failure into an empty snapshot and a clean
#           bill of health. Land the raw status in a file and check that command's status.
snapshot() {  # $1 = destination file
  git status --porcelain --ignored=traditional -uall -z > "$scratch/raw" || {
    echo "assert-tree-clean: git status failed in $root -- refusing to certify a tree it could not read" >&2
    exit 1
  }
  tr '\0' '\n' < "$scratch/raw" | sed 's/^...//' | LC_ALL=C sort > "$1"
}

if [ "${1:-}" = "--record" ]; then
  snapshot "$MANIFEST"
  echo "assert-tree-clean: recorded $(wc -l < "$MANIFEST" | tr -d ' ') pre-build paths"
  exit 0
fi

# spec: scripts/check-family-conventions.sh check 20 keys on a COMMITTED CMakePresets.json
#       for this reason: a build step can write an untracked file, and an allowlist the
#       build wrote for itself is not the reviewed allowlist this is meant to honour.
allowlist=""
if [ -f .mavericks-intree ] && git ls-files --error-unmatch .mavericks-intree >/dev/null 2>&1; then
  allowlist=.mavericks-intree
elif [ -f .mavericks-intree ]; then
  echo "assert-tree-clean: .mavericks-intree is not tracked by git, so nothing in it is being honoured -- commit it, or a build step could allowlist its own output" >&2
fi

patterns() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$allowlist"; }

allowed() {  # $1 = path
  [ -n "$allowlist" ] || return 1
  patterns | while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    case "$pat" in
      */) case "$1" in "$pat"*) echo yes; return ;; esac ;;
      *)  [ "$1" = "$pat" ] && { echo yes; return; } ;;
    esac
  done | grep -q yes
}

if [ -n "$allowlist" ]; then
  patterns | while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    case "$pat" in
      */) : ;;
      *)  [ ! -d "$pat" ] || echo "assert-tree-clean: .mavericks-intree allows '$pat', which is a directory; a bare entry is an exact match and matches nothing inside it -- write it as '$pat/' with the trailing slash" >&2 ;;
    esac
  done
fi

snapshot "$scratch/now"
if [ -f "$MANIFEST" ]; then
  added="$(LC_ALL=C comm -23 "$scratch/now" "$MANIFEST")"
  mode="against the pre-build manifest"
else
  added="$(cat "$scratch/now")"
  mode="with NO manifest (no --record was run), so EVERY untracked or ignored path counts"
fi

# platform: a `for p in $added` here would word-split a path containing a
#           space, and a `while read` in a pipeline cannot set a variable
#           the caller sees -- collect offenders in a file so neither trap
#           applies.
offenders="$scratch/offenders"
: > "$offenders"
printf '%s\n' "$added" | while IFS= read -r p; do
  [ -n "$p" ] || continue
  allowed "$p" && continue
  printf '%s\n' "$p" >> "$offenders"
done
if [ -s "$offenders" ]; then
  while IFS= read -r p; do
    echo "assert-tree-clean: the build wrote into the source tree: $p" >&2
  done < "$offenders"
  echo "assert-tree-clean: checked $mode" >&2
  echo "    fix: build outside the tree (\$MAVERICKS_BUILD_ROOT), or declare the path in .mavericks-intree with a reason" >&2
  exit 1
fi

if [ -n "$allowlist" ]; then
  patterns | while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    [ -e "$pat" ] || echo "assert-tree-clean: .mavericks-intree allows '$pat', which nothing wrote -- prune it" >&2
  done
fi
rm -f "$MANIFEST"
echo "assert-tree-clean: ok ($mode)"
