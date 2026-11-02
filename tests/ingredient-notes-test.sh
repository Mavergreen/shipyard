#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/ingredient-notes.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL $*"; exit 1; }

A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
H1=1111111111111111111111111111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222222222222222222222222222
REL='# renovate: datasource=github-releases'

ing() {  # name file value [line2]
  mkdir -p ".mavergreen/ingredients/$1"
  if [ "$#" -ge 4 ]; then printf '%s\n%s\n' "$3" "$4" > ".mavergreen/ingredients/$1/$2"
  else printf '%s\n' "$3" > ".mavergreen/ingredients/$1/$2"; fi
}
meta() {  # name description
  mkdir -p ".mavergreen/ingredients/$1"
  printf '%s\n' "$2" > ".mavergreen/ingredients/$1/description"
  printf 'build-only\n' > ".mavergreen/ingredients/$1/role"
  printf 'a fixture\n' > ".mavergreen/ingredients/$1/why"
}

r="$work/r"; mkdir -p "$r"; cd "$r"
git init -q -b main .
git config user.email t@example.com; git config user.name tester

meta cmake 'The Mavergreen cmake product'
ing cmake VERSION 4.4.4-mavericks.1 "$REL depName=Mavergreen/cmake versioning=regex:^(?<major>\\d+)\$"
ing cmake REPO Mavergreen/cmake
meta clang22 "The family's LLVM 22 toolchain"
ing clang22 VERSION 22.1.8-mavericks.11 "$REL depName=Mavergreen/clang-22"
ing clang22 LINUX_SHA256 "$H1"
meta swift 'Swift'
ing swift VERSION 6.3.3 '# renovate: datasource=github-tags depName=swiftlang/swift extractVersion=^swift-(?<version>.+)-RELEASE$'
meta libgit 'libgit2, pinned to a commit'
ing libgit PIN "v1.0@$A"
ing libgit REPO https://github.com/libgit2/libgit2.git
printf 'no manager reads it\n' > .mavergreen/ingredients/libgit/untracked
meta zlib 'zlib'
ing zlib VERSION 1.3
printf 'frozen\n' > .mavergreen/ingredients/zlib/untracked
meta pyyaml 'PyYAML'
ing pyyaml VERSION 6.0.2 '# renovate: datasource=pypi depName=PyYAML'
ing pyyaml SHA256 "$H1"
meta guess 'a template that cannot say which tag exists'
ing guess VERSION 1.0 '# renovate: datasource=github-tags depName=foo/bar extractVersion=^v?(?<version>.+)$'
meta gone 'an ingredient that goes'
ing gone VERSION 1.0
meta steady 'unchanged'
printf '2.0' > .mavergreen/ingredients/steady/VERSION
meta child 'built from the upstream'
ing child from self
meta sparkle 'Sparkle 1.x'
printf 'the version is a literal\n' > .mavergreen/ingredients/sparkle/untracked
printf 'MavericksSparkle.cmake\n' > .mavergreen/ingredients/sparkle/watch
printf 'set(SPARKLE 1.26.0)\n' > MavericksSparkle.cmake
git add -A; git commit -qm base; git tag 1.0-mavericks.1

out="$(sh "$S" 1.0-mavericks.1)"
[ -z "$out" ] || fail "unchanged: nothing moved prints nothing, so callers append unconditionally: '$out'"
out="$(sh "$S" "")"
[ -z "$out" ] || fail "no-prev: '$out'"
if sh "$S" no-such-tag >/dev/null 2>&1; then fail "badprev: a baseline git cannot read must be fatal"; fi

ing cmake VERSION 4.4.5-mavericks.2 "$REL depName=Mavergreen/cmake versioning=regex:^(?<major>\\d+)\$"
ing clang22 VERSION 22.1.8-mavericks.12 "$REL depName=Mavergreen/clang-22"
ing clang22 LINUX_SHA256 "$H2"
ing swift VERSION 6.4.1 '# renovate: datasource=github-tags depName=swiftlang/swift extractVersion=^swift-(?<version>.+)-RELEASE$'
ing libgit PIN "v1.1@$B"
ing zlib VERSION 1.3.1
ing zlib SHA256 "$H2"
ing pyyaml VERSION 6.0.3 '# renovate: datasource=pypi depName=PyYAML'
rm .mavergreen/ingredients/pyyaml/SHA256
ing guess VERSION 1.1 '# renovate: datasource=github-tags depName=foo/bar extractVersion=^v?(?<version>.+)$'
rm -r .mavergreen/ingredients/gone
printf '2.0\r\n' > .mavergreen/ingredients/steady/VERSION
printf 'described anew\n' > .mavergreen/ingredients/steady/description
printf 'linked\n' > .mavergreen/ingredients/steady/role
ing child from cmake
meta newone 'lazydocker'
ing newone VERSION 0.24.1 "$REL depName=jesseduffield/lazydocker extractVersion=^v(?<version>.+)\$"
printf 'set(SPARKLE 1.27.0)\n' > MavericksSparkle.cmake

out="$(sh "$S" 1.0-mavericks.1)"
cat > "$work/want" <<EOF
### Build ingredients

Changed since 1.0-mavericks.1:

- **child / from**: self -> cmake
  built from the upstream
- **clang22 / LINUX_SHA256**: 111111111111... -> 222222222222... ([release notes](https://github.com/Mavergreen/clang-22/releases/tag/22.1.8-mavericks.12))
  The family's LLVM 22 toolchain
- **clang22 / VERSION**: 22.1.8-mavericks.11 -> 22.1.8-mavericks.12 ([release notes](https://github.com/Mavergreen/clang-22/releases/tag/22.1.8-mavericks.12))
- **cmake / VERSION**: 4.4.4-mavericks.1 -> 4.4.5-mavericks.2 ([release notes](https://github.com/Mavergreen/cmake/releases/tag/4.4.5-mavericks.2))
  The Mavergreen cmake product
- **gone**: removed
- **guess / VERSION**: 1.0 -> 1.1
  a template that cannot say which tag exists
- **libgit / PIN**: v1.0@aaaaaaaaaaaa -> v1.1@bbbbbbbbbbbb ([changes](https://github.com/libgit2/libgit2/compare/$A...$B))
  libgit2, pinned to a commit
- **newone**: added (0.24.1) ([release notes](https://github.com/jesseduffield/lazydocker/releases/tag/v0.24.1))
  lazydocker
- **pyyaml / SHA256**: removed
  PyYAML
- **pyyaml / VERSION**: 6.0.2 -> 6.0.3
- **sparkle / watch**: \`MavericksSparkle.cmake\` changed
  Sparkle 1.x
- **swift / VERSION**: 6.3.3 -> 6.4.1 ([changes](https://github.com/swiftlang/swift/compare/swift-6.3.3-RELEASE...swift-6.4.1-RELEASE))
  Swift
- **zlib / SHA256**: added (222222222222...)
  zlib
- **zlib / VERSION**: 1.3 -> 1.3.1
EOF
want="$(cat "$work/want")"
[ "$out" = "$want" ] || { echo "FAIL two trees: got:"; printf '%s\n' "$out"; echo "want:"; printf '%s\n' "$want"; exit 1; }
printf '%s\n' "$out" | LC_ALL=C grep -q '[^ -~]' && fail "ASCII only, since the notes are embedded in appcast XML: $out"

ing libgit REPO https://gitlab.com/libgit2/libgit2.git
out="$(sh "$S" 1.0-mavericks.1)"
printf '%s\n' "$out" | grep -qx -- "- \*\*libgit / PIN\*\*: v1.0@aaaaaaaaaaaa -> v1.1@bbbbbbbbbbbb" \
  || fail "a REPO off GitHub links nothing: $out"
printf '%s\n' "$out" | grep -qx -- "- \*\*libgit / REPO\*\*: https://github.com/libgit2/libgit2.git -> https://gitlab.com/libgit2/libgit2.git" \
  || fail "REPO is a value file too: $out"

r="$work/first"; mkdir -p "$r"; cd "$r"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
printf '4.4.4\n' > CMAKE_VERSION
git add -A; git commit -qm base; git tag v1.0.1
meta cmake 'The Mavergreen cmake product'
ing cmake VERSION 4.4.5-mavericks.2 "$REL depName=Mavergreen/cmake"
meta zlib zlib
ing zlib VERSION 1.3.1
out="$(sh "$S" v1.0.1)"
[ "$out" = '- Ingredients moved to .mavergreen/; no per-pin changes listed for this release.' ] \
  || fail "a previous tag with no .mavergreen/ prints the one line, never a bullet per pin: '$out'"

r="$work/none"; mkdir -p "$r/.mavergreen/upstream"; cd "$r"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
printf '1.0\n' > .mavergreen/upstream/VERSION
git add -A; git commit -qm base; git tag v1.0.1
printf '1.1\n' > .mavergreen/upstream/VERSION
out="$(sh "$S" v1.0.1)"
[ -z "$out" ] || fail "no ingredients at either tree prints nothing: '$out'"

echo "PASS: ingredient-notes"
