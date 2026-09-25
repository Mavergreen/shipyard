# platform: host-agnostic
#   usage: . stand-in-marker.sh     (sourced; defines the two variables below)
#          The exact strings stand-in-feeds.sh writes into an unsigned feed's edSignature and its
#          stand-in RELEASE_NOTES.md heading -- defined once here so release-assets.sh can refuse
#          both by the same strings stand-in-feeds.sh writes, and cannot drift out of agreement
#          with it.
# spec: tests/release-assets-test.sh -- stand-in-feeds.sh's output must never reach a published dist

STAND_IN_SIGNATURE='unsigned-stand-in'
STAND_IN_NOTES_HEADING='## A build that is not a release'
