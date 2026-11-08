#!/bin/sh
# platform: host-agnostic
#   usage: objc-reference-dir.sh
#          Prints the Objective-C reference set the strict analyzer measures against. An installed shipyard
#          stages the pinned Drydock's set beside its scripts, as reference/objc (CMakeLists.txt), and that is
#          the answer when it exists. A checkout stages none, so the answer is then the pinned Drydock's own
#          share/drydock/objc/reference, from scripts/fetch_drydock.sh and .mavergreen/ingredients/drydock (which
#          MAVERGREEN_DRYDOCK_PREFIX replaces). Exit 1 when neither is there.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$SELF/../reference/objc" ]; then
  (cd "$SELF/../reference/objc" && pwd -P); exit 0
fi
d="$(sh "$SELF/fetch_drydock.sh" "$SELF/..")" || {
  echo "objc-reference-dir: no reference/objc beside $SELF, and the pinned Drydock could not be had" >&2; exit 1; }
[ -d "$d/share/drydock/objc/reference" ] || {
  echo "objc-reference-dir: the pinned Drydock at $d holds no share/drydock/objc/reference" >&2; exit 1; }
printf '%s\n' "$d/share/drydock/objc/reference"
