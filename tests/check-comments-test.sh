#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-comments.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/check-comments-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT

ok() {   # $1 = name, stdin = file content; must PASS
  f="$w/$1.sh"; cat > "$f"
  sh "$S" "$f" > "$w/$1.out" 2>&1 || { echo "FAIL $1: expected clean, got: $(cat "$w/$1.out")"; exit 1; }
}
bad() {  # $1 = name, $2 = a string the message must contain, stdin = content; must FAIL
  f="$w/$1.sh"; cat > "$f"
  if sh "$S" "$f" > "$w/$1.out" 2>&1; then echo "FAIL $1: expected a violation, got none"; exit 1; fi
  grep -q "$2" "$w/$1.out" || { echo "FAIL $1: message lacks '$2': $(cat "$w/$1.out")"; exit 1; }
}

ok shebang <<'EOF'
#!/bin/sh
set -eu
EOF

ok directive <<'EOF'
#!/bin/sh
# shellcheck disable=SC2086
echo hi
EOF

ok usage_block <<'EOF'
#!/bin/sh
#   usage: thing.sh --flag VALUE
#          --flag   what it does
set -eu
EOF

ok tagged_platform <<'EOF'
#!/bin/sh
# platform: 10.9's BSD mktemp rejects a bare -d
d="$(mktemp -d "${TMPDIR:-/tmp}/x.XXXXXX")"
EOF

ok tagged_spec <<'EOF'
#!/bin/sh
# spec: 2026-09-12 decision 3 -- an automatic publish also requires main
[ "$REF" = refs/heads/main ] || exit 0
EOF

ok tagged_continuation <<'EOF'
#!/bin/sh
# platform: 10.9's BSD sort has no -V, so any version compare must use lib.sh's
#           ver_cmp instead
. ./lib.sh
EOF

# THE HAZARD: heredoc bodies are payload. scripts/package-pkg.sh writes a script
# with 15 comment lines inside <<'PRE'; flagging or deleting those ships a broken pkg.
ok heredoc_quoted <<'EOF'
#!/bin/sh
cat > out <<'PRE'
# this is the generated script's own comment
# and this one too
PRE
EOF

ok heredoc_unquoted <<'EOF'
#!/bin/sh
cat > out <<PRE
# still payload even unquoted
PRE
EOF

ok heredoc_dash <<'EOF'
#!/bin/sh
cat > out <<-'PRE'
	# indented terminator form
	PRE
EOF

bad untagged 'platform:' <<'EOF'
#!/bin/sh
# this explains what the next line does
echo hi
EOF

bad unknown_tag 'propose a new reason' <<'EOF'
#!/bin/sh
# because: I felt like it
echo hi
EOF

bad paragraph_not_continuation 'platform:' <<'EOF'
#!/bin/sh
# platform: 10.9's BSD mktemp rejects a bare -d
# and here is a second unindented line pretending to belong to it
d=1
EOF

bad yaml_untagged 'platform:' <<'EOF'
name: CI
# an untagged comment in a workflow
on: push
EOF

# The message must name the file and the line number, or a sweep cannot be driven by it.
f="$w/loc.sh"; printf '#!/bin/sh\nx=1\n# untagged\n' > "$f"
sh "$S" "$f" > "$w/loc.out" 2>&1 || true
grep -q "loc.sh:3:" "$w/loc.out" || { echo "FAIL location: want loc.sh:3:, got $(cat "$w/loc.out")"; exit 1; }

# A path NAMED on the command line that does not exist is a usage error, not a silent skip: a
# caller's typo'd or non-matching glob (scripts/[a-m]*.sh) must not produce exit 0 with no
# output, which would be indistinguishable from "this directory is clean".
missing="$w/does-not-exist.sh"
rc=0
sh "$S" "$missing" > "$w/missing.out" 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL missing-path: expected exit 2, got $rc: $(cat "$w/missing.out")"; exit 1; }
[ -s "$w/missing.out" ] || { echo "FAIL missing-path: expected non-empty output naming the path, got nothing"; exit 1; }
grep -q "does-not-exist.sh" "$w/missing.out" || { echo "FAIL missing-path: output does not name the path: $(cat "$w/missing.out")"; exit 1; }

# The trailing count is what later sweeps drive their work from: it must count VIOLATIONS (not
# lines of output), appear only when something was found, and stay silent on a clean file.
countcheck="$w/countcheck.sh"
printf '#!/bin/sh\n# one\necho 1\n# two\necho 2\n# three\necho 3\n' > "$countcheck"
sh "$S" "$countcheck" > "$w/countcheck.out" 2>&1 || true
got="$(grep -cE ':[0-9]+: ' "$w/countcheck.out")"
[ "$got" -eq 3 ] || { echo "FAIL countcheck: expected 3 violations, saw $got: $(cat "$w/countcheck.out")"; exit 1; }
grep -q '^3 comments cite no reason$' "$w/countcheck.out" \
  || { echo "FAIL countcheck: expected trailing count '3 comments cite no reason', got: $(cat "$w/countcheck.out")"; exit 1; }
grep -q 'comments cite no reason' "$w/shebang.out" \
  && { echo "FAIL shebang: a clean file printed a count line: $(cat "$w/shebang.out")"; exit 1; }

echo "PASS: check-comments"
