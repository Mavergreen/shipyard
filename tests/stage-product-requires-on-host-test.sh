#!/bin/sh
# platform: host-agnostic
# spec: scripts/stage_product.sh --requires-on-host -- a requirement the generated preinstall enforces on one host arch;
#       the committed registry; sysctl is a stub first on PATH
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/stage_product.sh"
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || { echo "FAIL: fetch_stevedore.sh failed"; exit 1; }; export STEVEDORE="$SD"
w="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/stage-req-host.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
mkdir -p "$w/bin"; PATH="$w/bin:$PATH"; export PATH
stub() { printf '#!/bin/sh\n%s\n' "$1" > "$w/bin/sysctl"; chmod +x "$w/bin/sysctl"; }
stage() {  # $1 = scripts dir, then stage_product options
  _d="$1"; shift
  rm -rf "$w/stage"; mkdir -p "$w/stage/usr/local/mavergreen/swift-toolchain/bin"
  echo x > "$w/stage/usr/local/mavergreen/swift-toolchain/bin/swiftc"
  sh "$S" --stage "$w/stage" --product swift-toolchain --name "Swift Toolchain" --version 1 --scripts-out "$_d" "$@"
}
vol() {  # $1 = volume; products named after it are installed, with an old tree in place
  mkdir -p "$1/usr/local/mavergreen/swift-toolchain/bin"; echo old > "$1/usr/local/mavergreen/swift-toolchain/bin/swiftc"
  shift_v="$1"; shift
  for p in "$@"; do mkdir -p "$shift_v/usr/local/mavergreen/$p"; : > "$shift_v/usr/local/mavergreen/$p/mavergreen.plist"; done
}

stage "$w/scr" --requires sdk109 --requires-on-host x86_64:swift-runtime || fail "staging with --requires-on-host must succeed"
sh -n "$w/scr/preinstall" || fail "the generated preinstall must be valid sh"

test_x86_64_host_missing_runtime_refuses() {
  stub 'exit 1'; V="$w/v1"; vol "$V" sdk109
  rc=0; sh "$w/scr/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
  [ "$rc" -eq 1 ] || fail "a missing swift-runtime on an x86_64 host must exit 1, got $rc"
  grep -q swift-runtime "$w/err" || fail "the refusal names swift-runtime: $(cat "$w/err")"
  grep -q 'https://github.com/Mavergreen/swift/releases/latest' "$w/err" || fail "the refusal names swift's releases URL: $(cat "$w/err")"
  [ "$(cat "$V/usr/local/mavergreen/swift-toolchain/bin/swiftc")" = old ] || fail "a refusal leaves the product tree untouched"
}
test_arm64_host_skips_it() {
  grep -qF 'if [ -n "$ROOT" ] || [ "$(mavergreen_host_arch)" = x86_64 ]; then' "$w/scr/preinstall" \
    || fail "the swift-runtime check must sit inside the host-arch guard"
  grep -q 'mavergreen_host_arch()' "$w/scr/preinstall" || fail "the preinstall must inline host-arch.sh"
  sh -n "$w/scr/preinstall" || fail "the guarded preinstall must be valid sh"
  awk '/mavergreen_host_arch\)" = x86_64/ { g = 1 } g && /swift-runtime/ { ok = 1 } /^fi$/ { g = 0 } END { exit !ok }' "$w/scr/preinstall" \
    || fail "the swift-runtime check must come after the guard"
}
test_non_root_volume_enforces_on_arm64() {
  stub 'echo 1'; V="$w/v3"; vol "$V" sdk109
  rc=0; sh "$w/scr/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
  [ "$rc" -eq 1 ] || fail "an x86_64 requirement is enforced on a non-/ volume even on an arm64 host, got $rc"
  grep -q swift-runtime "$w/err" || fail "the refusal names swift-runtime: $(cat "$w/err")"
  V="$w/v3b"; vol "$V" sdk109 swift-runtime
  sh "$w/scr/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" || fail "with swift-runtime installed the preinstall proceeds: $(cat "$w/err")"
}
test_both_unmet_reported() {
  stub 'exit 1'; V="$w/v4"; vol "$V"
  rc=0; sh "$w/scr/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
  [ "$rc" -eq 1 ] || fail "two unmet requirements must exit 1, got $rc"
  grep -q 'needs sdk109' "$w/err" && grep -q 'needs swift-runtime' "$w/err" \
    || fail "both unmet requirements are reported: $(cat "$w/err")"
}
test_versioned_form() {
  [ -x /usr/libexec/PlistBuddy ] || { echo skip; return 0; }
  stage "$w/scr2" --requires-on-host 'x86_64:swift-runtime>=6.1' || fail "staging a versioned --requires-on-host must succeed"
  stub 'exit 1'; V="$w/v5"; vol "$V"
  mkdir -p "$V/usr/local/mavergreen/swift-runtime"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n<key>version</key>\n<string>6.0</string>\n</dict>\n</plist>\n' \
    > "$V/usr/local/mavergreen/swift-runtime/mavergreen.plist"
  rc=0; sh "$w/scr2/preinstall" /x.pkg "$V/" "$V/" 2>"$w/err" || rc=$?
  [ "$rc" -eq 1 ] || fail "swift-runtime 6.0 against >=6.1 must exit 1, got $rc"
  grep -q '6.1 or newer' "$w/err" || fail "the refusal says 6.1 or newer: $(cat "$w/err")"
}
test_refusals() {
  _r() {  # $1 = wanted text; rest = options
    _want="$1"; shift
    rc=0; stage "$w/scr-bad" "$@" 2>"$w/err" || rc=$?
    [ "$rc" -eq 2 ] || fail "staging with $* must exit 2, got $rc"
    grep -q -- "$_want" "$w/err" || fail "staging with $* must say '$_want': $(cat "$w/err")"
  }
  _r 'names no arch x86_64 or arm64' --requires-on-host ppc:sdk109
  _r 'cannot require itself' --requires-on-host x86_64:swift-toolchain
  _r 'not in shipyard' --requires-on-host x86_64:nosuch
  _r 'both --requires and --requires-on-host' --requires sdk109 --requires-on-host x86_64:sdk109
  _r 'not an orderable version' --requires-on-host 'x86_64:sdk109>=x.y'
}
test_x86_64_host_missing_runtime_refuses; test_arm64_host_skips_it; test_non_root_volume_enforces_on_arm64
test_both_unmet_reported; test_versioned_form; test_refusals
echo "PASS: stage-product-requires-on-host"
