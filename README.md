# shipyard

Build goop for Mac OS X 10.9 Mavericks.

Features: yes. Whatever helps native builds to succeed and cross builds to match.

## Install (once)

Install the [Mavergreen CMake product](https://github.com/Mavergreen/cmake/releases) first, then
shipyard. Shipyard's installer checks that CMake meets the minimum in
[`.mavergreen/products/shipyard/requires/cmake/min`](.mavergreen/products/shipyard/requires/cmake/min);
an absent or older product is refused.
For a first install, download both current packages into separate directories:

```sh
gh release download -R Mavergreen/cmake --pattern '*.pkg' --dir cmake-pkg
gh release download -R Mavergreen/shipyard --pattern '*.pkg' --dir shipyard-pkg
sudo installer -pkg cmake-pkg/cmake-*.pkg -target /
sudo installer -pkg shipyard-pkg/shipyard-*.pkg -target /
```

Shipyard's modules, scripts and launchers land in `/usr/local/mavergreen/shipyard`.
CMake lives separately in `/usr/local/mavergreen/cmake`. Nothing goes in `/usr/local/bin` but the
family's `mavergreen` helper.
The helper links three commands into `/usr/local/mavergreen/bin`, which the pkg puts on every login
shell's `PATH` through `/etc/paths.d/mavergreen` (open a new terminal to pick it up):

```
/usr/local/mavergreen/bin/shipyard-cmake
/usr/local/mavergreen/bin/shipyard-ctest
/usr/local/mavergreen/bin/shipyard-cpack
```

**Configure your projects with `shipyard-cmake`.** It launches the sibling CMake product after
appending shipyard's prefix to `CMAKE_PREFIX_PATH`, so your own search paths still take precedence.
`shipyard-ctest` and `shipyard-cpack` launch that product's matching tools. The bare names
`cmake`, `ctest` and `cpack` stay out of the family's link farm.

On macOS, `MavergreenShipyardConfig.cmake` accepts only a CMake product paired with an installed
shipyard and at least the pinned upstream version; it names a foreign or older CMake when refusing it.
Existing build directories keep regenerating through compatibility links at
`shipyard/bin/{cmake,ctest,cpack}`. If the CMake product has been removed, the launchers print its
release URL and ask you to install it.

In GitHub Actions, `install@v1` verifies and installs the pinned CMake package before shipyard.
Consumers keep using the same action and `shipyard-*` commands.

The pkg also keeps itself current: its updater checks daily and installs each new release. The same
pkg works on Intel, on Apple Silicon and on 10.9.

GUI tools that want a CMake executable (CLion, VS Code's CMake Tools, Xcode wrappers), launchd jobs and
anything else that never runs a login shell do not see `paths.d`: point them at
`/usr/local/mavergreen/bin/shipyard-cmake`. The shared presets live at
`/usr/local/mavergreen/shipyard/share/cmake/MavergreenShipyard/mavergreen-presets.json`.

**The CMake product has no HTTPS downloader.** `file(DOWNLOAD https://…)` and HTTPS
`FetchContent` fail with "Unsupported protocol". See [CMake's README](https://github.com/Mavergreen/cmake#readme)
for the limit and the offline FetchContent pattern. Fetch pinned sources with shipyard's
`mavergreen_fetch.sh`, `clone_pinned.sh` or `fetch_pinned_source.sh` instead.

If you have a machine that ran an older shipyard, `rm -rf ~/.cmake/packages/MavergreenShipyard` once.
Nothing reads it any more.

A machine that had shipyard installed before it moved under `/usr/local/mavergreen` still has the old
layout, which no installer removes and whose `/usr/local/bin/shipyard-cmake` comes first on `PATH`.
Remove it by hand, once:

```sh
sudo rm -rf /usr/local/mavergreen-shipyard /usr/local/bin/shipyard-cmake /usr/local/bin/shipyard-ctest /usr/local/bin/shipyard-cpack
```

CMake.app (`cmake-gui`) uses its own bundled CMake and cannot be pointed at the launcher.
It can open a build directory first configured with `shipyard-cmake`.

### Developing shipyard itself

`--install` is for working on shipyard, not for consuming it. Build and install into a prefix of your
own:

```sh
shipyard-cmake -S . -B build
shipyard-cmake --install build --prefix "$HOME/.local/opt/shipyard-dev"
```

Then point a consumer at the dev copy for one configure, without disturbing the installed pkg:

```sh
CMAKE_PREFIX_PATH="$HOME/.local/opt/shipyard-dev" shipyard-cmake -S . -B build
```

The launcher appends the installed shipyard prefix after your `CMAKE_PREFIX_PATH`, so the dev copy
wins for that command. The dev prefix does not need a CMake product of its own.

### Developing shipyard on Linux

You can work on shipyard without a Mac: edit its scripts, run its gates, and run every suite that does
not need Apple tools. On Debian or Ubuntu:

```sh
sudo apt-get install bats cmake python3-yaml jq
sh scripts/run-repo-tests.sh --strict-host      # every host-agnostic suite; a skip counts as a failure
sh scripts/check-family-conventions.sh          # the gate every product repo runs
```

**What you cannot do on Linux** is anything that inspects an Apple artifact: shipyard-cmake, the updater,
and the `lipo`/`otool` assertions on real Mach-O files. The pkg seams are not on that list: they run on any
host, through stevedore. There is no Linux shipyard-cmake. On Linux, shipyard's CMake config accepts any
`cmake`, because there is nothing else to demand. Those suites are listed in `tests/maintainer-tests`, which the maintainer runs by hand on a 10.9 box and a modern Mac.

**How to tell which is which:** every script and test says so in its header, and check 22 enforces it:

```sh
grep -rl '^# platform: macOS-only' scripts tests   # the Mac-only half, each with its reason
```

`--strict-host` lists each macOS-only suite as `SKIP ... (macOS-only)` and ends with a count. The same
command runs in CI on ubuntu-latest (`.github/workflows/linux-host.yml`), and a release does not
publish unless it passes.

Consumers get the same half in their own Linux jobs: `install@v1` on a non-macOS runner exports
`SHIPYARD_SCRIPTS` and `MavergreenShipyard_DIR`, and `find_package(MavergreenShipyard)` resolves with any
cmake.

## Use

In your `CMakeLists.txt`:

```cmake
project(foo LANGUAGES C OBJC)

find_package(MavergreenShipyard REQUIRED)
include(Mavergreen)

add_executable(foo ...)
mavergreen_assert_binary_compatible(foo)
```

In your `CMakePresets.json`:

```json
{
  "version": 6,
  "include": ["/usr/local/mavergreen/shipyard/share/cmake/MavergreenShipyard/mavergreen-presets.json"],
  "configurePresets": [
    { "name": "native", "inherits": "mavergreen-native" },
    { "name": "cross",  "inherits": "mavergreen-cross"  }
  ]
}
```

In your `.github/workflows/*.yml` (if applicable):

```yaml
- uses: Mavergreen/shipyard/.github/actions/install@v1
```

Then build, and test:

```sh
shipyard-cmake --preset native    # on Mavericks
shipyard-cmake --preset cross     # on Tahoe
shipyard-ctest --preset native
shipyard-cpack --preset native    # where the product packages with CPack
```

On macOS, a foreign or too-old CMake is refused by `find_package(MavergreenShipyard)`, with a
message naming the minimum version and `shipyard-cmake`. On Linux, any CMake may configure it.

## Sparkle

Configure a keypair with
[ed25519](https://github.com/Mavergreen/ed25519).

In your `CMakeLists.txt`:

```cmake
include(MavericksSparkle)
mavericks_add_updater_app(
  PRODUCT       foo
  ICON          updater/foo.icns
  CONFIRM_TITLE "Foo updated"
  CONFIRM_BODY  "Foo was updated in the background."
)
```

`foo` is the product's short name, the directory `.mavergreen/products/foo/`; the app (`foo-updater.app`),
its bundle id and its feed are derived from it and the repo.

## SDK declaration metadata

Some Objective-C source needs a declaration the 10.9 SDK lacks, such as `NSArray`'s lightweight
generic parameter. Recaulk ships recipes for those edits as data
(`/usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json`, schema 1); `MavergreenSDKMetadata`
applies them without touching the SDK:

```cmake
include(MavergreenSDKMetadata)
mavergreen_materialize_sdk_metadata(overlay
  SDK        "${CMAKE_OSX_SYSROOT}"
  RECIPES    "${recipes_json}"
  IDS        foundation-array-generics-v1
  OUTPUT_DIR "${fresh_dir}")
```

It refuses, before writing anything, a recipe file of another schema, SDK name or SDK archive than
the pinned one; an unknown, repeated or overlapping recipe; a header whose SHA-256 is not the
recipe's; a header or alias that resolves outside the SDK, or an alias that is not the same file; a
replacement whose text does not occur exactly once; and an `OUTPUT_DIR` that exists or resolves into
the SDK. Otherwise `OUTPUT_DIR` appears whole, holding the edited headers and `overlay.json`, a clang
VFS overlay that maps each header's path and its aliases (under the SDK path as given and as
resolved) onto the edited copy; `overlay` is set to its path. Every `old` is found in the SDK's own
text, never in another replacement's output, and two replacements may not overlap. The overlay
matches paths exactly: a spelling it does not list (`Versions/Current/Headers/NSArray.h`, or another
case) reaches the SDK's own header.

A product opts one target in, explicitly:

```cmake
mavergreen_target_sdk_metadata(TARGET iTerm2
  SDK        "${CMAKE_OSX_SYSROOT}"
  RECIPES    "${recipes_json}"
  IDS        foundation-array-generics-v1
  OUTPUT_DIR "${CMAKE_BINARY_DIR}/sdk-metadata")
```

That target's Objective-C and Objective-C++ compiles get `-ivfsoverlay <overlay>` beside their
unchanged `-isysroot`; its C and C++ compiles, every other target and every link are untouched. The
overlay lives in a generation under `OUTPUT_DIR` named for its inputs: the SDK path, the recipe
file's bytes, the ids, the Objective-C compilers and this module's own bytes. A reconfigure with the
same inputs reuses the generation once its recipes validate again against the SDK's current bytes
and pin, and every file in it matches the stamp written beside it; a
generation without that stamp, or with a changed, added or missing file, is refused and left as it
is (remove it to regenerate). `SDK` must be the configure's `CMAKE_OSX_SYSROOT`, or the overlay
could never apply.

What it does not do: an overlay changes declarations only, so a recipe can make generic syntax
compile but adds no methods, classes or runtime behaviour, and a binary built with it needs nothing
extra on 10.9. The compiler must read clang VFS overlays (clang22 does); the recipes cover only what
Recaulk ships, and `tests/sdk-metadata-consumer-test.sh` (run by hand on each box, see
`tests/maintainer-tests`) is the evidence for the import orders it checks.

## Build-input host tools

Some build inputs come from tools that run on the build machine, never on 10.9: the pinned
[mulle-xcode-to-cmake](https://github.com/mulle-nat/mulle-xcode-to-cmake) exporter
(`.mavergreen/ingredients/mulle-xcode-to-cmake/`, GPL-3.0, never shipped in a pkg). `MavergreenHostTools`
builds them for the host in a configure of their own:

```cmake
include(MavergreenHostTools)
mavergreen_build_host_tools(tools_bin
  OUTPUT_ROOT "${MAVERGREEN_BUILD_ROOT}/host-tools"
  COMPILER    /usr/local/mavergreen/bin/clang-22-cross)   # clang-22 on 10.9
```

On Apple Silicon the tools are arm64, against the pinned 11.3 SDK for macOS 11.0. When CMake itself
runs under Rosetta, the tools' own configure and build are started with `/usr/bin/arch -arm64`, so
neither they nor the tools run translated; if `sysctl` cannot tell but `uname -m` says arm64, it
refuses rather than build x86_64 tools. Elsewhere the tools are x86_64, against the pinned 10.9 SDK
for 10.9. Building them needs `/usr/bin/make`, which is a Command Line Tools stub on every macOS. The
compiler runs with `--no-default-config` and an explicit target, so clang22's product defaults
(Recaulk, its libc++, the 10.9 target) never reach a host link, and links with lld. An x86_64 host
link also passes `-Wl,-U,__availability_version_check`, as clang22's own config does: compiler-rt's
version-check helper names that libSystem function, which 10.9 lacks and never calls.

The tools land in `OUTPUT_ROOT/<key>/bin`, keyed by host arch, compiler, SDK pin, exporter pin and
this module's own files, beside a stamp of each file's SHA-256. The same inputs reuse the entry once
it matches its stamp; an entry that does not (changed, unstamped, or left by an interrupted build) is
set aside as `.rejected-*` and rebuilt, never run. The stamp guards against accidents, not against
someone who can write `OUTPUT_ROOT`: keep it private to the build. One writer builds per key at a time, and an
`OUTPUT_ROOT` inside shipyard or the exporter source is refused. The first build fetches the
exporter's tarball (verified) and the host's pinned SDK.

`MavergreenXcodeInputs` uses them to read an upstream Xcode project's source lists without Xcode:

```cmake
include(MavergreenXcodeInputs)
mavergreen_export_xcode_sources(sources_cmake
  PROJECT       "${src}/iTerm2.xcodeproj"
  TARGETS       iTerm2 iTerm2Shared image_decoder SSKeychain
  PREFIXES      ITERM2 ITERM2_SHARED IMAGE_DECODER SSKEYCHAIN
  HOST_COMPILER /usr/local/mavergreen/bin/clang-22-cross
  OUTPUT_DIR    "${CMAKE_BINARY_DIR}/xcode-inputs")
include("${sources_cmake}")   # ITERM2_SHARED_SOURCES, ITERM2_MODELS, ...
```

`PREFIXES` are the variable prefixes the exporter gives each target, in `TARGETS`' order; with two or
more targets, one it does not use is an error (a lone target's variables take its prefix). The
exporter's `sexport -r` output is read as data, never `include()`d: every line must have the shape it
writes, and every path must be plain (no `[ ] ; $ " \ ( )`, no `..`, nothing absolute) and lead to
something inside the project's directory. Each target's sources, headers and resources are checked, entry
for entry and duplicate for duplicate, against `mavergreen-xcode-inputs`, which reads the same build phases through
Foundation's property-list reader and the project's group tree. Only then does the generated file
appear, defining for each prefix:

- `<P>_SOURCES`: the code files its sources phase compiles;
- `<P>_MODELS`: the Core Data models that phase lists, which are not compiled;
- `<P>_PRODUCT_RESOURCES`: other targets' built products its resources phase copies, by product name;
- the exporter's `<P>_INCLUDE_DIRS`, `<P>_*_HEADERS` and `<P>_*RESOURCES`.

Every path is relative to the project's directory, written as a bracket argument. Nothing in the
project runs, and no link, ARC or bundle setting is translated: those belong to the product's own
CMake. The same inputs reuse the export while it matches its stamp; a changed or unstamped export is
refused and left as it is (remove it to export again).

`MavergreenResourceInputs` stages a chosen subset of a pinned zip archive, such as compiled nibs from an
upstream release, without unpacking or running the rest:

```cmake
include(MavergreenResourceInputs)
mavergreen_extract_resource_members(resources_dir
  ARCHIVE        "${zip}"                       # fetched beforehand, e.g. shipyard_fetch_verified
  SHA256         90e6f2bd3eb2d245f4ab2c9f856c627c8a1536bac024fb3989db417bc3147565
  MANIFEST       "${CMAKE_SOURCE_DIR}/resources/compiled.tsv"
  MEMBER_PREFIX  "iTerm.app/Contents/Resources/"
  VERSION_MEMBER "iTerm.app/Contents/Info.plist"
  EXPECT_VERSION 3.0.15
  HOST_COMPILER  /usr/local/mavergreen/bin/clang-22-cross
  OUTPUT_DIR     "${CMAKE_BINARY_DIR}/resources")
```

The manifest's header is `member`, `destination`, `kind`, `bytes`, `sha256` (tab-separated); each line
names a regular file under `MEMBER_PREFIX`, where it goes, `file`, and its exact size and SHA-256.
`mavergreen-resource-extract` checks the archive's SHA-256 before reading any member, reads it with the
system's libarchive, and stages each selected member only after its type, size and SHA-256 hold while
it streams (written mode 0644, never as a link). `VERSION_MEMBER` must say `EXPECT_VERSION` as both
`CFBundleVersion` and `CFBundleShortVersionString`; it is read, not staged. A member that is a Mach-O
file (thin or fat) is refused, so upstream code cannot ride in as a resource, and `MEMBER_PREFIX` must
name a directory. Names are compared in Unicode composed form (a zip made on macOS stores them
decomposed). It refuses an unsafe path (absolute, `.`, `..`, empty segments, or `;`, `[`, `]`, which
CMake would read as syntax), two members with one destination or one inside another, a name
the archive holds twice, a missing member, a damaged, truncated or encrypted archive, and an output
directory that exists or whose parent is a link. The output appears complete or not at all, and
nothing outside it is written. On 10.9, libarchive 2.8.3 reads a zip's symbolic link as a regular file
holding the link's text; such a member is still refused, because its bytes are not the manifest's.
The same inputs reuse the staged members while each still has its manifest size, SHA-256 and mode and
nothing else is there; anything else is refused and left as it is.

## Conventions for Claude Code

The family's conventions ship as the `mavergreen` Claude Code plugin, from this repo's
marketplace. A product repo's checked-in `.claude/settings.json` registers the marketplace and
enables the plugin, but that alone installs nothing. Install it once, for every family repo:

```sh
claude plugin install mavergreen@mavergreen --scope user
```

then turn on auto-update in `/plugin` → Marketplaces → mavergreen. The plugin carries no
version, so every push to `main` is an update.

### Linux product archives

For a product that publishes a Linux x86_64 archive, use
`sh "$SHIPYARD_SCRIPTS/fetch_product_tar.sh" --repo OWNER/REPO SHORT VERSION SHA256 DEST`.
Pin the version and archive SHA-256 together in the consuming repository. The helper
fetches OWNER/REPO's release (the ingredient's `REPO`), verifies cached downloads and extracted
files, and prints the user-owned prefix on stdout. It requires Python 3.9 or newer,
curl, and either shasum or sha256sum. Override `MAVERGREEN_TAR_CACHE` to choose a
local-disk cache; no root installation is required.

A Linux build targeting Mavericks uses `MavergreenToolchain.cmake` with explicit
Linux-native clang22 compiler and LLVM tool paths. It selects Darwin and the
configured arch (x86_64 against the pinned 10.9 SDK, arm64 against the pinned 11.3 SDK with
deployment target 11.0) before compiler detection. Use host-native
CMake and build tools. Target executables must be tested on Mavericks, not run as
Linux configure probes. Apple SDK bytes remain separately fetched by `fetch_sdk.sh`.

## Build ingredients

Everything baked into what shipyard ships, and how a change to it reaches a release, is in
[`.mavergreen/`](.mavergreen/): one directory per ingredient under `ingredients/`, shipyard's own line
under `upstream/`, the product under `products/` and each declared deviation under `deviations/`.
`sh scripts/ingredients-table.sh` prints the ingredients as a table. shipyard no longer compiles CMake:
`shipyard-cmake`, `shipyard-ctest` and `shipyard-cpack` are launchers into the Mavergreen cmake product,
which shipyard pins and its pkg requires. The only thing shipyard compiles is its Sparkle updater app,
with clang22, alongside the CMake modules and shell scripts it has always shipped.
The Objective-C reference producer is a generation/test-only host tool, not a packaged runtime.
Its output, `reference/objc`, holds facts derived from the pinned SDKs and a floor runtime capture,
with their identities in `manifest.json`; no Apple header or binary is copied into it.
The Objective-C artifact reader (`tools/objc-compat`) is likewise built from source for tests and is
not yet packaged; the Drydock core it compiles is the `objc-reader-drydock` ingredient.

On a bump:

- GitHub Actions: automerges on green (`ship-if-green`), and the merge itself cuts the next shipyard
  version.
- bats: a new bats reaches CI on its next run; the suites are version-agnostic.
- cmake: the pkg's preinstall `requires` cmake at or above the minimum; `install@v1` installs the pinned
  release (SHA256SUMS-verified) before shipyard; a bump runs shipyard's full CI against it and the merge
  releases shipyard.
- stevedore: `scripts/fetch_stevedore.sh` fetches that release (SHA256SUMS-verified, `--version`
  checked); a bump runs shipyard's full CI against it and the merge releases shipyard.

## Release-doctrine surface

Four more scripts (`scripts/declared-state.sh`, `scripts/release-state.sh`,
`scripts/release-needed.sh`, `scripts/release-state-record.sh`) and one more reusable workflow
(`.github/workflows/reconcile.yml`) ship as of this release. Consumers reach all five the same way
they reach everything else here: through the moving `@v1` tag. What they do and how a product wires
them in is documented in the conventions skill, "A release is a declared state, not an event".

## Comment-reasons surface

`.mavergreen/config/comment-reasons` and `scripts/check-comments.sh` ship as of this release, run as
check 15 in `check-family-conventions.sh`. Consumers reach both the same way they reach everything else
here: through the moving `@v1` tag. A consumer adopts the check by sweeping its own tree and committing
its own `.mavergreen/config/comment-reasons` (one recognised tag per line — `platform`, `spec`); check 15
exits 0, silently, in a repo that has not swept yet. A repo that wants a declared exception states it as
`.mavergreen/deviations/comments/<label>/` (`scope`, `reason`, `revisit`), the same deviations
`check-artifact-conformance.sh` reads. What the two tolerated reasons are, and the test that decides
whether a comment is warranted at all, is documented in the conventions skill ("Comments cite a
reason").
