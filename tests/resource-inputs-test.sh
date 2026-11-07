#!/bin/sh
# platform: macOS-only -- builds and runs the libarchive-based extractor against zip archives made here
# usage: sh tests/resource-inputs-test.sh
#        mavericks-resource-extract and mavericks_extract_resource_members: a selected subset with spaces
#        comes out byte-exact and mode 0644 with nothing else; a wrong archive or member hash, size,
#        version, a missing, duplicated, directory or symlink member, an unsafe path, an oversized,
#        truncated or encrypted member, and an output path that escapes are each refused, publishing
#        nothing and leaving everything outside untouched. With SHIPYARD_ON_TARGET=1 it also extracts
#        the 31 members of the pinned iTerm2 3.0.15 release (a download). MAVERICKS_HOST_TOOLS_CC names
#        the compiler (default: clang-22 on 10.9, clang-22-cross on a modern Mac).
set -eu
# platform: sort orders by the locale's collation, which ignores case in modern macOS's en_US.UTF-8 and
#           compares bytes on 10.9, so the expected listings are compared in the C locale
LC_ALL=C
export LC_ALL
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
fx="$here/fixtures/resource-inputs"
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
command -v zip >/dev/null 2>&1 || unmet "no zip to make the fixture archives"

_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/resource inputs.XXXXXX")"
trap 'chmod -R u+w "$w" 2>/dev/null; rm -rf "$w"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
sha() { "$SC" -E sha256sum "$1" | awk '{print $1}'; }
size() { wc -c < "$1" | tr -d ' '; }

"$SC" -DMODULE_DIR="$root" -DCOMPILER="$CC" -DROOT="$w/ht" -DRESULT="$w/bin" -P "$here/fixtures/xcode-inputs/tools.cmake" \
  > "$w/tools.log" 2>&1 || { cat "$w/tools.log"; echo "FAIL: the host tools did not build"; exit 1; }
X="$(cat "$w/bin")/mavericks-resource-extract"
[ -x "$X" ] || { echo "FAIL: no mavericks-resource-extract in $(cat "$w/bin")"; exit 1; }

R="$w/tree/My App.app/Contents/Resources"
mkdir -p "$R/en.lproj" "$w/tree/My App.app/Contents/MacOS"
printf 'main nib bytes\n' > "$R/Main Menu.nib"
printf 'about\n' > "$R/en.lproj/About.nib"
printf 'not selected\n' > "$R/Other.txt"
printf '#!/bin/sh\necho ran > "%s/ran"\n' "$w" > "$w/tree/My App.app/Contents/MacOS/My App"
chmod 755 "$w/tree/My App.app/Contents/MacOS/My App"
cat > "$w/tree/My App.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>3.0.15</string>
<key>CFBundleVersion</key><string>3.0.15</string>
</dict></plist>
EOF
ln -s "Main Menu.nib" "$R/Link.nib"
mkzip() { (cd "$w/tree" && rm -f "$1" && zip -qry "$1" "My App.app"); }
mkzip "$w/app.zip"
ZSHA="$(sha "$w/app.zip")"
PREFIX="My App.app/Contents/Resources/"
VER="My App.app/Contents/Info.plist"
manifest() {
  mf="$1"; shift
  printf 'member\tdestination\tkind\tbytes\tsha256\n' > "$mf"
  for m in "$@"; do
    printf '%s\t%s\tfile\t%s\t%s\n' "$m" "$m" "$(size "$R/$m")" "$(sha "$R/$m")" >> "$mf"
  done
}
manifest "$w/good.tsv" "Main Menu.nib" "en.lproj/About.nib"
defaults() { ARCHIVE="$w/app.zip"; ASHA="$ZSHA"; MAN="$w/good.tsv"; EXPECT=3.0.15; KEEP=; WHY=; }
run() {
  "$X" --archive "$ARCHIVE" --sha256 "$ASHA" --manifest "$MAN" --prefix "$PREFIX" \
    --version-member "$VER" --expect-version "$EXPECT" --outdir "$1" > "$w/run.log" 2>&1
}
defaults
: > "$w/sentinel"

echo "== valid_subset_with_spaces"
if run "$w/out-good"; then
  cmp -s "$w/out-good/Main Menu.nib" "$R/Main Menu.nib" || bad "valid: Main Menu.nib differs"
  cmp -s "$w/out-good/en.lproj/About.nib" "$R/en.lproj/About.nib" || bad "valid: en.lproj/About.nib differs"
  got="$(cd "$w/out-good" && find . -type f | sort | tr '\n' '|')"
  [ "$got" = "./Main Menu.nib|./en.lproj/About.nib|" ] || bad "valid: the output holds $got"
  for f in "Main Menu.nib" en.lproj/About.nib; do
    [ "$(stat -f %Lp "$w/out-good/$f")" = 644 ] || bad "valid: $f is mode $(stat -f %Lp "$w/out-good/$f"), want 644"
  done
  [ ! -e "$w/ran" ] || bad "valid: the archive's executable ran"
else
  bad "valid subset refused: $(cat "$w/run.log")"
fi

refused() {
  name="$1"; shift; out="$w/out-$name"; defaults
  for kv in "$@"; do
    case "$kv" in
      ARCHIVE=*|ASHA=*|MAN=*|EXPECT=*|KEEP=*|WHY=*) eval "${kv%%=*}=\${kv#*=}" ;;
      *) out="$kv" ;;
    esac
  done
  if run "$out"; then bad "$name: accepted"; fi
  grep -qF -- "${WHY:-mavericks-resource-extract:}" "$w/run.log" || bad "$name: refused for another reason than '$WHY': $(cat "$w/run.log")"
  [ ! -e "$out" ] || [ "${KEEP:-}" = 1 ] || bad "$name: left $out behind"
  [ -z "$(find "$(dirname "$out")" -maxdepth 1 -name '.*staging*' 2>/dev/null)" ] || bad "$name: left a staging directory"
  [ -f "$w/sentinel" ] && [ ! -s "$w/sentinel" ] || bad "$name: the outside sentinel changed"
  [ ! -e "$w/ran" ] || bad "$name: the archive's executable ran"
  defaults
}
echo "== wrong_archive_hash"
refused wrong_archive_hash ASHA=0000000000000000000000000000000000000000000000000000000000000000 "WHY=no member was read"
echo "== wrong_member_hash_or_size"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$4=99} {print}' "$w/good.tsv" > "$w/size.tsv"; refused wrong_member_size "MAN=$w/size.tsv" "WHY=the manifest says 99"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$5="1111111111111111111111111111111111111111111111111111111111111111"} {print}' "$w/good.tsv" > "$w/hash.tsv"
refused wrong_member_hash "MAN=$w/hash.tsv" "WHY=has SHA-256"
echo "== oversized_member_stream"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$4=3} {print}' "$w/good.tsv" > "$w/over.tsv"; refused oversized_member_stream "MAN=$w/over.tsv" "WHY=the manifest says 3"
echo "== wrong_version"
refused wrong_version EXPECT=3.0.14 "WHY=not 3.0.14"
echo "== missing_member"
printf 'Missing.nib\tMissing.nib\tfile\t1\t%s\n' "$ZSHA" >> "$(cp "$w/good.tsv" "$w/missing.tsv"; echo "$w/missing.tsv")"
refused missing_member "MAN=$w/missing.tsv" "WHY=the archive has no My App.app/Contents/Resources/Missing.nib"
echo "== duplicate_output_destination"
awk -F'\t' 'BEGIN{OFS="\t"} NR==3{$2="Main Menu.nib"} {print}' "$w/good.tsv" > "$w/dupdest.tsv"; refused duplicate_output_destination "MAN=$w/dupdest.tsv" "WHY=collides with"
awk -F'\t' 'BEGIN{OFS="\t"} NR==3{$2="Main Menu.nib/x"} {print}' "$w/good.tsv" > "$w/nestdest.tsv"; refused nested_output_destination "MAN=$w/nestdest.tsv" "WHY=collides with"
echo "== directory_or_symlink_selected"
printf 'Link.nib\tLink.nib\tfile\t13\t%s\n' "$(sha "$R/Main Menu.nib")" > "$w/link.tsv.body"
{ head -1 "$w/good.tsv"; cat "$w/link.tsv.body"; } > "$w/link.tsv"; refused symlink_selected "MAN=$w/link.tsv"
grep -Eq 'is not a regular file|has SHA-256' "$w/run.log" || bad "symlink_selected: refused for another reason: $(cat "$w/run.log")"
{ head -1 "$w/good.tsv"; printf 'en.lproj\ten.lproj\tfile\t0\t%s\n' "$ZSHA"; } > "$w/dir.tsv"; refused directory_selected "MAN=$w/dir.tsv" "WHY=is not a regular file"
echo "== absolute_dot_segment_paths"
for bad_path in "/etc/passwd" "../Main Menu.nib" "en.lproj/../Main Menu.nib" "./Main Menu.nib" "en.lproj//About.nib"; do
  { head -1 "$w/good.tsv"; printf 'Main Menu.nib\t%s\tfile\t15\t%s\n' "$bad_path" "$(sha "$R/Main Menu.nib")"; } > "$w/path.tsv"
  refused "unsafe_destination_$bad_path" "MAN=$w/path.tsv" "WHY=is not a plain relative path" "$w/out-path"
  { head -1 "$w/good.tsv"; printf '%s\tx.nib\tfile\t15\t%s\n' "$bad_path" "$(sha "$R/Main Menu.nib")"; } > "$w/path.tsv"
  refused "unsafe_member_$bad_path" "MAN=$w/path.tsv" "WHY=is not a plain relative path" "$w/out-path"
done
{ head -1 "$w/good.tsv"; printf 'Main Menu.nib\tMain Menu.nib\tlink\t15\t%s\n' "$(sha "$R/Main Menu.nib")"; } > "$w/kind.tsv"
refused unknown_kind "MAN=$w/kind.tsv" "WHY=is not file"
echo "== executable_member"
mkdir -p "$w/exetree/My App.app/Contents/Resources"
cp "$w/tree/My App.app/Contents/Info.plist" "$w/exetree/My App.app/Contents/"
cp "$X" "$w/exetree/My App.app/Contents/Resources/helper"
(cd "$w/exetree" && zip -qr "$w/exe.zip" "My App.app")
{ head -1 "$w/good.tsv"; printf 'helper\thelper\tfile\t%s\t%s\n' "$(size "$X")" "$(sha "$X")"; } > "$w/exe.tsv"
refused executable_member "ARCHIVE=$w/exe.zip" "ASHA=$(sha "$w/exe.zip")" "MAN=$w/exe.tsv" "WHY=is a Mach-O executable or library"
echo "== duplicate_archive_name"
mkdir -p "$w/duptree/My App.app/Contents/Resources"
cp "$w/tree/My App.app/Contents/Info.plist" "$w/duptree/My App.app/Contents/"
cp "$R/Main Menu.nib" "$w/duptree/My App.app/Contents/Resources/Main Menu.nib"
cp "$R/Main Menu.nib" "$w/duptree/My App.app/Contents/Resources/Main Menx.nib"
(cd "$w/duptree" && zip -qr "$w/dup.zip" "My App.app")
perl -pi -e 's/Main Menx\.nib/Main Menu.nib/g' "$w/dup.zip"
refused duplicate_archive_name "ARCHIVE=$w/dup.zip" "ASHA=$(sha "$w/dup.zip")" "WHY=twice"
echo "== truncated_or_encrypted_archive"
head -c 200 "$w/app.zip" > "$w/trunc.zip"
refused truncated_archive "ARCHIVE=$w/trunc.zip" "ASHA=$(sha "$w/trunc.zip")"
(cd "$w/tree" && rm -f "$w/enc.zip" && zip -qry -P secret "$w/enc.zip" "My App.app")
refused encrypted_archive "ARCHIVE=$w/enc.zip" "ASHA=$(sha "$w/enc.zip")"
echo "== escaping_output_parent, no_partial_publish"
mkdir -p "$w/existing"; : > "$w/existing/keep"
refused existing_output KEEP=1 "WHY=already exists" "$w/existing"
[ "$(ls -A "$w/existing")" = keep ] || bad "existing_output: the existing directory was changed"
ln -s "$w/tree/My App.app/Contents/Resources" "$w/into-tree"
if run "$w/into-tree/out"; then bad "escaping_output_parent: accepted"; fi
[ ! -e "$R/out" ] || bad "escaping_output_parent: wrote into the linked directory"
if run "relative/out"; then bad "relative_output: accepted"; fi

echo "== utf8_names_and_list_separators"
mkdir -p "$w/utftree/My App.app/Contents/Resources"
cp "$w/tree/My App.app/Contents/Info.plist" "$w/utftree/My App.app/Contents/"
U="$w/utftree/My App.app/Contents/Resources"
utf="$(printf 'Pr\303\251f.nib')"
printf 'pref\n' > "$U/$utf"
printf 'semi\n' > "$U/a;b.nib"
(cd "$w/utftree" && zip -qr "$w/utf.zip" "My App.app")
{ head -1 "$w/good.tsv"; printf '%s\t%s\tfile\t%s\t%s\n' "$utf" "$utf" "$(size "$U/$utf")" "$(sha "$U/$utf")"; } > "$w/utf.tsv"
{ head -1 "$w/good.tsv"; printf 'a;b.nib\ta;b.nib\tfile\t5\t%s\n' "$(sha "$U/a;b.nib")"; } > "$w/semi.tsv"
refused list_separator_name "ARCHIVE=$w/utf.zip" "ASHA=$(sha "$w/utf.zip")" "MAN=$w/semi.tsv" "WHY=is not a plain relative path"
utf_ex() {
  "$SC" -DMODULE_DIR="$root" -DCOMPILER="$CC" -DARCHIVE="$w/utf.zip" -DSHA="$(sha "$w/utf.zip")" -DMANIFEST="$w/utf.tsv" \
    "-DPREFIX=$PREFIX" "-DVERSION_MEMBER=$VER" -DEXPECT=3.0.15 -DOUT="$w/res-utf" -DRESULT="$w/result" \
    -P "$fx/extract.cmake" > "$w/ex.log" 2>&1
}
if utf_ex; then
  cmp -s "$(cat "$w/result")/$utf" "$U/$utf" || bad "utf8: the wrapper staged the UTF-8 name wrongly"
  utf_ex || bad "utf8: reusing a UTF-8 name failed: $(cat "$w/ex.log")"
else
  bad "utf8: the wrapper refused a UTF-8 member name: $(cat "$w/ex.log")"
fi

echo "== wrapper: empty_member_prefix"
if "$SC" -DMODULE_DIR="$root" -DCOMPILER="$CC" -DARCHIVE="$w/app.zip" -DSHA="$ZSHA" -DMANIFEST="$w/good.tsv" \
     "-DPREFIX=" "-DVERSION_MEMBER=$VER" -DEXPECT=3.0.15 -DOUT="$w/res-noprefix" -DRESULT="$w/result" \
     -P "$fx/extract.cmake" > "$w/ex.log" 2>&1; then
  bad "wrapper: an empty MEMBER_PREFIX was accepted"
fi
grep -q 'MEMBER_PREFIX must name' "$w/ex.log" || bad "wrapper: empty MEMBER_PREFIX refused for another reason: $(cat "$w/ex.log")"

echo "== wrapper: same_input_reconfigure, tampered_output_refused"
ex() {
  "$SC" -DMODULE_DIR="$root" -DCOMPILER="$CC" -DARCHIVE="$w/app.zip" -DSHA="$ZSHA" -DMANIFEST="$w/good.tsv" \
    "-DPREFIX=$PREFIX" "-DVERSION_MEMBER=$VER" -DEXPECT=3.0.15 -DOUT="$1" -DRESULT="$w/result" \
    -P "$fx/extract.cmake" > "$w/ex.log" 2>&1
}
if ex "$w/res"; then
  d="$(cat "$w/result")"
  case "$d" in "$w/res"/*) ;; *) bad "wrapper: '$d' is not under OUTPUT_DIR" ;; esac
  cmp -s "$d/Main Menu.nib" "$R/Main Menu.nib" || bad "wrapper: Main Menu.nib differs"
  before="$(ls -l "$d/Main Menu.nib")"
  ex "$w/res" || bad "wrapper: reconfigure failed: $(cat "$w/ex.log")"
  [ "$(cat "$w/result")" = "$d" ] || bad "wrapper: another directory for the same inputs"
  [ "$(ls -l "$d/Main Menu.nib")" = "$before" ] || bad "wrapper: the output was rewritten"
  chmod u+w "$d/en.lproj/About.nib"; printf 'tampered\n' >> "$d/en.lproj/About.nib"
  if ex "$w/res"; then bad "wrapper: tampered output accepted"; fi
  grep -q 'mavericks_extract_resource_members' "$w/ex.log" || bad "wrapper: tampered refused without naming the function"
  tail -1 "$d/en.lproj/About.nib" | grep -q tampered || bad "wrapper: the tampered output was overwritten"
else
  bad "wrapper failed: $(cat "$w/ex.log")"
fi

if [ "${SHIPYARD_ON_TARGET:-}" = 1 ]; then
  echo "== pinned iTerm2 3.0.15 release (31 members)"
  . "$root/scripts/mavericks_fetch.sh"
  rc=0
  shipyard_fetch_verified https://iterm2.com/downloads/stable/iTerm2-3_0_15.zip \
    90e6f2bd3eb2d245f4ab2c9f856c627c8a1536bac024fb3989db417bc3147565 "$w/dl" iTerm2-3_0_15.zip > "$w/fetch.log" 2>&1 || rc=$?
  [ "$rc" = 0 ] && [ -f "$w/dl/iTerm2-3_0_15.zip" ] || unmet "the pinned iTerm2 release could not be fetched: $(tail -2 "$w/fetch.log")"
  tail -n +2 "$fx/iterm2-3.0.15.tsv" | cut -f2 | sort > "$w/it-want"
  ARCHIVE="$w/dl/iTerm2-3_0_15.zip"; ASHA=90e6f2bd3eb2d245f4ab2c9f856c627c8a1536bac024fb3989db417bc3147565
  MAN="$fx/iterm2-3.0.15.tsv"; PREFIX="iTerm.app/Contents/Resources/"; VER="iTerm.app/Contents/Info.plist"
  if run "$w/it"; then
    (cd "$w/it" && find . -type f | sed 's|^\./||' | sort) > "$w/it-got"
    cmp -s "$w/it-want" "$w/it-got" || bad "iTerm2: the output is not exactly the 31 selected members"
    [ "$(wc -l < "$w/it-got" | tr -d ' ')" = 31 ] || bad "iTerm2: $(wc -l < "$w/it-got") members, want 31"
    [ -z "$(find "$w/it" -type f -perm -100)" ] || bad "iTerm2: an executable file was staged"
  else
    bad "iTerm2: extraction refused: $(cat "$w/run.log")"
  fi
fi

[ "$fail" -eq 0 ] && echo "resource-inputs-test: OK"
exit "$fail"
