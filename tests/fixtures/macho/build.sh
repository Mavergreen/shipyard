#!/bin/sh
# platform: macOS-only -- compiles with clang-22 against the pinned Apple SDK (scripts/fetch_sdk.sh)
#   usage: build.sh
#          Rebuilds the checked-in Mach-O fixtures beside this script. The tests read the results and
#          never run this, so they need no compiler and no SDK on any host.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$here/../../.."
sdk="$(sh "$root/scripts/fetch_sdk.sh")"
cc="clang-22 -target x86_64-apple-macos10.9 -isysroot $sdk"
w="$(mktemp -d "${TMPDIR:-/tmp}/macho-fixtures.XXXXXX")"
trap 'rm -rf "$w"' EXIT
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
restamp_x86(d + '/clean', d + '/r265', (26, 5))
restamp_x86(d + '/leak', d + '/leak265', (26, 5))
PY
llvm-lipo -create "$here/clean" "$here/a113" -output "$here/fatok"
llvm-lipo -create "$here/clean" "$here/a265" -output "$here/fatbad"
llvm-lipo -create "$here/leak" "$here/a113" -output "$here/fatleak"
llvm-lipo -create "$here/clean" "$here/a130" -output "$here/fat130"
llvm-lipo -create "$here/clean" "$here/a280" -output "$here/fat280"
rm -f "$here/leak265"
