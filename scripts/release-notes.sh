#!/bin/sh
# platform: host-agnostic
#   usage: release-notes.sh --tag T --version V --product P --out FILE [--line L] [--min-os M]
#                           [--short S]
#     --tag/--version   the release tag and full version (equal for most repos; golang's differ)
#     --product         the BARE product noun ("OpenSSH", "Go", "Signal Desktop"). This composes the
#                       family's prose register: "OpenSSH 9.9p2 (9.9p2-mavergreen.6)".
#     --line            upstream-line prefix for a repo shipping parallel lines (golang: "1.26";
#                       "1.26.*" also accepted -- both are normalized to a glob before use)
#     --min-os          emits the install floor line; omit for a product that is not a 10.9 .pkg
#     --short           this product's short name, in a repo whose .mavergreen/release-notes/<short>/
#                       nests its tree
#     Generates ONE product's release notes: the Sparkle appcast <description> and the GitHub
#     Release body, which are the same bytes by construction. Sections, in order: title, committed
#     prose (verbatim, never rewritten), Before you update (only with requires/ or rebuild), What
#     changed, Our patches (only when one changed), Build ingredients (only when a pin moved), footer.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Release notes" --
#       NOTES ARE PART OF THE RELEASE CONTRACT: every gap here is fatal and names its cause. The old
#       doctrine -- prose must never fail a release -- meant every section was appended with
#       `|| true` and 2>/dev/null, so a broken hook or an unfindable baseline produced a shorter body
#       and a green run: openssh never listed an ingredient in any release, and signal-desktop
#       shipped a new upstream with no link.
# spec: tests/release-notes-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"          # MAVERGREEN_REPO_ROOT
. "$SELF/deviation-reason.sh"

TAG=""; VER=""; PRODUCT=""; OUT=""; LINE=""; MINOS=""; SHORT=""; SHORT_SET=no
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2;;
    --version) VER="$2"; shift 2;;
    --product) PRODUCT="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --line) LINE="$2"; shift 2;;
    --min-os) MINOS="$2"; shift 2;;
    --short) SHORT="$2"; SHORT_SET=yes; shift 2;;
    *) echo "release-notes: unknown argument: $1" >&2; exit 2;;
  esac
done
die() { echo "release-notes: $1" >&2; exit 1; }
[ -n "$TAG" ] || die "--tag is required"
[ -n "$VER" ] || die "--version is required"
[ -n "$PRODUCT" ] || die "--product is required (the bare product noun, e.g. OpenSSH)"
[ -n "$OUT" ] || die "--out is required"

if [ -n "$LINE" ]; then
  case "$LINE" in
    *'*') ;;                      # already a glob
    *) LINE="$LINE.*" ;;
  esac
fi

if [ "$SHORT_SET" = yes ]; then
  case "$SHORT" in
    ''|-*|*[!a-z0-9-]*) die "--short '$SHORT' is not a short name ([a-z0-9][a-z0-9-]*)" ;;
  esac
  [ -d "$MAVERGREEN_REPO_ROOT/.mavergreen/products/$SHORT" ] \
    || die "--short '$SHORT' is not a product of this repo; declare it in .mavergreen/products/$SHORT/"
fi

cd "$MAVERGREEN_REPO_ROOT"

[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = false ] \
  || die "$MAVERGREEN_REPO_ROOT is a shallow clone, so release tags are unknown and the release kind cannot be decided (use fetch-depth: 0)"
git tag --list >/dev/null 2>&1 || die "cannot list release tags in $MAVERGREEN_REPO_ROOT"

UP="${VER%%-mavergreen.*}"
SELF_UPSTREAM=no
if [ "$UP" = "$VER" ]; then SELF_UPSTREAM=yes; fi

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Release notes"
#       -- --tag-glob 'v*.*.*' (never 'v[0-9]*') excludes the moving major tag (v1, no dot) before
#       it is ever compared. tests/release-notes-test.sh's "selfvglob" case is a mutation test for
#       this branch: deleting it left the suite green.
SELF_GLOB=""
if [ "$SELF_UPSTREAM" = yes ]; then
  case "$TAG" in
    v[0-9]*) SELF_GLOB='v*.*.*' ;;
    [0-9]*)  SELF_GLOB='[0-9]*' ;;
  esac
fi

# platform: `git clone --no-tags` (or actions/checkout fetch-tags: false) leaves `git tag --list`
#           succeeding with empty output, so the shallow guard above never fires for it.
# spec: tests/release-notes-test.sh "notags" -- a second, independent check for exactly that gap.
if [ "$SELF_UPSTREAM" = no ]; then
  UPTAGS="$(git tag --list "$UP-mavergreen.*" 2>/dev/null || true)"
  if [ -z "$UPTAGS" ]; then
    N="${VER##*-mavergreen.}"
    case "$N" in
      1) ;;
      *) die "$VER is -mavergreen.$N but no $UP-mavergreen.* tags are visible in $MAVERGREEN_REPO_ROOT, so it is unknown whether this is a first release or a repackage (tags may not be fetched -- use fetch-tags: true or fetch-depth: 0)" ;;
    esac
  fi
fi

# spec: tests/release-notes-test.sh "prevtagfails" -- an EMPTY result is legitimate (a genuine first
#       release has no baseline); a NON-ZERO exit from previous-release-tag.sh itself is not, and
#       must not be swallowed into the same "no baseline" reading.
if [ -n "$SELF_GLOB" ]; then
  PREV="$(sh "$SELF/previous-release-tag.sh" --tag-glob "$SELF_GLOB" "$TAG")" && prevrc=0 || prevrc=$?
else
  PREV="$(sh "$SELF/previous-release-tag.sh" "$TAG" ${LINE:+"$LINE"})" && prevrc=0 || prevrc=$?
fi
[ "$prevrc" -eq 0 ] \
  || die "previous-release-tag.sh failed (exit $prevrc) for $TAG; cannot decide the compare baseline or whether an ingredient moved without it"

# spec: tests/release-notes-test.sh "linefatal" -- an unmatched --line is indistinguishable from "no
#       earlier release" here, so a repackage would otherwise publish with no ingredient section and
#       no compare link, green. N=1 is left alone: a first release of a new line has no baseline.
if [ -n "$LINE" ] && [ -z "$PREV" ] && [ "$SELF_UPSTREAM" = no ]; then
  case "${VER##*-mavergreen.}" in
    1) ;;
    *) die "--line matches no ${LINE}-mavergreen.* tag, so $VER (a repackage) would ship with no compare link and no ingredient section; pass the prefix the tags actually carry (1.26, not 126)" ;;
  esac
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/release-notes.XXXXXX")"
footer_tmp="$(mktemp "${TMPDIR:-/tmp}/release-notes-footer.XXXXXX")"
watched_tmp="$(mktemp "${TMPDIR:-/tmp}/release-notes-watched.XXXXXX")"
trap 'rm -f "$tmp" "$footer_tmp" "$watched_tmp"' EXIT

if [ "$SELF_UPSTREAM" = yes ]; then
  printf '## %s %s\n' "$PRODUCT" "$VER" > "$tmp"
else
  printf '## %s %s (%s)\n' "$PRODUCT" "$UP" "$VER" > "$tmp"
fi

# spec: SKILL.md "Release notes" -- a tag that names a commit other than HEAD is already minted; its
#       committed prose publishes as is.
minted() {
  _t="$(git -C "$MAVERGREEN_REPO_ROOT" rev-parse -q --verify "refs/tags/$TAG^{commit}")" || return 1
  [ "$_t" != "$(git -C "$MAVERGREEN_REPO_ROOT" rev-parse HEAD)" ]
}

# spec: SKILL.md "Release notes" -- committed .md prose publishes only for a minted tag; a new
#       release writes .mavergreen/release-notes/<TAG>/ instead (both under <short>/ there when
#       --short names a nested tree). Any mark line is stripped, never shown to readers.
readable_dir() {
  { [ -r "$1" ] && [ -x "$1" ]; } || die "$1 cannot be read; fix its permissions"
}
ROOT="$MAVERGREEN_REPO_ROOT/.mavergreen/release-notes"
if [ -d "$ROOT" ]; then
  readable_dir "$ROOT"
  if [ -n "$SHORT" ] && [ -d "$ROOT/$SHORT" ]; then ROOT="$ROOT/$SHORT"; readable_dir "$ROOT"; fi
fi
DIR="$ROOT/$TAG"
MARK='<!-- edited by a human -->'
notes="$ROOT/${TAG}.md"
if [ -f "$notes" ] && [ -s "$notes" ]; then
  minted || die "$notes is prose for a release not yet published. Write $DIR/changes/<slug> files instead; see SKILL.md \"Release notes\"."
  awk -v m="$MARK" '{ l = $0; sub(/\r$/, "", l); sub(/[ \t]+$/, "", l); if (l != m) print }' "$notes" > "$tmp.prose" \
    || die "could not read $notes"
  if [ -s "$tmp.prose" ]; then
    printf '\n' >> "$tmp"; cat "$tmp.prose" >> "$tmp"
  fi
  rm -f "$tmp.prose"
fi

# spec: SKILL.md "Release notes" -- .mavergreen/release-notes/<TAG>/ holds changes/<slug> and
#       rebuild; a repo tagging products separately nests them under .mavergreen/release-notes/<short>/.
#       Anything else there fails, naming it. A minted tag skips only the sentence check, so a later
#       rule never reddens its regeneration. The requirements and the standing notice are the
#       product's: .mavergreen/products/<short>/requires/<dep>/min and .mavergreen/products/<short>/notice.
MINTED=no; if minted; then MINTED=yes; fi
# spec: SKILL.md "Release notes" -- a directory named for any other tag would be silently dropped, so
#       a new release refuses one that is not an existing tag or a product's nest. A minted tag's
#       regeneration leaves alone notes staged for the release after it.
if [ "$MINTED" = no ]; then
  for e in "$ROOT"/*; do
    b="${e##*/}"
    if [ -f "$e" ] || [ -L "$e" ]; then
      case "$b" in
        *.md) continue ;;
        *) die "$e is not a release-notes entry; a standing footer line is .mavergreen/products/<short>/notice (see SKILL.md \"Release notes\")" ;;
      esac
    fi
    [ -d "$e" ] || continue
    [ "$b" = "$TAG" ] && continue
    [ "$b" = "$SHORT" ] && continue
    git rev-parse -q --verify "refs/tags/$b^{commit}" >/dev/null && continue
    [ -d "$MAVERGREEN_REPO_ROOT/.mavergreen/products/$b" ] && continue
    die "$e is release notes for $b, which is not an existing tag; this release is $TAG, so rename it $DIR (see SKILL.md \"Release notes\")"
  done
fi
ALLOW=""; if [ "$PRODUCT" = Shipyard ]; then ALLOW="--allow shipyard"; fi
line1() {
  awk 'NR == 1 { gsub(/\r/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; exit }' "$1" \
    || die "could not read $1"
}
sentence() {
  { [ -f "$1" ] && [ -r "$1" ]; } || die "cannot read $1"
  [ "$MINTED" = yes ] && return 0
  # shellcheck disable=SC2086  # ALLOW is empty or one flag and its word
  sh "$SELF/check-release-sentence.sh" $ALLOW "$1" \
    || die "$1 is not one release-note sentence (see the complaint above); see SKILL.md \"Release notes\""
}
if [ -d "$DIR" ]; then
  readable_dir "$DIR"
  for e in "$DIR"/* "$DIR"/.*; do
    case "${e##*/}" in .|..) continue ;; esac
    { [ -e "$e" ] || [ -L "$e" ]; } || continue
    case "${e##*/}" in
      changes) { [ -d "$e" ] && [ ! -L "$e" ]; } || die "$e must be a directory" ;;
      rebuild) sentence "$e" ;;
      *) die "$e is not a release-notes entry (only changes/ and rebuild are; a requirement is .mavergreen/products/<short>/requires/<dep>/min); see SKILL.md \"Release notes\"" ;;
    esac
  done
  if [ -d "$DIR/changes" ]; then
    readable_dir "$DIR/changes"
    n=0
    for e in "$DIR/changes"/* "$DIR/changes"/.*; do
      b="${e##*/}"
      case "$b" in .|..) continue ;; esac
      { [ -e "$e" ] || [ -L "$e" ]; } || continue
      n=$((n + 1))
      [ -f "$e" ] || die "$e must be a file"
      case "$b" in *[!a-z0-9-]*) die "$e: a change's name is [a-z0-9-]+ (the names order the bullets)" ;; esac
      sentence "$e"
    done
    [ "$n" -gt 0 ] || die "$DIR/changes is empty; remove it or add an entry"
  fi
fi

# spec: SKILL.md "Release notes" -- the product is --short's, else the one whose short name is the
#       noun lowercased, else the repo's only product. A requirement is listed when its min differs
#       from the previous release's; a previous release from before .mavergreen/ lists none.
PSHORT="$SHORT"
if [ -z "$PSHORT" ]; then
  _p="$(printf '%s' "$PRODUCT" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ ' 'abcdefghijklmnopqrstuvwxyz-')"
  _all="$(mg_list products)"
  if [ -d ".mavergreen/products/$_p" ]; then PSHORT="$_p"
  elif [ -n "$_all" ] && [ "$(printf '%s\n' "$_all" | wc -l | tr -d ' ')" -eq 1 ]; then PSHORT="$_all"
  fi
fi
PD=".mavergreen/products/$PSHORT"
REQS=""
if [ -n "$PSHORT" ] && [ -n "$PREV" ] && git cat-file -e "$PREV:.mavergreen" 2>/dev/null; then
  for dep in $(mg_list "products/$PSHORT/requires"); do
    f="$MAVERGREEN_REPO_ROOT/$PD/requires/$dep/min"
    { [ -e "$f" ] || [ -L "$f" ]; } || continue
    { [ -f "$f" ] && [ -r "$f" ]; } || die "cannot read $f"
    v="$(mg_value "products/$PSHORT/requires/$dep/min")" || die "cannot read $f"
    case "$v" in
      [0-9]*[!0-9A-Za-z.+-]*|[!0-9]*|'') die "$f: line 1 must be a minimum version ([0-9][0-9A-Za-z.+-]*), not '$v'" ;;
    esac
    old="$(git show "$PREV:$PD/requires/$dep/min" 2>/dev/null | awk 'NR == 1 { gsub(/\r/, ""); print; exit }')" || old=""
    [ "$v" = "$old" ] || REQS="$REQS- Install $dep $v or later first.
"
  done
fi
if [ -n "$REQS" ] || [ -f "$DIR/rebuild" ]; then
  printf '\n### Before you update\n' >> "$tmp"
  printf '%s' "$REQS" >> "$tmp"
  if [ -f "$DIR/rebuild" ]; then
    v="$(line1 "$DIR/rebuild")"
    printf -- '- %s\n' "$v" >> "$tmp"
  fi
fi
NOTICE=""
if [ -n "$PSHORT" ] && { [ -e "$MAVERGREEN_REPO_ROOT/$PD/notice" ] || [ -L "$MAVERGREEN_REPO_ROOT/$PD/notice" ]; }; then
  sentence "$MAVERGREEN_REPO_ROOT/$PD/notice"
  NOTICE="$(line1 "$MAVERGREEN_REPO_ROOT/$PD/notice")"
fi
HAS_CHANGES=""; if [ -d "$DIR/changes" ]; then HAS_CHANGES=yes; fi

printf '\n### What changed\n' >> "$tmp"
if [ -n "$HAS_CHANGES" ]; then
  for b in $(LC_ALL=C ls "$DIR/changes"); do
    v="$(line1 "$DIR/changes/$b")"
    printf -- '- %s\n' "$v" >> "$tmp"
  done
fi

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Consuming a
#       Mavergreen toolchain + auto-propagation" -- "Name that caller
#       .github/workflows/repackage-on-ingredient-bump.yml": the conventional path wins outright: a
#       repo naming the caller something else falls through to DISCOVERY (naming the reusable
#       workflow on a non-comment line -- not a `uses:.*<filename>` regex, which a folded `uses: >-`
#       scalar defeats), and discovery finding more than one candidate stops the release rather than
#       guessing. tests/release-notes-test.sh's badcaller/nopins/unwired/decoytrap/foldedcaller/
#       commentonly/twocallers cases are this rule's regression suite.
CALLER=""
default_caller="$MAVERGREEN_REPO_ROOT/.github/workflows/repackage-on-ingredient-bump.yml"
is_caller() {
  grep -v '^[[:space:]]*#' "$1" 2>/dev/null | grep -Fq 'repackage-on-ingredient-bump.yml'
}
if [ -f "$default_caller" ] && is_caller "$default_caller"; then
  CALLER="$default_caller"
else
  ncand=0; candidates=""
  for f in "$MAVERGREEN_REPO_ROOT"/.github/workflows/*.yml "$MAVERGREEN_REPO_ROOT"/.github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    is_caller "$f" || continue
    ncand=$((ncand + 1)); CALLER="$f"
    candidates="${candidates:+$candidates, }$f"
  done
  [ "$ncand" -le 1 ] \
    || die "more than one workflow names repackage-on-ingredient-bump.yml and none of them is at the conventional path .github/workflows/repackage-on-ingredient-bump.yml, so which one defines this repo's ingredient pins is ambiguous: $candidates (rename the real caller to the conventional path, or drop the mention from the other)"
fi
if [ -n "$CALLER" ]; then
  [ -n "$(sh "$SELF/ingredient-pins.sh")" ] \
    || die "$CALLER calls repackage-on-ingredient-bump.yml but .mavergreen/ingredients/ holds no ingredient"
fi
# spec: tests/release-notes-test.sh "r3new"/"r1d" -- this repo's owner/repo names its own compare
#       view; with no repo to learn, a link is left out rather than guessed.
SLUG="$(mg_repo)" || SLUG=""

INGREDIENTS=""
WATCHED=""
if [ -n "$PREV" ]; then
  INGREDIENTS="$(sh "$SELF/ingredient-notes.sh" --watched "$watched_tmp" "$PREV")" \
    || die "cannot read the ingredient pins that moved since $PREV; a repackage that cannot say what moved must not ship"
  case "$INGREDIENTS" in
    ''|'### '*) ;;
    *) INGREDIENTS="$(printf '### Build ingredients\n\n%s' "$INGREDIENTS")" ;;
  esac
  WATCHED="$(LC_ALL=C sort -u "$watched_tmp")"
fi

# spec: tests/release-notes-test.sh "patchadd" -- tailscale's seventh 1.102.4 release added
#       patches/darwin-exit-nodes.patch (exit nodes on macOS) and its notes still said "packaging
#       changes only": a change to OUR modifications of the upstream source is a behaviour change a
#       reader is owed. Watched files are excluded because ingredient-notes.sh already reports them. A
#       self-upstream product has no upstream to modify, so nothing here applies to it.
PATCHES=""
if [ -n "$PREV" ] && [ "$SELF_UPSTREAM" = no ]; then
  # shellcheck disable=SC2086  # WATCHED is a deliberate list of paths
  PATCHES="$(sh "$SELF/patch-notes.sh" "$PREV" $WATCHED)" \
    || die "cannot read which of our patches changed since $PREV; a release that cannot say whether it changed our patches must not ship"
fi

# spec: tests/release-notes-test.sh "r3*" -- a self-upstream release says why it was cut, as a
#       port's does: an ingredient-only YYYYMMDD.N repackage that read "Release of <product>" looked
#       like new code. The compare names the tags, since shipyard's v1.0.209 is version 1.0.209.
if [ "$SELF_UPSTREAM" = yes ]; then
  date_of() {
    case "$1" in
      [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].*[0-9]) printf '%s' "${1%%.*}" ;;
    esac
  }
  if [ -z "$PREV" ] && [ -z "$(git tag --list)" ]; then
    # spec: tests/release-notes-test.sh "m4" -- "First release" is a claim; a checkout that only
    #       lacks its tags must not make it. N > 1 on a date says earlier releases exist, and in CI
    #       the repo's own releases say so for any scheme.
    unfetched="cannot see this repo's earlier release tags, so \"First release\" may be false (fetch tags: fetch-depth: 0)"
    case "$VER" in
      [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].1) ;;
      [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].*[0-9]) die "$VER is not its date's first release, but this $unfetched" ;;
    esac
    if [ "${GITHUB_ACTIONS:-}" = true ] && [ -n "$SLUG" ]; then
      # spec: tests/release-notes-test.sh "m4" -- a gh that cannot list (no GH_TOKEN on the step)
      #       proves nothing either way, so it warns and trusts the checkout.
      if released="$(gh release list --repo "$SLUG" --limit 1 --json tagName --jq '.[0].tagName // empty' 2>/dev/null)"; then
        [ -z "$released" ] || die "$SLUG has released $released, but this $unfetched"
      else
        echo "release-notes: warning: gh cannot list $SLUG's releases (is GH_TOKEN set on this step?), so a first release is taken on the checkout's word" >&2
      fi
    fi
  fi
  if [ -z "$PREV" ]; then
    printf -- '- First release of %s %s.\n' "$PRODUCT" "$VER" >> "$tmp"
  elif [ -n "$(date_of "$VER")" ] && [ "$(date_of "$VER")" = "$(date_of "$PREV")" ] \
       && { [ -n "$INGREDIENTS" ] || [ -z "$HAS_CHANGES" ]; }; then
    if [ -n "$INGREDIENTS" ]; then
      if [ -n "$HAS_CHANGES" ]; then
        printf -- '- Rebuilt because build ingredients moved (below).\n' >> "$tmp"
      else
        printf -- '- Rebuilt because build ingredients moved (below); no change to %s itself.\n' "$PRODUCT" >> "$tmp"
      fi
    else
      printf -- '- Repackage of %s %s; packaging changes only.\n' "$PRODUCT" "$(date_of "$VER")" >> "$tmp"
    fi
  else
    prevver="$PREV"
    [ "$TAG" != "v$VER" ] || prevver="${PREV#v}"
    printf -- '- New release of %s %s (was %s).\n' "$PRODUCT" "$VER" "$prevver" >> "$tmp"
    [ -z "$SLUG" ] \
      || printf -- '  [Changes since %s](https://github.com/%s/compare/%s...%s)\n' "$PREV" "$SLUG" "$PREV" "$TAG" >> "$tmp"
  fi
else
  set +e
  URL="$(sh "$SELF/upstream-notes.sh" --url-only "$VER")"; urc=$?
  set -e
  case "$urc" in
    0)
      if [ -n "$PREV" ]; then
        printf -- '- New upstream: %s %s (was %s).\n' "$PRODUCT" "$UP" "${PREV%%-mavergreen.*}" >> "$tmp"
      else
        printf -- '- First release of %s %s.\n' "$PRODUCT" "$UP" >> "$tmp"
      fi
      printf -- '  [Upstream release notes for %s](%s)\n' "$UP" "$URL" >> "$tmp"
      ;;
    3)  # a repackage: no upstream change
      if [ -n "$INGREDIENTS" ] && [ -n "$PATCHES" ]; then
        printf -- '- Repackage of upstream %s %s, rebuilt because build ingredients moved and our patches changed (below).\n  No upstream change.\n' \
          "$PRODUCT" "$UP" >> "$tmp"
      elif [ -n "$INGREDIENTS" ]; then
        printf -- '- Repackage of upstream %s %s, rebuilt because build ingredients moved (below).\n  No upstream change.\n' \
          "$PRODUCT" "$UP" >> "$tmp"
      elif [ -n "$PATCHES" ]; then
        printf -- '- Repackage of upstream %s %s with changes to our patches (below).\n  No upstream change.\n' \
          "$PRODUCT" "$UP" >> "$tmp"
      elif [ -n "$HAS_CHANGES" ]; then
        printf -- '- Built on upstream %s %s (no upstream change).\n' "$PRODUCT" "$UP" >> "$tmp"
      else
        printf -- '- Repackage of upstream %s %s; packaging changes only.\n' "$PRODUCT" "$UP" >> "$tmp"
      fi
      ;;
    4)  # no hook -- allowed ONLY where the repo declares why
      shipyard_deviations "$MAVERGREEN_REPO_ROOT" >/dev/null 2>&1 || :
      shipyard_deviated upstream-notes >/dev/null \
        || die "$VER ships a new upstream but this repo has no .mavergreen/hooks/upstream-release-notes-url, and no .mavergreen/deviations/upstream-notes/ says why (add the hook, or that deviation)"
      printf -- '- New upstream: %s %s.\n' "$PRODUCT" "$UP" >> "$tmp"
      ;;
    *)  # a hook that failed, or printed something that is not one URL
      die "$VER ships a new upstream but .mavergreen/hooks/upstream-release-notes-url did not print exactly one URL for $UP (run it by hand to see why)"
      ;;
  esac
fi

[ -z "$PATCHES" ] || printf '\n%s\n' "$PATCHES" >> "$tmp"
[ -z "$INGREDIENTS" ] || printf '\n%s\n' "$INGREDIENTS" >> "$tmp"

# spec: tests/release-notes-test.sh "nofooter"/"withfooter" -- the footer's '---' rule is buffered
#       separately and emitted only when at least one footer line follows it; swift-toolchain has
#       neither a --min-os floor nor (in a fixture with no remote) a compare link.
[ -z "$NOTICE" ] || printf '%s\n' "$NOTICE" >> "$footer_tmp"
if [ -n "$MINOS" ]; then
  if [ -s "$footer_tmp" ]; then printf '\n' >> "$footer_tmp"; fi
  printf 'Requires Mac OS X %s or later.\n' "$MINOS" >> "$footer_tmp"
fi

if [ -n "$PREV" ]; then
  if [ -n "${GITHUB_SERVER_URL:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
    REPO_URL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY"
  else
    origin="$(git config --get remote.origin.url 2>/dev/null || true)"
    case "$origin" in
      git@github.com:*) REPO_URL="https://github.com/$(printf '%s' "${origin#git@github.com:}" | sed 's/\.git$//')" ;;
      https://github.com/*) REPO_URL="$(printf '%s' "$origin" | sed 's/\.git$//')" ;;
      *) REPO_URL="" ;;
    esac
  fi
  if [ -n "$REPO_URL" ]; then
    # spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Release
    #       notes" -- "Every footer line gets a blank line BEFORE it, never after the line it
    #       follows": the rule binds anything appended after this generator hands the file off too
    #       (the release-doctrine session's `Mavergreen-State:` marker is the live case), which
    #       is why it is written down here even though this file cannot enforce that append itself.
    # platform: `[ -s "$f" ] && cmd`, as the LAST command of a script or function, returns non-zero
    #           under `set -e` and aborts the caller when the test is false.
    if [ -s "$footer_tmp" ]; then
      printf '\n' >> "$footer_tmp"
    fi
    printf '[All changes since %s](%s/compare/%s...%s)\n' "$PREV" "$REPO_URL" "$PREV" "$TAG" >> "$footer_tmp"
  fi
fi

if [ -s "$footer_tmp" ]; then
  printf '\n---\n' >> "$tmp"
  cat "$footer_tmp" >> "$tmp"
fi

if ! shape="$(sh "$SELF/check-release-notes.sh" "$tmp" "$VER" 2>&1 >/dev/null)"; then
  printf '%s\n' "$shape" >&2
  if [ -f "$notes" ] && [ -s "$notes" ]; then
    die "the generated body failed the family shape check (see the complaint above); likely cause: the committed prose at $notes"
  else
    die "the generated body failed the family shape check (see the complaint above); this is a bug in release-notes.sh"
  fi
fi

mkdir -p "$(dirname "$OUT")"
cat "$tmp" > "$OUT"
echo "release-notes: wrote $OUT for $VER"
