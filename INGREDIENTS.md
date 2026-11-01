# Build ingredients

Everything baked into what shipyard ships, and how a change to it reaches a release. shipyard no longer
compiles CMake: `shipyard-cmake`, `shipyard-ctest` and `shipyard-cpack` are launchers into the
Mavergreen cmake product, which shipyard pins and its pkg requires. The only thing shipyard compiles is
its Sparkle updater app, with clang22, alongside the CMake modules and shell scripts it has always shipped.

This repo is consumed through a **moving** tag. Fifteen repos pin `@v1`, so anything merged here reaches
all of them within minutes — which is why the version is derived from the commit count (see
`scripts/shipyard-version.sh`) rather than bumped by hand.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| Sparkle 1.27.3 (updater framework) | `MavericksSparkle.cmake` (`mavericks_fetch_sparkle`) | ❌ **untrackable** by a standard manager: the version is a literal inside a CMake function, not a dependency declaration. Deliberate — Sparkle 1.x is the last line supporting 10.9, so a bump is a decision, not a routine update. | hand-edit, then the next push cuts a version like any other change |
| MacOSX10.9 SDK | `scripts/fetch_sdk.sh` (`MAVERICKS_SDK_URL` + `MAVERICKS_SDK_SHA256`, phracker/MacOSX-SDKs 11.3) | ❌ **untrackable**: pinned by SHA-256 against a frozen third-party release. There is no newer 10.9 SDK to move to; the pin exists to prove the bytes, not to track a stream. | n/a — a change here would mean a different SDK, which is a deliberate port decision |
| GitHub Actions (`actions/checkout@v7`, `actions/download-artifact@v8`, `actions/setup-python@v7`, `actions/upload-artifact@v7`, `softprops/action-gh-release@v3`) | `.github/workflows/*.yml` | ✅ native `github-actions` manager | automerges on green (`ship-if-green`), and the merge itself cuts the next shipyard version |
| `bats` (shell test driver) | installed by `.github/actions/install` from the platform package manager | ✅ tracked by the package manager, not pinned here | a new bats reaches CI on its next run; the suites are version-agnostic |
| cmake 4.4.4-mavericks.1 (the Mavergreen cmake product; role `shipped`, which the launchers run) | `components/cmake/version` | ✅ Renovate customManager (github-releases Mavergreen/cmake, `-mavericks.N` compared) | the pkg's preinstall `requires` cmake at or above the pin; `install@v1` installs that release (SHA256SUMS-verified) before shipyard; a bump runs shipyard's full CI against it and the merge releases shipyard |
| clang22 22.1.8-mavericks.12 (the family's LLVM 22, which compiles and links shipyard's Sparkle updater on every host) | `components/clang22/version`, and its Linux archive's SHA-256 in `components/clang22/linux-sha256` | ✅ Renovate customManager (github-releases Mavergreen/clang-22, `-mavericks.N` compared); the digest beside it is written by hand from the release's SHA256SUMS (the bump PR says how) | `scripts/fetch_clang22.sh` fetches that release (the Linux archive against the pinned digest, a pkg against its release's SHA256SUMS, or the installed one at that version); a bump rebuilds the updater in shipyard's full CI and the merge releases shipyard |
| stevedore 20261027.1 (the Mavergreen packager that writes and reads family pkgs) | `scripts/stevedore.pin` | ✅ Renovate customManager (github-releases Mavergreen/stevedore) | `scripts/fetch_stevedore.sh` fetches that release (SHA256SUMS-verified, `--version` checked); a bump runs shipyard's full CI against it and the merge releases shipyard |
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
a repo that has not swept yet. A repo that wants a declared exception states it as
`.mavergreen/deviations/comments/<label>/` (`scope`, `reason`, `revisit`), the same deviations
`check-artifact-conformance.sh` reads. What the two tolerated reasons are, and the test that decides
whether a comment is warranted at all, is documented in the conventions skill ("Comments cite a
reason").
