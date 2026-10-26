#!/bin/sh
# platform: host-agnostic
#   usage: source-date-epoch.sh
#          Prints the timestamp every packaged artifact is stamped with: $SOURCE_DATE_EPOCH when set
#          (a non-negative integer, else exit 2), otherwise the commit time of HEAD in the current
#          repo. Exit 1, naming SOURCE_DATE_EPOCH, when neither is available.
set -eu
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  case "$SOURCE_DATE_EPOCH" in
    *[!0-9]*) echo "source-date-epoch: SOURCE_DATE_EPOCH is not a non-negative integer: $SOURCE_DATE_EPOCH" >&2; exit 2 ;;
  esac
  echo "$SOURCE_DATE_EPOCH"; exit 0
fi
if t="$(git log -1 --format=%ct 2>/dev/null)" && [ -n "$t" ]; then
  echo "$t"; exit 0
fi
echo "source-date-epoch: no SOURCE_DATE_EPOCH and no git history to take a commit time from; export SOURCE_DATE_EPOCH" >&2
exit 1
