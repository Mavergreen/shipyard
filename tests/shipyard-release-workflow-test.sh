#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "shipyard: consume its facilities" -- "A repo that ships the tooling publishes
#       itself with the commit under test, not with @v1", and the 2026-09-09 conventions-check-7d
#       incident that rule prevents a repeat of.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$here/../.github/workflows/release.yml"
[ -f "$w" ] || { echo "FAIL: no release.yml"; exit 1; }

python3 - "$w" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))

pub = [j for j in wf["jobs"].values() if "publish-release.yml" in (j.get("uses") or "")]
if not pub:
    print("FAIL: no job calls publish-release.yml"); sys.exit(1)
p = pub[0]

# A LOCAL uses: path resolves to this very commit. `@v1` would be the previous version's workflow.
if not (p.get("uses") or "").startswith("./"):
    print("FAIL: publish must be called by local path (./.github/...), not a @ref: %r" % p.get("uses")); sys.exit(1)

ref = str((p.get("with") or {}).get("shipyard-ref", ""))
if "github.sha" not in ref:
    print("FAIL: shipyard-ref must be github.sha, not %r -- else release-assets.sh comes from @v1" % ref); sys.exit(1)

# Trigger: every push to main, so the version cannot fall behind the content.
on = wf.get("on") or wf.get(True)
branches = ((on.get("push") or {}).get("branches")) or []
if "main" not in branches:
    print("FAIL: release.yml must trigger on push to main; got %r" % (branches,)); sys.exit(1)

# The publishing side must be alone in its concurrency group (check 1b).
grp = str((wf.get("concurrency") or {}).get("group", ""))
if "github.run_id" not in grp:
    print("FAIL: concurrency group must be keyed per run: %r" % grp); sys.exit(1)
print("ok: publishes from the commit under test, on every push to main, alone in its group")
PY
python3 - "$w" <<'PY'
import re, sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))

# Inspect COMMANDS, never the file's text: release.yml's comments name every one of these scripts and
# flags, so a substring search stays green after the invocation itself is deleted. Take every step's
# parsed `run:` body, drop whole-line comments, and join backslash continuations so one command is one
# line. (Only whole-line comments: a trailing '#' cannot be told from ${x#v} without a shell parser.)
def step_cmds(step):
    lines = [l for l in (step.get("run") or "").splitlines() if not l.lstrip().startswith("#")]
    joined = re.sub(r"\\\s*\n\s*", " ", "\n".join(lines))
    return [" ".join(l.split()) for l in joined.splitlines() if l.strip()]

cmds = []
for job in (wf.get("jobs") or {}).values():
    for step in (job.get("steps") or []):
        cmds += step_cmds(step)

def find(pattern):
    return [c for c in cmds if re.search(pattern, c)]

bad = []
def need(pattern, why):
    if not find(pattern):
        bad.append(why)

build = wf["jobs"]["build"]
build_steps = build["steps"]

# spec: 2026-10-24 macOS runner exit -- building, packaging, signing and conformance are host-agnostic.
if not str(build.get("runs-on", "")).startswith("ubuntu-"):
    bad.append("the build job must run on ubuntu-*, not %r" % build.get("runs-on"))

# shipyard cannot install a RELEASED shipyard to test the commit about to become one. On Linux,
# install@v1 by local path hands the job this checkout's shell half, which is that commit.
inst = [s for s in build_steps if str(s.get("uses", "")) == "./.github/actions/install"]
if not inst:
    bad.append("the build job must use ./.github/actions/install by local path, on its Linux path")
# spec: 2026-10-09 C4 -- CMake is the cmake product's, which install@v1 installs at shipyard's pin.
#       shipyard builds none, so nothing hands install@v1 a tree.
elif "cmake-tree" in (inst[0].get("with") or {}):
    bad.append("the build job still passes cmake-tree to install@v1; shipyard builds no CMake now")
if any(str(s.get("uses", "")) == "./.github/actions/shipyard-cmake" for s in build_steps):
    bad.append("the build job still runs ./.github/actions/shipyard-cmake; shipyard builds no CMake now")

need(r'^sh tests/lib/build-updater\.sh --arch x86_64 --arch arm64 --out "?\$RUNNER_TEMP/shipyard-updater\.app"?$',
     "the updater must be built for x86_64 and arm64 by tests/lib/build-updater.sh, with clang22")
if find(r"CMAKE_OBJC_COMPILER=/usr/bin/clang"):
    bad.append("release.yml still builds an updater with /usr/bin/clang; it builds with clang22 on every host")
# ...and the result is asserted, not assumed. The merge is NOT followed by a re-sign: lipo copies each
# slice byte for byte, so the ad-hoc signature ld gives the arm64 slice -- all Apple Silicon needs to
# run it -- survives, and nothing in shipyard's build seals this bundle for a re-seal to restore.
# `codesign --deep` in particular must not come back: the app carries Sparkle as a VERSIONED
# framework, which `--verify --deep` calls ambiguous on every runner (R-P1-22).
for arch in ("x86_64", "arm64"):
    need(r'^case " \$archs " in \*" %s "\*\) ;; \*\) echo "::error::the merged updater has no %s slice' % (arch, arch),
         "the merged updater's %s slice is never asserted after the merge" % arch)

# The pkg: shipyard's install prefix + the merged app. CMake is the cmake product's, never in the pkg.
need(r"^sh scripts/package-pkg\.sh .*--shipyard-prefix \S+ .*--app \S*/shipyard-updater\.app\"?",
     "release.yml never runs scripts/package-pkg.sh with --shipyard-prefix and the merged --app")
need(r"^sh scripts/package-pkg\.sh .*--dist dist(\s|$)",
     "release.yml must build the pkg into dist with --dist dist; its name is derived, shipyard-<v>.pkg")
if find(r"^sh scripts/package-pkg\.sh .*--out "):
    bad.append("release.yml still passes package-pkg.sh --out; the filename is derived, so it passes --dist")
need(r'^sh scripts/assert_pkg_installs_in_place\.sh "dist/shipyard-\$v\.pkg"$',
     "release.yml must gate dist/shipyard-$v.pkg, the pkg package-pkg.sh derives")
need(r'^sh scripts/sign_and_appcast\.sh .*--pkg-url "https://github\.com/Mavergreen/shipyard/releases/download/v\$v/shipyard-\$v\.pkg" .*--pkg "dist/shipyard-\$v\.pkg"$',
     "release.yml must sign dist/shipyard-$v.pkg and point the feed at that asset")
if find(r"--cmake-tree"):
    bad.append("release.yml still passes --cmake-tree; the pkg carries no CMake now")

# The built pkg is gated the way the family gates one: what the installer does on a box that has the
# previous version, and whether the artifacts agree with each other.
need(r"^sh scripts/assert_pkg_installs_in_place\.sh \S*\.pkg\"?$",
     "release.yml never runs scripts/assert_pkg_installs_in_place.sh on the pkg")
need(r"^sh scripts/shipyard-check --dist dist$",
     "release.yml never runs scripts/shipyard-check --dist dist")

need(r"^sh scripts/sign_and_appcast\.sh --product shipyard --feed-dir dist .*--pkg \S+\.pkg\"?$",
     "release.yml never runs scripts/sign_and_appcast.sh --product shipyard --feed-dir dist")

# shipyard's tags are vX.Y.Z. Without --tag-glob the upgradeable gate sees none of them, finds no
# previous release, and skips the ordering check on every release.
need(r"^sh scripts/assert_appcast_upgradeable\.sh .*--appcast dist/shipyard\.xml .*--tag-glob 'v\*\.\*\.\*'",
     "release.yml must run scripts/assert_appcast_upgradeable.sh on dist/shipyard.xml with --tag-glob 'v*.*.*'")

# release-notes.sh is called directly (no wrapper): --out writes the body straight to
# dist/RELEASE_NOTES.md. shipyard's own .pkg IS floored at 10.9.5 (package-pkg.sh builds it through
# set_install_floor.sh, whose default MIN_OS is 10.9.5 and which self-checks that floor lands in the
# built pkg), so the notes must pass --min-os 10.9.5 like every other repo's own release.
need(r"^sh \"\$SHIPYARD_SCRIPTS/release-notes\.sh\" --tag \"v\$v\" --version \"\$v\" --short shipyard --min-os 10\.9\.5 --out dist/RELEASE_NOTES\.md$",
     "release.yml must call release-notes.sh directly with --short shipyard --min-os 10.9.5 --out dist/RELEASE_NOTES.md")
need(r"^\[ -s dist/RELEASE_NOTES\.md \] \|\| \{ echo \"::error::release notes came back empty\"; exit 1; \}$",
     "release.yml lost the empty-release-notes guard")

# The tarball is retired: nothing consumed it, and GitHub ships source archives for free.
tars = find(r"(^|[\s;|&(])tar\s") + find(r"\.tar\.gz\b")
if tars:
    bad.append("the release tarball should be gone; the pkg is the asset now: %r" % tars[0])

# GNU binutils cannot read Mach-O and Linux has no lipo, so the updater merge's slice check and
# conformance's slice and SDK checks need clang22's tools, exported before the first of them.
def first(pat):
    return [i for i, s in enumerate(build_steps) if any(re.search(pat, c) for c in step_cmds(s))][:1]
users = first(r"^sh tests/lib/build-updater\.sh ") + first(r"^sh scripts/shipyard-check --dist dist$")
for tool in ("LIPO", "OTOOL", "NM", "STRINGS"):
    exp = [i for i, s in enumerate(build_steps)
           if any(re.search(r'^echo "%s=\$CL/bin/llvm-' % tool, c) for c in step_cmds(s))
           and '>> "$GITHUB_ENV"' in (s.get("run") or "")]
    if len(users) != 2 or not exp or exp[0] > min(users):
        bad.append("the build job never exports %s (clang22's llvm tool) to $GITHUB_ENV before the updater build and the artifact checks" % tool)

# Linux has no shipyard-cmake: install@v1's Linux path installs no pkg, so the payload is configured
# and installed with the runner's cmake.
if any(re.search(r"(^|[\s;|&(=])shipyard-c(make|test|pack)\b", c) for st in build_steps for c in step_cmds(st)):
    bad.append("the build job runs shipyard-cmake/ctest/cpack, which install@v1's Linux path does not provide")
need(r'^cmake -S \. -B "\$RUNNER_TEMP/payload-build"$',
     "the build job must configure the payload with the runner's cmake (cmake -S . -B \"$RUNNER_TEMP/payload-build\")")
need(r'^DESTDIR="\$RUNNER_TEMP/payload-stage" cmake --install "\$RUNNER_TEMP/payload-build" --prefix /usr/local/mavergreen/shipyard$',
     "the build job must install the payload with the runner's cmake (DESTDIR=... cmake --install ... --prefix /usr/local/mavergreen/shipyard)")

if find(r"^sudo (-n )?installer "):
    bad.append("release.yml installs a pkg on a runner; shipyard's release builds and publishes it, and runs no install")

# SPARKLE_PRIVATE_KEY reaches the signing step's env and the scan's secrets, nothing else.
jobs = wf.get("jobs") or {}
holders = []
for jn, job in jobs.items():
    if "SPARKLE_PRIVATE_KEY" in str(job.get("env") or ""):
        holders.append("%s (job env)" % jn)
    if jn != "scan" and "SPARKLE_PRIVATE_KEY" in str(job.get("secrets") or ""):
        holders.append("%s (secrets)" % jn)
    if str(job.get("secrets") or "").strip() == "inherit":
        holders.append("%s (secrets: inherit)" % jn)
    if "SPARKLE_PRIVATE_KEY" in str(job.get("with") or ""):
        holders.append("%s (with)" % jn)
    for st in (job.get("steps") or []):
        if "SPARKLE_PRIVATE_KEY" in (st.get("run") or ""):
            holders.append("%s step %r (run)" % (jn, st.get("name")))
        if "SPARKLE_PRIVATE_KEY" in str(st.get("with") or ""):
            holders.append("%s step %r (with)" % (jn, st.get("name")))
        signs = any(re.search(r"^sh scripts/sign_and_appcast\.sh ", c) for c in step_cmds(st))
        if "SPARKLE_PRIVATE_KEY" in str(st.get("env") or "") and not (jn == "build" and signs):
            holders.append("%s step %r (env)" % (jn, st.get("name")))
if "SPARKLE_PRIVATE_KEY" in str(wf.get("env") or ""):
    holders.append("the workflow's env")
if holders:
    bad.append("SPARKLE_PRIVATE_KEY reaches more than the signing step's env and the scan: %s" % ", ".join(holders))
if find(r"(^|\s)set -[a-z]*x"):
    bad.append("release.yml traces a step (set -x), which could print the signing key")

if "smoke" in jobs:
    bad.append("release.yml still has a smoke job; shipyard's release runs no VM job")
# The key scan stays between build and publish (another session's work; a rewrite must not drop it).
if "scan-for-key.yml" not in str((jobs.get("scan") or {}).get("uses", "")):
    bad.append("the scan job (./.github/workflows/scan-for-key.yml) is gone")
if "canary" in jobs:
    bad.append("release.yml still has a canary job; shipyard runs no macOS job, and @v1 moves once publish succeeds")
if sorted((jobs.get("major-tag") or {}).get("needs") or []) != ["build", "publish"]:
    bad.append("major-tag must need exactly [build, publish], so @v1 never names a release that did not publish")
if sorted((jobs.get("publish") or {}).get("needs") or []) != ["build", "linux", "scan"]:
    bad.append("publish must need exactly [build, linux, scan]")
if "build" not in ((jobs.get("scan") or {}).get("needs") or []):
    bad.append("the scan job must need build, to scan its artifact and logs")

# Nothing of the superseded design survives in any command: no user package registry, no second
# "cross" updater app, no postinstall picking a slice by hw.optional.arm64.
for gone in (r"cmake/packages", r"register-with-cmake", r"CrossUpdater", r"hw\.optional\.arm64"):
    if find(gone):
        bad.append("release.yml still runs something mentioning %s" % gone)

if bad:
    for b in bad:
        print("FAIL: " + b)
    sys.exit(1)
print("ok: built and signed on Linux, scanned and checked on Linux before publish, @v1 moved after publish")
PY

# spec: .github/actions/install/action.yml -- the other half of the same design: a consumer gets the
#       PKG at the ref it pinned, and only shipyard itself builds from source.
python3 - "$here/../.github/actions/install/action.yml" <<'PY'
import re, sys, yaml
a = yaml.safe_load(open(sys.argv[1]))
bad = []
if a.get("inputs"):
    bad.append("install@v1 takes no inputs: it installs the release its ref names, and its source: build "
               "path for shipyard's own retired macOS test job is gone; got %r" % sorted(a["inputs"]))
if "'build'" in open(sys.argv[1]).read():
    bad.append("install@v1 still has a source: build path; no workflow uses it")
if "release-version" in (a.get("inputs") or {}) or "inputs.release-version" in open(sys.argv[1]).read():
    bad.append("install@v1 still has a 'release-version' input; only the retired release canary passed it")
steps = (a.get("runs") or {}).get("steps") or []

# R-P1-19. NO local `uses: ./...` may appear in this composite, ever. GitHub resolves such a path
# against GITHUB_WORKSPACE -- the CONSUMER's checkout, which has none of shipyard's actions -- and it
# prepares nested actions BEFORE evaluating step `if:` conditions, so an `if:` on
# such a step does not spare a consumer: their job dies with "Can't find 'action.yml'"
# for a step that was never going to run. shipyard's own CI cannot catch it, because its workspace IS
# shipyard and the path resolves there. The caller runs the composite and passes its output in.
for s in steps:
    u = str(s.get("uses", ""))
    if u.startswith("./") or u.startswith("../"):
        bad.append("install@v1 nests a LOCAL action (uses: %s). Every consumer would fail with "
                   "\"Can't find 'action.yml'\", and shipyard's CI could never reproduce it -- the "
                   "calling workflow must run it and pass the result in as an input (R-P1-19)" % u)
def cmds(pred):
    out = []
    for s in steps:
        if pred(str(s.get("if", ""))):
            lines = [l for l in (s.get("run") or "").splitlines() if not l.lstrip().startswith("#")]
            out += [" ".join(l.split()) for l in re.sub(r"\\\s*\n\s*", " ", "\n".join(lines)).splitlines() if l.strip()]
    return out
# The release path has TWO branches (R-P1-18): macOS installs the pkg, everything else exports
# shipyard's shell half out of the action's own checkout. They are separate STEPS with separate `if:`
# expressions, so "the non-macOS branch installs nothing" is a claim this can actually check -- inside
# one step's shell `if`, both halves would land in the same flat command list and be indistinguishable.
rel_mac = cmds(lambda c: "runner.os == 'macOS'" in c)
rel_oth = cmds(lambda c: "runner.os != 'macOS'" in c)

def exports(cs, name):
    """Set in GITHUB_ENV, so LATER STEPS see it. A diagnostic `echo "... NAME=$x"` mentions the name
    without exporting anything -- and both modes print one, so a bare substring search for the name
    stays green after the export itself is deleted."""
    for i, c in enumerate(cs):
        if not re.search(r'(^|[\s"{])%s=' % name, c):
            continue
        if re.search(r'>> "\$GITHUB_ENV"$', c):
            return True
        for later in cs[i + 1:]:          # a { ... } group: the redirect rides the closing brace
            if re.match(r'^\}\s*>> "\$GITHUB_ENV"$', later):
                return True
            if later.startswith("}"):
                break
    return False

for pat, why in ((r'resolve-action-version\.sh', "the macOS release path never resolves its ref to a version"),
                 (r'fetch-release-pkg\.sh" shipyard "v\$ver" "shipyard-\$ver\.pkg" ', "the macOS release path never downloads the release's pkg through fetch-release-pkg.sh (retried, verified against SHA256SUMS)"),
                 (r'^sudo installer -pkg "\$pkg" ', "the macOS release path never installs the pkg it fetched")):
    if not any(re.search(pat, c) for c in rel_mac): bad.append(why)
if not exports(rel_mac, "SHIPYARD_SCRIPTS"):
    bad.append("the macOS release path never exports SHIPYARD_SCRIPTS")
# Consumer-facing: every product's CI calls shipyard-cmake by bare name and reads $SHIPYARD_SCRIPTS.
# The pkg exports its commands through the link farm, which only paths.d puts on PATH -- and a
# runner's steps never read paths.d.
if not any(re.search(r'^echo /usr/local/mavergreen/bin >> "\$GITHUB_PATH"$', c) for c in rel_mac):
    bad.append("the macOS release path never puts /usr/local/mavergreen/bin on the job's PATH "
               "(echo /usr/local/mavergreen/bin >> \"$GITHUB_PATH\"), so no later step finds shipyard-cmake")
if not any(re.search(r'^scripts=/usr/local/mavergreen/shipyard/share/cmake/MavergreenShipyard/scripts$', c) for c in rel_mac):
    bad.append("the macOS release path must export SHIPYARD_SCRIPTS from the installed product "
               "tree, /usr/local/mavergreen/shipyard/share/cmake/MavergreenShipyard/scripts")

# R-P1-18: a non-macOS runner gets shipyard's shell half, pinned to the ref, and nothing installed.
# repackage-on-ingredient-bump.yml runs on ubuntu-latest and wants exactly that.
if not rel_oth:
    bad.append("install@v1 has no non-macOS release path; ubuntu jobs that want only shipyard's "
               "shell half (repackage-on-ingredient-bump.yml) would fail (R-P1-18)")
else:
    if not exports(rel_oth, "SHIPYARD_SCRIPTS"):
        bad.append("the non-macOS release path never exports SHIPYARD_SCRIPTS")
    if not any("GITHUB_ACTION_PATH" in c for c in rel_oth):
        bad.append("the non-macOS release path must take its scripts from the action's OWN checkout "
                   "($GITHUB_ACTION_PATH/../../..), which is shipyard at the ref the consumer pinned")
    # R-P1-23: find_package(MavergreenShipyard) has to RESOLVE there too -- container-tools' two
    # ubuntu-latest jobs do exactly that. SHIPYARD_SCRIPTS alone does not make find_package work.
    if not exports(rel_oth, "MavergreenShipyard_DIR"):
        bad.append("the non-macOS release path never exports MavergreenShipyard_DIR, so "
                   "find_package(MavergreenShipyard) cannot resolve on a Linux runner (R-P1-23)")
    if not any(re.search(r'^\[ -f "\$root/MavergreenShipyardConfig\.cmake" \] \|\|', c) for c in rel_oth):
        bad.append("the non-macOS release path exports MavergreenShipyard_DIR without checking the "
                   "config is actually there; a wrong path would surface as a consumer's find_package failure")
    for pat, why in ((r'^sudo installer', "installs a pkg"),
                     (r'^gh release download|fetch-release-pkg\.sh', "downloads a release asset")):
        if any(re.search(pat, c) for c in rel_oth):
            bad.append("the non-macOS release path %s; there is no Linux pkg to install" % why)

# R-P1-18: no step may refuse a non-macOS runner; those jobs get shipyard's shell half instead.
for c in cmds(lambda c: True):
    if re.search(r'uname -s.*Darwin', c) and "exit 1" in c:
        bad.append("install@v1 fails on a non-macOS runner (%s) -- R-P1-18: it must hand those jobs "
                   "shipyard's shell half instead" % c)

# spec: 2026-10-09 C4 -- shipyard's launchers run the cmake product, and shipyard's pkg refuses to
#       install without it, so on macOS install@v1 installs the cmake product first, at the pin the
#       action's own checkout carries, verified against that release's SHA256SUMS.
cm_steps = [i for i, st in enumerate(steps)
            if "runner.os == 'macOS'" in str(st.get("if", "")) and "fetch-release-pkg.sh\" cmake " in (st.get("run") or "")]
sy_steps = [i for i, st in enumerate(steps)
            if "runner.os == 'macOS'" in str(st.get("if", "")) and "fetch-release-pkg.sh\" shipyard " in (st.get("run") or "")]
for pat, why in ((r'^v="\$\(\. "\$root/scripts/mavergreen-meta\.sh" && MAVERGREEN_REPO_ROOT="\$root" mg_value ingredients/cmake/VERSION\)" \|\| v=$',
                  "install@v1 never reads the cmake pin from its own checkout ($root/.mavergreen/ingredients/cmake/VERSION)"),
                 (r'^pkg="\$\(sh "\$root/scripts/fetch-release-pkg\.sh" cmake "\$v" "cmake-\$v\.pkg" "\$d"\)"$',
                  "install@v1 never fetches cmake-<pin>.pkg from the Mavergreen/cmake release <pin> through "
                  "fetch-release-pkg.sh (verified against that release's SHA256SUMS)")):
    if not any(re.search(pat, c) for c in rel_mac):
        bad.append(why)
if len(cm_steps) != 1 or len(sy_steps) != 1 or cm_steps[0] > sy_steps[0]:
    bad.append("install@v1 must install the cmake product in one macOS step BEFORE the one that installs "
               "shipyard, whose pkg refuses to install without it")

if any("cmake/packages" in c for c in rel_mac + rel_oth):
    bad.append("install@v1 still reads the CMake user package registry")
for b in bad: print("FAIL: " + b)
if bad: sys.exit(1)
print("ok: install@v1 installs the cmake product then the released pkg on macOS, and hands non-macOS jobs the shell half")
PY

# spec: 2026-10-09 C4 -- shipyard builds no CMake, so nothing of that build survives in the files
#       that drove it, comments included.
[ ! -e "$here/../.github/actions/shipyard-cmake" ] \
  || { echo "FAIL: .github/actions/shipyard-cmake still exists; shipyard builds no CMake now"; exit 1; }
for f in "$here/../.github/actions/install/action.yml" "$here/../.github/workflows/ci.yml" "$w"; do
  if grep -n -e 'cmake-tree' -e 'actions/shipyard-cmake' "$f"; then
    echo "FAIL: ${f##*/} still names cmake-tree or the shipyard-cmake action"; exit 1
  fi
done
bu="$here/lib/build-updater.sh"
merge="$(grep -v '^[[:space:]]*#' "$bu" | awk '/\\$/ { sub(/\\$/, ""); printf "%s", $0; next } { print }' | grep 'lipo-merge-tree\.sh' || :)"
case "$merge" in
  *'--require-archs "x86_64 arm64"'*) ;;
  *) echo "FAIL: tests/lib/build-updater.sh never merges the two updaters with lipo-merge-tree.sh --require-archs \"x86_64 arm64\""; exit 1 ;;
esac
case "$merge" in
  *--allow-differ*) echo "FAIL: tests/lib/build-updater.sh merges with --allow-differ; nothing in updater/Info.plist.in is arch-dependent, so a difference there is a defect to fix, not one to declare"; exit 1 ;;
esac
echo "PASS: shipyard-release-workflow"
