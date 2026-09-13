#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/delete-draft-release.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/delete-draft.XXXXXX")"; trap 'rm -rf "$work"' EXIT  # template: 10.9 BSD mktemp requires one

# spec: real `gh api ... --paginate` prints one JSON array per page, concatenated -- the stub
#       mimics that by catting $GH_PAGES, which holds two page arrays.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'SH'
#!/bin/sh
[ "${GH_FAIL:-}" = 1 ] && { echo "gh: HTTP 502" >&2; exit 1; }
case "$*" in
  "api -X DELETE "*) echo "$4" >> "$GH_LOG" ;;
  "api repos/"*"/releases?per_page=100 --paginate") cat "$GH_PAGES" ;;
  *) echo "stub gh: unexpected: $*" >&2; exit 3 ;;
esac
SH
chmod +x "$work/bin/gh"
cat > "$work/pages" <<'JSON'
[{"id": 11, "tag_name": "1.26.8-mavericks.3", "draft": true},
 {"id": 12, "tag_name": "1.26.8-mavericks.2", "draft": false}]
[{"id": 13, "tag_name": "1.26.8-mavericks.2", "draft": true},
 {"id": 14, "tag_name": "1.26.8-mavericks.3", "draft": true},
 {"id": 15, "tag_name": "1.26.8-mavericks.30", "draft": true}]
JSON
export GH_PAGES="$work/pages" GH_LOG="$work/log"
PATH="$work/bin:$PATH"; export PATH

: > "$GH_LOG"
sh "$S" o/r 1.26.8-mavericks.3 >/dev/null
got="$(tr '\n' ' ' < "$GH_LOG")"
[ "$got" = "repos/o/r/releases/11 repos/o/r/releases/14 " ] \
  || { echo "FAIL: must delete both drafts of the tag across pages, and nothing else (not the published .2, its draft, or .30's) -- expected drafts 11 and 14 of .3 deleted, got: $got"; exit 1; }

: > "$GH_LOG"
out="$(sh "$S" o/r 1.26.8-mavericks.9)"
[ ! -s "$GH_LOG" ] || { echo "FAIL: a tag whose only release is published must delete nothing: $(cat "$GH_LOG")"; exit 1; }
printf '%s\n' "$out" | grep -q 'no draft release' || { echo "FAIL should say there was no draft: $out"; exit 1; }
: > "$GH_LOG"
sh "$S" o/r 1.26.8-mavericks.2 >/dev/null
[ "$(cat "$GH_LOG")" = "repos/o/r/releases/13" ] \
  || { echo "FAIL only .2's draft (13), never its published release (12): $(cat "$GH_LOG")"; exit 1; }

: > "$GH_LOG"
if GH_FAIL=1 sh "$S" o/r 1.26.8-mavericks.3 >/dev/null 2>&1; then
  echo "FAIL a failed listing should fail, not pass as nothing-to-clean"; exit 1
fi

echo "PASS: delete-draft-release"
