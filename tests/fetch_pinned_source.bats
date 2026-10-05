#!/usr/bin/env bats
# platform: host-agnostic
# Tests for scripts/fetch_pinned_source.sh -- the tarball-source supply-chain boundary. No network: a
# fixture tarball shaped like GitHub's (one top-level NAME-DIGEST directory) is served from a file://
# tree through MAVERICKS_CODELOAD.

setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/fetch_pinned_source.sh"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/fetch_pinned_source_test.XXXXXX")"
  D=0123456789abcdef0123456789abcdef01234567
  REPO=https://github.com/acme/widget.git
  mkdir -p "$WORK/stage/widget-$D/sub"
  echo hello > "$WORK/stage/widget-$D/sub/file.txt"
  printf '#!/bin/sh\necho run\n' > "$WORK/stage/widget-$D/run.sh"; chmod 755 "$WORK/stage/widget-$D/run.sh"
  ln -s sub/file.txt "$WORK/stage/widget-$D/link"
  mkdir -p "$WORK/codeload/acme/widget/tar.gz"
  ( cd "$WORK/stage" && tar czf "$WORK/codeload/acme/widget/tar.gz/$D" "widget-$D" )
  SHA="$(shasum -a 256 < "$WORK/codeload/acme/widget/tar.gz/$D" | cut -c1-64)"
  export MAVERICKS_CODELOAD="file://$WORK/codeload" MAVERICKS_SOURCE_CACHE="$WORK/cache"
  DEST="$WORK/build/widget"
}
teardown() { rm -rf "$WORK"; }

@test "fetches, verifies and extracts the tree as the tarball holds it, with a stamp; stdout stays empty" {
  out="$(sh "$HELPER" "$REPO" "$D" "$SHA" "$DEST" 2>/dev/null)"
  [ -z "$out" ]
  [ "$(cat "$DEST/sub/file.txt")" = hello ]
  [ -x "$DEST/run.sh" ]
  [ "$(readlink "$DEST/link")" = sub/file.txt ]
  [ "$(cat "$DEST/.mavergreen-source")" = "$REPO $D $SHA" ]
  [ -f "$WORK/cache/widget-$D.tar.gz" ]
  [ -z "$(ls -A "$WORK/build" | grep -v '^widget$')" ]
}

@test "a second call extracts afresh from the cached tarball: changes and strays are gone" {
  run sh "$HELPER" "$REPO" "$D" "$SHA" "$DEST"; [ "$status" -eq 0 ]
  echo changed > "$DEST/sub/file.txt"; echo stray > "$DEST/stray.orig"
  run env MAVERICKS_CODELOAD=file:///no/such/codeload sh "$HELPER" "$REPO" "$D" "$SHA" "$DEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/sub/file.txt")" = hello ]
  [ ! -e "$DEST/stray.orig" ]
}

@test "a checksum mismatch fails, names the SHA-256 it got, keeps no tarball, and leaves DEST as it was" {
  mkdir -p "$DEST"; echo old > "$DEST/old.txt"
  BAD=0000000000000000000000000000000000000000000000000000000000000000
  run sh "$HELPER" "$REPO" "$D" "$BAD" "$DEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$SHA"* ]] || false
  [ ! -e "$WORK/cache/widget-$D.tar.gz" ]
  [ "$(cat "$DEST/old.txt")" = old ]
}

@test "a commit GitHub has no tarball for fails, leaving DEST as it was" {
  mkdir -p "$DEST"; echo old > "$DEST/old.txt"
  run sh "$HELPER" "$REPO" 89abcdef0123456789abcdef0123456789abcdef "$SHA" "$DEST"
  [ "$status" -eq 1 ]
  [ "$(cat "$DEST/old.txt")" = old ]
}

@test "a tarball holding anything beside its one NAME-DIGEST directory is refused" {
  mkdir -p "$WORK/stage/other"
  ( cd "$WORK/stage" && tar czf "$WORK/codeload/acme/widget/tar.gz/$D" "widget-$D" other )
  S2="$(shasum -a 256 < "$WORK/codeload/acme/widget/tar.gz/$D" | cut -c1-64)"
  run sh "$HELPER" "$REPO" "$D" "$S2" "$DEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"widget-$D"* ]] || false
  [ ! -e "$DEST" ]
}

@test "--url prints the codeload URL of the commit, with or without .git" {
  run env -u MAVERICKS_CODELOAD sh "$HELPER" --url "$REPO" "$D"
  [ "$status" -eq 0 ]
  [ "$output" = "https://codeload.github.com/acme/widget/tar.gz/$D" ]
  run env -u MAVERICKS_CODELOAD sh "$HELPER" --url https://github.com/acme/widget "$D"
  [ "$output" = "https://codeload.github.com/acme/widget/tar.gz/$D" ]
}

@test "usage errors exit 2: not GitHub, not a commit, not a SHA-256, no DEST" {
  run sh "$HELPER" https://example.com/acme/widget.git "$D" "$SHA" "$DEST"; [ "$status" -eq 2 ]
  run sh "$HELPER" "$REPO" abc123 "$SHA" "$DEST"; [ "$status" -eq 2 ]
  run sh "$HELPER" "$REPO" "$D" abc123 "$DEST"; [ "$status" -eq 2 ]
  run sh "$HELPER" "$REPO" "$D" "$SHA" ""; [ "$status" -eq 2 ]
  run sh "$HELPER" "$REPO" "$D" "$SHA"; [ "$status" -eq 2 ]
}

@test "a rename that fails puts the old DEST back and leaves no temp dirs beside it" {
  mkdir -p "$DEST" "$WORK/bin"; echo old > "$DEST/old.txt"
  printf '#!/bin/sh\ncase "$1" in *.tmp.*) exit 1 ;; esac\nexec /bin/mv "$@"\n' > "$WORK/bin/mv"; chmod +x "$WORK/bin/mv"
  run env PATH="$WORK/bin:$PATH" sh "$HELPER" "$REPO" "$D" "$SHA" "$DEST"
  [ "$status" -eq 1 ]
  [ "$(cat "$DEST/old.txt")" = old ]
  [ "$(ls -A "$WORK/build")" = widget ]
}

@test "a TERM during the extraction exits 143, leaves DEST as it was and no temp dirs beside it" {
  mkdir -p "$DEST" "$WORK/bin"; echo old > "$DEST/old.txt"
  printf '#!/bin/sh\nkill -TERM $PPID\nsleep 1\nexit 1\n' > "$WORK/bin/tar"; chmod +x "$WORK/bin/tar"
  run sh "$HELPER" "$REPO" "$D" "$SHA" "$DEST"; [ "$status" -eq 0 ]
  run env PATH="$WORK/bin:$PATH" sh "$HELPER" "$REPO" "$D" "$SHA" "$DEST"
  [ "$status" -eq 143 ]
  [ "$(cat "$DEST/sub/file.txt")" = hello ]
  [ "$(ls -A "$WORK/build")" = widget ]
}
