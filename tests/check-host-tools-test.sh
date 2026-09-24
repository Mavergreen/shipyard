#!/bin/sh
# platform: host-agnostic
#   usage: check-host-tools-test.sh
#          Every case asserts check-host-tools.sh's EXIT STATUS on a one-purpose fixture repo.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md check 22
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-host-tools.sh"
_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/check-host-tools-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT
AGN='# platform: host-agnostic'
MAC='# platform: macOS-only -- a fixture'
T="$(printf '\t')"

# spec: scripts/check-host-tools.sh -- it asks git what is tracked, so each fixture is a real
#       checkout. $1 = dir; the rest are "path<TAB>content" pairs, content printf-expanded. One
#       host-agnostic baseline script adopts the split, so a case fails only for what it adds.
mk() {
  d="$work/$1"; shift; mkdir -p "$d/scripts"
  printf '#!/bin/sh\n%s\necho ok\n' "$AGN" > "$d/scripts/base.sh"
  for pc in "$@"; do
    p="${pc%%"$T"*}"; c="${pc#*"$T"}"
    mkdir -p "$d/$(dirname "$p")"; printf "$c" > "$d/$p"
  done
  (cd "$d" && git init -q && git add -A) >/dev/null 2>&1
}
passes() {  # $1 = fixture, $2 = why
  (cd "$work/$1" && sh "$S" >/dev/null 2>&1) || { echo "FAIL: $2 -- should pass:"; (cd "$work/$1" && sh "$S" 2>&1 | sed 's/^/    | /'); exit 1; }
}
fails() {  # $1 = fixture, $2 = why
  if (cd "$work/$1" && sh "$S" >/dev/null 2>&1); then echo "FAIL: $2 -- should fail"; exit 1; fi
}

mk ok; passes ok "an adopted repo whose one script is clean"

mkdir -p "$work/none/scripts"; printf '#!/bin/sh\necho hi\n' > "$work/none/scripts/x.sh"
(cd "$work/none" && git init -q && git add -A) >/dev/null 2>&1
passes none "a repo where no script declares a host has not adopted the split"
if (cd "$work/none" && sh "$S" --required >/dev/null 2>&1); then echo "FAIL: --required must fail a repo that has not adopted the split"; exit 1; fi

mk undeclared "scripts/new.sh${T}#!/bin/sh\necho hi\n"
fails undeclared "D1: an undeclared script in an adopted repo is an error, never assumed host-agnostic"
mk late "scripts/late.sh${T}#!/bin/sh\necho hi\n$AGN\n"
fails late "a declaration below the first line of code is not a header declaration"
mk twice "scripts/twice.sh${T}#!/bin/sh\n$AGN\n$MAC\necho hi\n"
fails twice "a script declaring both hosts"
(cd "$work/twice" && sh "$S" 2>&1 || true) | grep -q 'more than once' || { echo "FAIL: two declarations must be named as two, not as none"; exit 1; }
mk noreason "scripts/nr.sh${T}#!/bin/sh\n# platform: macOS-only\notool -L x\n"
fails noreason "macOS-only with no reason is not a declaration"

mk agnotool "scripts/a.sh${T}#!/bin/sh\n$AGN\notool -L x\n"
fails agnotool "a host-agnostic script running otool"
mk macotool "scripts/m.sh${T}#!/bin/sh\n$MAC\notool -L x\n"
passes macotool "a macOS-only script may run otool"

# spec: SKILL.md check 22 -- the three shapes check 18 provably cannot see, each on its own.
#       Each fixture is found by exactly one listing rule: no "#!" on the .bats (most of
#       shipyard's have none) or the executable, and no execute bit on the "#!" file.
mk bats "tests/t.bats${T}$AGN\n@test \"t\" {\n  run otool -L x\n}\n"
fails bats "a .bats file"
mk testsh "tests/t-test.sh${T}$AGN\notool -L x\n"
fails testsh "a tests/*.sh file"
mk extless "bin/tool${T}$AGN\notool -L x\n"
chmod +x "$work/extless/bin/tool"; (cd "$work/extless" && git add -A) >/dev/null 2>&1
fails extless "an extensionless executable"
mk shebang "libexec/helper${T}#!/bin/sh\n$AGN\notool -L x\n"
fails shebang "an extensionless, non-executable #! script"
mk extundecl "bin/tool${T}#!/bin/sh\necho hi\n"
fails extundecl "an undeclared extensionless #! script, anywhere in the tree"
mk tmpl "scripts/templates/msc.sh${T}#!/bin/sh\notool -L x\n"
passes tmpl "scripts/templates/ holds other repos' canonical copies (check 17's), not this repo's scripts"

# spec: scripts/host-tools.awk -- command position, as a shell sees it.
n=0
for call in '(otool -L x)' '/usr/bin/otool -L x' 'sudo -u "$u" launchctl list' 'env A=1 otool -L x' \
            'A=1 otool -L x' 'echo "$(otool -L x)"' 'x=`otool -L x`' 'if otool -L x; then :; fi' \
            '! otool -L x' 'true && otool -L x' 'ls | xargs otool -L' '{ otool -L x; }' \
            '/usr/libexec/PlistBuddy -c Print x' 'exec lipo -info x' 'x="$(true)"; lipo -info x' \
            'case "$1" in a) otool -L x ;; esac' 'n=$((n + 1)) otool -L x'; do
  n=$((n + 1)); mk "call$n"
  printf '#!/bin/sh\n%s\n%s\n' "$AGN" "$call" > "$work/call$n/scripts/c.sh"; (cd "$work/call$n" && git add -A) >/dev/null 2>&1
  fails "call$n" "a call: $call"
done
n=0
for notcall in 'command -v otool >/dev/null' 'echo "use otool to look"' 'otools --help' 'echo $((1 + 2)) lipo' \
               'lipo() { echo stub; }' '# otool -L x' 'echo x  # not run; otool -L x would be' "printf '%%s\\\\n' 'a
otool -L x'"; do
  n=$((n + 1)); mk "notcall$n"
  printf '#!/bin/sh\n%s\n%s\n' "$AGN" "$notcall" > "$work/notcall$n/scripts/c.sh"; (cd "$work/notcall$n" && git add -A) >/dev/null 2>&1
  passes "notcall$n" "not a call: $notcall"
done
mk heredoc "scripts/h.sh${T}#!/bin/sh\n$AGN\ncat <<'EOF2'\notool -L x\nEOF2\necho after\n"
passes heredoc "a heredoc body is payload, not a call"
mk afterheredoc "scripts/h.sh${T}#!/bin/sh\n$AGN\ncat <<EOF2\nx\nEOF2\notool -L x\n"
fails afterheredoc "the line after a heredoc's terminator is code again"

mk guarded "scripts/g.sh${T}#!/bin/sh\n$AGN\n# platform: guarded macOS-only call -- uname\n[ \"\$(uname -s)\" = Darwin ] && sw_vers\n"
passes guarded "a call guarded, and saying so directly above"
mk guardgap "scripts/g.sh${T}#!/bin/sh\n$AGN\n# platform: guarded macOS-only call -- uname\n\nsw_vers\n"
fails guardgap "the guard comment covers only the line directly below it"
mk guardonce "scripts/g.sh${T}#!/bin/sh\n$AGN\n# platform: guarded macOS-only call -- uname\n[ \"\$(uname -s)\" = Darwin ] && sw_vers\nsw_vers\n"
fails guardonce "the guard comment covers one line, not the rest of the file"

out="$(cd "$work/agnotool" && sh "$S" 2>&1 || true)"
printf '%s\n' "$out" | grep -q 'scripts/a.sh:3' || { echo "FAIL: a violation must name file:line: $out"; exit 1; }
out="$(cd "$work/ok" && sh "$S" 2>&1)"
printf '%s\n' "$out" | grep -q 'whole tree' || { echo "FAIL: the ok line must say it scanned the whole tree: $out"; exit 1; }

# spec: SKILL.md check 22 -- shipyard itself has adopted the split, and must stay adopted.
(cd "$here/.." && sh "$S" --required >/dev/null 2>&1) \
  || { echo "FAIL: shipyard's own tree must pass check-host-tools --required:"; (cd "$here/.." && sh "$S" --required 2>&1 | sed 's/^/    | /'); exit 1; }

echo "PASS: check-host-tools"
