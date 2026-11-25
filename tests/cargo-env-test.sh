#!/bin/sh
# platform: host-agnostic
#   usage: cargo-env-test.sh
#          --arch arm64 scopes everything to aarch64-apple-darwin (11.0, the 11.3 SDK, no SDKROOT) and needs
#          an aarch64 std in the rust; --arch x86_64 prints exactly what no --arch does; other arches exit 2.
#          cargo-env.sh prints, for a cargo build targeting 10.9 x86_64, the pinned toolchain, clang22 as
#          linker and as the cc crate's compiler and archiver, the SDK and its floor, and clang22's llvm-
#          tools for every Mach-O tool variable, never a host tool; --sh output evals to the same values;
#          the pins are fetched through fetch_rust.sh and fetch_clang22.sh; a missing tool, a host with no
#          cc and a path with whitespace are refused.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
E="$here/../scripts/cargo-env.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/cargo-env.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: cargo-env: $1"; [ ! -f "$w/out" ] || cat "$w/out"; exit 1; }
mkdir -p "$w/rust/bin" "$w/cl/bin" "$w/sdk/usr/include" "$w/pins/rust" "$w/pins/clang22"
for t in cargo rustc rustdoc; do printf '#!/bin/sh\n' > "$w/rust/bin/$t"; chmod +x "$w/rust/bin/$t"; done
for t in clang clang++ llvm-ar llvm-ranlib llvm-lipo llvm-otool llvm-nm llvm-strip llvm-install-name-tool llvm-strings ld64.lld; do
  printf '#!/bin/sh\n' > "$w/cl/bin/$t"; chmod +x "$w/cl/bin/$t"
done
printf '1.99.1-mavericks.99\n' > "$w/pins/rust/version"
printf '22.1.8-mavericks.99\n' > "$w/pins/clang22/version"
want() {
  grep -qxF "$1" "$w/out" || fail "no line $1"
}
CARGO_ENV_HOST=Linux sh "$E" --rust "$w/rust" --clang22 "$w/cl" --sdk "$w/sdk" "$w/pins/rust" > "$w/out" || fail "a complete toolchain is accepted"
want "CARGO=$w/rust/bin/cargo"
want "RUSTC=$w/rust/bin/rustc"
want "RUSTDOC=$w/rust/bin/rustdoc"
want "CARGO_BUILD_TARGET=x86_64-apple-darwin"
want "CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER=$w/cl/bin/clang++"
want "CC_x86_64_apple_darwin=$w/cl/bin/clang"
want "CXX_x86_64_apple_darwin=$w/cl/bin/clang++"
want "AR_x86_64_apple_darwin=$w/cl/bin/llvm-ar"
want "RANLIB_x86_64_apple_darwin=$w/cl/bin/llvm-ranlib"
want "SDKROOT=$w/sdk"
want "MACOSX_DEPLOYMENT_TARGET=10.9"
for p in LIPO=llvm-lipo OTOOL=llvm-otool NM=llvm-nm AR=llvm-ar STRIP=llvm-strip INSTALL_NAME_TOOL=llvm-install-name-tool STRINGS=llvm-strings; do
  want "${p%%=*}=$w/cl/bin/${p#*=}"
done
if grep -q '^RUSTFLAGS=\|^CC=\|^CXX=' "$w/out"; then fail "nothing that would reach the host's own build is set"; fi
n="$(grep -c . "$w/out")"

CARGO_ENV_HOST=Linux sh "$E" --sh --rust "$w/rust" --clang22 "$w/cl" --sdk "$w/sdk" "$w/pins/rust" > "$w/sh" || fail "--sh is accepted"
[ "$(grep -c '^export [A-Za-z_0-9]*=' "$w/sh")" = "$n" ] || fail "--sh prints one export per line"
( eval "$(cat "$w/sh")"
  [ "$CC_x86_64_apple_darwin" = "$w/cl/bin/clang" ] && [ "$SDKROOT" = "$w/sdk" ] && [ "$MACOSX_DEPLOYMENT_TARGET" = 10.9 ] ) \
  || fail "--sh evals to the same values"

CARGO_ENV_HOST=Linux sh "$E" --rust "$w/rust" --clang22 "$w/cl" --sdk "$w/sdk" "$w/pins/rust" > "$w/out" || fail "x86_64 default"
cp "$w/out" "$w/default"
CARGO_ENV_HOST=Linux sh "$E" --arch x86_64 --rust "$w/rust" --clang22 "$w/cl" --sdk "$w/sdk" "$w/pins/rust" > "$w/out" || fail "--arch x86_64 is accepted"
cmp -s "$w/default" "$w/out" || fail "--arch x86_64 output is byte-identical to no --arch"
rc=0; CARGO_ENV_HOST=Linux sh "$E" --arch i386 --rust "$w/rust" --clang22 "$w/cl" --sdk "$w/sdk" "$w/pins/rust" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "--arch i386 is a usage error (exit 2, got $rc)"
rc=0; CARGO_ENV_HOST=Linux sh "$E" --arch --rust "$w/rust" "$w/pins/rust" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "--arch with no value is a usage error"

if CARGO_ENV_HOST=Linux sh "$E" --arch arm64 --rust "$w/rust" --clang22 "$w/cl" --sdk "$w/sdk" "$w/pins/rust" > "$w/out" 2>&1; then
  fail "a rust with no aarch64 std is refused for arm64"
fi
grep -q 'aarch64-apple-darwin' "$w/out" || fail "the refusal names aarch64-apple-darwin"
mkdir -p "$w/rust/lib/rustlib/aarch64-apple-darwin"
CARGO_ENV_HOST=Linux sh "$E" --arch arm64 --rust "$w/rust" --clang22 "$w/cl" --sdk "$w/sdk" "$w/pins/rust" > "$w/out" || fail "--arch arm64 is accepted"
want "CARGO_BUILD_TARGET=aarch64-apple-darwin"
want "MACOSX_DEPLOYMENT_TARGET=11.0"
want "CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER=$w/cl/bin/clang++"
want "CC_aarch64_apple_darwin=$w/cl/bin/clang"
want "CXX_aarch64_apple_darwin=$w/cl/bin/clang++"
want "AR_aarch64_apple_darwin=$w/cl/bin/llvm-ar"
want "RANLIB_aarch64_apple_darwin=$w/cl/bin/llvm-ranlib"
want "CFLAGS_aarch64_apple_darwin=--no-default-config --target=arm64-apple-macos11.0 -isysroot $w/sdk"
want "CXXFLAGS_aarch64_apple_darwin=--no-default-config --target=arm64-apple-macos11.0 -isysroot $w/sdk -nostdinc++ -isystem $w/sdk/usr/include/c++/v1"
want "CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS=-C link-arg=--no-default-config -C link-arg=--target=arm64-apple-macos11.0 -C link-arg=-fuse-ld=lld -C link-arg=-isysroot -C link-arg=$w/sdk"
for p in LIPO=llvm-lipo OTOOL=llvm-otool NM=llvm-nm AR=llvm-ar STRIP=llvm-strip INSTALL_NAME_TOOL=llvm-install-name-tool STRINGS=llvm-strings; do
  want "${p%%=*}=$w/cl/bin/${p#*=}"
done
if grep -q '^SDKROOT=\|x86_64\|X86_64\|=10\.9' "$w/out"; then fail "arm64 sets no SDKROOT and nothing of the x86_64 target"; fi
CARGO_ENV_HOST=Linux sh "$E" --sh --arch arm64 --rust "$w/rust" --clang22 "$w/cl" --sdk "$w/sdk" "$w/pins/rust" > "$w/sh" || fail "--sh --arch arm64"
( eval "$(cat "$w/sh")"
  [ "$CFLAGS_aarch64_apple_darwin" = "--no-default-config --target=arm64-apple-macos11.0 -isysroot $w/sdk" ] \
    && [ "$CXXFLAGS_aarch64_apple_darwin" = "--no-default-config --target=arm64-apple-macos11.0 -isysroot $w/sdk -nostdinc++ -isystem $w/sdk/usr/include/c++/v1" ] \
    && [ "${SDKROOT:-unset}" = unset ] && [ "$MACOSX_DEPLOYMENT_TARGET" = 11.0 ] ) || fail "--sh arm64 evals to the same values"

sdkdir="$(sh -c '. "$1/sdk-pins.sh"; set -- $(shipyard_sdk_pin arm64); echo "$4"' x "$here/../scripts")"
mkdir -p "$w/cache/$sdkdir/usr/lib" "$w/cache/$sdkdir/usr/include"
CARGO_ENV_HOST=Linux MAVERICKS_SDK_CACHE="$w/cache" sh "$E" --arch arm64 --rust "$w/rust" --clang22 "$w/cl" "$w/pins/rust" > "$w/out" || fail "the arm64 SDK is fetched"
want "CFLAGS_aarch64_apple_darwin=--no-default-config --target=arm64-apple-macos11.0 -isysroot $w/cache/$sdkdir"
[ "$(MAVERICKS_SDK_CACHE="$w/cache" sh "$here/../scripts/fetch_sdk.sh" --arch arm64)" = "$w/cache/$sdkdir" ] || fail "the SDK is fetch_sdk.sh --arch arm64's"

mkdir -p "$w/inst/rust/bin"; cp "$w/rust/bin/"* "$w/inst/rust/bin/"
printf '<plist><dict>\n<key>version</key>\n<string>1.99.1-mavericks.99</string>\n</dict></plist>\n' > "$w/inst/rust/mavergreen.plist"
mkdir -p "$w/inst/clang22"; cp -R "$w/cl/bin" "$w/inst/clang22/"
printf '<plist><dict>\n<key>version</key>\n<string>22.1.8-mavericks.99</string>\n</dict></plist>\n' > "$w/inst/clang22/mavergreen.plist"
RUST_INSTALLED="$w/inst/rust" CLANG22_INSTALLED="$w/inst/clang22" CLANG22_HOST=linux RUST_HOST=linux CARGO_ENV_HOST=Linux \
  sh "$E" --sdk "$w/sdk" "$w/pins/rust" "$w/pins/clang22" > "$w/out" || fail "the pinned rust and clang22 are fetched"
want "RUSTC=$w/inst/rust/bin/rustc"
want "CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER=$w/inst/clang22/bin/clang++"

rm "$w/cl/bin/llvm-ar"
if CARGO_ENV_HOST=Linux sh "$E" --rust "$w/rust" --clang22 "$w/cl" --sdk "$w/sdk" "$w/pins/rust" > "$w/out" 2>&1; then
  fail "a clang22 with no llvm-ar is refused"
fi
grep -q 'llvm-ar' "$w/out" || fail "the refusal names llvm-ar"
printf '#!/bin/sh\n' > "$w/cl/bin/llvm-ar"; chmod +x "$w/cl/bin/llvm-ar"

mkdir -p "$w/nocc"
for d in $(printf '%s' "$PATH" | tr ':' ' '); do
  for f in "$d"/*; do
    b="${f##*/}"
    [ "$b" != cc ] && [ -x "$f" ] && [ ! -e "$w/nocc/$b" ] && ln -s "$f" "$w/nocc/$b" || :
  done
done
if PATH="$w/nocc" CARGO_ENV_HOST=Linux sh "$E" --rust "$w/rust" --clang22 "$w/cl" --sdk "$w/sdk" "$w/pins/rust" > "$w/out" 2>&1; then
  fail "a Linux host with no cc is refused"
fi
grep -q 'no cc' "$w/out" || fail "the refusal names cc"
PATH="$w/nocc" CARGO_ENV_HOST=Darwin sh "$E" --rust "$w/rust" --clang22 "$w/cl" --sdk "$w/sdk" "$w/pins/rust" > "$w/out" 2>&1 \
  || fail "a Mac links its build scripts with the target's linker, so needs no cc"

mkdir -p "$w/a b/usr/include"
if CARGO_ENV_HOST=Linux sh "$E" --rust "$w/rust" --clang22 "$w/cl" --sdk "$w/a b" "$w/pins/rust" > "$w/out" 2>&1; then
  fail "an SDK path with whitespace is refused"
fi
if sh "$E" > /dev/null 2>&1; then fail "no pin is a usage error"; fi
rc=0; sh "$E" --bogus "$w/pins/rust" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "an unknown option is a usage error (exit 2, got $rc)"
echo "PASS: cargo-env"
