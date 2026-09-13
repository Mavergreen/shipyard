#!/bin/sh
#   usage: artifact-facts.sh <dist-dir> <version> [repo-root]
#          Emits the fact stream check-artifact-conformance.sh consumes, by inspecting a built dist/
#          directory and the repo it came from. Deliberately thin: all judgement lives in the
#          checker, so this can be read in one sitting and the interesting logic stays testable
#          without fabricating .pkg files.
# platform: runs at PACKAGE TIME, on macOS, where pkgutil exists and the artifacts do.
# spec: claude-plugins/modernmavericks/skills/modernmavericks-conventions/SKILL.md "Artifact
#       conformance (checked at package time)" -- distinct in scope from the conventions gate, which
#       reads a repo in seconds and gates every PR.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"   # siblings live here (deviations.sh)
dist="${1:?artifact-facts: dist directory required}"
version="${2:?artifact-facts: version required}"
root="${3:-$(pwd)}"

# spec: claude-plugins/modernmavericks/skills/modernmavericks-conventions/SKILL.md "Artifact
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

# spec: tests/artifact-conformance-test.sh -- the line is the NAME of the lines/<X>/ directory whose
#       UPSTREAM_VERSION matches this build's upstream, not a guess from the version: that guess only
#       worked for MINOR-based lines (golang: 1.26 -> 126), and a MAJOR-based line (clang 22, nodejs
#       24) collapses 22.1.1 -> "221", which no identifier carries. Falls back to the old
#       major.minor heuristic only if nothing matches (a committed VERSION that has drifted).
if [ -d "$root/lines" ]; then
  _up="${version%%-mavericks.*}"; _line=""
  for _d in "$root"/lines/*/; do
    [ -f "$_d/UPSTREAM_VERSION" ] || continue
    [ "$(tr -d '[:space:]' < "$_d/UPSTREAM_VERSION")" = "$_up" ] && { _line="$(basename "$_d")"; break; }
  done
  [ -n "$_line" ] || _line="$(printf '%s' "$_up" | cut -d. -f1,2 | tr -d '.')"
  printf 'line %s\n' "$_line"
fi

# spec: claude-plugins/modernmavericks/skills/modernmavericks-conventions/SKILL.md "Conformance
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
  [ -z "$_devs" ] || printf '%s\n' "$_devs" | while read -r _check _glob _reason; do
    if [ "$_glob" = '*' ]; then printf 'deviation %s %s\n' "$_check" "$_reason"
    else printf 'deviation %s:%s %s\n' "$_check" "$_glob" "$_reason"; fi
  done
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
          # platform: a product archive: version, floor and identity all live in Distribution.
          ver="$(sed -n 's/.*<pkg-ref[^>]*version="\([^"]*\)".*/\1/p' "$x/x/Distribution" | head -1)"
          floor="$(sed -n 's/.*<os-version[^>]*min="\([^"]*\)".*/\1/p' "$x/x/Distribution" | head -1)"
          ident="$(sed -n 's/.*<pkg-ref[^>]*id="\([^"]*\)".*/\1/p' "$x/x/Distribution" | head -1)"
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
        fi
        # spec: tests/artifact-conformance-test.sh -- the fact stream is whitespace-delimited, so a
        #       value containing a space would silently shift the fields after it; collapsed to
        #       underscores instead, so a shifted record can't fail the WRONG check invisibly.
        printf 'pkg %s %s %s %s\n' "$b" \
          "$(printf '%s' "${ver:-unknown}" | tr -s '[:space:]' '_')" \
          "$(printf '%s' "${floor:-none}" | tr -s '[:space:]' '_')" \
          "$(printf '%s' "${ident:-none}" | tr -s '[:space:]' '_')"
      else
        printf 'pkg %s unreadable none none\n' "$b"
      fi
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
    *appcast*.xml)
      # spec: claude-plugins/modernmavericks/skills/modernmavericks-conventions/SKILL.md "The Sparkle
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
