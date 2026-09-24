#!/bin/sh
# platform: host-agnostic
#   usage: release-needed.sh --digest v1:sha256:<hex> --version <full> [--repo OWNER/NAME]
#          Has this declared state already been released? One line out; decides nothing about HOW to
#          publish.
#            PUBLISH                        no published release carries this digest
#            SKIP=already-released/<tag>    a published release carries this digest
#            SKIP=unreadable-marker/<tag>   no match, and <tag> records a marker this shipyard cannot
#                                            read -- NOT "no marker"
# spec: SKILL.md "A release is a declared state, not an event" (ruling 16) -- the answer depends
#       only on the digest, never the version. A pre-migration release's state is computed from its
#       own tree (release-state.sh --ref) and recorded once, rather than inferred backward from
#       version equality, which silently lost a release.
# spec: tests/release-needed-test.sh -- the four version/digest quadrants, the fetch/parse split at
#       $MAVERICKS_RELEASES_RAW, and the draft/tab/shape-change edge cases the API boundary must
#       survive.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"                    # state_marker(): the family's ONE reader of a recorded marker

DIGEST=""; VERSION=""; REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --digest) DIGEST="$2"; shift 2;;
    --version) VERSION="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    *) echo "release-needed: unknown option $1" >&2; exit 2;;
  esac
done
[ -n "$DIGEST" ] || { echo "release-needed: --digest required" >&2; exit 2; }
[ -n "$VERSION" ] || { echo "release-needed: --version required" >&2; exit 2; }
case "$DIGEST" in
  v1:sha256:*) state_digest_readable "$DIGEST" \
    || { echo "release-needed: --digest is not v1:sha256:<lowercase hex>: $DIGEST" >&2; exit 2; } ;;
  *) echo "release-needed: --digest must start with v1:sha256: (got '$DIGEST')" >&2; exit 2;;
esac

TAB="$(printf '\t')"
_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/release-needed.XXXXXX")"; trap 'rm -rf "$work"' EXIT

fetch_raw() {
  if [ -n "${MAVERICKS_RELEASES_RAW+x}" ]; then printf '%s\n' "$MAVERICKS_RELEASES_RAW"; return 0; fi
  if [ -n "$REPO" ]; then p="repos/$REPO/releases"; else p="repos/{owner}/{repo}/releases"; fi
  "${MAVERICKS_GH:-gh}" api "$p?per_page=100" --paginate \
      --jq '.[] | [.tag_name, (.draft|tostring), (.body // "")] | @tsv' 2>"$work/gh-err" || {
    echo "release-needed: gh could not read $p -- refusing to decide" >&2
    [ ! -s "$work/gh-err" ] || sed 's/^/    /' "$work/gh-err" >&2
    echo "    an unreadable set of releases is not an EMPTY one: treating it as empty says PUBLISH," >&2
    echo "    which is how an expired token or a rate limit publishes a duplicate unattended" >&2
    return 1
  }
}

unescape_tsv() {
  awk '{
    out = ""; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (c == "\\" && i < n) {
        d = substr($0, i + 1, 1); i++
        if (d == "n") out = out "\n"
        else if (d == "t") out = out "\t"
        else if (d == "r") out = out "\r"
        else if (d == "\\") out = out "\\"
        else out = out c d
      } else out = out c
    }
    print out
  }'
}

transform_records() {
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    tag="${line%%$TAB*}"
    rest="${line#*$TAB}"
    [ "$rest" != "$line" ] || continue          # no TAB at all: not a record
    [ -n "$tag" ] || {
      echo "release-needed: a release record has no tag: the raw API shape changed under us" >&2
      echo "    (@tsv renders a null or renamed field as empty, and dropping such records answers" >&2
      echo "    PUBLISH). Refusing to decide." >&2
      return 1
    }
    draft="${rest%%$TAB*}"
    body="${rest#*$TAB}"
    [ "$body" != "$rest" ] || body=""
    case "$draft" in
      true) continue ;;
      false) : ;;
      *) echo "release-needed: malformed release record for '$tag': draft flag is '$draft', not" >&2
         echo "    true/false. The raw API shape changed under us; refusing to decide." >&2
         return 1 ;;
    esac
    printf '%s\t%s\n' "$tag" "$(printf '%s\n' "$body" | unescape_tsv | state_marker)"
  done
}

if [ -n "${MAVERICKS_RELEASES+x}" ]; then
  printf '%s\n' "$MAVERICKS_RELEASES" > "$work/records"
else
  if ! fetch_raw > "$work/raw"; then exit 1; fi
  transform_records < "$work/raw" > "$work/records"
fi

match_tag=""; alien_tag=""; alien_value=""
while IFS= read -r rec || [ -n "$rec" ]; do
  [ -n "$rec" ] || continue
  tag="${rec%%$TAB*}"
  dg="${rec#*$TAB}"
  [ "$dg" != "$rec" ] || dg=""            # no TAB in the record at all
  [ -n "$tag" ] || continue
  [ -n "$dg" ] || continue                # no marker: this release says nothing about any state
  if [ "$dg" = "$DIGEST" ] && [ -z "$match_tag" ]; then match_tag="$tag"; fi
  if [ -z "$alien_tag" ] && ! state_digest_readable "$dg"; then alien_tag="$tag"; alien_value="$dg"; fi
done < "$work/records"

if [ -n "$match_tag" ]; then
  echo "release-needed: $match_tag already realises $DIGEST; $VERSION will not be published" >&2
  printf 'SKIP=already-released/%s\n' "$match_tag"
elif [ -n "$alien_tag" ]; then
  echo "release-needed: $alien_tag records a state marker this shipyard cannot read:" >&2
  echo "    $alien_value" >&2
  echo "    Nothing will publish until that is recomputed, because treating it as 'no marker' is how" >&2
  echo "    a digest format bump republishes every product. Recompute it from the tag's own tree:" >&2
  echo "        d=\"\$(release-state.sh --ref $alien_tag)\"" >&2
  echo "        release-state-record.sh --tag $alien_tag --digest \"\$d\" --replace-unreadable" >&2
  echo "    (--replace-unreadable is required and replaces ONLY an unreadable marker: without it the" >&2
  echo "    re-record exits 3, because a marker being present is what blocked publishing.)" >&2
  printf 'SKIP=unreadable-marker/%s\n' "$alien_tag"
else
  echo "release-needed: no published release realises $DIGEST; $VERSION would be published" >&2
  printf 'PUBLISH\n'
fi
