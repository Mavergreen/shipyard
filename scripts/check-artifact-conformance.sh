#!/bin/sh
# platform: host-agnostic
#   usage: check-artifact-conformance.sh                                (under shipyard-check --dist <dir>)
#          artifact-facts.sh dist "$VER" | check-artifact-conformance.sh
#          Under shipyard-check --dist, SHIPYARD_CHECK_DIST names the dist directory and
#          SHIPYARD_CHECK_VERSION the release's version, and the facts are produced here
#          (SHIPYARD_CHECK_REPO names the repo whose .mavergreen/deviations/ declares deviations; default the
#          current directory). Piped, it reads a fact stream on stdin (see artifact-facts.sh), one
#          record per line:
#            expected      <version>                              the version this release claims to be
#            upstream-kind <port|own>                             whether the repo ports an upstream or is its own
#            pkg           <file> <version> <floor> <identifier>  one per shipped .pkg
#            pkg-title     <file> <title|none>                    a product archive's Distribution title (%20-encoded)
#            pkg-arch      <file> <hostArchitectures|none> <before|none> <rule>  one per .pkg, read by arch_read_distribution (none none none: no Distribution)
#            component     <file> <identifier> <name|none>        one per component, in Distribution order; its pkg-ref name
#            installs      <file> <path>                          one per installed file or link (%20-encoded)
#            bundle        <file> <path> <CFBundleIdentifier>     one per top-level bundle
#            bundle-name   <file> <path> <CFBundleName|none> <CFBundleDisplayName|none>  one per top-level bundle (%20-encoded)
#            launchd       <file> <path> <Label>                  one per launchd job
#            launchd-program <file> <path> <program|none>         one per Library/LaunchDaemons plist: Program, else ProgramArguments:0 (%20-encoded)
#            script        <file> <component-id> <preinstall|postinstall> <interpreter|none>  one per install script: its #! line's first word (%20-encoded)
#            script-mentions <file> <component-id> <phase> <token>  one per admin-writable root that script's text names
#            payload-mode  <file> <path> <uid> <gid> <mode>       one per payload entry, its mode as ls spells it (%20-encoded; . is the volume root)
#            manifest      <file> <product> <identifier> <dir>    one per opt/mavergreen/<dir>/mavergreen.plist
#            manifest-outside <file> <path>                       one per entry of that manifest's outside (%20-encoded)
#            manifest-generated <file> <path>                     one per entry of that manifest's generated (%20-encoded)
#            product       <product>                              one per directory in the repo's .mavergreen/products/
#            floor         <product> <version>                    the product's floor (.mavergreen/products/<product>/floor, else 10.9.5)
#            target        <product> <glob>                       one per line of .mavergreen/products/<product>/target (%20-encoded)
#            derived       <product> <feed|none>                  the feed derived for it (mavergreen_name feed-url)
#            name          <product> <surface> <value>            mavergreen_name's value, at the expected version (%20-encoded)
#            app           <product> <noun|upstream|none>         how the product's .app is named
#            manifest-name <file> <name|none>                     that manifest's name (%20-encoded)
#            manifest-line <file> <line|none>                     that manifest's line
#            manifest-feed <file> <url|none>                      that manifest's feed
#            manifest-requires <file> <dep> <kind>                one per requires entry of that manifest
#            built-on-install <product>                           one per product whose .mavergreen/products/<product>/built-on-install exists
#            edition       <product> <edition>                    one per product whose .mavergreen/products/<product>/edition exists (%20-encoded)
#            repository    <owner/name>                           the repo the release is built in (mg_repo), when known
#            appcast       <file> <version> <enclosure> <length> <minos>  one per feed
#            appcast-title <file> <channel|none> <item|none>      that feed's channel and first item titles (%20-encoded)
#            appcast-requires <file> <dep> <kind>                 one per <mavergreen:requires> element of that feed
#            asset         <file> <bytes>                         one per file that will be published
#            standalone    <file> ok|fail [<finding>]             one per <short>-<version>-macos-<arch>.tar.gz, judged by check-standalone-archive.sh (%20-encoded)
#            standalone-text-unused <glob>                        a standalone-text deviation no archive used
#            standalone-flow <file> archive-first|pkg-first       one per standalone archive: whether its repo declares packaging/<short>.standalone-bundled
#            macho         <artifact> <path> <arch> <filetype> <minos> <sdk> <sha256>  one per shipped Mach-O slice
#            cxxabi-defines <artifact> <path> <arch> <symbol> <visible|hidden>  one per C++ runtime symbol a slice defines beyond Recaulk's back-fills
#            cxxabi-loads  <artifact> <path> <arch> <load-path>   one per libc++abi a slice loads other than /usr/lib's or libcxx22's (%20-encoded)
#            cxxabi-unjudgeable <artifact> <path> <arch>          one per linked slice with C++ exception tables that names no ___gxx_personality_v0
#            macho-load    <artifact> <path> <arch> <dylib|rpath> <value>  one per dylib load or rpath of a slice, for a product with a target file (%20-encoded)
#            uuid          <artifact> <path> <arch> <uuid>        one per linked (EXECUTE, DYLIB, BUNDLE) slice
#            load          <artifact> <path> <arch> <dylib>       one per dylib a linked slice loads (%20-encoded)
#            rpath         <artifact> <path> <arch> <n> <rpath>   one per LC_RPATH of a linked slice, n its order from 1 (%20-encoded)
#            weakbind-unsorted <artifact> <path> <arch> <symbol>  a linked slice whose weak-bind info is out of name order, and the first such symbol
#            oso           <artifact> <path> <arch>               one per linked slice that keeps a debug map
#            homepath      <artifact> <path> <string>             a string in a linked file naming /Users/<u>/, /home/<u>/ or /var/folders/ (%20-encoded)
#            dsym          <tarball> <path> <arch> <uuid>         one per DWARF slice in a *-dSYM.tar.gz
#            notes-render  <notes-file> <sha256>                  digest of gen_appcast.sh --render-notes
#            appcast-notes <appcast-file> [<sha256>]               digest of the appcast's <description> CDATA
#            kext          <file> <path> <id> boot|library        one per kext a "/" payload carries (%20-encoded)
#            kext-exception <file> <id>                           one per id stage_product.sh --boot-kext lists
#            excludelist-script <file> <script>                   a pre/postinstall touching AppleKextExcludeList itself
#            deviation     <check> <reason...>                    a declared, reasoned departure
#            abort         <reason...>                            the producer gave up here, and why
#            end-of-facts                                         the producer ran to completion (LAST line)
#          Facts rather than files: the agreement logic is testable without fabricating real .pkg
#          files, and extraction is exercised for real at package time.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact
#       conformance (checked at package time)" -- what this checks and why, on all three axes
#       (itself / neighbours / siblings), lives there.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
. "$SELF/sdk-pins.sh"
. "$SELF/deviation-reason.sh"
. "$SELF/lib/vercmp.sh"
. "$SELF/lib/arch-rules.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/conformance.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT  # template: 10.9 BSD mktemp requires one
facts="$tmp/facts"
chk_ran artifact-facts
if [ -n "${SHIPYARD_CHECK_DIST:-}" ]; then
  if [ -z "${SHIPYARD_CHECK_VERSION:-}" ]; then
    chk_fail artifact-facts "the release's version is unknown" \
      "conformance compares every artifact with the version the release claims, and none was given" \
      "export SHIPYARD_CHECK_VERSION=<the release version> before shipyard-check --dist"
    exit 1
  fi
  sh "$SELF/artifact-facts.sh" "$SHIPYARD_CHECK_DIST" "$SHIPYARD_CHECK_VERSION" "${SHIPYARD_CHECK_REPO:-.}" > "$facts" 2>"$tmp/facts.err" || :
  [ ! -s "$tmp/facts.err" ] || cat "$tmp/facts.err" >&2
else
  cat > "$facts"
fi

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact
#       conformance", "A truncated fact stream fails" -- every check below is a "stay quiet with no
#       records" check, so a truncated stream would pass them all; the producer's exit status is
#       discarded by the pipe (no pipefail), so a sentinel is the only structural fix. Checked here,
#       not via fail(), and abort checked first and separately: neither may be excused by a
#       deviation, or the switch-off would excuse the very check that notices switch-offs.
why="$(sed -n 's/^abort \(..*\)$/\1/p' "$facts" | head -1)"
if [ -n "$why" ]; then
  chk_fail artifact-facts "the artifacts could not be read to the end" \
    "artifact-facts.sh aborted: $why -- the fact stream cannot be trusted, so nothing was checked" \
    "fix what the reason names and rebuild; no deviation can excuse this check"
  exit 1
fi

if ! grep -q '^end-of-facts$' "$facts"; then
  chk_fail artifact-facts "the artifacts could not be read to the end" \
    "the fact stream is incomplete -- artifact-facts.sh did not run to completion (no end-of-facts record), so nothing was checked" \
    "re-run artifact-facts.sh and read its stderr for the cause; no deviation can excuse this check"
  exit 1
fi

shipyard_deviations - < "$facts" > /dev/null
deviation_reason() { shipyard_deviated "$@" || :; }  # $1 = check, $2 = subject (optional)

# spec: scripts/check-ids.tsv -- every id this script evaluates; a deviation declared under the name
#       a check had before it had an id (scheme, ingredients) still excuses it.
has() { grep -q "^$1 " "$facts"; }
kind_ran() {  # $1 = the fact kind the ids read, $2 = what it is called, then the ids
  _kr_kind="$1"; _kr_what="$2"; shift 2
  for _id in "$@"; do
    if has "$_kr_kind"; then chk_ran "$_id"; else chk_notrun "$_id" "no $_kr_what in this release"; fi
  done
}
chk_ran version-scheme
if has pkg || has appcast; then chk_ran version; else chk_notrun version "no .pkg or appcast in this release"; fi
kind_ran pkg .pkg identifier bundle-id launchd-label manifest base line install-path feed repository arch-host arch-target \
  pkg-name installer-title manifest-name app-name root-runs os-overwrite no-standalone standalone
kind_ran pkg-arch .pkg arch-distribution arch-floors
kind_ran appcast appcast enclosure length enclosure-url notes feed-title
kind_ran build-info "build record" variant-build-info
kind_ran macho Mach-O sdk-pin cxxabi
kind_ran uuid "linked Mach-O" debug-map dsym-asset
if grep -Eq '^macho [^ ]+ [^ ]+ [^ ]+ (EXECUTE|DYLIB|BUNDLE) ' "$facts"; then chk_ran link-rpath; chk_ran weak-bind-sorted
else chk_notrun link-rpath "no linked Mach-O in this release"; chk_notrun weak-bind-sorted "no linked Mach-O in this release"; fi

rule_of() {
  case "$1" in
    version-scheme) echo "a port's release version is <upstream>-mavergreen.N, and an own-upstream repo's is YYYYMMDD.N" ;;
    version) echo "every artifact names the version the release claims" ;;
    arch-distribution) echo "a pkg's Distribution declares hostArchitectures x86_64,arm64 and the OS range and installation-check its class gets from its host slices" ;;
    arch-floors) echo "a pkg's x86_64 floor is its product's, and its arm64 floor the highest minimum OS its arm64 host slices record" ;;
    identifier) echo "a pkg identifier is inside dev.mavergreen.*, and a product's is its derived one" ;;
    bundle-id) echo "an installed bundle's identifier is inside dev.mavergreen.*" ;;
    pkg-name) echo "a product's pkg and its component are named as derived from the product" ;;
    installer-title) echo "a product's Installer title is the one derived from the product" ;;
    feed-title) echo "a product's feed carries the channel and item titles derived from the product" ;;
    manifest-name) echo "a product's manifest carries the name derived from the product" ;;
    app-name) echo "a product's .app is named as its app file says, and its bundle name agrees with its filename" ;;
    launchd-label) echo "a launchd job's Label is inside dev.mavergreen.* and names its plist" ;;
    manifest) echo "a pkg that installs a product carries exactly one valid manifest, and installs only what it lists" ;;
    base) echo "a pkg that installs a product has dev.mavergreen.base as its first component" ;;
    line) echo "a lined product's manifest, version and repo agree about the line" ;;
    install-path) echo "a pkg installs only into its product's tree under opt/mavergreen and the places the OS dictates" ;;
    feed) echo "a product's manifest names its derived feed, and the dist carries <short>.xml unless it is built on install" ;;
    repository) echo "every product a release ships is one of this repo's .mavergreen/products/" ;;
    enclosure) echo "an appcast's enclosure names a published asset" ;;
    length) echo "an appcast's enclosure length is the asset's real size" ;;
    enclosure-url) echo "an appcast's enclosure URL names this release" ;;
    notes) echo "an appcast's description is the release body" ;;
    variant-build-info) echo "variants of one release agree about what they were built from" ;;
    sdk-pin) echo "every shipped Mach-O slice records its arch's pinned minos and SDK" ;;
    arch-host) echo "a host binary ships an arm64 slice only where a deviation declares its install path" ;;
    arch-target) echo "every target glob matches a file its product installs, and no host binary of the pkg loads a target file" ;;
    cxxabi) echo "one process gets one C++ runtime: no shipped Mach-O defines libc++abi's machinery or loads another libc++abi" ;;
    debug-map) echo "no shipped linked Mach-O keeps a debug map or names a builder's home or temporary directory" ;;
    dsym-asset) echo "every shipped linked Mach-O slice has its dSYM, by LC_UUID, in a *-dSYM.tar.gz of the same release" ;;
    link-rpath) echo "a family dylib is loaded by @rpath from outside its own product tree, and libc++ through an LC_RPATH that finds the installed libcxx22 first" ;;
    weak-bind-sorted) echo "every shipped linked Mach-O slice lists its weak-bind info in name order" ;;
    root-runs) echo "root runs a launch daemon or an install script only from a root-only chain" ;;
    os-overwrite) echo "a regular product only adds files to Mac OS X 10.9.5, and never replaces one the OS ships" ;;
    standalone) echo "every standalone archive in a release passes check-standalone-archive.sh" ;;
    no-standalone) echo "a release that ships a product's pkg ships its standalone archive beside it" ;;
    kext-sig-exception) echo "a boot kext a pkg installs in Library/Extensions is listed in 10.9's OSKextSigExceptionList through stage_product.sh --boot-kext, and the list names only kexts the pkg ships" ;;
    kext-exclude-list) echo "no pkg script edits AppleKextExcludeList other than through stage_product.sh --boot-kext" ;;
  esac
}
fix_of() {
  case "$1" in
    version-scheme) echo "version a port <upstream>-mavergreen.N (1.2.3-mavergreen.1) and an own-upstream repo YYYYMMDD.N (20261006.1), or declare .mavergreen/deviations/version-scheme/<label>/ (scope *, a reason, a revisit)" ;;
    version) echo "rebuild the artifact with the release version, or remove the stale one from dist/" ;;
    arch-distribution) echo "build every pkg with set_install_floor.sh, which writes the class's Distribution from the payload; a product that serves newer macOS declares .mavergreen/deviations/newer-macos/<label>/ (scope <short>, a reason, a revisit); no deviation excuses this check" ;;
    arch-floors) echo "build the pkg with set_install_floor.sh, which writes .mavergreen/products/<short>/floor (default 10.9.5) and the arm64 floor its slices record; no deviation excuses a floor" ;;
    identifier) echo "build the pkg with set_install_floor.sh --short <short>, whose identifier is dev.mavergreen.<short>, or declare .mavergreen/deviations/identifier/<label>/ (scope <glob>, a reason, a revisit)" ;;
    pkg-name) echo "build the pkg with set_install_floor.sh --short <short> --dist DIR (or package-system-replace.sh), which derive both names, and do not rename it" ;;
    installer-title) echo "build the pkg with set_install_floor.sh --short <short>, which titles it Mavergreen <name> from .mavergreen/products/<short>/" ;;
    feed-title) echo "generate the feed with gen_appcast.sh <short>, which derives both titles from .mavergreen/products/<short>/" ;;
    manifest-name) echo "write the manifest with render-manifest.sh --product <short>, which derives its name from .mavergreen/products/<short>/" ;;
    app-name) echo "name an app = noun bundle <noun>.app with CFBundleName and CFBundleDisplayName the noun and CFBundleIdentifier dev.mavergreen.<short>; keep an app = upstream bundle's CFBundleName equal to its filename, with no other CFBundleDisplayName" ;;
    bundle-id) echo "give the bundle a CFBundleIdentifier beginning dev.mavergreen., or declare .mavergreen/deviations/bundle-id/<label>/ (scope <its identifier>, a reason, a revisit)" ;;
    launchd-label) echo "name the job dev.mavergreen.<name> and its plist <Label>.plist, or declare .mavergreen/deviations/launchd-label/<label>/ (scope <its Label>, a reason, a revisit)" ;;
    manifest) echo "install opt/mavergreen/<product>/mavergreen.plist (render-manifest.sh writes it), listing every file outside the product's tree under outside" ;;
    base) echo "build the product archive with set_install_floor.sh, which lists dev.mavergreen.base first" ;;
    line) echo "write .mavergreen/products/<short>/line (dotted, like 1.27), render the manifest from it with render-manifest.sh, and release from the repo whose suffix is that line without dots, or fix the version" ;;
    install-path) echo "install under opt/mavergreen/<product>/ (an app under Applications/Mavergreen/; list the exceptions in the manifest's outside), or, where the OS dictates the place, declare .mavergreen/deviations/install-path/<label>/ (scope <glob>, a reason, a revisit)" ;;
    feed) echo "sign each product with sign_and_appcast.sh --product <product>, which writes <product>.xml, and render the manifest with render-manifest.sh, which names the derived feed" ;;
    repository) echo "declare the product in .mavergreen/products/<product>/, or release it from the repo that declares it" ;;
    enclosure) echo "publish the pkg the appcast names, or regenerate the appcast with gen_appcast.sh" ;;
    length) echo "regenerate the appcast after the pkg is final, so its length is the pkg's" ;;
    enclosure-url) echo "regenerate the appcast with the release's own tag in the pkg URL" ;;
    notes) echo "generate the appcast from the same RELEASE_NOTES.md the Release body is built from" ;;
    variant-build-info) echo "build every variant from the same pins, or declare .mavergreen/deviations/variant-build-info/<label>/ (scope *, a reason, a revisit)" ;;
    sdk-pin) echo "link against the pinned SDK (scripts/fetch_sdk.sh), or declare .mavergreen/deviations/sdk-pin/<label>/ (scope <glob>, a reason, a revisit)" ;;
    arch-host) echo "build that path x86_64 only, or declare .mavergreen/deviations/arch-host/<label>/ (scope <install-path glob>, a reason saying who runs it as arm64 on Apple Silicon and why, a revisit), with a modern-smoke job in release.yml that runs it" ;;
    arch-target) echo "correct .mavergreen/products/<short>/target, so it names only files built for the target, or link the host binary against a host copy; no deviation excuses this check" ;;
    cxxabi) echo "link the family's runtime (libcxx22), or declare .mavergreen/deviations/cxxabi/<label>/ (scope <glob>, a reason, a revisit)" ;;
    debug-map) echo "build through MavergreenToolchain.cmake, which maps the build paths away, and run split-debug.sh on the staged root, or declare .mavergreen/deviations/debug-map/<label>/ (scope <path glob>, a reason, a revisit)" ;;
    link-rpath) echo "link the family dylib by its @rpath install name, with the installed tree's LC_RPATH first (for libcxx22, one resolving to opt/mavergreen/libcxx22/lib), or declare .mavergreen/deviations/link-rpath/<label>/ (scope <path glob>, a reason, a revisit)" ;;
    weak-bind-sorted) echo "relink with clang22 22.1.8-mavericks.5 or later, whose lld writes weak-bind info in name order, or declare .mavergreen/deviations/weak-bind-sorted/<label>/ (scope <path glob>, a reason, a revisit)" ;;
    dsym-asset) echo "run split-debug.sh on the staged root and publish the S-V-dSYM.tar.gz it writes beside the pkg and archive, or declare .mavergreen/deviations/dsym-asset/<label>/ (scope <path glob>, a reason, a revisit)" ;;
    root-runs) echo "never name an admin-writable path in an install script; root runs only from a root-only chain" ;;
    os-overwrite) echo "install it under /opt/mavergreen/<short>/, or make this a system edition" ;;
    standalone) echo "build the archive with stage_standalone.sh from the staged product, and fix what check-standalone-archive.sh names; text that must name a Mavergreen prefix declares .mavergreen/deviations/standalone-text/<label>/ (scope <archive-path glob>, a reason, a revisit)" ;;
    no-standalone) echo "publish <short>-<version>-macos-<arch>.tar.gz with stage_standalone.sh, or, where a standalone form is meaningless, declare .mavergreen/deviations/no-standalone/<label>/ (scope <short>, a reason, a revisit)" ;;
  esac
}

fail() {  # $1 = check name, $2 = message, $3 = the artifact it concerns (optional), $4 = the fix, when not fix_of's
  # spec: SKILL.md "Artifact conformance" -- a deviation excuses only its OWN check, only for the
  #       artifacts it names, and only with a reason (swift-toolchain's swift.org .pkg is the scoping
  #       example there).
  _c="$1"; _msg="$2"; _file="${3:-}"; _fix="${4:-}"
  case "$_c" in
    scheme) _id=version-scheme ;;
    ingredients) _id=variant-build-info ;;
    *) _id="$_c" ;;
  esac
  reason="$(deviation_reason "$_id" "$_file")"
  if [ -z "$reason" ]; then
    case "$_id" in
      version-scheme) reason="$(deviation_reason scheme "$_file")" ;;
      variant-build-info) reason="$(deviation_reason ingredients "$_file")" ;;
    esac
  fi
  if [ -n "$reason" ]; then
    echo "conformance: ${_id}: DECLARED DEVIATION${_file:+ (${_file})} -- $reason"
    return 0
  fi
  # spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Conformance
  #       deviations" -- excusing requires a REASON; a bare "deviation <check>" with none must still
  #       fail here, the same way its sibling above (the completion sentinel) refuses to let any
  #       deviation excuse it -- a switch-off with no reason attached is indistinguishable from a
  #       check nobody wrote.
  if shipyard_deviation_scopes "$_id" | grep -qx '\*' || shipyard_deviation_scopes "$_c" | grep -qx '\*'; then
    chk_fail "$_id" "$(rule_of "$_id")" "a '${_c}' deviation is declared with no reason, which excuses nothing" \
      "state why in .mavergreen/deviations/${_c}/<label>/ (scope, reason, revisit), or fix the artifact"
    return 0
  fi
  chk_fail "$_id" "$(rule_of "$_id")" "$_msg" "${_fix:-$(fix_of "$_id")}"
}

expected="$(sed -n 's/^expected \(..*\)$/\1/p' "$facts" | head -1)"
[ -n "$expected" ] || {
  chk_fail artifact-facts "the artifacts could not be read to the end" \
    "the fact stream names no expected version, so nothing can be compared with it" \
    "run artifact-facts.sh <dist> <version>, which writes it first"
  exit 1
}

upstream_kind="$(sed -n 's/^upstream-kind \(..*\)$/\1/p' "$facts" | head -1)"
case "$upstream_kind" in
  port)
    case "$expected" in
      ?*-mavergreen.*) n="${expected##*-mavergreen.}" ;;
      *) n="" ;;
    esac
    case "$n" in
      ''|*[!0123456789]*) fail scheme "version '$expected' is not <upstream>-mavergreen.N, though this repo ports an upstream" ;;
    esac
    ;;
  own)
    case "$expected" in
      [0123456789][0123456789][0123456789][0123456789][0123456789][0123456789][0123456789][0123456789].*) n="${expected#????????.}" ;;
      *) n="" ;;
    esac
    case "$n" in
      ''|*[!0123456789]*) fail scheme "version '$expected' is not YYYYMMDD.N, though this repo is its own upstream" ;;
    esac
    ;;
  *) fail scheme "the repo's kind is unknown (no upstream-kind fact), so version '$expected' cannot be checked against its scheme" ;;
esac

# spec: SKILL.md "Artifact conformance" axis table -- ITSELF/NEIGHBOURS: every .pkg agrees with the
#       tag and identifier scheme.
while read -r kind file ver floor ident; do
  [ "$kind" = pkg ] || continue
  [ "$ver" = "$expected" ] \
    || fail version "$file says version $ver, the release is $expected" "$file"
  case "$ident" in
    dev.mavergreen.*) : ;;
    *) fail identifier "$file has identifier '$ident', outside dev.mavergreen.*" "$file" ;;
  esac
done < "$facts"

# spec: explain/arch-distribution.md and explain/arch-floors.md -- each pkg's class, OS range and
#       floors are derived from its host slices, its product's floor and the newer-macos deviation,
#       through lib/arch-rules.sh as set_install_floor.sh derives them; no deviation excuses either.
arch_fail() { chk_fail "$1" "$(rule_of "$1")" "$2" "$(fix_of "$1")"; }
grep '^pkg-arch ' "$facts" > "$tmp/pkg-arch" || true
while read -r _ pa_file pa_host pa_before pa_rule; do
  if ! awk -v f="$pa_file" '$1 == "pkg-title" && $2 == f { hit = 1 } END { exit !hit }' "$facts"; then
    arch_fail arch-distribution "$pa_file is a component package with no Distribution, and every pkg a release ships is a product archive from set_install_floor.sh"
    continue
  fi
  pa_prod="$(awk -v f="$pa_file" '$1 == "manifest" && $2 == f { print $3; exit }' "$facts")"
  pa_floor=10.9.5; pa_newer=no; pa_tree=
  : > "$tmp/pa-targets"
  if [ -n "$pa_prod" ]; then
    pa_tree="opt/mavergreen/$pa_prod/"
    pa_floor="$(awk -v p="$pa_prod" '$1 == "floor" && $2 == p { print $3; exit }' "$facts")"
    : "${pa_floor:=10.9.5}"
    awk -v p="$pa_prod" '$1 == "target" && $2 == p { print $3 }' "$facts" | sed -e 's/%20/ /g' -e 's/%25/%/g' > "$tmp/pa-targets"
    [ -z "$(deviation_reason newer-macos "$pa_prod")" ] || pa_newer=yes
  fi
  pa_pkgfloor="$(awk -v f="$pa_file" '$1 == "pkg" && $2 == f { print $4; exit }' "$facts")"
  [ "$pa_pkgfloor" = "$pa_floor" ] \
    || arch_fail arch-floors "$pa_file declares an install floor of $pa_pkgfloor; $(if [ -n "$pa_prod" ]; then echo "$pa_prod's floor"; else echo "$pa_file names no product, whose floor"; fi) is $pa_floor"
  [ "$pa_host" = x86_64,arm64 ] || {
    if [ "$pa_host" = none ]; then arch_fail arch-distribution "$pa_file declares no hostArchitectures; every pkg declares \"x86_64,arm64\""
    else arch_fail arch-distribution "$pa_file declares hostArchitectures \"$pa_host\", not \"x86_64,arm64\""; fi
  }
  awk -v f="$pa_file" '$1 == "macho" && $2 == f {
      d = $3; gsub(/%20/, " ", d); gsub(/%25/, "%", d); print $3, $4, $6, d }' "$facts" > "$tmp/pa-all"
  : > "$tmp/pa-slices"
  while read -r pa_p pa_a pa_m pa_d; do
    if [ -n "$pa_tree" ] && [ -s "$tmp/pa-targets" ]; then
      case "$pa_d" in "$pa_tree"*) ! arch_is_target "${pa_d#"$pa_tree"}" "$tmp/pa-targets" || continue ;; esac
    fi
    printf '%s %s %s\n' "$pa_p" "$pa_a" "$pa_m" >> "$tmp/pa-slices"
  done < "$tmp/pa-all"
  if ! arch_derive < "$tmp/pa-slices" > "$tmp/pa-derived" 2> "$tmp/pa-err"; then
    arch_fail arch-distribution "$pa_file: $(sed -e 's/%20/ /g' -e 's/%25/%/g' "$tmp/pa-err" | head -n 1)"
    continue
  fi
  pa_class="$(sed -n 's/^class //p' "$tmp/pa-derived")"
  pa_arm="$(sed -n 's/^arm64-floor //p' "$tmp/pa-derived")"
  case "$pa_rule" in
    arm64-below:*)
      [ "$pa_arm" = none ] || [ "${pa_rule#arm64-below:}" = "$pa_arm" ] \
        || arch_fail arch-floors "$pa_file refuses Apple Silicon below macOS ${pa_rule#arm64-below:}; its arm64 host slices record $pa_arm" ;;
  esac
  pa_want="$(arch_rule "$pa_class" "$pa_newer" "$pa_floor" "$pa_arm")" || {
    arch_fail arch-distribution "$pa_file ships an arm64 host slice, so it is universal, and $(if [ -n "$pa_prod" ]; then echo "$pa_prod declares"; else echo "a pkg that names no product can declare"; fi) no newer-macos deviation; a universal pkg has no 10.11 ceiling, so it must serve newer macOS"
    continue
  }
  pa_want="${pa_want%% *}"
  case "$pa_class:$pa_newer" in
    universal:*|*:yes) pa_wbefore=none ;;
    *) pa_wbefore=10.11 ;;
  esac
  pa_how="its class is $pa_class$(if [ "$pa_newer" = yes ]; then echo ", with newer-macos"; fi)"
  [ "$pa_before" = "$pa_wbefore" ] || {
    if [ "$pa_wbefore" = none ]; then arch_fail arch-distribution "$pa_file allows os-versions before=\"$pa_before\"; $pa_how, which wants no before"
    else arch_fail arch-distribution "$pa_file allows os-versions with $(if [ "$pa_before" = none ]; then echo "no before"; else echo "before=\"$pa_before\""; fi); $pa_how, which wants before=\"$pa_wbefore\""; fi
  }
  [ "${pa_rule%%:*}" = "$pa_want" ] \
    || arch_fail arch-distribution "$pa_file $(if [ "$pa_rule" = none ]; then echo "has no installation-check"; else echo "has an $pa_rule installation-check"; fi); $pa_how, which wants $pa_want"
done < "$tmp/pkg-arch"

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Install layout and
#       identity" -- SIBLINGS: what a pkg installs carries the family's identity. A deviation for these
#       is scoped to the bundle identifier or Label it excuses, not to the pkg that ships it.
dec() { printf '%s' "$1" | sed -e 's/%20/ /g' -e 's/%25/%/g'; }
awk '$1 == "app" && $3 == "upstream" { up[$2] = 1 }
     $1 == "manifest" { m[$2] = $5 }
     $1 == "bundle" { b[++n] = $2 " " $3 }
     END { for (i = 1; i <= n; i++) { split(b[i], f, " ")
             if ((f[1] in m) && (m[f[1]] in up) && f[2] ~ /\.app$/) print b[i] } }' \
  "$facts" > "$tmp/upstream-apps"
while read -r kind file path id; do
  [ "$kind" = bundle ] || continue
  ! grep -qxF "$file $path" "$tmp/upstream-apps" || continue
  case "$id" in
    dev.mavergreen.*) : ;;
    *) fail bundle-id "$file installs $(dec "$path") as '$id', outside dev.mavergreen.*" "$id" ;;
  esac
done < "$facts"
while read -r kind file path label; do
  [ "$kind" = launchd ] || continue
  p="$(dec "$path")"; base="${p##*/}"; base="${base%.plist}"
  case "$label" in
    dev.mavergreen.*) : ;;
    *) fail launchd-label "$file installs $p with Label '$label', outside dev.mavergreen.*" "$label" ;;
  esac
  [ "$base" = "$label" ] \
    || fail launchd-label "$file installs $p with Label '$label' -- a job's plist is named <Label>.plist, or launchctl and every uninstaller look for the wrong file" "$label"
done < "$facts"

# spec: tests/artifact-conformance-test.sh -- a pkg that installs a product carries exactly one
#       manifest, whose identifier is dev.mavergreen.<product> and one of its components; it installs only into
#       that product's tree and what the manifest lists as outside (else uninstall leaves files
#       behind); and its first component is dev.mavergreen.base, whose postinstall installs or
#       upgrades the helper before the product's postinstall runs it. Coverage mirrors
#       scripts/mavergreen.sh uninstall, which removes an outside entry only as an exact file or
#       link, or as a directory whose name ends in one of the bundle extensions render-manifest.sh
#       collapses to, and refuses the shapes outside_shape_ok rejects.
grep '^manifest ' "$facts" > "$tmp/manifests" || true
grep '^component ' "$facts" > "$tmp/components" || true
: > "$tmp/prod-of"
for pk in $(sed -n 's/^pkg \([^ ][^ ]*\) .*/\1/p' "$facts" | sort -u); do
  n="$(awk -v p="$pk" '$2 == p' "$tmp/manifests" | wc -l | tr -d ' ')"
  product_files="$(awk -v p="$pk" '$1 == "installs" && $2 == p && index($3, "opt/mavergreen/.base/") != 1' "$facts" | wc -l | tr -d ' ')"
  if [ "$product_files" -gt 0 ] && [ "$n" -ne 1 ]; then
    fail manifest "$pk installs $product_files files but carries $n opt/mavergreen/<product>/mavergreen.plist manifests; it must carry exactly one, or nothing can find, update or uninstall what it installed" "$pk"
    continue
  fi
  [ "$n" -eq 1 ] || continue
  read -r _ _ mprod mid mdir <<EOF
$(awk -v p="$pk" '$2 == p' "$tmp/manifests")
EOF
  [ "$mprod" = "$mdir" ] \
    || fail manifest "$pk's manifest names product '$mprod' but sits in opt/mavergreen/$(dec "$mdir")" "$pk"
  [ "$mid" = "dev.mavergreen.$mprod" ] \
    || fail manifest "$pk's manifest names identifier $mid; product $mprod's is dev.mavergreen.$mprod" "$pk"
  awk -v p="$pk" -v i="$mid" '$2 == p && $3 == i { f = 1 } END { exit !f }' "$tmp/components" \
    || fail manifest "$pk's manifest names identifier $mid, which is not one of its components" "$pk"
  first="$(awk -v p="$pk" '$2 == p { print $3; exit }' "$tmp/components")"
  [ "$first" = dev.mavergreen.base ] \
    || fail base "$pk installs a product but its first component is '${first:-none}', not dev.mavergreen.base -- its postinstall would run the helper before the base had installed or upgraded it" "$pk"
  printf '%s %s\n' "$pk" "$mdir" >> "$tmp/prod-of"
  awk -v p="$pk" -v pr="$mdir" '
    NR == FNR {
      if ($1 != "manifest-outside" || $2 != p) next
      if ($3 == "" || $3 ~ /^\// || $3 ~ /\/$/ || index($3, "//") || index("/" $3 "/", "/./") || index("/" $3 "/", "/../") \
          || $3 == "opt/mavergreen" || index($3, "opt/mavergreen/") == 1) print "badshape " $3
      else o[$3] = 1
      next
    }
    $1 == "installs" && $2 == p && index($3, "opt/mavergreen/" pr "/") != 1 && index($3, "opt/mavergreen/.base/") != 1 {
      hit = ""
      if ($3 in o) hit = $3
      else {
        n = split($3, c, "/"); s = c[1]
        for (i = 1; i < n && hit == ""; i++) {
          if ((s in o) && c[i] ~ /\.(app|kext|prefPane|plugin|bundle|framework|jdk|fs)$/) hit = s
          s = s "/" c[i + 1]
        }
      }
      if (hit == "") print "unlisted " $3; else used[hit] = 1
    }
    END { for (k in o) if (!(k in used)) print "unused " k }' "$facts" "$facts" | sort > "$tmp/outside-$pk"
  unlisted=0
  while read -r why op; do
    case "$why" in
      unlisted) unlisted=$((unlisted + 1)); [ "$unlisted" -le 20 ] || continue
        fail manifest "$pk installs $(dec "$op") outside its tree, and its manifest's outside list does not name it -- uninstall would leave it behind" "$pk" ;;
      unused) fail manifest "$pk's manifest lists $(dec "$op") in outside, but the pkg installs nothing it would remove -- uninstall deletes an entry only as that exact file or link, or as a whole .app, .kext, .prefPane, .plugin, .bundle, .framework, .jdk or .fs directory" "$pk" ;;
      badshape) fail manifest "$pk's manifest lists outside entry '$(dec "$op")' in a shape the helper refuses to uninstall -- empty, absolute, ending in /, an empty, . or .. segment, or under opt/mavergreen" "$pk" ;;
    esac
  done < "$tmp/outside-$pk"
  [ "$unlisted" -le 20 ] \
    || fail manifest "$pk installs $((unlisted - 20)) more files outside its tree that its manifest's outside list does not name" "$pk"
  awk -v p="$pk" '$1 == "manifest-generated" && $2 == p { print $3 }' "$facts" > "$tmp/generated-$pk"
  while IFS= read -r gp; do
    case "$gp" in
      ''|/*|*/|*//*|opt/mavergreen|opt/mavergreen/*) gbad=1 ;;
      *) case "/$gp/" in *"/./"*|*"/../"*) gbad=1 ;; *) gbad=0 ;; esac ;;
    esac
    [ "$gbad" -eq 0 ] \
      || fail manifest "$pk's manifest lists generated entry '$(dec "$gp")' in a shape the helper refuses to uninstall -- empty, absolute, ending in /, an empty, . or .. segment, or under opt/mavergreen" "$pk"
  done < "$tmp/generated-$pk"
done

# spec: tests/artifact-conformance-test.sh -- line identity: a product's feed is the derived record's,
#       a lined product's line is its version and its repo's suffix, and every product a release
#       ships is one this repo declares.
repository="$(sed -n 's/^repository \([^ ][^ ]*\)$/\1/p' "$facts" | head -1)"
up="${expected#v}"; up="${up%-mavergreen.*}"
repo="${repository#*/}"
nm() { awk -v p="$1" -v s="$2" '$1 == "name" && $2 == p && $3 == s { print $4; exit }' "$facts"; }
noun_of() { _it="$(nm "$1" item-title)"; printf '%s' "${_it%"%20$up"}"; }
line_of() {
  _no="$(noun_of "$1")"; _mn="$(nm "$1" manifest-name)"
  [ "$_mn" = "$_no" ] || printf '%s' "${_mn#"$_no%20"}"
}
while read -r pk P; do
  awk -v m="$P" '$1 == "product" && $2 == m { f = 1 } END { exit !f }' "$facts" \
    || fail repository "$pk ships $P, which this repo does not declare in .mavergreen/products/$P/" "$pk"
  want_feed=""
  read -r _ _ want_feed <<EOF
$(awk -v m="$P" '$1 == "derived" && $2 == m { print; exit }' "$facts")
EOF
  if [ -n "$want_feed" ]; then
    ma="$(awk -v p="$pk" '$1 == "manifest-feed" && $2 == p { print $3; exit }' "$facts")"
    if awk -v m="$P" '$1 == "built-on-install" && $2 == m { f = 1 } END { exit !f }' "$facts"; then
      [ -z "$ma" ] || [ "$ma" = none ] \
        || fail feed "$pk's manifest names the feed '$ma'; $P is built on install and names none" "$pk"
    else
      if [ "$want_feed" != none ]; then
        [ -z "$ma" ] || [ "$ma" = "$want_feed" ] \
          || fail feed "$pk's manifest names the feed '$ma'; $P's feed is $want_feed" "$pk"
      fi
      grep -q "^appcast $P\.xml " "$facts" \
        || fail feed "$pk ships $P, but the dist carries no $P.xml -- /latest/download/$P.xml would 404 for the Engine on every box that installed $P" "$pk"
    fi
  fi
  ml="$(awk -v p="$pk" '$1 == "manifest-line" && $2 == p { print $3; exit }' "$facts")"
  case "$ml" in ''|none) lv="" ;; *) lv="$ml" ;; esac
  if [ -n "$(nm "$P" item-title)" ]; then
    pl="$(line_of "$P")"
    [ "$lv" = "$pl" ] \
      || fail line "$pk's manifest declares line '${ml:-none}', but .mavergreen/products/$P/line is '${pl:-none}'" "$pk"
  fi
  case "$repo" in
    *-*) case "${repo##*-}" in
           ''|*[!0-9]*) : ;;
           *) [ -n "$lv" ] || fail line "$pk ships $P from the line repo $repo, so its manifest must declare the line whose digits are ${repo##*-}; it declares '${ml:-none}'" "$pk" ;;
         esac ;;
  esac
  if [ -n "$lv" ]; then
    ls_="$(printf '%s' "$lv" | tr -d .)"
    case "$repo" in
      *-"$ls_") : ;;
      '') : ;;
      *) fail line "$pk is line $lv, so its repo is <product>-$ls_, but this release is built in $repository" "$pk" ;;
    esac
    case "$up" in
      "$lv"|"$lv".*) : ;;
      *) fail line "$pk is line $lv, but version $expected is not $lv or $lv.<more>" "$pk" ;;
    esac
  fi
done < "$tmp/prod-of"

nonbase() { awk -v p="$1" '$1 == "component" && $2 == p && $3 != "dev.mavergreen.base" { print $3, ($4 == "" ? "none" : $4) }' "$facts"; }
while read -r pk P; do
  want_id="$(nm "$P" identifier)"
  [ -n "$want_id" ] || continue
  want_pkg="$(nm "$P" pkg)"; want_comp="$(nm "$P" component)"
  [ "$pk" = "$want_pkg" ] || fail pkg-name "$pk carries $P's manifest, so it is named $(dec "$want_pkg")" "$pk"
  nonbase "$pk" > "$tmp/nonbase"
  while read -r cid cname; do
    [ "$cname" = none ] || [ "$cname" = "$want_comp" ] \
      || fail pkg-name "$pk names $P's component $(dec "$cname"); it is $(dec "$want_comp")" "$pk"
  done < "$tmp/nonbase"
  want_t="$(nm "$P" installer-title)"
  t="$(awk -v p="$pk" '$1 == "pkg-title" && $2 == p { print $3; exit }' "$facts")"
  [ -z "$t" ] || [ "$t" = "$want_t" ] \
    || fail installer-title "$pk is titled '$(dec "$t")'; $P's title is '$(dec "$want_t")'" "$pk"
  want_mn="$(nm "$P" manifest-name)"
  mn="$(awk -v p="$pk" '$1 == "manifest-name" && $2 == p { print $3; exit }' "$facts")"
  [ -z "$mn" ] || [ "$mn" = "$want_mn" ] \
    || fail manifest-name "$pk's manifest is named '$(dec "$mn")'; $P's name is '$(dec "$want_mn")'" "$pk"
  pid="$(awk -v p="$pk" '$1 == "pkg" && $2 == p { print $5; exit }' "$facts")"
  case "$pid" in
    dev.mavergreen.*) [ "$pid" = "$want_id" ] || fail identifier "$pk carries $P's manifest but is identified as $pid; $P's identifier is $want_id" "$pk" ;;
  esac
  while read -r cid cname; do
    [ "$cid" = "$want_id" ] || [ "$cid" = "$pid" ] \
      || fail identifier "$pk's component $cid carries $P; $P's identifier is $want_id" "$pk"
  done < "$tmp/nonbase"
  case "$(awk -v p="$P" '$1 == "app" && $2 == p { print $3; exit }' "$facts")" in
    noun)
      noun="$(noun_of "$P")"
      awk -v p="$pk" -v n="$noun.app" '$1 == "bundle-name" && $2 == p { k = split($3, c, "/"); if (c[k] == n) print $3, $4, $5 }' "$facts" > "$tmp/noun-app"
      [ -s "$tmp/noun-app" ] \
        || fail app-name "$P's app is noun, but $pk installs no top-level $(dec "$noun").app" "$pk"
      while read -r ap bn bdn; do
        [ "$bn" = "$noun" ] && [ "$bdn" = "$noun" ] \
          || fail app-name "$pk installs $(dec "$ap") with CFBundleName '$(dec "$bn")' and CFBundleDisplayName '$(dec "$bdn")'; both are '$(dec "$noun")'" "$pk"
        bid="$(awk -v p="$pk" -v b="$ap" '$1 == "bundle" && $2 == p && $3 == b { print $4; exit }' "$facts")"
        [ "$bid" = "$want_id" ] \
          || fail app-name "$pk installs $(dec "$ap") as '$bid'; $P's app is $want_id" "$pk"
      done < "$tmp/noun-app"
      ;;
    upstream)
      awk -v p="$pk" '$1 == "bundle-name" && $2 == p && $3 ~ /\.app$/ { print $3, $4, $5 }' "$facts" > "$tmp/up-app"
      while read -r ap bn bdn; do
        stem="${ap##*/}"; stem="${stem%.app}"
        [ "$bn" = "$stem" ] && { [ "$bdn" = none ] || [ "$bdn" = "$stem" ]; } \
          || fail app-name "$pk installs $(dec "$ap") with CFBundleName '$(dec "$bn")' and CFBundleDisplayName '$(dec "$bdn")'; an upstream app's CFBundleName is its filename, '$(dec "$stem")', and its display name is that or absent" "$pk"
      done < "$tmp/up-app"
      ;;
  esac
done < "$tmp/prod-of"

while read -r kind pk _ _ pid; do
  [ "$kind" = pkg ] || continue
  case "$pid" in dev.mavergreen.*.system-replace) : ;; *) continue ;; esac
  P="${pid#dev.mavergreen.}"; P="${P%.system-replace}"
  [ "$(nm "$P" identifier)" = "dev.mavergreen.$P" ] || continue
  want_pkg="$(nm "$P" pkg)"; want_pkg="$P-system-replace-${want_pkg#"$P"-}"
  want_comp="$(nm "$P" component)"; want_comp="${want_comp%.pkg}-system-replace.pkg"
  [ "$pk" = "$want_pkg" ] || fail pkg-name "$pk is $P's System Replace, so it is named $(dec "$want_pkg")" "$pk"
  nonbase "$pk" | while read -r cid cname; do
    [ "$cname" = none ] || [ "$cname" = "$want_comp" ] || echo "$cname"
  done > "$tmp/sr-comp"
  while read -r cname; do
    fail pkg-name "$pk names $P's System Replace component $(dec "$cname"); it is $(dec "$want_comp")" "$pk"
  done < "$tmp/sr-comp"
  want_t="$(nm "$P" installer-title)%20System%20Replace"
  t="$(awk -v p="$pk" '$1 == "pkg-title" && $2 == p { print $3; exit }' "$facts")"
  [ -z "$t" ] || [ "$t" = "$want_t" ] \
    || fail installer-title "$pk is titled '$(dec "$t")'; $P's System Replace is titled '$(dec "$want_t")'" "$pk"
done < "$facts"

while read -r kind af ch it; do
  [ "$kind" = appcast-title ] || continue
  P="${af%.xml}"
  want_ch="$(nm "$P" channel-title)"
  [ -n "$want_ch" ] || continue
  want_it="$(nm "$P" item-title)"
  [ "$ch" = "$want_ch" ] || fail feed-title "$af's channel is titled '$(dec "$ch")'; $P's is '$(dec "$want_ch")'" "$af"
  [ "$it" = "$want_it" ] || fail feed-title "$af's item is titled '$(dec "$it")'; $P's is '$(dec "$want_it")'" "$af"
done < "$facts"

# spec: tests/artifact-conformance-test.sh "feed:" -- a feed offers exactly the requirements its product's manifest declares.
awk '
  $1 == "manifest" { prod[$2] = $3 }
  $1 == "manifest-requires" { mr[++n] = $2 SUBSEP $3 SUBSEP $4 }
  $1 == "appcast" { feed[$2] = 1 }
  $1 == "appcast-requires" { ar[++m] = $2 SUBSEP $3 SUBSEP $4; have[$2 SUBSEP $3] = $4 }
  END {
    for (i = 1; i <= n; i++) {
      split(mr[i], r, SUBSEP); f = prod[r[1]] ".xml"
      if (!(f in feed)) continue
      declared[f SUBSEP r[2]] = r[3]; judged[f] = 1
      if (have[f SUBSEP r[2]] != r[3]) print f, r[1], "missing", r[2], r[3]
    }
    for (p in prod) judged[prod[p] ".xml"] = 1
    for (i = 1; i <= m; i++) {
      split(ar[i], r, SUBSEP)
      if (!(r[1] in judged)) continue
      if (declared[r[1] SUBSEP r[2]] != r[3]) print r[1], "-", "undeclared", r[2], r[3]
    }
  }' "$facts" | LC_ALL=C sort -u > "$tmp/feed-requires"
while read -r af pk what dep kind; do
  if [ "$what" = missing ]; then
    fail feed "$af has no <mavergreen:requires product=\"$dep\" kind=\"$kind\"/>, which $pk's manifest requires" "$af"
  else
    fail feed "$af requires $dep ($kind), which no manifest of its product declares" "$af"
  fi
done < "$tmp/feed-requires"

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Standalone archive"
while read -r kind file verdict why; do
  if [ "$kind" = standalone-text-unused ]; then
    chk_fail standalone "$(rule_of standalone)" "the standalone-text deviation scoped $(dec "$file") excuses nothing in any standalone archive of this release" \
      "delete the .mavergreen/deviations/standalone-text/ entry scoped $(dec "$file")"
    continue
  fi
  if [ "$kind" = standalone-flow ]; then
    [ "$verdict" != pkg-first ] || echo "::warning::standalone: $file: pkg-first, with no packaging/<short>.standalone-bundled; convert to archive-first (derive_pkg_tree.sh) at the next release"
    continue
  fi
  [ "$kind" = standalone ] || continue
  [ "$verdict" = ok ] || chk_fail standalone "$(rule_of standalone)" "$file: $(dec "${why:-check-standalone-archive.sh refused it}")" "$(fix_of standalone)"
done < "$facts"
awk '!seen[$2]++' "$tmp/prod-of" > "$tmp/sa-products"
while read -r pk P; do
  awk -v m="$P" '$1 == "product" && $2 == m { f = 1 } END { exit !f }' "$facts" || continue
  have=""
  for v in "$expected" "${expected#v}"; do
    for a in universal x86_64 arm64; do
      n="$P-$v-macos-$a.tar.gz"
      case " $have " in *" $n "*) continue ;; esac
      if awk -v n="$n" '$1 == "asset" && $2 == n { f = 1 } END { exit !f }' "$facts"; then have="${have:+$have }$n"; fi
    done
  done
  if [ -n "$have" ]; then
    if [ -n "$(deviation_reason no-standalone "$P")" ]; then
      chk_fail no-standalone "$(rule_of no-standalone)" "$P: a no-standalone deviation covers $P, but the release carries $have" \
        "delete the no-standalone deviation for $P, or stop publishing the archive"
    fi
    for n in $have; do
      awk -v n="$n" '$1 == "standalone" && $2 == n { f = 1 } END { exit !f }' "$facts" \
        || chk_fail standalone "$(rule_of standalone)" "$n: artifact-facts.sh did not judge it with check-standalone-archive.sh" "$(fix_of standalone)"
    done
  elif [ -n "$repo" ] && [ -f "$SELF/conventions-grandfathered" ] && grep -qxF "standalone $repo $P" "$SELF/conventions-grandfathered"; then
    echo "::warning::no-standalone: $P: $pk ships $P, and the release carries no $P-${expected#v}-macos-<arch>.tar.gz (grandfathered: standalone $repo $P)"
  else
    fail no-standalone "$P: $pk ships $P, and the release carries no $P-${expected#v}-macos-<universal|x86_64|arm64>.tar.gz beside it" "$P"
  fi
done < "$tmp/sa-products"

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Install layout and
#       identity" -- where a family product may put files by default. Anything else is a declared
#       deviation scoped to the PATH (glob; `*` spans "/" and spaces), so excusing a kext's
#       directory cannot quietly excuse a stray file elsewhere in the same pkg. Reported once per
#       reason and capped, since one wrong directory can hold thousands of files.
os_bundle() {  # $1 = path, $2 = the directory the OS loads from, $3 = the bundle suffix
  case "$1" in "$2"?*) ;; *) return 1 ;; esac
  _ob="${1#"$2"}"; _ob="${_ob%%/*}"
  case "$_ob" in ?*"$3") return 0 ;; esac
  return 1
}
installs_seen=0
last_file=""; prod=""; has_base=no
: > "$tmp/ip-dev"; : > "$tmp/ip-fail"; : > "$tmp/ip-usrlocal"
while read -r kind file path; do
  [ "$kind" = installs ] || continue
  installs_seen=$((installs_seen + 1))
  if [ "$file" != "$last_file" ]; then
    last_file="$file"
    prod="$(awk -v f="$file" '$1 == f { print $2; exit }' "$tmp/prod-of")"
    has_base=no
    awk -v f="$file" '$2 == f && $3 == "dev.mavergreen.base" { g = 1 } END { exit !g }' "$tmp/components" && has_base=yes
  fi
  if [ -n "$prod" ]; then case "$path" in "opt/mavergreen/$prod/"*) continue ;; esac; fi
  case "$path" in
    usr/local|usr/local/*) printf '%s\n' "$file: $(dec "$path")" >> "$tmp/ip-usrlocal"; continue ;;
    opt/mavergreen/.base/*) [ "$has_base" = no ] || continue ;;
    Applications/Mavergreen/*) os_bundle "$path" Applications/Mavergreen/ .app && continue ;;
    Library/LaunchAgents/dev.mavergreen.*.plist|Library/LaunchDaemons/dev.mavergreen.*.plist)
      case "${path#Library/*/}" in */*) ;; *) continue ;; esac ;;
  esac
  os_bundle "$path" Library/Extensions/ .kext && continue
  os_bundle "$path" System/Library/Extensions/ .kext && continue
  os_bundle "$path" System/Library/Filesystems/ .fs && continue
  os_bundle "$path" Library/PreferencePanes/ .prefPane && continue
  os_bundle "$path" Library/Application%20Support/Apple/BezelServices/ .plugin && continue
  os_bundle "$path" Library/Application%20Support/SIMBL/Plugins/ .bundle && continue
  p="$(dec "$path")"
  r="$(deviation_reason install-path "$p")"
  if [ -n "$r" ]; then printf '%s\n' "$r" >> "$tmp/ip-dev"
  else printf '%s: %s\n' "$file" "$p" >> "$tmp/ip-fail"; fi
done < "$facts"
sort "$tmp/ip-dev" | uniq -c | while read -r n r; do
  echo "conformance: install-path: DECLARED DEVIATION ($n files) -- $r"
done
ul="$(wc -l < "$tmp/ip-usrlocal" | tr -d ' ')"
if [ "$ul" -gt 0 ]; then
  head -20 "$tmp/ip-usrlocal" > "$tmp/ip-usrlocal20"
  while IFS= read -r l; do
    chk_fail install-path "$(rule_of install-path)" "$l -- nothing installs under usr/local/; the family left it (vision principle 6)" "install it under opt/mavergreen/<product>/, or, for an app, under Applications/Mavergreen/; no deviation excuses usr/local/"
  done < "$tmp/ip-usrlocal20"
  [ "$ul" -le 20 ] || echo "conformance: install-path: ... and $((ul - 20)) more under usr/local/" >&2
fi
nfail="$(wc -l < "$tmp/ip-fail" | tr -d ' ')"
if [ "$nfail" -gt 0 ]; then
  head -20 "$tmp/ip-fail" > "$tmp/ip-fail20"
  while IFS= read -r l; do
    case "${l#*: }" in
      Applications/*) _ipfix="install it under Applications/Mavergreen/" ;;
      *) _ipfix="$(fix_of install-path)" ;;
    esac
    chk_fail install-path "$(rule_of install-path)" "$l -- outside opt/mavergreen/<its product>, opt/mavergreen/.base (with the base component), Applications/Mavergreen and the places the OS dictates (kexts, filesystems, preference panes, BezelServices and SIMBL plugins, dev.mavergreen.* launchd jobs)" "$_ipfix"
  done < "$tmp/ip-fail20"
  [ "$nfail" -le 20 ] || echo "conformance: install-path: ... and $((nfail - 20)) more" >&2
fi
echo "conformance: install-path: checked $installs_seen installed files"

while read -r kind file a b c; do
  case "$kind" in
    launchd-program)
      prog="$(dec "$b")"
      case "$prog" in
        *"/../"*|*/..) ok=no ;;
        /opt/mavergreen/?*|/bin/?*|/sbin/?*|/usr/bin/?*|/usr/sbin/?*|/usr/libexec/?*|/System/?*) ok=yes ;;
        *) ok=no ;;
      esac
      [ "$ok" = yes ] || fail root-runs "$file's launch daemon $(dec "$a") runs $prog, outside /opt/mavergreen/ and the system's own /bin/, /sbin/, /usr/bin/, /usr/sbin/, /usr/libexec/ and /System/" "$file" \
        "install the program under /opt/mavergreen/<short>/ and point the plist there" ;;
    script)
      case "$(dec "$c")" in
        /bin/sh|/bin/bash) ;;
        *) fail root-runs "$file's $a $b runs under $(dec "$c"), not /bin/sh or /bin/bash" "$file" \
             "start the script with #!/bin/sh or #!/bin/bash; root runs only from a root-only chain" ;;
      esac ;;
    script-mentions)
      fail root-runs "$file's $a $b names $c, which an admin can write" "$file" ;;
  esac
done < "$facts"
awk '$1 == "payload-mode" {
       p = $3; t = substr($6, 1, 1)
       if (p != "." && p != "opt" && p != "opt/mavergreen" && p !~ /^opt\/mavergreen\// \
           && p != "Applications" && p != "Applications/Mavergreen" && p !~ /^Applications\/Mavergreen\//) next
       if ($4 != 0 || $5 != 0 || (t != "l" && (substr($6, 6, 1) == "w" || substr($6, 9, 1) == "w"))) print $2, $3, $4, $5, $6
     }' "$facts" > "$tmp/rr-modes"
cut -d' ' -f1 "$tmp/rr-modes" | sort -u > "$tmp/rr-files"
while IFS= read -r file; do
  awk -v f="$file" '$1 == f' "$tmp/rr-modes" > "$tmp/rr-modes1"
  n="$(wc -l < "$tmp/rr-modes1" | tr -d ' ')"
  rr_dev="$(deviation_reason root-runs "$file")"
  if [ -n "$rr_dev" ]; then head -1 "$tmp/rr-modes1" > "$tmp/rr-modes20"; else head -20 "$tmp/rr-modes1" > "$tmp/rr-modes20"; fi
  while read -r _f path uid gid mode; do
    fail root-runs "$file installs $(dec "$path") as $mode $uid:$gid; root runs from a product's tree, so every entry on the way to and under opt/mavergreen/ and Applications/Mavergreen/ is 0:0 and grants no group or other write" "$file" \
      "build the component with build_component_pkg.sh, which strips group and other write, or chmod -R go-w the staged tree and rebuild"
  done < "$tmp/rr-modes20"
  [ -n "$rr_dev" ] || [ "$n" -le 20 ] || echo "conformance: root-runs: ... and $((n - 20)) more in $file" >&2
done < "$tmp/rr-files"

# spec: explain/os-overwrite.md -- a regular product only adds files to Mac OS X 10.9.5.
if has pkg; then
  awk '$1 == "edition" && $3 == "system" { s[$2] = 1 }
       $1 == "name" && $3 == "identifier" { id[$2] = $4 }
       END { for (p in s) if (p in id) print id[p] }' "$facts" > "$tmp/ow-system"
  awk 'FILENAME == ARGV[1] { sys[$1] = 1; next }
       $1 == "pkg" && !($5 in sys) && $5 !~ /\.system-replace$/ { reg[$2] = 1 }
       $1 == "installs" && ($2 in reg) { print $2, $3 }' "$tmp/ow-system" "$facts" > "$tmp/ow-installs"
  : > "$tmp/ow-dev"; : > "$tmp/ow-fail"; : > "$tmp/ow-hits"
  ow_inv="$SELF/os-inventory-10.9.5.gz"
  ow_rc=0
  gzip -t "$ow_inv" 2>/dev/null && gzip -dc "$ow_inv" 2>/dev/null | head -1 | grep -q . || ow_rc=3
  if [ "$ow_rc" -eq 0 ] && [ -s "$tmp/ow-installs" ]; then
    awk '{ p = $2; gsub(/%20/, " ", p); gsub(/%25/, "%", p); print p }' "$tmp/ow-installs" | LC_ALL=C sort -u > "$tmp/ow-want"
    gzip -dc "$ow_inv" | LC_ALL=C comm -12 - "$tmp/ow-want" > "$tmp/ow-shipped" || ow_rc=3
    awk 'FILENAME == ARGV[1] { s[$0] = 1; next }
         { p = $2; gsub(/%20/, " ", p); gsub(/%25/, "%", p); if (p in s) print $1, $2 }' \
      "$tmp/ow-shipped" "$tmp/ow-installs" > "$tmp/ow-hits"
  fi
  if [ "$ow_rc" -ne 0 ]; then
    chk_fail os-overwrite "$(rule_of os-overwrite)" \
      "scripts/os-inventory-10.9.5.gz is missing, empty or unreadable, so nothing says which files 10.9.5 ships" \
      "restore scripts/os-inventory-10.9.5.gz from shipyard, or regenerate it on a 10.9.5 Mac with gen-os-inventory.sh | gzip -9n"
  else
    LC_ALL=C sort "$tmp/ow-hits" | while read -r file path; do
      p="$(dec "$path")"
      r="$(deviation_reason os-overwrite "$p")"
      if [ -n "$r" ]; then printf '%s\n' "$r" >> "$tmp/ow-dev"
      else printf '%s %s\n' "$file" "$path" >> "$tmp/ow-fail"; fi
    done
    sort "$tmp/ow-dev" | uniq -c | while read -r n r; do
      echo "conformance: os-overwrite: DECLARED DEVIATION ($n files) -- $r"
    done
    head -20 "$tmp/ow-fail" > "$tmp/ow-fail20"
    while read -r file path; do
      chk_fail os-overwrite "$(rule_of os-overwrite)" \
        "$file overwrites $(dec "$path"), which Mac OS X 10.9.5 ships; a regular product may only add files" "$(fix_of os-overwrite)"
    done < "$tmp/ow-fail20"
    ow_nfail="$(wc -l < "$tmp/ow-fail" | tr -d ' ')"
    [ "$ow_nfail" -le 20 ] || echo "conformance: os-overwrite: ... and $((ow_nfail - 20)) more" >&2
  fi
fi

# spec: SKILL.md "Artifact conformance" axis table -- ITSELF: the appcast describes this release, and
#       its enclosure names a published asset at its real length.
while read -r kind file ver enclosure length minos; do
  [ "$kind" = appcast ] || continue
  [ "$ver" = "$expected" ] \
    || fail version "$file advertises version $ver, the release is $expected" "$file"
  actual="$(sed -n "s/^asset $enclosure \(..*\)$/\1/p" "$facts" | head -1)"
  if [ -z "$actual" ]; then
    fail enclosure "$file points at '$enclosure', which is not among the published assets" "$file"
  elif [ "$actual" != "$length" ]; then
    fail length "$file says '$enclosure' is $length bytes; it is $actual" "$file"
  fi
done < "$facts"

# platform: an enclosure URL carries the release tag.
while read -r kind file url; do
  [ "$kind" = enclosure-url ] || continue
  # platform: a self-upstream product's tag carries a leading v (magic-trackpad2's v0.5.5), while
  #           $expected is the bare version, so both spellings name THIS release.
  case "$url" in
    */download/"$expected"/*|*/download/v"$expected"/*) : ;;
    *) fail enclosure-url "$file points outside this release: $url -- Sparkle would silently serve users a different build than the one just published, and every other check here still passes because both artifacts are individually fine" "$file" ;;
  esac
done < "$facts"

while read -r kind af _ enc _; do
  [ "$kind" = appcast ] || continue
  ep="$(awk -v f="$enc" '$1 == f { print $2; exit }' "$tmp/prod-of")"
  [ -n "$ep" ] || continue
  [ "$af" = "$ep.xml" ] \
    || fail feed "$af describes $enc, which ships $ep; its feed is $ep.xml, the file the Engine reads for $ep" "$af"
done < "$facts"

# spec: SKILL.md "Release notes", "Three enforcement layers" -- this is the conformance layer: does
#       the Sparkle appcast's <description> agree with the GitHub Release body, which neither the gate
#       nor the publisher can see (both run before the appcast exists). Edge cases (a notes file
#       staged under a name this check doesn't recognize, an appcast with no matching render) are
#       covered in tests/artifact-conformance-test.sh.
render="$(sed -n 's/^notes-render [^ ]* \(..*\)$/\1/p' "$facts" | head -1)"
appcast_notes="$(grep '^appcast-notes ' "$facts" || true)"
if [ -n "$render" ]; then
  compared=0
  while read -r _ file digest; do
    [ -n "$file" ] || continue
    compared=$((compared + 1))
    if [ -z "$digest" ]; then
      fail notes "$file carries no <description>; that is what a 10.9 user reads in the update dialog" "$file"
    elif [ "$digest" != "$render" ]; then
      fail notes "$file's <description> is not the release body; Sparkle users and the Release page would read different notes" "$file"
    fi
  done <<EOF
$appcast_notes
EOF
  if [ "$compared" -gt 0 ]; then
    echo "conformance: notes: compared $compared appcast description(s) against the rendered release body"
  else
    echo "conformance: notes: no appcast in this release (nothing to compare)"
  fi
elif [ -n "$appcast_notes" ]; then
  while read -r _ file _digest; do
    [ -n "$file" ] || continue
    fail notes "$file carries a description, but no notes-render fact exists to compare it against -- the notes file may be staged under a name this check does not recognize" "$file"
  done <<EOF
$appcast_notes
EOF
else
  echo "conformance: notes: no notes file staged (nothing to compare)"
fi

# spec: SKILL.md "Artifact conformance", "Record what a variant was built FROM" -- NEIGHBOURS:
#       variants of one release must agree about their ingredients; the artifacts themselves cannot
#       answer this (golang's native .pkg carries the CA bundle/shim, its cross .pkg legitimately does
#       not), so each variant records what it used and this compares the records.
bi_files="$(sed -n 's/^build-info \([^ ][^ ]*\) .*/\1/p' "$facts" | sort -u | wc -l | tr -d ' ')"
if [ "$bi_files" -gt 0 ]; then
  echo "conformance: ingredients: compared $bi_files build records"
else
  echo "conformance: ingredients: no build records in this release (nothing to compare)"
fi

per_variant=" variant arch prefix pkg identifier "
for key in $(sed -n 's/^build-info [^ ][^ ]* \([^ ][^ ]*\) .*/\1/p' "$facts" | sort -u); do
  case "$per_variant" in *" $key "*) continue ;; esac
  vals="$(sed -n "s/^build-info [^ ][^ ]* $key \(..*\)$/\1/p" "$facts" | sort -u)"
  [ "$(printf '%s\n' "$vals" | wc -l | tr -d ' ')" -le 1 ] && continue
  files="$(sed -n "s/^build-info \([^ ][^ ]*\) $key .*/\1/p" "$facts" | tr '\n' ' ')"
  fail ingredients "variants disagree about $key: $(printf '%s' "$vals" | tr '\n' '/') (from $files)"
done

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- every shipped
#       Mach-O slice records its arch's pinned minos and SDK, unless a declared sdk-pin:<glob>
#       deviation names its path.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- a slice is
#       judged at the floor of the product its artifact's manifest names; an artifact with no manifest, or
#       a product with no floor fact, at 10.9.5.
sdk_floor_file=""; sdk_floor=10.9.5
while read -r kind file path arch ft mn sd sha; do
  [ "$kind" = macho ] || continue
  if [ "$file" != "$sdk_floor_file" ]; then
    sdk_floor_file="$file"
    sdk_floor="$(awk -v f="$file" '
      $1 == "manifest" && $2 == f && !(f in m) { m[f] = $3 }
      $1 == "floor" { fl[$2] = $3 }
      END { print (m[f] in fl) ? fl[m[f]] : "10.9.5" }' "$facts")"
  fi
  why="$(shipyard_sdk_rule "$arch" "$ft" "$mn" "$sd" "$sdk_floor")" \
    || fail sdk-pin "$file installs $(dec "$path") ($arch): $why" "$(dec "$path")"
done < "$facts"

# spec: explain/arch-host.md -- a host binary ships x86_64 unless an arch-host deviation's scope matches
#       its install path; a target file is not a host binary. A repo
#       grandfathered as modern-smoke is warned.
targets_of() {  # $1 = product; its target globs, decoded, one per line
  awk -v p="$1" '$1 == "target" && $2 == p { print $3 }' "$facts" | sed -e 's/%20/ /g' -e 's/%25/%/g'
}
prod_of() { awk -v f="$1" '$1 == "manifest" && $2 == f { print $3; exit }' "$facts"; }
arm_gf=no
[ -n "$repository" ] && [ -f "$SELF/conventions-grandfathered" ] \
  && grep -qxF "modern-smoke ${repository#*/} release.yml:modern-smoke" "$SELF/conventions-grandfathered" && arm_gf=yes
awk '$1 == "pkg" { pkg[$2] = 1 }
     $1 == "macho" && $4 ~ /^arm64e?$/ && !(($2 " " $3) in seen) { seen[$2 " " $3] = 1; arm[++n] = $2 " " $3 }
     END { for (i = 1; i <= n; i++) { split(arm[i], m, " "); if (m[1] in pkg) print arm[i] } }' "$facts" > "$tmp/arm64"
arm_declared=0; arm_undeclared=0; ah_file=; ah_tree=
while read -r file path; do
  p="$(dec "$path")"
  if [ "$file" != "$ah_file" ]; then
    ah_file="$file"; ah_tree=; : > "$tmp/ah-targets"
    ah_prod="$(prod_of "$file")"
    if [ -n "$ah_prod" ]; then ah_tree="opt/mavergreen/$ah_prod/"; targets_of "$ah_prod" > "$tmp/ah-targets"; fi
  fi
  if [ -n "$ah_tree" ] && [ -s "$tmp/ah-targets" ]; then
    case "$p" in "$ah_tree"*) ! arch_is_target "${p#"$ah_tree"}" "$tmp/ah-targets" || continue ;; esac
  fi
  if [ -n "$(deviation_reason arch-host "$p")" ]; then arm_declared=$((arm_declared + 1)); continue; fi
  arm_undeclared=$((arm_undeclared + 1))
  [ "$arm_undeclared" -le 20 ] || continue
  msg="$file installs $p with an arm64 slice, and no .mavergreen/deviations/arch-host/ scope matches that install path"
  if [ "$arm_gf" = yes ]; then
    echo "::warning::conformance: arch-host: $msg (grandfathered: modern-smoke ${repository#*/})"
  else
    chk_fail arch-host "$(rule_of arch-host)" "$msg" "$(fix_of arch-host)"
  fi
done < "$tmp/arm64"
if [ "$arm_undeclared" -gt 20 ]; then
  if [ "$arm_gf" = yes ]; then echo "::warning::conformance: arch-host: and $((arm_undeclared - 20)) more undeclared arm64 host files"
  else echo "conformance: arch-host: and $((arm_undeclared - 20)) more undeclared arm64 host files" >&2; fi
fi
[ "$arm_declared" -eq 0 ] && [ "$arm_undeclared" -eq 0 ] \
  || echo "conformance: arch-host: $arm_declared declared, $arm_undeclared undeclared arm64 host files in pkgs"

# spec: explain/arch-target.md -- every target glob matches an installed file of its product, and no
#       host binary of the same pkg loads a target file; loads are resolved lexically from the loader's
#       directory, @rpath through each of its rpaths.
tab="$(printf '\t')"
for at_prod in $(awk '$1 == "target" { print $2 }' "$facts" | LC_ALL=C sort -u); do
  at_pkgs="$(awk -v p="$at_prod" '$1 == "manifest" && $3 == p { print $2 }' "$facts" | LC_ALL=C sort -u)"
  [ -n "$at_pkgs" ] || continue
  at_tree="opt/mavergreen/$at_prod/"
  targets_of "$at_prod" > "$tmp/at-globs"
  for at_pkg in $at_pkgs; do
    awk -v f="$at_pkg" -v t="$at_tree" '$1 == "installs" && $2 == f && index($3, t) == 1 { print substr($3, length(t) + 1) }' "$facts"
  done | sed -e 's/%20/ /g' -e 's/%25/%/g' > "$tmp/at-installs"
  : > "$tmp/at-targets"
  while IFS= read -r at_rel; do
    ! arch_is_target "$at_rel" "$tmp/at-globs" || printf '%s%s\n' "$at_tree" "$at_rel" >> "$tmp/at-targets"
  done < "$tmp/at-installs"
  while IFS= read -r at_g; do
    [ -n "$at_g" ] || continue
    printf '%s\n' "$at_g" > "$tmp/at-one"
    at_hit=0
    while IFS= read -r at_rel; do
      if arch_is_target "$at_rel" "$tmp/at-one"; then at_hit=1; break; fi
    done < "$tmp/at-installs"
    [ "$at_hit" -eq 1 ] \
      || arch_fail arch-target "the target glob $at_g matches no file $at_prod installs, so .mavergreen/products/$at_prod/target declares a file the pkg does not ship"
  done < "$tmp/at-globs"
  [ -s "$tmp/at-targets" ] || continue
  for at_pkg in $at_pkgs; do
    awk -v f="$at_pkg" '
      function dec(s) { gsub(/%20/, " ", s); gsub(/%25/, "%", s); return s }
      function norm(s,   n, c, i, k, o, r) {
        n = split(s, c, "/"); k = 0
        for (i = 1; i <= n; i++) {
          if (c[i] == "" || c[i] == ".") continue
          if (c[i] == "..") { if (k > 0) k--; continue }
          o[++k] = c[i]
        }
        r = ""; for (i = 1; i <= k; i++) r = r (i > 1 ? "/" : "") o[i]
        return r
      }
      function res(v, d) {
        if (v == "@loader_path" || v == "@executable_path") return norm(d)
        if (index(v, "@loader_path/") == 1) return norm(d "/" substr(v, 14))
        if (index(v, "@executable_path/") == 1) return norm(d "/" substr(v, 18))
        if (index(v, "/") == 1) return norm(v)
        return ""
      }
      $1 == "macho-load" && $2 == f {
        k = $3 SUBSEP $4
        if ($5 == "rpath") { rp[k] = rp[k] dec($6) "\n"; next }
        if ($5 == "dylib") { ld[++n] = k; lv[n] = dec($6); lp[n] = dec($3) }
      }
      END {
        for (i = 1; i <= n; i++) {
          d = lp[i]; sub(/\/[^\/]*$/, "", d); v = lv[i]
          if (index(v, "@rpath/") == 1) {
            m = split(rp[ld[i]], r, "\n")
            for (j = 1; j <= m; j++) { b = res(r[j], d); if (b != "") print lp[i] "\t" norm(b "/" substr(v, 8)) "\t" v }
          } else {
            b = res(v, d); if (b != "") print lp[i] "\t" b "\t" v
          }
        } }' "$facts" | LC_ALL=C sort -u > "$tmp/at-loads"
    while IFS="$tab" read -r at_ld at_to at_raw; do
      grep -qxF -- "$at_to" "$tmp/at-targets" || continue
      ! grep -qxF -- "$at_ld" "$tmp/at-targets" || continue
      arch_fail arch-target "$at_pkg: $at_ld loads $at_to ($at_raw), a target file"
    done < "$tmp/at-loads"
  done
done

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact conformance" -- one C++
#       runtime per process; a cxxabi deviation whose scope is a glob excuses a path, and a path grandfathered as cxxabi
#       for this repo is warned.
awk 'function add(list, v) { return index(" " list " ", " " v " ") ? list : (list == "" ? v : list " " v) }
     $1 == "cxxabi-defines" || $1 == "cxxabi-loads" || $1 == "cxxabi-unjudgeable" {
       k = $2 " " $3; if (!(k in seen)) { o[++m] = k; seen[k] = 1; da[k] = ""; la[k] = ""; ua[k] = ""; n[k] = 0; s[k] = ""; l[k] = "" }
       if ($1 == "cxxabi-loads") { la[k] = add(la[k], $4); l[k] = add(l[k], $5); next }
       if ($1 == "cxxabi-unjudgeable") { ua[k] = add(ua[k], $4); next }
       da[k] = add(da[k], $4)
       sym = $5 ($6 == "hidden" ? "(hidden)" : "")
       if ((k SUBSEP sym) in d) next
       d[k, sym] = 1; if (++n[k] <= 5) s[k] = s[k] " " sym
     }
     END { for (i = 1; i <= m; i++) { k = o[i]
             f = (da[k] == "" ? "-" : da[k]); g = (la[k] == "" ? "-" : la[k]); h = (l[k] == "" ? "-" : l[k])
             u = (ua[k] == "" ? "-" : ua[k])
             gsub(/ /, ",", f); gsub(/ /, ",", g); gsub(/ /, ",", h); gsub(/ /, ",", u)
             print k, f, g, u, n[k], h s[k] } }' "$facts" > "$tmp/cxxabi"
cxx_report() {  # $1 = message; a grandfathered path ($gf) warns, anything else fails cxxabi
  if [ -n "$gf" ]; then echo "::warning::conformance: cxxabi: $1 (grandfathered: $gf)"
  else chk_fail cxxabi "$(rule_of cxxabi)" "$1" "$how"; fi
}
cxx_fail=0
while read -r file path darches larches uarches n loads syms; do
  p="$(dec "$path")"
  gf=""
  if [ -z "$(deviation_reason cxxabi "$p")" ]; then
    [ -n "$repository" ] && [ -f "$SELF/conventions-grandfathered" ] \
      && grep -qxF "cxxabi ${repository#*/} $path" "$SELF/conventions-grandfathered" && gf="cxxabi ${repository#*/} $path"
    if [ -z "$gf" ]; then cxx_fail=$((cxx_fail + 1)); [ "$cxx_fail" -le 20 ] || { chk_status=1; continue; }; fi
  else
    echo "conformance: cxxabi: DECLARED DEVIATION ($p) -- $(deviation_reason cxxabi "$p")"
    continue
  fi
  how="link the family's runtime (libcxx22), or declare .mavergreen/deviations/cxxabi/<label>/ (scope $p, a reason, a revisit)"
  if [ "$n" -gt 0 ]; then
    more=""; [ "$n" -le 5 ] || more=" and $((n - 5)) more"
    cxx_report "$file installs $p ($darches), which defines C++ runtime machinery beyond Recaulk's back-fills: $syms$more -- one process gets one C++ runtime, hidden or not"
  fi
  if [ "$uarches" != - ]; then
    cxx_report "$file: $p ($uarches) has C++ exception tables but names no personality routine, so its C++ runtime cannot be judged; strip it with -S, never -x"
  fi
  if [ "$loads" != - ]; then
    cxx_report "$file installs $p ($larches), which loads $(dec "$(printf '%s' "$loads" | sed 's/,/, /g')") -- a process may load only /usr/lib/libc++abi.dylib or libcxx22's libc++abi.1.dylib"
  fi
done < "$tmp/cxxabi"
[ "$cxx_fail" -le 20 ] || echo "conformance: cxxabi: and $((cxx_fail - 20)) more files with a second C++ runtime" >&2
nmacho="$(grep -c '^macho ' "$facts" || :)"
[ "$nmacho" -eq 0 ] || echo "conformance: cxxabi: checked $nmacho Mach-O slices"

# spec: explain/debug-map.md -- a shipped image is stripped of its debug map and names no builder's
#       directory; a deviation excuses a path.
awk '$1 == "oso" || $1 == "homepath" { k = $2 " " $3; if (!(k in o)) { o[k] = ++n; r[n] = k }
       if ($1 == "oso") a[k] = a[k] (a[k] == "" ? "" : ",") $4; else if (!(k in h)) h[k] = $4 }
     END { for (i = 1; i <= n; i++) { k = r[i]; print k, (a[k] == "" ? "-" : a[k]), (h[k] == "" ? "-" : h[k]) } }' \
  "$facts" > "$tmp/debug-map"
while read -r file path oarch home; do
  p="$(dec "$path")"
  if [ "$oarch" != - ]; then
    fail debug-map "$file ships $p ($oarch) with its debug map, which names the objects it was linked from -- split-debug.sh moves the DWARF to a dSYM and strips it" "$p"
  fi
  if [ "$home" != - ]; then
    fail debug-map "$file ships $p, which names $(dec "$home") -- a builder's directory in a shipped image" "$p"
  fi
done < "$tmp/debug-map"

# spec: explain/link-rpath.md -- a family dylib under /opt/mavergreen/ or /usr/local/mavergreen/ is loaded by
#       its absolute path only from inside its own product tree, and an image loading @rpath/libc++.1.dylib
#       resolves its first LC_RPATH, from where the pkg installs it, to opt/mavergreen/libcxx22/lib. A standalone
#       archive's SHORT-VERSION/ is where its pkg installs SHORT; a deviation excuses a path.
awk -v ver="${expected#v}" '
  function inst(f, p,   top, s, r) {
    if (f !~ /-macos-(universal|x86_64|arm64)\.tar\.gz$/) return p
    top = f; sub(/-macos-(universal|x86_64|arm64)\.tar\.gz$/, "", top)
    if (index(p, top "/") != 1) return p
    r = substr(p, length(top) + 2); s = top
    if (ver != "" && substr(s, length(s) - length(ver)) == "-" ver) s = substr(s, 1, length(s) - length(ver) - 1)
    if (r ~ /^[^\/]+\.app(\/|$)/) return "Applications/Mavergreen/" r
    return "opt/mavergreen/" s "/" r
  }
  function norm(p,   n, c, i, k, o, out) {
    n = split(p, c, "/"); k = 0
    for (i = 1; i <= n; i++) {
      if (c[i] == "" || c[i] == ".") continue
      if (c[i] == "..") { if (k > 0) k--; else return "(outside the root)"; continue }
      o[++k] = c[i]
    }
    out = ""; for (i = 1; i <= k; i++) out = out (i > 1 ? "/" : "") o[i]
    return out
  }
  function resolve(r, img,   d) {
    if (r ~ /^@(loader|executable)_path(\/|$)/) {
      d = img; sub(/\/[^\/]*$/, "", d); if (d == img) d = ""
      sub(/^@[a-z_]*/, "", r); return norm(d "/" r)
    }
    if (r ~ /^\//) return norm(r)
    return "(unresolvable)"
  }
  $1 == "rpath" { k = $2 " " $3 " " $4; if (!(k in first) || $5 + 0 < fn[k]) { first[k] = $6; fn[k] = $5 + 0 }; next }
  $1 == "load" { nl++; la[nl] = $2; lp[nl] = $3; lh[nl] = $4; lv[nl] = $5 }
  END {
    for (i = 1; i <= nl; i++) {
      img = inst(la[i], lp[i]); v = lv[i]; gsub(/%20/, " ", img); gsub(/%25/, "%", img)
      if (v ~ /^\/(opt|usr\/local)\/mavergreen\/[^\/]+\//) {
        t = v; sub(/^\//, "", t)
        if (t ~ /^opt\//) { match(t, /^opt\/mavergreen\/[^\/]+\//) } else { match(t, /^usr\/local\/mavergreen\/[^\/]+\//) }
        if (index(img, substr(t, 1, RLENGTH)) != 1) print "absolute", la[i], lp[i], lh[i], v, substr(t, 1, RLENGTH)
        continue
      }
      if (v != "@rpath/libc++.1.dylib") continue
      k = la[i] " " lp[i] " " lh[i]
      if (!(k in first)) { print "norpath", la[i], lp[i], lh[i], v, "-"; continue }
      r = first[k]; gsub(/%20/, " ", r); gsub(/%25/, "%", r)
      to = resolve(r, img)
      if (to != "opt/mavergreen/libcxx22/lib") { gsub(/ /, "%20", to); print "order", la[i], lp[i], lh[i], first[k], to }
    }
  }' "$facts" > "$tmp/link-rpath"
while read -r how file path arch val to; do
  p="$(dec "$path")"
  case "$how" in
    absolute) fail link-rpath "$file ships $p ($arch), which loads $(dec "$val") by its absolute path from outside $to -- a family dylib is loaded by @rpath, so the installed and the bundled copy are one" "$p" ;;
    norpath) fail link-rpath "$file ships $p ($arch), which loads @rpath/libc++.1.dylib, and has no LC_RPATH -- dyld cannot find libcxx22" "$p" ;;
    order) fail link-rpath "$file ships $p ($arch), which loads @rpath/libc++.1.dylib, and its first LC_RPATH, $(dec "$val"), resolves to $(dec "$to"), not opt/mavergreen/libcxx22/lib -- the installed libcxx22 comes first, so one libc++ serves the process" "$p" ;;
  esac
done < "$tmp/link-rpath"

# spec: explain/weak-bind-sorted.md -- 10.9's dyld coalesces weak symbols across images only from
#       name-sorted weak-bind info; a deviation excuses a path.
awk '$1 == "weakbind-unsorted" { k = $2 " " $3; if (!(k in o)) { o[k] = ++n; r[n] = k; a[k] = $4; s[k] = $5 } else a[k] = a[k] "," $4 }
     END { for (i = 1; i <= n; i++) print r[i], a[r[i]], s[r[i]] }' "$facts" > "$tmp/weak-bind"
while read -r file path arch sym; do
  p="$(dec "$path")"
  fail weak-bind-sorted "$file ships $p ($arch), whose weak-bind info is not sorted by name (first out of order: $sym) -- 10.9's dyld then leaves weak symbols such as a class's type_info duplicated across images" "$p"
done < "$tmp/weak-bind"

# spec: explain/dsym-asset.md -- each linked slice's LC_UUID is among the DWARF of the release's
#       *-dSYM.tar.gz; a deviation excuses a path.
awk '$1 == "dsym" { d[$5] = 1; nd++ }
     $1 == "uuid" { k = $2 " " $3; if (!(k in o)) { o[k] = ++n; r[n] = k; m[k] = "" }
       u[++nu] = k; ua[nu] = $4; uu[nu] = $5 }
     END { for (j = 1; j <= nu; j++) if (!(uu[j] in d)) { k = u[j]; m[k] = m[k] (m[k] == "" ? "" : ",") ua[j] ":" uu[j] }
           for (i = 1; i <= n; i++) if (m[r[i]] != "") print r[i], m[r[i]], nd + 0 }' "$facts" > "$tmp/dsym-asset"
while read -r file path missing nd; do
  p="$(dec "$path")"
  if [ "$nd" -eq 0 ]; then
    fail dsym-asset "$file ships $p, and this release ships no *-dSYM.tar.gz to hold its DWARF ($missing)" "$p"
  else
    fail dsym-asset "$file ships $p, whose LC_UUID ($missing) no *-dSYM.tar.gz of this release holds -- its dSYM is another build's, or missing" "$p"
  fi
done < "$tmp/dsym-asset"

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Kexts that load at boot" -- a
#       kext in Library/Extensions that loads other than as a dependency is listed through
#       stage_product.sh --boot-kext or declared as a kext-sig-exception deviation; the facility lists
#       only kexts the pkg ships; and no script edits Apple's exclude list itself, which no deviation excuses.
kind_ran pkg ".pkg" kext-sig-exception kext-exclude-list
while read -r kind file path id how; do
  [ "$kind" = kext ] && [ "$how" = boot ] || continue
  case "$path" in Library/Extensions/*.kext) ;; *) continue ;; esac
  case "${path#Library/Extensions/}" in */*) continue ;; esac
  awk -v p="$file" -v i="$id" '$1 == "kext-exception" && $2 == p && $3 == i { f = 1 } END { exit !f }' "$facts" \
    || fail kext-sig-exception "$file installs $(dec "$path") ($id), which 10.9's kextd refuses unsigned unless its id is in OSKextSigExceptionList -- stage it with stage_product.sh --boot-kext $id, or declare .mavergreen/deviations/kext-sig-exception/<label>/ scoped to $id" "$id"
done < "$facts"
while read -r kind file id; do
  [ "$kind" = kext-exception ] || continue
  awk -v p="$file" -v i="$id" '$1 == "kext" && $2 == p && $4 == i { f = 1 } END { exit !f }' "$facts" \
    || fail kext-sig-exception "$file lists $id in OSKextSigExceptionList but installs no kext with that CFBundleIdentifier -- the list carries exactly the kexts a product ships" "$id"
done < "$facts"
while read -r kind file script; do
  [ "$kind" = excludelist-script ] || continue
  chk_fail kext-exclude-list "$(rule_of kext-exclude-list)" \
    "$file's $script edits AppleKextExcludeList other than through stage_product.sh --boot-kext" \
    "every other key of Apple's file is left alone, so declare the kext's id with --boot-kext and drop the hand-written edit"
done < "$facts"

[ "$chk_status" -ne 0 ] || echo "conformance: ok — $expected"
exit "$chk_status"
