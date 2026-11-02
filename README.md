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
sudo installer -pkg shipyard-pkg/mavericks-shipyard-*.pkg -target /
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

On macOS, `MavericksShipyardConfig.cmake` accepts only a CMake product paired with an installed
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
`/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/mavericks-presets.json`.

**The CMake product has no HTTPS downloader.** `file(DOWNLOAD https://…)` and HTTPS
`FetchContent` fail with "Unsupported protocol". See [CMake's README](https://github.com/Mavergreen/cmake#readme)
for the limit and the offline FetchContent pattern. Fetch pinned sources with shipyard's
`mavericks_fetch.sh`, `clone_pinned.sh` or `fetch_pinned_source.sh` instead.

If you have a machine that ran an older shipyard, `rm -rf ~/.cmake/packages/MavericksShipyard` once.
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
`cmake`, because there is nothing else to demand. Those suites run in CI's macOS jobs.

**How to tell which is which:** every script and test says so in its header, and check 22 enforces it:

```sh
grep -rl '^# platform: macOS-only' scripts tests   # the Mac-only half, each with its reason
```

`--strict-host` lists each macOS-only suite as `SKIP ... (macOS-only)` and ends with a count. The same
command runs in CI on ubuntu-latest (`.github/workflows/linux-host.yml`), and a release does not
publish unless it passes.

Consumers get the same half in their own Linux jobs: `install@v1` on a non-macOS runner exports
`SHIPYARD_SCRIPTS` and `MavericksShipyard_DIR`, and `find_package(MavericksShipyard)` resolves with any
cmake.

## Use

In your `CMakeLists.txt`:

```cmake
project(foo LANGUAGES C OBJC)

find_package(MavericksShipyard REQUIRED)
include(Mavericks)

add_executable(foo ...)
mavericks_assert_binary_compatible(foo)
```

In your `CMakePresets.json`:

```json
{
  "version": 6,
  "include": ["/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/mavericks-presets.json"],
  "configurePresets": [
    { "name": "native", "inherits": "mavericks-native" },
    { "name": "cross",  "inherits": "mavericks-cross"  }
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

On macOS, a foreign or too-old CMake is refused by `find_package(MavericksShipyard)`, with a
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

`foo` is the product's short name in shipyard's `scripts/product-names`; the app (`foo-updater.app`),
its bundle id and its feed are derived from that line.

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
`sh "$SHIPYARD_SCRIPTS/fetch_product_tar.sh" SHORT VERSION SHA256 DEST`.
Pin the version and archive SHA-256 together in the consuming repository. The helper
uses the product registry to find its release, verifies cached downloads and extracted
files, and prints the user-owned prefix on stdout. It requires Python 3.9 or newer,
curl, and either shasum or sha256sum. Override `MAVERGREEN_TAR_CACHE` to choose a
local-disk cache; no root installation is required.

A Linux build targeting Mavericks uses `MavericksToolchain.cmake` with explicit
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

On a bump:

- GitHub Actions: automerges on green (`ship-if-green`), and the merge itself cuts the next shipyard
  version.
- bats: a new bats reaches CI on its next run; the suites are version-agnostic.
- cmake: the pkg's preinstall `requires` cmake at or above the minimum; `install@v1` installs the pinned
  release (SHA256SUMS-verified) before shipyard; a bump runs shipyard's full CI against it and the merge
  releases shipyard.
- clang22: `scripts/fetch_clang22.sh` fetches that release (the Linux archive against the pinned digest,
  a pkg against its release's SHA256SUMS, or the installed one at that version); a bump rebuilds the
  updater in shipyard's full CI and the merge releases shipyard.
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
