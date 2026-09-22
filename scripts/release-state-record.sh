#!/bin/sh
#   usage: release-state-record.sh --notes-file F --digest v1:sha256:<hex>
#          release-state-record.sh --tag T --digest v1:sha256:<hex> [--repo OWNER/NAME]
#          release-state-record.sh --tag T --digest D [--replace-unreadable]
#          release-state-record.sh --tag T --digest D --body-file F --out F   (offline; tests)
#          Records a state digest onto a release body. --notes-file marks a notes file in place
#          BEFORE packaging (the normal path, no --tag: the notes are not a release yet). --tag marks
#          an ALREADY PUBLISHED release once, at migration -- paired with `release-state.sh --ref T`,
#          which renders what that tag's tree actually contained.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "A release is a
#       declared state, not an event" -- the only writer of a release body outside the publish path:
#       appends one line and preserves every other byte, is idempotent, and a conflicting digest
#       stops it with exit 3 rather than overwriting.
# spec: SKILL.md "A release is a declared state, not an event" (ruling 16) -- marking each
#       existing release once, with the digest computed from what it actually contains, is exact
#       where inferring backward from a version match was a guess that lost a release.
# spec: tests/release-state-record-test.sh -- append/idempotent/conflict, both targets, the
#       marker-as-its-own-paragraph rendering rule, and --replace-unreadable's narrow escape.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"                    # state_marker(): the family's ONE reader of a recorded marker

TAG=""; DIGEST=""; REPO=""; BODY_FILE=""; OUT=""; NOTES_FILE=""; REPLACE_UNREADABLE=no
REPLACED=no
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2;;
    --digest) DIGEST="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --notes-file) NOTES_FILE="$2"; shift 2;;
    --body-file) BODY_FILE="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --replace-unreadable) REPLACE_UNREADABLE=yes; shift;;
    *) echo "release-state-record: unknown option $1" >&2; exit 2;;
  esac
done
if [ -n "$NOTES_FILE" ] && [ -n "$TAG" ]; then
  echo "release-state-record: --notes-file and --tag are different targets; pass one" >&2
  exit 2
fi
[ -n "$NOTES_FILE" ] || [ -n "$TAG" ] || {
  echo "release-state-record: name a target -- --notes-file F (before packaging) or --tag T (an" >&2
  echo "    already-published release)" >&2
  exit 2
}
[ -n "$DIGEST" ] || { echo "release-state-record: --digest required" >&2; exit 2; }
case "$DIGEST" in
  v1:sha256:*) rest="${DIGEST#v1:sha256:}"
    case "$rest" in
      ''|*[!0-9a-f]*) echo "release-state-record: --digest is not v1:sha256:<lowercase hex>" >&2; exit 2;;
    esac ;;
  *) echo "release-state-record: --digest must start with v1:sha256:" >&2; exit 2;;
esac
if [ -n "$BODY_FILE" ] && [ -z "$OUT" ]; then
  echo "release-state-record: --body-file needs --out (offline mode writes a file, never a release)" >&2
  exit 2
fi

_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/state-record.XXXXXX")"; trap 'rm -rf "$work"' EXIT
body="$work/body"

if [ -n "$NOTES_FILE" ]; then
  [ -f "$NOTES_FILE" ] || {
    echo "release-state-record: no such notes file: $NOTES_FILE" >&2
    echo "    the notes are a build product; a missing one means this ran before they were" >&2
    echo "    generated. This script never creates them." >&2
    exit 2
  }
  cp "$NOTES_FILE" "$body"
  what="$NOTES_FILE"
elif [ -n "$BODY_FILE" ]; then
  cp "$BODY_FILE" "$body"
  what="$TAG"
else
  set -- release view "$TAG" --json body --jq .body
  [ -z "$REPO" ] || set -- "$@" --repo "$REPO"
  gh "$@" > "$body" 2>"$work/err" || {
    echo "release-state-record: cannot read release $TAG: $(cat "$work/err")" >&2
    exit 1
  }
  what="$TAG"
fi

existing="$(state_marker < "$body")"
if [ -n "$existing" ]; then
  if [ "$existing" = "$DIGEST" ]; then
    [ -z "$OUT" ] || cp "$body" "$OUT"
    printf 'UNCHANGED=%s\n' "$what"
    exit 0
  fi
  if [ "$REPLACE_UNREADABLE" = yes ] && ! state_digest_readable "$existing"; then
    awk -v new="Mavergreen-State: $DIGEST" '
      /^Mavergreen-State:/ { if (!seen) { print new; seen = 1 } ; next }
      { print }
    ' "$body" > "$work/replaced"
    mv "$work/replaced" "$body"
    REPLACED=yes
  else
    echo "release-state-record: $what already records a DIFFERENT state" >&2
    echo "    recorded: $existing" >&2
    echo "    offered:  $DIGEST" >&2
    echo "    two declared states cannot claim one release; nothing was written" >&2
    if state_digest_readable "$existing"; then
      echo "    (both are readable digests, so this is a real disagreement -- not something" >&2
      echo "    --replace-unreadable will resolve for you)" >&2
    else
      echo "    the recorded marker is not a digest this shipyard can read; to replace exactly that," >&2
      echo "    pass --replace-unreadable" >&2
    fi
    exit 3
  fi
fi

# platform: Markdown joins consecutive lines, so a marker appended directly after the footer's last
#           line renders -- in the Sparkle update dialog a 10.9 user actually reads -- as one run-on
#           paragraph ending in a raw 64-character hash. `gh release view --json body --jq .body`
#           does not promise a trailing newline, and neither does a hand-edited notes file.
if [ "$REPLACED" = no ]; then
  if [ -s "$body" ]; then
    [ -z "$(tail -c 1 "$body")" ] || printf '\n' >> "$body"
    printf '\n' >> "$body"
  fi
  printf 'Mavergreen-State: %s\n' "$DIGEST" >> "$body"
fi

if [ -n "$NOTES_FILE" ]; then
  cat "$body" > "$NOTES_FILE"
  if [ "$REPLACED" = yes ]; then printf 'REPLACED=%s\n' "$NOTES_FILE"
  else printf 'RECORDED=%s\n' "$NOTES_FILE"; fi
  exit 0
fi

if [ -n "$OUT" ]; then
  cp "$body" "$OUT"
else
  set -- release edit "$TAG" --notes-file "$body"
  [ -z "$REPO" ] || set -- "$@" --repo "$REPO"
  gh "$@" >/dev/null
fi
if [ "$REPLACED" = yes ]; then printf 'REPLACED=%s\n' "$TAG"
else printf 'BACKFILLED=%s\n' "$TAG"; fi
