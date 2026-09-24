# shipyard

Build goop for Mac OS X 10.9 Mavericks.

Features: yes. Whatever helps native builds to succeed and cross builds to match.

## Install (once)

Install shipyard from the pkg. Download it from the latest release and install it:

```sh
gh release download -R Mavergreen/shipyard --pattern '*.pkg'
sudo installer -pkg mavericks-shipyard-*.pkg -target /
```

Everything lands in `/usr/local/mavergreen/shipyard` — one directory holding CMake, the shipyard
modules and the shell scripts — and nothing in `/usr/local/bin` but the family's `mavergreen` helper.
The helper links three commands into `/usr/local/mavergreen/bin`, which the pkg puts on every login
shell's `PATH` through `/etc/paths.d/mavergreen` (open a new terminal to pick it up):

```
/usr/local/mavergreen/bin/shipyard-cmake
/usr/local/mavergreen/bin/shipyard-ctest
/usr/local/mavergreen/bin/shipyard-cpack
```

**Configure your projects with `shipyard-cmake`.** It is a real CMake (4.4.3) that finds shipyard in
its own prefix, so there is nothing to register and no search path to set. Any *other* cmake is
refused at configure time, by name — `MavericksShipyardConfig.cmake` says so rather than half-working.
There is no longer a "install shipyard first and cmake afterwards" order to get right: the pkg brings
its own.

The pkg also keeps itself current: its updater checks daily and installs each new release. The same
pkg works on Intel, on Apple Silicon and on 10.9.

GUI tools that want a CMake executable (CLion, VS Code's CMake Tools, Xcode wrappers), launchd jobs and
anything else that never runs a login shell do not see `paths.d`: point them at
`/usr/local/mavergreen/bin/shipyard-cmake`. The shared presets live at
`/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/mavericks-presets.json`.

**One thing shipyard-cmake cannot do: HTTPS from inside CMake.** `file(DOWNLOAD https://…)` and
`FetchContent` over HTTPS fail with "Unsupported protocol" — deliberately, and loudly rather than
fragilely. shipyard-cmake is built with `CMAKE_USE_SYSTEM_LIBRARIES=0` so it links nothing from the
build host; CMake's own bundled curl has no macOS TLS backend without OpenSSL, and 10.9's system
libcurl (7.30) is too old for CMake 4.4 to build against. Since this is the cmake the family is now
required to use, the limitation is everyone's: **fetch with the shipyard helpers instead**, pinned and
integrity-checked in a way `file(DOWNLOAD)` never was —

```sh
sh "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"  # a tarball, verified against a pinned SHA-256
sh "$SHIPYARD_SCRIPTS/clone_pinned.sh"     # a git source, pinned to a digest
```

Nothing in the org used CMake-level downloads, so nothing broke; if you are porting something that
does, that is the substitution to make.

If you have a machine that ran an older shipyard, `rm -rf ~/.cmake/packages/MavericksShipyard` once.
Nothing reads it any more.

A machine that had shipyard installed before it moved under `/usr/local/mavergreen` still has the old
layout, which no installer removes and whose `/usr/local/bin/shipyard-cmake` comes first on `PATH`.
Remove it by hand, once:

```sh
sudo rm -rf /usr/local/mavergreen-shipyard /usr/local/bin/shipyard-cmake /usr/local/bin/shipyard-ctest /usr/local/bin/shipyard-cpack
```

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

`CMAKE_PREFIX_PATH` is searched before shipyard-cmake's own prefix, so the override is explicit, scoped
to the command that asks for it, and gone the moment you stop asking.

### Developing shipyard on Linux

You can work on shipyard without a Mac: edit its scripts, run its gates, and run every suite that does
not need Apple tools. On Debian or Ubuntu:

```sh
sudo apt-get install bats cmake python3-yaml jq
sh scripts/run-repo-tests.sh --strict-host      # every host-agnostic suite; a skip counts as a failure
sh scripts/check-family-conventions.sh          # the gate every product repo runs
```

**What you cannot do on Linux** is anything that produces or inspects an Apple artifact: the pkg,
shipyard-cmake, the updater, and the `lipo`/`otool`/`pkgbuild` assertions. There is no Linux pkg and no
Linux shipyard-cmake. On Linux, shipyard's CMake config accepts any `cmake`, because there is nothing
else to demand. Those suites run in CI's macOS jobs.

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

Plain `cmake` is refused: `find_package(MavericksShipyard)` fails with a message naming
`shipyard-cmake`, rather than configuring against a CMake that cannot target 10.9.

## Sparkle

Configure a keypair with
[ed25519](https://github.com/Mavergreen/ed25519).

In your `CMakeLists.txt`:

```cmake
include(MavericksSparkle)
mavericks_add_updater_app(
  NAME          FooUpdater
  BUNDLE_ID     com.example.FooUpdater
  FEED_URL      https://github.com/you/foo/releases/latest/download/appcast.xml
  ICON          updater/foo.icns
  CONFIRM_TITLE "Foo updated"
  CONFIRM_BODY  "Foo was updated in the background."
)
```

## Conventions for Claude Code

The family's conventions ship as the `mavergreen` Claude Code plugin, from this repo's
marketplace. A product repo's checked-in `.claude/settings.json` registers the marketplace and
enables the plugin, but that alone installs nothing. Install it once, for every family repo:

```sh
claude plugin install mavergreen@mavergreen --scope user
```

then turn on auto-update in `/plugin` → Marketplaces → mavergreen. The plugin carries no
version, so every push to `main` is an update.
