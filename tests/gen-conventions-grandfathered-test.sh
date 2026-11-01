#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/deviation_tree.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/gen-gf-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT
python3 -c 'import yaml' 2>/dev/null || { echo "SKIP: needs a python3 with PyYAML"; exit 77; }

# spec: scripts/gen-conventions-grandfathered.sh -- a stand-in gh serves the org's repo list from
#       $FAKE_REPOS and clones from a local source repo, so the generator runs offline.
mkdir -p "$work/bin" "$work/root" "$work/src"
cp -R "$here/../scripts" "$work/root/scripts"; rm -f "$work/root/scripts/conventions-grandfathered"
G="$work/root/scripts/gen-conventions-grandfathered.sh"
cat > "$work/bin/gh" <<'SH'
#!/bin/sh
case "$1 $2" in
  "repo list") cat "$FAKE_REPOS" ;;
  "repo clone")
    name="${3#Mavergreen/}"; dir="$4"
    git clone -q "file://$FAKE_SRC/$name" "$dir" >/dev/null 2>&1
    git -C "$dir" config "url.file://$FAKE_SRC/$name.insteadOf" "https://github.com/Mavergreen/$name.git"
    git -C "$dir" remote set-url origin "https://github.com/Mavergreen/$name.git" ;;
  "release view")
    name="${4#Mavergreen/}"
    [ ! -f "$FAKE_SRC/$name.release-error" ] || { cat "$FAKE_SRC/$name.release-error" >&2; exit 1; }
    [ -d "$FAKE_SRC/$name.release" ] || { echo "release not found" >&2; exit 1; }
    cat "$FAKE_SRC/$name.release/.tag"; ls "$FAKE_SRC/$name.release" ;;
  "release download")
    name="${5#Mavergreen/}"; dir="${9:?}"
    [ "$3" = "$(cat "$FAKE_SRC/$name.release/.tag")" ] || { echo "fake gh: no release $3" >&2; exit 1; }
    mkdir -p "$dir"; cp "$FAKE_SRC/$name.release/"*.pkg "$dir/" ;;
  *) echo "fake gh: $*" >&2; exit 1 ;;
esac
SH
cat > "$work/bin/lipo" <<'SH'
#!/bin/sh
printf 'Non-fat file: %s is architecture: arm64\n' "$2"
SH
cat > "$work/bin/otool" <<'SH'
#!/bin/sh
[ "$1" = -hv ] || exit 0
printf '%s:\nMach header\n      magic cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags\nMH_MAGIC_64   ARM64        ALL  0x00     EXECUTE     0          0 0x00000000\n' "$2"
SH
cat > "$work/bin/nm" <<'SH'
#!/bin/sh
case "$2" in
  */throws) printf '0000000100000f50 (__TEXT,__text) external ___cxa_throw\n' ;;
  */librecaulk.a) printf '0000000000000000 (__TEXT,__text) external ___cxa_uncaught_exceptions\n' ;;
esac
SH
chmod +x "$work/bin/lipo" "$work/bin/otool" "$work/bin/nm"
LIPO="$work/bin/lipo"; OTOOL="$work/bin/otool"; NM="$work/bin/nm"; export LIPO OTOOL NM
STEVEDORE="$(sh "$here/../scripts/fetch_stevedore.sh")" || { echo "FAIL: fetch_stevedore.sh failed -- the generator reads each repo's released pkgs with it"; exit 1; }
export STEVEDORE
chmod +x "$work/bin/gh"
# spec: scripts/cxxabi-allowlist.sh -- the allow-list is read from the pinned Recaulk's librecaulk.a, served
#       here from a file:// release tree so the generator's cxxabi facts need no network.
rv="$(sed -n 's/^RECAULK_VERSION=//p' "$here/../scripts/recaulk.pin")"
rr="$work/rel/Mavergreen/recaulk/releases/download/$rv"; mkdir -p "$rr" "$work/rc/usr/local/mavergreen/recaulk/lib"
printf '!<arch>\n' > "$work/rc/usr/local/mavergreen/recaulk/lib/librecaulk.a"
"$STEVEDORE" component --root "$work/rc" --identifier dev.mavergreen.recaulk --version "$rv" --install-location / \
  --mtime 1700000000 --out "$work/rc.pkg" >/dev/null || { echo "FAIL: stevedore could not build the Recaulk fixture component"; exit 1; }
printf '<?xml version="1.0" encoding="utf-8"?>\n<installer-gui-script minSpecVersion="1">\n  <pkg-ref id="dev.mavergreen.recaulk" version="%s">rc.pkg</pkg-ref>\n  <choices-outline><line choice="r"/></choices-outline>\n  <choice id="r"><pkg-ref id="dev.mavergreen.recaulk"/></choice>\n</installer-gui-script>\n' "$rv" > "$work/rc.xml"
"$STEVEDORE" product --distribution "$work/rc.xml" --package "$work/rc.pkg" --mtime 1700000000 --out "$rr/recaulk-$rv.pkg" >/dev/null \
  || { echo "FAIL: stevedore could not build the Recaulk fixture pkg"; exit 1; }
(cd "$rr" && shasum -a 256 "recaulk-$rv.pkg" > SHA256SUMS)
MAVERGREEN_RELEASES="file://$work/rel"; MAVERGREEN_PKG_CACHE="$work/cache"; export MAVERGREEN_RELEASES MAVERGREEN_PKG_CACHE
PATH="$work/bin:$PATH"; export PATH
FAKE_REPOS="$work/repos"; FAKE_SRC="$work/src"; export FAKE_REPOS FAKE_SRC

mksrc() {  # $1 = name, $2 = yes: has a release workflow that calls the gate and runs on macos, $3 = decl: declares an arm64 slice
  d="$work/src/$1"; mkdir -p "$d"
  [ "${3:-}" != decl ] || deviation "$d" arm64 bin "usr/local/mavergreen/$1/bin/*" 'developers on Apple Silicon run it'
  [ "${3:-}" != cxxdecl ] || deviation "$d" cxxabi bin "usr/local/mavergreen/$1/bin/*" 'upstream vendors its runtime; exit: when it links libcxx22'
  if [ "$2" = yes ]; then
    mkdir -p "$d/.github/workflows"
    printf '# calls family-conventions.yml\nname: release\non: push\njobs:\n  build:\n    runs-on: macos-14\n    steps:\n      - run: true\n' > "$d/.github/workflows/release.yml"
  else
    printf 'x\n' > "$d/README"
  fi
  (cd "$d" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -q -m init)
}
# spec: scripts/gen-conventions-grandfathered.sh -- modern-smoke is found two ways: the gate's own
#       static finding, and the latest release's pkgs read by artifact-facts.sh and the conformance
#       checker, since a repo that ships an undeclared arm64 slice and has no modern-smoke job passes
#       the static half.
mkrel() {  # $1 = name, $2 = tool|throws|updater|none: where the pkg's arm64 Mach-O is (throws: one that defines ___cxa_throw)
  r="$work/src/$1.release"; st="$work/stage-$1"; mkdir -p "$r" "$st"; printf 'v1\n' > "$r/.tag"
  case "$2" in
    tool|throws) mkdir -p "$st/usr/local/mavergreen/$1/bin"; m="$st/usr/local/mavergreen/$1/bin/$2" ;;
    updater)
      a="$st/Library/Application Support/Mavergreen/$1-updater.app/Contents"; mkdir -p "$a/MacOS"
      printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.mavergreen.%s.updater</string><key>SUFeedURL</key><string>https://github.com/Mavergreen/%s/releases/latest/download/%s.xml</string></dict></plist>\n' "$1" "$1" "$1" > "$a/Info.plist"
      m="$a/MacOS/$1-updater" ;;
    none) printf 'x\n' > "$r/notes.txt"; return 0 ;;
  esac
  printf '\317\372\355\376\014\000\000\001\000\000\000\000\002\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000' > "$m"
  "$STEVEDORE" component --root "$st" --identifier "dev.mavergreen.$1" --version 1 --install-location / \
    --mtime 1700000000 --out "$r/$1-1.pkg" >/dev/null || { echo "FAIL: stevedore could not build $1's fixture pkg"; exit 1; }
}
mksrc alpha yes; mksrc bravo no; mksrc charlie yes
mksrc delta yes; mkrel delta tool
mksrc echo yes decl; mkrel echo none
mksrc foxtrot yes; mkrel foxtrot updater
# spec: scripts/gen-conventions-grandfathered.sh -- cxxabi is found in the latest release's pkgs, one
#       line per undeclared path; a cxxabi:<glob> declaration keeps a path off the list.
mksrc golf yes; mkrel golf throws
mksrc hotel yes cxxdecl; mkrel hotel throws
printf '.github\nalpha\nbravo\ncharlie\ndelta\necho\nfoxtrot\ngolf\nhotel\n' > "$work/repos"

out="$(sh "$G" "$work/clones" 2>"$work/err")" || { echo "FAIL: generator failed: $(cat "$work/err")"; exit 1; }
want='cxxabi golf usr/local/mavergreen/golf/bin/throws
macos-runner alpha release.yml:build
macos-runner charlie release.yml:build
macos-runner delta release.yml:build
macos-runner echo release.yml:build
macos-runner foxtrot release.yml:build
macos-runner golf release.yml:build
macos-runner hotel release.yml:build
modern-smoke delta release.yml:modern-smoke
modern-smoke echo release.yml:modern-smoke
modern-smoke golf release.yml:modern-smoke
modern-smoke hotel release.yml:modern-smoke'
[ "$out" = "$want" ] || { echo "FAIL: a repo with no workflows must not swallow the repos after it; delta ships an undeclared arm64 tool, echo declares one with no job, foxtrot's arm64 is its updater's; the generator lists golf, whose latest release defines ___cxa_throw, and not hotel, which declares it: got [$out]"; exit 1; }
[ -f "$work/clones/.gen-conventions-grandfathered" ] || { echo "FAIL: the generator must mark the directory it owns"; exit 1; }

out="$(sh "$G" "$work/clones" 2>"$work/err")" || { echo "FAIL: a rerun in an owned directory must refresh: $(cat "$work/err")"; exit 1; }
[ "$out" = "$want" ] || { echo "FAIL: rerun differs: [$out]"; exit 1; }

printf 'HTTP 502: Bad Gateway\n' > "$work/src/charlie.release-error"
sh "$G" "$work/clones" >/dev/null 2>"$work/err" && { echo "FAIL: a release that cannot be read must fail the generator, not read as no release"; exit 1; }
grep -q 'charlie' "$work/err" || { echo "FAIL: the failure should name the repo: $(cat "$work/err")"; exit 1; }
rm -f "$work/src/charlie.release-error"

mkdir "$work/foreign"; printf 'mine\n' > "$work/foreign/file"
sh "$G" "$work/foreign" >/dev/null 2>&1 && { echo "FAIL: a non-empty directory without the sentinel must be refused"; exit 1; }
[ "$(cat "$work/foreign/file")" = mine ] && [ ! -e "$work/foreign/.gen-conventions-grandfathered" ] \
  || { echo "FAIL: a refused directory must be left untouched"; exit 1; }

mkdir "$work/empty"; sh "$G" "$work/empty" >/dev/null 2>&1 || { echo "FAIL: an empty directory is the generator's to use"; exit 1; }

git -C "$work/clones/alpha" remote set-url origin https://github.com/Somebody/alpha.git
printf 'dirty\n' > "$work/clones/alpha/keep"
sh "$G" "$work/clones" >/dev/null 2>"$work/err" && { echo "FAIL: a clone whose origin is not Mavergreen/<name> must be refused"; exit 1; }
grep -q 'not Mavergreen/alpha' "$work/err" || { echo "FAIL: the refusal should name the origin: $(cat "$work/err")"; exit 1; }
[ -f "$work/clones/alpha/keep" ] || { echo "FAIL: a refused clone must not be reset or removed"; exit 1; }

git -C "$work/clones/alpha" remote set-url origin https://github.com/Mavergreen/alpha.git
rm -rf "$work/clones/bravo"; mkdir "$work/clones/bravo"; printf 'x\n' > "$work/clones/bravo/f"
sh "$G" "$work/clones" >/dev/null 2>&1 && { echo "FAIL: a non-git directory where a clone belongs must be refused"; exit 1; }
[ -f "$work/clones/bravo/f" ] || { echo "FAIL: that directory must be left alone"; exit 1; }

# spec: scripts/gen-conventions-grandfathered.sh -- git walks up from a non-git directory, so an outer
#       checkout whose origin is Mavergreen/<name> must not pass for the clone and be reset.
mkdir -p "$work/outer/clones/alpha"; : > "$work/outer/clones/.gen-conventions-grandfathered"
git clone -q "file://$work/src/alpha" "$work/outer/co" >/dev/null 2>&1
mv "$work/outer/co/.git" "$work/outer/.git"; rm -rf "$work/outer/co"
git -C "$work/outer" remote set-url origin https://github.com/Mavergreen/alpha.git
git -C "$work/outer" -c user.name=t -c user.email=t@t commit -q --allow-empty -m local
printf 'dirty\n' > "$work/outer/keep"; head="$(git -C "$work/outer" rev-parse HEAD)"
printf 'alpha\n' > "$work/repos"
sh "$G" "$work/outer/clones" >/dev/null 2>"$work/err" && { echo "FAIL: a non-git directory inside an outer checkout must be refused"; exit 1; }
grep -q 'not itself a git checkout' "$work/err" || { echo "FAIL: the refusal should say why: $(cat "$work/err")"; exit 1; }
[ "$(git -C "$work/outer" rev-parse HEAD)" = "$head" ] && [ -f "$work/outer/keep" ] \
  || { echo "FAIL: the outer checkout must not be reset"; exit 1; }

printf 'alpha\n../escape\n' > "$work/repos"
sh "$G" "$work/clones2" >/dev/null 2>&1 && { echo "FAIL: a repo name that is a path must be refused"; exit 1; }

echo "PASS: gen-conventions-grandfathered"
