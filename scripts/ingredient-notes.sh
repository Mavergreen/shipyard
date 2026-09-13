#!/bin/sh
#   usage: ingredient-notes.sh <prev-tag> [pin-path[:KEY]...]
#          Describes which build-ingredient pins moved since the previous release, as a markdown
#          section for the release notes (Sparkle appcast <description> + GitHub Release body).
#          Prints NOTHING when no pin moved, when there is no previous release, or when no pins were
#          passed -- so callers can append its output unconditionally. Never fails a release: a
#          missing pin path is skipped with a warning, and call sites should still use `|| true`.
#          A "path:KEY" argument (ingredient-pins.sh's own-upstream-paths key form) excludes just
#          that KEY from the file's ingredient set -- the file's other keys are still reported
#          normally.
#          Shapes, because a pin is not always a bare version string:
#            single-line file      -> old -> new                  (components/<name>/version)
#            KEY=VALUE assignments -> one bullet per changed KEY   (versions.sh, pins.env: decided
#                                                                    by CONTENT, not extension --
#                                                                    see is_kv_pins())
#            anything else         -> "updated (N -> M bytes)"     (vendor/cacert.pem and other
#                                                                    blobs)
set -eu

prev="${1:-}"
[ -n "$prev" ] || exit 0
shift
[ "$#" -gt 0 ] || exit 0

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
bullets="$tmp/bullets"
: > "$bullets"
# spec: tests/ingredient-notes-test.sh "A pin that became DERIVED must not be announced as removed"
#       -- a key that only became derived (still assigned, no longer literal) is real information
#       but not evidence anything MOVED; collected separately and appended only once a real move
#       already earned the section.
derived="$tmp/derived"
: > "$derived"

pin_name() {
  case "$1" in
    components/*/version) p="${1#components/}"; printf '%s' "${p%/version}" ;;
    *.patch) printf '%s' "${1##*/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# spec: tests/ingredient-notes-test.sh "CRITICAL2" -- components/*/version pin files share one set
#       of key names (REPO/REF/DIGEST/BASE) across many components, unlike versions.sh/pins.env
#       (the repo's one and only pin file), so a bullet from this shape is ALWAYS prefixed with the
#       component name, not only when this run happens to be ambiguous.
label_prefix_for() {
  case "$1" in
    components/*/version) printf '%s / ' "$(pin_name "$1")" ;;
    *) printf '' ;;
  esac
}

patch_subject() {
  sed -n 's/^Subject:[[:space:]]*//p' | sed 's/^\[PATCH[^]]*\][[:space:]]*//' | head -1
}

# spec: tests/ingredient-notes-test.sh "shorten()" -- a 64-character hash diff tells a reader
#       nothing; 12 characters identifies which is which.
shorten() {
  v="$1"
  case "$v" in
    *[!0-9a-fA-F]*) printf '%s' "$v"; return ;;
  esac
  if [ "${#v}" -ge 32 ]; then printf '%.12s...' "$v"; else printf '%s' "$v"; fi
}

bullet() {  # name old new
  printf -- '- **%s**: %s -> %s\n' "$1" "$(shorten "$2")" "$(shorten "$3")" >> "$bullets"
}

# spec: tests/ingredient-notes-test.sh "G2"/"CRITICAL1" -- assignments() and assigned_keys() must
#       parse KEY=VALUE lines identically or they drift on what counts as an assignment; factored
#       out here once so they can't.
kv_raw() {
  sed -n 's/^[[:space:]]*export[[:space:]]\{1,\}//; s/^\([A-Z][A-Z0-9_]*\)=\(.*\)$/\1	\2/p' \
    | sed 's/[[:space:]]*#.*$//; s/["'"'"']//g; s/[[:space:]]*$//'
}

# spec: tests/ingredient-notes-test.sh "CRITICAL1" -- the value must hold at least one non-"="
#       character, or a base64 blob's padding lines ("MK9=") read as bogus one-key "assignments";
#       an uppercase-only key class narrows but does not close that class by itself. A pin's value
#       also carries no $ or backtick -- a derivation like GO_VERSION="$(upstream_version)" is a
#       code change, not a pin move.
assignments() {
  kv_raw | grep -v '[$`]' | awk -F'\t' '$2 ~ /[^=]/' || true
}

# spec: tests/ingredient-notes-test.sh -- assigned_keys() answers "is this key still assigned at
#       all" (literal or derived), sharing kv_raw()'s value-has-content guard with assignments() so
#       the two functions cannot drift on what counts as an assignment: swift-runtime's SWIFT_TAG
#       becoming derived ("swift-${SWIFT_VERSION}-RELEASE") once announced as a removal.
assigned_keys() {
  kv_raw | awk -F'\t' '$2 ~ /[^=]/ { print $1 }'
}

# spec: tests/ingredient-notes-test.sh -- a pin file gets per-key rendering by CONTENT (one real
#       KEY=VALUE line), never by extension or filename; a genuine blob (patch, vendored binary,
#       bare version string) has none and falls through to the byte-delta fallback. Defined directly
#       in terms of assignments() so the two can never drift.
is_kv_pins() {
  [ -n "$(assignments < "$1")" ]
}

for arg in "$@"; do
  case "$arg" in
    *:*) path="${arg%%:*}"; exclkey="${arg##*:}" ;;
    *) path="$arg"; exclkey="" ;;
  esac
  if [ ! -f "$path" ]; then
    echo "ingredient-notes: skipping missing pin $path" >&2
    continue
  fi
  newsize="$(wc -c < "$path" | tr -d ' ')"

  if ! oldsize="$(git cat-file -s "$prev:$path" 2>/dev/null)"; then
    case "$path" in
      *.patch)
        sub="$(patch_subject < "$path")"
        if [ -n "$sub" ]; then
          printf -- '- **%s**: added ("%s")\n' "$(pin_name "$path")" "$sub" >> "$bullets"
        else
          printf -- '- **%s**: added\n' "$(pin_name "$path")" >> "$bullets"
        fi
        ;;
      *)
        if is_kv_pins "$path"; then
          # spec: tests/ingredient-notes-test.sh "a first-time pins.env" -- exclkey (the repo's own
          #       upstream) is excluded even from a brand-new file; every OTHER key in it is still a
          #       real, reportable ingredient.
          label_prefix="$(label_prefix_for "$path")"
          assignments < "$path" | sort | while IFS= read -r line; do
            key="${line%%	*}"; newv="${line#*	}"
            [ "$key" = "$exclkey" ] && continue
            printf -- '- **%s%s**: added (%s)\n' "$label_prefix" "$key" "$newv" >> "$bullets"
          done
        elif [ "$newsize" -lt 256 ]; then
          printf -- '- **%s**: added (%s)\n' "$(pin_name "$path")" "$(head -1 "$path")" >> "$bullets"
        else
          printf -- '- **%s**: added\n' "$(pin_name "$path")" >> "$bullets"
        fi
        ;;
    esac
    continue
  fi

  [ "$(git rev-parse "$prev:$path")" = "$(git hash-object "$path")" ] && continue

  case "$path" in
    *.patch)
      # spec: tests/ingredient-notes-test.sh -- a patch is an ingredient too, but a byte delta says
      #       nothing about one; report what a reader can act on: what the patch claims to do, and
      #       how much moved.
      git show "$prev:$path" > "$tmp/oldpatch"
      oldsub="$(patch_subject < "$tmp/oldpatch")"
      newsub="$(patch_subject < "$path")"
      a="$(diff "$tmp/oldpatch" "$path" | grep -c '^>' || true)"
      d="$(diff "$tmp/oldpatch" "$path" | grep -c '^<' || true)"
      if [ -n "$oldsub" ] && [ -n "$newsub" ] && [ "$oldsub" != "$newsub" ]; then
        printf -- '- **%s**: "%s" -> "%s" (+%s/-%s lines)\n' \
          "$(pin_name "$path")" "$oldsub" "$newsub" "$a" "$d" >> "$bullets"
      elif [ -n "$newsub" ]; then
        printf -- '- **%s**: updated ("%s", +%s/-%s lines)\n' \
          "$(pin_name "$path")" "$newsub" "$a" "$d" >> "$bullets"
      else
        printf -- '- **%s**: updated (+%s/-%s lines)\n' "$(pin_name "$path")" "$a" "$d" >> "$bullets"
      fi
      ;;
    *)
      if is_kv_pins "$path"; then
        label_prefix="$(label_prefix_for "$path")"
        git show "$prev:$path" | assignments | sort > "$tmp/old"
        assignments < "$path" | sort > "$tmp/new"
        # spec: tests/ingredient-notes-test.sh -- a DIGEST that moved together with the REF in the
        #       same file says nothing the REF bullet did not (two spellings of one bump); a DIGEST
        #       moving ALONE is upstream re-tagging the SAME ref, which is exactly what a reader
        #       needs told, so only the moved-together case is suppressed.
        ref_moved=no
        oldref="$(grep '^REF	' "$tmp/old" | head -1 | cut -f2- || true)"
        newref="$(grep '^REF	' "$tmp/new" | head -1 | cut -f2- || true)"
        if [ -n "$oldref" ] && [ -n "$newref" ] && [ "$oldref" != "$newref" ]; then
          ref_moved=yes
        fi
        while IFS= read -r line; do
          key="${line%%	*}"; newv="${line#*	}"
          [ "$key" = "$exclkey" ] && continue
          [ "$key" = DIGEST ] && [ "$ref_moved" = yes ] && continue
          oldv="$(grep "^$key	" "$tmp/old" | head -1 | cut -f2- || true)"
          if [ -z "$oldv" ]; then
            printf -- '- **%s%s**: added (%s)\n' "$label_prefix" "$key" "$newv" >> "$bullets"
          elif [ "$oldv" != "$newv" ]; then
            bullet "${label_prefix}${key}" "$oldv" "$newv"
          fi
        done < "$tmp/new"
        # spec: tests/ingredient-notes-test.sh -- a key that stopped being pinned is a real change,
        #       and walking only the new file would omit it entirely; but it counts as removed only
        #       if the file stopped ASSIGNING it -- still assigned, just no longer a literal, is
        #       "derived now" ($derived above), a different and much smaller fact than removal.
        assigned_keys < "$path" | sort -u > "$tmp/newkeys"
        while IFS= read -r line; do
          key="${line%%	*}"; oldv="${line#*	}"
          [ "$key" = "$exclkey" ] && continue
          grep -q "^$key	" "$tmp/new" && continue     # still a literal: already handled above
          if grep -q "^$key\$" "$tmp/newkeys"; then
            printf -- '- **%s%s**: still used, now computed rather than pinned (was %s)\n' \
              "$label_prefix" "$key" "$(shorten "$oldv")" >> "$derived"
          else
            printf -- '- **%s%s**: removed\n' "$label_prefix" "$key" >> "$bullets"
          fi
        done < "$tmp/old"
      else
        oldlines="$(git show "$prev:$path" | wc -l | tr -d ' ')"
        newlines="$(wc -l < "$path" | tr -d ' ')"
        if [ "$newsize" -lt 256 ] && [ "$oldlines" -le 1 ] && [ "$newlines" -le 1 ]; then
          bullet "$(pin_name "$path")" "$(git show "$prev:$path" | head -1)" "$(head -1 "$path")"
        else
          printf -- '- **%s**: updated (%s -> %s bytes)\n' "$path" "$oldsize" "$newsize" >> "$bullets"
        fi
      fi
      ;;
  esac
done

if [ -s "$bullets" ]; then
  printf '### Build ingredients\n\nChanged since %s:\n\n' "$prev"
  cat "$bullets"
  cat "$derived"
fi
