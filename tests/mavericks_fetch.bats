#!/usr/bin/env bats
# platform: host-agnostic
# Tests for mav_fetch_pinned (scripts/mavericks_fetch.sh). No network: a local
# fixture tarball is served via a file:// URL.

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
