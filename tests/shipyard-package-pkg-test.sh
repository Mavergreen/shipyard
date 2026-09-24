#!/bin/sh
# platform: host-agnostic
# spec: 2026-09-11 decision 1 -- the pkg is ONE prefix holding shipyard's own CMake and shipyard
#       itself, three uniquely named commands exported through the mavergreen link farm, and one
#       universal updater. No registration, no arch picking.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
S="$root/scripts/package-pkg.sh"
[ -f "$S" ] || { echo "FAIL: no scripts/package-pkg.sh"; exit 1; }
w="$(mktemp -d "${TMPDIR:-/tmp}/pkg-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
code() { grep -v '^[[:space:]]*#' "$S"; }   # the script minus its comments

[ "$(code | grep -c -- '--host-arch x86_64,arm64')" = 1 ] || { echo "FAIL: the Distribution must declare BOTH architectures and exactly those -- without arm64, Installer on Apple Silicon offers Rosetta for a pkg with scripts and runs them translated; only one arch would stop the pkg installing on the other box -- package-pkg.sh must pass --host-arch x86_64,arm64 exactly once"; exit 1; }
for gone in register-with-cmake sysctl agent-load-cross uname CrossUpdater modernmavericks mavericks-shipyard/ mavergreen-shipyard emit-preinstall; do
  code | grep -q -- "$gone" && { echo "FAIL: package-pkg.sh still mentions $gone"; exit 1; }
done
for c in cmake ctest cpack; do
  code | grep -q "ln -s $c \"\$STAGE\$PREFIX_DIR/bin/shipyard-$c\"" \
    || { echo "FAIL: shipyard-$c must be a RELATIVE link to $c inside shipyard's own bin, so the farm link resolves through it on any volume"; exit 1; }
  code | grep -q -- "--exclude bin/$c" \
    || { echo "FAIL: bin/$c must be in exports-exclude -- a bare $c in the link farm would shadow whatever cmake the user already has on the path"; exit 1; }
done
code | grep -q 'PREFIX_DIR="/usr/local/mavergreen/shipyard"' \
  || { echo "FAIL: shipyard installs into /usr/local/mavergreen/shipyard, the one directory its short name owns"; exit 1; }
code | grep -q 'usr/local/bin' && { echo "FAIL: shipyard installs nothing into /usr/local/bin -- only the base component's helper lives there"; exit 1; }
code | grep -q 'stage_product.sh' || { echo "FAIL: shipyard gets its install scripts from stage_product.sh like every product"; exit 1; }
code | grep -q -- '--base-version "\$VER"' \
  || { echo "FAIL: the base component shipyard ships must be stamped with the version being built (--base-version \"\$VER\")"; exit 1; }

for missing in --cmake-tree --shipyard-prefix --app --version --out; do
  args="--cmake-tree $w/t --shipyard-prefix $w/p --app $w/MavericksShipyardUpdater.app --version 1.0.0 --out $w/o.pkg"
  args="$(printf '%s' "$args" | sed "s|$missing [^ ]*||")"
  # shellcheck disable=SC2086
  if err="$(sh "$S" $args 2>&1 >/dev/null)"; then echo "FAIL: $missing must be required"; exit 1; fi
  printf '%s\n' "$err" | grep -q -- "$missing" \
    || { echo "FAIL: the refusal for a missing $missing must name it; got '$err'"; exit 1; }
done
mkdir -p "$w/Other.app"
if sh "$S" --cmake-tree "$w/t" --shipyard-prefix "$w/p" --app "$w/Other.app" --version 1.0.0 --out "$w/o.pkg" >/dev/null 2>&1; then
  echo "FAIL: an app not named MavericksShipyardUpdater.app must be refused"; exit 1
fi

# spec: 2026-09-11 decision 1 -- both --cmake-tree and --shipyard-prefix BECOME the product prefix
#       verbatim, so a stray file beside a tree (the tarball it was unpacked from, a .DS_Store, a
#       build dir) would otherwise install into /usr/local/mavergreen/shipyard.
mkfixture() {  # $1 = dir: a tree, a shipyard prefix and an app that all pass every other check
  rm -rf "$1"
  mkdir -p "$1/tree/bin" "$1/tree/doc" "$1/tree/man" "$1/tree/share" \
           "$1/sp/share/cmake/MavericksShipyard" "$1/app/MavericksShipyardUpdater.app"
  for c in cmake ctest cpack; do printf '#!/bin/sh\n' > "$1/tree/bin/$c"; chmod +x "$1/tree/bin/$c"; done
  : > "$1/sp/share/cmake/MavericksShipyard/MavericksShipyardConfig.cmake"
  : > "$1/notadir"
}
# platform: --out under a plain FILE, so a fixture that passes every input check stops at the first
#           mkdir after them -- exercising the checks without pkgbuild, and without a special case
#           for valid input.
run_pkg() {  # $1 = fixture dir; sets $rc and $err
  rc=0
  err="$(sh "$S" --cmake-tree "$1/tree" --shipyard-prefix "$1/sp" \
    --app "$1/app/MavericksShipyardUpdater.app" --version 1.0.0 --out "$1/notadir/o.pkg" 2>&1 >/dev/null)" || rc=$?
}
mkfixture "$w/fa"; run_pkg "$w/fa"
[ "$rc" -ne 0 ] || { echo "FAIL: the fixture was built to stop at --out; it did not fail at all"; exit 1; }
if printf '%s\n' "$err" | grep -q 'unexpected top-level entry'; then
  echo "FAIL: bin/doc/man/share are the payload; none may be refused as unexpected; got '$err'"; exit 1
fi
mkfixture "$w/fb"; : > "$w/fb/tree/shipyard-cmake-tree.tar.gz"; run_pkg "$w/fb"
[ "$rc" -ne 0 ] || { echo "FAIL: a stray file at the --cmake-tree root must be refused"; exit 1; }
printf '%s\n' "$err" | grep -q 'shipyard-cmake-tree.tar.gz' \
  || { echo "FAIL: the refusal must name the stray entry; got '$err'"; exit 1; }
printf '%s\n' "$err" | grep -q -- '--cmake-tree' \
  || { echo "FAIL: the refusal must name the flag that carried it; got '$err'"; exit 1; }
mkfixture "$w/fc"; mkdir -p "$w/fc/sp/build"; run_pkg "$w/fc"
[ "$rc" -ne 0 ] || { echo "FAIL: a stray dir at the --shipyard-prefix root must be refused"; exit 1; }
printf '%s\n' "$err" | grep -q 'build' \
  || { echo "FAIL: the refusal must name the stray entry; got '$err'"; exit 1; }
printf '%s\n' "$err" | grep -q -- '--shipyard-prefix' \
  || { echo "FAIL: the refusal must name the flag that carried it; got '$err'"; exit 1; }

echo "PASS: shipyard-package-pkg"
