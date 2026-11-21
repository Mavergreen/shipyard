#!/bin/sh
# platform: host-agnostic -- needs curl, dpkg, dpkg-deb and python3; exits 77 without them
#   usage: check-preset-icons.sh CONF
#          A Porthole preset names where its app icon comes from: ICON_URL, a vendor-hosted PNG that
#          Porthole fetches on the user's Mac at install, and ICON_GLOB, the icon's path inside the
#          vendor's package, which Porthole extracts from the app's container. Either can move. This
#          fails when ICON_URL no longer serves a PNG, or when ICON_GLOB (one path segment per *, as
#          the container's shell expands it) matches nothing in the newest package named first in
#          APT_PKGS from APT_REPO (checked only when APT_KEY_URL and APT_REPO are set). Preset repos
#          run it on push and weekly through preset-icons.yml, so a moved source turns a run red
#          between releases.
#          Provenance, so a changed icon can be noticed and its replacement judged. A preset records,
#          when an icon is accepted (check-preset-icons.sh --accept CONF prints the lines):
#            ICON_URL_FINGERPRINT  the accepted icon's sha256, difference hash, size and colour
#            ICON_URL_SOURCE       "<package> <version> <path> distance:<n>": the closest icon in the
#                                  vendor's package (an old version is fetched from the pool), or
#                                  "none ..." when nothing in the package resembles it
#            ICON_URL_ARCHIVE      a Wayback Machine id_ URL holding the accepted icon's bytes
#          Each run then WARNs (and still passes) when ICON_URL redirects, serves other bytes, has
#          changed substantially, or looks unlike the package's icon; every warning says what the
#          accepted icon was. It fails when ICON_URL_SOURCE or ICON_URL_ARCHIVE no longer holds the
#          accepted icon: a record that is wrong is worse than none. With GITHUB_STEP_SUMMARY set it
#          adds the accepted and current icons side by side; with ICON_OUT_DIR, it keeps the fetched
#          icon there as icon.png.
# spec: tests/check-preset-icons-test.sh; .superpowers/specs/2026-11-21-preset-icon-provenance-design.md
set -eu
usage() { echo "usage: check-preset-icons.sh [--accept [--search-back N]] CONF" >&2; exit 2; }
accept= back=0
[ "${1:-}" != --accept ] || { accept=1; shift; }
[ -z "$accept" ] || [ "${1:-}" != --search-back ] || { [ $# -ge 2 ] || usage; back=$2; shift 2; }
[ $# -eq 1 ] || usage
CONF=$1
for t in curl dpkg-deb dpkg python3; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP: check-preset-icons needs $t"; exit 77; }
done
ICON_URL= ICON_GLOB= APT_REPO= APT_KEY_URL= APT_PKGS=
ICON_URL_FINGERPRINT= ICON_URL_SOURCE= ICON_URL_ARCHIVE=
case "$CONF" in */*) . "$CONF" ;; *) . "./$CONF" ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/mavericks_fetch.sh"
W=$(mktemp -d "${TMPDIR:-/tmp}/check-preset-icons.XXXXXX"); trap 'rm -rf "$W"' EXIT
fail=0 fp= pkgicon=
tool() { python3 "$HERE/icon-tool.py" "$@"; }
shasum_of() { python3 -c 'import hashlib, sys; print("sha256:" + hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
was() {
  w=${ICON_URL_SOURCE}
  [ -z "$ICON_URL_ARCHIVE" ] || w="${w:+$w; }archived at $ICON_URL_ARCHIVE"
  [ -z "$w" ] || printf ' (was: %s)' "$w"
}
warn() { echo "WARN: $*$(was)"; printf -- '- %s\n' "$*" >> "$W/summary"; }
newest_package() {
  set -- $(printf '%s\n' "$APT_REPO" | sed 's/\[[^]]*\]//')
  base=$2 suite=$3 comp=$4
  pkg=$(printf '%s\n' "$APT_PKGS" | awk '{ print $1 }'); pkg=${pkg%%=*}
  shipyard_curl "$base/dists/$suite/$comp/binary-amd64/Packages" "$W/Packages"
  awk -v p="$pkg" '
    /^Package: / { k = $2 } /^Version: / { v = $2 } /^Filename: / { f = $2 }
    /^$/ { if (k == p) print v, f; k = "" }
    END { if (k == p) print v, f }' "$W/Packages" > "$W/candidates"
  best= bestv=
  while read -r v f; do
    if [ -z "$bestv" ] || dpkg --compare-versions "$v" gt "$bestv"; then bestv=$v; best=$f; fi
  done < "$W/candidates"
}
# spec: tests/check-preset-icons-test.sh -- an apt pool keeps old versions after the index moves on (1Password: 8.10.80 still served 2026-11-20)
pool_deb() {
  f=$(awk -v f="$best" -v o="$bestv" -v n="$1" 'BEGIN { i = index(f, o); if (i) print substr(f, 1, i - 1) n substr(f, i + length(o)) }')
  [ -n "$f" ] && [ "$f" != "$best" ] && shipyard_curl "$base/$f" "$2" 2>/dev/null && [ "$(dpkg-deb -f "$2" Version)" = "$1" ]
}
# spec: tests/check-preset-icons-test.sh -- one member, not the whole ~100 MB package, on every weekly run
deb_member() {
  m=${2%%.asar:*}; [ "$m" = "$2" ] || m=$m.asar
  mkdir -p "$3" && dpkg-deb --fsys-tarfile "$1" | tar -xf - -C "$3" "./${m#/}" 2>/dev/null
}
# spec: tests/check-preset-icons-test.sh -- the preset sources these lines, so a quote or an & in a URL would break or background it
line() { case $2 in *"'"*) echo "check-preset-icons: --accept: $1 contains a quote; not printed" >&2 ;; *) echo "$1='$2'" ;; esac; }

if [ -n "$accept" ]; then
  [ -n "$ICON_URL" ] || { echo "check-preset-icons: --accept: $CONF has no ICON_URL" >&2; exit 2; }
  shipyard_curl "$ICON_URL" "$W/icon"
  fp=$(tool fingerprint "$W/icon") || {
    echo "check-preset-icons: --accept: can't fingerprint $ICON_URL (see above); choose another icon URL" >&2; exit 1; }
  line ICON_URL_FINGERPRINT "$fp"
  if [ -n "$APT_REPO" ]; then
    newest_package
    [ -n "$best" ] || { echo "check-preset-icons: --accept: $pkg is not in $base $suite $comp" >&2; exit 1; }
    versions=$bestv
    if [ "$back" -gt 0 ]; then
      # spec: tests/check-preset-icons-test.sh -- the versions this preset shipped, newest first, from its repo's history
      d=$(cd "$(dirname "$CONF")" && pwd)
      versions="$versions $(git -C "$d" log -p --format= -- UPSTREAM_VERSION 2>/dev/null | sed -n 's/^+\([^+].*\)$/\1/p' \
        | awk -v n="$back" -v b="$bestv" '$0 != b && !seen[$0]++ && c++ < n')"
    fi
    src= closest=
    for v in $versions; do
      if [ "$v" = "$bestv" ]; then shipyard_curl "$base/$best" "$W/pkg.deb" || continue
      else pool_deb "$v" "$W/pkg.deb" || { echo "check-preset-icons: $pkg $v is not in the pool" >&2; continue; }; fi
      rm -rf "$W/root"; dpkg-deb -x "$W/pkg.deb" "$W/root"
      hit=$(tool find "$fp" "$W/root") || continue
      path=$(printf '%s' "$hit" | cut -f1); dist=$(printf '%s' "$hit" | cut -f2)
      [ -n "$closest" ] || closest="$path distance:$dist"
      tool cat "$W/root" "$path" > "$W/hit"
      if tool similar "$fp" "$(tool fingerprint "$W/hit")"; then
        src="$pkg $v $path distance:$dist"; break
      fi
    done
    line ICON_URL_SOURCE "${src:-none within $(tool same-dhash) in $pkg $bestv (closest ${closest:-none})}"
  fi
  archiver=${SHIPYARD_ICON_ARCHIVER:-}
  if [ -z "$archiver" ]; then
    snap=$(curl -sS -o /dev/null -D - --max-time 180 "https://web.archive.org/save/$ICON_URL" 2>/dev/null \
      | tr -d '\r' | sed -n 's/^[Ll]ocation: *//p' | sed 's|^\(https://web.archive.org/web/[0-9]*\)/|\1id_/|')
  else
    snap=$("$archiver" "$ICON_URL")
  fi
  if [ -n "$snap" ] && shipyard_curl "$snap" "$W/snap" 2>/dev/null && \
     [ "$(tool fingerprint "$W/snap" 2>/dev/null | awk '{ print $1 }')" = "${fp%% *}" ]; then
    line ICON_URL_ARCHIVE "$snap"
  else
    echo "check-preset-icons: --accept: the archive capture (${snap:-none}) does not hold this icon; not recorded" >&2
  fi
  exit 0
fi

if [ -n "$ICON_URL" ]; then
  if ! shipyard_curl "$ICON_URL" "$W/icon"; then
    echo "ICON_URL: fetch failed: $ICON_URL"; fail=1
  elif [ "$(head -c 8 "$W/icon" | od -An -tx1 | tr -d ' \n')" != 89504e470d0a1a0a ]; then
    echo "ICON_URL: not a PNG: $ICON_URL"; fail=1
  else
    echo "ICON_URL ok: $ICON_URL ($(wc -c < "$W/icon" | tr -d ' ') bytes)"
    [ -z "${ICON_OUT_DIR:-}" ] || { mkdir -p "$ICON_OUT_DIR" && cp "$W/icon" "$ICON_OUT_DIR/icon.png"; }
    case "$ICON_URL" in http://* | https://*)
      final=$(curl -sSL -o /dev/null -w '%{url_effective}' --max-time 60 "$ICON_URL" 2>/dev/null) || final=
      [ -z "$final" ] || [ "$final" = "$ICON_URL" ] || warn "ICON_URL redirects to $final: the first sign a URL is going away"
    esac
    if ! fp=$(tool fingerprint "$W/icon" 2>&1); then
      warn "ICON_URL could not be fingerprinted: $fp"; fp=
    elif [ -z "$ICON_URL_FINGERPRINT" ]; then
      warn "no ICON_URL_FINGERPRINT: run check-preset-icons.sh --accept $CONF and commit the lines it prints"
    elif [ "${fp%% *}" != "${ICON_URL_FINGERPRINT%% *}" ]; then
      if ! d=$(tool distance "$ICON_URL_FINGERPRINT" "$fp" 2>&1); then
        warn "ICON_URL_FINGERPRINT can't be read ($d): run --accept again"
      elif tool similar "$ICON_URL_FINGERPRINT" "$fp"; then
        warn "ICON_URL serves different bytes than the accepted icon, the same picture ($d)"
      else
        warn "ICON_URL changed substantially from the accepted icon ($d)"
      fi
    fi
  fi
fi

if [ -n "$ICON_URL_ARCHIVE" ]; then
  # spec: tests/check-preset-icons-test.sh -- the Wayback Machine has outages and serves HTML error pages; only a PNG with other bytes is a wrong record
  if ! shipyard_curl "$ICON_URL_ARCHIVE" "$W/archived" 2>/dev/null; then
    warn "ICON_URL_ARCHIVE could not be fetched now: $ICON_URL_ARCHIVE"
  elif [ "$(head -c 8 "$W/archived" | od -An -tx1 | tr -d ' \n')" != 89504e470d0a1a0a ]; then
    warn "ICON_URL_ARCHIVE did not serve a PNG now: $ICON_URL_ARCHIVE"
  elif [ -n "$ICON_URL_FINGERPRINT" ] && [ "$(shasum_of "$W/archived")" != "${ICON_URL_FINGERPRINT%% *}" ]; then
    echo "ICON_URL_ARCHIVE: $ICON_URL_ARCHIVE does not hold the accepted icon (${ICON_URL_FINGERPRINT%% *})"; fail=1
  else
    echo "ICON_URL_ARCHIVE ok: $ICON_URL_ARCHIVE"
  fi
fi

if [ -n "$ICON_GLOB" ] && [ -n "$APT_REPO" ] && [ -n "$APT_KEY_URL" ]; then
  newest_package
  if [ -z "$best" ]; then
    echo "ICON_GLOB: $pkg not found in $base $suite $comp"; fail=1
  else
    shipyard_curl "$base/$best" "$W/pkg.deb"
    dpkg-deb -c "$W/pkg.deb" | awk '{ print substr($6, 2) }' > "$W/files"
    depth() { printf '%s' "$1" | tr -cd / | wc -c | tr -d ' '; }
    want=$(depth "$ICON_GLOB")
    found=
    while read -r path; do
      [ "$(depth "$path")" = "$want" ] || continue
      case "$path" in $ICON_GLOB) found=$path; break ;; esac
    done < "$W/files"
    if [ -n "$found" ]; then
      echo "ICON_GLOB ok in $pkg $bestv: $found"
      deb_member "$W/pkg.deb" "$found" "$W/root"
      # spec: tests/check-preset-icons-test.sh -- an icon accepted as unlike the package's ("none ...") is not re-flagged until its bytes change
      case "$ICON_URL_SOURCE" in none\ *) [ "${fp%% *}" != "${ICON_URL_FINGERPRINT%% *}" ] || fp_known=1 ;; esac
      if [ -n "$fp" ] && [ -z "${fp_known:-}" ] && pkgicon=$(tool fingerprint "$W/root/$found" 2>/dev/null) && \
         ! tool similar "$pkgicon" "$fp"; then
        warn "ICON_URL looks unlike the package's icon $found ($(tool distance "$pkgicon" "$fp"))"
      fi
    else
      echo "ICON_GLOB: nothing in $pkg $bestv matches $ICON_GLOB"; fail=1
    fi
  fi
fi

# spec: tests/check-preset-icons-test.sh -- the recorded source is re-checked against the fingerprint, from the pool when old
case "$ICON_URL_SOURCE" in '' | none\ *) ;; *)
  r=$ICON_URL_SOURCE; spkg=${r%% *}; r=${r#* }; sver=${r%% *}; r=${r#* }
  sdist=${r##* distance:}; spath=${r% distance:*}
  [ -n "${best:-}" ] || [ -z "$APT_REPO" ] || newest_package
  if [ -z "$APT_REPO" ]; then
    warn "ICON_URL_SOURCE is not checked: this preset names no APT_REPO"
  elif [ -z "${best:-}" ] || [ "$spkg" != "${pkg:-}" ]; then
    warn "ICON_URL_SOURCE names $spkg, which this preset's APT_PKGS does not lead with; not checked"
  elif [ -z "$ICON_URL_FINGERPRINT" ]; then
    warn "ICON_URL_SOURCE is not checked without ICON_URL_FINGERPRINT"
  else
    if [ "$sver" = "$bestv" ]; then sdeb=$W/pkg.deb; [ -s "$sdeb" ] || shipyard_curl "$base/$best" "$sdeb" || sdeb=
    else sdeb=$W/source.deb; pool_deb "$sver" "$sdeb" || sdeb=; fi
    if [ -z "$sdeb" ]; then
      warn "ICON_URL_SOURCE: $spkg $sver can't be fetched from the pool as that version, so the source can't be re-checked"
    else
      rm -rf "$W/src"; deb_member "$sdeb" "$spath" "$W/src" || :
      if ! tool cat "$W/src" "$spath" > "$W/srcicon" 2>/dev/null; then
        echo "ICON_URL_SOURCE: $spkg $sver has no $spath"; fail=1
      elif ! sfp=$(tool fingerprint "$W/srcicon" 2>&1); then
        echo "ICON_URL_SOURCE: $spath in $spkg $sver can't be read ($sfp)"; fail=1
      elif ! got=$(tool distance "$ICON_URL_FINGERPRINT" "$sfp" 2>&1); then
        warn "ICON_URL_SOURCE is not checked: $got"
      elif [ "${got%% *}" != "dhash:$sdist" ]; then
        echo "ICON_URL_SOURCE: $spath in $spkg $sver is no longer distance $sdist from the accepted icon ($got)"; fail=1
      else
        echo "ICON_URL_SOURCE ok: $spath in $spkg $sver, distance $sdist"
      fi
    fi
  fi
esac

if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -s "$W/summary" ]; then
  {
    echo "### Preset icon: $CONF"; echo
    cat "$W/summary"; echo
    echo "| accepted | now |"; echo "|---|---|"
    echo "| ${ICON_URL_ARCHIVE:+![accepted]($ICON_URL_ARCHIVE)}${ICON_URL_ARCHIVE:-(no archived copy)} | ![now]($ICON_URL) |"
    [ -z "$ICON_URL_SOURCE" ] || { echo; echo "Accepted icon's source: \`$ICON_URL_SOURCE\`"; }
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit $fail
