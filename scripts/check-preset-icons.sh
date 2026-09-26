#!/bin/sh
# platform: host-agnostic -- needs curl, dpkg and dpkg-deb; exits 77 without them
#   usage: check-preset-icons.sh CONF
#          A Porthole preset names where its app icon comes from: ICON_URL, a vendor-hosted PNG that
#          Porthole fetches on the user's Mac at install, and ICON_GLOB, the icon's path inside the
#          vendor's package, which Porthole extracts from the app's container. Either can move. This
#          fails when ICON_URL no longer serves a PNG, or when ICON_GLOB (one path segment per *, as
#          the container's shell expands it) matches nothing in the newest package named first in
#          APT_PKGS from APT_REPO (checked only when APT_KEY_URL and APT_REPO are set). Preset repos
#          run it on push and weekly through preset-icons.yml, so a moved source turns a run red
#          between releases.
# spec: tests/check-preset-icons-test.sh
set -eu
CONF="${1:?usage: check-preset-icons.sh CONF}"
for t in curl dpkg-deb dpkg; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP: check-preset-icons needs $t"; exit 77; }
done
ICON_URL= ICON_GLOB= APT_REPO= APT_KEY_URL= APT_PKGS=
. "$CONF"
W=$(mktemp -d "${TMPDIR:-/tmp}/check-preset-icons.XXXXXX"); trap 'rm -rf "$W"' EXIT
fail=0

if [ -n "$ICON_URL" ]; then
  if ! curl -fsSL --max-time 30 -o "$W/icon" "$ICON_URL"; then
    echo "ICON_URL: fetch failed: $ICON_URL"; fail=1
  elif [ "$(head -c 8 "$W/icon" | od -An -tx1 | tr -d ' \n')" != 89504e470d0a1a0a ]; then
    echo "ICON_URL: not a PNG: $ICON_URL"; fail=1
  else
    echo "ICON_URL ok: $ICON_URL ($(wc -c < "$W/icon" | tr -d ' ') bytes)"
  fi
fi

if [ -n "$ICON_GLOB" ] && [ -n "$APT_REPO" ] && [ -n "$APT_KEY_URL" ]; then
  set -- $(printf '%s\n' "$APT_REPO" | sed 's/\[[^]]*\]//')
  base=$2 suite=$3 comp=$4
  pkg=$(printf '%s\n' "$APT_PKGS" | awk '{ print $1 }'); pkg=${pkg%%=*}
  curl -fsSL --max-time 60 -o "$W/Packages" "$base/dists/$suite/$comp/binary-amd64/Packages"
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
    curl -fsSL -o "$W/pkg.deb" "$base/$best"
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
    else
      echo "ICON_GLOB: nothing in $pkg $bestv matches $ICON_GLOB"; fail=1
    fi
  fi
fi
exit $fail
