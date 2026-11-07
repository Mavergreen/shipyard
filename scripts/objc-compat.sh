#!/bin/sh
# platform: macOS-only -- builds the host-native analyzer against the pinned host SDK, then reads the artifact as data
#   usage: objc-compat.sh --artifact FILE --root SHIPPED_ROOT --references REF_DIR --report NEW_FILE
#                         [--build-evidence FILE] [--provider-prefix DIR [--source-receipt FILE]] [--mode inventory|strict] [--exceptions FILE]
#          Classifies every Objective-C message send in FILE's x86_64 slice against the versioned
#          reference set REF_DIR (reference/objc) and writes the schema-1 report to NEW_FILE, which
#          must not exist in any form. FILE must lie inside SHIPPED_ROOT; the report names it
#          relative to that root. --build-evidence supplies reviewed, artifact-bound binding,
#          R2 type and guard evidence (tools/objc-compat/source-evidence.c header); without it only
#          binary-measured receivers close. --provider-prefix names an Objective-C provider's prefix
#          (DIR/share/recaulk/objc-providers.json and its archive); a send it backfills is `provided`
#          only when the build evidence's mapping (scripts/objc-build-evidence.sh) checks out against
#          the artifact's bytes (tools/objc-compat/provider.c header). --source-receipt, with both, is the
#          provider body's source receipt (scripts/objc-source-inventory.sh); it closes sends in verified
#          provider code only (tools/objc-compat/source-evidence.c header). inventory (the default)
#          reports what was measured; strict additionally fails on any unsupported or unresolved
#          finding, but for one a reviewed objc-api deviation record listed in --exceptions names
#          exactly (tools/objc-compat/main.m "objc-api scoped deviations"; scripts/assert_binary_compatible.sh
#          writes the list). Nothing is executed: the artifact is read, never run or loaded.
#          Exit 0 measured (strict: and no blocking finding), 1 strict with a blocking finding,
#          2 usage, 4 cannot measure (including a failure to build the analyzer). The analyzer's
#          source identity -- every source byte and the Drydock pin, not the compiler, SDK or arch
#          that differ between hosts (scripts/objc-compat-build.sh) -- goes into the report's inputs.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

usage() { echo "usage: objc-compat.sh --artifact FILE --root SHIPPED_ROOT --references REF_DIR --report NEW_FILE [--build-evidence FILE] [--provider-prefix DIR [--source-receipt FILE]] [--mode inventory|strict] [--exceptions FILE]" >&2; exit 2; }
n=$#
[ "$n" -ge 8 ] || usage
i=0
for a in "$@"; do
  i=$((i + 1))
  # platform: odd positions are option names; the analyzer validates values and repeats.
  if [ $((i % 2)) = 1 ]; then
    case "$a" in --artifact|--root|--references|--report|--build-evidence|--mode|--provider-prefix|--source-receipt|--exceptions) ;; *) usage ;; esac
  fi
done
[ $((n % 2)) = 0 ] || usage

T=$(mktemp -d "${TMPDIR:-/tmp}/objc-compat.XXXXXX")
trap 'rm -rf "$T"' EXIT
sh "$HERE/objc-compat-build.sh" --analyzer "$T/objc-compat" 2>"$T/build.log" || {
  cat "$T/build.log" >&2; echo "objc-compat: the analyzer did not build" >&2; exit 4; }
id=$(sed -n 's/^objc-compat: analyzer [0-9a-f]* source \([0-9a-f]*\) .*/\1/p' "$T/build.log")
[ -n "$id" ] || { cat "$T/build.log" >&2; echo "objc-compat: the analyzer build reported no identity" >&2; exit 4; }
rc=0
"$T/objc-compat" "$@" --analyzer-id "objc-compat-src-$id" || rc=$?
exit "$rc"
