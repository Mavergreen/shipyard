#!/bin/sh
# platform: macOS-only -- pkgbuild and productbuild write the fixture pkgs
#   usage: build.sh
#          Rebuilds every checked-in fixture pkg: the real-payload set beside this script, which
#          tests/artifact-conformance-test.sh reads, and the dist/ directories under
#          tests/fixtures/checks/<id>/{pass,fail}/ that tests/dist-fixtures-test.sh runs the dist
#          checks over. The tests read the results and never run this, so they need no pkgbuild on
#          any host. Each pkg stays under 64 KB.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$here/../../.."
checks="$here/../checks"
macho="$here/../macho"
V=1.0.0-mavericks.1
w="$(mktemp -d "${TMPDIR:-/tmp}/pkg-fixtures.XXXXXX")"
trap 'rm -rf "$w"' EXIT
mkdir -p "$w/pool"

plist() {  # $1 = out; the rest: key value pairs
  out="$1"; shift
  { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>\n'
    while [ $# -ge 2 ]; do printf '<key>%s</key><string>%s</string>\n' "$1" "$2"; shift 2; done
    printf '</dict></plist>\n'; } > "$out"
}

manifest() {  # $1 = stage, $2 = product, $3 = identifier, $4 = extra XML (outside list, line)
  mkdir -p "$1/usr/local/mavergreen/$2"
  { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>\n'
    printf '<key>product</key><string>%s</string><key>identifier</key><string>%s</string>\n' "$2" "$3"
    printf '%s\n</dict></plist>\n' "${4:-}"; } > "$1/usr/local/mavergreen/$2/mavergreen.plist"
}

outside() {  # entries...
  printf '<key>outside</key><array>'
  for e in "$@"; do printf '<string>%s</string>' "$e"; done
  printf '</array>'
}

stage() { st="$w/st.$1"; rm -rf "$st"; mkdir -p "$st"; }

component() {  # $1 = out, $2 = identifier, $3 = version, $4 = scripts dir (optional)
  sh "$root/scripts/build_component_pkg.sh" --root "$st" --identifier "$2" --version "$3" --install-location / --out "$1" \
    ${4:+--scripts "$4"} >/dev/null 2>&1
}

component_reloc() {  # $1 = out, $2 = identifier, $3 = version: pkgbuild's defaults, bundles relocatable
  pkgbuild --quiet --root "$st" --identifier "$2" --version "$3" --install-location / "$1"
}

archive() {  # $1 = component, $2 = out, $3 = identifier, $4... = extra set_install_floor args
  c="$1"; o="$2"; id="$3"; shift 3
  sh "$root/scripts/set_install_floor.sh" --identifier "$id" --title fixture --component "$c" --out "$o" "$@" >/dev/null 2>&1
}

ed_stage() {  # $1 = tag; leaves $st with the ed25519 product tree
  stage "$1"
  mkdir -p "$st/usr/local/mavergreen/ed25519/bin"
  printf 'ed25519 fixture\n' > "$st/usr/local/mavergreen/ed25519/bin/ed25519-sign"
}

ed() {  # $1 = pool name, $2 = version, $3... = archive args
  n="$1"; v="$2"; shift 2
  ed_stage "$n"; manifest "$st" ed25519 dev.mavergreen.ed25519
  component "$w/$n.comp.pkg" dev.mavergreen.ed25519 "$v"
  archive "$w/$n.comp.pkg" "$w/pool/$n.pkg" dev.mavergreen.ed25519 "$@"
}

ed ed "$V"
ed ed-v100 1.0.0
ed ed-floor13 "$V" --min-os 10.13

ed_stage nomanifest
rm -rf "$st/usr"
mkdir -p "$st/Library/Application Support/Mavergreen"
printf 'stray\n' > "$st/Library/Application Support/Mavergreen/stuff"
component "$w/nomanifest.comp.pkg" dev.mavergreen.ed25519 "$V"
archive "$w/nomanifest.comp.pkg" "$w/pool/ed-nomanifest.pkg" dev.mavergreen.ed25519

ed_stage nobase; manifest "$st" ed25519 dev.mavergreen.ed25519
component "$w/nobase.comp.pkg" dev.mavergreen.ed25519 "$V"
mkdir -p "$w/nobase.x"
cat > "$w/nobase.dist.xml" <<XML
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<installer-gui-script minSpecVersion="1">
    <title>fixture</title>
    <allowed-os-versions><os-version min="10.9.5"/></allowed-os-versions>
    <choices-outline><line choice="dev.mavergreen.ed25519"/></choices-outline>
    <choice id="dev.mavergreen.ed25519" visible="false"><pkg-ref id="dev.mavergreen.ed25519"/></choice>
    <pkg-ref id="dev.mavergreen.ed25519" version="$V">#nobase.comp.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --quiet --distribution "$w/nobase.dist.xml" --package-path "$w" "$w/pool/ed-nobase.pkg"

ed_stage badbundle
mkdir -p "$st/Applications/Foo.app/Contents"
plist "$st/Applications/Foo.app/Contents/Info.plist" CFBundleIdentifier com.example.foo
manifest "$st" ed25519 dev.mavergreen.ed25519 "$(outside Applications/Foo.app)"
component "$w/badbundle.comp.pkg" dev.mavergreen.ed25519 "$V"
archive "$w/badbundle.comp.pkg" "$w/pool/ed-badbundle.pkg" dev.mavergreen.ed25519

ed_stage badlabel
mkdir -p "$st/Library/LaunchAgents"
plist "$st/Library/LaunchAgents/dev.mavergreen.ed25519-job.plist" Label dev.mavergreen.ed25519-other
manifest "$st" ed25519 dev.mavergreen.ed25519 "$(outside Library/LaunchAgents/dev.mavergreen.ed25519-job.plist)"
component "$w/badlabel.comp.pkg" dev.mavergreen.ed25519 "$V"
archive "$w/badlabel.comp.pkg" "$w/pool/ed-badlabel.pkg" dev.mavergreen.ed25519

ed_stage instray
mkdir -p "$st/opt/stray"
printf 'stray\n' > "$st/opt/stray/file"
manifest "$st" ed25519 dev.mavergreen.ed25519 "$(outside opt/stray/file)"
component "$w/instray.comp.pkg" dev.mavergreen.ed25519 "$V"
archive "$w/instray.comp.pkg" "$w/pool/ed-instray.pkg" dev.mavergreen.ed25519

ed_stage badplist
manifest "$st" ed25519 dev.mavergreen.ed25519
head -c 90 "$st/usr/local/mavergreen/ed25519/mavergreen.plist" > "$w/trunc"
cp "$w/trunc" "$st/usr/local/mavergreen/ed25519/mavergreen.plist"
component "$w/badplist.comp.pkg" dev.mavergreen.ed25519 "$V"
archive "$w/badplist.comp.pkg" "$w/pool/ed-badplist.pkg" dev.mavergreen.ed25519

stage ident
pkgbuild --quiet --nopayload --identifier com.example.thing --version "$V" "$w/ident.comp.pkg"
archive "$w/ident.comp.pkg" "$w/pool/ident-bad.pkg" com.example.thing

clang_stage() {  # $1 = tag, $2 = extra manifest XML
  stage "$1"
  mkdir -p "$st/usr/local/mavergreen/clang22/bin"
  printf 'clang fixture\n' > "$st/usr/local/mavergreen/clang22/bin/clang-22"
  manifest "$st" clang22 dev.mavergreen.clang.clang22 "$2"
  component "$w/$1.comp.pkg" dev.mavergreen.clang.clang22 22.1.1-mavericks.5
  archive "$w/$1.comp.pkg" "$w/pool/$1.pkg" dev.mavergreen.clang.clang22
}
clang_stage clang-line '<key>line</key><string>22</string>'
clang_stage clang-noline ''

app_product() {  # $1 = tag, $2 = "reloc" or "" ; leaves $st an ed25519 tree with one bundle listed in the manifest
  ed_stage "$1"
  mkdir -p "$st/Applications/Foo.app/Contents"
  plist "$st/Applications/Foo.app/Contents/Info.plist" CFBundleIdentifier dev.mavergreen.foo
  manifest "$st" ed25519 dev.mavergreen.ed25519 "$(outside Applications/Foo.app)"
}

inplace() {  # $1 = tag, $2 = true when the bundle is left relocatable and version-checked
  app_product "$1"
  if [ "$2" = true ]; then
    component_reloc "$w/$1.comp.pkg" dev.mavergreen.ed25519 "$V"
  else
    component "$w/$1.comp.pkg" dev.mavergreen.ed25519 "$V"
  fi
  archive "$w/$1.comp.pkg" "$w/pool/$1.pkg" dev.mavergreen.ed25519
}
inplace inplace-bad true
inplace inplace-ok false

hello() {  # $1 = tag, $2 = postinstall body
  ed_stage "$1"; manifest "$st" ed25519 dev.mavergreen.ed25519
  mkdir -p "$w/$1.scripts"
  printf '#!/bin/sh\n%s\nexit 0\n' "$2" > "$w/$1.scripts/postinstall"
  chmod 755 "$w/$1.scripts/postinstall"
  component "$w/$1.comp.pkg" dev.mavergreen.ed25519 "$V" "$w/$1.scripts"
  archive "$w/$1.comp.pkg" "$w/pool/$1.pkg" dev.mavergreen.ed25519
}
hello gui-ok '. /usr/local/mavergreen/.base/postinstall-stop-gui.sh
shipyard_stop_gui_instance fixture
open -a Fixture'
hello gui-bad 'open -a Fixture'

notes() {  # $1 = out, $2 = bullet
  printf '## Notes\n\n- %s\n' "$2" > "$1"
}

appcast() {  # $1 = out dir, $2 = file name, $3 = notes file, $4 = enclosure file name, $5 = pkg, $6 = version, $7 = release tag
  len="$(wc -c < "$5" | tr -d ' ')"
  sh "$root/scripts/gen_appcast.sh" ed25519 "$6" "https://github.com/Mavergreen/ed25519/releases/download/$7/$4" 10.9.5 \
    "$3" "sparkle:edSignature=\"x\" length=\"$len\"" > "$1/$2"
}

D=""
mkd() {  # $1 = id, $2 = pass|fail, $3... = KEY=value lines for ENV
  [ -n "$1" ] && [ -n "$2" ] || exit 2
  D="$checks/$1/$2"
  rm -rf "$D"
  mkdir -p "$D/dist"
  shift 2
  : > "$D/ENV"
  for e in "$@"; do printf '%s\n' "$e" >> "$D/ENV"; done
}
put() { cp "$w/pool/$1.pkg" "$D/dist/$2"; }
EDN="ed25519-$V.pkg"
EDV="SHIPYARD_CHECK_VERSION=$V"

mkd artifact-facts pass "$EDV"; put ed "$EDN"
mkd artifact-facts fail "$EDV"; put ed-badplist "$EDN"
mkd version-scheme pass "$EDV"; put ed "$EDN"
mkd version-scheme fail SHIPYARD_CHECK_VERSION=1.0.0; put ed-v100 ed25519-1.0.0.pkg
mkd version pass "$EDV"; put ed "$EDN"
mkd version fail SHIPYARD_CHECK_VERSION=1.0.0-mavericks.2; put ed "$EDN"
mkd floor pass "$EDV"; put ed "$EDN"
mkd floor fail "$EDV"; put ed-floor13 "$EDN"
mkd identifier pass "$EDV"; put ed "$EDN"
mkd identifier fail "$EDV"; put ident-bad "$EDN"
mkd bundle-id pass "$EDV"; put ed "$EDN"
mkd bundle-id fail "$EDV"; put ed-badbundle "$EDN"
mkd launchd-label pass "$EDV"; put ed "$EDN"
mkd launchd-label fail "$EDV"; put ed-badlabel "$EDN"
mkd manifest pass "$EDV"; put ed "$EDN"
mkd manifest fail "$EDV"; put ed-nomanifest "$EDN"
mkd base pass "$EDV"; put ed "$EDN"
mkd base fail "$EDV"; put ed-nobase "$EDN"
mkd install-path pass "$EDV"; put ed "$EDN"
mkd install-path fail "$EDV"; put ed-instray "$EDN"
mkd repository pass "$EDV" GITHUB_REPOSITORY=Mavergreen/ed25519; put ed "$EDN"
mkd repository fail "$EDV" GITHUB_REPOSITORY=Mavergreen/other; put ed "$EDN"
mkd line pass SHIPYARD_CHECK_VERSION=22.1.1-mavericks.5; put clang-line clang22-22.1.1-mavericks.5.pkg
mkd line fail SHIPYARD_CHECK_VERSION=22.1.1-mavericks.5; put clang-noline clang22-22.1.1-mavericks.5.pkg

feed_dist() {  # $1 = id, $2 = pass|fail, $3 = appcast name, $4 = enclosure, $5 = notes bullet for the appcast, $6 = release tag
  mkd "$1" "$2" "$EDV"; put ed "$EDN"
  notes "$D/dist/RELEASE_NOTES.md" "a fix"
  notes "$w/appcast-notes.md" "$5"
  appcast "$D/dist" "$3" "$w/appcast-notes.md" "$4" "$D/dist/$EDN" "$V" "$6"
}
feed_dist feed pass ed25519.xml "$EDN" "a fix" "$V"
feed_dist feed fail wrong.xml "$EDN" "a fix" "$V"
feed_dist enclosure pass ed25519.xml "$EDN" "a fix" "$V"
feed_dist enclosure fail ed25519.xml ghost.pkg "a fix" "$V"
feed_dist enclosure-url pass ed25519.xml "$EDN" "a fix" "$V"
feed_dist enclosure-url fail ed25519.xml "$EDN" "a fix" 1.0.0-mavericks.0
feed_dist notes pass ed25519.xml "$EDN" "a fix" "$V"
feed_dist notes fail ed25519.xml "$EDN" "a different fix" "$V"
feed_dist length pass ed25519.xml "$EDN" "a fix" "$V"
feed_dist length fail ed25519.xml "$EDN" "a fix" "$V"
sed -i.bak 's/length="[0-9]*"/length="999"/' "$D/dist/ed25519.xml"
rm -f "$D/dist/ed25519.xml.bak"

mkd variant-build-info pass "$EDV"; put ed "$EDN"
printf 'mls_version=1.5.2-mavericks.2\n' > "$D/dist/build-info-native.txt"
printf 'mls_version=1.5.2-mavericks.2\n' > "$D/dist/build-info-cross.txt"
mkd variant-build-info fail "$EDV"; put ed "$EDN"
printf 'mls_version=1.5.2-mavericks.2\n' > "$D/dist/build-info-native.txt"
printf 'mls_version=1.5.2-mavericks.1\n' > "$D/dist/build-info-cross.txt"

tgz() {  # $1 = out name in $D/dist, $2 = Mach-O fixture, $3 = name inside
  mkdir -p "$w/tgz"
  cp "$macho/$2" "$w/tgz/$3"
  ( cd "$w/tgz" && tar -czf "$D/dist/$1" "$3" )
  rm -f "$w/tgz/$3"
}
TV="SHIPYARD_CHECK_VERSION=$V"
mkd sdk-pin pass "$TV"; tgz tool.tar.gz clean tool
mkd sdk-pin fail "$TV"; tgz tool.tar.gz r265 tool
mkd compat-imports pass "$TV" MAVERICKS_POST_10_9_SYMBOLS=_mav_test_post109; tgz tool.tar.gz clean tool
mkd compat-imports fail "$TV" MAVERICKS_POST_10_9_SYMBOLS=_mav_test_post109; tgz tool.tar.gz leak tool
mkd compat-selectors pass "$TV"; tgz tool.tar.gz sel_ok tool
mkd compat-selectors fail "$TV"; tgz tool.tar.gz sel_bad tool
mkd compat-archs pass "$TV"; tgz tool.tar.gz clean tool
mkd compat-archs fail "$TV"; tgz tool.tar.gz fatok tool
mkd compat-required-defined pass "$TV" MAVERICKS_REQUIRE_DEFINED_SYMBOLS=_mav_test_shim; tgz tool.tar.gz shim tool
mkd compat-required-defined fail "$TV" MAVERICKS_REQUIRE_DEFINED_SYMBOLS=_mav_test_shim; tgz tool.tar.gz clean tool

mkd pkg-in-place pass "$EDV"; put inplace-ok "$EDN"
mkd pkg-in-place fail "$EDV"; put inplace-bad "$EDN"
mkd gui-relaunch-safe pass "$EDV"; put gui-ok "$EDN"
mkd gui-relaunch-safe fail "$EDV"; put gui-bad "$EDN"

up_stage() {  # $1 = tag, $2 = updater bundle id, $3 = agent label, $4 = feed in the appcast (yes|no)
  ed_stage "$1"
  app="$st/Library/Application Support/Mavergreen/ed25519-updater.app/Contents"
  mkdir -p "$app" "$st/Library/LaunchAgents"
  plist "$app/Info.plist" CFBundleIdentifier "$2" SUFeedURL https://github.com/Mavergreen/ed25519/releases/latest/download/ed25519.xml
  plist "$st/Library/LaunchAgents/$3.plist" Label "$3"
  manifest "$st" ed25519 dev.mavergreen.ed25519 "$(outside 'Library/Application Support/Mavergreen/ed25519-updater.app' "Library/LaunchAgents/$3.plist")<key>appcast</key><string>https://github.com/Mavergreen/ed25519/releases/latest/download/ed25519.xml</string>"
  component "$w/$1.comp.pkg" dev.mavergreen.ed25519 "$V"
  archive "$w/$1.comp.pkg" "$w/pool/$1.pkg" dev.mavergreen.ed25519
}
up_stage up-ok dev.mavergreen.ed25519.updater dev.mavergreen.ed25519-updatecheck yes
up_stage up-bad dev.mavergreen.ed25519.helper dev.mavergreen.ed25519-updatecheck yes
mkd updater pass "$EDV"; put up-ok "$EDN"
notes "$D/dist/RELEASE_NOTES.md" "a fix"
appcast "$D/dist" ed25519.xml "$D/dist/RELEASE_NOTES.md" "$EDN" "$D/dist/$EDN" "$V" "$V"
mkd updater fail "$EDV"; put up-bad "$EDN"
notes "$D/dist/RELEASE_NOTES.md" "a fix"
appcast "$D/dist" ed25519.xml "$D/dist/RELEASE_NOTES.md" "$EDN" "$D/dist/$EDN" "$V" "$V"

px="$here"
stage x
sa="$st/Library/Application Support/Mavergreen/x-updater.app/Contents"
mkdir -p "$sa/Frameworks/Sparkle.framework/Resources" "$st/Library/LaunchAgents" "$st/usr/local/mavergreen/x/bin"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.mavergreen.x.updater</string><key>SUFeedURL</key><string>https://github.com/Mavergreen/x/releases/latest/download/x.xml</string></dict></plist>\n' > "$sa/Info.plist"
plist "$sa/Frameworks/Sparkle.framework/Resources/Info.plist" CFBundleIdentifier org.sparkle-project.Sparkle
plist "$st/Library/LaunchAgents/dev.mavergreen.x-updatecheck.plist" Label dev.mavergreen.x-updatecheck
printf 'x\n' > "$st/usr/local/mavergreen/x/bin/x"
ln -s bin/x "$st/usr/local/mavergreen/x/link"
cp "$macho/clean" "$st/usr/local/mavergreen/x/bin/hello"
{ printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>\n'
  printf '<key>product</key><string>x</string><key>identifier</key><string>dev.mavergreen.x</string>\n'
  outside 'Library/Application Support/Mavergreen/x-updater.app' Library/LaunchAgents/dev.mavergreen.x-updatecheck.plist
  printf '<key>generated</key><array><string>Applications/Linux X.app</string></array>\n'
  printf '<key>appcast</key><string>https://github.com/Mavergreen/x/releases/latest/download/x.xml</string>\n</dict></plist>\n'; } \
  > "$st/usr/local/mavergreen/x/mavergreen.plist"
component "$px/x-component.pkg" dev.mavergreen.x "$V"
pkgbuild --quiet --root "$st/usr/local/mavergreen/x" --identifier dev.mavergreen.y --version "$V" --install-location /usr/local/y "$px/y-component.pkg"
pkgbuild --quiet --root "$st" --identifier dev.mavergreen.z --version "$V" --install-location /opt/z "$px/z-component.pkg"
sh "$root/scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --base-version 1.0.9 \
  --component "$px/x-component.pkg" --out "$px/x-archive.pkg" >/dev/null 2>&1
( cd "$st/usr/local/mavergreen/x" && tar -czf "$px/x-tools.tar.gz" bin/hello )
