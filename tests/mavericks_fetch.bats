#!/usr/bin/env bats
# platform: host-agnostic
# platform: tests for scripts/mavericks_fetch.sh run with no network -- a local fixture tarball is served via a file:// URL.

setup() {
  . "$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/mav_fetch_test.XXXXXX")"
  mkdir -p "$WORK/stage/payload"
  echo hello > "$WORK/stage/payload/file.txt"
  ( cd "$WORK/stage" && tar cf "$WORK/fixture.tar" payload )
  SHA="$(shasum -a 256 "$WORK/fixture.tar" | awk '{print $1}')"
  URL="file://$WORK/fixture.tar"
  CACHE="$WORK/cache"
}

teardown() { rm -rf "$WORK"; }

@test "happy path: verifies and extracts the member" {
  run mav_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -eq 0 ]
  [ -f "$CACHE/payload/file.txt" ]
}

@test "checksum mismatch: aborts non-zero and does not extract" {
  BAD=0000000000000000000000000000000000000000000000000000000000000000
  run mav_fetch_pinned "$URL" "$BAD" "$CACHE" fixture.tar payload
  [ "$status" -ne 0 ]
  [ ! -e "$CACHE/payload/file.txt" ]
}

@test "cache-hit: second call does not re-download (bogus URL still succeeds)" {
  run mav_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -eq 0 ]
  run mav_fetch_pinned "file:///no/such/file.tar" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -eq 0 ]
  [ -f "$CACHE/payload/file.txt" ]
}

@test "failed download leaves no poisoned cache (retry after a bad URL succeeds)" {
  run mav_fetch_pinned "file:///no/such/file.tar" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -ne 0 ]
  [ ! -f "$CACHE/fixture.tar" ]
  run mav_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -eq 0 ]
  [ -f "$CACHE/payload/file.txt" ]
}

@test "checksum mismatch: the bad tarball is not kept, so the next run can succeed" {
  # platform: a download that went bad (truncated, a captive portal's HTML) sits in the cache
  #           under the tarball's name; kept, it would fail every later run without re-downloading.
  mkdir -p "$CACHE"
  echo "not the tarball" > "$CACHE/fixture.tar"
  run mav_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -ne 0 ]
  [ ! -e "$CACHE/fixture.tar" ]
  run mav_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -eq 0 ]
  [ -f "$CACHE/payload/file.txt" ]
}

@test "an extract that fails part-way leaves no partial tree to be trusted later" {
  # platform: a verified tarball cut off inside its second member: tar extracts the first member,
  #           then fails -- the shape of an extract interrupted mid-way.
  mkdir -p "$WORK/stage2/payload"
  echo first > "$WORK/stage2/payload/a.txt"
  head -c 65536 /dev/zero > "$WORK/stage2/payload/b.bin"
  ( cd "$WORK/stage2" && tar cf "$WORK/whole.tar" payload/a.txt payload/b.bin )
  head -c 10240 "$WORK/whole.tar" > "$WORK/cut.tar"
  CUTSHA="$(shasum -a 256 "$WORK/cut.tar" | awk '{print $1}')"
  run mav_fetch_pinned "file://$WORK/cut.tar" "$CUTSHA" "$CACHE" cut.tar
  [ "$status" -ne 0 ]
  [ ! -e "$CACHE/payload" ]
  [ -z "$(find "$CACHE" -mindepth 1 ! -name cut.tar)" ]
}

@test "mav_fetch_verified verifies without extracting, and a mismatch says what it got" {
  run mav_fetch_verified "$URL" "$SHA" "$CACHE" fixture.tar
  [ "$status" -eq 0 ]
  [ -f "$CACHE/fixture.tar" ]
  [ ! -e "$CACHE/payload" ]
  BAD=0000000000000000000000000000000000000000000000000000000000000000
  run mav_fetch_verified "$URL" "$BAD" "$CACHE" fixture.tar
  [ "$status" -ne 0 ]
  [[ "$output" == *"is sha256 $SHA, not the pinned $BAD"* ]] || false
  [ ! -e "$CACHE/fixture.tar" ]
}

dir_fixture() {
  mkdir -p "$WORK/dstage/d"
  echo hello > "$WORK/dstage/d/f"
  ( cd "$WORK/dstage" && tar cf "$WORK/fixture.tar" d )
  SHA="$(shasum -a 256 "$WORK/fixture.tar" | awk '{print $1}')"
}

@test "publish keeps an entry that appeared first" {
  dir_fixture
  mkdir -p "$CACHE/d"
  : > "$CACHE/d/marker"
  x="$(mav_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar d)"
  [ -d "$x" ]
  mav_fetch_publish "$CACHE" "$x"
  [ -f "$CACHE/d/marker" ]
  [ ! -e "$CACHE/d/d" ]
  [ ! -e "$x" ]
  [ -z "$(find "$CACHE" -name '.mav-extract.*')" ]
}

@test "publish with an empty extract dir returns non-zero and moves nothing" {
  mkdir -p "$CACHE"
  : > "$CACHE/keep"
  run mav_fetch_publish "$CACHE" ""
  [ "$status" -ne 0 ]
  [ "$(ls -A "$CACHE")" = "keep" ]
}

@test "two concurrent mav_fetch_pinned calls into an empty cache" {
  dir_fixture
  ( mav_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar d ) & p1=$!
  ( mav_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar d ) & p2=$!
  s1=0; s2=0
  wait "$p1" || s1=$?
  wait "$p2" || s2=$?
  [ "$s1" -eq 0 ]
  [ "$s2" -eq 0 ]
  [ -f "$CACHE/d/f" ]
  [ ! -e "$CACHE/d/d" ]
  [ -z "$(find "$CACHE" -mindepth 1 -name '.*')" ]
}

@test "a held lock times out naming the lock" {
  dir_fixture
  x="$(mav_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar d)"
  mkdir "$CACHE/.mav-publish.lock"
  MAV_FETCH_LOCK_TRIES=2 run mav_fetch_publish "$CACHE" "$x"
  [ "$status" -eq 1 ]
  [[ "$output" == *".mav-publish.lock held"* ]] || false
}

@test "a failing mv under set -e still releases the publish lock" {
  # platform: callers run under `set -e`; a bare failing mv would kill them while they hold the lock,
  #           and every later fetch into that cache would wait out the lock and fail.
  dir_fixture
  x="$(mav_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar d)"
  run sh -ec '. "$1/scripts/mavericks_fetch.sh"; mv() { return 1; }; mav_fetch_publish "$2" "$3"' \
    sh "$BATS_TEST_DIRNAME/.." "$CACHE" "$x"
  [ "$status" -ne 0 ]
  [ ! -e "$CACHE/.mav-publish.lock" ]
}

# platform: MAVERGREEN_PROGRESS=1 adds stderr progress; bats has no terminal, so these cover the
#           non-terminal path (whole lines, no \r) and the unset default.
@test "default output is byte-identical" {
  unset MAVERGREEN_PROGRESS
  x="$(mav_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload 2>"$WORK/err")"
  [ "$x" = "$(printf '%s' "$x" | head -n 1)" ]
  [[ "$x" == "$CACHE"/.mav-extract.* ]] || false
  [[ "$(cat "$WORK/err")" == "$CACHE/.fixture.tar."??????": OK" ]] || false
  [ "$(wc -l < "$WORK/err" | tr -d ' ')" -eq 1 ]
  x="$(mav_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload 2>"$WORK/err")"
  [ "$(cat "$WORK/err")" = "$CACHE/fixture.tar: OK" ]
}

@test "progress, not a terminal: one line per stage" {
  MAVERGREEN_PROGRESS=1 mav_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload 2>"$WORK/err" >/dev/null
  printf 'mav_fetch: downloading fixture.tar\nmav_fetch: downloaded fixture.tar\nmav_fetch: verified fixture.tar\nmav_fetch: unpacking fixture.tar\n' > "$WORK/want"
  cmp "$WORK/want" "$WORK/err"
}

@test "progress, cached tarball: no download lines" {
  mav_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload >/dev/null 2>&1
  MAVERGREEN_PROGRESS=1 mav_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload 2>"$WORK/err" >/dev/null
  printf 'mav_fetch: verified fixture.tar\nmav_fetch: unpacking fixture.tar\n' > "$WORK/want"
  cmp "$WORK/want" "$WORK/err"
}

@test "progress does not change stdout" {
  x="$(MAVERGREEN_PROGRESS=1 mav_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload 2>/dev/null)"
  [[ "$x" == "$CACHE"/.mav-extract.?????? ]] || false
  [ -f "$x/payload/file.txt" ]
}

@test "progress: a mismatch message is unchanged" {
  BAD=0000000000000000000000000000000000000000000000000000000000000000
  MAVERGREEN_PROGRESS=1 mav_fetch_verified "$URL" "$BAD" "$CACHE" fixture.tar 2>"$WORK/err" || true
  grep -q "is sha256 $SHA, not the pinned $BAD" "$WORK/err"
  run grep -q verified "$WORK/err"
  [ "$status" -eq 1 ]
}
