#!/bin/sh
# platform: host-agnostic
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
. "$SELF/mavergreen-meta.sh"
. "$SELF/deviation-reason.sh"
MAVERGREEN_ROOT="$(pwd)"
shipyard_deviations . >/dev/null 2>&1 || :
REL=.github/workflows/release.yml
TAB="$(printf '\t')"
CR="$(printf '\r')"

if [ -f "$REL" ]; then
  chk_ran upstream-complete
  if [ ! -d .mavergreen/upstream ]; then
    chk_fail upstream-complete "there is no .mavergreen/upstream/" \
      "the release version is derived from it, so without it there is no version to cut" \
      "create .mavergreen/upstream/ with VERSION (or COMMIT or PIN) and a one-line description"
  else
    _kinds=""
    for _k in VERSION COMMIT PIN; do
      if mg_has "upstream/$_k"; then _kinds="$_kinds $_k"; fi
    done
    set -- $_kinds
    if [ "$#" -eq 0 ]; then
      chk_fail upstream-complete ".mavergreen/upstream/ has none of VERSION, COMMIT or PIN" \
        "the release version is derived from one of them" \
        "add .mavergreen/upstream/VERSION holding the upstream's version (or COMMIT or PIN)"
    elif [ "$#" -gt 1 ]; then
      chk_fail upstream-complete ".mavergreen/upstream/ has more than one of VERSION, COMMIT or PIN:$_kinds" \
        "which one the version comes from would be a guess" \
        "keep the one Renovate tracks and delete the others"
    elif [ "$1" != VERSION ] && ! mg_has hooks/derive-upstream-version; then
      chk_fail upstream-complete ".mavergreen/upstream/$1 has no .mavergreen/hooks/derive-upstream-version" \
        "a $1 is not a version, and nothing turns it into one" \
        "add .mavergreen/hooks/derive-upstream-version, printing the upstream's version"
    fi
    mg_has upstream/description \
      || chk_fail upstream-complete ".mavergreen/upstream/ has no description" \
           "nothing says what the upstream is" \
           "add .mavergreen/upstream/description: one line saying what the upstream is"
  fi
else
  chk_notrun upstream-complete "no $REL, so this is not a product repo and the rule has nothing to hold to"
fi

chk_ran value-file-line
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/check-metadata.XXXXXX")"
trap 'rm -rf "$w"' EXIT
if [ -d .mavergreen ]; then
  find .mavergreen -type f | LC_ALL=C sort > "$w/files"
  while IFS= read -r f; do
    rel="${f#.mavergreen/}"
    case "/$rel" in
      */.*|/hooks/*|*/hooks/*|/config/*|/release-notes/*|*.md) continue ;;
    esac
    case "${rel##*/}" in
      reason|revisit|untracked|tracked-by|role|watch|target|union|intree) continue ;;
    esac
    shipyard_deviated value-file-line "$f" >/dev/null && continue
    bad=""
    if grep -q "$CR" "$f"; then
      bad="it holds a carriage return (a CRLF line ending)"
    else
      n=0
      while IFS= read -r l || [ -n "$l" ]; do
        n=$((n + 1))
        if [ "$n" -eq 1 ]; then
          case "$l" in
            [" $TAB"]*|*[" $TAB"]) bad="line 1 has a space or a tab before or after the value" ;;
          esac
          if [ "$rel" = upstream/VERSION ]; then
            case "$l" in [vV][0-9]*) bad="${bad:-line 1 starts with a v}" ;; esac
          fi
        elif [ "$n" -eq 2 ]; then
          case "$l" in '# renovate:'*) ;; *) bad="${bad:-line 2 is not a '# renovate:' annotation}" ;; esac
        else
          bad="${bad:-it has more than two lines}"
          break
        fi
      done < "$f"
    fi
    [ -z "$bad" ] || chk_fail value-file-line "$f is not a value file: $bad" \
      "every reader takes line 1 as the value, so whitespace, a CR or a v becomes part of it, and any line 2 but a Renovate annotation is a value nobody reads" \
      "write the value alone on line 1, and nothing after it but a '# renovate: datasource=... depName=...' line"
  done < "$w/files"
fi

exit "$chk_status"
