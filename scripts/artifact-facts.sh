#!/bin/sh
# platform: macOS-only -- PlistBuddy and pkgutil read a built pkg
#   usage: artifact-facts.sh <dist-dir> <version> [repo-root]
#          Emits the fact stream check-artifact-conformance.sh consumes, by inspecting a built dist/
#          directory and the repo it came from. Deliberately thin: all judgement lives in the
#          checker, so this can be read in one sitting and the interesting logic stays testable
#          without fabricating .pkg files. Also emits a `macho` fact per Mach-O slice in every pkg
#          payload and shipped tarball.
# platform: runs at PACKAGE TIME, on macOS, where pkgutil exists and the artifacts do.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact
#       conformance (checked at package time)" -- distinct in scope from the conventions gate, which
#       reads a repo in seconds and gates every PR.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"   # siblings live here (deviations.sh)
. "$SELF/deviation-reason.sh"
dist="${1:?artifact-facts: dist directory required}"
version="${2:?artifact-facts: version required}"
root="${3:-$(pwd)}"

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact
#       conformance", "A truncated fact stream fails" -- this producer runs upstream of a pipe with
#       no pipefail, so dying here does not fail the step, it TRUNCATES the stream, and every check
#       downstream is a "stay quiet with no records" check. A successful run therefore ends with
#       `end-of-facts`, catching truncation from ANY cause; `abort` carries the human-readable reason
#       across the pipe as a RECORD (so it survives) plus a line on stderr (for this script's own
#       log), so the operator reads WHY rather than only "the stream stopped".
abort() {  # $1 = why.
  printf 'abort %s\n' "$1"
  echo "artifact-facts: $1" >&2
  exit 1
}

printf 'expected %s\n' "$version"

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Install layout and
#       identity" -- what a pkg INSTALLS, read from its payload rather than from the recipe that built it:
#       every installed file or link (installs), every top-level bundle's CFBundleIdentifier (bundle),
#       every launchd job's Label (launchd). Paths are relative to "/" and carry spaces as %20, since
#       the stream is whitespace-delimited and "Application Support" is in nearly every product.
enc() { sed -e 's/%/%25/g' -e 's/ /%20/g'; }
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- one fact per
#       Mach-O slice of every shipped file, read by the ONE parser (macho-slices.sh). A file with an
#       unambiguous Mach-O magic that cannot be read aborts the stream rather than vanishing from it;
#       "cafebabe" (and its 64-bit-offset twin "cafebabf") is also a Java class file's magic and
#       "!<arch>" any ar archive's, so those are Mach-O only if lipo can read them.
macho_facts() {  # $1 = artifact name, $2 = root dir, $3 = path prefix (encoded, may be empty). Non-zero on abort.
  # platform: the file list is captured to a temp file and the loop below reads it via "< $_ml",
  #           not piped in -- a `while` fed by a pipe is the LAST stage of that pipeline, which runs
  #           in a subshell on both dash and bash (no lastpipe by default), so a `return` inside it
  #           only exits the subshell and this function would silently keep going and return 0. A
  #           redirected-in loop has no such subshell, so `return` here really does abort the caller.
  _ml="$(mktemp "${TMPDIR:-/tmp}/macho-facts-list.XXXXXX")"   # template: 10.9 BSD mktemp requires one
  ( cd "$2" && find . -type f ) | sed 's|^\./||' > "$_ml"
  while IFS= read -r _mf; do
    [ -r "$2/$_mf" ] || { echo "artifact-facts: cannot read $1:$_mf" >&2; rm -f "$_ml"; return 1; }
    _mg="$(head -c 4 "$2/$_mf" | od -An -tx1 | tr -d ' \n')"
    case "$_mg" in
      cffaedfe|cefaedfe|feedfacf|feedface) _strict=1 ;;
      cafebabe|cafebabf|213c6172) _strict=0 ;;
      *) continue ;;
    esac
    if ! _sl="$(sh "$SELF/macho-slices.sh" "$2/$_mf")"; then
      [ "$_strict" = 0 ] && continue
      echo "artifact-facts: cannot read Mach-O $1:$_mf" >&2; rm -f "$_ml"; return 1
    fi
    _sha="$(shasum -a 256 "$2/$_mf" | awk '{print $1}')"
    _p="$3$(printf '%s' "$_mf" | enc)"
    printf '%s\n' "$_sl" | while read -r _a _ft _mn _sd; do
      printf 'macho %s %s %s %s %s %s %s\n' "$1" "$_p" "$_a" "$_ft" "$_mn" "$_sd" "$_sha"
    done
  done < "$_ml"
  rm -f "$_ml"
}
payload_facts() {  # $1 = pkg basename, $2 = its expanded tree. Non-zero when a payload cannot be read.
  for _pl in $(find "$2" -name Payload -type f | sed 's/ /%20/g'); do
    _pl="$(printf '%s' "$_pl" | sed 's/%20/ /g')"
    _dir="${_pl%/Payload}"
    # platform: a payload's paths are relative to its component's install-location, not to "/".
    _loc="$(sed -n '/<pkg-info/ s/.*[[:space:]]install-location="\([^"]*\)".*/\1/p' "$_dir/PackageInfo" 2>/dev/null | head -1)"
    _loc="${_loc:-/}"; _loc="${_loc#/}"; _loc="${_loc%/}"; [ -z "$_loc" ] || _loc="$_loc/"
    _root="$_dir.root"; mkdir -p "$_root"
    # platform: pkgbuild writes a gzip'd cpio archive; captured to a file, not piped, so a failed
    #           decompress is a failure here rather than an empty (and therefore "clean") payload.
    gzip -dc "$_pl" > "$_dir.cpio" 2>/dev/null || return 1
    ( cd "$_root" && cpio -id < "$_dir.cpio" 2>/dev/null ) || return 1
    rm -f "$_dir.cpio"
    macho_facts "$1" "$_root" "$(printf '%s' "$_loc" | enc)" || return 1
    ( cd "$_root" && find . \( -type f -o -type l \) ) | sed 's|^\./||' | enc \
      | awk -v pkg="$1" -v loc="$(printf '%s' "$_loc" | enc)" '{ print "installs " pkg " " loc $0 }'
    ( cd "$_root" && find . -type d \( -name '*.app' -o -name '*.prefPane' -o -name '*.kext' -o -name '*.bundle' \
        -o -name '*.plugin' -o -name '*.framework' -o -name '*.appex' -o -name '*.xpc' \) ) | sed 's|^\./||' \
      | awk '{ n = split($0, c, "/"); nested = 0
               for (i = 1; i < n; i++) if (c[i] ~ /\.(app|prefPane|kext|bundle|plugin|framework|appex|xpc)$/) nested = 1
               if (!nested) print }' \
      | while IFS= read -r _bd; do
          _id=none
          for _ip in Contents/Info.plist Resources/Info.plist Info.plist; do
            [ -f "$_root/$_bd/$_ip" ] || continue
            _id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$_root/$_bd/$_ip" 2>/dev/null || echo none)"; break
          done
          printf 'bundle %s %s%s %s\n' "$1" "$(printf '%s' "$_loc" | enc)" "$(printf '%s' "$_bd" | enc)" "${_id:-none}"
        done
    for _ld in Library/LaunchAgents Library/LaunchDaemons; do
      [ -z "$_loc" ] && [ -d "$_root/$_ld" ] || continue
      for _lp in "$_root/$_ld"/*.plist; do
        [ -f "$_lp" ] || continue
        _lab="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$_lp" 2>/dev/null || echo none)"
        printf 'launchd %s %s/%s %s\n' "$1" "$_ld" "$(basename "$_lp" | enc)" "${_lab:-none}"
      done
    done
    # spec: tests/artifact-conformance-test.sh -- a product tree always installs at "/", so only
    #       such a payload can carry a manifest. Values are collapsed like the pkg record's so a
    #       space cannot shift fields; outside entries are encoded like installs paths so the
    #       checker compares them directly.
    [ -z "$_loc" ] || continue
    for _mf in "$_root"/usr/local/mavergreen/*/mavergreen.plist; do
      [ -f "$_mf" ] || continue
      _dir="$(basename "$(dirname "$_mf")" | enc)"
      _mp="$(/usr/libexec/PlistBuddy -c 'Print :product' "$_mf" 2>/dev/null)" || _mp=""
      _mi="$(/usr/libexec/PlistBuddy -c 'Print :identifier' "$_mf" 2>/dev/null)" || _mi=""
      _reg="$(sh "$SELF/product-name.sh" identifier "$_mp" 2>/dev/null)" || _reg=""
      _mp="$(printf '%s' "${_mp:-none}" | tr -s '[:space:]' '_')"
      printf 'manifest %s %s %s %s\n' "$1" "$_mp" "$(printf '%s' "${_mi:-none}" | tr -s '[:space:]' '_')" "$_dir"
      printf 'registered %s %s\n' "$_mp" "$(printf '%s' "${_reg:-none}" | tr -s '[:space:]' '_')"
      _k=0
      while _o="$(/usr/libexec/PlistBuddy -c "Print :outside:$_k" "$_mf" 2>/dev/null)"; do
        printf 'manifest-outside %s %s\n' "$1" "$(printf '%s' "$_o" | tr '\n' ' ' | enc)"; _k=$((_k + 1))
      done
      _k=0
      while _g="$(/usr/libexec/PlistBuddy -c "Print :generated:$_k" "$_mf" 2>/dev/null)"; do
        printf 'manifest-generated %s %s\n' "$1" "$(printf '%s' "$_g" | tr '\n' ' ' | enc)"; _k=$((_k + 1))
      done
    done
  done
  return 0
}

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Conformance
#       deviations" -- declared under "## Conformance deviations" as "- <check>[:<glob>]: <reason>";
#       a deviation IS a product fact, so it belongs with the other product facts, not a file of its
#       own that could disagree with them. ONE parser reads them -- deviations.sh -- because the
#       conventions gate honours the same declarations, and two regexes for one grammar drift apart
#       silently.
if [ -f "$root/INGREDIENTS.md" ]; then
  # platform: not a pipeline -- deviations.sh exits 1 on an entry with no reason, and a pipeline
  #           reports the `while`'s status instead, turning "this declaration is malformed" into
  #           "there are no deviations".
  _devs="$(sh "$SELF/deviations.sh" "$root")" || exit 1
  printf '%s\n' "$_devs" | mav_deviation_facts
fi

for f in "$dist"/*; do
  [ -f "$f" ] || continue
  b="${f##*/}"
  printf 'asset %s %s\n' "$b" "$(wc -c < "$f" | tr -d ' ')"

  case "$b" in
    *.pkg)
      # platform: pkgutil is the only way to read what the .pkg actually declares; a filename is a
      #           claim, not a fact.
      x="$(mktemp -d "${TMPDIR:-/tmp}/artifact-facts.XXXXXX")"   # template: 10.9 BSD mktemp requires one
      if pkgutil --expand "$f" "$x/x" >/dev/null 2>&1; then
        if [ -f "$x/x/Distribution" ]; then
          # platform: a product archive: version, floor and identity all live in Distribution. The
          #           version and identity are the product's, not those of the dev.mavergreen.base
          #           component set_install_floor.sh lists ahead of it; its choice ids are the pkg
          #           identifiers, in install order.
          nb="$(sed -n '/<pkg-ref[^>]*version=/p' "$x/x/Distribution" | grep -v 'id="dev\.mavergreen\.base"' || true)"
          ver="$(printf '%s\n' "$nb" | sed -n 's/.*<pkg-ref[^>]*version="\([^"]*\)".*/\1/p' | head -1)"
          floor="$(sed -n 's/.*<os-version[^>]*min="\([^"]*\)".*/\1/p' "$x/x/Distribution" | head -1)"
          ident="$(printf '%s\n' "$nb" | sed -n 's/.*<pkg-ref[^>]*id="\([^"]*\)".*/\1/p' | head -1)"
          comps="$(sed -n 's/.*<line choice="\([^"]*\)".*/\1/p' "$x/x/Distribution" | grep -v '^default$' || true)"
        else
          # platform: a component package: PackageInfo carries version and identity, and there is NO
          #           floor to read -- that is structural, not a defect (the checker requires an
          #           appcast to declare the minimum instead). Restricted to <pkg-info> and anchored
          #           on a SPACE before the attribute name, or two real artifacts mis-parse: line 1's
          #           <?xml version="1.0"?> would match first without the element restriction, and
          #           generator-version="InstallCmds-864.1 (25E246)" (embedded space) would shift
          #           every later field without the space anchor.
          ver="$(sed -n '/<pkg-info/ s/.*[[:space:]]version="\([^"]*\)".*/\1/p' "$x/x/PackageInfo" 2>/dev/null | head -1)"
          ident="$(sed -n '/<pkg-info/ s/.*[[:space:]]identifier="\([^"]*\)".*/\1/p' "$x/x/PackageInfo" 2>/dev/null | head -1)"
          floor=""
          comps="$ident"
        fi
        # spec: tests/artifact-conformance-test.sh -- the fact stream is whitespace-delimited, so a
        #       value containing a space would silently shift the fields after it; collapsed to
        #       underscores instead, so a shifted record can't fail the WRONG check invisibly.
        printf 'pkg %s %s %s %s\n' "$b" \
          "$(printf '%s' "${ver:-unknown}" | tr -s '[:space:]' '_')" \
          "$(printf '%s' "${floor:-none}" | tr -s '[:space:]' '_')" \
          "$(printf '%s' "${ident:-none}" | tr -s '[:space:]' '_')"
        printf '%s\n' "$comps" | while IFS= read -r c; do
          [ -z "$c" ] || printf 'component %s %s\n' "$b" "$(printf '%s' "$c" | tr -s '[:space:]' '_')"
        done
        payload_facts "$b" "$x/x" || { rm -rf "$x"; abort "cannot read the payload of $b"; }
      else
        printf 'pkg %s unreadable none none\n' "$b"
      fi
      rm -rf "$x"
      ;;
    *.tar.gz|*.tgz|*.tar.xz|*.tar.bz2)
      x="$(mktemp -d "${TMPDIR:-/tmp}/artifact-facts.XXXXXX")"   # template: 10.9 BSD mktemp requires one
      tar -xf "$f" -C "$x" 2>/dev/null || { rm -rf "$x"; abort "cannot extract $b"; }
      macho_facts "$b" "$x" "" || { rm -rf "$x"; abort "cannot read a Mach-O in $b"; }
      rm -rf "$x"
      ;;
    RELEASE_NOTES.md)
      # spec: tests/artifact-conformance-test.sh -- the digest is of the RENDERED body, not the
      #       markdown: what the appcast carries is the HTML fragment, and gen_appcast.sh
      #       --render-notes is the same renderer that builds it, so the two sides of the comparison
      #       cannot drift the way two independent parsers would. Captured rather than piped straight
      #       into shasum: `render-notes | shasum` would let a renderer failure print nothing on
      #       stdout without tripping set -eu, and silently digest to sha256-of-empty.
      render="$(sh "$(dirname "$0")/gen_appcast.sh" --render-notes "$f")" \
        || abort "gen_appcast.sh --render-notes failed for $b"
      [ -n "$render" ] \
        || abort "gen_appcast.sh --render-notes produced no output for $b"
      printf 'notes-render %s %s\n' "$b" "$(printf '%s\n' "$render" | shasum -a 256 | cut -d' ' -f1)"
      ;;
    build-info*)
      # spec: SKILL.md "Artifact conformance", "Record what a variant was built FROM" -- one fact
      #       per key so the checker can compare a single key across variants without parsing files
      #       itself.
      sed -n 's/^\([a-z][a-z0-9_]*\)=\(..*\)$/\1 \2/p' "$f" \
        | while read -r k v; do printf 'build-info %s %s %s\n' "$b" "$k" "$v"; done
      ;;
    *.xml)
      # spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "The Sparkle
      #       comparison version must be dotted-numeric AND monotonic" -- the version that IDENTIFIES
      #       the release is the human shortVersionString; <sparkle:version> is a separate NUMERIC
      #       comparison key Sparkle can order, deliberately NOT equal to the "-mavericks.N" release
      #       version, so conformance reads shortVersionString here.
      ver="$(sed -n 's|.*<sparkle:shortVersionString>\([^<]*\)<.*|\1|p' "$f" | head -1)"
      minos="$(sed -n 's|.*<sparkle:minimumSystemVersion>\([^<]*\)<.*|\1|p' "$f" | head -1)"
      url="$(sed -n 's/.*<enclosure[^>]*url="\([^"]*\)".*/\1/p' "$f" | head -1)"
      len="$(sed -n 's/.*<enclosure[^>]*length="\([^"]*\)".*/\1/p' "$f" | head -1)"
      printf 'appcast %s %s %s %s %s\n' "$b" "${ver:-unknown}" "${url##*/}" "${len:-0}" "${minos:-none}"
      [ -z "$url" ] || printf 'enclosure-url %s %s\n' "$b" "$url"
      # platform: a CDATA body spans lines, and sed is line-oriented, so it cannot isolate one.
      # spec: tests/artifact-conformance-test.sh -- the <description> CDATA, digested. gen_appcast.sh
      #       wraps the rendered notes in a leading blank line and an injected <style> block that
      #       --render-notes never emits; both are stripped so this compares the NOTES against
      #       notes-render, not gen_appcast's own CDATA wrapping. Emitted with no digest when the
      #       appcast has no description at all -- the checker treats that as a failure.
      desc="$(awk '
        /<!\[CDATA\[/ { inside = 1; sub(/.*<!\[CDATA\[/, ""); }
        inside {
          if (match($0, /\]\]>/)) { $0 = substr($0, 1, RSTART - 1); inside = 0 }
          if ($0 !~ /^[[:space:]]*$/ && $0 !~ /^<style[ >]/) print
          if (inside == 0) exit
        }' "$f" | shasum -a 256 | cut -d' ' -f1)"
      if awk '/<!\[CDATA\[/ { found = 1 } END { exit !found }' "$f"; then
        printf 'appcast-notes %s %s\n' "$b" "$desc"
      else
        printf 'appcast-notes %s\n' "$b"
      fi
      ;;
  esac
done

printf 'end-of-facts\n'
