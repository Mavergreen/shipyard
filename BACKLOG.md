# Backlog

Family-wide work that is worth doing and is not worth interrupting something else to do. Drop an
item here instead of spawning an agent at shipyard mid-flight; several sessions touch this repo at
once, and a queued note costs nothing while a concurrent branch costs a rebase.

Each entry carries the **evidence**, not just the conclusion — including what was already tried and
did not work, so the next person does not re-walk it. Delete an entry when it lands.

---

## 1. Conventions check: a test that hardcodes the upstream version blocks its own bumps

Two repos now carry one, so it is a pattern:

- **openssh** `tests/derive-upstream-version.bats` asserted the derived value equals `"9.9p2"`.
  Moving the pin to `V_10_5_P1` failed it, and `run-repo-tests` gates the build, so the release never
  ran. Fixed 2026-09-13 in `bba3750`.
- **clang** `tests/version-test.sh` hardcodes the upstream version and blocks its Renovate automerge.
  Not fixed (another session owns that repo).

A test that must be edited to accept a new upstream is not testing the upstream, it is blocking it.

**The distinction to encode:** hardcoding is fine when the test pins a **transform** with fixed
inputs (`V_9_9_P2` → `9.9p2` is true forever). It is wrong when the test pins **plumbing** — that the
build reads the committed pin and acts on it — because that holds at every version and the literal
only encodes today's. openssh's fix shows the shape: transform cases keep fixed inputs, the plumbing
case derives its expectation from the committed tag.

**Proposed check:** flag a tracked test file containing a string literal equal to the repo's current
upstream pin (`components/*/version`, `UPSTREAM_VERSION`, or the `renovate:`-annotated line in
`build/versions.sh`). False-positive risk: a fixture legitimately using the current version as sample
input — needs the usual reasoned escape hatch.

## 2. compat guard: replace the post-10.9 denylist with an SDK-derived allowlist

`scripts/assert_binary_compatible.sh` decides post-10.9 imports with one denylist:

    POST_10_9='_clock_gettime|_clock_gettime_nsec_np|_os_unfair_lock_.*|_os_log.*'

A denylist must predict which future API someone will accidentally call. Two independent proofs it
does not:

1. **swift-runtime already patched around it** — `scripts/guard.sh` there exports a widened
   `MAVERICKS_POST_10_9_SYMBOLS`, commenting that the shared default "only covers os_unfair_lock +
   os_log single-underscore".
2. **openssh, 2026-09-13** — a patch called `launch_activate_socket()` (10.10-era, undeclared in the
   10.9 SDK). It compiled, linked, and the guard said `1 binaries clean ... no post-10.9 imports`.

The 10.9 SDK is **frozen**, so an allowlist derived from it is complete by construction, and
`fetch_sdk.sh` already pins the SDK by hash so the two cannot drift.

**Already tried and rejected — do not repeat:** a naive union of *every* exported symbol in the SDK.
703 dylibs/stubs yield 214,822 symbols (7.2 MB; 1.4 MB gzipped) and it wrongly approves
`_clock_gettime` (exported by `CoreWiFi.framework`, which bundles its own — nothing links CoreWiFi)
and `_launch_activate_socket` (exported by `usr/lib/system/libxpc.dylib`). Scope the allowlist to
**the libraries a product actually links** — its link line, or `otool -L` of the built binary —
taking each library's exports from the pinned SDK. That mirrors how the linker resolves.

**Honest limits.** It would *not* have caught the openssh case: libxpc genuinely exports that symbol
in the SDK and on a running 10.9.5 box (the call links and returns `ENOTSUP`). That defect was
source-level — undeclared, so the compiler guessed an SPI's prototype — which is item 3's job. It
catches "does not exist", not "exists but is unavailable here". **Weak imports must survive:**
swift-runtime permits some post-10.9 families *only* when imported weak, and deliberately refuses
`os_unfair_lock` because its runtime calls it unguarded.

**Language coverage is free** — the guard reads Mach-O via `nm` and does not care what produced the
binary, so unlike item 3 this protects every product, not just the C ones.

## 3. Adopt `-Werror=implicit-function-declaration` as a family default, with an opt-out

Apple's old clang treats an undeclared function as a *warning*, so the openssh case compiled, linked,
passed the guard, and buried the only real signal in a 5,800-line log. An undeclared function is also
worse than it looks: the compiler invents a prototype, and here that was an SPI.

**Nothing breaks today** — zero `implicit declaration` hits across all 12 reachable products' most
recent successful `release` runs on main (2026-09-13 survey).

**But the shared CMake line is the wrong lever.** `Mavericks.cmake:29`'s `add_compile_options` is the
one shared site, yet for 5 of 6 consumers it governs a *single generated ObjC file compiled against
the modern SDK* — nearly inert. The heavy C, the 10.9 SDK, and the motivating bug live in per-repo
shell scripts, and shipyard has **no shared CFLAGS**. Seven sites, six repos:
`openssh/build/build-openssh.sh:27`, `openssh/build/build-libressl.sh:58`,
`macports-legacy-support/build/build-lib.sh:19`, `ed25519/build/build-tools.sh:29,31`,
`porthole/build/fetch-s6.sh:15`, golang's `build-{cross,native}.sh` clang wrappers,
`swift-toolchain/build-llvm.sh:35`. Suggested vehicle: `MAVERICKS_STRICT_CFLAGS` in `scripts/lib.sh`.

**Scope: 5 products, not 13.** openssh (~300 TUs), magic-trackpad2, macports-legacy-support (44
files), porthole, ed25519 compile meaningful C/ObjC. Four others compile 1-6 ObjC updater TUs;
swift-toolchain's C is vendored LLVM; 1password and signal-desktop compile none.

**Opt-out:** mirror `MAVERICKS_REQUIRE_APPLECLANG` for the switch, plus a glob-scoped
`- implicit-decls[:<glob>]: <reason>` in `INGREDIENTS.md` — `deviations.sh` already exits 1 on a
reasonless entry and `check-family-conventions.sh` already has the `deviated <check> <path>` helper.

**Gating precondition — do not skip.** Injecting this into `CFLAGS` *before autoconf* can silently
flip feature detection: a probe that fails reads as "feature absent". Rerun openssh's and libressl's
`./configure` with and without the flag and diff `config.log` first.

**Two dead ends, recorded.** `/usr/bin/clang` on the 10.9 box (Apple LLVM 6.0) rejects
`-Wunguarded-availability`, `-Wunguarded-availability-new` and `-Wpartial-availability` as unknown,
and the 10.9 SDK carries no availability annotations — so that flag is only worth adding,
`check_c_compiler_flag`-guarded, on the modern-SDK CMake surface (and its `-new` variant defaults to
a 10.13 threshold, leaving 10.10-10.12 uncovered). Unsettled: whether the macos-26 AppleClang 21
runner already errors on this by default; one probe job settles it.

## 4. Convention: fix Renovate blockers on the PR's branch, not by bypassing to main

When a Renovate PR is blocked by something in the source tree, push the fixing commits to
`renovate/<whatever>` so the PR goes green and automerges. Do not fix on main and leave the PR
superfluous.

The model here is ship-if-green automerge: Renovate proposes, the build gates, the bot merges. Fixing
on main puts an agent on the one path with no PR-time gate, closes the PR as "already up to date" so
the bump was never Renovate-driven, and risks breaking main when fix and bump are only correct
together.

**The case (openssh, 2026-09-13).** Renovate #4 proposed OpenSSH v10, blocked because three vendored
Apple patches no longer applied. Patch rewrites and version bump are *only valid together* — the new
patches do not apply to 9.9p2. The agent reasoned "therefore one atomic commit to main" and pushed.
The atomicity constraint was real; the inference was not. **Pushing the patch commits onto the
Renovate branch satisfies both.** Refreshing a stale branch needs no push either: every Renovate PR
body carries a `- [ ] <!-- rebase-check -->` checkbox.

**Exception:** a blocker genuinely independent of the bump — wrong at the old version too — is fixed
on main and Renovate rebases. Test: does the fix make sense *without* the bump?

Belongs in the conventions skill, near the Renovate & automerge section. Documentation, not a gate.

## 5. Convention: show the diff before shipping agent-authored code

Before an irreversible step that ships code the agent **authored** — written or substantively
re-derived, as opposed to moved unchanged or already reviewed — put the actual diff in front of the
human, not a description of it. Weighted heavily when the code is security-sensitive (openssh,
ed25519, the signing path), when the push auto-releases to users via Sparkle, and when the agent made
judgment calls a summary cannot convey.

**Why prose is not a substitute:** "ported the patches, verified natively" is equally consistent with
a correct port and a subtly wrong one. Authorization granted on that basis is not informed
authorization, and closing that gap is the agent's job, not the human's.

**The case (openssh, 2026-09-13).** Three vendored patches re-derived for 10.5p1, built and tested
natively, then pushed to main on an instruction given without the human having seen any code; two
releases went out. The work demonstrably needed review — the agent found three of its own errors
mid-flight: an `add_file()` call passing 8 arguments to a 9-parameter function, a wrong launchd API
choice, and a false claim about libSystem already committed to a repo.

**What a good review artifact looks like here:** not the vendored `.patch` files, whose diffs are
diffs-of-diffs and unreadable — the **effective change to the upstream source** (patched tree vs
pristine tarball), plus an explicit split between what carried over unchanged from the previous
patch set and what the agent authored this time. In the openssh case that reduced "we ported OpenSSH
to 10.x" to six reviewable items, four of them one-liners.

Suggested default: openssh, ed25519, and anything touching signing or key handling get a diff-first
pause regardless of how routine the change looks.

## 6. `docs/` should be committable; `docs/superpowers/` must never be

Superpowers plans, specs and SDD ledgers are **ephemeral working material** and must never be
committed. Everything else under `docs/` is ordinary documentation and should be.

Today the family ignores the wrong thing, inconsistently:

| repo | rule |
|---|---|
| shipyard, openssh, golang, container-tools, swift-runtime, ed25519, porthole | `docs/` — ignores everything |
| **magic-trackpad2** | `/docs/superpowers/` — **correct; this is the shape to standardise on** |
| tailscale | no rule at all |

Ignoring all of `docs/` costs something real: it makes `docs/` unusable for documentation anyone else
can read, so useful material either goes somewhere odd or stays local. It also silently hides work —
on 2026-09-13 a session "preserved" a plan ledger and two research write-ups into
`shipyard/docs/superpowers/specs/`, which felt like archiving and was in fact machine-local invisibility.

**Wanted:**
1. Every repo's `.gitignore` narrows `docs/` to `/docs/superpowers/` (magic-trackpad2 already has it;
   tailscale needs the rule added).
2. New-project scaffolding emits the narrow rule, not the broad one.
3. The conventions skill says which is which and why.
4. A conventions check, and it must assert **both directions**: `docs/superpowers/` IS ignored (an
   ephemeral plan must never be committable) and `docs/` as a whole is NOT (documentation must be).
   A one-directional check would let the current broad rule keep passing.

## 7. Parked findings from the release-notes enforcement work (2026-09-12)

Recorded in that plan's SDD ledger, which is gitignored and therefore machine-local — hence copied
here. All were deliberately not-fixed with reasons; none is urgent; each is small.

- **`ref_moved` is not `$exclkey`-aware** (`scripts/ingredient-notes.sh`). If a repo passed
  `path:REF` on a `REPO`/`REF`/`DIGEST` component file, a real `DIGEST` move would be suppressed and
  the file would report **nothing**. That is the silent-nothing class, which bit this work four
  separate times. **Fix is one condition:** only set `ref_moved=yes` when `REF` is not the excluded
  key. Unreachable today — `own-upstream-paths` is only ever `pins.env:SWIFT_VERSION`-shaped, never a
  component triple — which is the only reason it was parked.
- **A decoy tag that proves less than it looks** (`tests/previous-release-tag-test.sh`).
  `20260802-rc1` does reach `numeric()`'s skip, but `ver_cmp` defaults a missing component to 0, so
  it loses on ordering even with the skip disabled entirely — verified by mutating both. Wants a
  decoy that would otherwise sort HIGHEST, e.g. `20260899.9-rc1`.
- **A hardcoded example in a fatal message** (`scripts/release-notes.sh`). The unmatched-`--line`
  error ends with a literal `(1.26, not 126)` instead of deriving the shape. Harmless while golang is
  the only `--line` consumer; the day a second product adopts `--line`, it quotes golang's example at
  an unrelated operator.
- **`v1` satisfies a `## Shipyard 1.0.209` title** via the bare `1` after v-stripping
  (`scripts/check-release-notes.sh`). Unreachable: the `v1` major tag is moved by a separate job that
  never calls `publish-release.yml`.
- **A whitespace-only notes file passes conformance.** It renders to nothing, so both digests become
  sha256-of-empty and agree. Caught upstream by `check-release-notes.sh`'s "empty apart from
  whitespace"; defence-in-depth only.
- **`inside == 0 exit` in the appcast CDATA extractor** is unnecessary today — one `<item>` per
  appcast.

**And one that is not small, recorded by the final whole-branch review:** *nothing in any of the
three enforcement layers checks that a body actually **has** its compare link or ingredient section.*
Tasks 1 and 3 closed the two reachable causes; a third cause would be invisible. This needs a real
answer to "when is absence legitimate?" before it can be a check — a genuine first release and a
self-upstream product with no baseline both legitimately lack a compare link. Design work, not a
task.
## 8. Comments gate: two blind spots in `check-comments.sh`

**Cannot see inside heredocs.** ~40 lines of prose in `package-pkg.sh`'s rendered pre/postinstall —
including the whole R-P1-24 two-updaters-forever reasoning — will never be swept or re-checked. Known
limitation in the comments spec; demonstrated during the shipyard-cmake collapse, 2026-09-13.

**Ignores trailing comments entirely.** `ci.yml`'s untagged `# the CMake modules gate on Apple clang`
passes only because it shares a line with code. This is ruling 3's deliberate scope exclusion, now with
a live example.

## 9. No consumer repo documents how to obtain shipyard outside CI

All 14 surveyed 2026-09-13; the real instructions live in code comments, CLAUDE.md, or test scripts. The
shipyard-cmake cutover makes this worse — a developer now needs shipyard-cmake installed — and only
macho-tools' README was fixed, because there the existing text became actively false rather than merely
absent.

## 10. 1password's `cmake-10_9-gate` job cannot succeed as checked out

It runs `cmake --preset cross` against a "Porthole viewer", but the repo has no CMakeLists.txt, no
CMakePresets.json and no Porthole source. Pre-existing and unrelated to the flag day, which deliberately
left it alone (flag-day spec D8).

## 11. Check 18 has three blind spots, and real breakage hid in all of them

It reads workflow `run:` blocks plus `git ls-files -- '*.sh'` minus `tests/`, so `*.bats`, `tests/*.sh`,
extensionless executables, `*.cmake` and `CMakeLists.txt` are invisible; and it ignores a bare `(` even
inside files it does read.

**Concrete evidence, all found during the 2026-09-13 cutover:** porthole's
`tests/test_standalone_build.bats` ran a real configure that CI executes via `run-repo-tests.sh`;
porthole's extensionless `bin/generate-viewer` printed the build recipe users follow; and five
`echo "... (build it: cmake --build ...)"` recipes across clang, golang, openssh and swift-runtime.

Across the fourteen repos the gate saw a **minority** of the real call sites — magic-trackpad2 was 4
visible against 18 invisible, macho-tools 2 of 12, macports-legacy-support 2 of 10.

A gate that reports `ok` because it did not look is worse than no gate, because the `ok` is believed.

## 12. Check 16 has two blind spots of its own

It matches only `.cmake/package[s]`, so a locator reading `$HOME/.local/share/cmake/...` is invisible —
clang and golang each carried a second locator in `build/versions.sh`, and swift-runtime two more in
`package.sh` and `scripts/guard.sh`.

It also skips `tests/` entirely, so a locator there can match its pattern exactly and still never be
reported — magic-trackpad2's `tests/test_appcast_notes.sh` read `~/.cmake/packages/MavericksShipyard`
and the gate said nothing.

## 13. shipyard's CI never exercises the consumer path of `install/action.yml`

**This is the most valuable finding of the 2026-09-16 cutover.** shipyard's own workflows use
`uses: ./.github/actions/install` — the LOCAL path — where `github.action_ref` is populated differently
than for a consumer pinning `@v1`. Every gate, test and review we ran exercised only the path that
works.

The cutover replaced a warn-and-continue with a hard `exit 1` when the ref would not resolve. That read
as tightening, and it was — but on a condition nobody had measured. `github.action_ref` is **empty** for
a consumer calling the action, so the released version broke **all 14 consumers at once**, at the first
step, before reaching anything the cutover actually changed. Fixed forward in `8c46891` by falling back
to `basename "$root"`, but nothing would have caught it before release.

What is missing is a CI job that consumes shipyard the way a consumer does — pinned by ref, from
outside the repo — rather than by relative path. Until that exists, any change to the install action is
tested only on the half of its behaviour shipyard itself uses.

## 14. `gh run rerun` cannot validate anything in this family

A re-run makes `github.action_ref` empty, so `install@v1` fails at the first step with
`'' names no shipyard release`. The re-run therefore fails EARLIER and for a DIFFERENT reason than the
original run — which reads as "nothing changed / the fix did not work" and cost real debugging time on
2026-09-16.

Two consequences worth writing down. To force a genuine fresh run on a PR, close and reopen it; that
re-triggers `pull_request` workflows with proper context and adds no commits. But repos whose workflows
trigger only on `push` (swift-runtime and swift-toolchain use `branches: ['**']` with no
`pull_request:`) ignore close/reopen entirely and need an actual push.

Entry 13's fix would also make this less sharp, since the fallback covers the re-run case too.

## 15. The major tag could move backwards (fixed 2026-09-16, recorded so it is not reintroduced)

`major-tag` force-pushed `v1` onto its own run's commit unconditionally. Two overlapping releases
therefore raced, and whichever job finished LAST won regardless of which commit was newer. On
2026-09-16 a Renovate release and a fix release overlapped, `v1` landed on the OLDER commit, and every
consumer resolved a stale action for about 40 minutes.

Fixed in `938f902`: the tag moves only forward, skipping when `v1` already points at a descendant.
Recorded here because the bug was latent for as long as the job has existed and only surfaced once two
releases happened close enough together — which is to say, it will not resurface as a symptom until the
next time someone ships quickly, long after anyone remembers why the guard is there.

## 16. No way to pause automerge for a planned window

Renovate merged `mavericks-clang` `.1 -> .2` (PR #11) at 17:40 on 2026-09-16, during a cutover where we
had deliberately decided to hold it. It did exactly what `default.json` tells it to: checks were green,
so it shipped.

**This is NOT an argument for restricting automerge on that pin.** The exception rule's test is whether
a green build can catch a bad bump, and for `mavericks-clang` it demonstrably can — CI verifies the pkg
against its SHA256SUMS, rebuilds shipyard-cmake with it, runs the compat guard over the output and the
full suite through the result. The bump was fine and was kept. The 40-minute stale-action window
belonged to entry 15, not to this merge.

The real gap is narrower: there is no mechanism for a TEMPORARY hold while something risky is in
flight. Possibly not worth building — the family has already decided fix-forward beats human review of
routine bumps, and this day is evidence for that policy rather than against it. Recorded so the
question is asked deliberately rather than rediscovered mid-incident.

## 17. A repackage publishes even when the product did not change

`repackage-on-ingredient-bump.yml` dispatches a `local_release` whenever a push to main touches its
path filter. In swift-runtime that filter is `build.sh` and `patches/**`. On 2026-09-21 the
out-of-tree adoption commits changed where `build.sh` puts its build directory and nothing about what it
builds, and that was enough: `6.3.3-mavericks.7` shipped to Sparkle users with no change in it.

A path filter answers "might the product have changed?", which is the wrong question for deciding to
publish. The right one is "did it change?". Answer it by comparing what this run built against the last
release's assets. The digests already exist, since `publish-release.yml` regenerates `SHA256SUMS`, so
this needs no new machinery. Two cautions:

- **The build must be reproducible for the comparison to mean anything.** An embedded timestamp or a
  pkg's own metadata will differ on every run and make every build look new. Measure which bytes
  differ between two builds of one commit before trusting a digest. A comparison that is always
  "changed" is the current behaviour with extra steps.
- **Every repo with a repackage trigger has this,** not only swift-runtime. openssh and swift-toolchain
  carry the same workflow.

## 18. Two repackages close together race for the same `-mavericks.N`; the loser is dropped silently

Also 2026-09-21, swift-runtime. Two adoption commits (`88b1b14`, `9a7fabd`) each dispatched a
repackage. Both runs resolved `version=6.3.3-mavericks.7` near 07:54, because `version.sh local`
computes N+1 from the tags that exist when the build **starts**. The first published `.7` at 08:01:28.
The second reached publish at 08:02 and failed at "Refuse an already-taken tag" (run 35575078755).

The guard did its job: no double publish, no overwritten release. But nothing retried, so the second
commit's change was never released. It was CI-only this time and harmless. Next time it could be a
real fix, and the only sign would be one red run that reads like a duplicate.

Why concurrency cannot fix this: publishing runs are keyed per `run_id` deliberately, because GitHub keeps
only the newest PENDING run per group and silently evicts the rest (golang lost a release that way
on 2026-09-09). Queuing them is exactly what already failed. The fix belongs in the version, not the
queue: either resolve N at publish time and not build time, or on a taken tag re-resolve and retry
once with the next N. Either way, take the assets from the loser's own build and don't rebuild. Item 17
interacts with this: if the loser's product is identical to what the winner shipped, the right outcome
is to skip publishing, not to take `.8`.

## 19. `assert-tree-clean.sh` warns "prune it" falsely in shipyard's own `ci.yml`

`.mavericks-intree` declares `VERSION` and `dist/`. Only `release.yml`'s build job writes them, but
the stale-allowlist check runs in every job that calls the assertion. Both of `ci.yml`'s jobs therefore
print:

    assert-tree-clean: .mavericks-intree allows 'VERSION', which nothing wrote -- prune it
    assert-tree-clean: .mavericks-intree allows 'dist/', which nothing wrote -- prune it

The exit code is 0, and `ci.yml` runs only on branches and pull requests, never on main, so it is rare
noise. It still matters, because a warning that is false on every run of the repo that owns the
mechanism teaches everyone to ignore it, and "a stale allowlist is how this rots" is the reason the
warning exists.

The allowlist belongs to the repo, while staleness belongs to one workflow. The obvious fixes each cost
something:

- **A flag on the bare call** (`--no-stale-check`) would not match check 19's bare-call pattern
  (`scripts/check-family-conventions.sh`), so a repo using only the flagged form would fail check 19.
  That coupling is worse than the noise.
- **An environment knob** (a `MAVERICKS_*` variable set in the jobs that build only part of the
  product) avoids the coupling and follows the family's existing idiom (`assert_binary_compatible.sh`
  has seven such knobs). It is probably the right shape.
- **Moving the stale check behind an opt-in** means most repos would never run it.

Recorded 2026-09-21 by the review of the out-of-tree work (finding M4). Deferred then, because a
new knob touching four files was out of scope for a fix round.

## 20. Reproducible builds as the convention for new repos, with deviations declared

Raised by the repo owner 2026-09-21, prompted by entry 17: "maybe reproducible builds should be the
convention for new org repos, and deviations documented."

**Why it is worth making a convention rather than a per-repo nicety.** Entry 17's fix, publishing a
repackage only when the product changed, is only as good as the answer to "did it change?". That answer
is a digest comparison, and a digest comparison is meaningful only for a reproducible build. Without
reproducibility, every build looks new and entry 17 changes nothing. Reproducibility also makes
the cross build versus 10.9 native equivalence claims (macho-tools' `characterize`) checkable by digest
rather than by bespoke comparison.

**The shape, following how the family already handles conventions:**

- **Stated in the conventions skill**, as the default for a NEW repo.
- **Checked by building twice.** CI builds the same commit twice and compares the artifact digests.
  A check that only reads files cannot see an embedded timestamp.
- **Deviations declared** in `INGREDIENTS.md`'s `## Conformance deviations`, with the existing
  `- <name>: <reason>` grammar (`- comments:` already works this way), so a repo that cannot be
  reproducible says why, and the reason surfaces in the artifact facts.
- **Existing repos are measured, not assumed.** Build each one twice and record what differs. Some
  will already be reproducible, and some will need a deviation or a fix.

**Known sources of difference to measure first, not a list of fixes:** timestamps embedded by
`pkgbuild`/`productbuild` and in archives; code signatures with a secure timestamp, which differ per
signing, so the comparison may have to be of the pre-signature payload; `__DATE__`/`__TIME__`;
absolute build paths embedded in debug info or `__FILE__`, which the out-of-tree move to
`$RUNNER_TEMP` may make worse, since that path can differ per run; and the order in which files
are archived. Which of these actually bite in this family is unknown until measured.

Depends on nothing. Entry 17 depends on this.
