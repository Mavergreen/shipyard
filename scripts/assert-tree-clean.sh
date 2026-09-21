#!/bin/sh
#   usage: assert-tree-clean.sh --record   (before the build)
#          assert-tree-clean.sh            (after the build)
#
# The family's out-of-tree contract. It asks what the source tree looks like, never
# how the build was run -- so it holds for CMake, make, a shell script, a container
# image, and for a build system nobody has invented yet. A check that enumerated
# build mechanisms would exempt every new one by default, which is how clang and
# golang went unnoticed for a year.
#
# --record writes a manifest; the second call reports every path the build added.
# With NO manifest the check gets STRICTER, not weaker: nothing untracked or
# ignored may exist at all, except the allowlist. Getting the wiring wrong must
# fail loudly rather than pass quietly.
#
# .mavericks-intree lists paths a build may create: one per line, '#' starts a
# reason, a trailing '/' means a directory. Nothing broader -- a pattern wide
# enough to hide the next mistake defeats the point.
#
# `git status --porcelain -z` prints a rename as two NUL-separated paths (old,
# then new); a build renaming a tracked file is not the case this guards
# against, and a mislabelled entry is still reported, not silently passed.
set -eu

MANIFEST="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/mavericks-tree-manifest"

snapshot() { git status --porcelain --ignored -z | tr '\0' '\n' | sed 's/^...//' | sort; }

if [ "${1:-}" = "--record" ]; then
  snapshot > "$MANIFEST"
  echo "assert-tree-clean: recorded $(wc -l < "$MANIFEST" | tr -d ' ') pre-build paths"
  exit 0
fi

allowed() {  # $1 = path
  [ -f .mavericks-intree ] || return 1
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' .mavericks-intree | while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    case "$pat" in
      */) case "$1" in "$pat"*) echo yes; return ;; esac ;;
      *)  [ "$1" = "$pat" ] && { echo yes; return; } ;;
    esac
  done | grep -q yes
}

now="$(snapshot)"
if [ -f "$MANIFEST" ]; then
  added="$(printf '%s\n' "$now" | comm -23 - "$MANIFEST")"
  mode="against the pre-build manifest"
else
  added="$now"
  mode="with NO manifest (no --record was run), so EVERY untracked or ignored path counts"
fi

# A `for p in $added` here would word-split a path containing a space, and a
# `while read` in a pipeline cannot set a variable the caller sees. Collect
# offenders in a file so neither trap applies.
offenders="$(mktemp "${TMPDIR:-/tmp}/atc-offenders.XXXXXX")"
trap 'rm -f "$offenders"' EXIT INT TERM
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

# A stale allowlist is how this rots: report an entry nothing wrote.
if [ -f .mavericks-intree ]; then
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' .mavericks-intree | while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    [ -e "$pat" ] || echo "assert-tree-clean: .mavericks-intree allows '$pat', which nothing wrote -- prune it" >&2
  done
fi
echo "assert-tree-clean: ok ($mode)"
