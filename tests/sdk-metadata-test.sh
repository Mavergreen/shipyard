#!/bin/sh
# platform: host-agnostic
# usage: sh tests/sdk-metadata-test.sh
#        mavergreen_materialize_sdk_metadata against a synthetic SDK: exact edits, aliases, paths with
#        spaces, and every refusal leaving the SDK unchanged and nothing published.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
fx="$here/fixtures/sdk-metadata"
SC="${CMAKE:-$(command -v shipyard-cmake || command -v cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)}"
[ -x "$SC" ] || command -v "$SC" >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/sdk metadata test.XXXXXX")"
trap 'chmod -R u+w "$w" 2>/dev/null; rm -rf "$w"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

FW=System/Library/Frameworks/Foundation.framework
CANON="$FW/Versions/C/Headers/NSArray.h"
ALIAS="$FW/Headers/NSArray.h"
PIN=fcf88ce8ff0dd3248b97f4eb81c7909f2cc786725de277f4d05a2b935cc49de0
sha() { "$SC" -E sha256sum "$1" | awk '{print $1}'; }

mksdk() {
  mkdir -p "$1/MacOSX10.9.sdk/$FW/Versions/C/Headers"
  cp "$fx/NSArray.h" "$1/MacOSX10.9.sdk/$CANON"
  ln -s C "$1/MacOSX10.9.sdk/$FW/Versions/Current"
  ln -s Versions/Current/Headers "$1/MacOSX10.9.sdk/$FW/Headers"
  printf '%s/MacOSX10.9.sdk\n' "$1"
}
HSHA="$(sha "$fx/NSArray.h")"
R1='{"old":"@interface NSArray : NSObject","new":"@interface NSArray<__covariant ObjectType> : NSObject"}'
R2='{"old":"@interface NSMutableArray : NSArray","new":"@interface NSMutableArray<ObjectType> : NSArray<ObjectType>"}'
recipe() {
  printf '{"id":"%s","header":"%s","sha256":"%s","aliases":[%s],"replacements":[%s]}' "$1" "$2" "$3" "$4" "$5"
}
GOOD="$(recipe arr-v1 "$CANON" "$HSHA" "\"$ALIAS\"" "$R1,$R2")"
recipes() {
  printf '{"schema":%s,"sdk":"MacOSX10.9","sdk_archive_sha256":"%s","recipes":[%s]}\n' "${SCHEMA:-1}" "${ASHA:-$PIN}" "$1" > "$2"
}

run() {
  "$SC" -DMODULE_DIR="$root" -DSDK="$1" -DRECIPES="$2" -DIDS="$3" -DOUTPUT_DIR="$4" -DRESULT="$w/result" \
    -P "$fx/materialize.cmake" > "$w/log" 2>&1
}
lookup() {
  "$SC" -DOVERLAY="$1" -DNAME="$2" -P "$fx/vfs-lookup.cmake" 2>/dev/null
}

ok_case() {
  name="$1" base="$2"
  sdk="$(mksdk "$base/sdk")"
  recipes "$GOOD" "$base/recipes.json"
  out="$base/scratch/out"
  mkdir -p "$base/scratch"
  if ! run "$sdk" "$base/recipes.json" arr-v1 "$out"; then
    bad "$name: materialize failed: $(cat "$w/log")"; return
  fi
  ov="$(cat "$w/result")"
  case "$ov" in "$out"/*) ;; *) bad "$name: the overlay '$ov' is not inside OUTPUT_DIR '$out'" ;; esac
  [ -f "$ov" ] || { bad "$name: no overlay file at $ov"; return; }
  c="$(lookup "$ov" "$sdk/$CANON")" || { bad "$name: the overlay does not map the canonical header"; return; }
  a="$(lookup "$ov" "$sdk/$ALIAS")" || { bad "$name: the overlay does not map the alias"; return; }
  [ "$c" = "$a" ] || bad "$name: canonical and alias map to different files: $c vs $a"
  case "$c" in "$out"/*) ;; *) bad "$name: external contents '$c' are outside OUTPUT_DIR" ;; esac
  cmp -s "$c" "$fx/NSArray.expected.h" || bad "$name: the generated header is not the SDK's text with exactly the two edits"
  cmp -s "$sdk/$CANON" "$fx/NSArray.h" || bad "$name: the SDK header changed"
  left="$(cd "$base/scratch" && ls -A)"
  [ "$left" = out ] || bad "$name: OUTPUT_DIR's parent holds more than out: $left"
}

echo "== exact_two_edits, canonical_and_alias"
ok_case exact_two_edits "$w/plain"
echo "== spaces_in_paths"
ok_case spaces_in_paths "$w/with space/and more"

refuse_case() {
  name="$1" base="$2" ids="$3" out="${4:-$2/scratch/out}"
  sdk="$base/sdk/MacOSX10.9.sdk"
  before="$(sha "$sdk/$CANON")"
  if run "$sdk" "$base/recipes.json" "$ids" "$out"; then
    bad "$name: materialize succeeded but should have refused"
  fi
  grep -q 'mavergreen_materialize_sdk_metadata' "$w/log" || bad "$name: refused without naming the function: $(cat "$w/log")"
  [ "$(sha "$sdk/$CANON")" = "$before" ] || bad "$name: the SDK header changed"
  if [ "$out" = "$base/scratch/out" ]; then
    left="$(cd "$base/scratch" && ls -A)"
    [ "$left" = "${KEEP:-}" ] || bad "$name: a refusal left output behind: $left"
  fi
}
setup() {
  base="$w/$1"
  mksdk "$base/sdk" >/dev/null
  mkdir -p "$base/scratch"
  recipes "$2" "$base/recipes.json"
  printf '%s\n' "$base"
}

echo "== wrong_hash"
refuse_case wrong_hash "$(setup wrong_hash "$(recipe arr-v1 "$CANON" "$PIN" "\"$ALIAS\"" "$R1,$R2")")" arr-v1
echo "== wrong_schema"
b="$(SCHEMA=2 setup wrong_schema "$GOOD")"; refuse_case wrong_schema "$b" arr-v1
echo "== wrong_sdk_archive"
b="$(ASHA="$HSHA" setup wrong_sdk_archive "$GOOD")"; refuse_case wrong_sdk_archive "$b" arr-v1
echo "== wrong_sdk_name"
b="$(setup wrong_sdk_name "$GOOD")"; mv "$b/sdk/MacOSX10.9.sdk" "$b/sdk/MacOSX10.10.sdk"
ln -s MacOSX10.10.sdk "$b/sdk/MacOSX10.9.sdk"
refuse_case wrong_sdk_name "$b" arr-v1
echo "== unknown_id"
refuse_case unknown_id "$(setup unknown_id "$GOOD")" nope-v1
echo "== zero_or_duplicate_match"
refuse_case zero_match "$(setup zero_match "$(recipe arr-v1 "$CANON" "$HSHA" "" '{"old":"@interface NSSet : NSObject","new":"x"}')")" arr-v1
refuse_case duplicate_match "$(setup duplicate_match "$(recipe arr-v1 "$CANON" "$HSHA" "" '{"old":"@end","new":"@end "}')")" arr-v1
echo "== duplicate_id_or_overlapping_header_recipe"
refuse_case duplicate_selected_id "$(setup duplicate_selected_id "$GOOD")" "arr-v1;arr-v1"
refuse_case duplicate_recipe_id "$(setup duplicate_recipe_id "$GOOD,$GOOD")" arr-v1
refuse_case overlapping_header "$(setup overlapping_header "$GOOD,$(recipe arr2-v1 "$ALIAS" "$HSHA" "" "$R2")")" "arr-v1;arr2-v1"
echo "== escaping_header_alias"
b="$(setup escaping_alias "$(recipe arr-v1 "$CANON" "$HSHA" '"System/Escape/NSArray.h"' "$R1")")"
mkdir -p "$b/outside" "$b/sdk/MacOSX10.9.sdk/System/Escape"; cp "$fx/NSArray.h" "$b/outside/NSArray.h"
ln -s "$b/outside/NSArray.h" "$b/sdk/MacOSX10.9.sdk/System/Escape/NSArray.h"
refuse_case escaping_alias "$b" arr-v1
b="$(setup escaping_header "$(recipe arr-v1 System/Escape/NSArray.h "$HSHA" "" "$R1")")"
mkdir -p "$b/outside" "$b/sdk/MacOSX10.9.sdk/System/Escape"; cp "$fx/NSArray.h" "$b/outside/NSArray.h"
ln -s "$b/outside/NSArray.h" "$b/sdk/MacOSX10.9.sdk/System/Escape/NSArray.h"
refuse_case escaping_header "$b" arr-v1
refuse_case dotdot_alias "$(setup dotdot_alias "$(recipe arr-v1 "$CANON" "$HSHA" "\"$FW/../Foundation.framework/Headers/NSArray.h\"" "$R1")")" arr-v1
refuse_case unrelated_alias "$(setup unrelated_alias "$(recipe arr-v1 "$CANON" "$HSHA" '"System/Library/Frameworks"' "$R1")")" arr-v1
b="$(setup other_file_alias "$(recipe arr-v1 "$CANON" "$HSHA" "\"$FW/Versions/C/Headers/NSOther.h\"" "$R1")")"
cp "$fx/NSArray.h" "$b/sdk/MacOSX10.9.sdk/$FW/Versions/C/Headers/NSOther.h"
refuse_case other_file_alias "$b" arr-v1
grep -q 'not to the header' "$w/log" || bad "other_file_alias: refused for another reason: $(cat "$w/log")"
echo "== escaping_output_parent"
b="$(setup escaping_output_parent "$GOOD")"
ln -s "sdk/MacOSX10.9.sdk/System" "$b/into-sdk"
refuse_case escaping_output_parent "$b" arr-v1 "$b/into-sdk/out"
[ ! -e "$b/sdk/MacOSX10.9.sdk/System/out" ] || bad "escaping_output_parent: output was written into the SDK"
echo "== existing_output_refused"
b="$(setup existing_output "$GOOD")"; mkdir "$b/scratch/out"; : > "$b/scratch/out/keep"
KEEP=out
refuse_case existing_output "$b" arr-v1 "$b/scratch/out"
KEEP=
[ "$(ls -A "$b/scratch/out")" = keep ] || bad "existing_output: the existing directory was changed"
refuse_case relative_output "$(setup relative_output "$GOOD")" arr-v1 relative/out
echo "== failure_no_partial_output"
refuse_case failure_no_partial_output "$(setup partial "$GOOD,$(recipe set-v1 "$FW/Versions/C/Headers/NSSet.h" "$HSHA" "" "$R1")")" "arr-v1;set-v1"

echo "== replacements_see_only_sdk_text"
refuse_case chained_replacement "$(setup chained "$(recipe arr-v1 "$CANON" "$HSHA" "" '{"old":"@class NSString;","new":"@class NSString; QQQ"},{"old":"QQQ","new":"ZZZ"}')")" arr-v1
grep -q "'QQQ' does not occur" "$w/log" || bad "chained_replacement: refused for another reason: $(cat "$w/log")"
refuse_case overlapping_replacements "$(setup overlapping "$(recipe arr-v1 "$CANON" "$HSHA" "" "$R1"',{"old":"NSObject <NSCopying>","new":"NSObject"}')")" arr-v1
grep -q 'overlap' "$w/log" || bad "overlapping_replacements: refused for another reason: $(cat "$w/log")"

echo "== reuse_rechecks_sdk"
b="$(setup reuse "$GOOD")"
gen() {
  "$SC" -DMODULE_DIR="$root" -DSDK="$b/sdk/MacOSX10.9.sdk" -DRECIPES="$b/recipes.json" -DIDS=arr-v1 \
    -DOUTPUT_DIR="$b/scratch/gens" -DRESULT="$w/result" -P "$fx/generation.cmake" > "$w/log" 2>&1
}
if gen; then
  first="$(cat "$w/result")"
  gen && [ "$(cat "$w/result")" = "$first" ] || bad "reuse: the same inputs did not reuse the generation: $(cat "$w/log")"
  chmod u+w "$b/sdk/MacOSX10.9.sdk/$CANON"
  printf '@interface NSSwapped : NSObject\n@end\n' >> "$b/sdk/MacOSX10.9.sdk/$CANON"
  if gen; then bad "reuse: a generation was reused after the SDK's header changed"; fi
  grep -q 'SHA-256' "$w/log" || bad "reuse: refused for another reason: $(cat "$w/log")"
  cmp -s "$(dirname "$first")/headers/$CANON" "$fx/NSArray.expected.h" || bad "reuse: the refused generation was changed"
else
  bad "reuse: the first generation failed: $(cat "$w/log")"
fi

[ "$fail" -eq 0 ] && echo "sdk-metadata-test: OK"
exit "$fail"
