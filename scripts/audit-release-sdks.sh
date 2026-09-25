#!/bin/sh
# platform: macOS-only -- artifact-facts.sh reads pkgs with pkgutil and Mach-O with lipo/otool
#   usage: audit-release-sdks.sh <owner/repo>...
#          audit-release-sdks.sh --dist DIR REPO_CHECKOUT
#          The family acceptance audit for "SDK pinning": downloads each repo's LATEST release (verified
#          against its SHA256SUMS; a release without one is audited anyway and said to be UNVERIFIED),
#          runs artifact-facts.sh over it and applies the sdk-pin rule alone,
#          honouring the deviations its INGREDIENTS.md declares. One verdict line per repo; exit 1 if any
#          repo has an unexcused violation. --dist audits an already-downloaded release against a local
#          checkout (the test uses it).
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/audit-sdks.XXXXXX")"; trap 'rm -rf "$w"' EXIT
audit_one() {  # $1 = label, $2 = dist dir, $3 = repo root holding INGREDIENTS.md (may lack one)
  # platform: only the macho, deviation and sentinel facts reach the checker, so the version it is told
  #           is never compared with anything; a fixed well-formed one keeps its scheme check quiet.
  # spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the filter
  #       below drops every `pkg` record, so a pkg pkgutil could not expand (artifact-facts.sh emits
  #       "pkg <file> unreadable none none" rather than aborting the stream) would otherwise leave the
  #       checker NOTHING to examine and pass this audit having looked at nothing. Captured ONCE to
  #       "$w/facts": the checker reads the filtered view of it, and this function separately reads the
  #       unfiltered file for the unreadable-pkg record the filter would hide.
  sh "$SELF/artifact-facts.sh" "$2" 0.0.0-mavericks.0 "$3" > "$w/facts" || true
  _unreadable="$(sed -n 's/^pkg \([^ ]*\) unreadable .*/\1/p' "$w/facts")"
  _n="$(grep -c '^macho ' "$w/facts" || true)"
  _ok=1
  if ! grep -E '^(expected|deviation|macho|abort|end-of-facts)( |$)' "$w/facts" \
       | sh "$SELF/check-artifact-conformance.sh" > "$w/out" 2>&1; then
    _ok=0
  fi
  if [ -n "$_unreadable" ]; then
    _ok=0
    { printf '%s\n' "$_unreadable" | while IFS= read -r _pf; do
        printf 'conformance: pkg-unreadable: %s could not be expanded by pkgutil -- nothing in it was checked\n' "$_pf"
      done
      cat "$w/out" 2>/dev/null
    } > "$w/out.combined"
    mv "$w/out.combined" "$w/out"
  fi
  if [ "$_ok" -eq 1 ]; then
    if [ "$_n" -eq 0 ]; then echo "audit: $1 COMPLIANT (no Mach-O shipped)"
    else echo "audit: $1 COMPLIANT ($_n Mach-O slices)"; fi
    return 0
  fi
  echo "audit: $1 NOT COMPLIANT"; sed 's/^/    /' "$w/out"; return 1
}
rc=0
if [ "${1:-}" = --dist ]; then
  [ "$#" -eq 3 ] || { echo "usage: audit-release-sdks.sh --dist DIR REPO_CHECKOUT" >&2; exit 2; }
  audit_one "$2" "$2" "$3" || rc=1
  exit "$rc"
fi
[ "$#" -gt 0 ] || { echo "usage: audit-release-sdks.sh <owner/repo>..." >&2; exit 2; }
for r in "$@"; do
  d="$w/${r##*/}"; mkdir -p "$d/dist" "$d/src"
  gh release download -R "$r" --dir "$d/dist" --pattern '*.pkg' --pattern '*.tar.gz' --pattern '*.tgz' \
      --pattern '*.tar.xz' --pattern '*.tar.bz2' --pattern SHA256SUMS \
    || { echo "audit: $r has no downloadable release"; rc=1; continue; }
  if [ -f "$d/dist/SHA256SUMS" ]; then
    ( cd "$d/dist" && grep -E '\.(pkg|tar\.gz|tgz|tar\.xz|tar\.bz2)$' SHA256SUMS | shasum -a 256 -c - >/dev/null ) \
      || { echo "audit: $r failed its SHA256SUMS"; rc=1; continue; }
  else
    echo "audit: $r has no SHA256SUMS -- audited UNVERIFIED"
  fi
  rm -f "$d/dist/SHA256SUMS"
  gh api "repos/$r/contents/INGREDIENTS.md" --jq .content 2>/dev/null | base64 -d > "$d/src/INGREDIENTS.md" 2>/dev/null || rm -f "$d/src/INGREDIENTS.md"
  audit_one "$r" "$d/dist" "$d/src" || rc=1
done
exit "$rc"
