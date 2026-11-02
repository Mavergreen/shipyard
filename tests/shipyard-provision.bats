#!/usr/bin/env bats
# platform: host-agnostic

setup() {
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/shipyard-provision-test.XXXXXX")" && pwd)"
  S="$WORK/scripts"
  mkdir -p "$S/lib" "$WORK/bin" "$WORK/repo/.mavergreen/ingredients" "$WORK/prefix"
  for f in shipyard-provision mavergreen-meta.sh deviation-reason.sh deviations.sh; do cp "$BATS_TEST_DIRNAME/../scripts/$f" "$S/$f" 2>/dev/null || :; done
  cat > "$S/fetch_product_pkg.sh" <<'STUB'
#!/bin/sh
echo "pkg $*" >> "$STUB_LOG"
repo=""; asset=""
while [ $# -gt 3 ]; do case "$1" in --repo) repo=$2 ;; --asset) asset=$2 ;; esac; shift 2; done
mkdir -p "$3"
d="$MAVERGREEN_PKG_CACHE/${repo#*/}/$2"; mkdir -p "$d"; : > "$d/${asset:-$1-$2.pkg}"
printf '%s\n' "$3"
STUB
  cat > "$S/fetch_product_tar.sh" <<'STUB'
#!/bin/sh
echo "tar $*" >> "$STUB_LOG"
while [ $# -gt 4 ]; do shift 2; done
mkdir -p "$4"; printf '%s\n' "$4"
STUB
  printf '#!/bin/sh\necho "sudo $*" >> "$STUB_LOG"\n' > "$WORK/bin/sudo"
  chmod +x "$WORK/bin/sudo"
  export STUB_LOG="$WORK/log"; : > "$STUB_LOG"
  export PATH="$WORK/bin:$PATH"
  export MAVERGREEN_ROOT="$WORK/repo" MAVERGREEN_PREFIX="$WORK/prefix" MAVERGREEN_PKG_CACHE="$WORK/cache"
  export SHIPYARD_PROVISION_OS=Darwin
  unset CI
  P="sh $S/shipyard-provision"
  ing "cmake" Mavergreen/cmake 4.4.5-mavericks.2 cmake shipped
  ing "stevedore" Mavergreen/stevedore 20261027.1 stevedore build-only
}
teardown() { rm -rf "$WORK"; }

ing() {  # ing NAME REPO VERSION PRODUCT ROLE...
  d="$WORK/repo/.mavergreen/ingredients/$1"; mkdir -p "$d"
  printf '%s\n' "$2" > "$d/REPO"
  printf '%s\n# renovate: datasource=github-releases depName=%s\n' "$3" "$2" > "$d/VERSION"
  printf '%s\n' "$4" > "$d/product"
  shift 4; printf '%s\n' "$@" > "$d/role"
}
installed() {  # installed PRODUCT VERSION
  mkdir -p "$WORK/prefix/$1"
  printf '<plist><dict>\n<key>version</key>\n<string>%s</string>\n</dict></plist>\n' "$2" > "$WORK/prefix/$1/mavergreen.plist"
}

@test "an installed copy at the pin is used, with no fetch" {
  installed cmake 4.4.5-mavericks.2
  run $P --only cmake
  [ "$status" -eq 0 ]
  [ "$output" = "cmake=$WORK/prefix/cmake" ]
  [ ! -s "$STUB_LOG" ]
}

@test "an installed copy at another release is not used: the pinned release is fetched" {
  installed cmake 4.4.4-mavericks.1
  run $P --only cmake --into "$WORK/into"
  [ "$status" -eq 0 ]
  [ "$output" = "cmake=$WORK/into/cmake-4.4.5-mavericks.2" ]
  [ "$(cat "$STUB_LOG")" = "pkg --repo Mavergreen/cmake cmake 4.4.5-mavericks.2 $WORK/into/cmake-4.4.5-mavericks.2" ]
}

@test "--role keeps only the ingredients with one of the roles" {
  run $P --role build-only --into "$WORK/into"
  [ "$status" -eq 0 ]
  [ "$output" = "stevedore=$WORK/into/stevedore-20261027.1" ]
  run $P --role linked,shipped --into "$WORK/into"
  [ "$output" = "cmake=$WORK/into/cmake-4.4.5-mavericks.2" ]
}

@test "an ingredient with no product is not provisioned" {
  mkdir -p "$WORK/repo/.mavergreen/ingredients/bats"; echo test > "$WORK/repo/.mavergreen/ingredients/bats/role"
  run $P --into "$WORK/into"
  [ "$status" -eq 0 ]
  [[ "$output" != *bats* ]] || false
}

@test "--only names an ingredient that has no product: fails, naming it" {
  run $P --only nonesuch --into "$WORK/into"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nonesuch"* ]] || false
}

@test "a from child comes out of its parent's download" {
  d="$WORK/repo/.mavergreen/ingredients/libcxx22"; mkdir -p "$d"
  printf 'clang22\n' > "$d/from"; printf 'libcxx22\n' > "$d/product"; printf 'linked\n' > "$d/role"
  ing clang22 Mavergreen/clang-22 22.1.8-mavericks.12 clang22 build-only
  run $P --only libcxx22 --into "$WORK/into"
  [ "$status" -eq 0 ]
  [ "$output" = "libcxx22=$WORK/into/libcxx22-22.1.8-mavericks.12" ]
  [ "$(cat "$STUB_LOG")" = "pkg --repo Mavergreen/clang-22 libcxx22 22.1.8-mavericks.12 $WORK/into/libcxx22-22.1.8-mavericks.12" ]
}

@test "Linux takes the tarball path for an ingredient with a LINUX_SHA256" {
  sha=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  printf '%s\n' "$sha" > "$WORK/repo/.mavergreen/ingredients/cmake/LINUX_SHA256"
  SHIPYARD_PROVISION_OS=Linux run $P --into "$WORK/into"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmake=$WORK/into/cmake-4.4.5-mavericks.2"* ]] || false
  grep -qx "tar --repo Mavergreen/cmake cmake 4.4.5-mavericks.2 $sha $WORK/into/cmake-4.4.5-mavericks.2" "$STUB_LOG"
  grep -qx "pkg --repo Mavergreen/stevedore stevedore 20261027.1 $WORK/into/stevedore-20261027.1" "$STUB_LOG"
}

@test "a relocatable product without --install stops, saying so" {
  d="$WORK/repo/.mavergreen/deviations/relocatable/cmake"; mkdir -p "$d"
  echo cmake > "$d/scope"; echo 'loads its modules from its real prefix' > "$d/reason"; echo 'when cmake finds its modules relative to itself' > "$d/revisit"
  run $P --only cmake --into "$WORK/into"
  [ "$status" -eq 1 ]
  [ "$output" = "shipyard-provision: cmake only works from its real prefix (deviation relocatable); rerun with --install" ]
  [ ! -s "$STUB_LOG" ]
}

@test "a relocatable product with --install is installed from the pinned pkg" {
  d="$WORK/repo/.mavergreen/deviations/relocatable/cmake"; mkdir -p "$d"
  echo cmake > "$d/scope"; echo 'loads its modules from its real prefix' > "$d/reason"; echo 'when cmake finds its modules relative to itself' > "$d/revisit"
  run $P --only cmake --install
  [ "$status" -eq 0 ]
  [ "$output" = "cmake=$WORK/prefix/cmake" ]
  grep -qx "sudo installer -pkg $WORK/cache/cmake/4.4.5-mavericks.2/cmake-4.4.5-mavericks.2.pkg -target /" "$STUB_LOG"
}

@test "CI=true implies --install" {
  CI=true run $P --only cmake
  [ "$status" -eq 0 ]
  [ "$output" = "cmake=$WORK/prefix/cmake" ]
  grep -q '^sudo installer ' "$STUB_LOG"
}

@test "no --install and no CI: nothing is installed" {
  run $P --only cmake --into "$WORK/into"
  [ "$status" -eq 0 ]
  run grep -q "^sudo" "$STUB_LOG"
  [ "$status" -ne 0 ]
}

@test "--env-file writes MAVERGREEN_INGREDIENT_<name>=<path>, a dash in a name becoming an underscore" {
  ing python-315 Mavergreen/python-315 3.15.0-mavericks.1 python315 test
  run $P --role test,shipped --into "$WORK/into" --env-file "$WORK/env"
  [ "$status" -eq 0 ]
  [ "$(cat "$WORK/env")" = "MAVERGREEN_INGREDIENT_cmake=$WORK/into/cmake-4.4.5-mavericks.2
MAVERGREEN_INGREDIENT_python_315=$WORK/into/python315-3.15.0-mavericks.1" ]
  [[ "$output" == *"python-315=$WORK/into/python315-3.15.0-mavericks.1"* ]] || false
}

@test "--product and --asset steer the one ingredient --only names" {
  run $P --only cmake --product cmake-cross --asset other.pkg --into "$WORK/into"
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = "pkg --repo Mavergreen/cmake --asset other.pkg cmake-cross 4.4.5-mavericks.2 $WORK/into/cmake-cross-4.4.5-mavericks.2" ]
  run $P --asset other.pkg --into "$WORK/into"
  [ "$status" -eq 2 ]
}

@test "an ingredient with a product but no REPO or VERSION fails, naming the file" {
  rm "$WORK/repo/.mavergreen/ingredients/cmake/REPO"
  run $P --only cmake --into "$WORK/into"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ingredients/cmake/REPO"* ]] || false
}

@test "a version that is not a release tag is a usage error" {
  printf '../x\n' > "$WORK/repo/.mavergreen/ingredients/cmake/VERSION"
  run $P --only cmake --into "$WORK/into"
  [ "$status" -eq 2 ]
}
