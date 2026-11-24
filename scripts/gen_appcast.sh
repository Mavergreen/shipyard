#!/bin/sh
# platform: host-agnostic
#   usage: gen_appcast.sh <short> <version> <pkg-url> <min-os> <notes-file> <enclosure-attrs>
#          gen_appcast.sh --render-notes <notes-file>      # emit just the HTML fragment (test seam)
#          Generates the Sparkle feed (<short name>.xml) for ONE release, to stdout. Fails if the notes file is
#          missing or empty: the notes ARE the release's <description>.
#          Release notes (docs/release-notes/vX.Y.Z.md) are rendered from Markdown to a subset of
#          HTML, inlined into the <description> CDATA:
#            `## Heading`            -> <h2>Heading</h2>
#            `### Heading`           -> <h3>Heading</h3>       (the generated upstream/ingredient
#                                                                sections)
#            contiguous `- ` bullets -> <ul><li>...</li></ul>  (continuation lines fold into the
#                                                                item)
#            `[text](scheme:url)`    -> <a href="...">text</a> (upstream-notes.sh links upstream's
#                                                                notes)
#            `**bold**`              -> <strong>bold</strong>
#            `*italic*`              -> <em>italic</em>
#            `---` on its own line   -> <hr>                   (release-notes.sh's footer rule)
#            blank-line-separated prose (incl. the trailing `Requires...`) -> <p>...</p>
#          <enclosure-attrs> is the `sparkle:edSignature="..." length="..."` string that
#          `sign_update -s <key> <pkg>` prints -- passed in, so this script needs no signing key and
#          stays a pure text transform, unit-testable via --render-notes.
# platform: Sparkle 1.x shows the <description> in a WebView, which treats the CDATA as HTML; feeding
#           it raw Markdown collapsed the notes into one line-joined blob.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "The build must
#       also run natively ON 10.9" -- the renderer is deliberately dependency-free (pure awk, no
#       pandoc/cmark) so it runs identically on the 10.9 dev box's BSD/BWK awk and on a modern CI
#       runner.
set -eu

md_to_html() {
  awk '
    function esc(s) {                       # HTML-escape before we inject our own tags
      gsub(/&/, "\\&amp;", s)
      gsub(/</, "\\&lt;",  s)
      gsub(/>/, "\\&gt;",  s)
      return s
    }
    function inline(s,   r, before, m, i) { # links, **bold**, *italic* (BWK awk: no gensub backrefs)
      s = esc(s)
      r = ""
      # spec: tests/gen_appcast.bats "leaves brackets that are not a link alone" -- only a
      #       scheme-qualified target is a link, so prose like "[the docs] (later)" stays prose.
      while (match(s, /\[[^]]+\]\([a-z]+:[^) ]+\)/)) {
        before = substr(s, 1, RSTART - 1)
        m = substr(s, RSTART + 1, RLENGTH - 2)          # text](url
        i = index(m, "](")
        r = r before "<a href=\"" substr(m, i + 2) "\">" substr(m, 1, i - 1) "</a>"
        s = substr(s, RSTART + RLENGTH)
      }
      s = r s
      r = ""
      while (match(s, /\*\*[^*]+\*\*/)) {
        before = substr(s, 1, RSTART - 1)
        m = substr(s, RSTART + 2, RLENGTH - 4)
        r = r before "<strong>" m "</strong>"
        s = substr(s, RSTART + RLENGTH)
      }
      s = r s
      r = ""
      while (match(s, /\*[^*]+\*/)) {
        before = substr(s, 1, RSTART - 1)
        m = substr(s, RSTART + 1, RLENGTH - 2)
        r = r before "<em>" m "</em>"
        s = substr(s, RSTART + RLENGTH)
      }
      return r s
    }
    function flush_li() { if (li != "") { print "<li>" inline(li) "</li>"; li = "" } }
    function close_block() {
      if (mode == "p")  { if (p != "") print "<p>" inline(p) "</p>"; p = "" }
      else if (mode == "ul") { flush_li(); print "</ul>" }
      mode = ""
    }
    { line = $0 }
    line ~ /^[[:space:]]*$/ { close_block(); next }         # blank line closes the current block
    line ~ /^## / {                                         # heading
      close_block()
      print "<h2>" inline(substr(line, 4)) "</h2>"
      next
    }
    line ~ /^### / {
      close_block()
      print "<h3>" inline(substr(line, 5)) "</h3>"
      next
    }
    line ~ /^- / {                                          # bullet item start
      if (mode == "p") close_block()
      if (mode != "ul") { print "<ul>"; mode = "ul" }
      flush_li()
      li = substr(line, 3)
      next
    }
    line ~ /^---[[:space:]]*$/ { close_block(); print "<hr>"; next }   # thematic break (footer rule)
    {                                                       # prose / continuation line
      sub(/^[[:space:]]+/, "", line)
      if (mode == "ul") { li = li " " line }
      else { mode = "p"; p = (p == "" ? line : p " " line) }
    }
    END { close_block() }
  ' "$1"
}

if [ "${1:-}" = "--render-notes" ]; then
  [ $# -eq 2 ] || { echo "usage: gen_appcast.sh --render-notes <notes-file>" >&2; exit 2; }
  [ -f "$2" ] || { echo "release notes not found: $2" >&2; exit 1; }
  [ -s "$2" ] || { echo "release notes empty: $2" >&2; exit 1; }
  md_to_html "$2"
  exit 0
fi

SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"          # comparison_key()

[ $# -eq 6 ] || { echo "usage: gen_appcast.sh <short> <version> <pkg-url> <min-os> <notes-file> <enclosure-attrs>" >&2; exit 2; }
SHORT="$1"; VER="$2"; URL="$3"; MINOS="$4"; NOTES_FILE="$5"; ENCLOSURE_ATTRS="$6"
CHANNEL_TITLE="$(mavergreen_name channel-title "$SHORT")" || exit 1
ITEM_TITLE="$(mavergreen_name item-title "$SHORT" "$VER")" || exit 1

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "The Sparkle
#       comparison version must be dotted-numeric AND monotonic" -- SUStandardVersionComparator can't
#       order the "-mavergreen.N" suffix (it reads 1.2.3-mavergreen.3 and .4 as EQUAL), so
#       <sparkle:version> must be numeric-only; the human string stays in shortVersionString. The
#       derivation itself is lib/vercmp.sh's mavergreen_build_version(), which render-manifest.sh's
#       build-version also uses; MavericksSparkle.cmake mirrors comparison_key().
BUILD_VER=$(mavergreen_build_version "$VER")

# spec: tests/gen_appcast.bats -- fail closed if the derived key is not purely dotted-numeric
#       (X.Y.Z.N): SUStandardVersionComparator only totally orders that domain, and every "update
#       says I'm up to date" bug lived outside it. Caught here, at the source every product's appcast
#       flows through. The monotonic "> previous release" half is
#       assert_appcast_upgradeable.sh, which needs the prior release to compare.
case "$BUILD_VER" in
  ''|.*|*.|*..*|*[!0-9.]*)
    echo "gen_appcast: sparkle:version '$BUILD_VER' (from version '$VER') is not purely dotted-numeric --" >&2
    echo "  SUStandardVersionComparator can only order X.Y.Z.N, so auto-update would misfire on it." >&2
    exit 1;;
esac

[ -f "$NOTES_FILE" ] || { echo "release notes not found: $NOTES_FILE" >&2; exit 1; }
[ -s "$NOTES_FILE" ] || { echo "release notes empty: $NOTES_FILE" >&2; exit 1; }

# spec: tests/gen_appcast.bats "each requires kind" -- each requires/<dep> is an item element in the mavergreen namespace,
#       which Sparkle ignores and the Engine reads.
REQUIRES="$(mg_list "products/$SHORT/requires" | while IFS= read -r d; do
  k="$(mg_value "products/$SHORT/requires/$d/kind")" || { echo "gen_appcast: products/$SHORT/requires/$d has no kind" >&2; exit 1; }
  if [ "$k" = external ]; then
    wh="$(mg_value "products/$SHORT/requires/$d/where")" || { echo "gen_appcast: products/$SHORT/requires/$d is external and has no where" >&2; exit 1; }
    printf '      <mavergreen:requires product="%s" kind="%s" where="%s"/>\n' "$d" "$k" "$(mg_xml_text "$wh" | sed 's/"/\&quot;/g')"
  else
    printf '      <mavergreen:requires product="%s" kind="%s"/>\n' "$d" "$k"
  fi
done)" || exit 1

# platform: Sparkle sorts appcast items by pubDate, which it expects as RFC-822, in UTC.
PUBDATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:mavergreen="https://github.com/Mavergreen/mavergreen/ns/feed/1">
  <channel>
    <title>$(mg_xml_text "$CHANNEL_TITLE")</title>
    <item>
      <title>$(mg_xml_text "$ITEM_TITLE")</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD_VER</sparkle:version>
      <sparkle:shortVersionString>$VER</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINOS</sparkle:minimumSystemVersion>
${REQUIRES:+$REQUIRES
}      <description><![CDATA[
<style>body{font-family:"Helvetica Neue",Helvetica,Arial,sans-serif;font-size:13px;}</style>
$(md_to_html "$NOTES_FILE")
]]></description>
      <enclosure url="$URL" type="application/octet-stream" $ENCLOSURE_ATTRS />
    </item>
  </channel>
</rss>
XML
