#!/bin/sh
# platform: host-agnostic
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
. "$SELF/deviation-reason.sh"
. "$SELF/mavergreen-meta.sh"
chk_ran deviation-complete
chk_ran deviation-known-check
chk_ran deviation-scope-matches
[ -d .mavergreen/deviations ] || exit 0
MAVERGREEN_ROOT="$(pwd)"

_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/check-deviations.XXXXXX")"
trap 'rm -rf "$w"' EXIT

rc=0
shipyard_deviations . > /dev/null 2> "$w/err" || rc=$?
if [ "$rc" -ne 0 ]; then
  chk_fail deviation-complete "a deviation under .mavergreen/deviations/ is incomplete or malformed" \
    "an exception without a scope, a reason and a revisit trigger, or with a scope its check cannot honour, is indistinguishable from drift; deviations.sh says which, below" \
    "give each deviations/<check>/<label>/ a one-line scope, a reason and a revisit, under a label of lowercase letters, digits, dots and dashes, and fix any scope deviations.sh names"
  cat "$w/err" >&2
fi

retired_fix() {
  case "$1" in
    product-layout) echo "now \`stage-product\` (and \`registered\`)" ;;
    artifact-conformance) echo "now \`artifact-checks-wired\`" ;;
    scheme) echo "now \`version-scheme\`" ;;
    ingredients) echo "now \`variant-build-info\`" ;;
    msc-template) echo "now the \`shipyard-scripts\` command; delete the directory" ;;
    upstream-version) echo "now \`upstream-complete\`, which reads no deviation; delete the directory" ;;
    upstream-version-bare) echo "now \`value-file-line\`; move the directory to .mavergreen/deviations/value-file-line/" ;;
    sparkle-updater|release-assets|python3) echo "no check reads this; delete the directory" ;;
    *) return 1 ;;
  esac
}

chk_tracked_files > "$w/tracked" || exit 2

while IFS= read -r key; do
  case "$key" in ''|*[!a-z0-9_-]*|[!a-z]*) continue ;; esac
  if fix="$(retired_fix "$key")"; then
    chk_fail deviation-known-check ".mavergreen/deviations/$key/ is a deviation for the retired check name \"$key\"" \
      "no check reads a deviation under that name any more" "$fix"
    continue
  fi
  if ! chk_registered "$key"; then
    chk_fail deviation-complete ".mavergreen/deviations/$key/ is a deviation for \"$key\", which is not a check id" \
      "a deviation naming a check that does not exist excuses nothing" \
      "name an id from \`shipyard-check --list\`, or delete the directory"
    continue
  fi
  case "$key" in on-target|macos-runner) continue ;; esac
  [ "$(awk -F'\t' -v k="$key" '$1 == k { print $2 }' "$SHIPYARD_CHECK_REGISTRY")" = checkout ] || continue
  while IFS= read -r glob; do
    [ -n "$glob" ] && [ "$glob" != '*' ] || continue
    hit=0
    while IFS= read -r f; do
      case "$f" in $glob) hit=1; break ;; esac
    done < "$w/tracked"
    [ "$hit" -eq 1 ] || chk_fail deviation-scope-matches "the \"$key\" deviation scopes itself to \"$glob\", which matches no tracked file" \
      "an exception that covers nothing is stale or mistyped" \
      "correct the scope to match a tracked path, or delete the deviation's directory"
  done <<EOF
$(shipyard_deviation_scopes "$key")
EOF
done <<EOF
$(mg_list deviations)
EOF

exit "$chk_status"
