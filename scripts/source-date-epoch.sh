#!/bin/sh
# platform: host-agnostic
#   usage: source-date-epoch.sh
#          Prints the timestamp every packaged artifact is stamped with: $SOURCE_DATE_EPOCH when set
#          (a non-negative integer, else exit 2); else the commit time of HEAD in $MAVERICKS_ROOT when
#          that is a git work tree; else the commit time of HEAD in the current directory's repo, saying
#          on stderr which repo's time it took. Exit 1, naming SOURCE_DATE_EPOCH, when none is available.
set -eu
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  case "$SOURCE_DATE_EPOCH" in
    *[!0-9]*) echo "source-date-epoch: SOURCE_DATE_EPOCH is not a non-negative integer: $SOURCE_DATE_EPOCH" >&2; exit 2 ;;
  esac
  echo "$SOURCE_DATE_EPOCH"; exit 0
fi
if [ -n "${MAVERICKS_ROOT:-}" ] && [ "$(git -C "$MAVERICKS_ROOT" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] \
  && t="$(git -C "$MAVERICKS_ROOT" log -1 --format=%ct 2>/dev/null)" && [ -n "$t" ]; then
  echo "$t"; exit 0
fi
if [ -n "${MAVERICKS_ROOT:-}" ]; then
  echo "source-date-epoch: MAVERICKS_ROOT=$MAVERICKS_ROOT is not a git work tree with history; trying the current directory" >&2
fi
if top="$(git rev-parse --show-toplevel 2>/dev/null)" && t="$(git log -1 --format=%ct 2>/dev/null)" && [ -n "$t" ]; then
  echo "source-date-epoch: no SOURCE_DATE_EPOCH; using the commit time of $top" >&2
  echo "$t"; exit 0
fi
echo "source-date-epoch: no SOURCE_DATE_EPOCH and no git history to take a commit time from; export SOURCE_DATE_EPOCH" >&2
exit 1
