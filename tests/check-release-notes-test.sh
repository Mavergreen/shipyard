#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "Release notes" -- this is the family shape for a release body: a title naming
#       THIS version, a What changed section, no empty sections, a non-empty body. Six products
#       once published "Automated release for Mac OS X 10.9 (Mavericks)." as their entire notes.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-release-notes.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/check-release-notes.XXXXXX")"; trap 'rm -rf "$work"' EXIT

ok() {  # $1 = version, $2 = label; file content on stdin
  cat > "$work/n.md"
  sh "$S" "$work/n.md" "$1" >/dev/null 2>&1 || { echo "FAIL should pass: $2"; exit 1; }
}
no() {  # $1 = version, $2 = label, $3 = expected substring of the complaint; content on stdin
  cat > "$work/n.md"
  if out="$(sh "$S" "$work/n.md" "$1" 2>&1)"; then echo "FAIL should fail: $2"; exit 1; fi
  printf '%s\n' "$out" | grep -q "$3" || { echo "FAIL $2: complaint lacked '$3': $out"; exit 1; }
  [ "$(printf '%s\n' "$out" | sed -n 1p | cut -d: -f1)" = notes-shape ] || { echo "FAIL $2: the complaint should open with its id, notes-shape: $out"; exit 1; }
}

ok 9.9p2-mavericks.6 "the family shape" <<'EOF'
## OpenSSH 9.9p2 for Mavericks (9.9p2-mavericks.6)

### What changed
- Repackage of upstream OpenSSH 9.9p2; packaging changes only.

### Build ingredients
- **libressl**: 3.8.2 -> 3.9.2 ([release notes](https://github.com/libressl/portable/releases/tag/v3.9.2))

---
Requires Mac OS X 10.9.5 or later.
EOF

ok 20260802.6 "self-upstream title" <<'EOF'
## Porthole 20260802.6

### What changed
- Release of Porthole 20260802.6.
EOF

no 9.9p2-mavericks.6 "empty file" "empty" </dev/null
no 9.9p2-mavericks.6 "whitespace only" "empty" <<'EOF'


EOF

no 9.9p2-mavericks.6 "stale version in title" "9.9p2-mavericks.6" <<'EOF'
## OpenSSH 9.9p2 for Mavericks (9.9p2-mavericks.5)

### What changed
- Repackage.
EOF

# spec: release.yml calls release-notes.sh with --tag "v$v" --version "$v" -- a leading "v" is
#       not part of the version. shipyard's tag is v1.0.209, but its generated title has no "v"
#       (the title is built from the bare "$v"). previous-release-tag.sh already strips "v"
#       before keying, for the same reason: "v" and bare are one version spelled two ways, not
#       two versions.
ok v1.0.209 "title bare, checked version v-prefixed" <<'EOF'
## Shipyard 1.0.209

### What changed
- Release of Shipyard 1.0.209.
EOF

no v1.0.208 "stale version, v-prefixed check version" "v1.0.208" <<'EOF'
## Shipyard 1.0.209

### What changed
- Release of Shipyard 1.0.209.
EOF

no v "degenerate version \"v\" must not match every title" "does not name v" <<'EOF'
## Something Unrelated

### What changed
- Whatever.
EOF

ok 9.9p2-mavericks.6 "no leading v anywhere, unaffected" <<'EOF'
## OpenSSH 9.9p2 for Mavericks (9.9p2-mavericks.6)

### What changed
- Repackage.
EOF

no 9.9p2-mavericks.6 "no What changed" "What changed" <<'EOF'
## Mavericks OpenSSH 9.9p2 (9.9p2-mavericks.6)

Automated release for Mac OS X 10.9 (Mavericks).
EOF

no 9.9p2-mavericks.6 "empty What changed" "empty" <<'EOF'
## OpenSSH 9.9p2 for Mavericks (9.9p2-mavericks.6)

### What changed

### Build ingredients
- **libressl**: 3.8.2 -> 3.9.2
EOF

# spec: scripts/check-release-notes.sh -- an empty ### section followed by a further ## heading
#       must still be caught: the ## branch that resets tracking for a new top-level heading
#       must not skip the pending-empty-section check.
no 9.9p2-mavericks.6 "empty section before a further ## heading" "empty" <<'EOF'
## OpenSSH 9.9p2 for Mavericks (9.9p2-mavericks.6)

### What changed
- Repackage.

### Empty Section

## Appendix
Some trailing content.
EOF

no 9.9p2-mavericks.6 "title not first" "first line" <<'EOF'
Some prose first.

## OpenSSH 9.9p2 for Mavericks (9.9p2-mavericks.6)

### What changed
- Repackage.
EOF

# spec: SKILL.md "Release notes" -- every moved ingredient says where its change is described, or
#       why nothing does. container-tools 20260727-mavericks.37 shipped "- **docker-cli / REF**:
#       v29.9.0 -> v29.9.1" and nothing else: a reader had to go and find docker/cli's notes.
no 20260727-mavericks.37 "an ingredient bullet with no link and no reason" "docker-cli / REF" <<'EOF'
## Container Tools 20260727 for Mavericks (20260727-mavericks.37)

### What changed
- Repackage of upstream Container Tools 20260727, rebuilt because build ingredients moved (below).

### Build ingredients

Changed since 20260727-mavericks.36:

- **docker-cli / REF**: v29.9.0 -> v29.9.1
EOF
for fix in 'Renovate' 'REPO=' 'unlinked:'; do
  printf '%s\n' "$out" | grep -q "$fix" || { echo "FAIL: the complaint must name the fix ($fix): $out"; exit 1; }
done

ok 20260727-mavericks.37 "linked, reasoned, removed and now-computed bullets" <<'EOF'
## Container Tools 20260727 for Mavericks (20260727-mavericks.37)

### What changed
- Repackage of upstream Container Tools 20260727, rebuilt because build ingredients moved (below).

### Build ingredients

Changed since 20260727-mavericks.36:

- **docker-cli / REF**: v29.9.0 -> v29.9.1 ([changes](https://github.com/docker/cli/compare/v29.9.0...v29.9.1))
- **boot2docker / BASE**: debian:13-slim@sha256:a -> debian:13-slim@sha256:b (no change notes: a digest refresh publishes none)
- **GO_SRC_SHA512**: removed
- **SWIFT_TAG**: still used, now computed rather than pinned (was swift-6.3.3-RELEASE)

---
[All changes since 20260727-mavericks.36](https://github.com/Mavergreen/container-tools/compare/20260727-mavericks.36...20260727-mavericks.37)
EOF

# spec: scripts/check-release-notes.sh -- only the ingredient section is held to this: a link-less
#       bullet a human wrote in the committed prose, or under What changed, is not an ingredient.
ok 9.9p2-mavericks.6 "bare bullets outside the ingredient section" <<'EOF'
## OpenSSH 9.9p2 for Mavericks (9.9p2-mavericks.6)

- a bullet a human wrote

### What changed
- Repackage of upstream OpenSSH 9.9p2; packaging changes only.
EOF

printf '## OpenSSH 9.9p2 for Mavericks (9.9p2-mavericks.1)\n\nWords.\n<!-- edited by a human -->\n\n### What changed\n\n- a change\n' \
  | no 9.9p2-mavericks.1 "a body carrying the mark is refused" 'edited by a human'
echo "PASS: check-release-notes"
