#!/bin/sh
# platform: host-agnostic
#   usage: artifact-facts.sh <dist-dir> <version> [repo-root]
#          Emits the fact stream check-artifact-conformance.sh consumes, by inspecting a built dist/
#          directory and the repo it came from. Deliberately thin: all judgement lives in the
#          checker, so this can be read in one sitting and the interesting logic stays testable
#          without fabricating .pkg files. Also emits a `macho` fact per Mach-O slice in every pkg
#          payload and shipped tarball.
#          Reads pkgs with bsdtar and plists with plist-facts.py, and Mach-O with LLVM's readers
#          (lib/macho-tools.sh), so it runs the same on 10.9, modern macOS and Linux.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact
#       conformance (checked at package time)" -- distinct in scope from the conventions gate, which
#       reads a repo in seconds and gates every PR.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"   # siblings live here (deviations.sh)
. "$SELF/deviation-reason.sh"
. "$SELF/registry-lookup.sh"
. "$SELF/lib/py.sh"
. "$SELF/lib/pkg-read.sh"
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
[ -z "${GITHUB_REPOSITORY:-}" ] || printf 'repository %s\n' "$GITHUB_REPOSITORY"

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Install layout and
#       identity" -- what a pkg INSTALLS, read from its payload rather than from the recipe that built it:
#       every installed file or link (installs), every top-level bundle's CFBundleIdentifier (bundle),
#       every launchd job's Label (launchd). Paths are relative to "/" and carry spaces as %20, since
#       the stream is whitespace-delimited and "Application Support" is in nearly every product.
enc() { af_enc; }
# spec: scripts/lib/plist-facts.py -- a plist is read once into _pl, as "<key-path><TAB><value>" lines;
#       one that cannot be read aborts the stream naming the file, since a fact read from half a
#       plist is a fact about nothing. plist_val answers one key-path from it, empty when absent.
plist_load() {  # $1 = plist file, $2 = its name for the operator. Non-zero when unreadable (why in _pf_why).
  _pf_err="$(mktemp "${TMPDIR:-/tmp}/plist-err.XXXXXX")"
  if _pl="$(chk_py "$SELF/lib/plist-facts.py" "$1" 2>"$_pf_err")"; then
    rm -f "$_pf_err"; return 0
  fi
  _pf_why="cannot read the plist $2: $(tr '\n' ' ' < "$_pf_err")"
  rm -f "$_pf_err"; return 1
}
plist_val() { printf '%s\n' "$_pl" | awk -F'\t' -v k="$1" '$1 == k { print $2; exit }'; }
plist_list() { printf '%s\n' "$_pl" | awk -F'\t' -v k="$1" 'index($1, k ":") == 1 { print $2 }'; }
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- one fact per
#       Mach-O slice of every shipped file, read by the ONE parser (macho-slices.sh). A file with an
#       unambiguous Mach-O magic that cannot be read aborts the stream rather than vanishing from it;
#       "cafebabe" (and its 64-bit-offset twin "cafebabf") is also a Java class file's magic and
#       "!<arch>" any ar archive's, so those are Mach-O only if lipo can read them.
macho_facts() {  # $1 = artifact name, $2 = root dir, $3 = path prefix (encoded, may be empty). Non-zero on abort, with why in _mf_why.
  # platform: the file list is captured to a temp file and the loop below reads it via "< $_ml",
  #           not piped in -- a `while` fed by a pipe is the LAST stage of that pipeline, which runs
  #           in a subshell on both dash and bash (no lastpipe by default), so a `return` inside it
  #           only exits the subshell and this function would silently keep going and return 0. A
  #           redirected-in loop has no such subshell, so `return` here really does abort the caller.
  _ml="$(mktemp "${TMPDIR:-/tmp}/macho-facts-list.XXXXXX")"   # template: 10.9 BSD mktemp requires one
  _mferr="$_ml.err"
  ( cd "$2" && find . -type f ) | sed 's|^\./||' > "$_ml"
  while IFS= read -r _mf; do
    [ -r "$2/$_mf" ] || { _mf_why="cannot read a Mach-O in $1: $_mf is unreadable"; echo "artifact-facts: cannot read $1:$_mf" >&2; rm -f "$_ml" "$_mferr"; return 1; }
    case "$(af_macho_kind "$2/$_mf")" in
      strict) _strict=1 ;;
      loose) _strict=0 ;;
      *) continue ;;
    esac
    _rc=0; _sl="$(sh "$SELF/macho-slices.sh" "$2/$_mf" 2>"$_mferr")" || _rc=$?
    # spec: scripts/macho-slices.sh -- exit 1 is "not Mach-O" (skipped for the ambiguous magics); exit 4 is a
    #       reader that is missing or failed, and any other status is unexpected: both abort, never vanish.
    if [ "$_rc" -ne 0 ]; then
      [ "$_strict" = 0 ] && [ "$_rc" -eq 1 ] && continue
      _mf_why="cannot read a Mach-O in $1: $_mf (macho-slices.sh exit $_rc) $(tr '\n' ' ' < "$_mferr")"
      echo "artifact-facts: cannot read Mach-O $1:$_mf (macho-slices.sh exit $_rc)" >&2; rm -f "$_ml" "$_mferr"; return 1
    fi
    _sha="$(shasum -a 256 "$2/$_mf" | awk '{print $1}')"
    _p="$3$(printf '%s' "$_mf" | enc)"
    printf '%s\n' "$_sl" | while read -r _a _ft _mn _sd; do
      printf 'macho %s %s %s %s %s %s %s\n' "$1" "$_p" "$_a" "$_ft" "$_mn" "$_sd" "$_sha"
    done
  done < "$_ml"
  rm -f "$_ml" "$_mferr"
}
payload_facts() {  # $1 = pkg basename, $2 = its expanded tree. Non-zero when a payload cannot be read, or the registry cannot answer (why in _pf_why).
  _pf_why=""
  for _pl_f in $(find "$2" -name Payload -type f | sed 's/ /%20/g'); do
    _pl_f="$(printf '%s' "$_pl_f" | sed 's/%20/ /g')"
    # platform: a payload's paths are relative to its component's install-location, not to "/".
    # spec: scripts/lib/pkg-read.sh -- bsdtar reads the gzip'd cpio itself, and a failed read is a
    #       failure here rather than an empty (and therefore "clean") payload.
    af_unpack_payload "$_pl_f" || { _pf_why="cannot read the payload of $1"; return 1; }
    _root="$AF_ROOT"; _loc="$AF_LOC"
    macho_facts "$1" "$_root" "$(printf '%s' "$_loc" | enc)" || { _pf_why="$_mf_why"; return 1; }
    ( cd "$_root" && find . \( -type f -o -type l \) ) | sed 's|^\./||' | enc \
      | awk -v pkg="$1" -v loc="$(printf '%s' "$_loc" | enc)" '{ print "installs " pkg " " loc $0 }'
    ( cd "$_root" && find . -type d \( -name '*.app' -o -name '*.prefPane' -o -name '*.kext' -o -name '*.bundle' \
        -o -name '*.plugin' -o -name '*.framework' -o -name '*.appex' -o -name '*.xpc' \) ) | sed 's|^\./||' \
      | awk '{ n = split($0, c, "/"); nested = 0
               for (i = 1; i < n; i++) if (c[i] ~ /\.(app|prefPane|kext|bundle|plugin|framework|appex|xpc)$/) nested = 1
               if (!nested) print }' > "$_pl_f.bundles"
    while IFS= read -r _bd; do
      _id=none; _feed=""
      for _ip in Contents/Info.plist Resources/Info.plist Info.plist; do
        [ -f "$_root/$_bd/$_ip" ] || continue
        plist_load "$_root/$_bd/$_ip" "$1:$_loc$_bd/$_ip" || return 1
        _id="$(plist_val CFBundleIdentifier)"; _feed="$(plist_val SUFeedURL)"; break
      done
      printf 'bundle %s %s%s %s\n' "$1" "$(printf '%s' "$_loc" | enc)" "$(printf '%s' "$_bd" | enc)" "${_id:-none}"
      [ -z "$_feed" ] || printf 'sparkle %s %s%s %s\n' "$1" "$(printf '%s' "$_loc" | enc)" \
        "$(printf '%s' "$_bd" | enc)" "$(printf '%s' "$_feed" | tr -s '[:space:]' '_')"
    done < "$_pl_f.bundles"
    for _ld in Library/LaunchAgents Library/LaunchDaemons; do
      [ -z "$_loc" ] && [ -d "$_root/$_ld" ] || continue
      for _lp in "$_root/$_ld"/*.plist; do
        [ -f "$_lp" ] || continue
        plist_load "$_lp" "$1:$_ld/${_lp##*/}" || return 1
        _lab="$(plist_val Label)"
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
      plist_load "$_mf" "$1:usr/local/mavergreen/${_dir}/mavergreen.plist" || return 1
      _mp="$(plist_val product)"; _mi="$(plist_val identifier)"
      _reg=""; _repo=""; _dv=""
      for _q in identifier repo updater-bundle-id agent-label updater-app feed; do
        _rc=0; registry_lookup "$_q" "$_mp" || _rc=$?
        [ "$_rc" -ne 1 ] || break
        [ "$_rc" -eq 0 ] || { _pf_why="cannot look up $_mp in shipyard's registry: $(printf '%s' "$REG_WHY" | tr '\n' ' ')"; return 1; }
        case "$_q" in
          identifier) _reg="$REG_V" ;;
          repo) _repo="$REG_V" ;;
          updater-app) _dv="$_dv $(printf '%s' "$REG_V" | enc)" ;;
          *) _dv="$_dv $REG_V" ;;
        esac
      done
      _dv="${_dv# }"
      _ml="$(plist_val line)"
      _ma="$(plist_val appcast)"
      _mp="$(printf '%s' "${_mp:-none}" | tr -s '[:space:]' '_')"
      printf 'manifest %s %s %s %s\n' "$1" "$_mp" "$(printf '%s' "${_mi:-none}" | tr -s '[:space:]' '_')" "$_dir"
      printf 'registered %s %s %s\n' "$_mp" "$(printf '%s' "${_reg:-none}" | tr -s '[:space:]' '_')" "${_repo:-none}"
      printf 'manifest-line %s %s\n' "$1" "$(printf '%s' "${_ml:-none}" | tr -s '[:space:]' '_')"
      printf 'manifest-appcast %s %s\n' "$1" "$(printf '%s' "${_ma:-none}" | tr -s '[:space:]' '_')"
      [ -z "$_dv" ] || printf 'derived %s %s\n' "$_mp" "$_dv"
      plist_list outside | while IFS= read -r _o; do
        printf 'manifest-outside %s %s\n' "$1" "$(printf '%s' "$_o" | enc)"
      done
      plist_list generated | while IFS= read -r _g; do
        printf 'manifest-generated %s %s\n' "$1" "$(printf '%s' "$_g" | enc)"
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
  printf '%s\n' "$_devs" | shipyard_deviation_facts
fi

for f in "$dist"/*; do
  [ -f "$f" ] || continue
  b="${f##*/}"
  printf 'asset %s %s\n' "$b" "$(wc -c < "$f" | tr -d ' ')"

  case "$b" in
    *.pkg)
      # spec: scripts/lib/pkg-read.sh -- reading what the .pkg actually declares is the point; a
      #       filename is a claim, not a fact. A host with no bsdtar cannot say, which aborts the
      #       stream rather than reading every pkg as unreadable.
      x="$(mktemp -d "${TMPDIR:-/tmp}/artifact-facts.XXXXXX")"   # template: 10.9 BSD mktemp requires one
      mkdir "$x/x"
      af_bsdtar >/dev/null 2>&1 || { rm -rf "$x"; abort "cannot read $b: no bsdtar found -- install libarchive-tools, or set BSDTAR to its path"; }
      if af_extract "$f" "$x/x"; then
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
        payload_facts "$b" "$x/x" || { af_rm "$x"; abort "${_pf_why:-cannot read the payload of $b}"; }
      else
        printf 'pkg %s unreadable none none\n' "$b"
      fi
      af_rm "$x"
      ;;
    *.tar.gz|*.tgz|*.tar.xz|*.tar.bz2)
      x="$(mktemp -d "${TMPDIR:-/tmp}/artifact-facts.XXXXXX")"   # template: 10.9 BSD mktemp requires one
      af_extract "$f" "$x" || { af_rm "$x"; abort "cannot extract $b"; }
      macho_facts "$b" "$x" "" || { af_rm "$x"; abort "${_mf_why:-cannot read a Mach-O in $b}"; }
      af_rm "$x"
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
