#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
_tmp="${TMPDIR:-/tmp}"
w="$(cd -P "$(mktemp -d "${_tmp%/}/shipyard-pins-test.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL $1"; exit 1; }
pin() { sed -n 1p "$here/.mavergreen/ingredients/$1/VERSION"; }
SHIPYARD_FETCH_TRIES=1; export SHIPYARD_FETCH_TRIES
mkdir -p "$w/rel"; : > "$w/rel/SHA256SUMS"
for r in stevedore ed25519 recaulk; do
  mkdir -p "$w/rel/Mavergreen/$r/releases/download/$(pin "$r")"
  : > "$w/rel/Mavergreen/$r/releases/download/$(pin "$r")/SHA256SUMS"
done

V="$(pin stevedore)"
[ -n "$V" ] || fail "the stevedore ingredient pins a release"
printf '#!/bin/sh\necho "stevedore %s"\n' "$V" > "$w/stevedore"; chmod +x "$w/stevedore"
out="$(STEVEDORE="$w/stevedore" sh "$here/scripts/fetch_stevedore.sh")" || fail "fetch_stevedore.sh reads its pin from the checkout"
[ "$out" = "$w/stevedore" ] || fail "fetch_stevedore.sh confirms the pinned stevedore, got $out"
printf '#!/bin/sh\necho "stevedore 0.0"\n' > "$w/other"; chmod +x "$w/other"
if STEVEDORE="$w/other" sh "$here/scripts/fetch_stevedore.sh" >/dev/null 2>&1; then fail "fetch_stevedore.sh refuses another release"; fi

mkdir -p "$w/inst/scripts"
sh "$here/scripts/script-closure.sh" fetch_stevedore.sh > "$w/closure" || fail "script-closure.sh runs"
while IFS= read -r f; do
  mkdir -p "$w/inst/scripts/$(dirname "$f")"
  cp "$here/scripts/$f" "$w/inst/scripts/$f"
done < "$w/closure"
out="$(STEVEDORE="$w/stevedore" sh "$w/inst/scripts/fetch_stevedore.sh")" || fail "fetch_stevedore.sh reads its pin beside a copy of its closure"
[ "$out" = "$w/stevedore" ] || fail "a copied closure confirms the pinned stevedore, got $out"

C="$(pin clang22)"
mkdir -p "$w/clang/bin"
for t in clang ld64.lld llvm-lipo llvm-otool llvm-nm llvm-strings; do printf x > "$w/clang/bin/$t"; chmod 755 "$w/clang/bin/$t"; done
printf '<plist><dict>\n<key>version</key>\n<string>%s</string>\n</dict></plist>\n' "$C" > "$w/clang/mavergreen.plist"
out="$(CLANG22_HOST=mac109 CLANG22_INSTALLED="$w/clang" sh "$here/scripts/fetch_clang22.sh" "$here")" \
  || fail "fetch_clang22.sh reads the clang22 ingredient's VERSION"
[ "$out" = "$w/clang" ] || fail "fetch_clang22.sh uses the installed clang22 at the pin, got $out"

E="$(pin ed25519)"
out="$(ED25519_HOST=Darwin MAVERGREEN_RELEASES="file://$w/rel" sh "$here/scripts/fetch_ed25519_tools.sh" "$w/ed" 2>&1)" \
  && fail "fetch_ed25519_tools.sh finds no pkg in an empty release"
printf '%s\n' "$out" | grep -qF "ed25519-$E.pkg" || fail "fetch_ed25519_tools.sh asks for the pinned release's pkg: $out"

R="$(pin recaulk)"
out="$(NM=true MAVERGREEN_RELEASES="file://$w/rel" MAVERGREEN_PKG_CACHE="$w/cache" sh "$here/scripts/cxxabi-allowlist.sh" 2>&1)" \
  && fail "cxxabi-allowlist.sh finds no pkg in an empty release"
printf '%s\n' "$out" | grep -qF "recaulk $R" || fail "cxxabi-allowlist.sh fetches the pinned Recaulk: $out"

echo "PASS shipyard-pins"
