# Build ingredients

Everything baked into what shipyard ships, and how a change to it reaches a release. shipyard **does**
compile: it builds CMake itself — shipped as `shipyard-cmake`, `shipyard-ctest` and `shipyard-cpack` —
and the Sparkle updater app, alongside the CMake modules and shell scripts it has always shipped. So
its build inputs are now both the things it compiles WITH and the things its scripts fetch on a
consumer's behalf.

This repo is consumed through a **moving** tag. Fifteen repos pin `@v1`, so anything merged here reaches
all of them within minutes — which is why the version is derived from the commit count (see
`scripts/shipyard-version.sh`) rather than bumped by hand.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| Sparkle 1.27.3 (updater framework) | `MavericksSparkle.cmake` (`mavericks_fetch_sparkle`) | ❌ **untrackable** by a standard manager: the version is a literal inside a CMake function, not a dependency declaration. Deliberate — Sparkle 1.x is the last line supporting 10.9, so a bump is a decision, not a routine update. | hand-edit, then the next push cuts a version like any other change |
| MacOSX10.9 SDK | `scripts/fetch_sdk.sh` (`MAVERICKS_SDK_URL` + `MAVERICKS_SDK_SHA256`, phracker/MacOSX-SDKs 11.3) | ❌ **untrackable**: pinned by SHA-256 against a frozen third-party release. There is no newer 10.9 SDK to move to; the pin exists to prove the bytes, not to track a stream. | n/a — a change here would mean a different SDK, which is a deliberate port decision |
| GitHub Actions (`actions/checkout@v7`, `actions/download-artifact@v8`, `actions/setup-python@v7`, `actions/upload-artifact@v7`, `softprops/action-gh-release@v3`) | `.github/workflows/*.yml` | ✅ native `github-actions` manager | automerges on green (`ship-if-green`), and the merge itself cuts the next shipyard version |
| `bats` (shell test driver) | installed by `.github/actions/install` from the platform package manager | ✅ tracked by the package manager, not pinned here | a new bats reaches CI on its next run; the suites are version-agnostic |
| CMake 4.4.3 (shipped as shipyard-cmake) | `cmake.pin` (version only) | ✅ Renovate customManager (github-releases Kitware/CMake) | `build-cmake.sh` verifies Kitware's published SHA-256; CI rebuilds the universal tree on a cache miss; the next push releases it |
| mavericks-clang 22.1.1-mavericks.1 (compiles shipyard-cmake's x86_64/10.9 half) | `mavericks-clang.pin` | ✅ Renovate customManager (github-releases Mavergreen/clang, `-mavericks.N` compared) | CI installs the pinned cross pkg (SHA256SUMS-verified); a bump rebuilds shipyard-cmake on green |
| PyYAML 6.0.3 (vendored: the checks' YAML reader; role shipped) | `scripts/vendor/pyyaml.pin` (`PYYAML_VERSION` + `PYYAML_SHA256` of the sdist) | ✅ Renovate customManager (pypi PyYAML) | the bump fails CI until `sh scripts/vendor/sync-pyyaml.sh` re-vendors `scripts/vendor/yaml` from the new sdist and rewrites `yaml.sha256` |
| shipyard's own version | `UPSTREAM_VERSION` (the **line**) + `git rev-list --count` | n/a — first-party | every push to `main` cuts `<line>.<count>`; `@v1` moves to it |

No upstream release notes: shipyard is its own upstream -- it ports nothing, so there are no
someone-else's notes for a release to link.

## Release-doctrine surface

Four more scripts (`scripts/declared-state.sh`, `scripts/release-state.sh`,
`scripts/release-needed.sh`, `scripts/release-state-record.sh`) and one more reusable workflow
(`.github/workflows/reconcile.yml`) ship as of this release. Consumers reach all five the same way
they reach everything else here: through the moving `@v1` tag. What they do and how a product wires
them in is documented in the conventions skill, "A release is a declared state, not an event".

shipyard itself carries no `## Declared state` section. Its version is
`<UPSTREAM_VERSION>.<commit count>` (see the last row of the table above), so its own state changes
on every push, and every push already publishes by design. Adopting the digest path here would only
describe that status quo more slowly -- it is shipyard's declared exception, not a pattern to copy.

## Comment-reasons surface

`comment-reasons` and `scripts/check-comments.sh` ship as of this release, run as check 15 in
`check-family-conventions.sh`. Consumers reach both the same way they reach everything else here:
through the moving `@v1` tag. A consumer adopts the check by sweeping its own tree and committing its
own `comment-reasons` (one recognised tag per line — `platform`, `spec`); check 15 exits 0, silently, in
a repo that has not swept yet. A repo that wants one declared exception states it under `## Conformance
deviations` below (`- comments: <reason>`), the same grammar `check-artifact-conformance.sh` already
reads. What the two tolerated reasons are, and the test that decides whether a comment is warranted at
all, is documented in the conventions skill ("Comments cite a reason").

**That grammar has a second reader.** `artifact-facts.sh` also parses this file's `## Conformance
deviations` section, so a `- comments: <reason>` line surfaces twice — once as a deviation for
`check-family-conventions.sh`, once as a `deviation comments <reason>` record in the artifact fact
stream. Harmless, since the conformance checker only consults records for checks it evaluates, but the
two subsystems share one namespace under one header.

## Conformance deviations

`check-artifact-conformance.sh` holds each release's artifacts to the family's schemes. One of them,
`version-scheme`, assumes a version of the form `<upstream>-mavericks.N`; shipyard's is not, on purpose.
Machine-read by `artifact-facts.sh` as `- <check>[:<glob>]: <reason>` (the reason is the rest of that
one line):

- version-scheme: shipyard ports nothing, so there is no upstream to suffix -- its version is <line>.<commit count> (scripts/shipyard-version.sh), cut on every push to main.
  Every artifact still carries that one version: the pkg, the appcast and the tag agree, and conformance
  checks that they do.
- pr-trigger: shipyard's pull requests are built by ci.yml, its required check; release.yml cuts a release on every push to main and must not run on a PR. Revisit if release.yml gains a dry-run mode for PRs.
- permissions-contents-read: release.yml has held `contents: write` at the top since before this check; its build job was never audited for needing less, and the publish and major-tag jobs already declare their own. Revisit once a release run proves the build job needs only `contents: read`.
- checkout-drops-credentials: the major-tag job pushes with its checkout's token, and the build job's checkout was never audited for dropping it. Revisit with permissions-contents-read.
- bare-curl:scripts/assert_update_trusted.sh: it curls the live feed and pkg on its own to see the HTTP status; it does not source the fetch library. Revisit when QUEUE #58's mav_curl lands.
- bare-curl:scripts/fetch_product_pkg.sh: it fetches the release's SHA256SUMS with a curl of its own, beside the library's verified fetch. Revisit when QUEUE #58's mav_curl lands.
- bare-curl:.github/workflows/publish-release.yml: its first-release readme step fetches the template with a curl of its own. Revisit when QUEUE #58's mav_curl lands.
- bare-curl:scripts/build-cmake.sh: it curls Kitware's tarball and checksum file before the fetch library can be sourced. Revisit when QUEUE #58's mav_curl lands.
- bare-curl:scripts/check-preset-icons.sh: it curls a vendor's icon and apt index on its own. Revisit when QUEUE #58's mav_curl lands.
- bare-curl:scripts/vendor/sync-pyyaml.sh: it curls the PyYAML sdist on its own. Revisit when QUEUE #58's mav_curl lands.
- brew:scripts/install-macho-readers.sh: the fallback for llvm-lipo and llvm-strings, which Xcode does not ship. Revisit when every job that runs the compat guard has clang22 installed (vision area 14).
- brew:.github/workflows/ci.yml: the step that records what the Mach-O readers resolved to asks brew whether llvm is present. Revisit with brew:scripts/install-macho-readers.sh, whose fallback it reports on.
- brew:.github/actions/install/action.yml: bats-core, where no family bats exists. Revisit when a family product or the runner image supplies bats.
- brew:scripts/build-cmake.sh: it names the prefix only to exclude it (CMAKE_IGNORE_PREFIX_PATH): /opt/homebrew is kept out of CMake's search and nothing from it is used. Revisit if the exclusion list moves into a shared CMake module.
- macports:scripts/build-cmake.sh: it names the prefix only to exclude it (CMAKE_IGNORE_PREFIX_PATH): /opt/local is kept out of CMake's search and nothing from it is used. Revisit if the exclusion list moves into a shared CMake module.
- pkgsrc:scripts/build-cmake.sh: it names the prefix only to exclude it (CMAKE_IGNORE_PREFIX_PATH): /opt/pkg is kept out of CMake's search and nothing from it is used. Revisit if the exclusion list moves into a shared CMake module.
- apt:.github/workflows/linux-host.yml: the Linux CI job installs llvm and libarchive-tools. Revisit when area 14's pinned LLVM tarball supplies the readers and bsdtar comes from a family Linux tarball or the job's image.
- apt:.github/actions/install/action.yml: bats-core on a Linux runner, where no family bats exists. Revisit when a family product or the runner image supplies bats.
- host:linux: bash32-parse needs a bash 3.2 /bin/sh and Linux has none. Revisit when QUEUE #60's Apple-shells collection ships its Linux tarball.
- vendored:scripts/vendor/yaml/**: PyYAML is vendored because python-315's phase 1 has no ssl, so pip cannot fetch it on 10.9, and the checks keep their Python. Revisit when python-315 ships ssl and pip works (its phase 2); then delete the vendored copy and the checks import a pip-installed PyYAML (/opt/mavergreen/bin/python3 -m pip install --user pyyaml).
- vendored:scripts/vendor/pyyaml.pin: the pin that maintains scripts/vendor/yaml. Revisit with vendored:scripts/vendor/yaml/**; it goes when the copy does.
- vendored:scripts/vendor/yaml.sha256: the checksum that maintains scripts/vendor/yaml. Revisit with vendored:scripts/vendor/yaml/**; it goes when the copy does.
- vendored:scripts/vendor/sync-pyyaml.sh: the sync script that maintains scripts/vendor/yaml. Revisit with vendored:scripts/vendor/yaml/**; it goes when the copy does.
- docs-no-sudo:README.md: its install, uninstall and Linux dev-dependency steps are written as root commands; the Engine does not exist yet, so no family command does the first two. Revisit when the Engine's `mavergreen install` and `mavergreen uninstall` ship in the flag day; the dev-dependency line goes with `apt:.github/actions/install/action.yml`.
