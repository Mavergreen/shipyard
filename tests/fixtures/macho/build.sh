#!/bin/sh
# platform: macOS-only -- compiles with clang-22 against the pinned Apple SDK (scripts/fetch_sdk.sh)
#   usage: build.sh [dbg]
#          Rebuilds the checked-in Mach-O fixtures beside this script. The tests read the results and
#          never run this, so they need no compiler and no SDK on any host. With dbg, rebuilds only dbg,
#          dbgfat, dbghome and their objects in dbg-objs/, which a cross clang-22 on any host can.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$here/../../.."
sdk="$(sh "$root/scripts/fetch_sdk.sh")"
cc="clang-22 -target x86_64-apple-macos10.9 -isysroot $sdk"
w="$(mktemp -d "${TMPDIR:-/tmp}/macho-fixtures.XXXXXX")"
trap 'rm -rf "$w"' EXIT
build_dbg() {
  sdk113="$(sh "$root/scripts/fetch_sdk.sh" --arch arm64)"
  mkdir -p "$here/dbg-objs"
  printf 'static int dbg_helper(int x){return x+1;}\nint main(int c,char**v){(void)v;return dbg_helper(c)-2;}\n' > "$w/dbg.c"
  for a in x86_64 arm64; do
    case "$a" in x86_64) t="-target x86_64-apple-macos10.9 -isysroot $sdk" ;; *) t="-target arm64-apple-macos11.0 -isysroot $sdk113" ;; esac
    (cd "$w" && clang-22 --no-default-config $t -g -O0 -ffile-prefix-map="$w"=. -c dbg.c -o "$here/dbg-objs/dbg-$a.o")
    ZERO_AR_DATE=1 clang-22 --no-default-config $t -fuse-ld=lld "$here/dbg-objs/dbg-$a.o" -Wl,-oso_prefix,"$here/" -o "$w/dbg-$a"
  done
  cp "$w/dbg-x86_64" "$here/dbg"
  printf 'static const char *dbg_where = "/Users/runner/work/x";\nint main(void){return dbg_where[0] == 0;}\n' > "$w/dbghome.c"
  (cd "$w" && clang-22 --no-default-config -target x86_64-apple-macos10.9 -isysroot "$sdk" -g -O0 -ffile-prefix-map="$w"=. -c dbghome.c -o "$here/dbg-objs/dbghome.o")
  ZERO_AR_DATE=1 clang-22 --no-default-config -target x86_64-apple-macos10.9 -isysroot "$sdk" -fuse-ld=lld "$here/dbg-objs/dbghome.o" -Wl,-oso_prefix,"$here/" -o "$here/dbghome"
  llvm-lipo -create "$w/dbg-x86_64" "$w/dbg-arm64" -output "$here/dbgfat"
}
if [ "${1:-}" = dbg ]; then build_dbg; exit 0; fi
printf 'int main(void){return 0;}\n' > "$w/clean.c"
printf 'int mav_test_shim(void){return 0;}\nint main(void){return mav_test_shim();}\n' > "$w/shim.c"
printf 'extern int mav_test_post109(void);\nint main(void){return mav_test_post109();}\n' > "$w/leak.c"
printf '#import <AppKit/AppKit.h>\nint main(void){(void)[NSColor labelColor];return 0;}\n' > "$w/sel_bad.m"
printf '#import <AppKit/AppKit.h>\nint main(void){(void)[NSColor blackColor];return 0;}\n' > "$w/sel_ok.m"
$cc "$w/clean.c" -o "$here/clean"
$cc "$w/shim.c" -o "$here/shim"
$cc -Wl,-undefined,dynamic_lookup "$w/leak.c" -o "$here/leak"
$cc -framework AppKit "$w/sel_bad.m" -o "$here/sel_bad" 2>/dev/null
$cc -framework AppKit "$w/sel_ok.m" -o "$here/sel_ok"
$cc -c "$w/clean.c" -o "$w/m.o"
rm -f "$here/libm.a"
llvm-ar rcs "$here/libm.a" "$w/m.o"
python3 - "$here" <<'PY'
import struct, sys
d = sys.argv[1]
def ver(a, b=0):
    return (a << 16) | (b << 8)
def arm64(path, minos, sdk):
    lc = struct.pack('<IIIIIIII', 0x32, 32, 1, ver(*minos), ver(*sdk), 1, 3, 0x03e80000)
    hdr = struct.pack('<IiiIIIII', 0xfeedfacf, 0x0100000c, 0, 2, 1, len(lc), 0x200085, 0)
    open(path, 'wb').write(hdr + lc + b'\0' * 4064)
def arm64_unversioned(path):
    hdr = struct.pack('<IiiIIIII', 0xfeedfacf, 0x0100000c, 0, 2, 0, 0, 0x200085, 0)
    open(path, 'wb').write(hdr + b'\0' * 4096)
def padded(s, head):
    b = s.encode() + b'\0'
    return b + b'\0' * (-(head + len(b)) % 8)
def x86_64_loader(path):
    dylib = padded('@rpath/libt.dylib', 24)
    rpath = padded('@loader_path/../lib', 12)
    lc = (struct.pack('<IIIIII', 0xc, 24 + len(dylib), 24, 2, 0x10000, 0x10000) + dylib +
          struct.pack('<III', 0x8000001c, 12 + len(rpath), 12) + rpath)
    hdr = struct.pack('<IiiIIIII', 0xfeedfacf, 0x01000007, 3, 2, 2, len(lc), 0x200085, 0)
    open(path, 'wb').write(hdr + lc + b'\0' * 4064)
def x86_64_dylib(path):
    name = padded('@rpath/libw.dylib', 24)
    lc = struct.pack('<IIIIII', 0xd, 24 + len(name), 24, 2, 0x10000, 0x10000) + name
    hdr = struct.pack('<IiiIIIII', 0xfeedfacf, 0x01000007, 3, 6, 1, len(lc), 0x100085, 0)
    open(path, 'wb').write(hdr + lc + b'\0' * 4064)
def x86_64_links(path, dylibs, rpaths):
    lc = b''
    for n in dylibs:
        b = padded(n, 24)
        lc += struct.pack('<IIIIII', 0xc, 24 + len(b), 24, 2, 0x10000, 0x10000) + b
    for r in rpaths:
        b = padded(r, 12)
        lc += struct.pack('<III', 0x8000001c, 12 + len(b), 12) + b
    hdr = struct.pack('<IiiIIIII', 0xfeedfacf, 0x01000007, 3, 2, len(dylibs) + len(rpaths), len(lc), 0x200085, 0)
    open(path, 'wb').write(hdr + lc + b'\0' * 4064)
def uleb(n):
    out = b''
    while True:
        b = n & 0x7f; n >>= 7
        if not n:
            return out + bytes([b])
        out += bytes([b | 0x80])
def seg(name, vmaddr, fileoff, sects=()):
    body = b''.join(struct.pack('<16s16sQQIIIIIIII', sn, name, a, sz, off, 3, 0, 0, 0, 0, 0, 0) for (sn, a, sz, off) in sects)
    return struct.pack('<II16sQQQQiiII', 0x19, 72 + len(body), name, vmaddr, 0x1000, fileoff, 0x1000, 7, 3, len(sects), 0) + body
def x86_64_weakbind(path, names):
    wb = b''
    for i, n in enumerate(names):
        wb += b'\x40' + n.encode() + b'\0' + b'\x51\x71' + uleb(8 * i) + b'\x90'
    wb += b'\0' * (8 - len(wb) % 8)
    lc = (seg(b'__TEXT', 0x100000000, 0, [(b'__text', 0x100000f00, 0x10, 0xf00)]) +
          seg(b'__DATA', 0x100001000, 0x1000, [(b'__data', 0x100001000, 0x100, 0x1000)]) +
          seg(b'__LINKEDIT', 0x100002000, 0x2000) +
          struct.pack('<12I', 0x80000022, 48, 0, 0, 0, 0, 0x2000, len(wb), 0, 0, 0, 0))
    hdr = struct.pack('<IiiIIIII', 0xfeedfacf, 0x01000007, 3, 2, 4, len(lc), 0x200085, 0)
    b = hdr + lc
    b += b'\0' * (0x2000 - len(b)) + wb
    open(path, 'wb').write(b + b'\0' * (0x3000 - len(b)))
def restamp_x86(src, dst, sdk):
    b = bytearray(open(src, 'rb').read())
    off = 32
    for _ in range(struct.unpack_from('<I', b, 16)[0]):
        cmd, size = struct.unpack_from('<II', b, off)
        if cmd == 0x24:
            struct.pack_into('<I', b, off + 12, ver(*sdk))
        off += size
    open(dst, 'wb').write(b)
arm64(d + '/a113', (11, 0), (11, 3))
arm64(d + '/a265', (11, 0), (26, 5))
arm64(d + '/a130', (13, 0), (11, 3))
arm64(d + '/a280', (28, 0), (11, 3))
arm64_unversioned(d + '/a00')
x86_64_loader(d + '/loader')
x86_64_dylib(d + '/libw')
x86_64_links(d + '/cxxloader', ['@rpath/libc++.1.dylib'], ['@loader_path/../../libcxx22/lib', '@loader_path/../lib'])
x86_64_links(d + '/cxxbundled', ['@rpath/libc++.1.dylib'], ['@loader_path/../lib', '@loader_path/../../libcxx22/lib'])
x86_64_links(d + '/cxxabs', ['/opt/mavergreen/libcxx22/lib/libc++.1.dylib'], [])
x86_64_weakbind(d + '/wbsorted', ['__ZTI1A', '__ZTS1A', '__ZTV1A'])
x86_64_weakbind(d + '/wbunsorted', ['__ZTV1A', '__ZTI1A', '__ZTS1A'])
restamp_x86(d + '/clean', d + '/r265', (26, 5))
restamp_x86(d + '/leak', d + '/leak265', (26, 5))
PY
llvm-lipo -create "$here/clean" "$here/a113" -output "$here/fatok"
llvm-lipo -create "$here/clean" "$here/a265" -output "$here/fatbad"
llvm-lipo -create "$here/leak" "$here/a113" -output "$here/fatleak"
llvm-lipo -create "$here/clean" "$here/a130" -output "$here/fat130"
llvm-lipo -create "$here/clean" "$here/a280" -output "$here/fat280"
rm -f "$here/leak265"
build_dbg
