#!/bin/sh
# platform: macOS-only -- builds and runs the Foundation-based project inspector and the exporter
# usage: sh tests/xcode-inputs-test.sh
#        mavericks-xcode-inputs and mavericks_export_xcode_sources against a fixture project and the
#        pinned iTerm2 3.0.15 project: source-phase membership, multiplicity, paths with spaces, variant
#        groups and models; every malformed or unsafe input refused before any generated CMake exists.
#        MAVERICKS_HOST_TOOLS_CC names the compiler (default: clang-22 on 10.9, clang-22-cross on a
#        modern Mac). Without one the test skips, unless SHIPYARD_ON_TARGET=1 (tests/maintainer-tests).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
fx="$here/fixtures/xcode-inputs"
SC="${CMAKE:-$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)}"
unmet() {
  if [ "${SHIPYARD_ON_TARGET:-}" = 1 ]; then echo "FAIL: $*"; exit 1; fi
  echo "SKIP: $*"; exit 77
}
CC="${MAVERICKS_HOST_TOOLS_CC:-}"
if [ -z "$CC" ]; then
  for c in /usr/local/mavergreen/bin/clang-22 /usr/local/mavergreen/bin/clang-22-cross; do
    [ -x "$c" ] && { CC="$c"; break; }
  done
fi
[ -x "$SC" ] || unmet "no shipyard-cmake"
[ -n "$CC" ] && [ -x "$CC" ] || unmet "no clang22 (set MAVERICKS_HOST_TOOLS_CC)"

_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/xcode inputs.XXXXXX")"
trap 'rm -rf "$w"' EXIT
cd "$w"
fail=0
bad() { echo "FAIL: $*"; fail=1; }

"$SC" -DMODULE_DIR="$root" -DCOMPILER="$CC" -DROOT="$w/ht" -DRESULT="$w/bin" -P "$fx/tools.cmake" > "$w/tools.log" 2>&1 \
  || { cat "$w/tools.log"; echo "FAIL: the host tools did not build"; exit 1; }
INSPECT="$(cat "$w/bin")/mavericks-xcode-inputs"
[ -x "$INSPECT" ] || { echo "FAIL: no mavericks-xcode-inputs in $(cat "$w/bin")"; exit 1; }

cp -R "$fx/src" "$w/fx"
P="$w/fx/fx.xcodeproj"
json() { "$SC" -DJSON="$1" -DQUERY="$2" -P "$fx/query.cmake" 2>/dev/null; }
export_() {
  "$SC" -DMODULE_DIR="$root" -DCOMPILER="$CC" -DPROJECT="$1" -DTARGETS="$2" -DPREFIXES="$3" -DOUT="$4" \
    -DRESULT="$w/result" -P "$fx/export.cmake" > "$w/export.log" 2>&1
}
entries() { "$SC" -DFILE="$1" -DVAR="$2" -P "$fx/count.cmake"; }

echo "== inspector: group_relative_paths, same_basename_different_dirs, spaces, multiplicity, variants, models"
if "$INSPECT" --project "$P" --target App --target "Lib Thing" --output "$w/fx.json" > "$w/inspect.log" 2>&1; then
  json "$w/fx.json" "App sources" > "$w/app-sources"
  for want in "source Sources/main.m" "source Sources/a/Thing.m" "source Sources/b/Thing.m" \
              "source Sources/With Space/Spaced.m" "model Model.xcdatamodeld"; do
    grep -qxF "$want" "$w/app-sources" || bad "inspector: App sources lack '$want': $(cat "$w/app-sources")"
  done
  [ "$(grep -cxF 'source Shared/util.c' "$w/app-sources")" = 2 ] || bad "inspector: util.c is in App's sources phase twice"
  [ "$(wc -l < "$w/app-sources" | tr -d ' ')" = 7 ] || bad "inspector: App has 7 source-phase entries, got: $(cat "$w/app-sources")"
  json "$w/fx.json" "App resources" > "$w/app-res"
  for want in "variant Resources/en.lproj/Main.xib" "variant Resources/fr.lproj/Main.xib" "file README.txt" \
              "product libLibThing.a"; do
    grep -qxF "$want" "$w/app-res" || bad "inspector: App resources lack '$want': $(cat "$w/app-res")"
  done
  [ "$(json "$w/fx.json" "App headers")" = "header Shared/util.h" ] || bad "inspector: App headers"
  [ "$(json "$w/fx.json" "Lib Thing sources")" = "source Lib/lib.m" ] || bad "inspector: a path through a pathless named group"
else
  bad "inspector failed on the fixture: $(cat "$w/inspect.log")"
fi
[ ! -e /tmp/never-run ] || bad "inspector: an upstream shell phase ran"

refused() {
  name="$1"; shift
  if "$INSPECT" "$@" --output "$w/$name.json" > "$w/$name.log" 2>&1; then bad "inspector: $name was accepted"; fi
  [ ! -e "$w/$name.json" ] || bad "inspector: $name left output behind"
  grep -q 'mavericks-xcode-inputs:' "$w/$name.log" || bad "inspector: $name refused without saying why: $(cat "$w/$name.log")"
}
echo "== unknown_target"
refused unknown_target --project "$P" --target Nope
variant() {
  rm -rf "$w/$1"; cp -R "$fx/src" "$w/$1"
  printf '%s\n' "$w/$1/fx.xcodeproj"
}
echo "== outside_source_symlink"
v="$(variant outside)"; printf 'outside\n' > "$w/outside.m"; rm "$w/outside/Sources/main.m"; ln -s "$w/outside.m" "$w/outside/Sources/main.m"
refused outside_source_symlink --project "$v" --target App
echo "== unknown_record"
v="$(variant unknown)"; sed -i '' 's/F0000000000000000000000A = {isa = PBXFileReference;/F0000000000000000000000A = {isa = PBXReferenceProxy;/' "$v/project.pbxproj"
refused unknown_record --project "$v" --target App
v="$(variant absolute)"; sed -i '' 's|path = README.txt; sourceTree = SOURCE_ROOT;|path = /etc/hosts; sourceTree = "<absolute>";|' "$v/project.pbxproj"
refused absolute_reference --project "$v" --target App
v="$(variant escaping)"; sed -i '' 's|path = README.txt; sourceTree = SOURCE_ROOT;|path = ../README.txt; sourceTree = SOURCE_ROOT;|' "$v/project.pbxproj"; printf 'x\n' > "$w/README.txt"
refused escaping_reference --project "$v" --target App
v="$(variant stray-product)"; sed -i '' 's|productName = LibThing; productReference = F0000000000000000000001A;|productName = LibThing;|' "$v/project.pbxproj"
refused built_reference_not_a_product --project "$v" --target App

echo "== exporter: model_classified_not_compiled, repeat_without_timestamp"
if export_ "$P" "App;Lib Thing" "APP;LIB__THING" "$w/out1"; then
  g1="$(cat "$w/result")"
  case "$g1" in "$w/out1"/*) ;; *) bad "exporter: '$g1' is not under OUTPUT_DIR" ;; esac
  entries "$g1" APP_SOURCES > "$w/g-app"
  [ "$(wc -l < "$w/g-app" | tr -d ' ')" = 6 ] || bad "exporter: APP_SOURCES is not the 6 code entries: $(cat "$w/g-app")"
  grep -q xcdatamodeld "$w/g-app" && bad "exporter: the model is in APP_SOURCES"
  [ "$(entries "$g1" APP_MODELS)" = Model.xcdatamodeld ] || bad "exporter: APP_MODELS is not the model"
  grep -qxF "Sources/With Space/Spaced.m" "$w/g-app" || bad "exporter: the spaced path did not survive"
  [ "$(grep -cxF Shared/util.c "$w/g-app")" = 2 ] || bad "exporter: the duplicate reference was collapsed"
  [ "$(entries "$g1" LIB__THING_SOURCES)" = Lib/lib.m ] || bad "exporter: LIB__THING_SOURCES"
  entries "$g1" APP_RESOURCES > "$w/g-res"
  grep -qxF Resources/fr.lproj/Main.xib "$w/g-res" || bad "exporter: a variant resource is missing: $(cat "$w/g-res")"
  grep -qxF libLibThing.a "$w/g-res" && bad "exporter: a built product is listed as a source-tree resource"
  [ "$(entries "$g1" APP_PRODUCT_RESOURCES)" = libLibThing.a ] || bad "exporter: APP_PRODUCT_RESOURCES is not the Lib product"
  export_ "$P" "App;Lib Thing" "APP;LIB__THING" "$w/out2" || bad "exporter: the second export failed: $(cat "$w/export.log")"
  cmp -s "$g1" "$(cat "$w/result")" || bad "exporter: two exports of the same inputs differ"
  grep -Eq '20[0-9][0-9]-[0-9]' "$g1" && bad "exporter: the generated file carries a date"

  echo "== same_input_reconfigure"
  before="$(ls -l "$g1")"
  export_ "$P" "App;Lib Thing" "APP;LIB__THING" "$w/out1" || bad "reconfigure: $(cat "$w/export.log")"
  [ "$(cat "$w/result")" = "$g1" ] || bad "reconfigure: another file for the same inputs"
  [ "$(ls -l "$g1")" = "$before" ] || bad "reconfigure: the generated file was rewritten"

  echo "== tampered_export_cache"
  printf 'set(APP_SOURCES evil.m)\n' >> "$g1"
  if export_ "$P" "App;Lib Thing" "APP;LIB__THING" "$w/out1"; then bad "tampered: a changed export was accepted"; fi
  grep -q 'mavericks_export_xcode_sources' "$w/export.log" || bad "tampered: refused without naming the function"
  tail -1 "$g1" | grep -q evil.m || bad "tampered: the export was overwritten instead of refused"
else
  bad "exporter failed on the fixture: $(cat "$w/export.log")"
fi

echo "== wrong_prefix, unknown_target"
if export_ "$P" "App;Lib Thing" "APPLICATION;LIB__THING" "$w/out3"; then bad "exporter: a prefix the exporter does not use was accepted"; fi
if export_ "$P" "Lib Thing" "LIBRARY" "$w/out3b"; then
  [ "$(entries "$(cat "$w/result")" LIBRARY_SOURCES)" = Lib/lib.m ] || bad "exporter: a lone target's sources did not take its prefix"
else
  bad "exporter: a lone target failed: $(cat "$w/export.log")"
fi
if export_ "$P" "Nope" "NOPE" "$w/out4"; then bad "exporter: an unknown target was accepted"; fi
if export_ "$P" "App;Lib Thing" "APP" "$w/out5"; then bad "exporter: unequal TARGETS and PREFIXES were accepted"; fi

echo "== cmake_path_injection"
v="$(variant inject)"
mv "$w/inject/Sources/With Space/Spaced.m" "$w/inject/Sources/With Space/x) file(WRITE pwned x) set(y.m"
sed -i '' 's|path = "With Space/Spaced.m";|path = "With Space/x) file(WRITE pwned x) set(y.m";|' "$v/project.pbxproj"
if export_ "$v" "App" "APP" "$w/out6"; then bad "injection: a path with CMake syntax was accepted"; fi
[ ! -e "$w/pwned" ] && [ ! -e "$w/inject/pwned" ] || bad "injection: the injected command ran"
[ -z "$(find "$w/out6" -name sources.cmake 2>/dev/null)" ] || bad "injection: a generated file was published"

echo "== four_production_targets (pinned iTerm2 3.0.15)"
if sh "$root/scripts/fetch_pinned_source.sh" https://github.com/gnachman/iTerm2 687aedf89cc860e273e16309b4b902a533d047db \
     49474361d457b6550d45ccfc602f32d384e38ef3d6a734d74a145831c72bef15 "$w/iterm2" > "$w/fetch.log" 2>&1; then
  IP="$w/iterm2/iTerm2.xcodeproj"
  if export_ "$IP" "iTerm2;iTerm2Shared;image_decoder;SSKeychain" "ITERM2;ITERM2_SHARED;IMAGE_DECODER;SSKEYCHAIN" "$w/out-it"; then
    g="$(cat "$w/result")"
    n() { entries "$g" "$1" | wc -l | tr -d ' '; }
    got="$(n ITERM2_SOURCES)/$(n ITERM2_MODELS) $(n ITERM2_SHARED_SOURCES) $(n IMAGE_DECODER_SOURCES) $(n SSKEYCHAIN_SOURCES)"
    [ "$got" = "2/1 359 2 2" ] || bad "iTerm2: source-phase entries are '$got', want '2/1 359 2 2' (365 code + 1 model)"
  else
    bad "iTerm2: export failed: $(cat "$w/export.log")"
  fi
else
  unmet "the pinned iTerm2 source could not be fetched: $(tail -2 "$w/fetch.log")"
fi

[ "$fail" -eq 0 ] && echo "xcode-inputs-test: OK"
exit "$fail"
