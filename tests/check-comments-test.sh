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

# spec: scripts/package-pkg.sh writes its generated script inside a <<'PRE' heredoc with 15
#       comment lines in it -- those are payload, not commentary, and flagging or deleting them
#       would ship a broken pkg.
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

# spec: publish-release.yml's `{ echo 'files<<EOF'; }` is the real incident -- a quoted
#       "<<WORD" inside a string is not a heredoc, but the scanner once treated "EOF" as a real
#       terminator with no matching close, silently swallowing ~120 lines of genuine comments:
#       exit 0, no output, indistinguishable from "this file is clean".
bad quoted_marker_single 'platform:' <<'EOF'
#!/bin/sh
{ echo 'files<<EOF'; }
# an untagged comment
# and another
EOF

bad quoted_marker_double 'platform:' <<'EOF'
#!/bin/sh
echo "files<<EOF"
# an untagged comment after a double-quoted fake heredoc marker
EOF

# spec: scripts/check-comments.sh takes the LAST real "<<" candidate on a line, so a quoted
#       fake earlier on the same line must neither suppress a real heredoc opener nor be
#       mistaken for it.
ok heredoc_after_quoted_fake <<'EOF'
#!/bin/sh
printf 'x<<EOF' > f <<'REAL'
# this line is payload, not commentary, and must not be flagged
REAL
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

f="$w/loc.sh"; printf '#!/bin/sh\nx=1\n# untagged\n' > "$f"
sh "$S" "$f" > "$w/loc.out" 2>&1 || true
grep -q "loc.sh:3:" "$w/loc.out" \
  || { echo "FAIL location: the message must name the file and line number, or a sweep cannot be driven by it: got $(cat "$w/loc.out")"; exit 1; }

missing="$w/does-not-exist.sh"
rc=0
sh "$S" "$missing" > "$w/missing.out" 2>&1 || rc=$?
[ "$rc" -eq 2 ] \
  || { echo "FAIL missing-path: a path NAMED on the command line that does not exist is a usage error, not a silent skip -- expected exit 2, got $rc: $(cat "$w/missing.out")"; exit 1; }
[ -s "$w/missing.out" ] \
  || { echo "FAIL missing-path: a typo'd or non-matching glob must not produce exit 0 with no output, indistinguishable from a clean directory -- expected non-empty output naming the path, got nothing"; exit 1; }
grep -q "does-not-exist.sh" "$w/missing.out" \
  || { echo "FAIL missing-path: the usage-error output must name the path, or a typo cannot be diagnosed: $(cat "$w/missing.out")"; exit 1; }

countcheck="$w/countcheck.sh"
printf '#!/bin/sh\n# one\necho 1\n# two\necho 2\n# three\necho 3\n' > "$countcheck"
sh "$S" "$countcheck" > "$w/countcheck.out" 2>&1 || true
got="$(grep -cE ':[0-9]+: ' "$w/countcheck.out")"
[ "$got" -eq 3 ] \
  || { echo "FAIL countcheck: the trailing count is what later sweeps drive their work from, so it must count VIOLATIONS not lines of output: expected 3, saw $got: $(cat "$w/countcheck.out")"; exit 1; }
grep -q '^3 comments cite no reason$' "$w/countcheck.out" \
  || { echo "FAIL countcheck: expected trailing count '3 comments cite no reason', got: $(cat "$w/countcheck.out")"; exit 1; }
grep -q 'comments cite no reason' "$w/shebang.out" \
  && { echo "FAIL shebang: the count line must appear only when something was found, but a clean file printed one: $(cat "$w/shebang.out")"; exit 1; }

echo "PASS: check-comments"
