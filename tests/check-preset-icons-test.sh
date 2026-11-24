#!/bin/sh
# platform: host-agnostic -- needs dpkg-deb to build its fixture package; exits 77 without it
# spec: scripts/check-preset-icons.sh -- fixtures are file:// URLs and a two-version apt repo built here
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-preset-icons.sh"
for t in curl dpkg-deb dpkg python3; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP: needs $t"; exit 77; }
done
W=$(mktemp -d "${TMPDIR:-/tmp}/cpi-test.XXXXXX"); trap 'rm -rf "$W"' EXIT

python3 "$here/icon-fixtures.py" "$W/f"
cp "$W/f/dark-180.png" "$W/good.png"; printf '<html/>' > "$W/page.png"
mkdir -p "$W/repo/dists/stable/main/binary-amd64" "$W/repo/pool"
for v in 2.0 3.0 1.0; do
  d="$W/pkg$v"; mkdir -p "$d/DEBIAN"
  printf 'Package: demo\nVersion: %s\nArchitecture: amd64\nMaintainer: x\nDescription: x\n' "$v" > "$d/DEBIAN/control"
  case $v in
    2.0) i="$d/usr/share/icons/hicolor/512x512/apps" ;;
    3.0) i="$d/usr/share/icons/hicolor/512x512/extra/apps" ;;
    1.0) i= ;;
  esac
  [ -z "$i" ] || { mkdir -p "$i"; cp "$W/f/dark-64.png" "$i/demo.png"; }
  [ "$v" != 2.0 ] || { mkdir -p "$d/usr/share/doc/demo"; cp "$W/page.png" "$d/usr/share/doc/demo/broken.png"; }
  dpkg-deb -b "$d" "$W/repo/pool/demo_$v.deb" >/dev/null
  printf 'Package: demo\nVersion: %s\nFilename: pool/demo_%s.deb\n\n' "$v" "$v" >> "$W/repo/dists/stable/main/binary-amd64/Packages"
done
# spec: scripts/check-preset-icons.sh -- 1.5 is in the pool but not the index, as apt repos keep old versions
d="$W/pkg1.5"; mkdir -p "$d/DEBIAN" "$d/usr/share/pixmaps"
printf 'Package: demo\nVersion: 1.5\nArchitecture: amd64\nMaintainer: x\nDescription: x\n' > "$d/DEBIAN/control"
cp "$W/f/blue-180.png" "$d/usr/share/pixmaps/demo blue.png"
dpkg-deb -b "$d" "$W/repo/pool/demo_1.5.deb" >/dev/null
cp "$W/repo/pool/demo_3.0.deb" "$W/repo/pool/demo_2.5.deb"
conf() {
  printf "APT_KEY_URL=file://%s/key\nAPT_REPO='deb [arch=amd64 signed-by=/x.gpg] file://%s/repo stable main'\nAPT_PKGS='demo extra'\nICON_URL=%s\nICON_GLOB='%s'\n%s\n" \
    "$W" "$W" "$1" "$2" "${3:-}" > "$W/demo.conf"
}
run() { sh "$S" "$W/demo.conf" 2>&1; }
says() { printf '%s\n' "$out" | grep -q -- "$2" || { echo "FAIL $1: should say $2, got: $out"; exit 1; }; }
silent() { ! printf '%s\n' "$out" | grep -q -- "$2" || { echo "FAIL $1: should not say $2, got: $out"; exit 1; }; }
ok() { sh "$S" "$W/demo.conf" >/dev/null 2>&1 || { echo "FAIL $1: expected pass"; sh "$S" "$W/demo.conf"; exit 1; }; }
no() {
  out=$(sh "$S" "$W/demo.conf" 2>&1) && { echo "FAIL $1: expected failure"; exit 1; }
  printf '%s\n' "$out" | grep -q "$2" || { echo "FAIL $1: should mention $2, got: $out"; exit 1; }
}

deep='/usr/share/icons/hicolor/*/*/apps/demo.png'
conf "file://$W/good.png" "$deep";                                    ok "both sources work, and the newest version (listed mid-way) is the one checked"
conf "file://$W/gone.png" "$deep";                                    no "a 404 ICON_URL" ICON_URL
conf "file://$W/page.png" "$deep";                                    no "a non-PNG ICON_URL" ICON_URL
conf "file://$W/good.png" '/opt/moved/*.png';                         no "an ICON_GLOB the package no longer has" ICON_GLOB
conf "file://$W/good.png" '/usr/share/icons/hicolor/*/apps/demo.png'; no "an icon moved one directory deeper (a * never crosses /)" ICON_GLOB
conf "" "$deep";                                                      ok "no ICON_URL is fine"
conf "file://$W/good.png" "$deep"
( cd "$W" && sh "$S" demo.conf >/dev/null 2>&1 ) || { echo "FAIL a conf named relative to the current directory (as preset-icons.yml passes it)"; ( cd "$W" && sh "$S" demo.conf ) || exit 1; exit 1; }

fpr() { python3 "$here/../scripts/icon-tool.py" fingerprint "$1"; }
FP=$(fpr "$W/good.png"); SHA=${FP%% *}
src2='demo 2.0 /usr/share/icons/hicolor/512x512/apps/demo.png distance:'$(python3 "$here/../scripts/icon-tool.py" distance "$FP" "$(fpr "$W/f/dark-64.png")" | sed 's/^dhash:\([0-9]*\).*/\1/')
cp "$W/good.png" "$W/archived.png"; cp "$W/f/bars-64.png" "$W/other.png"

conf "file://$W/good.png" "$deep"
out=$(run) || { echo "FAIL no fingerprint yet: still passes: $out"; exit 1; }
says "a preset with no fingerprint is told how to adopt one" "check-preset-icons.sh --accept"

conf "file://$W/good.png" "$deep" "ICON_URL_FINGERPRINT='$FP'"
out=$(run) || { echo "FAIL the accepted icon: passes: $out"; exit 1; }
silent "the accepted icon, unchanged, raises nothing" WARN

conf "file://$W/f/dark-64.png" "$deep" "ICON_URL_FINGERPRINT='$FP'"
out=$(run) || { echo "FAIL new bytes, same picture: passes: $out"; exit 1; }
says "new bytes of the same picture are noted" "WARN: ICON_URL serves different bytes"
silent "...but not as a substantial change" "changed substantially"

conf "file://$W/f/bars-64.png" "$deep" "ICON_URL_FINGERPRINT='$FP'
ICON_URL_SOURCE='$src2'
ICON_URL_ARCHIVE=file://$W/archived.png"
out=$(run) || { echo "FAIL a different picture only warns: $out"; exit 1; }
says "a different picture is a substantial change" "WARN: ICON_URL changed substantially"
says "...and the warning says what the accepted icon was: its source and its archived copy" \
  "(was: $src2; archived at file://$W/archived.png)$"
says "an icon unlike the package's is noted" "WARN: ICON_URL looks unlike"

conf "file://$W/good.png" "$deep" "ICON_URL_FINGERPRINT='$FP'
ICON_URL_ARCHIVE=file://$W/other.png"
no "an archived copy that is not the accepted icon" ICON_URL_ARCHIVE

conf "file://$W/good.png" "$deep" "ICON_URL_FINGERPRINT='$FP'
ICON_URL_SOURCE='$src2'"
out=$(run) || { echo "FAIL a source in an older version (fetched from the pool) verifies: $out"; exit 1; }
silent "the older version's source verifies quietly" WARN
conf "file://$W/good.png" "$deep" "ICON_URL_FINGERPRINT='$FP'
ICON_URL_SOURCE='demo 2.0 /usr/share/icons/hicolor/512x512/apps/demo.png distance:31'"
no "a source whose distance no longer holds" ICON_URL_SOURCE
conf "file://$W/good.png" "$deep" "ICON_URL_FINGERPRINT='$FP'
ICON_URL_SOURCE='demo 2.0 /usr/share/icons/nowhere/demo.png distance:0'"
no "a source path the package lacks" ICON_URL_SOURCE
conf "file://$W/good.png" "$deep" "ICON_URL_FINGERPRINT='$FP'
ICON_URL_SOURCE='demo 9.9 /usr/share/icons/hicolor/512x512/apps/demo.png distance:0'"
out=$(run) || { echo "FAIL a source version the pool no longer has only warns: $out"; exit 1; }
says "a source version the pool no longer has is noted" "WARN: ICON_URL_SOURCE"

conf "file://$W/f/bars-64.png" "$deep" "ICON_URL_FINGERPRINT='$FP'
ICON_URL_ARCHIVE=file://$W/archived.png"
out=$(GITHUB_STEP_SUMMARY="$W/summary.md" ICON_OUT_DIR="$W/out" run) || :
grep -qF "file://$W/archived.png" "$W/summary.md" && grep -qF "file://$W/f/bars-64.png" "$W/summary.md" \
  || { echo "FAIL the job summary shows the accepted and the current icon"; cat "$W/summary.md"; exit 1; }
cmp -s "$W/out/icon.png" "$W/f/bars-64.png" || { echo "FAIL ICON_OUT_DIR keeps the fetched icon"; exit 1; }

python3 - "$W" > "$W/port" <<'PY' &
import http.server, os, sys
d = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path == "/old.png":
            self.send_response(301); self.send_header("Location", "/new.png"); self.end_headers(); return
        b = open(os.path.join(d, "good.png"), "rb").read()
        self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
s = http.server.HTTPServer(("127.0.0.1", 0), H); print(s.server_port, flush=True); s.serve_forever()
PY
srv=$!; n=0; while [ ! -s "$W/port" ] && [ $n -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
conf "http://127.0.0.1:$(cat "$W/port")/old.png" "$deep" "ICON_URL_FINGERPRINT='$FP'"
out=$(run) || :; kill $srv
says "a redirect is noted, naming where it goes" "WARN: ICON_URL redirects to http://127.0.0.1:$(cat "$W/port")/new.png"

printf '#!/bin/sh\ncp "${1#file://}" "%s/snap.png" && echo "file://%s/snap.png"\n' "$W" "$W" > "$W/archiver"
printf '#!/bin/sh\necho "file://%s/f/bars-64.png"\n' "$W" > "$W/bad-archiver"
chmod +x "$W/archiver" "$W/bad-archiver"
accept() { SHIPYARD_ICON_ARCHIVER="$W/${ARCHIVER:-archiver}" sh "$S" --accept "$@"; }
conf "file://$W/good.png" "$deep"
lines=$(accept "$W/demo.conf" 2>"$W/err") || { echo "FAIL --accept: $(cat "$W/err")"; exit 1; }
[ "$lines" = "ICON_URL_FINGERPRINT='$FP'
ICON_URL_SOURCE='demo 3.0 /usr/share/icons/hicolor/512x512/extra/apps/demo.png distance:${src2##*distance:}'
ICON_URL_ARCHIVE='file://$W/snap.png'" ] || { echo "FAIL --accept prints the three lines, got: $lines"; exit 1; }
printf '%s\n' "$lines" >> "$W/demo.conf"
out=$(run) || { echo "FAIL the accepted lines pass: $out"; exit 1; }
silent "the accepted lines round-trip to a quiet check" WARN

conf "file://$W/good.png" "$deep"
lines=$(ARCHIVER=bad-archiver accept "$W/demo.conf" 2>"$W/err") || { echo "FAIL --accept with a bad capture: $(cat "$W/err")"; exit 1; }
! printf '%s\n' "$lines" | grep -q ICON_URL_ARCHIVE || { echo "FAIL a capture holding other bytes is not recorded: $lines"; exit 1; }
grep -q "not recorded" "$W/err" || { echo "FAIL ...and says so: $(cat "$W/err")"; exit 1; }

conf "file://$W/f/blue-180.png" "$deep"
lines=$(accept "$W/demo.conf" 2>/dev/null)
printf '%s\n' "$lines" | grep -q "^ICON_URL_SOURCE='none within 10 in demo 3.0 (closest " \
  || { echo "FAIL an icon unlike anything in the newest package records none: $lines"; exit 1; }
printf '%s\n' "$lines" >> "$W/demo.conf"
out=$(run) || { echo "FAIL an accepted icon unlike the package's passes: $out"; exit 1; }
silent "an icon accepted as unlike the package's is not re-flagged while unchanged" WARN
conf "file://$W/f/blue-180.png" "$deep"
mkdir -p "$W/prod"; ( cd "$W/prod" && git init -q && for v in 1.0 1.5 2.0 3.0; do echo $v > UPSTREAM_VERSION
  git add UPSTREAM_VERSION && git -c user.name=t -c user.email=t@t commit -qm $v; done )
[ $? -eq 0 ] || exit 1
cp "$W/demo.conf" "$W/prod/demo.conf"
lines=$(accept --search-back 3 "$W/prod/demo.conf" 2>"$W/err") || { echo "FAIL --search-back: $(cat "$W/err")"; exit 1; }
printf '%s\n' "$lines" | grep -qx "ICON_URL_SOURCE='demo 1.5 /usr/share/pixmaps/demo blue.png distance:0'" \
  || { echo "FAIL --search-back finds it in an older version still in the pool: $lines"; exit 1; }

conf "file://$W/good.png" "$deep" "ICON_URL_FINGERPRINT='$FP'
ICON_URL_ARCHIVE=file://$W/no-such-capture.png"
out=$(run) || { echo "FAIL an archive that can't be fetched (a Wayback outage) only warns: $out"; exit 1; }
says "...and says so" "WARN: ICON_URL_ARCHIVE"
conf "file://$W/good.png" "$deep" "ICON_URL_FINGERPRINT='$FP'
ICON_URL_ARCHIVE=file://$W/page.png"
out=$(run) || { echo "FAIL an archive serving an HTML page only warns: $out"; exit 1; }

printf '#!/bin/sh\necho "file://%s/it'"'"'s.png"\n' "$W" > "$W/quote-archiver"; chmod +x "$W/quote-archiver"
cp "$W/good.png" "$W/it's.png"
conf "file://$W/good.png" "$deep"
lines=$(ARCHIVER=quote-archiver accept "$W/demo.conf" 2>"$W/err") || :
! printf '%s\n' "$lines" | grep -q ICON_URL_ARCHIVE || { echo "FAIL a value with a quote is not printed: $lines"; exit 1; }

conf "file://$W/good.png" "$deep" "ICON_URL_FINGERPRINT='$FP'
ICON_URL_SOURCE='demo 2.5 /usr/share/icons/hicolor/512x512/extra/apps/demo.png distance:${src2##*distance:}'"
out=$(run) || { echo "FAIL a pool file that is another version only warns: $out"; exit 1; }
says "a pool file that is not the version named is not trusted" "WARN: ICON_URL_SOURCE"

conf "file://$W/good.png" "$deep" "ICON_URL_FINGERPRINT='$FP'
ICON_URL_SOURCE='demo 2.0 /usr/share/doc/demo/broken.png distance:0'"
no "a source the decoder can't read" ICON_URL_SOURCE

conf "file://$W/good.png" "$deep" "ICON_URL_FINGERPRINT='sha256:abc'"
out=$(run) || { echo "FAIL a malformed fingerprint only warns: $out"; exit 1; }
says "...and the run still checks ICON_GLOB" "ICON_GLOB ok"

conf "file://$W/f/dark-64-interlaced.png" "$deep"
accept "$W/demo.conf" >/dev/null 2>"$W/err" && { echo "FAIL an interlaced icon can't be accepted"; exit 1; }
grep -q interlaced "$W/err" || { echo "FAIL ...and the refusal says why: $(cat "$W/err")"; exit 1; }

printf "APT_KEY_URL=file://%s/key\nAPT_REPO='deb [arch=amd64 signed-by=/x.gpg] file://%s/repo stable main'\nAPT_PKGS='demo extra'\nICON_URL=file://%s/good.png\nICON_URL_FINGERPRINT='%s'\nICON_URL_SOURCE='%s'\n" \
  "$W" "$W" "$W" "$FP" "$src2" > "$W/demo.conf"
out=$(run) || { echo "FAIL a source recorded without ICON_GLOB: $out"; exit 1; }
says "a source is checked even without ICON_GLOB" "ICON_URL_SOURCE ok"

echo "ok check-preset-icons"
