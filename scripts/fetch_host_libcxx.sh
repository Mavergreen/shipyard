#!/bin/sh
# platform: host-agnostic
#   usage: fetch_host_libcxx.sh PIN_DIR CLANG22_PREFIX
#          Prints a prefix holding libc++ and libc++abi (static: include/c++/v1, lib/libc++.a and
#          lib/libc++abi.a) for this x86_64 Linux host, built by that clang22 from the llvm-project release
#          clang22 is built from, and cached. PIN_DIR is a product's components/clang22: its llvm-project
#          holds "LLVM_VERSION SHA256" (the SHA-256 of llvm-project-LLVM_VERSION.src.tar.xz), and its version
#          must be a clang22 release of that LLVM version, else exit 1. A cross build's host toolset uses the
#          prefix, so host tools on Linux use clang22 and its own libc++ as on every Mac host; clang22's Linux
#          archive ships a libc++ for Darwin targets only. The cache is $MAVERGREEN_HOST_LIBCXX_CACHE
#          (default ~/.cache/mavergreen-host-libcxx)/CLANG22_VERSION-pic; the libraries are built
#          position-independent, so shared objects can link them.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavericks_fetch.sh"
die() { echo "fetch_host_libcxx: $*" >&2; exit 1; }
[ $# -eq 2 ] && [ -d "$1" ] || { echo "usage: fetch_host_libcxx.sh PIN_DIR CLANG22_PREFIX" >&2; exit 2; }
PIN="$(cd "$1" && pwd)"; CL="$2"
[ -f "$PIN/llvm-project" ] && [ -f "$PIN/version" ] || { echo "fetch_host_libcxx: $PIN needs llvm-project and version files" >&2; exit 2; }
v="$(awk '{ print $1 }' "$PIN/llvm-project")"; sha="$(awk '{ print $2 }' "$PIN/llvm-project")"
cv="$(tr -d ' \t\n' < "$PIN/version")"
case "$cv" in "$v"-*) ;; *) die "clang22 $cv is not LLVM $v; update $PIN/llvm-project" ;; esac
base="${MAVERGREEN_HOST_LIBCXX_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/mavergreen-host-libcxx}"
dest="$base/$cv-pic"
complete() { [ -f "$1/lib/libc++.a" ] && [ -f "$1/lib/libc++abi.a" ] && [ -f "$1/include/c++/v1/__config_site" ]; }
if complete "$dest"; then echo "$dest"; exit 0; fi
asset="llvm-project-$v.src.tar.xz"
shipyard_fetch_verified "https://github.com/llvm/llvm-project/releases/download/llvmorg-$v/$asset" "$sha" "$base/dl" "$asset" >&2
work="$(mktemp -d "${TMPDIR:-/tmp}/host-libcxx.XXXXXX")"; trap 'rm -rf "$work"' EXIT
tar -xJf "$base/dl/$asset" -C "$work"
s="$work/llvm-project-$v.src"
cm="$(command -v cmake)" || die "no cmake on PATH"
flags="--no-default-config -rtlib=libgcc --unwindlib=libgcc -stdlib=libstdc++"
rm -rf "$dest.tmp"
"$cm" -S "$s/runtimes" -B "$work/b" -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_INSTALL_PREFIX="$dest.tmp" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF -DLLVM_INCLUDE_TESTS=OFF \
  -DCMAKE_C_COMPILER="$CL/bin/clang" -DCMAKE_CXX_COMPILER="$CL/bin/clang++" \
  -DCMAKE_C_COMPILER_TARGET=x86_64-unknown-linux-gnu -DCMAKE_CXX_COMPILER_TARGET=x86_64-unknown-linux-gnu \
  -DCMAKE_C_FLAGS="$flags" -DCMAKE_CXX_FLAGS="$flags" \
  -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld --ld-path=$CL/bin/ld.lld" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld --ld-path=$CL/bin/ld.lld" \
  -DCMAKE_AR="$CL/bin/llvm-ar" -DCMAKE_RANLIB="$CL/bin/llvm-ranlib" \
  -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
  -DLIBCXXABI_USE_LLVM_UNWINDER=OFF -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF \
  -DLIBCXX_INCLUDE_BENCHMARKS=OFF >&2
"$cm" --build "$work/b" --target install-cxx install-cxxabi -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)" >&2
rm -rf "$dest"; mv "$dest.tmp" "$dest"
complete "$dest" \
  || die "the build installed no lib/libc++.a, lib/libc++abi.a or include/c++/v1/__config_site under $dest"
echo "$dest"
