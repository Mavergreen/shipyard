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

# platform: shipyard_curl's tests put a stub curl first on PATH. Each line of $WORK/stub/plan is one
#           attempt's "<curl exit> <http code>"; a failing attempt writes a partial body, a passing
#           one writes $WORK/stub/body. Every call's arguments land in $WORK/stub/calls.
stub_curl() {   # stub_curl "<exit> <http>"...
  mkdir -p "$WORK/stub"
  printf '%s\n' "$@" > "$WORK/stub/plan"
  printf 'the body\n' > "$WORK/stub/body"
  : > "$WORK/stub/calls"
  cat > "$WORK/stub/curl" <<'STUB'
#!/bin/sh
n=$(( $(wc -l < "$STUB_DIR/calls") + 1 ))
printf '%s\n' "$*" >> "$STUB_DIR/calls"
out=
while [ $# -gt 0 ]; do
  case $1 in -o) out=$2; shift ;; esac
  shift
done
line=$(sed -n "${n}p" "$STUB_DIR/plan")
rc=${line%% *}; http=${line#* }
if [ "$rc" = 0 ]; then cat "$STUB_DIR/body" > "$out"; else printf 'partial' > "$out"; fi
printf '%s' "$http"
exit "$rc"
STUB
  chmod +x "$WORK/stub/curl"
}

SURL=https://example.invalid/x.tar

sc() {   # sc [ENV=VAL...] -- ARGS: shipyard_curl ARGS under sh; sets rc, $WORK/out and $WORK/err
  _env=
  while [ "$1" != -- ]; do _env="$_env $1"; shift; done; shift
  rc=0
  env PATH="$WORK/stub:$PATH" STUB_DIR="$WORK/stub" SHIPYARD_FETCH_BACKOFF=0 $_env \
    sh -c '. "$1"; shift; shipyard_curl "$@"' x "$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh" "$@" \
    >"$WORK/out" 2>"$WORK/err" || rc=$?
}

calls() { wc -l < "$WORK/stub/calls" | tr -d ' '; }

@test "shipyard_curl: a reset twice, then success, passes with two retry lines" {
  stub_curl "56 000" "56 000" "0 200"
  sc -- "$SURL" "$WORK/x.tar"
  [ "$rc" -eq 0 ]
  [ "$(cat "$WORK/x.tar")" = "the body" ]
  [ -z "$(ls "$WORK" | grep '^x\.tar\.part')" ]
  [ ! -s "$WORK/out" ]
  printf 'shipyard_curl: %s: curl exit 56; retry 1 of 5 in 2s\nshipyard_curl: %s: curl exit 56; retry 2 of 5 in 4s\n' "$SURL" "$SURL" > "$WORK/want"
  cmp "$WORK/want" "$WORK/err"
  [ "$(calls)" -eq 3 ]
  grep -qE -- "-fL -sS --connect-timeout 20 --speed-limit 1024 --speed-time 60 -w %\\{http_code\\} -o $WORK/x.tar.part.[A-Za-z0-9]+ $SURL\$" "$WORK/stub/calls"
  run grep -c -- '-C' "$WORK/stub/calls"
  [ "$output" = 0 ]
}

@test "shipyard_curl: another fetch's OUT.part is never touched" {
  stub_curl "56 000" "0 200"
  printf 'theirs\n' > "$WORK/x.tar.part"
  sc -- "$SURL" "$WORK/x.tar"
  [ "$rc" -eq 0 ]
  [ "$(cat "$WORK/x.tar")" = "the body" ]
  [ "$(cat "$WORK/x.tar.part")" = "theirs" ]
  run grep -c -- "-o $WORK/x.tar.part " "$WORK/stub/calls"
  [ "$output" = 0 ]
}

@test "shipyard_curl: a 404 fails at once, with no retry and no file" {
  stub_curl "22 404"
  sc -- "$SURL" "$WORK/x.tar"
  [ "$rc" -eq 22 ]
  [ "$(calls)" -eq 1 ]
  run grep -c retry "$WORK/err"
  [ "$output" = 0 ]
  [ ! -e "$WORK/x.tar" ]
  [ -z "$(ls "$WORK" | grep '^x\.tar\.part')" ]
}

@test "shipyard_curl: a reset five times fails after five tries, backing off 2, 4, 8, 16s" {
  stub_curl "56 000" "56 000" "56 000" "56 000" "56 000" "0 200"
  sc -- "$SURL" "$WORK/x.tar"
  [ "$rc" -eq 56 ]
  [ "$(calls)" -eq 5 ]
  for n in 1 2 3 4; do
    w=$((1 << n))
    grep -qx "shipyard_curl: $SURL: curl exit 56; retry $n of 5 in ${w}s" "$WORK/err"
  done
  [ "$(tail -n 1 "$WORK/err")" = "shipyard_curl: $SURL: curl exit 56; giving up after 5 tries" ]
  [ "$(wc -l < "$WORK/err" | tr -d ' ')" -eq 5 ]
  [ ! -e "$WORK/x.tar" ]
  [ -z "$(ls "$WORK" | grep '^x\.tar\.part')" ]
}

@test "shipyard_curl: SHIPYARD_FETCH_TRIES bounds the attempts" {
  stub_curl "56 000" "56 000" "0 200"
  sc SHIPYARD_FETCH_TRIES=2 -- "$SURL" "$WORK/x.tar"
  [ "$rc" -eq 56 ]
  [ "$(calls)" -eq 2 ]
  sc SHIPYARD_FETCH_TRIES=none -- "$SURL" "$WORK/x.tar"
  [ "$rc" -eq 2 ]
}

@test "shipyard_curl: HTTP 503 and 429 are retried, and then the download passes" {
  stub_curl "22 503" "22 429" "0 200"
  sc -- "$SURL" "$WORK/x.tar"
  [ "$rc" -eq 0 ]
  [ "$(calls)" -eq 3 ]
  grep -qx "shipyard_curl: $SURL: HTTP 503; retry 1 of 5 in 2s" "$WORK/err"
  grep -qx "shipyard_curl: $SURL: HTTP 429; retry 2 of 5 in 4s" "$WORK/err"
  [ "$(cat "$WORK/x.tar")" = "the body" ]
}

@test "shipyard_curl: a stalled transfer (exit 28) is retried" {
  stub_curl "28 200" "0 200"
  sc -- "$SURL" "$WORK/x.tar"
  [ "$rc" -eq 0 ]
  [ "$(calls)" -eq 2 ]
  grep -qx "shipyard_curl: $SURL: curl exit 28; retry 1 of 5 in 2s" "$WORK/err"
}

@test "shipyard_curl: an exit it does not know (37) is not retried" {
  stub_curl "37 000" "0 200"
  sc -- "$SURL" "$WORK/x.tar"
  [ "$rc" -eq 37 ]
  [ "$(calls)" -eq 1 ]
}

@test "shipyard_curl -: a failed attempt prints nothing, and the body prints once on success" {
  stub_curl "56 000" "0 200"
  sc -- "$SURL" -
  [ "$rc" -eq 0 ]
  printf 'the body\n' > "$WORK/want"
  cmp "$WORK/want" "$WORK/out"
  stub_curl "56 000" "22 404"
  sc -- "$SURL" -
  [ "$rc" -eq 22 ]
  [ ! -s "$WORK/out" ]
}

@test "shipyard_curl: a call that makes no attempt leaves no stale HTTP code" {
  stub_curl "22 404" "22 404"
  rc=0
  env PATH="$WORK/stub:$PATH" STUB_DIR="$WORK/stub" SHIPYARD_FETCH_BACKOFF=0 \
    sh -c '. "$1"; shipyard_curl "$2" "$3"; printf "first=%s\n" "$shipyard_curl_http"
           shipyard_curl "$2"; printf "usage=%s rc=%s\n" "$shipyard_curl_http" "$?"
           shipyard_curl "$2" "$3"; SHIPYARD_FETCH_TRIES=0 shipyard_curl "$2" "$3"; printf "tries=%s\n" "$shipyard_curl_http"' \
    x "$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh" "$SURL" "$WORK/x.tar" >"$WORK/out" 2>"$WORK/err" || rc=$?
  cat "$WORK/out"
  printf 'first=404\nusage= rc=2\ntries=\n' > "$WORK/want"
  cmp "$WORK/want" "$WORK/out"
}

@test "shipyard_curl under set -e: a retried fetch carries on, a failed one stops the caller" {
  stub_curl "56 000" "0 200"
  run env PATH="$WORK/stub:$PATH" STUB_DIR="$WORK/stub" SHIPYARD_FETCH_BACKOFF=0 \
    sh -ec '. "$1"; shipyard_curl "$2" "$3"; echo after' x "$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh" "$SURL" "$WORK/x.tar"
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = after ]
  stub_curl "22 404"
  run env PATH="$WORK/stub:$PATH" STUB_DIR="$WORK/stub" SHIPYARD_FETCH_BACKOFF=0 \
    sh -ec '. "$1"; shipyard_curl "$2" "$3"; echo after' x "$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh" "$SURL" "$WORK/y.tar"
  [ "$status" -eq 22 ]
  [[ "$output" != *after* ]] || false
}

@test "shipyard_fetch_verified retries a reset, and its default output gains only the retry line" {
  stub_curl "56 000" "0 200"
  cp "$WORK/stub/body" "$WORK/b"
  BSHA="$(shasum -a 256 "$WORK/b" | awk '{print $1}')"
  rc=0
  env PATH="$WORK/stub:$PATH" STUB_DIR="$WORK/stub" SHIPYARD_FETCH_BACKOFF=0 \
    sh -c '. "$1"; shipyard_fetch_verified "$2" "$3" "$4" x.tar' x "$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh" "$SURL" "$BSHA" "$CACHE" \
    2>"$WORK/err" || rc=$?
  [ "$rc" -eq 0 ]
  [ "$(calls)" -eq 2 ]
  [ "$(head -n 1 "$WORK/err")" = "shipyard_curl: $SURL: curl exit 56; retry 1 of 5 in 2s" ]
  [ "$(wc -l < "$WORK/err" | tr -d ' ')" -eq 2 ]
  [ -f "$CACHE/x.tar" ]
}

@test "a checksum mismatch after a good download is not retried" {
  stub_curl "0 200" "0 200"
  rc=0
  env PATH="$WORK/stub:$PATH" STUB_DIR="$WORK/stub" SHIPYARD_FETCH_BACKOFF=0 \
    sh -c '. "$1"; shipyard_fetch_verified "$2" "$3" "$4" x.tar' x "$BATS_TEST_DIRNAME/../scripts/mavericks_fetch.sh" "$SURL" "$SHA" "$CACHE" \
    2>"$WORK/err" || rc=$?
  [ "$rc" -ne 0 ]
  [ "$(calls)" -eq 1 ]
  grep -q "not the pinned $SHA" "$WORK/err"
  [ -z "$(find "$CACHE" -mindepth 1)" ]
}

