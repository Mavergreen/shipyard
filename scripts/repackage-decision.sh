#!/bin/sh
#   usage: repackage-decision.sh
#          env in:  CHANGED (newline-separated paths changed this push)
#                   OWN_UPSTREAM_PATHS (newline/space-separated paths or path:KEY entries, may be
#                   empty)
#                   BEFORE (pre-push git rev) -- required only when a path:KEY entry's file changed
#          stdout:  DISPATCH  or  SKIP=<reason>
#          Decides whether a build-ingredient bump should DISPATCH a repackage: did the repo's OWN
#          upstream ALSO change? If so it's a new-upstream (N=1), owned by the repo's own
#          new-upstream path -> SKIP. Otherwise -> DISPATCH (workflow_dispatch computes N+1 and
#          publishes inline). An entry may be a PATH ("components/tailscale/version") or a KEY INSIDE
#          A PATH ("pins.env:SWIFT_VERSION").
# spec: claude-plugins/modernmavericks/skills/modernmavericks-conventions/SKILL.md "Release notes" --
#       the path:KEY form exists because the swift repos keep every pin in one shared file
#       (pins.env), where path-level ownership cannot tell the upstream pin from an ingredient pin;
#       declaring the whole file own-upstream would skip every repackage, and declaring it not-own
#       would double-publish a Swift bump.
# spec: tests/repackage-decision-test.sh
set -eu

pin_value() {  # $1 = file contents on stdin is not used; $1 = file, $2 = key
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1 | sed 's/^"//; s/"$//'
}

if [ -n "${OWN_UPSTREAM_PATHS:-}" ]; then
  for p in $OWN_UPSTREAM_PATHS; do
    case "$p" in
      *:*)
        file="${p%%:*}"; key="${p##*:}"
        printf '%s\n' "${CHANGED:-}" | grep -Fxq "$file" || continue   # file untouched: not our case
        [ -n "${BEFORE:-}" ] || {
          echo "repackage-decision: $p names a key, so BEFORE (the pre-push rev) is required" >&2
          echo "  without it, 'did the upstream key change?' is unanswerable -- and guessing either way" >&2
          echo "  publishes twice or stops repackaging entirely." >&2
          exit 1
        }
        new="$(pin_value "$file" "$key")"
        old="$(git show "$BEFORE:$file" 2>/dev/null | sed -n "s/^$key=//p" | head -1 | sed 's/^"//; s/"$//')"
        if [ "$old" != "$new" ]; then
          echo "SKIP=own-upstream-changed"; exit 0
        fi
        ;;
      *)
        if printf '%s\n' "${CHANGED:-}" | grep -Fxq "$p"; then
          echo "SKIP=own-upstream-changed"; exit 0
        fi
        ;;
    esac
  done
fi
echo "DISPATCH"
