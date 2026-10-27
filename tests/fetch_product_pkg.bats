#!/usr/bin/env bats
# platform: host-agnostic -- stevedore builds the fixtures and fetch_product_pkg.sh reads them

mkcomp() {  # mkcomp IDENTIFIER ROOT OUT
  sh "$BATS_TEST_DIRNAME/../scripts/build_component_pkg.sh" --root "$2" --identifier "$1" --version 1.0 \
    --install-location / --out "$3" > /dev/null 2>&1
}

setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/fetch_product_pkg.sh"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/fetch_product_pkg_test.XXXXXX")" && pwd)"
  printf 'widget dev.mavergreen.widget widget-repo\n' > "$WORK/product-names"
  export SOURCE_DATE_EPOCH=1700000000
  if [ -z "${STEVEDORE:-}" ]; then
    STEVEDORE="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_stevedore.sh")" || { echo "fetch_stevedore.sh failed" >&2; return 1; }
  fi
  export STEVEDORE
  export MAVERGREEN_PRODUCT_NAMES="$WORK/product-names"
  export MAVERGREEN_RELEASES="file://$WORK/rel" MAVERGREEN_PKG_CACHE="$WORK/cache"
  REL="$WORK/rel/Mavergreen/widget-repo/releases/download/1.0"
  mkdir -p "$REL" "$WORK/base/usr/local/mavergreen/.base" "$WORK/prod/usr/local/mavergreen/widget/lib" \
    "$WORK/prod/usr/local/mavergreen/widget/include/widget"
  echo x > "$WORK/base/usr/local/mavergreen/.base/x"
  printf W > "$WORK/prod/usr/local/mavergreen/widget/lib/libwidget.a"
  : > "$WORK/prod/usr/local/mavergreen/widget/include/widget/w.h"
  DEST="$WORK/out/widget"
}
teardown() { rm -rf "$WORK"; }

serve() {  # serve ASSET [PRODUCT_IDENTIFIER]: build the archive (base first) and list it in SHA256SUMS
  mkcomp dev.mavergreen.base "$WORK/base" "$WORK/base.pkg"
  mkcomp "${2:-dev.mavergreen.widget}" "$WORK/prod" "$WORK/prod.pkg"
  cat > "$WORK/dist.xml" <<DIST
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
  <pkg-ref id="dev.mavergreen.base" version="1.0">base.pkg</pkg-ref>
  <pkg-ref id="${2:-dev.mavergreen.widget}" version="1.0">prod.pkg</pkg-ref>
  <choices-outline><line choice="dev.mavergreen.base"/><line choice="${2:-dev.mavergreen.widget}"/></choices-outline>
  <choice id="dev.mavergreen.base"><pkg-ref id="dev.mavergreen.base"/></choice>
  <choice id="${2:-dev.mavergreen.widget}"><pkg-ref id="${2:-dev.mavergreen.widget}"/></choice>
</installer-gui-script>
DIST
  "$STEVEDORE" product --distribution "$WORK/dist.xml" --package "$WORK/base.pkg" --package "$WORK/prod.pkg" \
    --mtime 1700000000 --out "$REL/$1" > /dev/null
  ( cd "$REL" && shasum -a 256 "$1" > SHA256SUMS )
}

@test "extracts the named component's tree; stdout is DEST only" {
  serve widget-1.0.pkg
  out="$(sh "$HELPER" widget 1.0 "$DEST" 2>/dev/null)"
  [ "$out" = "$DEST" ]
  [ "$(cat "$DEST/lib/libwidget.a")" = W ]
  [ -f "$DEST/include/widget/w.h" ]
  [ ! -e "$DEST/.base" ]
}

@test "the base component first does not confuse the pick" {
  mkdir -p "$WORK/base/usr/local/mavergreen/widget/lib"
  printf BASE > "$WORK/base/usr/local/mavergreen/widget/lib/libwidget.a"
  serve widget-1.0.pkg
  run sh "$HELPER" widget 1.0 "$DEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/lib/libwidget.a")" = W ]
}

@test "a second call for the same pkg keeps DEST in place, so a build using it is not pulled from under" {
  serve widget-1.0.pkg
  run sh "$HELPER" widget 1.0 "$DEST"; [ "$status" -eq 0 ]
  echo kept > "$DEST/marker"
  rm "$REL/widget-1.0.pkg"
  run sh "$HELPER" widget 1.0 "$DEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/marker")" = kept ]
}

@test "a tree with no record of its pkg, or another release's, is replaced afresh" {
  serve widget-1.0.pkg
  mkdir -p "$DEST"; echo stray > "$DEST/stray"
  run sh "$HELPER" widget 1.0 "$DEST"
  [ "$status" -eq 0 ]
  [ ! -e "$DEST/stray" ]
  [ "$(cat "$DEST/lib/libwidget.a")" = W ]
  echo stray > "$DEST/stray"
  printf 'X' >> "$WORK/prod/usr/local/mavergreen/widget/lib/libwidget.a"
  REL="$WORK/rel/Mavergreen/widget-repo/releases/download/2.0"; mkdir -p "$REL"
  serve widget-2.0.pkg
  run sh "$HELPER" widget 2.0 "$DEST"
  [ "$status" -eq 0 ]
  [ ! -e "$DEST/stray" ]
  [ "$(cat "$DEST/lib/libwidget.a")" = WX ]
}

@test "concurrent calls for the same pkg and DEST all succeed, with one whole tree" {
  serve widget-1.0.pkg
  for i in 1 2 3 4; do ( sh "$HELPER" widget 1.0 "$DEST" > "$WORK/out$i" 2> "$WORK/err$i"; echo $? > "$WORK/rc$i" ) & done
  wait
  for i in 1 2 3 4; do
    [ "$(cat "$WORK/rc$i")" = 0 ] || { cat "$WORK/err$i"; false; }
    [ "$(cat "$WORK/out$i")" = "$DEST" ]
  done
  [ "$(cat "$DEST/lib/libwidget.a")" = W ]
  [ -z "$(ls -d "$DEST".tmp.* "$DEST".old.* "$DEST".lock 2>/dev/null)" ]
}

@test "a lock nobody releases fails after SHIPYARD_LOCK_WAIT seconds, naming it" {
  serve widget-1.0.pkg
  mkdir -p "$DEST.lock"
  SHIPYARD_LOCK_WAIT=1 run sh "$HELPER" widget 1.0 "$DEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$DEST.lock"* ]] || false
}

@test "a pkg whose SHA-256 does not match fails 1 and leaves no cached pkg" {
  serve widget-1.0.pkg
  printf '%064d  widget-1.0.pkg\n' 0 > "$REL/SHA256SUMS"
  run sh "$HELPER" widget 1.0 "$DEST"
  [ "$status" -eq 1 ]
  [ ! -e "$DEST" ]
  [ -z "$(find "$WORK/cache" -name '*.pkg*' 2>/dev/null)" ]
}

@test "an asset SHA256SUMS does not list fails 1, naming the asset" {
  serve widget-1.0.pkg
  printf '%064d  other.pkg\n' 0 > "$REL/SHA256SUMS"
  run sh "$HELPER" widget 1.0 "$DEST"
  [ "$status" -eq 1 ]
  case "$output" in *"widget-1.0.pkg is not listed"*) : ;; *) false ;; esac
}

@test "a pkg without the registry's identifier fails 1, naming the identifier" {
  serve widget-1.0.pkg dev.mavergreen.gadget
  run sh "$HELPER" widget 1.0 "$DEST"
  [ "$status" -eq 1 ]
  case "$output" in *dev.mavergreen.widget*) : ;; *) false ;; esac
  [ ! -e "$DEST" ]
}

@test "an unregistered short name fails, naming it" {
  serve widget-1.0.pkg
  run sh "$HELPER" gizmo 1.0 "$DEST"
  [ "$status" -ne 0 ]
  case "$output" in *gizmo*) : ;; *) false ;; esac
}

@test "--asset overrides the default filename" {
  serve mavericks-widget-x-1.0.pkg
  run sh "$HELPER" --asset mavericks-widget-x-1.0.pkg widget 1.0 "$DEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/lib/libwidget.a")" = W ]
}

@test "wrong argument count exits 2" {
  run sh "$HELPER" widget 1.0; [ "$status" -eq 2 ]
  run sh "$HELPER" --asset; [ "$status" -eq 2 ]
  run sh "$HELPER" widget 1.0 "$DEST" extra; [ "$status" -eq 2 ]
}

@test "a relative DEST is extracted and printed as an absolute path" {
  serve widget-1.0.pkg
  cd "$WORK"
  run sh "$HELPER" widget 1.0 out/rel
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "$WORK/out/rel" ]
  [ "$(cat "$WORK/out/rel/lib/libwidget.a")" = W ]
}
