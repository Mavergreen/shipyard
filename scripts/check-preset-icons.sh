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
CONF="${1:?usage: check-preset-icons.sh CONF}"
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
was() {
  w=${ICON_URL_SOURCE}
  [ -z "$ICON_URL_ARCHIVE" ] || w="${w:+$w; }archived at $ICON_URL_ARCHIVE"
  [ -z "$w" ] || printf ' (was: %s)' "$w"
}
warn() { echo "WARN: $*$(was)"; printf -- '- %s\n' "$*" >> "$W/summary"; }

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
      d=$(tool distance "$ICON_URL_FINGERPRINT" "$fp")
      if tool similar "$ICON_URL_FINGERPRINT" "$fp"; then
        warn "ICON_URL serves different bytes than the accepted icon, the same picture ($d)"
      else
        warn "ICON_URL changed substantially from the accepted icon ($d)"
      fi
    fi
  fi
fi

if [ -n "$ICON_URL_ARCHIVE" ]; then
  if ! shipyard_curl "$ICON_URL_ARCHIVE" "$W/archived"; then
    echo "ICON_URL_ARCHIVE: fetch failed: $ICON_URL_ARCHIVE"; fail=1
  elif [ -n "$ICON_URL_FINGERPRINT" ] && \
       [ "$(tool fingerprint "$W/archived" 2>/dev/null | awk '{ print $1 }')" != "${ICON_URL_FINGERPRINT%% *}" ]; then
    echo "ICON_URL_ARCHIVE: $ICON_URL_ARCHIVE does not hold the accepted icon (${ICON_URL_FINGERPRINT%% *})"; fail=1
  else
    echo "ICON_URL_ARCHIVE ok: $ICON_URL_ARCHIVE"
  fi
fi

if [ -n "$ICON_GLOB" ] && [ -n "$APT_REPO" ] && [ -n "$APT_KEY_URL" ]; then
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
      dpkg-deb -x "$W/pkg.deb" "$W/root"
      if [ -n "$fp" ] && pkgicon=$(tool fingerprint "$W/root/$found" 2>/dev/null) && ! tool similar "$pkgicon" "$fp"; then
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
  if [ -z "${best:-}" ] || [ "$spkg" != "${pkg:-}" ]; then
    warn "ICON_URL_SOURCE names $spkg, which this preset's APT_PKGS does not lead with; not checked"
  elif [ -z "$ICON_URL_FINGERPRINT" ]; then
    warn "ICON_URL_SOURCE is not checked without ICON_URL_FINGERPRINT"
  else
    if [ "$sver" = "$bestv" ]; then sdeb=$W/pkg.deb
    else sdeb=$W/source.deb; shipyard_curl "$base/$(printf '%s' "$best" | sed "s|$bestv|$sver|g")" "$sdeb" 2>/dev/null || sdeb=; fi
    if [ -z "$sdeb" ]; then
      warn "ICON_URL_SOURCE: $spkg $sver is no longer in the pool, so the source can't be re-checked"
    else
      rm -rf "$W/src"; dpkg-deb -x "$sdeb" "$W/src"
      if ! tool cat "$W/src" "$spath" > "$W/srcicon" 2>/dev/null; then
        echo "ICON_URL_SOURCE: $spkg $sver has no $spath"; fail=1
      elif got=$(tool distance "$ICON_URL_FINGERPRINT" "$(tool fingerprint "$W/srcicon")") && \
           [ "${got%% *}" != "dhash:$sdist" ]; then
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
