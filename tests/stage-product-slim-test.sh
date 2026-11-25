#!/bin/sh
# platform: host-agnostic
# spec: stage_product.sh -- the generated postinstall slims on the boot volume only and never fatally; --slim-host is validated by render-manifest.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/stage_product.sh"
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || { echo "FAIL: fetch_stevedore.sh failed"; exit 1; }; export STEVEDORE="$SD"
w="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/stage-slim.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
stage() {
  rm -rf "$w/st" "$w/scr"; mkdir -p "$w/st/usr/local/mavergreen/recaulk/bin"; echo x > "$w/st/usr/local/mavergreen/recaulk/bin/x"
  sh "$S" --stage "$w/st" --product recaulk --name Recaulk --version 1 --scripts-out "$w/scr" "$@"
}
LINE='if [ -z "$ROOT" ]; then "$MG" slim apply recaulk || echo "recaulk: could not slim; the universal tree stays" >&2; fi'
stub="$w/mavergreen"; log="$w/log"
printf '#!/bin/sh\necho "$*" >> "%s"\ncase "$*" in *slim*) [ -z "${SLIM_FAILS:-}" ] || exit 1 ;; esac\nexit 0\n' "$log" > "$stub"; chmod +x "$stub"

test_postinstall_calls_slim_on_boot_volume_only() {
  stage
  po="$w/scr/postinstall"
  [ "$(grep -cxF "$LINE" "$po")" = 1 ] || fail "the postinstall has exactly the slim line"
  l="$(grep -n ' link recaulk' "$po" | cut -d: -f1)"; s="$(grep -nxF "$LINE" "$po" | cut -d: -f1)"
  [ "$s" -eq $((l + 1)) ] || fail "the slim line follows the link line immediately"
  sh -n "$po" || fail "the postinstall is valid sh"
}
test_non_root_volume_never_slims() {
  stage
  vol="$w/vol"; rm -rf "$vol"; mkdir -p "$vol/usr/local/bin"; cp "$stub" "$vol/usr/local/bin/mavergreen"; : > "$log"
  sh "$w/scr/postinstall" x x "$vol" || fail "the postinstall runs against a non-root volume"
  grep -q ' link recaulk' "$log" || fail "the stub saw link"
  grep -q "slim apply" "$log" && fail "a non-root volume never slims"
  return 0
}
test_slim_failure_is_not_fatal() {
  stage
  sed -e 's|^ROOT=.*|ROOT=""|' -e "s|^MG=.*|MG=\"$stub\"|" "$w/scr/postinstall" > "$w/po.boot"
  grep -q '^ROOT=""$' "$w/po.boot" || fail "ROOT was forced empty"
  : > "$log"
  SLIM_FAILS=1 sh "$w/po.boot" x x / 2> "$w/err" || fail "a failing slim does not fail the postinstall"
  grep -q 'slim apply recaulk' "$log" || fail "slim ran on the boot volume"
  grep -q 'could not slim' "$w/err" || fail "stderr says could not slim"
}
test_slim_host_refusals() {
  for g in /abs '../x' 'a/../x' './x' '*/*' '*' '?' ''; do
    rc=0; stage --slim-host "$g" 2>"$w/err" || rc=$?
    [ "$rc" = 2 ] || fail "--slim-host '$g' exits 2, got $rc"
    grep -q '^render-manifest: --slim-host' "$w/err" || fail "render-manifest is the one validator of --slim-host '$g': $(cat "$w/err")"
  done
  stage --slim-host 'bin/*' --slim-host 'libexec/a b' || fail "valid globs are accepted"
  grep -q 'bin/\*' "$w/st/usr/local/mavergreen/recaulk/mavergreen.plist" || fail "the manifest carries the glob"
}
test_postinstall_calls_slim_on_boot_volume_only
test_non_root_volume_never_slims
test_slim_failure_is_not_fatal
test_slim_host_refusals
echo "PASS: stage-product-slim"
