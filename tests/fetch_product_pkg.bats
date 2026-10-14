#!/usr/bin/env bats
# platform: macOS-only -- pkgbuild and productbuild make the fixture pkg

mkcomp() {  # mkcomp IDENTIFIER ROOT OUT
  pkgbuild --quiet --root "$2" --identifier "$1" --version 1.0 --install-location / "$3"
}

setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/fetch_product_pkg.sh"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/fetch_product_pkg_test.XXXXXX")" && pwd)"
  printf 'widget dev.mavergreen.widget widget-repo\n' > "$WORK/product-names"
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
  productbuild --quiet --package "$WORK/base.pkg" --package "$WORK/prod.pkg" "$REL/$1"
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

@test "a second call replaces DEST afresh from the cached pkg" {
  serve widget-1.0.pkg
  run sh "$HELPER" widget 1.0 "$DEST"; [ "$status" -eq 0 ]
  echo stray > "$DEST/stray"
  rm "$REL/widget-1.0.pkg"
  run sh "$HELPER" widget 1.0 "$DEST"
  [ "$status" -eq 0 ]
  [ ! -e "$DEST/stray" ]
  [ "$(cat "$DEST/lib/libwidget.a")" = W ]
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
