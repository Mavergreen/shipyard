#!/bin/sh
# platform: host-agnostic
#   usage: release-state.sh [--root DIR] [--ref REV] [--render]
#          Renders this product's declared state canonically, and hashes it. What is declared lives
#          in INGREDIENTS.md's "## Declared state" section; declared-state.sh is the parser and
#          documents the grammar. publish-release.yml records the digest; release-needed.sh looks it
#          up.
#          --render  print the canonical rendering instead of its digest (debugging, and the test)
#          --ref     take each declared entry's VALUE from REV's tree instead of the working tree
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "A release is a
#       declared state, not an event" -- a release realises a declared state, not the side effect of
#       an event; declared state EXCLUDES the source tree, which is what makes "a push causes
#       feedback and almost never a release" a property of the design.
# spec: SKILL.md "A release is a declared state, not an event" -- the rendering
#       is a WIRE FORMAT (hence the v1: prefix and the golden test: a format bump means recompute,
#       never republish) and ruling 16 (--ref recomputes a pre-migration release's digest from the
#       tag that actually released it, rather than guessing from a version match, which lost one).
# spec: tests/release-state-test.sh -- golden digest, byte-order sort, --ref rendering a tag's own
#       tree, and the upstream/version.sh coupling.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"

ROOT="."; RENDER=no; REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2%/}"; shift 2;;
    --ref) REF="$2"; shift 2;;
    --render) RENDER=yes; shift;;
    *) echo "release-state: unknown option $1" >&2; exit 2;;
  esac
done

if [ -n "$REF" ]; then
  git -C "$ROOT" rev-parse --verify "$REF^{commit}" >/dev/null 2>&1 || {
    echo "release-state: --ref '$REF' is not a revision of the repo at $ROOT" >&2
    echo "    (a shallow clone can hide one: release work needs fetch-depth: 0 and visible tags)" >&2
    exit 2
  }
fi

pin_value() {  # $1 = file  $2 = key
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1 | sed 's/^"//; s/"$//' | tr -d '[:space:]'
}

_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/release-state.XXXXXX")"; trap 'rm -rf "$work"' EXIT
decl="$work/decl"; lines="$work/lines"
: > "$lines"

if ! sh "$SELF/declared-state.sh" "$ROOT" > "$decl" 2>"$work/parse-err"; then
  cat "$work/parse-err" >&2
  echo "release-state: $ROOT/INGREDIENTS.md has a malformed \"## Declared state\" declaration" >&2
  exit 2
fi
[ -s "$decl" ] || {
  echo "release-state: $ROOT/INGREDIENTS.md declares no \"## Declared state\"" >&2
  echo "    add the section -- see scripts/declared-state.sh for the grammar:" >&2
  echo "        ## Declared state" >&2
  echo "        - upstream: UPSTREAM_VERSION" >&2
  echo "        - <name>: <path>[:<KEY>]" >&2
  exit 2
}

# platform: `git show REV:PATH` resolves PATH from the repo ROOT (no leading ./), which is what a
#           declared path already is.
entry_bytes() {   # $1 = declared path, relative to the repo root
  if [ -n "$REF" ]; then
    git -C "$ROOT" show "$REF:$1" > "$work/entry" 2>"$work/git-err" || return 1
  else
    [ -f "$ROOT/$1" ] || return 1
    cat "$ROOT/$1" > "$work/entry" || return 1
  fi
}

DERIVE_SCRIPT="build/derive-upstream-version.sh"

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "A release is a
#       declared state, not an event" -- a repo whose upstream is DERIVED (ca-certs' NSS_TAG,
#       ed25519's UPSTREAM_COMMIT) commits the pin, not version.sh's input, so 'upstream' and
#       version.sh's input may legitimately differ. That is safe only when one committed script
#       ties them together: the SAME text that reads the pin also names version.sh's input as
#       what it writes, so the digest and the version can never drift apart from two unrelated
#       edits. Read $DERIVE_SCRIPT with the same tree-reading mechanism entry_bytes uses, so
#       --ref judges the ref's own script, never the working tree's.
derive_script_names_both() {   # $1 = declared path (got)  $2 = version.sh's input (want)
  if [ -n "$REF" ]; then
    git -C "$ROOT" show "$REF:$DERIVE_SCRIPT" > "$work/derive" 2>/dev/null || return 1
  else
    git -C "$ROOT" ls-files --error-unmatch -- "$DERIVE_SCRIPT" >/dev/null 2>&1 || return 1
    cat "$ROOT/$DERIVE_SCRIPT" > "$work/derive" 2>/dev/null || return 1
  fi
  grep -qF -- "$1" "$work/derive" && grep -qF -- "$2" "$work/derive"
}

assert_upstream_is_version_sh_input() {   # $1 = the declared path
  want="${MAVERICKS_UPSTREAM_FILE:-UPSTREAM_VERSION}"
  case "$want" in "$ROOT"/*) want="${want#"$ROOT"/}" ;; esac
  want="${want#./}"
  got="${1#./}"
  [ "$got" != "$want" ] || return 0
  derive_script_names_both "$got" "$want" && return 0
  echo "release-state: the declared 'upstream' is not the file version.sh reads" >&2
  echo "    declared in INGREDIENTS.md: $got" >&2
  echo "    read by version.sh:         $want" >&2
  echo "    A digest tracking one file while the version is derived from another publishes N+1 of" >&2
  echo "    the PREVIOUS upstream carrying the NEW upstream's contents. Point them at one file, or" >&2
  echo "    export MAVERICKS_UPSTREAM_FILE here too (it is already needed for version.sh)." >&2
  echo "    A derived pin is allowed instead, but only when $DERIVE_SCRIPT is tracked and its own" >&2
  echo "    text names BOTH files above -- the same script that reads '$got' must write '$want', so" >&2
  echo "    the digest and the version can never come from two unrelated edits." >&2
  exit 2
}

while IFS="$(printf '\t')" read -r name spec || [ -n "$name" ]; do
  [ -n "$name" ] || continue
  case "$spec" in
    *:*) file="${spec%%:*}"; key="${spec##*:}" ;;
    *)   file="$spec"; key="" ;;
  esac
  [ "$name" != upstream ] || assert_upstream_is_version_sh_input "$spec"
  if ! entry_bytes "$file"; then
    if [ -n "$REF" ]; then
      echo "release-state: '$name' is declared from $file, which $REF's tree does not have" >&2
      [ ! -s "$work/git-err" ] || sed 's/^/    /' "$work/git-err" >&2
      echo "    a state that cannot be rendered from that revision must not become a digest for it" >&2
    else
      echo "release-state: '$name' is declared from $file, which does not exist under $ROOT" >&2
      echo "    an unrenderable state must not become a new digest, so this is fatal" >&2
    fi
    exit 2
  fi
  if [ -n "$key" ]; then
    value="$(pin_value "$work/entry" "$key")"
    [ -n "$value" ] || {
      echo "release-state: '$name' is declared as $key in $file, which assigns it nothing" >&2
      exit 2
    }
  else
    value="$(tr -d '[:space:]' < "$work/entry")"
    [ -n "$value" ] || { echo "release-state: '$name' is declared from $file, which is empty" >&2; exit 2; }
  fi
  printf '%s=%s\n' "$name" "$value" >> "$lines"
done < "$decl"

# platform: LC_ALL=C makes `sort` order by raw byte value on every box, forever -- glibc's own
#           locale collation (en_US.UTF-8) orders some names differently than that, while macOS's
#           BSD sort is byte order in every locale it has.
# spec: tests/release-state-test.sh -- this line IS the wire format: the digest is computed on
#       macOS at build time and on glibc in the nightly reconcile, so a byte-order regression here
#       is a two-host disagreement about whether a state was released.
rendered="$(LC_ALL=C sort < "$lines")"

if [ "$RENDER" = yes ]; then printf '%s\n' "$rendered"; exit 0; fi
printf 'v1:sha256:%s\n' "$(printf '%s\n' "$rendered" | shasum -a 256 | cut -d' ' -f1)"
