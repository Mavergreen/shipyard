#!/bin/sh
# platform: macOS-only -- xcrun, lipo and otool build and check the universal CMake
#   usage: build-cmake.sh --arch x86_64|arm64 --min-os VER --prefix DIR [--jobs N] [--sysroot DIR]
#          build-cmake.sh --fetch-only --dest DIR          (download + verify only; prints the path)
#          Builds the CMake shipyard ships as shipyard-cmake: ONE arch and deployment floor per run,
#          into a prefix, from Kitware's SOURCE tarball verified against the release's own
#          cmake-<v>-SHA-256.txt and configured by a HOST-NATIVE cmake found on PATH, which both
#          halves use. Universal comes from running this twice (x86_64/10.9, arm64/11.0) and
#          scripts/lipo-merge-tree.sh. The TARGET compiler is the environment's CC/CXX, which cmake
#          honours. SHIPYARD_CMAKE_URL_BASE overrides the download base (default
#          https://github.com/Kitware/CMake/releases/download); --sysroot DIR defaults to
#          `xcrun --show-sdk-path` and is passed through as CMAKE_OSX_SYSROOT.
# platform: CMake is an ordinary CMake project, so another cmake can build it; CMake's own
#           ./bootstrap first compiles a stage-0 cmake that must RUN on this host, and mavericks-clang
#           always targets x86_64, so on an arm64 runner that stage-0 needs Rosetta. macOS 28 removes
#           Rosetta, so the stage-0 is gone from this recipe rather than worked around.
# platform: the x86_64/10.9 half MUST be built with the family's mavericks-clang-22
#           (CC/CXX=<its prefix>/bin/clang{,++}) -- CMake 4.x needs C++17, the 10.9 box's Xcode 6
#           cannot provide it, and mavericks-clang links its own libc++ statically so the result
#           needs nothing outside the OS. The arm64/11.0 half uses Apple's clang, the default.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
ARCH=""; MINOS=""; PREFIX=""; JOBS=""; FETCH_ONLY=""; DEST=""; SYSROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --arch) ARCH="$2"; shift 2;;
    --min-os) MINOS="$2"; shift 2;;
    --prefix) PREFIX="$2"; shift 2;;
    --jobs) JOBS="$2"; shift 2;;
    --sysroot) SYSROOT="$2"; shift 2;;
    --fetch-only) FETCH_ONLY=1; shift;;
    --dest) DEST="$2"; shift 2;;
    *) echo "build-cmake: unknown option $1" >&2; exit 2;;
  esac
done

V="$(sed -n 's/^CMAKE_VERSION=//p' "$SELF/../cmake.pin")"
[ -n "$V" ] || { echo "build-cmake: no CMAKE_VERSION in $SELF/../cmake.pin" >&2; exit 1; }
BASE="${SHIPYARD_CMAKE_URL_BASE:-https://github.com/Kitware/CMake/releases/download}"
TARBALL="cmake-$V.tar.gz"

fetch_verified() {  # $1 = dir to download into; prints the tarball path
  mkdir -p "$1"
  curl -fsSL -o "$1/$TARBALL" "$BASE/v$V/$TARBALL" \
    || { echo "build-cmake: could not download $BASE/v$V/$TARBALL" >&2; return 1; }
  curl -fsSL -o "$1/cmake-$V-SHA-256.txt" "$BASE/v$V/cmake-$V-SHA-256.txt" \
    || { echo "build-cmake: could not download Kitware's checksum file for $V" >&2; return 1; }
  want="$(awk -v f="$TARBALL" '$2 == f { print $1 }' "$1/cmake-$V-SHA-256.txt")"
  [ -n "$want" ] || { echo "build-cmake: checksum file for $V does not list $TARBALL; refusing" >&2; return 1; }
  got="$(shasum -a 256 "$1/$TARBALL" | awk '{ print $1 }')"
  [ "$got" = "$want" ] \
    || { echo "build-cmake: checksum mismatch for $TARBALL (got $got, Kitware published $want); refusing" >&2; return 1; }
  printf '%s\n' "$1/$TARBALL"
}

if [ -n "$FETCH_ONLY" ]; then
  : "${DEST:?build-cmake: --fetch-only needs --dest}"
  fetch_verified "$DEST"; exit 0
fi

[ -n "$ARCH" ] && [ -n "$MINOS" ] && [ -n "$PREFIX" ] \
  || { echo "build-cmake: need --arch, --min-os and --prefix" >&2; exit 2; }

# platform: CMAKE_SYSTEM_NAME is what makes CMAKE_CROSSCOMPILING true, so CMake REFUSES to run a
#           binary it just built for the target instead of running it and silently depending on
#           Rosetta -- the whole point of dropping ./bootstrap. It wants the kernel's version, not
#           the product's: Darwin 13 is macOS 10.9 (10.x -> x+4), Darwin 20 is macOS 11.0 (N -> N+9).
case "$MINOS" in
  10.[0-9]|10.[0-9][0-9]) DARWIN_V="$(( ${MINOS#10.} + 4 ))";;
  1[1-9].[0-9]*|[2-9][0-9].[0-9]*) DARWIN_V="$(( ${MINOS%%.*} + 9 ))";;
  *) echo "build-cmake: --min-os '$MINOS' is not a macOS version with a known Darwin release" >&2; exit 2;;
esac

if ! HOSTCMAKE="$(command -v cmake 2>/dev/null)" || ! "$HOSTCMAKE" --version >/dev/null 2>&1; then
  echo "build-cmake: no usable cmake on PATH, and this recipe configures CMake with one" >&2
  echo "    install cmake and put it on PATH: GitHub's macOS runner images already ship one;" >&2
  echo "    otherwise: brew install cmake, pkgsrc devel/cmake, or an official binary release" >&2
  echo "    from https://cmake.org/download/ -- any cmake that runs HERE will do" >&2
  exit 1
fi

[ -n "$JOBS" ] || JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"
[ -n "$SYSROOT" ] || SYSROOT="$(xcrun --show-sdk-path)"
[ -d "$SYSROOT" ] || { echo "build-cmake: --sysroot $SYSROOT is not a directory" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/build-cmake.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
tb="$(fetch_verified "$WORK")"
tar -xzf "$tb" -C "$WORK"
cd "$WORK/cmake-$V"
# spec: .github/actions/shipyard-cmake/action.yml -- patches are part of the recipe, so the cache
#       key must cover patches/cmake/* too or a patch change will not invalidate a cached build.
for p in "$SELF"/../patches/cmake/*.patch; do
  [ -f "$p" ] || continue
  patch -p1 < "$p" || { echo "build-cmake: $p does not apply to CMake $V" >&2; exit 1; }
done
# platform: without CMAKE_USE_SYSTEM_LIBRARIES=0 (what ./bootstrap spelled --no-system-libs),
#           CMake's own configure finds and links whatever curl/zlib/etc. the build host has
#           installed (pkgsrc, Homebrew, MacPorts) -- which it must never do, since a shipyard-cmake
#           binary is built on ONE box and run on others that lack that package manager or that
#           library at that path. CMAKE_IGNORE_PREFIX_PATH and the FIND_ROOT_PATH modes are defence
#           in depth behind it: libraries, headers and packages come only from the target SDK, while
#           PROGRAM stays NEVER because the tools the build RUNS must be the host's.
#           BUILD_CursesDialog=OFF because ccmake is not shipped and needs curses.
# spec: 2026-09-11 decision 3 -- the consequence is that shipyard-cmake ships WITHOUT HTTPS in
#       CMake's own downloader: bundled curl 8.20 has no macOS TLS backend without OpenSSL, which we
#       cannot ship, and the OS's own curl (10.9's SDK: 7.30) is too old for CMake 4.4's cmCurl.cxx,
#       which needs 7.34+. file(DOWNLOAD https://...) therefore fails loudly with
#       CURLE_UNSUPPORTED_PROTOCOL; the family fetches with mavericks_fetch.sh or clone_pinned.sh.
"$HOSTCMAKE" -S . -B "$WORK/build" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=Darwin \
  -DCMAKE_SYSTEM_VERSION="$DARWIN_V.0.0" \
  -DCMAKE_SYSTEM_PROCESSOR="$ARCH" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MINOS" \
  -DCMAKE_OSX_SYSROOT="$SYSROOT" \
  -DCMAKE_FIND_ROOT_PATH="$SYSROOT" \
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DCMAKE_USE_SYSTEM_LIBRARIES=0 \
  -DCMAKE_USE_OPENSSL=OFF \
  -DBUILD_CursesDialog=OFF \
  "-DCMAKE_IGNORE_PREFIX_PATH=/opt/pkg;/opt/local;/opt/homebrew;/usr/local;/sw" \
  -DBUILD_TESTING=OFF
"$HOSTCMAKE" --build "$WORK/build" --parallel "$JOBS"
"$HOSTCMAKE" --install "$WORK/build"

# platform: a build-host package manager (pkgsrc, Homebrew, MacPorts) leaking into bin/* runs fine
#           here and fails to even launch on a box lacking that exact library at that exact path, so
#           every Mach-O just installed may link only the OS's own dylibs.
for f in "$PREFIX"/bin/*; do
  lipo -info "$f" >/dev/null 2>&1 || continue
  bad="$(otool -L "$f" | sed 1d | awk '{print $1}' | grep -v -e '^/usr/lib/' -e '^/System/' || true)"
  [ -z "$bad" ] || { echo "build-cmake: $f links outside the OS: $bad" >&2; exit 1; }
  # platform: the arch reached the compiler three ways at once here (the -D above, CMake's own
  #           Darwin defaults, and mavericks-clang's bin/clang.cfg hardcoding --target=), so a
  #           dropped -D would still look green while the OUTPUT quietly became the host's arch --
  #           which lipo-merge-tree.sh would then merge as if it were the cross slice. 10.9's lipo
  #           has no -archs; check-shell-portability.sh names this -info idiom instead.
  got="$(lipo -info "$f" 2>/dev/null | sed -n 's/.*: //p' | xargs)"
  [ "$got" = "$ARCH" ] \
    || { echo "build-cmake: $f is '$got', not the requested $ARCH" >&2; exit 1; }
done

echo "build-cmake: CMake $V ($ARCH, min $MINOS) -> $PREFIX" >&2
