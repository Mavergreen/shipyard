#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "Release notes" -- before this generator, notes were best-effort prose: every
#       generated section was appended with `|| true` and 2>/dev/null, so a broken hook, an
#       unfindable baseline or a shallow clone all produced a SHORTER body and a green run.
#       openssh never listed an ingredient; signal-desktop shipped a new upstream with no link;
#       swift-runtime's repackage failed at signing instead, for want of a committed file. This
#       generator is one shape for every product, and a fatal error for every gap it cannot fill.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/deviation_tree.sh"
S="$here/../scripts/release-notes.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/release-notes.XXXXXX")"; trap 'rm -rf "$work"' EXIT

mkrepo() {  # a product repo fixture: a git repo with a hook, an ingredient, and a repackage caller. $1 = dir
  mkdir -p "$1/.mavergreen/hooks" "$1/.mavergreen/ingredients/libressl" "$1/.github/workflows" "$1/.mavergreen/release-notes"
  ( cd "$1" && git init -q -b main . && git config user.email t@example.com && git config user.name tester )
  printf '3.8.2\n%s\n' "$L2" > "$1/.mavergreen/ingredients/libressl/VERSION"
  printf 'LibreSSL\n' > "$1/.mavergreen/ingredients/libressl/description"
  printf 'linked\n' > "$1/.mavergreen/ingredients/libressl/role"
  printf 'the TLS library\n' > "$1/.mavergreen/ingredients/libressl/why"
  cat > "$1/.github/workflows/repackage-on-ingredient-bump.yml" <<'YML'
on:
  push:
    branches: [main]
    paths:
      - .mavergreen/ingredients/libressl/VERSION
jobs:
  repackage:
    uses: Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
YML
  printf '#!/bin/sh\nprintf "https://example.com/notes/%%s\\n" "$1"\n' > "$1/.mavergreen/hooks/upstream-release-notes-url"
  ( cd "$1" && git add -A && git commit -qm base )
}
decl() { mkdir -p "$1/.mavergreen/products/$2"; printf '%s\n' "$2" > "$1/.mavergreen/products/$2/noun"; }
L2='# renovate: datasource=github-releases depName=libressl/portable extractVersion=^v(?<version>.+)$'
bump() {
  printf '%s\n%s\n' "$2" "$L2" > "$1/.mavergreen/ingredients/libressl/VERSION"
}

gen() {  # $1 = repo, $2 = tag/version, rest = extra args
  r="$1"; v="$2"; shift 2
  ( cd "$r" && MAVERGREEN_REPO_ROOT="$r" \
      GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=Mavergreen/mavericks-openssh \
      sh "$S" --tag "$v" --version "$v" \
      --product OpenSSH --min-os 10.9.5 --out "$r/OUT.md" "$@" )
}

# spec: scripts/release-notes.sh -- a new upstream must name the upstream, link its notes, and
#       say what it replaced.
r="$work/new"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 )
gen "$r" 9.9p2-mavergreen.1 >/dev/null
grep -q '^## OpenSSH 9.9p2 (9.9p2-mavergreen.1)$' "$r/OUT.md" \
  || { echo "FAIL new: title"; cat "$r/OUT.md"; exit 1; }
grep -q 'First release of OpenSSH 9.9p2' "$r/OUT.md" || { echo "FAIL new: first-release wording"; exit 1; }
grep -q 'https://example.com/notes/9.9p2' "$r/OUT.md" || { echo "FAIL new: upstream link"; exit 1; }
grep -q 'Requires Mac OS X 10.9.5 or later' "$r/OUT.md" || { echo "FAIL new: floor"; exit 1; }
sh "$here/../scripts/check-release-notes.sh" "$r/OUT.md" 9.9p2-mavergreen.1 >/dev/null \
  || { echo "FAIL new: own output fails the shape check"; exit 1; }

r="$work/restart"; mkrepo "$r"
( cd "$r" && git tag 1.2.3-mavericks.4 )
( cd "$r" && MAVERGREEN_REPO_ROOT="$r" GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=Mavergreen/foo \
    sh "$S" --tag 1.2.3-mavergreen.1 --version 1.2.3-mavergreen.1 --product Foo --min-os 10.9.5 --out "$r/OUT.md" ) >/dev/null \
  || { echo "FAIL restart: the first -mavergreen release beside a -mavericks tag must generate"; exit 1; }
grep -qx -- '- First release of Foo 1.2.3.' "$r/OUT.md" \
  || { echo "FAIL restart: the first -mavergreen.1 is a first release, never a repackage of 1.2.3-mavericks.4"; cat "$r/OUT.md"; exit 1; }
if grep -q 'compare/' "$r/OUT.md"; then
  echo "FAIL restart: no -mavergreen release precedes it, so there is no compare link"; cat "$r/OUT.md"; exit 1
fi

# spec: scripts/release-notes.sh -- an ingredient repackage must name the pin that moved, and
#       the baseline it moved from.
r="$work/ing"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 )
bump "$r" 3.9.2
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null
grep -q 'rebuilt because build ingredients moved' "$r/OUT.md" || { echo "FAIL ing: kind"; cat "$r/OUT.md"; exit 1; }
grep -q '3.8.2 -> 3.9.2' "$r/OUT.md" || { echo "FAIL ing: pin diff (the openssh pN bug)"; cat "$r/OUT.md"; exit 1; }
grep -qx -- '- \*\*libressl / VERSION\*\*: 3.8.2 -> 3.9.2 (\[release notes\](https://github.com/libressl/portable/releases/tag/v3.9.2))' "$r/OUT.md" \
  || { echo "FAIL ing: the moved pin must link its change notes"; cat "$r/OUT.md"; exit 1; }
grep -qx -- '  LibreSSL' "$r/OUT.md" || { echo "FAIL ing: the description sits beside the bullet"; cat "$r/OUT.md"; exit 1; }

r="$work/bare"; mkrepo "$r"
printf '3.8.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
printf 'a fixture with no notes\n' > "$r/.mavergreen/ingredients/libressl/untracked"
( cd "$r" && git add -A && git commit -qm "untracked" && git tag 9.9p2-mavergreen.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null || { echo "FAIL bare: an untracked ingredient with no REPO ships without a link"; exit 1; }
grep -qx -- '- \*\*libressl / VERSION\*\*: 3.8.2 -> 3.9.2' "$r/OUT.md" \
  || { echo "FAIL bare: the bullet has no link"; cat "$r/OUT.md"; exit 1; }
grep -q '9.9p2-mavergreen.1\.\{0,\}9.9p2-mavergreen.2' "$r/OUT.md" \
  || grep -q 'compare/9.9p2-mavergreen.1' "$r/OUT.md" || { echo "FAIL ing: compare link"; exit 1; }
grep -q 'Upstream release notes' "$r/OUT.md" && { echo "FAIL ing: a repackage must not claim a new upstream"; exit 1; }

# spec: scripts/release-notes.sh -- a packaging-only release has no upstream change and no pin
#       moved.
r="$work/pkgonly"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 && echo x >> .mavergreen/hooks/upstream-release-notes-url \
    && git commit -qam "ci: unrelated" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null
grep -q 'packaging changes only' "$r/OUT.md" || { echo "FAIL pkgonly: kind"; cat "$r/OUT.md"; exit 1; }
grep -q '### Build ingredients' "$r/OUT.md" && { echo "FAIL pkgonly: no pin moved, no section"; exit 1; }

r="$work/prose-short"; mkrepo "$r"
mkdir -p "$r/.mavergreen/release-notes/openssh" "$r/.mavergreen/release-notes"
printf 'Per-product prose.\n' > "$r/.mavergreen/release-notes/openssh/9.9p2-mavergreen.1.md"
printf 'Repo-wide prose.\n' > "$r/.mavergreen/release-notes/9.9p2-mavergreen.1.md"
printf 'Legacy prose.\n' > "$r/.mavergreen/release-notes/9.9p2-mavergreen.1.md"; decl "$r" openssh
( cd "$r" && git add -A && git commit -qm notes && git tag 9.9p2-mavergreen.1 && git commit -q --allow-empty -m later )
gen "$r" 9.9p2-mavergreen.1 --short openssh >/dev/null
grep -q '^Per-product prose\.$' "$r/OUT.md" || { echo "FAIL prose-short: a product tagged separately reads release-notes/<short>/"; cat "$r/OUT.md"; exit 1; }
grep -q 'Repo-wide prose' "$r/OUT.md" && { echo "FAIL prose-short: only the product's own prose"; cat "$r/OUT.md"; exit 1; }
grep -q 'Legacy prose' "$r/OUT.md" && { echo "FAIL prose-short: a top-level release-notes/ is not read"; cat "$r/OUT.md"; exit 1; }

r="$work/landing"; mkrepo "$r"
( cd "$r" && git rm -rq .mavergreen && git commit -qm legacy && git tag 9.9p2-mavergreen.1 \
    && git checkout -q HEAD~1 -- .mavergreen && git commit -qm "the flag day" )
bump "$r" 3.9.2
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null || { echo "FAIL landing: the first release after the move ships"; exit 1; }
want="$(printf '%s\n' '### Build ingredients' '' '- Ingredients moved to .mavergreen/; no per-pin changes listed for this release.')"
[ "$(awk '/^### Build ingredients$/{n=3} n>0{print;n--}' "$r/OUT.md")" = "$want" ] \
  || { echo "FAIL landing: one line under its heading"; cat "$r/OUT.md"; exit 1; }

r="$work/landing-watch"; mkrepo "$r"
mkdir -p "$r/patches"; printf 'Subject: [PATCH] one\n' > "$r/patches/x.patch"
printf 'patches/*.patch\n' > "$r/.mavergreen/ingredients/libressl/watch"
( cd "$r" && git add -A && git commit -qm watch && git rm -rq .mavergreen && git commit -qm legacy \
    && git tag 9.9p2-mavergreen.1 && git checkout -q HEAD~1 -- .mavergreen && git commit -qm "the flag day" )
printf 'Subject: [PATCH] one\n+x\n' > "$r/patches/x.patch"
( cd "$r" && git commit -qam "change the patch" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null || { echo "FAIL landing-watch: ships"; exit 1; }
grep -qx -- '- Changed `patches/x.patch`' "$r/OUT.md" \
  || { echo "FAIL landing-watch: a watched patch no ingredient bullet reports is one of our patches"; cat "$r/OUT.md"; exit 1; }

r="$work/added-watch"; mkrepo "$r"
mkdir -p "$r/patches"; printf 'Subject: [PATCH] one\n' > "$r/patches/x.patch"
( cd "$r" && git add -A && git commit -qm patch && git tag 9.9p2-mavergreen.1 )
mkdir -p "$r/.mavergreen/ingredients/quilt"
printf 'quilt\n' > "$r/.mavergreen/ingredients/quilt/description"
printf 'patches/*.patch\n' > "$r/.mavergreen/ingredients/quilt/watch"
printf 'Subject: [PATCH] one\n+x\n' > "$r/patches/x.patch"
( cd "$r" && git add -A && git commit -qm "add quilt, change the patch" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null || { echo "FAIL added-watch: ships"; exit 1; }
grep -qx -- '- Changed `patches/x.patch`' "$r/OUT.md" \
  || { echo "FAIL added-watch: a new ingredient gets no watch bullet, so its patch is one of our patches"; cat "$r/OUT.md"; exit 1; }

r="$work/prose-ing"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 )
bump "$r" 3.9.2
printf 'Why this release matters.\n' > "$r/.mavergreen/release-notes/9.9p2-mavergreen.2.md"
( cd "$r" && git add -A && git commit -qm "bump libressl, with prose" && git tag 9.9p2-mavergreen.2 \
    && git commit -q --allow-empty -m later )
gen "$r" 9.9p2-mavergreen.2 >/dev/null || { echo "FAIL prose-ing: prose and a described ingredient bullet pass the shape check"; exit 1; }
grep -q '^Why this release matters\.$' "$r/OUT.md" || { echo "FAIL prose-ing: prose"; cat "$r/OUT.md"; exit 1; }
grep -qx -- '  LibreSSL' "$r/OUT.md" || { echo "FAIL prose-ing: description"; cat "$r/OUT.md"; exit 1; }
sh "$here/../scripts/check-release-notes.sh" "$r/OUT.md" 9.9p2-mavergreen.2 >/dev/null \
  || { echo "FAIL prose-ing: shape"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- committed prose for an already-minted tag (a non-publishing run
#       regenerating a published release) is published verbatim with any mark line
#       stripped and no mark required; for a tag not yet minted it is refused, naming the directory form.
M='<!-- edited by a human -->'
hp() {
  r="$work/hp-$1"; mkrepo "$r"
  printf "$3" > "$r/.mavergreen/release-notes/9.9p2-mavergreen.1.md"
  ( cd "$r" && git add -A && git commit -qm notes && git tag 9.9p2-mavergreen.1 )
  if [ "$2" = minted ]; then ( cd "$r" && echo x >> README.md && git add -A && git commit -qm later ); fi
  rc=0; gen "$r" 9.9p2-mavergreen.1 >/dev/null 2>"$r/ERR" || rc=$?
}
hp legacy-minted minted "Some prose.\n$M\nMore.\n"
[ "$rc" -eq 0 ] || { echo "FAIL legacy-minted: ships"; cat "$r/ERR"; exit 1; }
grep -q 'edited by a human' "$r/OUT.md" && { echo "FAIL legacy-minted: the mark is stripped"; exit 1; }
grep -q '^Some prose\.$' "$r/OUT.md" && grep -q '^More\.$' "$r/OUT.md" \
  || { echo "FAIL legacy-minted: prose verbatim"; cat "$r/OUT.md"; exit 1; }
[ "$(awk 'f{print;n++} /^More\.$/{f=1} n==2{exit}' "$r/OUT.md")" = "$(printf '\n### What changed')" ] \
  || { echo "FAIL legacy-minted: the mark's line leaves no trace"; cat "$r/OUT.md"; exit 1; }
hp legacy-minted-unmarked minted 'Some prose.\n'
[ "$rc" -eq 0 ] || { echo "FAIL legacy-minted-unmarked: #123 needs no mark"; cat "$r/ERR"; exit 1; }
grep -q '^Some prose\.$' "$r/OUT.md" || { echo "FAIL legacy-minted-unmarked: prose included"; exit 1; }
hp legacy-verbatim minted 'Hand-written paragraph.\n\n- a bullet a human wrote\n'
[ "$rc" -eq 0 ] || { echo "FAIL legacy-verbatim: ships"; cat "$r/ERR"; exit 1; }
grep -q 'Hand-written paragraph.' "$r/OUT.md" || { echo "FAIL legacy-verbatim: not included"; exit 1; }
grep -q '^- a bullet a human wrote$' "$r/OUT.md" || { echo "FAIL legacy-verbatim: mangled"; exit 1; }
grep -q '^### What changed$' "$r/OUT.md" || { echo "FAIL legacy-verbatim: generated sections dropped"; exit 1; }
hp legacy-crlf minted "Some prose.\n$M  \r\n"
[ "$rc" -eq 0 ] || { echo "FAIL legacy-crlf: ships"; cat "$r/ERR"; exit 1; }
grep -q 'edited by a human' "$r/OUT.md" && { echo "FAIL legacy-crlf: mark with CR or trailing spaces is stripped"; exit 1; }
hp twice minted "$M\nSome prose.\n$M\n"
[ "$rc" -eq 0 ] || { echo "FAIL every mark line is stripped"; cat "$r/ERR"; exit 1; }
grep -q 'edited by a human' "$r/OUT.md" && { echo "FAIL every mark line is stripped"; exit 1; }
hp markonly minted "$M\n"
[ "$rc" -eq 0 ] || { echo "FAIL mark-only file inserts nothing"; cat "$r/ERR"; exit 1; }
r1="$r"; r="$work/hp-none"; mkrepo "$r"; ( cd "$r" && git tag 9.9p2-mavergreen.1 && echo x >> README.md && git add -A && git commit -qm later ); gen "$r" 9.9p2-mavergreen.1 >/dev/null
[ "$(cat "$r1/OUT.md")" = "$(cat "$r/OUT.md")" ] || { echo "FAIL mark-only file inserts nothing: body differs from no prose"; diff "$r/OUT.md" "$r1/OUT.md"; exit 1; }
for c in legacy-new legacy-new-marked; do
  case "$c" in legacy-new) f='Some prose.\n' ;; *) f="Some prose.\n$M\n" ;; esac
  hp "$c" new "$f"
  [ "$rc" -ne 0 ] || { echo "FAIL $c: refused"; exit 1; }
  [ ! -e "$r/OUT.md" ] || { echo "FAIL $c: --out was written"; exit 1; }
  grep -qF '.mavergreen/release-notes/9.9p2-mavergreen.1.md' "$r/ERR" && grep -qF '.mavergreen/release-notes/9.9p2-mavergreen.1/' "$r/ERR" \
    || { echo "FAIL $c: the complaint names the file and the directory"; cat "$r/ERR"; exit 1; }
done

# spec: SKILL.md "Release notes" -- a new release says what changed in
#       .mavergreen/release-notes/<TAG>/ files: changes/<slug> bullets lead What changed; a
#       product's requires/<dep>/min that moved and rebuild make Before you update; and the
#       product's standing notice opens the footer. Each sentence is checked unless the tag is
#       minted; the tree's shape is checked always.
T=9.9p2-mavergreen.2
dset() {  # $1 = case; leaves $r with tag 9.9p2-mavergreen.1 and $d = its .mavergreen/release-notes/$T
  r="$work/dir-$1"; mkrepo "$r"; ( cd "$r" && git tag 9.9p2-mavergreen.1 ); d="$r/.mavergreen/release-notes/$T"
}
dgen() {  # $1 = minted|new, rest = extra args; tags $T, generates $T, leaves $rc and $r/ERR
  m="$1"; shift
  ( cd "$r" && git add -A && git commit -q --allow-empty -m notes && git tag "$T" )
  if [ "$m" = minted ]; then ( cd "$r" && echo x >> README.md && git add -A && git commit -qm later ); fi
  rc=0; gen "$r" "$T" "$@" >/dev/null 2>"$r/ERR" || rc=$?
}
req() {  # $1 = repo, $2 = product, $3 = dependency, $4 = its min
  mkdir -p "$1/.mavergreen/products/$2/requires/$3"; printf '%s\n' "$4" > "$1/.mavergreen/products/$2/requires/$3/min"
}
notice() {  # $1 = repo, $2 = product, $3 = the notice
  mkdir -p "$1/.mavergreen/products/$2"; printf '%s\n' "$3" > "$1/.mavergreen/products/$2/notice"
}
refused() {  # $1 = label, $2 = text the complaint must carry
  [ "$rc" -ne 0 ] || { echo "FAIL $1: refused"; cat "$r/OUT.md"; exit 1; }
  [ ! -e "$r/OUT.md" ] || { echo "FAIL $1: --out was written"; exit 1; }
  grep -qF -- "$2" "$r/ERR" || { echo "FAIL $1: the complaint names $2"; cat "$r/ERR"; exit 1; }
}

dset changes; mkdir -p "$d/changes"
printf 'Stop now stays stopped.\n' > "$d/changes/a-first"
printf 'Keys load again.\n' > "$d/changes/b-second"
dgen new
[ "$rc" -eq 0 ] || { echo "FAIL dir-changes: ships"; cat "$r/ERR"; exit 1; }
[ "$(awk '/^### What changed$/{f=1; next} f{print} f&&++n==3{exit}' "$r/OUT.md")" = "$(printf -- '- Stop now stays stopped.\n- Keys load again.\n- Built on upstream OpenSSH 9.9p2 (no upstream change).')" ] \
  || { echo "FAIL dir-changes: change bullets lead What changed"; cat "$r/OUT.md"; exit 1; }
grep -q 'packaging changes only' "$r/OUT.md" && { echo "FAIL dir-changes: changes are not packaging only"; cat "$r/OUT.md"; exit 1; }
grep -q '### Before you update' "$r/OUT.md" && { echo "FAIL dir-changes: no requirement or rebuild, no section"; exit 1; }
r="$work/dir-changes-self"; mkrepo "$r"
( cd "$r" && git tag 20260802.4 && git tag 20260802.5 )
mkdir -p "$r/.mavergreen/release-notes/20260802.6/changes"; printf 'Pure-Go programs now run on Mavericks.\n' > "$r/.mavergreen/release-notes/20260802.6/changes/go"
( cd "$r" && git add -A && git commit -qm notes )
gen "$r" 20260802.6 --product Porthole --min-os 10.9 >/dev/null 2>"$r/ERR" || { echo "FAIL dir-changes-self: ships"; cat "$r/ERR"; exit 1; }
[ "$(awk '/^### What changed$/{f=1; next} f{print} f&&++n==3{exit}' "$r/OUT.md")" = "$(printf -- '- Pure-Go programs now run on Mavericks.\n- New release of Porthole 20260802.6 (was 20260802.5).\n  [Changes since 20260802.5](https://github.com/Mavergreen/mavericks-openssh/compare/20260802.5...20260802.6)')" ] \
  || { echo "FAIL dir-changes-self: a same-date release with changes is a new release"; cat "$r/OUT.md"; exit 1; }

dset before; mkdir -p "$d/changes"
printf 'Keys load again.\n' > "$d/changes/keys"
req "$r" openssh clang22 22.1.8
printf 'Rebuild your Go programs to use the new SDK.\n' > "$d/rebuild"
dgen new
[ "$rc" -eq 0 ] || { echo "FAIL dir-before: ships"; cat "$r/ERR"; exit 1; }
[ "$(awk '/^### /{print}' "$r/OUT.md" | sed -n 1,2p)" = "$(printf '### Before you update\n### What changed')" ] \
  || { echo "FAIL dir-before: Before you update comes first"; cat "$r/OUT.md"; exit 1; }
[ "$(awk '/^### Before you update$/{f=1; next} f&&/^$/{exit} f{print}' "$r/OUT.md")" = "$(printf -- '- Install clang22 22.1.8 or later first.\n- Rebuild your Go programs to use the new SDK.')" ] \
  || { echo "FAIL dir-before: requirements, then rebuild"; cat "$r/OUT.md"; exit 1; }
r="$work/dir-req-same"; mkrepo "$r"; req "$r" openssh clang22 22.1.8; req "$r" openssh libressl 3.8.2
( cd "$r" && git add -A && git commit -qm req && git tag 9.9p2-mavergreen.1 )
req "$r" openssh libressl 3.9.2; req "$r" openssh zlib 1.3
( cd "$r" && git add -A && git commit -qm raise && git tag "$T" )
gen "$r" "$T" >/dev/null 2>"$r/ERR" || { echo "FAIL dir-req-same: ships"; cat "$r/ERR"; exit 1; }
[ "$(awk '/^### Before you update$/{f=1; next} f&&/^$/{exit} f{print}' "$r/OUT.md")" = "$(printf -- '- Install libressl 3.9.2 or later first.\n- Install zlib 1.3 or later first.')" ] \
  || { echo "FAIL dir-req-same: a raised or new min is listed, an unchanged one is not"; cat "$r/OUT.md"; exit 1; }
r="$work/dir-req-landing"; mkrepo "$r"
( cd "$r" && git rm -rq .mavergreen && git commit -qm legacy && git tag 9.9p2-mavergreen.1 \
    && git checkout -q HEAD~1 -- .mavergreen && git commit -qm "the flag day" )
req "$r" openssh clang22 22.1.8
( cd "$r" && git add -A && git commit -qm req && git tag "$T" )
gen "$r" "$T" >/dev/null 2>"$r/ERR" || { echo "FAIL dir-req-landing: ships"; cat "$r/ERR"; exit 1; }
grep -q '### Before you update' "$r/OUT.md" && { echo "FAIL dir-req-landing: a release from before .mavergreen/ lists no requirement"; cat "$r/OUT.md"; exit 1; }

dset notice; notice "$r" openssh 'Never publish an image that contains macOS.'
dgen new --min-os ''
[ "$rc" -eq 0 ] || { echo "FAIL dir-notice: ships"; cat "$r/ERR"; exit 1; }
[ "$(awk '/^---$/{f=1; next} f' "$r/OUT.md")" = "$(printf 'Never publish an image that contains macOS.\n\n[All changes since 9.9p2-mavergreen.1](https://github.com/Mavergreen/mavericks-openssh/compare/9.9p2-mavergreen.1...9.9p2-mavergreen.2)')" ] \
  || { echo "FAIL dir-notice: the notice opens the footer"; cat "$r/OUT.md"; exit 1; }
gen "$r" "$T" >/dev/null 2>"$r/ERR" || { echo "FAIL dir-notice: ships with a floor"; cat "$r/ERR"; exit 1; }
[ "$(awk '/^---$/{f=1; next} f' "$r/OUT.md" | sed -n 1,3p)" = "$(printf 'Never publish an image that contains macOS.\n\nRequires Mac OS X 10.9.5 or later.')" ] \
  || { echo "FAIL dir-notice: a blank line before each later footer line"; cat "$r/OUT.md"; exit 1; }
notice "$r" openssh 'See https://x.org now.'
rm -f "$r/OUT.md"; rc=0; gen "$r" "$T" >/dev/null 2>"$r/ERR" || rc=$?
refused dir-notice-checked 'release-sentence: '

for m in new minted; do
  dset "bad-sentence-$m"; mkdir -p "$d/changes"; printf 'Cut to exercise the shared publish-release.yml.\n' > "$d/changes/x"
  dgen "$m"
  if [ "$m" = new ]; then
    refused dir-bad-sentence 'release-sentence: '
    grep -qF "$d/changes/x" "$r/ERR" || { echo "FAIL dir-bad-sentence: names the file"; cat "$r/ERR"; exit 1; }
  else
    [ "$rc" -eq 0 ] || { echo "FAIL dir-bad-sentence: a minted tag regenerates without the sentence check"; cat "$r/ERR"; exit 1; }
    grep -q '^- Cut to exercise' "$r/OUT.md" || { echo "FAIL dir-bad-sentence: minted renders"; cat "$r/OUT.md"; exit 1; }
  fi
done

for c in notes.md .DS_Store 'changes/Foo Bar' changes/ requires/; do
  for m in new minted; do
    dset "stray-$m-$(printf %s "$c" | tr -c a-zA-Z -)"; mkdir -p "$d/changes"
    case "$c" in
      */) rm -rf "$d/changes"; mkdir -p "$d/$c"; printf 'Keep going.\n' > "$d/rebuild"; ( cd "$r" && git add -A && git commit -qm keep ); want="$d/${c%/}" ;;
      *) printf 'Keys load again.\n' > "$d/changes/keys"; printf 'Stray.\n' > "$d/$c"; want="$d/$c" ;;
    esac
    dgen "$m"
    refused "dir-stray $c $m" "$want"
  done
done

dset crlf; mkdir -p "$d/changes"; printf 'Works now.  \r' > "$d/changes/w"
dgen new
[ "$rc" -eq 0 ] || { echo "FAIL dir-crlf: ships"; cat "$r/ERR"; exit 1; }
grep -q '^- Works now\.$' "$r/OUT.md" || { echo "FAIL dir-crlf: rendered without the CR"; od -c "$r/OUT.md" | head -20; exit 1; }

dset both; mkdir -p "$d/changes"; printf 'Keys load again.\n' > "$d/changes/keys"; printf 'Prose.\n' > "$r/.mavergreen/release-notes/$T.md"
dgen new
refused dir-both ".mavergreen/release-notes/$T.md"

for c in 'clang22 1 .0' 'clang22 v1.0' 'clang22 \f22.1.8\f'; do
  dset "requires-bad-$(printf %s "$c" | tr -c a-z0-9 -)"; req "$r" openssh "${c%% *}" "$(printf "${c#* }")"
  for m in new minted; do
    [ "$m" = new ] || { rm -f "$r/OUT.md"; ( cd "$r" && git tag -d "$T" >/dev/null ); }
    dgen "$m"
    refused "dir-requires-bad $c $m" "$r/.mavergreen/products/openssh/requires/${c%% *}/min"
  done
done

dset short; n="$r/.mavergreen/release-notes/swift-runtime"; mkdir -p "$n/$T/changes" "$d"
printf 'Runtime loads faster.\n' > "$n/$T/changes/x"; notice "$r" swift-runtime 'Use the runtime from here.'
printf 'Stray.\n' > "$d/notes.md"; notice "$r" openssh 'Top-level notice.'; decl "$r" swift-runtime
dgen new --short swift-runtime
[ "$rc" -eq 0 ] || { echo "FAIL dir-short: ships"; cat "$r/ERR"; exit 1; }
grep -q '^- Runtime loads faster\.$' "$r/OUT.md" && grep -q '^Use the runtime from here\.$' "$r/OUT.md" \
  || { echo "FAIL dir-short: the nested tree is read"; cat "$r/OUT.md"; exit 1; }
grep -q 'Top-level' "$r/OUT.md" && { echo "FAIL dir-short: the top-level tree is ignored"; exit 1; }
rm -f "$r/OUT.md"; rc=0; gen "$r" "$T" --short openssh >/dev/null 2>"$r/ERR" || rc=$?
refused dir-short-fallback "$d/notes.md"
r="$work/dir-changes-self-ing"; mkrepo "$r"
( cd "$r" && git tag 20260802.5 ); bump "$r" 3.9.2
mkdir -p "$r/.mavergreen/release-notes/20260802.6/changes"; printf 'Pure-Go programs now run on Mavericks.\n' > "$r/.mavergreen/release-notes/20260802.6/changes/go"
( cd "$r" && git add -A && git commit -qm "bump libressl" )
gen "$r" 20260802.6 --product Porthole --min-os 10.9 >/dev/null 2>"$r/ERR" || { echo "FAIL dir-changes-self-ing: ships"; cat "$r/ERR"; exit 1; }
[ "$(awk '/^### What changed$/{f=1; next} f{print} f&&++n==2{exit}' "$r/OUT.md")" = "$(printf -- '- Pure-Go programs now run on Mavericks.\n- Rebuilt because build ingredients moved (below).')" ] \
  || { echo "FAIL dir-changes-self-ing: changes are a change to the product itself"; cat "$r/OUT.md"; exit 1; }

for m in new minted; do
  dset "short-md-$m"; n="$r/.mavergreen/release-notes/swift-runtime"; mkdir -p "$n"; decl "$r" swift-runtime
  printf 'Nested prose.\n' > "$n/$T.md"
  dgen "$m" --short swift-runtime
  if [ "$m" = new ]; then
    refused dir-short-md "$n/$T.md"
  else
    [ "$rc" -eq 0 ] || { echo "FAIL dir-short-md: minted nested prose ships"; cat "$r/ERR"; exit 1; }
    grep -q '^Nested prose\.$' "$r/OUT.md" || { echo "FAIL dir-short-md: minted nested prose publishes"; cat "$r/OUT.md"; exit 1; }
  fi
done

dset vt; mkdir -p "$d/changes"; printf 'Works now.\v\n' > "$d/changes/w"
dgen minted
[ "$rc" -eq 0 ] || { echo "FAIL dir-vt: minted ships"; cat "$r/ERR"; exit 1; }
grep -q '^- Works now\.$' "$r/OUT.md" || { echo "FAIL dir-vt: line 1 is stripped as the checker strips it"; od -c "$r/OUT.md" | head -20; exit 1; }

dset wrongtag; w="$r/.mavergreen/release-notes/9.9p2-mavergreen.9"; mkdir -p "$w/changes"; printf 'Keys load again.\n' > "$w/changes/keys"
dgen new
refused dir-wrongtag "$w"
grep -qF "$T" "$r/ERR" || { echo "FAIL dir-wrongtag: the complaint names the expected $T"; cat "$r/ERR"; exit 1; }
dset wrongtag-short; w="$r/.mavergreen/release-notes/swift-runtime/9.9p2-mavergreen.9"; mkdir -p "$w/changes"; decl "$r" swift-runtime; printf 'Keys load again.\n' > "$w/changes/keys"
dgen new --short swift-runtime
refused dir-wrongtag-short "$w"
dset wrongtag-minted; mkdir -p "$r/.mavergreen/release-notes/9.9p2-mavergreen.9/changes"; printf 'Keys load again.\n' > "$r/.mavergreen/release-notes/9.9p2-mavergreen.9/changes/keys"
dgen minted
[ "$rc" -eq 0 ] || { echo "FAIL dir-wrongtag-minted: regenerating a published release ignores notes staged for a later one"; cat "$r/ERR"; exit 1; }
dset oldtag; decl "$r" swift-runtime; mkdir -p "$r/.mavergreen/release-notes/9.9p2-mavergreen.1/changes" "$r/.mavergreen/release-notes/swift-runtime"
printf 'Old news.\n' > "$r/.mavergreen/release-notes/9.9p2-mavergreen.1/changes/old"
mkdir -p "$r/.mavergreen/release-notes/swift-runtime/$T/changes"; printf 'Use the runtime from here.\n' > "$r/.mavergreen/release-notes/swift-runtime/$T/changes/x"
dgen new
[ "$rc" -eq 0 ] || { echo "FAIL dir-oldtag: an existing tag's directory and a product's nest are not strays"; cat "$r/ERR"; exit 1; }
grep -q 'Old news\|runtime from here' "$r/OUT.md" && { echo "FAIL dir-oldtag: neither is read"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- a notes directory that cannot be read is refused, not read as absent.
if [ "$(id -u)" != 0 ]; then
  for mode in 000 644; do
    for sub in "" changes; do
      dset "unreadable-$mode-$sub"; mkdir -p "$d/changes"; printf 'Keys load again.\n' > "$d/changes/keys"
      ( cd "$r" && git add -A && git commit -qm notes && git tag "$T" )
      chmod "$mode" "$d${sub:+/$sub}"
      rc=0; gen "$r" "$T" >/dev/null 2>"$r/ERR" || rc=$?
      chmod 755 "$d${sub:+/$sub}"
      refused "dir-unreadable $mode $sub" "$d${sub:+/$sub}"
    done
  done
fi

# spec: scripts/release-notes.sh -- the .mavergreen/release-notes/ tree itself, and a --short nest, are refused when unreadable.
if [ "$(id -u)" != 0 ]; then
  for mode in 000 644; do
    for level in top nest; do
      dset "unreadable-$level-$mode"; n="$r/.mavergreen/release-notes"
      mkdir -p "$d/changes" "$n/swift-runtime/$T/changes"
      printf 'Keys load again.\n' > "$d/changes/keys"; printf 'Runtime loads faster.\n' > "$n/swift-runtime/$T/changes/x"; decl "$r" swift-runtime
      ( cd "$r" && git add -A && git commit -qm notes && git tag "$T" )
      if [ "$level" = top ]; then victim="$n"; extra=""; else victim="$n/swift-runtime"; extra="--short swift-runtime"; fi
      chmod "$mode" "$victim"
      rc=0; gen "$r" "$T" $extra >/dev/null 2>"$r/ERR" || rc=$?
      chmod 755 "$victim"
      refused "dir-unreadable-$level $mode" "$victim"
    done
  done
  dset requires-unreadable; req "$r" openssh clang22 22.1.8; m="$r/.mavergreen/products/openssh/requires/clang22/min"
  ( cd "$r" && git add -A && git commit -qm notes && git tag "$T" )
  chmod 000 "$m"
  rc=0; gen "$r" "$T" >/dev/null 2>"$r/ERR" || rc=$?
  chmod 644 "$m"
  refused dir-requires-unreadable "$m"
  grep -q 'integer expression' "$r/ERR" && { echo "FAIL dir-requires-unreadable: a shell error leaked"; cat "$r/ERR"; exit 1; }
fi

# spec: scripts/release-notes.sh -- --short names a product this repo declares.
dset short-undeclared; n="$r/.mavergreen/release-notes/swift-runtime"; mkdir -p "$n/$T/changes"; printf 'Runtime loads faster.\n' > "$n/$T/changes/x"
dgen new --short swift-runtime
refused dir-short-undeclared ".mavergreen/products/swift-runtime/"

# spec: scripts/release-notes.sh -- --short names a declared product, in the form a short name takes.
for sv in .. a/b '' Foo -x swift-runtime-other; do
  dset "short-bad-$(printf %s "$sv" | tr -c a-z0-9 -)"; n="$r/.mavergreen/release-notes/swift-runtime"; mkdir -p "$n/$T/changes"
  printf 'Runtime loads faster.\n' > "$n/$T/changes/x"
  dgen new --short "$sv"
  refused "dir-short-bad '$sv'" "--short"
done

# spec: SKILL.md "Release notes" -- Before you update with only the rebuild bullet; a first release
#       whose footer is only the notice; a port repackage that has changes/ and moved ingredients.
dset rebuild-only; mkdir -p "$d"; printf 'Rebuild your Go programs to use the new SDK.\n' > "$d/rebuild"
dgen new
[ "$rc" -eq 0 ] || { echo "FAIL dir-rebuild-only: ships"; cat "$r/ERR"; exit 1; }
[ "$(awk '/^### Before you update$/{f=1; next} f&&/^$/{exit} f{print}' "$r/OUT.md")" = '- Rebuild your Go programs to use the new SDK.' ] \
  || { echo "FAIL dir-rebuild-only: only the rebuild bullet"; cat "$r/OUT.md"; exit 1; }
r="$work/dir-notice-first"; mkrepo "$r"; notice "$r" openssh 'Never publish an image that contains macOS.'
( cd "$r" && git add -A && git commit -qm notice && git tag 9.9p2-mavergreen.1 )
gen "$r" 9.9p2-mavergreen.1 --min-os '' >/dev/null 2>"$r/ERR" || { echo "FAIL dir-notice-first: ships"; cat "$r/ERR"; exit 1; }
[ "$(awk '/^---$/{f=1; next} f' "$r/OUT.md")" = 'Never publish an image that contains macOS.' ] \
  || { echo "FAIL dir-notice-first: the footer is the notice alone"; cat "$r/OUT.md"; exit 1; }
dset changes-ing; mkdir -p "$d/changes"; printf 'Keys load again.\n' > "$d/changes/keys"
bump "$r" 3.9.2
dgen new
[ "$rc" -eq 0 ] || { echo "FAIL dir-changes-ing: ships"; cat "$r/ERR"; exit 1; }
[ "$(awk '/^### What changed$/{f=1; next} f{print} f&&++n==3{exit}' "$r/OUT.md")" = "$(printf -- '- Keys load again.\n- Repackage of upstream OpenSSH 9.9p2, rebuilt because build ingredients moved (below).\n  No upstream change.')" ] \
  || { echo "FAIL dir-changes-ing: changes lead, then the ingredient repackage line"; cat "$r/OUT.md"; exit 1; }
grep -q '^### Build ingredients$' "$r/OUT.md" || { echo "FAIL dir-changes-ing: ingredients listed"; exit 1; }
grep -q 'Built on upstream' "$r/OUT.md" && { echo "FAIL dir-changes-ing: not 'Built on upstream'"; exit 1; }

# spec: scripts/release-notes.sh -- bullets order by slug in the C locale: '-' before a letter, which a
#       dictionary collation reverses. Capitals are not slugs, so a-z and aa stand in for B-x and a-x.
dset slug-order; mkdir -p "$d/changes"; printf 'Second thing.\n' > "$d/changes/aa"; printf 'First thing.\n' > "$d/changes/a-z"
( LC_ALL=en_US.UTF-8; export LC_ALL; dgen new; echo "$rc" > "$r/RC" )
rc="$(cat "$r/RC")"
[ "$rc" -eq 0 ] || { echo "FAIL dir-slug-order: ships"; cat "$r/ERR"; exit 1; }
[ "$(awk '/^### What changed$/{f=1; next} f{print} f&&++n==2{exit}' "$r/OUT.md")" = "$(printf -- '- First thing.\n- Second thing.')" ] \
  || { echo "FAIL dir-slug-order: C-locale order"; cat "$r/OUT.md"; exit 1; }

for p in Shipyard Porthole; do
  r="$work/dir-shipyard-$p"; mkrepo "$r"; ( cd "$r" && git tag v1.0.1 )
  mkdir -p "$r/.mavergreen/release-notes/v1.0.2/changes"; printf 'Shipyard now installs beside cmake.\n' > "$r/.mavergreen/release-notes/v1.0.2/changes/x"
  ( cd "$r" && git add -A && git commit -qm notes )
  rc=0; gen "$r" v1.0.2 --product "$p" >/dev/null 2>"$r/ERR" || rc=$?
  if [ "$p" = Shipyard ]; then
    [ "$rc" -eq 0 ] || { echo "FAIL dir-shipyard: shipyard's own notes may name it"; cat "$r/ERR"; exit 1; }
  else
    refused dir-shipyard-other 'internal term'
  fi
done

# spec: scripts/release-notes.sh -- self-upstream has no -mavergreen axis, so no upstream claim
#       and a plain title.
r="$work/self"; mkrepo "$r"; rm "$r/.mavergreen/hooks/upstream-release-notes-url"
deviation "$r" upstream-notes self '*' 'this repo is its own upstream.'
( cd "$r" && git add -A && git commit -qm self && git tag 20260802.5 )
( cd "$r" && MAVERGREEN_REPO_ROOT="$r" sh "$S" --tag 20260802.6 --version 20260802.6 \
    --product Porthole --out "$r/OUT.md" ) >/dev/null
grep -q '^## Porthole 20260802.6$' "$r/OUT.md" || { echo "FAIL self: title"; cat "$r/OUT.md"; exit 1; }
grep -q '^## .* (' "$r/OUT.md" && { echo "FAIL self: port-shaped title"; exit 1; }

# spec: Porthole/shipyard/magic-trackpad2 have no -mavergreen axis, so SELF_UPSTREAM is decided
#       from VER alone; that must not also mean "never gets a baseline" -- self-upstream also gets
#       the same compare-link footer everyone else gets. gen() hard-codes --product/--min-os but
#       appends "$@" after them, and release-notes.sh's argument loop lets a later flag win, so
#       this overrides both to exercise the porthole (YYYYMMDD.N) tag shape through the shared
#       fixture.
r="$work/selfglob"; mkrepo "$r"
( cd "$r" && git tag 20260802.4 && git tag 20260802.5 )
gen "$r" 20260802.6 --product Porthole --min-os 10.9 >/dev/null
grep -q '^## Porthole 20260802.6$' "$r/OUT.md" \
  || { echo "FAIL selfglob: title"; cat "$r/OUT.md"; exit 1; }
grep -q '^- Repackage of Porthole 20260802; packaging changes only\.$' "$r/OUT.md" \
  || { echo "FAIL selfglob: what-changed"; cat "$r/OUT.md"; exit 1; }
grep -q '^\[All changes since 20260802\.5\](.*compare/20260802\.5\.\.\.20260802\.6)$' "$r/OUT.md" \
  || { echo "FAIL selfglob: compare link missing"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh's SELF_GLOB derivation -- the date-shaped case above alone
#       leaves the v-shaped branch (shipyard/magic-trackpad2) uncovered: deleting the v[0-9]*
#       case left the whole suite green until this was added.
r="$work/selfvglob"; mkrepo "$r"
( cd "$r" && git tag v0.5.1 && git tag v0.5.2 )
gen "$r" v0.5.3 --product MagicTrackpad2 --min-os 10.9 >/dev/null
grep -q '^## MagicTrackpad2 v0.5.3$' "$r/OUT.md" \
  || { echo "FAIL selfvglob: title"; cat "$r/OUT.md"; exit 1; }
grep -q '^- New release of MagicTrackpad2 v0.5.3 (was v0.5.2)\.$' "$r/OUT.md" \
  || { echo "FAIL selfvglob: what-changed"; cat "$r/OUT.md"; exit 1; }
grep -q '^\[All changes since v0\.5\.2\](.*compare/v0\.5\.2\.\.\.v0\.5\.3)$' "$r/OUT.md" \
  || { echo "FAIL selfvglob: compare link missing"; cat "$r/OUT.md"; exit 1; }

r="$work/badhook"; mkrepo "$r"
printf '#!/bin/sh\nexit 1\n' > "$r/.mavergreen/hooks/upstream-release-notes-url"
( cd "$r" && git commit -qam badhook && git tag 9.9p2-mavergreen.1 )
if gen "$r" 9.9p2-mavergreen.1 >/dev/null 2>&1; then echo "FAIL badhook: should be fatal"; exit 1; fi
out="$(gen "$r" 9.9p2-mavergreen.1 2>&1 || true)"
printf '%s\n' "$out" | grep -qi 'upstream' || { echo "FAIL badhook: cause not named: $out"; exit 1; }

r="$work/nohook"; mkrepo "$r"; rm "$r/.mavergreen/hooks/upstream-release-notes-url"
( cd "$r" && git add -A && git commit -qm nohook && git tag 9.9p2-mavergreen.1 )
if gen "$r" 9.9p2-mavergreen.1 >/dev/null 2>&1; then echo "FAIL: a new upstream with no hook and no declared reason must be fatal"; exit 1; fi

# spec: scripts/release-notes.sh -- but a declared upstream-notes deviation is the sanctioned way to have none.
deviation "$r" upstream-notes none '*' 'upstream publishes none.'
( cd "$r" && git add -A && git commit -qm declare )
gen "$r" 9.9p2-mavergreen.1 >/dev/null || { echo "FAIL nohook+declared: should pass"; exit 1; }

# spec: scripts/release-notes.sh -- whether this repo owns an upstream-notes hook and whether
#       this RELEASE is even due an upstream link are independent questions, and the second is
#       answerable from the tags alone. Resolving the hook first conflated them: every hookless
#       repo reported "new
#       upstream" regardless of its tags, so the fleet preview found 1password's -mavergreen.2,
#       swift-toolchain's -mavergreen.4 and container-tools' -mavergreen.23 -- all of them the Nth
#       repackage of an upstream already shipped N-1 times -- classified as brand-new upstreams.
#       That surfaced two ways: without a declared reason, a FALSE REFUSAL (a legitimate
#       repackage cannot be published at all, demanding a hook for an upstream link this release
#       was never owed -- 1password, swift-toolchain); with a declared reason, WORSE -- a green
#       run whose body asserts "New upstream: X" over a release that changed no upstream at all,
#       a false claim in the GitHub Release and the Sparkle dialog at exit 0 (container-tools).
#       The existing nohook cases above cannot catch either: both publish -mavergreen.1, where "no
#       other tag of this upstream exists" makes new-upstream the correct answer and the ordering
#       unobservable. A repo with NO hook can still be publishing a repackage, and a repackage is
#       due no link.
r="$work/nohook-repack"; mkrepo "$r"; rm "$r/.mavergreen/hooks/upstream-release-notes-url"
( cd "$r" && git add -A && git commit -qm nohook && git tag 9.9p2-mavergreen.1 \
    && echo x >> README.md && git add -A && git commit -qm "ci: unrelated" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null \
  || { echo "FAIL nohook-repack: a repackage is due no upstream link, so a missing hook must not block it"; exit 1; }
grep -q 'Repackage of upstream OpenSSH 9.9p2' "$r/OUT.md" \
  || { echo "FAIL nohook-repack: kind"; cat "$r/OUT.md"; exit 1; }
grep -q 'New upstream' "$r/OUT.md" \
  && { echo "FAIL nohook-repack: claims a new upstream over an upstream already shipped"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- and the declared-reason variant must not turn that false
#       claim into a GREEN one.
deviation "$r" upstream-notes none '*' 'upstream publishes none.'
( cd "$r" && git add -A && git commit -qm declare )
gen "$r" 9.9p2-mavergreen.2 >/dev/null || { echo "FAIL nohook-repack+declared: should pass"; exit 1; }
grep -q 'Repackage of upstream OpenSSH 9.9p2' "$r/OUT.md" \
  || { echo "FAIL nohook-repack+declared: kind"; cat "$r/OUT.md"; exit 1; }
grep -q 'New upstream' "$r/OUT.md" \
  && { echo "FAIL nohook-repack+declared: a declared reason must not license a false new-upstream claim"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/upstream-notes.sh -- a shallow clone hides the tags, so the kind cannot be
#       decided, and this must be fatal. The assertion checks the MESSAGE, not just a nonzero
#       exit: with the shallow guard removed,
#       this fixture still exits 1 (via upstream-notes.sh's own shallow-clone bail, mapped to the
#       catch-all die), so "some die fired" is not enough to prove the shallow guard itself is
#       doing anything.
r="$work/shallow"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 )
sr="$work/shallow-clone"
git clone -q --depth 1 "file://$r" "$sr" 2>/dev/null || git clone -q --depth 1 "$r" "$sr"
if ( cd "$sr" && MAVERGREEN_REPO_ROOT="$sr" sh "$S" --tag 9.9p2-mavergreen.2 --version 9.9p2-mavergreen.2 \
       --product OpenSSH --out "$sr/OUT.md" ) >/dev/null 2>&1; then
  echo "FAIL shallow: should be fatal (this is signal-desktop's silent-drop shape)"; exit 1
fi
shallow_out="$(cd "$sr" && MAVERGREEN_REPO_ROOT="$sr" sh "$S" --tag 9.9p2-mavergreen.2 --version 9.9p2-mavergreen.2 \
       --product OpenSSH --out "$sr/OUT.md" 2>&1 || true)"
printf '%s\n' "$shallow_out" | grep -qi shallow \
  || { echo "FAIL shallow: cause not named as shallow: $shallow_out"; exit 1; }

# platform: a non-shallow checkout can still hide tags (git clone --no-tags) -- the shallow
#           guard above does not fire here at all -- so a repackage (-mavergreen.2) must not be
#           silently read as a first release with no baseline.
r="$work/notags"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 )
nr="$work/notags-clone"
git clone -q --no-tags "$r" "$nr" 2>/dev/null
if ( cd "$nr" && MAVERGREEN_REPO_ROOT="$nr" sh "$S" --tag 9.9p2-mavergreen.2 --version 9.9p2-mavergreen.2 \
       --product OpenSSH --out "$nr/OUT.md" ) >/dev/null 2>&1; then
  echo "FAIL notags: -mavergreen.2 with no visible upstream tags should be fatal"; exit 1
fi
# spec: scripts/release-notes.sh -- but -mavergreen.1 with no visible tags stays a legitimate
#       first release (or a not-yet-tagged dispatch-cut build): the plan accepts that false
#       negative rather than block every real first release.
if ! ( cd "$nr" && MAVERGREEN_REPO_ROOT="$nr" GITHUB_SERVER_URL=https://github.com \
       GITHUB_REPOSITORY=Mavergreen/mavericks-openssh sh "$S" \
       --tag 9.9p2-mavergreen.1 --version 9.9p2-mavergreen.1 \
       --product OpenSSH --out "$nr/OUT.md" ) >/dev/null 2>&1; then
  echo "FAIL notags: -mavergreen.1 with no visible upstream tags should still succeed"; exit 1
fi

# spec: scripts/previous-release-tag.sh takes a GLOB -- golang ships parallel lines; 1.26.7's
#       baseline must be 1.26.5 (same line), not 1.27.0 (a newer line that shipped in between) --
#       --line must scope the baseline to its own line, not the numerically-highest tag. Both
#       spellings of --line must work: the human-friendly "1.26" (the original bug: a bare prefix
#       matched nothing) and the already-a-glob "1.26.*".
r="$work/golang"; mkrepo "$r"
( cd "$r" && git tag 1.26.5-mavergreen.1 && git tag 1.27.0-mavergreen.1 )
for line in "1.26" "1.26.*"; do
  ( cd "$r" && GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=Mavergreen/mavericks-golang \
      MAVERGREEN_REPO_ROOT="$r" sh "$S" --tag 1.26.7-mavergreen.1 --version 1.26.7-mavergreen.1 \
      --product Go --line "$line" --out "$r/OUT.md" ) >/dev/null \
    || { echo "FAIL golang ($line): should succeed"; exit 1; }
  grep -q 'was 1.26.5' "$r/OUT.md" \
    || { echo "FAIL golang ($line): baseline should be 1.26.5"; cat "$r/OUT.md"; exit 1; }
  grep -q '1.27.0' "$r/OUT.md" \
    && { echo "FAIL golang ($line): must not pick the newer 1.27.0 line as baseline"; cat "$r/OUT.md"; exit 1; }
done

# spec: the original openssh bug -- a real ingredient bump (.mavergreen/ingredients/libressl/VERSION) reported
#       as "packaging changes only" because the caller was under a name ingredient-pins.sh did not
#       look for, or its own crash was swallowed. Reproduce both against this script directly, not
#       just ingredient-pins.sh: an ingredient repackage caller whose pins cannot be derived must
#       not ship as packaging-only.
r="$work/badcaller"; mkrepo "$r"
mv "$r/.github/workflows/repackage-on-ingredient-bump.yml" "$r/.github/workflows/renovate-repackage.yml"
( cd "$r" && git add -A && git commit -qm "rename caller" && git tag 9.9p2-mavergreen.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null \
  || { echo "FAIL badcaller: should succeed once the caller is discovered by content, not by name"; exit 1; }
grep -q 'rebuilt because build ingredients moved' "$r/OUT.md" \
  || { echo "FAIL badcaller: a moved pin under a differently-named caller must not read as packaging-only"; cat "$r/OUT.md"; exit 1; }

r="$work/nopins"; mkrepo "$r"
cat > "$r/.github/workflows/repackage-on-ingredient-bump.yml" <<'YML'
on:
  push:
    branches: [main]
jobs:
  repackage:
    uses: Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
YML
rm -rf "$r/.mavergreen/ingredients"
( cd "$r" && git add -A && git commit -qm "caller with no ingredients" && git tag 9.9p2-mavergreen.1 )
if gen "$r" 9.9p2-mavergreen.1 >/dev/null 2>&1; then
  echo "FAIL nopins: a wired-up caller deriving zero pins should be fatal"; exit 1
fi

r="$work/unwired"; mkrepo "$r"
cat > "$r/.github/workflows/repackage-on-ingredient-bump.yml" <<'YML'
# placeholder -- not yet wired up
on:
  workflow_dispatch: {}
YML
( cd "$r" && git add -A && git commit -qm "scaffold placeholder caller" && git tag 9.9p2-mavergreen.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null \
  || { echo "FAIL unwired: a half-wired placeholder at the conventional path must not be fatal"; exit 1; }
grep -q 'rebuilt because build ingredients moved' "$r/OUT.md" \
  || { echo "FAIL unwired: .mavergreen/ingredients/, not the caller, says what moved"; cat "$r/OUT.md"; exit 1; }

# spec: release.yml sorts before repackage-on-ingredient-bump.yml in glob order, and a comment
#       naming the caller (a plausible thing to write, e.g. documenting a dispatch trigger) must
#       not be mistaken for a call to it. If it is, the real caller sitting right next to it is
#       never consulted: either a legitimate release goes FATAL (decoy paths name an untracked
#       file -> zero pins) or, worse, it ships with the WRONG ingredient section (decoy paths name
#       a tracked file -> that file's own history is reported instead of the real moved pin). A
#       decoy workflow that only MENTIONS the caller must not outrank the real caller.
r="$work/decoytrap"; mkrepo "$r"
cat > "$r/.github/workflows/release.yml" <<'YML'
# Dispatched by repackage-on-ingredient-bump.yml with local_release=true.
on:
  push:
    tags:
      - '*-mavergreen.*'
    paths:
      - CMakeLists.txt
jobs:
  release:
    uses: ./.github/workflows/publish-release.yml
YML
( cd "$r" && git add -A && git commit -qm "add release.yml" && git tag 9.9p2-mavergreen.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
printf 'cmake_minimum_required(VERSION 3.10)\n' > "$r/CMakeLists.txt"
( cd "$r" && git add -A && git commit -qm "bump libressl, add CMakeLists" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null \
  || { echo "FAIL decoytrap: should succeed (the real caller sits right next to the decoy)"; exit 1; }
grep -q '3.8.2 -> 3.9.2' "$r/OUT.md" \
  || { echo "FAIL decoytrap: real moved pin (libressl) not reported -- decoy caller won"; cat "$r/OUT.md"; exit 1; }
grep -q 'CMakeLists.txt' "$r/OUT.md" \
  && { echo "FAIL decoytrap: decoy caller's unrelated path leaked into the ingredient section"; cat "$r/OUT.md"; exit 1; }

# platform: `uses: >-` with the reusable workflow's URI on the CONTINUATION line is valid YAML
#           and a real call, but the word `uses:` and the filename are then on different lines,
#           so a
#       `uses:.*<filename>` regex never matches. This repo IS wired up and its libressl pin really
#       moved; reading it as "no caller" ships "packaging changes only" at exit 0 -- the exact
#       original openssh bug, silently, for nothing but a formatting choice. A genuinely-wired
#       caller written as a YAML folded scalar is still a caller.
r="$work/foldedcaller"; mkrepo "$r"
cat > "$r/.github/workflows/repackage-on-ingredient-bump.yml" <<'YML'
on:
  push:
    branches: [main]
    paths:
      - .mavergreen/ingredients/libressl/VERSION
jobs:
  repackage:
    uses: >-
      Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
YML
( cd "$r" && git add -A && git commit -qm "folded-scalar caller" && git tag 9.9p2-mavergreen.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null \
  || { echo "FAIL foldedcaller: a folded-scalar 'uses:' is a real call and must not be fatal"; exit 1; }
grep -q '### Build ingredients' "$r/OUT.md" \
  || { echo "FAIL foldedcaller: wired caller's moved pin dropped, no ingredient section"; cat "$r/OUT.md"; exit 1; }
grep -q '3.8.2 -> 3.9.2' "$r/OUT.md" \
  || { echo "FAIL foldedcaller: a real libressl bump must not read as packaging-only"; cat "$r/OUT.md"; exit 1; }

# spec: aaa-release.yml -- decoytrap above is guarded by two rules at once (the default-path
#       preference AND the comment filter), so deleting either one alone leaves it passing -- it
#       proves nothing about the comment filter by itself. Here there is no file at the
#       conventional path at all, so only the comment filter stands between the earlier-sorting
#       decoy and the real caller: without it aaa-release.yml wins discovery outright and the
#       notes report ITS path instead of the libressl bump that actually moved. A comment
#       mention must not win DISCOVERY either,
#       not just the default-path race.
r="$work/commentonly"; mkrepo "$r"
mv "$r/.github/workflows/repackage-on-ingredient-bump.yml" "$r/.github/workflows/renovate-repackage.yml"
cat > "$r/.github/workflows/aaa-release.yml" <<'YML'
# Dispatched by repackage-on-ingredient-bump.yml with local_release=true.
on:
  push:
    tags:
      - '*-mavergreen.*'
    paths:
      - CMakeLists.txt
jobs:
  release:
    uses: ./.github/workflows/publish-release.yml
YML
( cd "$r" && git add -A && git commit -qm "rename caller, add commenting decoy" && git tag 9.9p2-mavergreen.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
printf 'cmake_minimum_required(VERSION 3.10)\n' > "$r/CMakeLists.txt"
( cd "$r" && git add -A && git commit -qm "bump libressl, add CMakeLists" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null \
  || { echo "FAIL commentonly: a comment mention is not a second caller, so discovery is unambiguous"; exit 1; }
grep -q '3.8.2 -> 3.9.2' "$r/OUT.md" \
  || { echo "FAIL commentonly: real moved pin not reported -- the commenting decoy won discovery"; cat "$r/OUT.md"; exit 1; }
grep -q 'CMakeLists.txt' "$r/OUT.md" \
  && { echo "FAIL commentonly: the decoy's unrelated path leaked into the ingredient section"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh's caller discovery -- with no workflow at the conventional
#       path, an earlier-sorting file naming the reusable workflow on a NON-comment line is
#       indistinguishable from the real caller by content: it
#       yields pins of its own, and a genuine caller written as a folded scalar is the weaker
#       textual match. Picking the first in glob order shipped the decoy's own file as "the
#       ingredient that moved" and dropped the real libressl bump -- confidently wrong notes.
#       Which workflow defines the ingredient set is a gap, so discovery that finds two
#       candidates must not guess which one owns the pins -- it stops here.
r="$work/twocallers"; mkrepo "$r"
mv "$r/.github/workflows/repackage-on-ingredient-bump.yml" "$r/.github/workflows/renovate-repackage.yml"
cat > "$r/.github/workflows/aaa-release.yml" <<'YML'
on:
  push:
    paths:
      - CMakeLists.txt
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - run: echo "dispatched by repackage-on-ingredient-bump.yml"
YML
( cd "$r" && git add -A && git commit -qm "rename caller, add mentioning decoy" && git tag 9.9p2-mavergreen.1 )
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"
printf 'cmake_minimum_required(VERSION 3.10)\n' > "$r/CMakeLists.txt"
( cd "$r" && git add -A && git commit -qm "bump libressl, add CMakeLists" && git tag 9.9p2-mavergreen.2 )
if gen "$r" 9.9p2-mavergreen.2 >/dev/null 2>&1; then
  echo "FAIL twocallers: two discovery candidates must not be resolved by glob order"; cat "$r/OUT.md"; exit 1
fi
out="$(gen "$r" 9.9p2-mavergreen.2 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'aaa-release.yml' \
  || { echo "FAIL twocallers: the die must name the candidates: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'renovate-repackage.yml' \
  || { echo "FAIL twocallers: the die must name the candidates: $out"; exit 1; }

# spec: scripts/release-notes.sh -- a release that is BOTH a new upstream AND an ingredient
#       repackage must show both
#       sections, with the upstream content FIRST. Neither existing case covers this: `new` above
#       is a first release with no baseline (so no ingredient diff is even possible), and `ing`
#       above is a same-upstream repackage that explicitly asserts NO upstream claim. A real
#       release can be both at once (a new upstream tarball that also bumps a vendored ingredient
#       in the same cut), and nothing else here exercises that combination or its ordering.
r="$work/combo"; mkrepo "$r"
( cd "$r" && git tag 9.9p1-mavergreen.1 )                       # baseline: a DIFFERENT upstream (9.9p1)
printf '3.9.2\n' > "$r/.mavergreen/ingredients/libressl/VERSION"            # an ingredient pin moves too
( cd "$r" && git commit -qam "bump libressl" && git tag 9.9p2-mavergreen.1 )  # this cut ships new upstream 9.9p2
gen "$r" 9.9p2-mavergreen.1 >/dev/null
grep -q 'New upstream: OpenSSH 9.9p2 (was 9.9p1)' "$r/OUT.md" \
  || { echo "FAIL combo: missing new-upstream bullet"; cat "$r/OUT.md"; exit 1; }
grep -q '### Build ingredients' "$r/OUT.md" \
  || { echo "FAIL combo: missing ingredient section"; cat "$r/OUT.md"; exit 1; }
grep -q '3.8.2 -> 3.9.2' "$r/OUT.md" || { echo "FAIL combo: pin delta missing"; cat "$r/OUT.md"; exit 1; }
u="$(grep -n 'New upstream:' "$r/OUT.md" | cut -d: -f1)"
i="$(grep -n '### Build ingredients' "$r/OUT.md" | cut -d: -f1)"
[ -n "$u" ] && [ -n "$i" ] && [ "$u" -lt "$i" ] \
  || { echo "FAIL combo: upstream content should precede ingredients"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/previous-release-tag.sh -- the only remaining `|| true` on a fact-bearing call:
#       a nonzero exit from this script (e.g. it cannot list tags) used to be swallowed into
#       PREV="",
#       which reads exactly like a genuine first release, silently dropping the ingredient
#       section and the compare link on a release that may have both. An EMPTY result must stay
#       legitimate; only a NONZERO exit is fatal, so this stubs the script to fail outright rather
#       than to print nothing: previous-release-tag.sh itself failing must not read as "no
#       baseline".
r="$work/prevtagfails"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 )
scripts_stub="$work/scripts-stub"
cp -R "$here/../scripts" "$scripts_stub"
printf '#!/bin/sh\necho "previous-release-tag.sh: boom, cannot list tags" >&2\nexit 7\n' \
  > "$scripts_stub/previous-release-tag.sh"
chmod +x "$scripts_stub/previous-release-tag.sh"
if ( cd "$r" && MAVERGREEN_REPO_ROOT="$r" sh "$scripts_stub/release-notes.sh" --tag 9.9p2-mavergreen.1 \
       --version 9.9p2-mavergreen.1 --product OpenSSH --out "$r/OUT.md" ) >/dev/null 2>&1; then
  echo "FAIL prevtagfails: a failing previous-release-tag.sh must be fatal, not read as no baseline"; exit 1
fi
prevtag_out="$(cd "$r" && MAVERGREEN_REPO_ROOT="$r" sh "$scripts_stub/release-notes.sh" --tag 9.9p2-mavergreen.1 \
       --version 9.9p2-mavergreen.1 --product OpenSSH --out "$r/OUT.md" 2>&1 || true)"
printf '%s\n' "$prevtag_out" | grep -qi 'previous-release-tag' \
  || { echo "FAIL prevtagfails: cause not named: $prevtag_out"; exit 1; }

r="$work/args"; mkrepo "$r"; ( cd "$r" && git tag 9.9p2-mavergreen.1 )
if ( cd "$r" && MAVERGREEN_REPO_ROOT="$r" sh "$S" --tag 9.9p2-mavergreen.1 --version 9.9p2-mavergreen.1 \
       --out "$r/OUT.md" ) >/dev/null 2>&1; then echo "FAIL args: --product must be required"; exit 1; fi

# spec: scripts/release-notes.sh -- a release with no --min-os floor and no compare link (e.g.,
#       swift-toolchain in a fixture with no remote). The old code printed the footer rule
#       unconditionally and then
#       conditionally appended the floor/link, so a body with neither ended in a dangling <hr>
#       and nothing after it -- the footer '---' must not be emitted with nothing after it.
r="$work/nofooter"; mkdir -p "$r/.mavergreen/release-notes"
( cd "$r" && git init -q -b main . && git config user.email t@example.com && git config user.name tester )
( cd "$r" && echo x > README.md && git add -A && git commit -qm base && git tag v1.0.0 )
( cd "$r" && MAVERGREEN_REPO_ROOT="$r" sh "$S" --tag v1.0.0 --version 1.0.0 \
    --product Shipyard --out "$r/OUT.md" ) >/dev/null
grep -q -- '^---$' "$r/OUT.md" \
  && { echo "FAIL G3: a footer rule with nothing after it was emitted"; cat "$r/OUT.md"; exit 1; }
[ -n "$(tail -1 "$r/OUT.md")" ] \
  || { echo "FAIL: the body must still end with real content, not a blank trailer left behind by the buffering: body ends with a blank line"; cat "$r/OUT.md"; exit 1; }
sh "$here/../scripts/check-release-notes.sh" "$r/OUT.md" 1.0.0 >/dev/null \
  || { echo "FAIL G3: no-footer body should still pass the family shape check"; exit 1; }

# spec: scripts/release-notes.sh -- but when a floor line applies, the rule must still be
#       emitted, right above it.
r="$work/withfooter"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 )
gen "$r" 9.9p2-mavergreen.1 >/dev/null
grep -q -- '^---$' "$r/OUT.md" || { echo "FAIL G3: footer rule missing when a floor line applies"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- "126" is the shape a human reaches for (it's golang's own
#       product id, GO_LINE) but the line glob is a PREFIX of the real tags
#       (1.26.7-mavergreen.N), so it must be "1.26" -- "126"
#       matches nothing. The existing "no visible tags" guard above only checks $UP-mavergreen.*
#       (1.26.7-mavergreen.*, which this fixture's own tag satisfies), so it does not cover this:
#       LINE is the one input it never looks at. Without this check PREV comes back empty, the
#       ingredient section and compare link both vanish, and the release ships shorter than the
#       truth at exit 0 -- a --line glob that matches no tag would silently ship a repackage
#       short.
r="$work/linefatal"; mkrepo "$r"
( cd "$r" && git tag 1.26.7-mavergreen.1 )
if gen "$r" 1.26.7-mavergreen.2 --product Go --line 126 --min-os 10.9.5 >/dev/null 2>&1; then
  echo "FAIL linefatal: --line matching no tag must be fatal for a repackage"; exit 1
fi
out="$(gen "$r" 1.26.7-mavergreen.2 --product Go --line 126 --min-os 10.9.5 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'matches no' \
  || { echo "FAIL linefatal: error must name the unmatched line glob: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '1\.26' \
  || { echo "FAIL linefatal: error must show the shape the tags actually carry: $out"; exit 1; }

gen "$r" 1.26.7-mavergreen.2 --product Go --line 1.26 --min-os 10.9.5 >/dev/null
grep -q 'compare/1\.26\.7-mavergreen\.1\.\.\.1\.26\.7-mavergreen\.2' "$r/OUT.md" \
  || { echo "FAIL linefatal: a correct --line still yields a compare link"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- N=1 is a genuine first release of a line and has no
#       baseline, so an unmatched --line must NOT be fatal for it -- that IS what a first release
#       of a new line looks like.
r="$work/linefatal-first"; mkrepo "$r"
gen "$r" 1.27.0-mavergreen.1 --product Go --line 1.27 --min-os 10.9.5 >/dev/null
grep -q '^## Go 1.27.0 (1.27.0-mavergreen.1)$' "$r/OUT.md" \
  || { echo "FAIL linefatal-first: first release of a line still generates"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/gen_appcast.sh's renderer is what a 10.9 user's Sparkle dialog actually shows.
#       Markdown joins consecutive lines into ONE <p> (that is correct Markdown), but
#       release-notes.sh used to emit the floor line and the compare link back-to-back with no
#       blank line between them. Rendered, that is one run-on sentence whose second half is a
#       link ("Requires Mac OS X 10.9.5 or later. All changes since 9.9p2-mavergreen.5"). An
#       assertion on the MARKDOWN would pass whether or not this is fixed -- the markdown was
#       never the problem -- so this asserts on the rendered HTML, via gen_appcast.sh
#       --render-notes, not on OUT.md: the footer's lines are separate statements and must
#       render as separate paragraphs.
r="$work/footerpara"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null
html="$(sh "$here/../scripts/gen_appcast.sh" --render-notes "$r/OUT.md")"
printf '%s\n' "$html" | grep -q '<p>Requires Mac OS X 10\.9\.5 or later\.</p>' \
  || { echo "FAIL footerpara: the install floor must be its own paragraph in the Sparkle dialog"; printf '%s\n' "$html"; exit 1; }
printf '%s\n' "$html" | grep -q 'or later\..*<a href' \
  && { echo "FAIL footerpara: the compare link is welded onto the install-floor sentence"; printf '%s\n' "$html"; exit 1; }

# spec: scripts/release-notes.sh -- a trailing machine-readable marker (the release-doctrine
#       session appends one before packaging) must also stand alone rather than trailing a
#       sentence a human is reading. This script cannot enforce that on an append that happens
#       afterwards in a different
#       repository's script -- it can only get its OWN footer right -- so this simulates that
#       append and checks the marker does not fuse to it either.
printf 'Mavergreen-State: v1:sha256:3f786850e387550fdab836ed7e6dc881de23001b\n' >> "$r/OUT.md"
html="$(sh "$here/../scripts/gen_appcast.sh" --render-notes "$r/OUT.md")"
printf '%s\n' "$html" | grep -q 'or later\..*sha256' \
  && { echo "FAIL footerpara: a state marker must not render inside the install-floor sentence"; printf '%s\n' "$html"; exit 1; }

# spec: scripts/patch-notes.sh -- a repackage that changes OUR modifications to the upstream source
#       is a behaviour change: tailscale 1.102.4-mavergreen.7 added patches/darwin-exit-nodes.patch
#       (exit nodes on macOS) and its notes called it "packaging changes only". Patches are the
#       behaviour change, so their section comes FIRST, before any ingredient section.
r="$work/patchadd"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 && mkdir patches && echo p > patches/darwin-exit-nodes.patch \
    && git add -A && git commit -qm "exit nodes" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null
grep -q 'packaging changes only' "$r/OUT.md" \
  && { echo "FAIL patchadd: a patch change is not packaging-only"; cat "$r/OUT.md"; exit 1; }
grep -q '^- Repackage of upstream OpenSSH 9.9p2 with changes to our patches (below)\.$' "$r/OUT.md" \
  || { echo "FAIL patchadd: kind"; cat "$r/OUT.md"; exit 1; }
grep -q '^  No upstream change\.$' "$r/OUT.md" || { echo "FAIL patchadd: no-upstream line"; cat "$r/OUT.md"; exit 1; }
grep -q '^### Our patches$' "$r/OUT.md" || { echo "FAIL patchadd: section"; cat "$r/OUT.md"; exit 1; }
grep -q '^- Added `patches/darwin-exit-nodes.patch`$' "$r/OUT.md" \
  || { echo "FAIL patchadd: bullet"; cat "$r/OUT.md"; exit 1; }
grep -q '### Build ingredients' "$r/OUT.md" && { echo "FAIL patchadd: no pin moved"; exit 1; }

# spec: scripts/patch-notes.sh -- an overlay is a modification even when it is not a .patch
#       (tailscale's replacement systray_darwin.m); removal and rename count too.
r="$work/patchmisc"; mkrepo "$r"
mkdir -p "$r/overlays" "$r/patches"
echo 'int x;' > "$r/overlays/systray_darwin.m"; echo a > "$r/patches/gone.patch"
printf '1\n2\n3\n4\n5\n6\n' > "$r/patches/before.patch"
( cd "$r" && git add -A && git commit -qm overlays && git tag 9.9p2-mavergreen.1 \
    && echo 'int y;' > overlays/systray_darwin.m && git rm -q patches/gone.patch \
    && git mv patches/before.patch patches/after.patch \
    && git add -A && git commit -qm "touch overlays" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null
grep -q '^- Changed `overlays/systray_darwin.m`$' "$r/OUT.md" || { echo "FAIL patchmisc: changed"; cat "$r/OUT.md"; exit 1; }
grep -q '^- Removed `patches/gone.patch`$' "$r/OUT.md" || { echo "FAIL patchmisc: removed"; cat "$r/OUT.md"; exit 1; }
grep -q '^- Renamed `patches/before.patch` to `patches/after.patch`$' "$r/OUT.md" \
  || { echo "FAIL patchmisc: renamed"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- patches AND ingredients moved -> both named in the summary,
#       patches section first.
r="$work/patching"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 && mkdir patches && echo p > patches/fix.patch \
    && printf '3.9.2\n' > .mavergreen/ingredients/libressl/VERSION \
    && git add -A && git commit -qm "both" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null
grep -q '^- Repackage of upstream OpenSSH 9.9p2, rebuilt because build ingredients moved and our patches changed (below)\.$' "$r/OUT.md" \
  || { echo "FAIL patching: kind"; cat "$r/OUT.md"; exit 1; }
grep -q '^  No upstream change\.$' "$r/OUT.md" || { echo "FAIL patching: no-upstream line"; cat "$r/OUT.md"; exit 1; }
p="$(grep -n '^### Our patches$' "$r/OUT.md" | cut -d: -f1)"
i="$(grep -n '^### Build ingredients$' "$r/OUT.md" | cut -d: -f1)"
[ -n "$p" ] && [ -n "$i" ] && [ "$p" -lt "$i" ] \
  || { echo "FAIL patching: patches section must precede ingredients"; cat "$r/OUT.md"; exit 1; }
sh "$here/../scripts/check-release-notes.sh" "$r/OUT.md" 9.9p2-mavergreen.2 >/dev/null \
  || { echo "FAIL patching: own output fails the shape check"; exit 1; }

# spec: scripts/release-notes.sh -- a new upstream often rebases our patches -- keep the
#       new-upstream line, add the section.
r="$work/patchnewup"; mkrepo "$r"
mkdir -p "$r/patches"; echo v1 > "$r/patches/fix.patch"
( cd "$r" && git add -A && git commit -qm p && git tag 9.9p1-mavergreen.1 \
    && echo v2 > patches/fix.patch && git commit -qam rebase && git tag 9.9p2-mavergreen.1 )
gen "$r" 9.9p2-mavergreen.1 >/dev/null
grep -q 'New upstream: OpenSSH 9.9p2 (was 9.9p1)' "$r/OUT.md" || { echo "FAIL patchnewup: kind"; cat "$r/OUT.md"; exit 1; }
grep -q '^- Changed `patches/fix.patch`$' "$r/OUT.md" || { echo "FAIL patchnewup: section"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/patch-notes.sh -- committed prose under .mavergreen/release-notes/ is not a modification of
#       upstream.
r="$work/patchprose"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 && printf 'Words.\n<!-- edited by a human -->\n' > .mavergreen/release-notes/README.md \
    && git add -A && git commit -qm prose && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null
grep -q '^- Repackage of upstream OpenSSH 9.9p2; packaging changes only\.$' "$r/OUT.md" \
  || { echo "FAIL patchprose: prose alone is packaging-only"; cat "$r/OUT.md"; exit 1; }
grep -q '### Our patches' "$r/OUT.md" && { echo "FAIL patchprose: no section"; exit 1; }

# spec: scripts/release-notes.sh -- with no patch change the body is byte-identical to what it
#       was before patch-notes existed.
r="$work/patchnone"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 && echo x >> README.md && git add -A \
    && git commit -qm unrelated && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null
want="$(printf '%s\n' '## OpenSSH 9.9p2 (9.9p2-mavergreen.2)' '' '### What changed' \
  '- Repackage of upstream OpenSSH 9.9p2; packaging changes only.' '' '---' \
  'Requires Mac OS X 10.9.5 or later.' '' \
  '[All changes since 9.9p2-mavergreen.1](https://github.com/Mavergreen/mavericks-openssh/compare/9.9p2-mavergreen.1...9.9p2-mavergreen.2)')"
[ "$(cat "$r/OUT.md")" = "$want" ] || { echo "FAIL patchnone: body changed"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- notes that cannot say whether our patches changed must not
#       ship.
r="$work/patchfails"; mkrepo "$r"
( cd "$r" && git tag 9.9p2-mavergreen.1 && git tag 9.9p2-mavergreen.2 )
pstub="$work/scripts-pstub"
cp -R "$here/../scripts" "$pstub"
printf '#!/bin/sh\necho "patch-notes.sh: boom" >&2\nexit 5\n' > "$pstub/patch-notes.sh"
if ( cd "$r" && MAVERGREEN_REPO_ROOT="$r" sh "$pstub/release-notes.sh" --tag 9.9p2-mavergreen.2 \
       --version 9.9p2-mavergreen.2 --product OpenSSH --out "$r/OUT.md" ) >/dev/null 2>&1; then
  echo "FAIL patchfails: a failing patch-notes.sh must be fatal"; exit 1
fi
out="$(cd "$r" && MAVERGREEN_REPO_ROOT="$r" sh "$pstub/release-notes.sh" --tag 9.9p2-mavergreen.2 \
       --version 9.9p2-mavergreen.2 --product OpenSSH --out "$r/OUT.md" 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'patches' || { echo "FAIL patchfails: cause not named: $out"; exit 1; }

# spec: SKILL.md "Release notes" -- a self-upstream release says why it was cut, as a port's does:
#       an ingredient-only YYYYMMDD.N repackage that read "Release of <product> <version>." looked
#       like new code.
selfgen() {  # $1 = repo, $2 = tag/version, rest = extra env assignments
  r="$1"; v="$2"; shift 2
  ( cd "$r" && env MAVERGREEN_REPO_ROOT="$r" "$@" sh "$S" --tag "$v" --version "$v" --product Porthole \
      --out "$r/OUT.md" ) >/dev/null
}
r="$work/r3first"; mkrepo "$r"
selfgen "$r" 20260802.1
grep -qx -- '- First release of Porthole 20260802.1\.' "$r/OUT.md" \
  || { echo "FAIL r3first"; cat "$r/OUT.md"; exit 1; }

r="$work/r3ing"; mkrepo "$r"
( cd "$r" && git tag 20260802.1 && printf '3.9.2\n' > .mavergreen/ingredients/libressl/VERSION \
    && git commit -qam "bump libressl" )
selfgen "$r" 20260802.2
grep -qx -- '- Rebuilt because build ingredients moved (below); no change to Porthole itself\.' "$r/OUT.md" \
  || { echo "FAIL r3ing"; cat "$r/OUT.md"; exit 1; }
grep -q '^### Build ingredients$' "$r/OUT.md" || { echo "FAIL r3ing: section"; cat "$r/OUT.md"; exit 1; }

r="$work/r3pkg"; mkrepo "$r"
( cd "$r" && git tag 20260802.1 && echo x >> README.md && git add -A && git commit -qm unrelated )
selfgen "$r" 20260802.2
grep -qx -- '- Repackage of Porthole 20260802; packaging changes only\.' "$r/OUT.md" \
  || { echo "FAIL r3pkg"; cat "$r/OUT.md"; exit 1; }

r="$work/r3new"; mkrepo "$r"
( cd "$r" && git tag 20260802.3 && echo x >> README.md && git add -A && git commit -qm code )
selfgen "$r" 20260815.1 GITHUB_REPOSITORY=Mavergreen/porthole-fork
grep -qx -- '- New release of Porthole 20260815.1 (was 20260802.3)\.' "$r/OUT.md" \
  || { echo "FAIL r3new"; cat "$r/OUT.md"; exit 1; }
grep -qx -- '  \[Changes since 20260802.3\](https://github.com/Mavergreen/porthole-fork/compare/20260802.3...20260815.1)' "$r/OUT.md" \
  || { echo "FAIL r3new: GITHUB_REPOSITORY names the compare"; cat "$r/OUT.md"; exit 1; }

# spec: SKILL.md "Release notes" -- with no GITHUB_REPOSITORY, the origin remote names the repo; with
#       neither, the link line is left out rather than guessed.
( cd "$r" && git remote add origin https://github.com/Someone/porthole.git )
selfgen "$r" 20260815.1 GITHUB_REPOSITORY=
grep -qx -- '  \[Changes since 20260802.3\](https://github.com/Someone/porthole/compare/20260802.3...20260815.1)' "$r/OUT.md" \
  || { echo "FAIL r3new: the origin remote names the compare"; cat "$r/OUT.md"; exit 1; }
( cd "$r" && git remote remove origin )
( cd "$r" && env MAVERGREEN_REPO_ROOT="$r" GITHUB_REPOSITORY= sh "$S" --tag 20260815.1 --version 20260815.1 \
    --product Unregistered --out "$r/OUT.md" ) >/dev/null
grep -qx -- '- New release of Unregistered 20260815.1 (was 20260802.3)\.' "$r/OUT.md" \
  || { echo "FAIL r3new: unregistered"; cat "$r/OUT.md"; exit 1; }
grep -q 'Changes since' "$r/OUT.md" && { echo "FAIL r3new: no repo, so no guessed link"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- a vX.Y.Z self-upstream's tag carries a v its version does not, so
#       the compare names the tags.
r="$work/r3v"; mkrepo "$r"
( cd "$r" && git tag v1.0.208 && echo x >> README.md && git add -A && git commit -qm code )
( cd "$r" && env MAVERGREEN_REPO_ROOT="$r" GITHUB_REPOSITORY=Mavergreen/shipyard sh "$S" --tag v1.0.209 \
    --version 1.0.209 --product Shipyard --out "$r/OUT.md" ) >/dev/null
grep -qx -- '- New release of Shipyard 1.0.209 (was 1.0.208)\.' "$r/OUT.md" \
  || { echo "FAIL r3v"; cat "$r/OUT.md"; exit 1; }
grep -qx -- '  \[Changes since v1.0.208\](https://github.com/Mavergreen/shipyard/compare/v1.0.208...v1.0.209)' "$r/OUT.md" \
  || { echo "FAIL r3v: link"; cat "$r/OUT.md"; exit 1; }

r="$work/r1d"; mkrepo "$r"
mkdir -p "$r/patches" "$r/vendor"
printf 'Subject: [PATCH] one\n' > "$r/patches/x.patch"; printf 'line one\n' > "$r/vendor/cacert.pem"
printf 'patches/*.patch\nvendor/cacert.pem\n' > "$r/.mavergreen/ingredients/libressl/watch"
( cd "$r" && git add -A && git commit -qm pins && git tag 9.9p2-mavergreen.1 )
printf 'Subject: [PATCH] one\n+x\n' > "$r/patches/x.patch"; printf 'line one\nline two\n' > "$r/vendor/cacert.pem"
( cd "$r" && git commit -qam "move watched files" && git tag 9.9p2-mavergreen.2 )
gen "$r" 9.9p2-mavergreen.2 >/dev/null || { echo "FAIL r1d: watched files ship"; exit 1; }
grep -qx -- '- \*\*libressl / watch\*\*: `patches/x.patch` changed' "$r/OUT.md" \
  || { echo "FAIL r1d: patch"; cat "$r/OUT.md"; exit 1; }
grep -qx -- '- \*\*libressl / watch\*\*: `vendor/cacert.pem` changed' "$r/OUT.md" \
  || { echo "FAIL r1d: blob"; cat "$r/OUT.md"; exit 1; }
grep -q '### Our patches' "$r/OUT.md" && { echo "FAIL r1d: a watched patch is reported once, as its ingredient"; cat "$r/OUT.md"; exit 1; }

# spec: scripts/release-notes.sh -- "First release" is a claim, so a self-upstream checkout that
#       simply lacks its tags must not make it: YYYYMMDD.N with N > 1 says earlier releases exist, and
#       in CI the repo's own releases say so for any scheme.
r="$work/m4"; mkrepo "$r"
if out="$(cd "$r" && env MAVERGREEN_REPO_ROOT="$r" sh "$S" --tag 20260802.3 --version 20260802.3 \
    --product Porthole --out "$r/OUT.md" 2>&1)"; then
  echo "FAIL m4: 20260802.3 with no tags visible is not a first release"; cat "$r/OUT.md"; exit 1
fi
printf '%s\n' "$out" | grep -q 'fetch-depth: 0' || { echo "FAIL m4: name the fix: $out"; exit 1; }
stub="$work/m4-bin"; mkdir -p "$stub"
printf '#!/bin/sh\nprintf "%%s\\n" "${M4_RELEASE:-}"\n' > "$stub/gh"; chmod +x "$stub/gh"
if out="$(cd "$r" && env PATH="$stub:$PATH" M4_RELEASE=v1.0.208 GITHUB_ACTIONS=true \
    GITHUB_REPOSITORY=Mavergreen/shipyard MAVERGREEN_REPO_ROOT="$r" sh "$S" --tag v1.0.209 \
    --version 1.0.209 --product Shipyard --out "$r/OUT.md" 2>&1)"; then
  echo "FAIL m4: the repo has releases, so no tags here means unfetched tags"; cat "$r/OUT.md"; exit 1
fi
printf '%s\n' "$out" | grep -q 'fetch-depth: 0' || { echo "FAIL m4: name the fix: $out"; exit 1; }
( cd "$r" && env PATH="$stub:$PATH" M4_RELEASE= GITHUB_ACTIONS=true GITHUB_REPOSITORY=Mavergreen/shipyard \
    MAVERGREEN_REPO_ROOT="$r" sh "$S" --tag v1.0.0 --version 1.0.0 --product Shipyard --out "$r/OUT.md" ) >/dev/null \
  || { echo "FAIL m4: a repo with no releases yet is a first release"; exit 1; }
grep -qx -- '- First release of Shipyard 1.0.0\.' "$r/OUT.md" || { echo "FAIL m4: first"; cat "$r/OUT.md"; exit 1; }
# spec: tests/release-notes-test.sh "m4" -- a gh that cannot list (no GH_TOKEN on the step) proves
#       nothing, so it warns and trusts the checkout rather than refusing a first release.
printf '#!/bin/sh\necho "gh: To use GitHub CLI in a GitHub Actions workflow, set the GH_TOKEN environment variable" >&2\nexit 4\n' > "$stub/gh"; chmod +x "$stub/gh"
( cd "$r" && env PATH="$stub:$PATH" GITHUB_ACTIONS=true GITHUB_REPOSITORY=Mavergreen/shipyard \
    MAVERGREEN_REPO_ROOT="$r" sh "$S" --tag v1.0.0 --version 1.0.0 --product Shipyard --out "$r/OUT.md" ) > "$work/m4-gh.out" 2>&1 \
  || { echo "FAIL m4: a gh that cannot list must not refuse a first release: $(cat "$work/m4-gh.out")"; exit 1; }
grep -q 'cannot list' "$work/m4-gh.out" || { echo "FAIL m4: say that the releases could not be checked: $(cat "$work/m4-gh.out")"; exit 1; }

echo "PASS: release-notes"
