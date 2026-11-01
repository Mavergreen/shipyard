#!/bin/sh
# platform: host-agnostic
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
chk_ran deviation-complete
chk_ran deviation-known-check
chk_ran deviation-scope-matches
[ -f INGREDIENTS.md ] || exit 0

_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/check-deviations.XXXXXX")"
trap 'rm -rf "$w"' EXIT

rc=0
sh "$SELF/deviations.sh" . > "$w/parsed" 2> "$w/err" || rc=$?
if [ "$rc" -ne 0 ]; then
  chk_fail deviation-complete "INGREDIENTS.md declares a conformance deviation that deviations.sh refuses" \
    "an exception without a reason, or with a scope its check cannot honour, is indistinguishable from drift; deviations.sh says which, below" \
    "give every '- <check>[:<glob>]:' entry its reason on the same line, and fix any scope deviations.sh names"
  cat "$w/err" >&2
fi

retired_fix() {
  case "$1" in
    product-layout) echo "now \`stage-product\` (and \`registered\`)" ;;
    artifact-conformance) echo "now \`artifact-checks-wired\`" ;;
    scheme) echo "now \`version-scheme\`" ;;
    ingredients) echo "now \`variant-build-info\`" ;;
    sparkle-updater|release-assets|python3) echo "no check reads this; delete the line" ;;
    *) return 1 ;;
  esac
}

chk_tracked_files > "$w/tracked" || exit 2

while read -r key glob _reason; do
  [ -n "$key" ] || continue
  if fix="$(retired_fix "$key")"; then
    chk_fail deviation-known-check "INGREDIENTS.md declares a deviation for the retired check name \"$key\"" \
      "no check reads a deviation under that name any more" "$fix"
    continue
  fi
  if ! chk_registered "$key"; then
    chk_fail deviation-known-check "INGREDIENTS.md declares a deviation for \"$key\", which is not a check id" \
      "a deviation naming a check that does not exist excuses nothing" \
      "name an id from \`shipyard-check --list\`, or delete the line"
    continue
  fi
  [ "$glob" != '*' ] || continue
  if [ "$key" = comments ]; then
    chk_fail deviation-scope-matches "INGREDIENTS.md scopes the comments deviation to \"$glob\"" \
      "a comments deviation is repo-wide only, and a glob is not honoured" \
      "drop the glob: write \"- comments: <reason>\""
    continue
  fi
  case "$key" in on-target|macos-runner) continue ;; esac
  [ "$(awk -F'\t' -v k="$key" '$1 == k { print $2 }' "$SHIPYARD_CHECK_REGISTRY")" = checkout ] || continue
  hit=0
  while IFS= read -r f; do
    case "$f" in $glob) hit=1; break ;; esac
  done < "$w/tracked"
  [ "$hit" -eq 1 ] || chk_fail deviation-scope-matches "the \"$key\" deviation scopes itself to \"$glob\", which matches no tracked file" \
    "an exception that covers nothing is stale or mistyped" \
    "correct the glob to match a tracked path, or delete the entry"
done < "$w/parsed"

exit "$chk_status"
