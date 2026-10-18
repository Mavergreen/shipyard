#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/ingredient-notes.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; trap 'rm -rf "$work"' EXIT
cd "$work"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p components/golang components/docker-cli vendor
printf '1.26.4-mavericks.3\n' > components/golang/version
printf '28.6.0\n'             > components/docker-cli/version
cat > versions.sh <<'SH'
export MLS_VERSION=1.5.1-mavericks.1   # mavericks-legacysupport
export CA_SHA256="3ff344e30b9b1ed2971044eabb438a08f2e2245ddb5f8ab1a3ad8b63ab4eaf91"
export MACOS_MIN="10.9"
export GO_SRC_SHA512="adacc6a34ad239d98277acd2ac8da867110da0b184dbbafb82e8a06d2b7fd234"
export GO_VERSION="$(upstream_version)"
export PKG_VERSION=`cat "$REPO_ROOT/UPSTREAM_VERSION"`
SH
printf 'line one\nline two\nline three\n' > vendor/cacert.pem
git add -A; git commit -qm base; git tag 20260727-mavericks.2

out="$(sh "$S" 20260727-mavericks.2 components/golang/version versions.sh)"
[ -z "$out" ] || { echo "FAIL: nothing changed yet must produce no section at all, since callers append unconditionally: got '$out'"; exit 1; }

out="$(sh "$S" "" components/golang/version)"
[ -z "$out" ] || { echo "FAIL no-prev: got '$out'"; exit 1; }

printf '1.26.5-mavericks.1\n' > components/golang/version
printf '28.6.1\n'             > components/docker-cli/version
cat > versions.sh <<'SH'
export MLS_VERSION=1.5.2-mavericks.1   # mavericks-legacysupport
export CA_SHA256="9a1c72b4aa0f1e8d5c3b7e6f2d4a8091ccee5577bb33ff11aa99887766554433"
export MACOS_MIN="10.9"
export GO_VERSION="$(upstream_version_v2)"
export PKG_VERSION=`sh "$REPO_ROOT/build/version.sh" auto`
SH
printf 'line one\nline two\nline three\nline four\n' > vendor/cacert.pem
mkdir -p components/lazydocker
printf '0.24.1\n' > components/lazydocker/version   # a pin that did not exist at the prev tag

out="$(sh "$S" 20260727-mavericks.2 components/golang/version components/docker-cli/version \
        versions.sh vendor/cacert.pem components/lazydocker/version)"
printf '%s\n' "$out" | grep -q '^### Build ingredients$' \
  || { echo "FAIL header: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'Changed since 20260727-mavericks.2:' \
  || { echo "FAIL baseline: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*golang\*\*: 1.26.4-mavericks.3 -> 1.26.5-mavericks.1' \
  || { echo "FAIL: whole-file pins must be named by component directory: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*docker-cli\*\*: 28.6.0 -> 28.6.1' \
  || { echo "FAIL second pin: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*MLS_VERSION\*\*: 1.5.1-mavericks.1 -> 1.5.2-mavericks.1' \
  || { echo "FAIL: shell assignments must be named by key, matched by name not line number: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*CA_SHA256\*\*: 3ff344e30b9b... -> 9a1c72b4aa0f...' \
  || { echo "FAIL: a 64-char hash pair communicates nothing and must be shortened: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'MACOS_MIN' \
  && { echo "FAIL: an unchanged assignment in a changed file must not be mentioned: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'GO_VERSION' \
  && { echo "FAIL: COMPUTED assignments are derivations, not pinned inputs -- a rewritten \$(...) value is a code change, and reporting it is noise and misleading -- computed \$() value reported as an ingredient: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'PKG_VERSION' \
  && { echo "FAIL: COMPUTED assignments are derivations, not pinned inputs -- a rewritten \`...\` value is a code change too -- computed backtick value reported as an ingredient: $out"; exit 1; }
printf '%s\n' "$out" | grep -q -- '- \*\*vendor/cacert.pem\*\*: updated (' \
  || { echo "FAIL: an opaque multi-line blob must report that it moved, with sizes: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*lazydocker\*\*: added (0.24.1)' \
  || { echo "FAIL: a pin absent at the previous release must say added: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*GO_SRC_SHA512\*\*: removed' \
  || { echo "FAIL: a pin that STOPPED being pinned is a real change -- walking only the new file's keys would silently omit it (golang dropped GO_SRC_SHA512 exactly this way) -- removed key not reported: $out"; exit 1; }
printf '%s\n' "$out" | LC_ALL=C grep -q '[^ -~]' \
  && { echo "FAIL: output must be ASCII only, since these notes get embedded in appcast XML: $out"; exit 1; }

out="$(sh "$S" 20260727-mavericks.2 components/golang/version nosuch/file 2>/dev/null)"
printf '%s\n' "$out" | grep -q 'golang' || { echo "FAIL: a missing pin path must be skipped, not fatal: $out"; exit 1; }

# spec: scripts/ingredient-notes.sh -- a .patch IS an ingredient (it is baked into the product),
#       but "updated (N -> M bytes)" says nothing useful about one -- report what a reader can
#       act on: the subject line, and how much moved.
work2="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work2"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p patches
cat > patches/0001-keyserver.patch <<'PATCH'
From abc123 Mon Sep 17 00:00:00 2001
Subject: [PATCH] boot2docker: fetch kernel keys over HTTPS
---
 Dockerfile | 2 +-
@@ -1,2 +1,2 @@
-old line
+new line
PATCH
cat > patches/0002-plain.patch <<'PATCH'
--- a/x
+++ b/x
@@ -1 +1 @@
-a
+b
PATCH
git add -A; git commit -qm base; git tag 1.0.0-mavericks.1

printf '+another line\n' >> patches/0001-keyserver.patch
printf '+extra\n' >> patches/0002-plain.patch
cat > patches/0003-new.patch <<'PATCH'
Subject: [PATCH] modernize the tls stack
---
 y | 1 +
PATCH

out="$(sh "$S" 1.0.0-mavericks.1 patches/0001-keyserver.patch patches/0002-plain.patch patches/0003-new.patch)"
printf '%s\n' "$out" | grep -q -- '- \*\*0001-keyserver.patch\*\*: updated ("boot2docker: fetch kernel keys over HTTPS", +1/-0 lines)' \
  || { echo "FAIL patch updated: $out"; exit 1; }
printf '%s\n' "$out" | grep -q -- '- \*\*0002-plain.patch\*\*: updated (+1/-0 lines)' \
  || { echo "FAIL: a patch with no Subject: header must still report a line delta: $out"; exit 1; }
printf '%s\n' "$out" | grep -q -- '- \*\*0003-new.patch\*\*: added ("modernize the tls stack")' \
  || { echo "FAIL patch added: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'bytes' \
  && { echo "FAIL: a patch must never be reported as a byte-size delta: $out"; exit 1; }

cat > patches/0001-keyserver.patch <<'PATCH'
From abc123 Mon Sep 17 00:00:00 2001
Subject: [PATCH] boot2docker: import kernel keys from a pinned bundle
---
 Dockerfile | 2 +-
PATCH
out="$(sh "$S" 1.0.0-mavericks.1 patches/0001-keyserver.patch)"
printf '%s\n' "$out" | grep -q -- '- \*\*0001-keyserver.patch\*\*: "boot2docker: fetch kernel keys over HTTPS" -> "boot2docker: import kernel keys from a pinned bundle"' \
  || { echo "FAIL: a rewritten patch that changes what it DOES must say so, old subject -> new subject: $out"; exit 1; }
cd "$work"; rm -rf "$work2"

# spec: the swift-toolchain regression -- pins.env holds the exact same KEY=VALUE shape as pins.sh
#       under a different extension, but the dispatch was `case "$path" in *.sh)`, so pins.env
#       fell through to the generic byte-delta branch. Rendering must be decided by CONTENT, not
#       by filename extension: a rewritten DERIVED expression is a code change, not an ingredient
#       move, and pins.env must get exactly the same answer as .sh.
work3="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work3"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
cat > pins.env <<'ENV'
SWIFT_VERSION="6.3.3"
VERSION="$(cat "$HERE/VERSION")"
ENV
cp pins.env pins.sh
git add -A; git commit -qm base; git tag base

cat > pins.env <<'ENV'
SWIFT_VERSION="6.3.3"
VERSION="$(MAVERICKS_ROOT="$HERE" sh "$SHIPYARD/resolve-version.sh")"
ENV
cp pins.env pins.sh

out_env="$(sh "$S" base pins.env)"
out_sh="$(sh "$S" base pins.sh)"
[ -z "$out_env" ] \
  || { echo "FAIL G1 pins.env: derived-only rewrite falsely reported as an ingredient move: $out_env"; exit 1; }
[ "$out_env" = "$out_sh" ] \
  || { echo "FAIL G1: identical bytes disagree by extension: env='$out_env' sh='$out_sh'"; exit 1; }

cat > pins.env <<'ENV'
SWIFT_VERSION="6.3.4"
VERSION="$(MAVERICKS_ROOT="$HERE" sh "$SHIPYARD/resolve-version.sh")"
ENV
out_env2="$(sh "$S" base pins.env)"
printf '%s\n' "$out_env2" | grep -qx -- '- \*\*SWIFT_VERSION\*\*: 6.3.3 -> 6.3.4' \
  || { echo "FAIL: a REAL literal key move in a .env file must still be reported, per key -- content dispatch must not just make everything opaque: G1 pins.env real move not reported per-key: $out_env2"; exit 1; }
printf '%s\n' "$out_env2" | grep -q 'bytes' \
  && { echo "FAIL G1 pins.env: still using the opaque byte-delta fallback: $out_env2"; exit 1; }
cd "$work"; rm -rf "$work3"

# spec: ingredient-pins.sh emits "pins.env:SWIFT_VERSION" for a swift-shaped repo's own-upstream
#       key (a "path:KEY" pin argument that excludes just that KEY, not the whole file). This
#       script must honour that suffix: SWIFT_VERSION must never appear as a moved ingredient,
#       while a real ingredient key in the SAME file still must.
work4="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work4"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
printf 'SWIFT_VERSION="6.3.3"\nLLVM_SHA="aaaa"\n' > pins.env
git add -A; git commit -qm base; git tag base
printf 'SWIFT_VERSION="6.3.4"\nLLVM_SHA="bbbb"\n' > pins.env
out="$(sh "$S" base pins.env:SWIFT_VERSION)"
printf '%s\n' "$out" | grep -q 'SWIFT_VERSION' \
  && { echo "FAIL G2: own-upstream key SWIFT_VERSION leaked as an ingredient: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*LLVM_SHA\*\*: aaaa -> bbbb' \
  || { echo "FAIL G2: real ingredient key LLVM_SHA in the same file was dropped: $out"; exit 1; }
cd "$work"; rm -rf "$work4"

# platform: a real vendor/cacert.pem's base64 PADDING lines ("MrY=", "MK9=") look exactly like
#           one-line KEY=VALUE "assignments" to a lowercase- or uppercase-tolerant key class --
#           is_kv_pins()'s first cut matched them and reported them as build ingredients (with
#           the key itself as a bogus "added" value, since oldv is always empty). Uppercase-only
#           narrowed but did not close this class: an all-caps-and-digit padding line ("MK9=")
#           still matches an uppercase-only key with an empty value -- the reviewer measured
#           ~0.46 expected such lines per real CA-bundle refresh, i.e. even odds of resurrecting
#           this exact false claim a third time. The value must hold at least one non-"="
#           character (padding is only ever "=" characters, at the end; no real pin's value is
#           empty or all-"=").
work5="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work5"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p vendor
cat > vendor/cacert.pem <<'PEM'
-----BEGIN CERTIFICATE-----
MIIDdZWAUWpLMKawYqGT8ZvYzsRjdT9ZR7E=
rJgWVqA=
IhNzbM8m9Yop5w==
MrY=
MK9=
-----END CERTIFICATE-----
PEM
git add -A; git commit -qm base; git tag base
printf '\n' >> vendor/cacert.pem   # a genuine, tiny change: a real CA-bundle refresh looks like this
out="$(sh "$S" base vendor/cacert.pem)"
printf '%s\n' "$out" | grep -q -- '- \*\*vendor/cacert.pem\*\*: updated (' \
  || { echo "FAIL CRITICAL1: base64 blob no longer treated as opaque: $out"; exit 1; }
printf '%s\n' "$out" | grep -qi 'MrY\|dZWAUWpL\|IhNzbM8m9Yop5w\|MK9\|added\b' \
  && { echo "FAIL CRITICAL1: base64 padding line(s) leaked as a bogus ingredient bullet: $out"; exit 1; }
cd "$work"; rm -rf "$work5"

# spec: scripts/ingredient-notes.sh -- the other direction: the value-must-have-content guard
#       must not cost a single real pin. Every real family KV pin the reviewer's table names must
#       still render per-key.
work5b="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work5b"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p build components/tailscale
cat > build/versions.sh <<'SH'
export MLS_VERSION=1.5.2-mavericks.3
export CA_SHA256="3ff344e30b9b1ed2971044eabb438a08f2e2245ddb5f8ab1a3ad8b63ab4eaf91"
export GO_SRC_SHA512="adacc6a34ad239d98277acd2ac8da867110da0b184dbbafb82e8a06d2b7fd234"
SH
cat > pins.env <<'ENV'
SWIFT_VERSION="6.3.3"
LLVM_SHA="aaaa"
ENV
cat > build.sh <<'SH'
SWIFT_TAG="swift-6.3.3-RELEASE"
TOOLCHAIN_SHA="cccc"
SH
printf 'REPO=https://github.com/tailscale/tailscale.git\nREF=v1.102.4\nDIGEST=deadbeef\n' \
  > components/tailscale/version
git add -A; git commit -qm base; git tag base
cat > build/versions.sh <<'SH'
export MLS_VERSION=1.5.2-mavericks.4
export CA_SHA256="9a1c72b4aa0f1e8d5c3b7e6f2d4a8091ccee5577bb33ff11aa99887766554433"
export GO_SRC_SHA512="adacc6a34ad239d98277acd2ac8da867110da0b184dbbafb82e8a06d2b7fd234"
SH
printf 'SWIFT_VERSION="6.3.4"\nLLVM_SHA="bbbb"\n' > pins.env
printf 'SWIFT_TAG="swift-6.3.4-RELEASE"\nTOOLCHAIN_SHA="dddd"\n' > build.sh
printf 'REPO=https://github.com/tailscale/tailscale.git\nREF=v1.102.5\nDIGEST=cafebabe\n' \
  > components/tailscale/version
out="$(sh "$S" base build/versions.sh pins.env build.sh components/tailscale/version)"
printf '%s\n' "$out" | grep -qx -- '- \*\*MLS_VERSION\*\*: 1.5.2-mavericks.3 -> 1.5.2-mavericks.4' \
  || { echo "FAIL both-directions: build/versions.sh MLS_VERSION dropped: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*CA_SHA256\*\*: 3ff344e30b9b... -> 9a1c72b4aa0f...' \
  || { echo "FAIL both-directions: build/versions.sh CA_SHA256 dropped: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*SWIFT_VERSION\*\*: 6.3.3 -> 6.3.4' \
  || { echo "FAIL both-directions: pins.env SWIFT_VERSION dropped: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*LLVM_SHA\*\*: aaaa -> bbbb' \
  || { echo "FAIL both-directions: pins.env LLVM_SHA dropped: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*SWIFT_TAG\*\*: swift-6.3.3-RELEASE -> swift-6.3.4-RELEASE' \
  || { echo "FAIL both-directions: build.sh SWIFT_TAG dropped: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*TOOLCHAIN_SHA\*\*: cccc -> dddd' \
  || { echo "FAIL both-directions: build.sh TOOLCHAIN_SHA dropped: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*tailscale / REF\*\*: v1.102.4 -> v1.102.5 (\[changes\](https://github.com/tailscale/tailscale/compare/v1.102.4...v1.102.5))' \
  || { echo "FAIL both-directions: tailscale component REF dropped: $out"; exit 1; }
printf '%s\n' "$out" | grep -q -- 'updated (' \
  && { echo "FAIL both-directions: a real KV pin fell through to the opaque byte-delta fallback: $out"; exit 1; }
cd "$work"; rm -rf "$work5b"

# spec: scripts/ingredient-notes.sh -- container-tools' real shape is SIX components sharing the
#       same REPO=/REF=/DIGEST=/BASE= key names. Renovate can bump two components in the same
#       release (docker-cli +
#       docker-compose): a bare "REF"/"DIGEST" bullet with no component identity is ambiguous at
#       best and misattributed at worst. Prefix ALWAYS for this pin shape, not only when this run
#       happens to be ambiguous -- an unprefixed bullet that reads fine today silently becomes
#       wrong the day a second component moves.
work6="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work6"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p components/docker-cli components/docker-compose
printf 'REPO=https://github.com/docker/cli.git\nREF=v29.8.0\nDIGEST=88096ef00576baf72a9cb45caa45c0544c40e0a7\n' \
  > components/docker-cli/version
printf 'REPO=https://github.com/docker/compose.git\nREF=v5.5.1\nDIGEST=5f94fb0aa42a2cd1248c6e6c7fafb87546b9c8de\n' \
  > components/docker-compose/version
git add -A; git commit -qm base; git tag base
printf 'REPO=https://github.com/docker/cli.git\nREF=v29.9.0\nDIGEST=111111111111111111111111111111111111111\n' \
  > components/docker-cli/version
printf 'REPO=https://github.com/docker/compose.git\nREF=v2.40.0\nDIGEST=222222222222222222222222222222222222222\n' \
  > components/docker-compose/version
out="$(sh "$S" base components/docker-cli/version components/docker-compose/version)"
printf '%s\n' "$out" | grep -qx -- '- \*\*docker-cli / REF\*\*: v29.8.0 -> v29.9.0 (\[changes\](https://github.com/docker/cli/compare/v29.8.0...v29.9.0))' \
  || { echo "FAIL CRITICAL2: docker-cli REF not prefixed with its component name: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*docker-compose / REF\*\*: v5.5.1 -> v2.40.0 (\[changes\](https://github.com/docker/compose/compare/v5.5.1...v2.40.0))' \
  || { echo "FAIL CRITICAL2: docker-compose REF not prefixed with its component name: $out"; exit 1; }
printf '%s\n' "$out" | grep -q -- '- \*\*REF\*\*:' \
  && { echo "FAIL CRITICAL2: an unprefixed, ambiguous REF bullet leaked: $out"; exit 1; }
printf '%s\n' "$out" | grep -q -- '- \*\*DIGEST\*\*:' \
  && { echo "FAIL CRITICAL2: an unprefixed, ambiguous DIGEST bullet leaked: $out"; exit 1; }
cd "$work"; rm -rf "$work6"

# spec: exclkey must use the LONGEST match, like pins.sh and repackage-decision.sh --
#       ${arg#*:} (shortest) would leave the own-upstream KEY itself carrying a stray colon
#       undetected if a path ever had one; ${arg##*:} (longest) is what pins.sh and
#       repackage-decision.sh both use.
work7="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work7"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
printf 'SWIFT_VERSION="6.3.3"\nLLVM_SHA="aaaa"\n' > pins.env
git add -A; git commit -qm base; git tag base
printf 'SWIFT_VERSION="6.3.4"\nLLVM_SHA="bbbb"\n' > pins.env
out="$(sh "$S" base "pins.env:SWIFT_VERSION")"
printf '%s\n' "$out" | grep -q 'SWIFT_VERSION' \
  && { echo "FAIL longest-match exclkey: SWIFT_VERSION leaked: $out"; exit 1; }
cd "$work"; rm -rf "$work7"

# spec: scripts/ingredient-notes.sh -- a first-time pins.env (absent at the previous release)
#       used to print a single "added" bullet with the file's first line as its value -- which
#       could BE the own-upstream key's own literal value. A newly-introduced KV file must
#       render per-key, excluding $exclkey, exactly like an existing one.
work8="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work8"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
git commit -q --allow-empty -m base; git tag base
printf 'SWIFT_VERSION="6.3.3"\nLLVM_SHA="aaaa"\n' > pins.env
out="$(sh "$S" base "pins.env:SWIFT_VERSION")"
printf '%s\n' "$out" | grep -q 'SWIFT_VERSION' \
  && { echo "FAIL new-file exclkey: SWIFT_VERSION leaked on a brand-new pins.env: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*LLVM_SHA\*\*: added (aaaa)' \
  || { echo "FAIL new-file exclkey: the real ingredient key LLVM_SHA was dropped: $out"; exit 1; }
cd "$work"; rm -rf "$work8"

# spec: DELIBERATE CHOICE -- before content-based dispatch, EVERY .sh file always took the
#       per-key branch regardless of content, so a .sh with zero KEY=VALUE lines produced NO
#       bullet at all when its bytes changed (assignments() extracts nothing from either side, so
#       the diff is empty). Content-based dispatch now falls through such a file to the opaque
#       byte-delta branch instead: release-notes.sh's own doctrine is "a release that says less
#       than the truth is the defect this removes" (see its header) -- a file explicitly watched
#       as a pin that changed and says NOTHING is the same silent-gap shape, just through dispatch
#       instead of a broken hook. A vague-but-honest "updated (N -> M bytes)" is strictly more
#       truthful than silence.
work9="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work9"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
printf '#!/bin/sh\necho hello\n' > noop.sh
git add -A; git commit -qm base; git tag base
printf '#!/bin/sh\necho hello world\n' > noop.sh
out="$(sh "$S" base noop.sh)"
printf '%s\n' "$out" | grep -q -- '- \*\*noop.sh\*\*: updated (' \
  || { echo "FAIL .sh-no-assignments: expected a byte delta (deliberate choice), got: $out"; exit 1; }
cd "$work"; rm -rf "$work9"

# spec: scripts/ingredient-notes.sh -- assignments() deliberately drops any value carrying $ or
#       a backtick, since rewriting a derivation is a code change, not an ingredient move -- but
#       the removal walk used to read
#       "absent from the literal set" as "removed": SWIFT_TAG going from swift-6.3.3-RELEASE to
#       "swift-${SWIFT_VERSION}-RELEASE" (exactly the family's derive-never-repeat convention) was
#       reported as a removed pin, which is false -- the build still uses SWIFT_TAG, just no
#       longer as a literal. A pin that became DERIVED must not be announced as removed.
work10="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work10"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
cat > versions.sh <<'SH'
SWIFT_VERSION=6.3.3
SWIFT_TAG=swift-6.3.3-RELEASE
LLVM_BRANCH=swift/release/6.3
GONE=1.2.3
SH
git add -A; git commit -qm base; git tag base
cat > versions.sh <<'SH'
SWIFT_VERSION=6.3.4
SWIFT_TAG="swift-${SWIFT_VERSION}-RELEASE"
LLVM_BRANCH=swift/release/6.3
SH
out="$(sh "$S" base versions.sh)"
printf '%s\n' "$out" | grep -qx -- '- \*\*SWIFT_VERSION\*\*: 6.3.3 -> 6.3.4' \
  || { echo "FAIL derived: a moved literal is still reported as a move: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*SWIFT_TAG\*\*: still used, now computed rather than pinned (was swift-6.3.3-RELEASE)' \
  || { echo "FAIL derived: literal -> derived must say still-used/computed, not removed: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'SWIFT_TAG.*removed' \
  && { echo "FAIL derived: SWIFT_TAG is still assigned; calling it removed is false: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*GONE\*\*: removed' \
  || { echo "FAIL derived: a key that is genuinely gone is still reported as removed: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'LLVM_BRANCH' \
  && { echo "FAIL derived: an unchanged key must produce no bullet: $out"; exit 1; }
cd "$work"; rm -rf "$work10"

# spec: CRITICAL2 (above) already guards the moved and added forms of a components/*/version
#       bullet against shipping unprefixed; the now-derived form is the only other bullet shape
#       that pin file can produce, and it shipped without the same guard. DIGEST moves for real
#       (so the section opens at all); REF becomes derived and must still read "widget / REF",
#       not a bare "REF".
work11="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work11"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p components/widget
cat > components/widget/version <<'SH'
REPO=https://github.com/example/widget.git
REF=v1.2.3
DIGEST=deadbeef
SH
git add -A; git commit -qm base; git tag base
cat > components/widget/version <<'SH'
REPO=https://github.com/example/widget.git
REF="$(cat REF_PIN)"
DIGEST=cafebabe
SH
out="$(sh "$S" base components/widget/version)"
printf '%s\n' "$out" | grep -qx -- '- \*\*widget / DIGEST\*\*: deadbeef -> cafebabe' \
  || { echo "FAIL label-prefix: real move missing: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*widget / REF\*\*: still used, now computed rather than pinned (was v1.2.3)' \
  || { echo "FAIL label-prefix: derived bullet is missing its component-name prefix: $out"; exit 1; }
cd "$work"; rm -rf "$work11"

# spec: scripts/ingredient-notes.sh -- the removal walk's exclkey skip was already proven for
#       the "removed" branch (G2 above); the newly split "now derived" branch is a second place
#       the same skip can be silently dropped, so exclkey (the "path:KEY" own-upstream exclusion)
#       must suppress it too. SWIFT_VERSION is this repo's own upstream (excluded); it becomes
#       derived here and must still not appear at all.
work12="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work12"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
printf 'SWIFT_VERSION="6.3.3"\nLLVM_SHA="aaaa"\n' > pins.env
git add -A; git commit -qm base; git tag base
printf 'SWIFT_VERSION="$(cat VERSION_FILE)"\nLLVM_SHA="bbbb"\n' > pins.env
out="$(sh "$S" base pins.env:SWIFT_VERSION)"
printf '%s\n' "$out" | grep -q 'SWIFT_VERSION' \
  && { echo "FAIL exclkey-derived: own-upstream key leaked on the derived branch: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*LLVM_SHA\*\*: aaaa -> bbbb' \
  || { echo "FAIL exclkey-derived: real ingredient key in the same file was dropped: $out"; exit 1; }
cd "$work"; rm -rf "$work12"

# spec: scripts/ingredient-notes.sh -- and the REMOVED branch, for the same exclkey, so the two
#       branches cannot silently disagree.
work13="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work13"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
printf 'SWIFT_VERSION="6.3.3"\nLLVM_SHA="aaaa"\n' > pins.env
git add -A; git commit -qm base; git tag base
printf 'LLVM_SHA="bbbb"\n' > pins.env
out="$(sh "$S" base pins.env:SWIFT_VERSION)"
printf '%s\n' "$out" | grep -q 'SWIFT_VERSION' \
  && { echo "FAIL exclkey-removed: own-upstream key leaked on the removed branch: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*LLVM_SHA\*\*: aaaa -> bbbb' \
  || { echo "FAIL exclkey-removed: real ingredient key in the same file was dropped: $out"; exit 1; }
cd "$work"; rm -rf "$work13"

# spec: scripts/ingredient-notes.sh's shorten() -- TOOLCHAIN_SHA moves from a 40-char hex
#       literal to a derived expression; OTHER_KEY moves for real (so the section opens). The
#       now-derived bullet's OLD value must still be shortened, like every other hash-shaped pin.
work14="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work14"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
cat > build.sh <<'SH'
TOOLCHAIN_SHA=3ff344e30b9b1ed2971044eabb438a08f2e2245
OTHER_KEY=1
SH
git add -A; git commit -qm base; git tag base
cat > build.sh <<'SH'
TOOLCHAIN_SHA="$(cat TOOLCHAIN_SHA_FILE)"
OTHER_KEY=2
SH
out="$(sh "$S" base build.sh)"
printf '%s\n' "$out" | grep -qx -- '- \*\*OTHER_KEY\*\*: 1 -> 2' \
  || { echo "FAIL shorten-derived: real move missing: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*TOOLCHAIN_SHA\*\*: still used, now computed rather than pinned (was 3ff344e30b9b...)' \
  || { echo "FAIL shorten-derived: the derived bullet's old hex value was not shortened: $out"; exit 1; }
cd "$work"; rm -rf "$work14"

# spec: scripts/ingredient-notes.sh's own header contract says "Prints NOTHING when no pin
#       moved" (ruling E). A "still used, now computed" bullet is real information about a key,
#       but it is not evidence that anything MOVED, so a derive-only refactor (no pin actually
#       moved) must never open the "### Build ingredients" section by itself. Only SWIFT_TAG
#       changes shape here; SWIFT_VERSION (the only literal) is untouched, so nothing actually
#       moved.
work15="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work15"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
cat > versions.sh <<'SH'
SWIFT_VERSION=6.3.3
SWIFT_TAG=swift-6.3.3-RELEASE
SH
git add -A; git commit -qm base; git tag base
cat > versions.sh <<'SH'
SWIFT_VERSION=6.3.3
SWIFT_TAG="swift-${SWIFT_VERSION}-RELEASE"
SH
out="$(sh "$S" base versions.sh)"
[ -z "$out" ] \
  || { echo "FAIL ruling-E: a derive-only refactor must print nothing at all: $out"; exit 1; }

cat > versions.sh <<'SH'
SWIFT_VERSION=6.3.4
SWIFT_TAG="swift-${SWIFT_VERSION}-RELEASE"
SH
out="$(sh "$S" base versions.sh)"
printf '%s\n' "$out" | grep -qx -- '### Build ingredients' \
  || { echo "FAIL ruling-E: a real move must still open the section: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*SWIFT_VERSION\*\*: 6.3.3 -> 6.3.4' \
  || { echo "FAIL ruling-E: the real-move bullet is missing: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*SWIFT_TAG\*\*: still used, now computed rather than pinned (was swift-6.3.3-RELEASE)' \
  || { echo "FAIL ruling-E: the derived bullet must still ride along once the section is open: $out"; exit 1; }
cd "$work"; rm -rf "$work15"

# spec: scripts/ingredient-notes.sh -- assigned_keys() answers "is this key still assigned at
#       all", and it MUST agree with assignments() on what counts as an assignment line in the
#       first place, or the two
#       functions drift on the exact question this task is about. A key emptied to KEY= (or
#       KEY="") is not "still assigned" just because a bare `KEY=` line matches the sed pattern --
#       it is GONE, identically to a line disappearing outright. Without the guard, CA_SHA256
#       going from a real hash to CA_SHA256= renders a false "still used, now computed rather
#       than pinned" bullet instead of "removed". SWIFT_VERSION moves for real so the section
#       opens.
work16="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work16"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
cat > versions.sh <<'SH'
SWIFT_VERSION=6.3.3
CA_SHA256=3ff344e30b9b1ed2971044eabb438a08f2e2245ddb5f8ab1a3ad8b63ab4eaf91
SH
git add -A; git commit -qm base; git tag base
cat > versions.sh <<'SH'
SWIFT_VERSION=6.3.4
CA_SHA256=
SH
out="$(sh "$S" base versions.sh)"
printf '%s\n' "$out" | grep -qx -- '- \*\*SWIFT_VERSION\*\*: 6.3.3 -> 6.3.4' \
  || { echo "FAIL guard: real move missing: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*CA_SHA256\*\*: removed' \
  || { echo "FAIL guard: a key emptied to KEY= must still say removed: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'CA_SHA256.*still used' \
  && { echo "FAIL guard: a key with no real value was falsely reported as still assigned/derived: $out"; exit 1; }
cd "$work"; rm -rf "$work16"

# spec: container-tools pins six components as REPO=/REF=/DIGEST= triples. A Renovate bump moves
#       REF and DIGEST together, so every bump used to print two bullets, the second a pair of
#       truncated hashes telling the reader nothing the REF bullet did not -- a DIGEST that moved
#       together with its REF restates it and must not be printed. But a DIGEST that moves ALONE
#       is upstream re-tagging the same ref, genuinely worth telling someone, so it must still be
#       reported.
work17="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work17"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p components/docker-cli
cat > components/docker-cli/version <<'SH'
REPO=https://github.com/docker/cli.git
REF=v29.7.0
DIGEST=88096ef00576baf72a9cb45caa45c0544c40e0a7
SH
git add -A; git commit -qm base; git tag base
cat > components/docker-cli/version <<'SH'
REPO=https://github.com/docker/cli.git
REF=v29.8.0
DIGEST=5f94fb0aa42a2cd1248c6e6c7fafb87546b9c8de
SH
out="$(sh "$S" base components/docker-cli/version)"
printf '%s\n' "$out" | grep -qx -- '- \*\*docker-cli / REF\*\*: v29.7.0 -> v29.8.0 (\[changes\](https://github.com/docker/cli/compare/v29.7.0...v29.8.0))' \
  || { echo "FAIL task7-together: the REF move is still reported: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'DIGEST' \
  && { echo "FAIL task7-together: a DIGEST that moved with its REF restates it: $out"; exit 1; }

cat > components/docker-cli/version <<'SH'
REPO=https://github.com/docker/cli.git
REF=v29.8.0
DIGEST=88096ef00576baf72a9cb45caa45c0544c40e0a7
SH
git add -A; git commit -qm retag-base; git tag retag-base
cat > components/docker-cli/version <<'SH'
REPO=https://github.com/docker/cli.git
REF=v29.8.0
DIGEST=5f94fb0aa42a2cd1248c6e6c7fafb87546b9c8de
SH
out="$(sh "$S" retag-base components/docker-cli/version)"
printf '%s\n' "$out" | grep -qx -- '- \*\*docker-cli / DIGEST\*\*: 88096ef00576... -> 5f94fb0aa42a...' \
  || { echo "FAIL task7-alone: a DIGEST moving alone is a re-tag and must be reported: $out"; exit 1; }
cd "$work"; rm -rf "$work17"

# spec: SKILL.md "Release notes" -- a moved ingredient links to where its change is described. A
#       Renovate customManager that owns the pin is a source: github-releases links the new release,
#       github-tags compares the two tags, and the tag is the version with the prefix
#       extractVersionTemplate strips put back. The repo's own managers come first, then shipyard's
#       preset (the recaulk pin and the mavericks-legacysupport marker live only there).
work18="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work18"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p .github components/golang components/libressl components/zstd components/recaulk components/xz build
cat > .github/renovate.json <<'JSON'
{
  "extends": ["github>Mavergreen/shipyard"],
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["/^components/golang/version$/"],
      "matchStrings": ["^(?<currentValue>.+?)\\s*$"],
      "depNameTemplate": "mavericks-golang",
      "packageNameTemplate": "Mavergreen/golang-126",
      "datasourceTemplate": "github-releases",
      "extractVersionTemplate": "^v?(?<version>.+)$"
    },
    {
      "customType": "regex",
      "managerFilePatterns": ["/^components/libressl/version$/"],
      "matchStrings": ["^(?<currentValue>\\S+)\\s*$"],
      "depNameTemplate": "libressl/portable",
      "datasourceTemplate": "github-releases",
      "extractVersionTemplate": "^v(?<version>.+)$"
    },
    {
      "customType": "regex",
      "managerFilePatterns": ["/^components/zstd/version$/"],
      "matchStrings": ["^(?<currentValue>\\S+)\\s*$"],
      "packageNameTemplate": "facebook/zstd",
      "datasourceTemplate": "github-tags",
      "extractVersionTemplate": "^v(?<version>.+)$"
    },
    {
      "customType": "regex",
      "managerFilePatterns": ["/^components/xz/version$/"],
      "matchStrings": ["TAG=(?<currentValue>\\S+)\\s+SHA256=(?<currentDigest>[0-9a-f]{64})"],
      "packageNameTemplate": "tukaani-project/xz",
      "datasourceTemplate": "github-release-attachments"
    }
  ]
}
JSON
printf '1.26.9-mavericks.1\n' > components/golang/version
printf '3.8.2\n' > components/libressl/version
printf '1.5.6\n' > components/zstd/version
printf '20260901.1\n' > components/recaulk/version
printf 'export MLS_VERSION=1.5.2-mavericks.3   # mavericks-legacysupport\n' > build/versions.sh
printf 'TAG=v5.8.3\nSHA256=%064d\n' 1 > components/xz/version
git add -A; git commit -qm base; git tag base
printf '1.26.10-mavericks.1\n' > components/golang/version
printf '3.9.2\n' > components/libressl/version
printf '1.5.7\n' > components/zstd/version
printf '20260915.2\n' > components/recaulk/version
printf 'export MLS_VERSION=1.5.2-mavericks.4   # mavericks-legacysupport\n' > build/versions.sh
printf 'TAG=v5.8.4\nSHA256=%064d\n' 2 > components/xz/version
out="$(sh "$S" base components/golang/version components/libressl/version components/zstd/version \
        components/recaulk/version build/versions.sh components/xz/version)"
printf '%s\n' "$out" | grep -qx -- '- \*\*golang\*\*: 1.26.9-mavericks.1 -> 1.26.10-mavericks.1' \
  || { echo "FAIL R1b: an optional prefix (^v?) cannot say which tag exists, so it links nothing rather than guess: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*libressl\*\*: 3.8.2 -> 3.9.2 (\[release notes\](https://github.com/libressl/portable/releases/tag/v3.9.2))' \
  || { echo "FAIL R1b: the prefix extractVersionTemplate strips must be put back, and an owner/repo depName names the repo: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*zstd\*\*: 1.5.6 -> 1.5.7 (\[changes\](https://github.com/facebook/zstd/compare/v1.5.6...v1.5.7))' \
  || { echo "FAIL R1b: a github-tags manager must compare the two tags: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*recaulk\*\*: 20260901.1 -> 20260915.2 (\[release notes\](https://github.com/Mavergreen/recaulk/releases/tag/20260915.2))' \
  || { echo "FAIL R1b: a pin only shipyard's preset owns must still be linked: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*MLS_VERSION\*\*: 1.5.2-mavericks.3 -> 1.5.2-mavericks.4' \
  || { echo "FAIL R1b: the preset's ^v? manager owns MLS_VERSION but cannot name its tag: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*xz / TAG\*\*: v5.8.3 -> v5.8.4 (\[release notes\](https://github.com/tukaani-project/xz/releases/tag/v5.8.4))' \
  || { echo "FAIL R1b: github-release-attachments is a GitHub release too: $out"; exit 1; }
printf '%s\n' "$out" | grep -q -- '^- \*\*xz / SHA256\*\*: .*](http' \
  && { echo "FAIL R1b: the manager captures TAG, not SHA256 on the next line: $out"; exit 1; }
cd "$work"; rm -rf "$work18"

# spec: SKILL.md "Release notes" -- a link is resolved per pin, the file plus its KEY. container-tools'
#       boot2docker pin holds a git source (REPO=/REF=/DIGEST=) and BASE=, which Renovate's docker
#       datasource owns; 20260727-mavericks.34's only move was BASE. A file-level rule links BASE to a
#       boot2docker compare that shows no change: confidently wrong. A docker manager has no change
#       link, so BASE needs the KEY-qualified unlinked: declaration, and gets none of REPO='s links.
work19="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work19"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p .github components/boot2docker
cat > .github/renovate.json <<'JSON'
{
  "extends": ["github>Mavergreen/shipyard"],
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["/^components/[^/]+/version$/"],
      "matchStrings": ["REPO=(?<packageName>\\S+?)\\.git\\s+REF=(?<currentValue>\\S+)\\s+DIGEST=(?<currentDigest>[0-9a-f]{40})"],
      "datasourceTemplate": "git-refs",
      "versioningTemplate": "semver"
    },
    {
      "customType": "regex",
      "managerFilePatterns": ["/^components/boot2docker/version$/"],
      "matchStrings": ["BASE=(?<depName>[^:\\s]+):(?<currentValue>[^@\\s]+)@(?<currentDigest>sha256:[0-9a-f]{64})"],
      "datasourceTemplate": "docker"
    }
  ]
}
JSON
cat > components/boot2docker/version <<'PIN'
REPO=https://github.com/dragonflylee/boot2docker.git
REF=v23.0.6
DIGEST=d4a73208aacc94f8f2ee85b3f9db53ac67ef865c
BASE=debian:13-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
PIN
git add -A; git commit -qm base; git tag base
cat > components/boot2docker/version <<'PIN'
REPO=https://github.com/dragonflylee/boot2docker.git
REF=v23.0.6
DIGEST=d4a73208aacc94f8f2ee85b3f9db53ac67ef865c
BASE=debian:13-slim@sha256:b39326f7b46f62f33bee128a998e0f3fa37f23e75b3bad21e876f5bbf5a5a22a
PIN
out="$(sh "$S" base components/boot2docker/version)"
printf '%s\n' "$out" | grep -q 'boot2docker / BASE' \
  || { echo "FAIL per-key: the BASE move is missing: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'compare\|](http' \
  && { echo "FAIL per-key: BASE must not borrow the boot2docker git source's link: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'no change notes' \
  && { echo "FAIL per-key: nothing declared BASE unlinked yet: $out"; exit 1; }
printf '# Build ingredients\n\n## Conformance deviations\n\n- unlinked:components/boot2docker/version: the git source only\n' > INGREDIENTS.md
out="$(sh "$S" base components/boot2docker/version)"
printf '%s\n' "$out" | grep -q 'no change notes' \
  && { echo "FAIL per-key: a file-level declaration must not cover a KEY in it: $out"; exit 1; }
printf '# Build ingredients\n\n## Conformance deviations\n\n- unlinked:components/boot2docker/version:BASE: a Debian slim image digest refresh publishes no notes\n' > INGREDIENTS.md
out="$(sh "$S" base components/boot2docker/version)"
printf '%s\n' "$out" | grep -qx -- '- \*\*boot2docker / BASE\*\*: debian:13-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f -> debian:13-slim@sha256:b39326f7b46f62f33bee128a998e0f3fa37f23e75b3bad21e876f5bbf5a5a22a (no change notes: a Debian slim image digest refresh publishes no notes)' \
  || { echo "FAIL per-key: the KEY-qualified unlinked: declaration must give the BASE bullet its reason: $out"; exit 1; }
cd "$work"; rm -rf "$work19"

# spec: SKILL.md "Release notes" -- a pin with no link source can still say why, in INGREDIENTS.md's
#       deviations; a scoped glob covers a family of pins (patches, a vendored blob) at once.
work20="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work20"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p components/widget vendor patches
printf '1.0\n' > components/widget/version
printf 'line one\n' > vendor/cacert.pem
printf 'Subject: [PATCH] one\n' > patches/0001-one.patch
cat > INGREDIENTS.md <<'MD'
# Build ingredients

## Conformance deviations

- unlinked:components/widget/version: widget publishes no release notes
- unlinked:vendor/cacert.pem: Mozilla's CA bundle has no per-refresh notes
- unlinked:patches/*: our own patches; the subject line is the description
MD
git add -A; git commit -qm base; git tag base
printf '1.1\n' > components/widget/version
printf 'line one\nline two\n' > vendor/cacert.pem
printf 'Subject: [PATCH] one\n+x\n' > patches/0001-one.patch
out="$(sh "$S" base components/widget/version vendor/cacert.pem patches/0001-one.patch)"
printf '%s\n' "$out" | grep -qx -- '- \*\*widget\*\*: 1.0 -> 1.1 (no change notes: widget publishes no release notes)' \
  || { echo "FAIL R1c: a single-line pin's declared reason: $out"; exit 1; }
printf '%s\n' "$out" | grep -q -- "^- \*\*vendor/cacert.pem\*\*: updated (.*) (no change notes: Mozilla's CA bundle has no per-refresh notes)\$" \
  || { echo "FAIL R1c: a blob's declared reason: $out"; exit 1; }
printf '%s\n' "$out" | grep -q -- '^- \*\*0001-one.patch\*\*: updated (.*) (no change notes: our own patches; the subject line is the description)$' \
  || { echo "FAIL R1c: a glob-scoped declaration covers a patch pin: $out"; exit 1; }
cd "$work"; rm -rf "$work20"

# spec: SKILL.md "Release notes" -- within one pin file, a key with no owning manager of its own that
#       moved alongside a linked key is part of that bump: python-315's sqlite SHA256 and YEAR move by
#       hand with VERSION, and a bullet each would restate it with nothing to link.
work21="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work21"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p .github components/sqlite
cat > .github/renovate.json <<'JSON'
{
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["/^components/sqlite/version$/"],
      "matchStrings": ["VERSION=(?<currentValue>\\S+)"],
      "depNameTemplate": "sqlite",
      "packageNameTemplate": "sqlite/sqlite",
      "datasourceTemplate": "github-tags",
      "extractVersionTemplate": "^version-(?<version>\\d+\\.\\d+\\.\\d+)$"
    }
  ]
}
JSON
printf 'VERSION=3.53.0\nYEAR=2025\nSHA256=%064d\n' 1 > components/sqlite/version
git add -A; git commit -qm base; git tag base
printf 'VERSION=3.54.0\nYEAR=2026\nSHA256=%064d\n' 2 > components/sqlite/version
out="$(sh "$S" base components/sqlite/version)"
[ "$(printf '%s\n' "$out" | grep -c '^- ')" = 1 ] \
  || { echo "FAIL fold: VERSION, YEAR and SHA256 are one bump, so one bullet: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*sqlite / VERSION\*\*: 3.53.0 -> 3.54.0 (\[changes\](https://github.com/sqlite/sqlite/compare/version-3.53.0...version-3.54.0))' \
  || { echo "FAIL fold: the linked VERSION bullet: $out"; exit 1; }

# spec: SKILL.md "Release notes" -- with no key in the file linked, nothing folds: each moved key
#       still needs a link or a declared reason.
printf 'VERSION=3.54.0\nYEAR=2026\nSHA256=%064d\n' 3 > components/sqlite/version
git add -A; git commit -qm hash-only; git tag hash-only
printf 'VERSION=3.54.0\nYEAR=2026\nSHA256=%064d\n' 4 > components/sqlite/version
out="$(sh "$S" hash-only components/sqlite/version)"
printf '%s\n' "$out" | grep -q -- '^- \*\*sqlite / SHA256\*\*: ' \
  || { echo "FAIL fold: a lone unowned move folds into nothing and keeps its bullet: $out"; exit 1; }
cd "$work"; rm -rf "$work21"

# spec: SKILL.md "Release notes" -- boot2docker's REF and DIGEST are one bump (DIGEST has no manager
#       of its own), but BASE has its own docker manager, so it keeps its own bullet and link rule.
work22="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work22"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p .github components/boot2docker
cat > .github/renovate.json <<'JSON'
{
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["/^components/[^/]+/version$/"],
      "matchStrings": ["REPO=(?<packageName>\\S+?)\\.git\\s+REF=(?<currentValue>\\S+)\\s+DIGEST=(?<currentDigest>[0-9a-f]{40})"],
      "datasourceTemplate": "git-refs",
      "versioningTemplate": "semver"
    },
    {
      "customType": "regex",
      "managerFilePatterns": ["/^components/boot2docker/version$/"],
      "matchStrings": ["BASE=(?<depName>[^:\\s]+):(?<currentValue>[^@\\s]+)@(?<currentDigest>sha256:[0-9a-f]{64})"],
      "datasourceTemplate": "docker"
    }
  ]
}
JSON
printf 'REPO=https://github.com/dragonflylee/boot2docker.git\nREF=v23.0.6\nDIGEST=%040d\nBASE=debian:13-slim@sha256:%064d\n' 1 1 \
  > components/boot2docker/version
git add -A; git commit -qm base; git tag base
printf 'REPO=https://github.com/dragonflylee/boot2docker.git\nREF=v23.0.7\nDIGEST=%040d\nBASE=debian:13-slim@sha256:%064d\n' 2 2 \
  > components/boot2docker/version
out="$(sh "$S" base components/boot2docker/version)"
printf '%s\n' "$out" | grep -qx -- '- \*\*boot2docker / REF\*\*: v23.0.6 -> v23.0.7 (\[changes\](https://github.com/dragonflylee/boot2docker/compare/v23.0.6...v23.0.7))' \
  || { echo "FAIL fold: the REF bullet: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'DIGEST' \
  && { echo "FAIL fold: DIGEST is part of REF's bump: $out"; exit 1; }
printf '%s\n' "$out" | grep -q -- '^- \*\*boot2docker / BASE\*\*: ' \
  || { echo "FAIL fold: BASE has its own manager, so its own bullet: $out"; exit 1; }
printf '%s\n' "$out" | grep -- '^- \*\*boot2docker / BASE\*\*: ' | grep -q '](http' \
  && { echo "FAIL fold: BASE must not borrow REF's link: $out"; exit 1; }
cd "$work"; rm -rf "$work22"

# spec: SKILL.md "Release notes" -- --repo and --tag let a whole-file pin link this repo's compare
#       view; a KEY of a KEY=VALUE pin never does, so it still needs a link or a declaration.
work23="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work23"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p .github patches components/thing
cat > .github/renovate.json <<'JSON'
{"customManagers": [{"customType": "regex", "managerFilePatterns": ["/^components/thing/version$/"],
  "matchStrings": ["BASE=(?<depName>[^@\\s]+)@(?<currentDigest>sha256:[0-9]+)"],
  "datasourceTemplate": "docker"}]}
JSON
printf 'Subject: [PATCH] one\n' > patches/x.patch
printf 'BASE=img@sha256:%064d\n' 1 > components/thing/version
git add -A; git commit -qm base; git tag base
printf 'Subject: [PATCH] one\n+x\n' > patches/x.patch
printf 'BASE=img@sha256:%064d\n' 2 > components/thing/version
out="$(sh "$S" --repo Mavergreen/thing --tag next base patches/x.patch components/thing/version)"
printf '%s\n' "$out" | grep -q -- '^- \*\*x.patch\*\*: updated (.*) (\[diff\](https://github.com/Mavergreen/thing/compare/base...next))$' \
  || { echo "FAIL R1d: a whole-file pin links the repo's compare: $out"; exit 1; }
printf '%s\n' "$out" | grep -- '^- \*\*thing / BASE\*\*' | grep -q 'compare' \
  && { echo "FAIL R1d: never for a KEY: $out"; exit 1; }
out="$(sh "$S" base patches/x.patch)"
printf '%s\n' "$out" | grep -q 'compare' && { echo "FAIL R1d: no --repo, no link: $out"; exit 1; }
cd "$work"; rm -rf "$work23"

# spec: SKILL.md "Release notes" -- a tag is rebuilt from the literal text around (?<version>...):
#       swift's ^swift-(?<version>.+)-RELEASE$ tags swift-6.4.1-RELEASE, and swift-6.4.1 does not
#       exist. Anything but literal text (openssh's ^v?, a class, alternation) cannot say which tag
#       exists, so the KEY is owned with no link and needs a declaration, never a guess.
work24="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work24"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p .github build
cat > .github/renovate.json <<'JSON'
{
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["/^pins\\.env$/"],
      "matchStrings": ["LLVM_SWIFT_RELEASE=\"(?<currentValue>[^\"]+)\""],
      "packageNameTemplate": "swiftlang/llvm-project",
      "datasourceTemplate": "github-tags",
      "extractVersionTemplate": "^swift-(?<version>.+)-RELEASE$"
    },
    {
      "customType": "regex",
      "managerFilePatterns": ["/^build/versions.sh$/"],
      "matchStrings": ["LIBRESSL_VERSION=(?<currentValue>\\S+)\\s+# renovate: libressl/portable"],
      "depNameTemplate": "libressl/portable",
      "datasourceTemplate": "github-tags",
      "extractVersionTemplate": "^v?(?<version>.+)$"
    }
  ]
}
JSON
printf 'LLVM_SWIFT_RELEASE="6.4.0"\n' > pins.env
printf 'LIBRESSL_VERSION=4.3.2 # renovate: libressl/portable\n' > build/versions.sh
git add -A; git commit -qm base; git tag base
printf 'LLVM_SWIFT_RELEASE="6.4.1"\n' > pins.env
printf 'LIBRESSL_VERSION=4.3.3 # renovate: libressl/portable\n' > build/versions.sh
out="$(sh "$S" --repo Mavergreen/swift --tag next base pins.env build/versions.sh)"
printf '%s\n' "$out" | grep -qx -- '- \*\*LLVM_SWIFT_RELEASE\*\*: 6.4.0 -> 6.4.1 (\[changes\](https://github.com/swiftlang/llvm-project/compare/swift-6.4.0-RELEASE...swift-6.4.1-RELEASE))' \
  || { echo "FAIL I1: the literal suffix must be put back too: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*LIBRESSL_VERSION\*\*: 4.3.2 -> 4.3.3' \
  || { echo "FAIL I1: ^v? owns the KEY but links nothing, not even this repo's diff: $out"; exit 1; }
cd "$work"; rm -rf "$work24"

# spec: SKILL.md "Release notes" -- a KEY no manager owns, in this repo's own pin file, is described by
#       this repo's diff: golang-127's CA refresh moves vendor/cacert.pem and build/versions.sh's
#       CA_SHA256 together, and a config literal moves alone. Folding still comes first, for added keys
#       too: a new REPO=/REF=/DIGEST= component is one bullet, as is a TARBALL_SHA256 added beside a
#       moved REF.
work25="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-notes-tes.XXXXXX")"; cd "$work25"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p .github build vendor components/mls
printf '{"extends": ["github>Mavergreen/shipyard"]}\n' > .github/renovate.json
cat > build/versions.sh <<'SH'
export MLS_VERSION=1.5.2-mavericks.6   # mavericks-legacysupport
export PREFIX="/usr/local/mavergreen/go${GO_LINE}"
export MACOS_MIN="10.9"
export CROSS_MIN_OS="13.0"
export CA_URL="https://curl.se/ca/cacert.pem"
export CA_SHA256="3ff344e30b9b1ed2971044eabb438a08f2e2245ddb5f8ab1a3ad8b63ab4eaf91"  # curl.se cacert.pem, Mozilla 2026-07-16
SH
printf '##\n## Bundle of CA Root Certificates\n##\n-----BEGIN CERTIFICATE-----\nMIIDdZWAUWpL\nMK9=\n-----END CERTIFICATE-----\n' > vendor/cacert.pem
printf 'REPO=https://github.com/macports/macports-legacy-support.git\nREF=v1.5.1\nDIGEST=%040d\n' 1 > components/mls/version
git add -A; git commit -qm base; git tag base
sed 's/3ff344e30b9b1ed2971044eabb438a08f2e2245ddb5f8ab1a3ad8b63ab4eaf91/9a1c72b4aa0f1e8d5c3b7e6f2d4a8091ccee5577bb33ff11aa99887766554433/' \
  build/versions.sh > build/v.new && mv build/v.new build/versions.sh
printf -- '-----BEGIN CERTIFICATE-----\nMIIEeZWAUWpL\n-----END CERTIFICATE-----\n' >> vendor/cacert.pem
out="$(sh "$S" --repo Mavergreen/golang-127 --tag next base build/versions.sh vendor/cacert.pem)"
diffl='(\[diff\](https://github.com/Mavergreen/golang-127/compare/base...next))'
printf '%s\n' "$out" | grep -qx -- "- \*\*CA_SHA256\*\*: 3ff344e30b9b... -> 9a1c72b4aa0f... $diffl" \
  || { echo "FAIL I3: CA_SHA256 moving alone links this repo's diff: $out"; exit 1; }
printf '%s\n' "$out" | grep -q -- "^- \*\*vendor/cacert.pem\*\*: updated (.*) $diffl\$" \
  || { echo "FAIL I3: the bundle links this repo's diff: $out"; exit 1; }
git add -A; git commit -qm ca; git tag ca
sed 's/MACOS_MIN="10.9"/MACOS_MIN="10.9.5"/' build/versions.sh > build/v.new && mv build/v.new build/versions.sh
out="$(sh "$S" --repo Mavergreen/golang-127 --tag next ca build/versions.sh)"
printf '%s\n' "$out" | grep -qx -- "- \*\*MACOS_MIN\*\*: 10.9 -> 10.9.5 (\[diff\](https://github.com/Mavergreen/golang-127/compare/ca...next))" \
  || { echo "FAIL I3: a config literal moving alone links this repo's diff: $out"; exit 1; }
printf 'REPO=https://github.com/macports/macports-legacy-support.git\nREF=v1.5.2\nDIGEST=%040d\nTARBALL_SHA256=%064d\n' 2 2 > components/mls/version
mkdir -p components/lazydocker
printf 'REPO=https://github.com/jesseduffield/lazydocker.git\nREF=v0.25.2\nDIGEST=%040d\n' 3 > components/lazydocker/version
out="$(sh "$S" --repo Mavergreen/golang-127 --tag next ca components/mls/version components/lazydocker/version)"
printf '%s\n' "$out" | grep -qx -- '- \*\*mls / REF\*\*: v1.5.1 -> v1.5.2 (\[changes\](https://github.com/macports/macports-legacy-support/compare/v1.5.1...v1.5.2))' \
  || { echo "FAIL I2: the moved REF: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'TARBALL_SHA256\|DIGEST\|REPO' \
  && { echo "FAIL I2: a key added or moved beside a linked REF is part of its bump: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx -- '- \*\*lazydocker / REF\*\*: added (v0.25.2) (\[source\](https://github.com/jesseduffield/lazydocker/tree/v0.25.2))' \
  || { echo "FAIL I2: a new component file is one bullet, its REF's: $out"; exit 1; }
[ "$(printf '%s\n' "$out" | grep -c '^- ')" = 2 ] || { echo "FAIL I2: two bullets: $out"; exit 1; }
cd "$work"; rm -rf "$work25"

echo "PASS: ingredient-notes"
