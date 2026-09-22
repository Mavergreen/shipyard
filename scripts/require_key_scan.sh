#!/bin/sh
#   usage: require_key_scan.sh DIST RECORD_DIR   (RECORD_DIR: where the sparkle-key-scan artifact
#                                                 landed). CI-only.
#          publish-release.yml's gate: a SIGNED release -- some file in it carries a
#          sparkle:edSignature -- must come with scan-for-key.yml's record that this run's logs and
#          release files were scanned for the signing key. An unsigned release needs no scan. A
#          missing record is an ERROR: every signing product calls scan-for-key.yml, and
#          check-family-conventions.sh check 12 fails a repo that signs without it, so this should
#          only ever fire on a scan that did not run or did not pass.
# platform: reading job logs needs `actions: read`, and a called GitHub Actions workflow may not ask
#           for more than its caller grants -- every product calls this one with `contents: write`
#           alone.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Sparkle updater"
#       -- scan-for-key.yml is the separate workflow this constraint forces, since the scan cannot
#       live in publish-release.yml itself without breaking every publish in the family at once;
#       this script is where its absence becomes visible on publish.
set -eu
[ "$#" -eq 2 ] || { echo "usage: require_key_scan.sh DIST RECORD_DIR" >&2; exit 2; }
DIST="$1"; RECORD="$2/sparkle-key-scan.txt"

grep -rlq 'sparkle:edSignature' "$DIST" 2>/dev/null || exit 0
if [ -s "$RECORD" ]; then
  echo "signing-key scan: $(cat "$RECORD")"
  exit 0
fi
echo "::error::this release is signed (it carries a sparkle:edSignature), but no scan-for-key.yml job scanned this run's logs and release files for the signing key -- refusing to publish. Add one between the job that signs and publish, under always() (see scan-for-key.yml), or find out why it did not run."
exit 1
