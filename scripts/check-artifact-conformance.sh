#!/bin/sh
# platform: host-agnostic
#   usage: artifact-facts.sh dist "$VER" | check-artifact-conformance.sh
#          Reads a fact stream on stdin (see artifact-facts.sh), one record per line:
#            expected      <version>                              the version this release claims to be
#            pkg           <file> <version> <floor> <identifier>  one per shipped .pkg
#            component     <file> <identifier>                    one per component, in Distribution order
#            installs      <file> <path>                          one per installed file or link (%20-encoded)
#            bundle        <file> <path> <CFBundleIdentifier>     one per top-level bundle
#            launchd       <file> <path> <Label>                  one per launchd job
#            manifest      <file> <product> <identifier> <dir>    one per usr/local/mavergreen/<dir>/mavergreen.plist
#            manifest-outside <file> <path>                       one per entry of that manifest's outside (%20-encoded)
#            manifest-generated <file> <path>                     one per entry of that manifest's generated (%20-encoded)
#            registered    <product> <identifier|none>            what scripts/product-names registers the product to
#            appcast       <file> <version> <enclosure> <length>  one per Sparkle appcast
#            asset         <file> <bytes>                         one per file that will be published
#            macho         <artifact> <path> <arch> <filetype> <minos> <sdk> <sha256>  one per shipped Mach-O slice
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
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/sdk-pins.sh"
. "$SELF/deviation-reason.sh"

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
# spec: scripts/deviation-reason.sh -- the ONE matcher, shared with assert_binary_compatible.sh.
deviation_reason() { mav_deviation_reason "$tmp/devs" "$@"; }  # $1 = check, $2 = subject (optional)

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

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Install layout and
#       identity" -- SIBLINGS: what a pkg installs carries the family's identity. A deviation for these
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

# spec: tests/artifact-conformance-test.sh -- a pkg that installs a product carries exactly one
#       manifest, naming a product registered to one of its components; it installs only into
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
  product_files="$(awk -v p="$pk" '$1 == "installs" && $2 == p && index($3, "usr/local/mavergreen/.base/") != 1' "$facts" | wc -l | tr -d ' ')"
  if [ "$product_files" -gt 0 ] && [ "$n" -ne 1 ]; then
    fail manifest "$pk installs $product_files files but carries $n usr/local/mavergreen/<product>/mavergreen.plist manifests; it must carry exactly one, or nothing can find, update or uninstall what it installed" "$pk"
    continue
  fi
  [ "$n" -eq 1 ] || continue
  read -r _ _ mprod mid mdir <<EOF
$(awk -v p="$pk" '$2 == p' "$tmp/manifests")
EOF
  [ "$mprod" = "$mdir" ] \
    || fail manifest "$pk's manifest names product '$mprod' but sits in usr/local/mavergreen/$(dec "$mdir")" "$pk"
  reg="$(awk -v m="$mprod" '$1 == "registered" && $2 == m { print $3; exit }' "$facts")"
  [ "$reg" = "$mid" ] \
    || fail manifest "$pk's product '$mprod' is not registered to $mid in shipyard's scripts/product-names (registered: ${reg:-none})" "$pk"
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
          || $3 == "usr/local/mavergreen" || index($3, "usr/local/mavergreen/") == 1) print "badshape " $3
      else o[$3] = 1
      next
    }
    $1 == "installs" && $2 == p && index($3, "usr/local/mavergreen/" pr "/") != 1 && index($3, "usr/local/mavergreen/.base/") != 1 {
      hit = ""
      if ($3 in o) hit = $3
      else {
        n = split($3, c, "/"); s = c[1]
        for (i = 1; i < n && hit == ""; i++) {
          if ((s in o) && c[i] ~ /\.(app|kext|prefPane|plugin|bundle|framework)$/) hit = s
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
      unused) fail manifest "$pk's manifest lists $(dec "$op") in outside, but the pkg installs nothing it would remove -- uninstall deletes an entry only as that exact file or link, or as a whole .app, .kext, .prefPane, .plugin, .bundle or .framework directory" "$pk" ;;
      badshape) fail manifest "$pk's manifest lists outside entry '$(dec "$op")' in a shape the helper refuses to uninstall -- empty, absolute, ending in /, an empty, . or .. segment, or under usr/local/mavergreen" "$pk" ;;
    esac
  done < "$tmp/outside-$pk"
  [ "$unlisted" -le 20 ] \
    || fail manifest "$pk installs $((unlisted - 20)) more files outside its tree that its manifest's outside list does not name" "$pk"
  awk -v p="$pk" '$1 == "manifest-generated" && $2 == p { print $3 }' "$facts" > "$tmp/generated-$pk"
  while IFS= read -r gp; do
    case "$gp" in
      ''|/*|*/|*//*|usr/local/mavergreen|usr/local/mavergreen/*) gbad=1 ;;
      *) case "/$gp/" in *"/./"*|*"/../"*) gbad=1 ;; *) gbad=0 ;; esac ;;
    esac
    [ "$gbad" -eq 0 ] \
      || fail manifest "$pk's manifest lists generated entry '$(dec "$gp")' in a shape the helper refuses to uninstall -- empty, absolute, ending in /, an empty, . or .. segment, or under usr/local/mavergreen" "$pk"
  done < "$tmp/generated-$pk"
done

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Install layout and
#       identity" -- where a family product may put files by default. Anything else is a declared
#       deviation scoped to the PATH (glob; `*` spans "/" and spaces), so excusing a kext's
#       directory cannot quietly excuse a stray file elsewhere in the same pkg. Reported once per
#       reason and capped, since one wrong directory can hold thousands of files.
installs_seen=0
last_file=""; prod=""; has_base=no
: > "$tmp/ip-dev"; : > "$tmp/ip-fail"
while read -r kind file path; do
  [ "$kind" = installs ] || continue
  installs_seen=$((installs_seen + 1))
  if [ "$file" != "$last_file" ]; then
    last_file="$file"
    prod="$(awk -v f="$file" '$1 == f { print $2; exit }' "$tmp/prod-of")"
    has_base=no
    awk -v f="$file" '$2 == f && $3 == "dev.mavergreen.base" { g = 1 } END { exit !g }' "$tmp/components" && has_base=yes
  fi
  if [ -n "$prod" ]; then case "$path" in "usr/local/mavergreen/$prod/"*) continue ;; esac; fi
  case "$path" in
    usr/local/mavergreen/.base/*) [ "$has_base" = no ] || continue ;;
    Applications/*|"Library/Application%20Support/Mavergreen/"*) continue ;;
    Library/LaunchAgents/dev.mavergreen.*.plist|Library/LaunchDaemons/dev.mavergreen.*.plist) continue ;;
  esac
  p="$(dec "$path")"
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
    echo "conformance: install-path: $l -- outside usr/local/mavergreen/<its product>, usr/local/mavergreen/.base (with the base component), Applications, Library/Application Support/Mavergreen and dev.mavergreen.* launchd jobs" >&2
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
  # platform: a self-upstream product's tag carries a leading v (magic-trackpad2's v0.5.5), while
  #           $expected is the bare version, so both spellings name THIS release.
  case "$url" in
    */download/"$expected"/*|*/download/v"$expected"/*) : ;;
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

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- every shipped
#       Mach-O slice records its arch's pinned minos and SDK, unless its bytes are a pinned third-party
#       binary or a declared sdk-pin:<glob> deviation names its path.
while read -r kind file path arch ft mn sd sha; do
  [ "$kind" = macho ] || continue
  mav_sdk_exempt_sha256 "$sha" && continue
  why="$(mav_sdk_rule "$arch" "$ft" "$mn" "$sd")" \
    || fail sdk-pin "$file installs $(dec "$path") ($arch): $why" "$(dec "$path")"
done < "$facts"

[ "$status" -eq 0 ] && echo "conformance: ok — $expected"
exit "$status"
