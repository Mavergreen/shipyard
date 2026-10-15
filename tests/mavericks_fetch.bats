#!/usr/bin/env bats
# platform: host-agnostic
# platform: tests for scripts/mavericks_fetch.sh run with no network -- a local fixture tarball is served via a file:// URL.

setup() {
  . "$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/shipyard_fetch_test.XXXXXX")"
  mkdir -p "$WORK/stage/payload"
  echo hello > "$WORK/stage/payload/file.txt"
  ( cd "$WORK/stage" && tar cf "$WORK/fixture.tar" payload )
  SHA="$(shasum -a 256 "$WORK/fixture.tar" | awk '{print $1}')"
  URL="file://$WORK/fixture.tar"
  CACHE="$WORK/cache"
}

teardown() { rm -rf "$WORK"; }

@test "happy path: verifies and extracts the member" {
  run shipyard_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -eq 0 ]
  [ -f "$CACHE/payload/file.txt" ]
}

@test "checksum mismatch: aborts non-zero and does not extract" {
  BAD=0000000000000000000000000000000000000000000000000000000000000000
  run shipyard_fetch_pinned "$URL" "$BAD" "$CACHE" fixture.tar payload
  [ "$status" -ne 0 ]
  [ ! -e "$CACHE/payload/file.txt" ]
}

@test "cache-hit: second call does not re-download (bogus URL still succeeds)" {
  run shipyard_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -eq 0 ]
  run shipyard_fetch_pinned "file:///no/such/file.tar" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -eq 0 ]
  [ -f "$CACHE/payload/file.txt" ]
}

@test "failed download leaves no poisoned cache (retry after a bad URL succeeds)" {
  run shipyard_fetch_pinned "file:///no/such/file.tar" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -ne 0 ]
  [ ! -f "$CACHE/fixture.tar" ]
  run shipyard_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -eq 0 ]
  [ -f "$CACHE/payload/file.txt" ]
}

@test "checksum mismatch: the bad tarball is not kept, so the next run can succeed" {
  # platform: a download that went bad (truncated, a captive portal's HTML) sits in the cache
  #           under the tarball's name; kept, it would fail every later run without re-downloading.
  mkdir -p "$CACHE"
  echo "not the tarball" > "$CACHE/fixture.tar"
  run shipyard_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar payload
  [ "$status" -ne 0 ]
  [ ! -e "$CACHE/fixture.tar" ]
  run shipyard_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar payload
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
  run shipyard_fetch_pinned "file://$WORK/cut.tar" "$CUTSHA" "$CACHE" cut.tar
  [ "$status" -ne 0 ]
  [ ! -e "$CACHE/payload" ]
  [ -z "$(find "$CACHE" -mindepth 1 ! -name cut.tar)" ]
}

@test "shipyard_fetch_verified verifies without extracting, and a mismatch says what it got" {
  run shipyard_fetch_verified "$URL" "$SHA" "$CACHE" fixture.tar
  [ "$status" -eq 0 ]
  [ -f "$CACHE/fixture.tar" ]
  [ ! -e "$CACHE/payload" ]
  BAD=0000000000000000000000000000000000000000000000000000000000000000
  run shipyard_fetch_verified "$URL" "$BAD" "$CACHE" fixture.tar
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
  x="$(shipyard_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar d)"
  [ -d "$x" ]
  shipyard_fetch_publish "$CACHE" "$x"
  [ -f "$CACHE/d/marker" ]
  [ ! -e "$CACHE/d/d" ]
  [ ! -e "$x" ]
  [ -z "$(find "$CACHE" -name '.mav-extract.*')" ]
}

@test "publish with an empty extract dir returns non-zero and moves nothing" {
  mkdir -p "$CACHE"
  : > "$CACHE/keep"
  run shipyard_fetch_publish "$CACHE" ""
  [ "$status" -ne 0 ]
  [ "$(ls -A "$CACHE")" = "keep" ]
}

@test "two concurrent shipyard_fetch_pinned calls into an empty cache" {
  dir_fixture
  ( shipyard_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar d ) & p1=$!
  ( shipyard_fetch_pinned "$URL" "$SHA" "$CACHE" fixture.tar d ) & p2=$!
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
  x="$(shipyard_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar d)"
  mkdir "$CACHE/.mav-publish.lock"
  SHIPYARD_FETCH_LOCK_TRIES=2 run shipyard_fetch_publish "$CACHE" "$x"
  [ "$status" -eq 1 ]
  [[ "$output" == *".mav-publish.lock held"* ]] || false
}

@test "a failing mv under set -e still releases the publish lock" {
  # platform: callers run under `set -e`; a bare failing mv would kill them while they hold the lock,
  #           and every later fetch into that cache would wait out the lock and fail.
  dir_fixture
  x="$(shipyard_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar d)"
  run sh -ec '. "$1/scripts/mavericks_fetch.sh"; mv() { return 1; }; shipyard_fetch_publish "$2" "$3"' \
    sh "$BATS_TEST_DIRNAME/.." "$CACHE" "$x"
  [ "$status" -ne 0 ]
  [ ! -e "$CACHE/.mav-publish.lock" ]
}

# platform: MAVERGREEN_PROGRESS=1 adds stderr progress; bats has no terminal, so these cover the
#           non-terminal path (whole lines, no \r) and the unset default.
@test "default output is byte-identical" {
  unset MAVERGREEN_PROGRESS
  x="$(shipyard_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload 2>"$WORK/err")"
  [ "$x" = "$(printf '%s' "$x" | head -n 1)" ]
  [[ "$x" == "$CACHE"/.mav-extract.* ]] || false
  [[ "$(cat "$WORK/err")" == "$CACHE/.fixture.tar."??????": OK" ]] || false
  [ "$(wc -l < "$WORK/err" | tr -d ' ')" -eq 1 ]
  x="$(shipyard_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload 2>"$WORK/err")"
  [ "$(cat "$WORK/err")" = "$CACHE/fixture.tar: OK" ]
}

@test "progress, not a terminal: one line per stage" {
  MAVERGREEN_PROGRESS=1 shipyard_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload 2>"$WORK/err" >/dev/null
  printf 'shipyard_fetch: downloading fixture.tar\nshipyard_fetch: downloaded fixture.tar\nshipyard_fetch: verified fixture.tar\nshipyard_fetch: unpacking fixture.tar\n' > "$WORK/want"
  cmp "$WORK/want" "$WORK/err"
}

@test "progress, cached tarball: no download lines" {
  shipyard_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload >/dev/null 2>&1
  MAVERGREEN_PROGRESS=1 shipyard_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload 2>"$WORK/err" >/dev/null
  printf 'shipyard_fetch: verified fixture.tar\nshipyard_fetch: unpacking fixture.tar\n' > "$WORK/want"
  cmp "$WORK/want" "$WORK/err"
}

@test "progress does not change stdout" {
  x="$(MAVERGREEN_PROGRESS=1 shipyard_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload 2>/dev/null)"
  [[ "$x" == "$CACHE"/.mav-extract.?????? ]] || false
  [ -f "$x/payload/file.txt" ]
}


# platform: runs one fetch under the given script and prints "status", stdout and stderr to files in
#           $WORK/$1, with the cache path and mktemp suffixes normalised so two runs compare byte for byte.
fetch_capture() {   # fetch_capture NAME SCRIPT FUNC SHA [ENV=VAL...]
  _n=$1; _s=$2; _f=$3; _h=$4; shift 4
  mkdir -p "$WORK/$_n"
  _rc=0
  env "$@" sh -c '. "$1"; "$2" "$3" "$4" "$5" fixture.tar payload' x "$_s" "$_f" "$URL" "$_h" "$WORK/$_n/cache" \
    >"$WORK/$_n/out" 2>"$WORK/$_n/err" || _rc=$?
  echo $_rc > "$WORK/$_n/status"
  sed -e "s|$WORK/$_n/cache|CACHE|g" -e 's|\.mav-extract\.[A-Za-z0-9]*|.mav-extract.X|g' \
      -e 's|\(\.fixture\.tar\)\.[A-Za-z0-9]\{6\}|\1.X|g' "$WORK/$_n/out" > "$WORK/$_n/out.n"
  sed -e "s|$WORK/$_n/cache|CACHE|g" -e 's|\.mav-extract\.[A-Za-z0-9]*|.mav-extract.X|g' \
      -e 's|\(\.fixture\.tar\)\.[A-Za-z0-9]\{6\}|\1.X|g' "$WORK/$_n/err" > "$WORK/$_n/err.n"
}

BAD0=0000000000000000000000000000000000000000000000000000000000000000

@test "default mismatch output is byte-identical to the original script's, but for the shipyard_fetch: prefix" {
  git -C "$BATS_TEST_DIRNAME/.." show a5c3e3d:scripts/mavericks_fetch.sh > "$WORK/orig.sh"
  fetch_capture old "$WORK/orig.sh" mav_fetch_extract "$BAD0" -u MAVERGREEN_PROGRESS
  fetch_capture new "$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh" shipyard_fetch_extract "$BAD0" -u MAVERGREEN_PROGRESS
  sed 's/^mav_fetch: /shipyard_fetch: /' "$WORK/old/err.n" > "$WORK/old/err.renamed" && mv "$WORK/old/err.renamed" "$WORK/old/err.n"
  [ "$(cat "$WORK/new/status")" -ne 0 ]
  [ "$(cat "$WORK/old/status")" = "$(cat "$WORK/new/status")" ]
  [ -s "$WORK/new/err.n" ]
  cmp "$WORK/old/err.n" "$WORK/new/err.n"
  cmp "$WORK/old/out.n" "$WORK/new/out.n"
  [ ! -s "$WORK/new/out" ]
}

@test "a value other than 1 leaves output unchanged, on success and on mismatch" {
  S="$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh"
  fetch_capture u "$S" shipyard_fetch_extract "$SHA" -u MAVERGREEN_PROGRESS
  fetch_capture um "$S" shipyard_fetch_extract "$BAD0" -u MAVERGREEN_PROGRESS
  for v in 0 yes "" 11; do
    fetch_capture v "$S" shipyard_fetch_extract "$SHA" MAVERGREEN_PROGRESS="$v"
    cmp "$WORK/u/err.n" "$WORK/v/err.n"; cmp "$WORK/u/out.n" "$WORK/v/out.n"
    [ "$(cat "$WORK/v/status")" -eq 0 ]
    rm -rf "$WORK/v"
    fetch_capture vm "$S" shipyard_fetch_extract "$BAD0" MAVERGREEN_PROGRESS="$v"
    cmp "$WORK/um/err.n" "$WORK/vm/err.n"; cmp "$WORK/um/out.n" "$WORK/vm/out.n"
    [ "$(cat "$WORK/vm/status")" -ne 0 ]
    rm -rf "$WORK/vm"
  done
}

@test "progress: a mismatch fails and its message is the default one after the download lines" {
  S="$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh"
  fetch_capture d "$S" shipyard_fetch_extract "$BAD0" -u MAVERGREEN_PROGRESS
  fetch_capture p "$S" shipyard_fetch_extract "$BAD0" MAVERGREEN_PROGRESS=1
  [ "$(cat "$WORK/p/status")" -ne 0 ]
  { printf "shipyard_fetch: downloading fixture.tar\nshipyard_fetch: downloaded fixture.tar\n"; cat "$WORK/d/err.n"; } > "$WORK/p/want"
  cmp "$WORK/p/want" "$WORK/p/err.n"
  cmp "$WORK/d/out.n" "$WORK/p/out.n"
  run grep -c 'OK$\|verified' "$WORK/p/err"
  [ "$output" = 0 ]
}

@test "progress, not a terminal: a failed download says why, and the default stays silent" {
  S="$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh"
  NOPE="file://$WORK/no-such-file.tar"
  rc=0
  sh -c '. "$1"; shipyard_fetch_verified "$2" "$3" "$4" fixture.tar' x "$S" "$NOPE" "$SHA" "$CACHE" 2>"$WORK/derr" || rc=$?
  [ "$rc" -ne 0 ]
  [ ! -s "$WORK/derr" ]
  rc=0
  MAVERGREEN_PROGRESS=1 sh -c '. "$1"; shipyard_fetch_verified "$2" "$3" "$4" fixture.tar' x "$S" "$NOPE" "$SHA" "$CACHE" \
    2>"$WORK/err" || rc=$?
  [ "$rc" -ne 0 ]
  [ "$(head -n 1 "$WORK/err")" = "shipyard_fetch: downloading fixture.tar" ]
  grep -q '^curl: ([0-9]*) ' "$WORK/err"
  run grep -c 'downloaded' "$WORK/err"
  [ "$output" = 0 ]
}

@test "progress: a failed check's message keeps a backslash in the cache path" {
  S="$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh"
  C="$WORK/back\\cslash"
  rc=0
  MAVERGREEN_PROGRESS=1 sh -c '. "$1"; shipyard_fetch_verified "$2" "$3" "$4" fixture.tar' x "$S" "$URL" "$BAD0" "$C" \
    2>"$WORK/err" || rc=$?
  [ "$rc" -ne 0 ]
  grep -qF 'back\cslash/.fixture.tar.' "$WORK/err"
  grep -q 'FAILED' "$WORK/err"
}

@test "the mav_* names still answer, until the family has moved to shipyard_*" {
  run sh -c '. "$1"; mav_fetch_verified "$2" "$3" "$4" fixture.tar' x "$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh" "$URL" "$SHA" "$CACHE"
  [ "$status" -eq 0 ]
  [ -f "$CACHE/fixture.tar" ]
  mkdir "$CACHE/.mav-publish.lock"
  x="$(shipyard_fetch_extract "$URL" "$SHA" "$CACHE" fixture.tar payload)"
  MAV_FETCH_LOCK_TRIES=2 run shipyard_fetch_publish "$CACHE" "$x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"held for 2s"* ]] || false
}
