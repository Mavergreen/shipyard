# platform: host-agnostic -- stevedore builds the fixtures
# Fixtures for the Sparkle-key checks (tests/lib/ is not itself run: run-repo-tests.sh takes top-level
# tests only). Real .pkg files, built with the stevedore that builds the products.

# mkpkg OUT [KEY FEED [APP]] ... -- a product archive whose payload holds one updater app per
# KEY FEED APP triple, under "Library/Application Support/Mavergreen/" (the space is on purpose:
# that is where shipyard's own updaters live). With no triples, the payload holds no updater at all.
mkpkg() {
  local out="$1" root; shift
  root="$(mktemp -d "$BATS_TEST_TMPDIR/root.XXXXXX")"
  mkdir -p "$root/usr/local/share/doc/test"; echo not-an-updater > "$root/usr/local/share/doc/test/README"
  while [ "$#" -ge 3 ]; do
    local c="$root/Library/Application Support/Mavergreen/$3.app/Contents"
    mkdir -p "$c"
    cat > "$c/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>dev.mavergreen.test.$3</string>
	<key>SUFeedURL</key>
	<string>$2</string>
	<key>SUPublicEDKey</key>
	<string>$1</string>
</dict>
</plist>
EOF
    shift 3
  done
  local sd; sd="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_stevedore.sh")" || { echo "fetch_stevedore.sh failed: no stevedore to build the fixture" >&2; return 1; }
  "$sd" component --root "$root" --identifier dev.mavergreen.test --version 1 --install-location / \
    --mtime 1700000000 --out "$out.component.pkg" >/dev/null
  cat > "$out.dist" <<DIST
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
  <pkg-ref id="dev.mavergreen.test" version="1">${out##*/}.component.pkg</pkg-ref>
  <choices-outline><line choice="dev.mavergreen.test"/></choices-outline>
  <choice id="dev.mavergreen.test"><pkg-ref id="dev.mavergreen.test"/></choice>
</installer-gui-script>
DIST
  "$sd" product --distribution "$out.dist" --package "$out.component.pkg" --mtime 1700000000 --out "$out" >/dev/null
  rm -f "$out.component.pkg" "$out.dist"
}

# An appcast whose one enclosure points at ENCLOSURE_URL, in gen_appcast.sh's shape.
mkfeed() {  # OUT ENCLOSURE_URL
  cat > "$1" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:version>1.2.2</sparkle:version>
      <enclosure url="$2" type="application/octet-stream" sparkle:edSignature="c2ln" length="1" />
    </item>
  </channel>
</rss>
EOF
}

# A stand-in for ed25519-verify with its exact contract (ed25519-verify's own crypto is tested in
# mavericks-ed25519): a signature "verifies" against key K iff it is the text "signed-by:K".
mkverifier() {  # OUT
  cat > "$1" <<'EOF'
#!/bin/sh
keys=
while getopts p: o; do case $o in p) keys="$keys $OPTARG" ;; *) exit 2 ;; esac; done
shift $((OPTIND - 1)); [ -n "$keys" ] && [ "$#" -eq 2 ] || exit 2
[ -r "$1" ] || exit 2
for k in $keys; do [ "$2" = "signed-by:$k" ] && { printf '%s\n' "$k"; exit 0; }; done
exit 1
EOF
  chmod +x "$1"
}
