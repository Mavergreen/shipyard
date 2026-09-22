#!/bin/sh
#   usage: artifact-facts.sh dist "$VER" | check-artifact-conformance.sh
#          Reads a fact stream on stdin (see artifact-facts.sh), one record per line:
#            expected      <version>                              the version this release claims to be
#            pkg           <file> <version> <floor> <identifier>  one per shipped .pkg
#            appcast       <file> <version> <enclosure> <length>  one per Sparkle appcast
#            asset         <file> <bytes>                         one per file that will be published
#            notes-render  <notes-file> <sha256>                  digest of gen_appcast.sh --render-notes
#            appcast-notes <appcast-file> [<sha256>]               digest of the appcast's <description> CDATA
#            deviation     <check> <reason...>                    a declared, reasoned departure
#            abort         <reason...>                            the producer gave up here, and why
#            end-of-facts                                         the producer ran to completion (LAST line)
#          Facts rather than files: the agreement logic is testable without fabricating real .pkg
#          files, and extraction is exercised for real at package time.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact
#       conformance (checked at package time)" -- what this checks and why, on all three axes
#       (itself / neighbours / siblings), lives there.
set -eu

tmp="$(mktemp -d "${TMPDIR:-/tmp}/conformance.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT  # template: 10.9 BSD mktemp requires one
facts="$tmp/facts"; cat > "$facts"

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact
#       conformance", "A truncated fact stream fails" -- every check below is a "stay quiet with no
#       records" check, so a truncated stream would pass them all; the producer's exit status is
#       discarded by the pipe (no pipefail), so a sentinel is the only structural fix. Checked here,
#       not via fail(), and abort checked first and separately: neither may be excused by a
#       deviation, or the switch-off would excuse the very check that notices switch-offs.
why="$(sed -n 's/^abort \(..*\)$/\1/p' "$facts" | head -1)"
if [ -n "$why" ]; then
  echo "conformance: artifact-facts.sh aborted: $why" >&2
  echo "conformance: the fact stream cannot be trusted; nothing was checked" >&2
  exit 2
fi

if ! grep -q '^end-of-facts$' "$facts"; then
  echo "conformance: the fact stream is incomplete -- artifact-facts.sh did not run to completion (no end-of-facts record); nothing was checked" >&2
  exit 2
fi

grep '^deviation ' "$facts" > "$tmp/devs" || true
deviation_reason() {  # $1 = check, $2 = the subject it concerns (optional). Prints the reason, if any.
  _dr="$(sed -n "s/^deviation ${1} \(..*\)$/\1/p" "$tmp/devs" | head -1)"
  if [ -z "$_dr" ] && [ -n "${2:-}" ]; then
    while IFS= read -r line; do
      rest="${line#deviation ${1}:}"
      glob="${rest%% *}"
      why="${rest#* }"
      [ "$why" = "$rest" ] && why=""      # no space => a glob with no reason, which is not a deviation
      case "$2" in
        $glob) [ -n "$why" ] && _dr="$why" && break ;;
      esac
    done <<EOF
$(grep "^deviation ${1}:" "$tmp/devs" || true)
EOF
  fi
  printf '%s' "$_dr"
}

status=0
fail() {  # $1 = check name, $2 = message, $3 = the artifact it concerns (optional)
  # spec: SKILL.md "Artifact conformance" -- a deviation excuses only its OWN check, only for the
  #       artifacts it names, and only with a reason (swift-toolchain's swift.org .pkg is the scoping
  #       example there).
  _c="$1"; _msg="$2"; _file="${3:-}"
  reason="$(deviation_reason "$_c" "$_file")"
  if [ -n "$reason" ]; then
    echo "conformance: ${_c}: DECLARED DEVIATION${_file:+ (${_file})} -- $reason"
    return 0
  fi
  # spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Conformance
  #       deviations" -- excusing requires a REASON; a bare "deviation <check>" with none must still
  #       fail here, the same way its sibling above (the completion sentinel) refuses to let any
  #       deviation excuse it -- a switch-off with no reason attached is indistinguishable from a
  #       check nobody wrote.
  if grep -q "^deviation ${_c}\$" "$facts"; then
    echo "conformance: ${_c}: deviation declared with no reason -- state why, or fix the artifact" >&2
    status=1; return 0
  fi
  echo "conformance: ${_c}: ${_msg}" >&2
  status=1
}

expected="$(sed -n 's/^expected \(..*\)$/\1/p' "$facts" | head -1)"
[ -n "$expected" ] || { echo "conformance: no expected version in the fact stream" >&2; exit 2; }

# spec: SKILL.md "Artifact conformance" axis table -- SIBLINGS: version scheme <upstream>-mavericks.N.
case "$expected" in
  *-mavericks.[0-9]*) : ;;
  *) fail scheme "version '$expected' is not <upstream>-mavericks.N" ;;
esac

# spec: SKILL.md "Artifact conformance" axis table -- ITSELF/NEIGHBOURS: every .pkg agrees with the
#       tag, floor and identifier scheme.
while read -r kind file ver floor ident; do
  [ "$kind" = pkg ] || continue
  [ "$ver" = "$expected" ] \
    || fail version "$file says version $ver, the release is $expected" "$file"
  # platform: a product archive (Distribution) declares an install floor; a component package
  #           (PackageInfo) cannot -- floors are a productbuild concept -- so its minimum lives in the
  #           appcast instead. golang's cross product targets 10.9 but runs on 11.0+, so demanding
  #           10.9.5 of it would be wrong.
  if [ "$floor" = none ]; then
    grep -q "^appcast .* $file [0-9][0-9]* [0-9]" "$facts" \
      || fail floor "$file declares no install floor, and no appcast declares a minimum system version for it" "$file"
  else
    [ "$floor" = 10.9.5 ] \
      || fail floor "$file declares an install floor of $floor, not 10.9.5" "$file"
  fi
  case "$ident" in
    dev.mavergreen.*) : ;;
    *) fail identifier "$file has identifier '$ident', outside dev.mavergreen.*" "$file" ;;
  esac
done < "$facts"

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Identity and install
#       paths" -- SIBLINGS: what a pkg installs carries the family's identity. A deviation for these
#       is scoped to the bundle identifier or Label it excuses, not to the pkg that ships it.
dec() { printf '%s' "$1" | sed -e 's/%20/ /g' -e 's/%25/%/g'; }
while read -r kind file path id; do
  [ "$kind" = bundle ] || continue
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

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Identity and install
#       paths" -- where a family product may put files by default. Anything else is a declared
#       deviation scoped to the PATH (glob; `*` spans "/" and spaces), so excusing a kext's
#       directory cannot quietly excuse a stray file elsewhere in the same pkg. Reported once per
#       reason and capped, since one wrong directory can hold thousands of files.
installs_seen=0
: > "$tmp/ip-dev"; : > "$tmp/ip-fail"
while read -r kind file path; do
  [ "$kind" = installs ] || continue
  installs_seen=$((installs_seen + 1))
  p="$(dec "$path")"
  case "$p" in
    usr/local/*|Applications/*|"Library/Application Support/Mavergreen/"*) continue ;;
    Library/LaunchAgents/dev.mavergreen.*.plist|Library/LaunchDaemons/dev.mavergreen.*.plist) continue ;;
  esac
  r="$(deviation_reason install-path "$p")"
  if [ -n "$r" ]; then printf '%s\n' "$r" >> "$tmp/ip-dev"
  else printf '%s: %s\n' "$file" "$p" >> "$tmp/ip-fail"; fi
done < "$facts"
sort "$tmp/ip-dev" | uniq -c | while read -r n r; do
  echo "conformance: install-path: DECLARED DEVIATION ($n files) -- $r"
done
nfail="$(wc -l < "$tmp/ip-fail" | tr -d ' ')"
if [ "$nfail" -gt 0 ]; then
  head -20 "$tmp/ip-fail" | while IFS= read -r l; do
    echo "conformance: install-path: $l -- outside usr/local, Applications, Library/Application Support/Mavergreen and dev.mavergreen.* launchd jobs" >&2
  done
  [ "$nfail" -le 20 ] || echo "conformance: install-path: ... and $((nfail - 20)) more" >&2
  status=1
fi
echo "conformance: install-path: checked $installs_seen installed files"

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
  case "$url" in
    */download/"$expected"/*) : ;;
    *) fail enclosure-url "$file points outside this release: $url -- Sparkle would silently serve users a different build than the one just published, and every other check here still passes because both artifacts are individually fine" "$file" ;;
  esac
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

[ "$status" -eq 0 ] && echo "conformance: ok — $expected"
exit "$status"
