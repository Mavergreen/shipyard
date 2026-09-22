#!/bin/sh
#   usage: upstream-notes.sh [--url-only] <version>          (<upstream>-mavericks.N)
#          Links upstream's own release notes, as a markdown section for the release notes (Sparkle
#          appcast <description> + GitHub Release body), when this release ships an upstream version
#          that no earlier release shipped. WHERE upstream publishes notes is per-repo, so the repo
#          answers it: build/upstream-release-notes-url.sh (or scripts/…) <upstream-version> prints
#          ONE URL.
#          Default mode prints NOTHING for a repackage, for a repo without the hook, or when the hook
#          fails -- so callers append unconditionally; it never fails a release. --url-only instead
#          reports which case it was on exit: 3 = no link is due (a repackage), 4 = this repo has no
#          hook, 5 = the hook is broken (or tags are unknowable), so a caller that cares can tell a
#          missing link from a broken one.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "A new upstream
#       links upstream's own notes" -- decides whether a link is due (from the tags, never the
#       previous release, since parallel lines make the previous release's upstream not comparable)
#       BEFORE it even looks for the hook, so a repackage never needs one to exist; signal-desktop
#       shipped a new upstream with no link and nothing red because that ordering was reversed.
# spec: tests/upstream-notes-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"          # sets MAVERICKS_ROOT if unset

url_only=no
if [ "${1:-}" = "--url-only" ]; then url_only=yes; shift; fi
ver="${1:?upstream-notes: version required}"
up="${ver%%-mavericks.*}"

bail() {  # $1 = --url-only exit code, $2 = message
  [ "$url_only" = yes ] || { echo "upstream-notes: $2" >&2; exit 0; }
  echo "upstream-notes: $2" >&2; exit "$1"
}

# platform: a pre-2.15 (2017) git does not recognize `--is-shallow-repository` and echoes the flag
#           back literally, so the comparison below tests for the literal string "true", never
#           merely a nonempty answer.
if [ "$(cd "$MAVERICKS_ROOT" && git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
  bail 5 "$MAVERICKS_ROOT is a shallow clone, so its release tags are unknown (use fetch-depth: 0)"
fi
if ! tags="$(cd "$MAVERICKS_ROOT" && git tag --list "$up-mavericks.*")"; then
  bail 5 "cannot list release tags in $MAVERICKS_ROOT"
fi
for t in $tags; do
  [ "$t" = "$ver" ] || bail 3 "$ver is a repackage of $up; no upstream link is due"
done

hook=""
for d in build scripts; do
  if [ -f "$MAVERICKS_ROOT/$d/upstream-release-notes-url.sh" ]; then
    hook="$MAVERICKS_ROOT/$d/upstream-release-notes-url.sh"; break
  fi
done
[ -n "$hook" ] || bail 4 "no build/ or scripts/upstream-release-notes-url.sh in $MAVERICKS_ROOT"

if ! url="$(cd "$MAVERICKS_ROOT" && sh "$hook" "$up")"; then
  bail 5 "$hook failed for $up; omitting the upstream section"
fi
case "$url" in
  http://*|https://*) ;;
  *) bail 5 "$hook printed no URL for $up; omitting the upstream section" ;;
esac
case "$url" in
  *[[:space:]]*|*")"*)
    bail 5 "$hook printed more than one URL for $up; omitting the upstream section" ;;
esac

if [ "$url_only" = yes ]; then
  printf '%s\n' "$url"
else
  printf '### Upstream\n\n- [Upstream release notes for %s](%s)\n' "$up" "$url"
fi
