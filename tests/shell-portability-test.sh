#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-shell-portability.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/shell-portability.XXXXXX")"; trap 'rm -rf "$work"' EXIT

mkrepo() {  # $1 = dir
  mkdir -p "$1"
  (cd "$1" && git init -q)
}

mkrepo "$work/ok"
printf '#!/bin/sh\nd="$(mktemp -d "${TMPDIR:-/tmp}/x.XXXXXX")"\nt="$(mktemp -d -t pfx)"\n' > "$work/ok/a.sh"
(cd "$work/ok" && git add -A) >/dev/null 2>&1
(cd "$work/ok" && sh "$S" >/dev/null) || { echo "FAIL legal mktemp forms should pass"; exit 1; }

mkrepo "$work/v"
printf '#!/bin/sh\ngit tag --list | sort -V | tail -1\n' > "$work/v/a.sh"  # portability-ok: a lint fixture must contain the violation it tests for
(cd "$work/v" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/v" && sh "$S" 2>&1)"; then echo "FAIL sort -V should fail"; exit 1; fi  # portability-ok: names the construct under test
printf '%s\n' "$out" | grep -q 'a.sh:2' || { echo "FAIL should name file:line: $out"; exit 1; }
printf '%s\n' "$out" | grep -qi 'ver_cmp' || { echo "FAIL should say what to use instead: $out"; exit 1; }

mkrepo "$work/v2"
printf '#!/bin/sh\nprintf x | sort --version-sort\n' > "$work/v2/a.sh"  # portability-ok: a lint fixture must contain the violation it tests for
(cd "$work/v2" && git add -A) >/dev/null 2>&1
if (cd "$work/v2" && sh "$S" >/dev/null 2>&1); then echo "FAIL: sort -V's long-form spelling (--version-sort) should also fail"; exit 1; fi  # portability-ok: names the construct under test
mkdir -p "$work/b64" && (cd "$work/b64" && git init -q)
printf '#!/bin/sh\nprintf aGk= | base64 -d\n' > "$work/b64/a.sh"  # portability-ok: a lint fixture must contain the violation it tests for
(cd "$work/b64" && git add a.sh)
out="$(cd "$work/b64" && sh "$S" 2>&1)" && { echo "FAIL: base64 -d should fail"; exit 1; }  # portability-ok: names the construct under test
printf '%s\n' "$out" | grep -q 'base64 --decode' || { echo "FAIL: the base64 rule should say to use --decode: $out"; exit 1; }
printf '#!/bin/sh\nprintf aGk= | base64 --decode\n' > "$work/b64/a.sh"
(cd "$work/b64" && git add a.sh && sh "$S" >/dev/null 2>&1) || { echo "FAIL: base64 --decode must pass"; exit 1; }

mkrepo "$work/m"
printf '#!/bin/sh\nw="$(mktemp -d)"\nl="$(mktemp)"\n' > "$work/m/a.sh"  # portability-ok: a lint fixture must contain the violation it tests for
(cd "$work/m" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/m" && sh "$S" 2>&1)"; then echo "FAIL bare mktemp should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'a.sh:2' || { echo "FAIL should catch mktemp -d: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'a.sh:2' || { echo "FAIL should catch bare mktemp: $out"; exit 1; }

mkrepo "$work/c"
printf '#!/bin/sh\n# never use sort -V here; and not $(mktemp -d) either\necho ok\n' > "$work/c/a.sh"  # portability-ok: a lint fixture must contain the violation it tests for
(cd "$work/c" && git add -A) >/dev/null 2>&1
(cd "$work/c" && sh "$S" >/dev/null) || { echo "FAIL: prose ABOUT a ban is not a violation, or the docs could not explain the rule -- full-line comments should not trip the lint"; exit 1; }

mkrepo "$work/b"
printf '#!/bin/sh\necho ok\n' > "$work/b/a.sh"
printf 'setup() {\n  TMP="$(mktemp -d)"\n}\n' > "$work/b/tests.bats"  # portability-ok: a lint fixture must contain the violation
(cd "$work/b" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/b" && sh "$S" 2>&1)"; then echo "FAIL: .bats files are shell too -- the first cut of this lint scanned only *.sh, so it called ed25519 clean while tests/version.bats was dying on a bare mktemp in setup(); a .bats violation should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'tests.bats:2' || { echo "FAIL should name the .bats file:line: $out"; exit 1; }

mkrepo "$work/u"
printf '#!/bin/sh\necho ok\n' > "$work/u/a.sh"
(cd "$work/u" && git add -A) >/dev/null 2>&1
printf '#!/bin/sh\nsort -V\n' > "$work/u/vendored.sh"  # portability-ok: a lint fixture must contain the violation it tests for
(cd "$work/u" && sh "$S" >/dev/null) || { echo "FAIL: UNTRACKED files are out of scope, since vendored/fetched upstream trees are not ours to rewrite"; exit 1; }

# spec: SKILL.md "Running a repo's tests" -- an assertion must be able to fail on 10.9 too;
#       check-shell-portability.sh bans the bare forms because it found them all green there
#       whatever the code did (seventeen in shipyard, fourteen in ed25519).
mkrepo "$work/a"
printf '@test "t" {\n  run x\n  [[ "$output" == *y* ]]\n  [ "$status" -eq 0 ]\n}\n' > "$work/a/t.bats"  # portability-ok: a lint fixture must contain the violation
(cd "$work/a" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/a" && sh "$S" 2>&1)"; then echo "FAIL a bare [[ ]] assertion should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 't.bats:3' || { echo "FAIL should name the bare [[ ]] line: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '|| false' || { echo "FAIL should say to end it || false: $out"; exit 1; }

mkrepo "$work/a2"
printf '@test "t" {\n  for i in 1 2; do [[ $i == 1 ]]; done\n  true\n}\n' > "$work/a2/t.bats"  # portability-ok: a lint fixture must contain the violation
(cd "$work/a2" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/a2" && sh "$S" 2>&1)"; then echo "FAIL: an unfailable [[ ]] must be caught as the body of a one-line loop too"; exit 1; fi
printf '%s\n' "$out" | grep -q 't.bats:2' || { echo "FAIL should name the loop line: $out"; exit 1; }

mkrepo "$work/n"
printf '@test "t" {\n  ! echo "$output" | grep -q y\n  true\n}\n' > "$work/n/t.bats"  # portability-ok: a lint fixture must contain the violation
(cd "$work/n" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/n" && sh "$S" 2>&1)"; then echo "FAIL a bare ! command should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 't.bats:2' || { echo "FAIL should name the ! line: $out"; exit 1; }

mkrepo "$work/a3"
printf '@test "t" {\n  [[ "$output" == *y* ]] || false\n  if [[ -n "$x" ]]; then true; fi\n  ! grep -q x f || { echo no; exit 1; }\n  ! grep x f \\\n      | grep -q y || return 1\n  run ! false\n  for i in 1; do [[ $i == 1 ]] || false; done\n}\n' > "$work/a3/t.bats"
(cd "$work/a3" && git add -A) >/dev/null 2>&1
(cd "$work/a3" && sh "$S" >/dev/null) || { echo "FAIL: the forms that DO fail a test (|| false, a condition, ! ... || fail, run !) must pass the lint"; exit 1; }

mkrepo "$work/br"
lb='['  # kept out of the fixture's literal text, or the lint would flag this very file
printf '#!/bin/sh\nawk '"'"'$0 !~ /^[^*?%s:]+$/ { print }'"'"'\n' "$lb" > "$work/br/a.sh"
(cd "$work/br" && git add -A) >/dev/null 2>&1
if out="$(cd "$work/br" && sh "$S" 2>&1)"; then echo "FAIL: a '[' before ':' inside a bracket expression should fail"; exit 1; fi
printf '%s\n' "$out" | grep -q 'a.sh:2' || { echo "FAIL should name the bracket line: $out"; exit 1; }
mkrepo "$work/br2"
cat > "$work/br2/a.sh" <<'EOF'
#!/bin/sh
awk '$0 !~ /^[[:space:]]*[a[:digit:]]+[^[:space:]#]$/ { print }'
EOF
(cd "$work/br2" && git add -A) >/dev/null 2>&1
(cd "$work/br2" && sh "$S" >/dev/null) || { echo "FAIL: well-formed [[:class:]] expressions must pass"; exit 1; }

# spec: scripts/check-shell-portability.sh -- preserve every draft fixture, including
#       unchanged HEAD limitations: multiline literals/heredocs, split conditions,
#       groups, inline negations and continued pipelines get no context analysis.
#       Only complete final simple-command/pipeline lines may lose a HEAD hit.
#       Escaped fixture newlines keep the original regex from scanning test data.
diagnostic_case() {  # $1 name of written fixture, $2 exact diagnostic lines
  rc=0
  out="$(sh "$S" "$work/$1.sh" 2>&1)" || rc=$?
  actual="$(printf '%s\n' "$out" | sed -n 's/.*\.sh:\([0-9][0-9]*\) uses a bare !-negated command.*/\1/p')"
  if [ "$actual" != "$2" ] || { [ -z "$2" ] && [ "$rc" -ne 0 ]; } || { [ -n "$2" ] && [ "$rc" -eq 0 ]; }; then
    echo "FAIL $1: expected lines [$2], got [$actual], exit $rc: $out"
    exit 1
  fi
}
syntax_case() {  # $1 name, $2 exact diagnostic lines, $3 printf-escaped source
  printf '%b\n' "$3" > "$work/$1.sh"
  /bin/sh -n "$work/$1.sh" || { echo "FAIL invalid shell fixture: $1"; exit 1; }
  diagnostic_case "$1" "$2"
}

syntax_case sockets '' 'if [ "$label" != expected ] ||\n    ! "$PLISTBUDDY" -c "Print :Sockets:A" "$plist" >/dev/null 2>&1 ||\n    ! "$PLISTBUDDY" -c "Print :Sockets:B" "$plist" >/dev/null 2>&1; then\n    :\nfi'
syntax_case wrapper '' 'if [ ! -f "$wrapper" ] || [ -L "$wrapper" ] ||\n    ! printf "%s\\n" "#!/bin/sh" "exec \\"\\$@\\"" | cmp -s "$wrapper" -; then\n    :\nfi'
syntax_case elif '' 'if false; then :\nelif ! has "auth: verified" "$log" ||\n    ! has "auto-login: on" "$log"; then\n    :\nfi'
syntax_case loops '2
4' 'while false ||\n    ! probe; do break; done\nuntil false &&\n    ! probe\ndo :; done'
syntax_case continuations 10 'if \\\n    ! probe && # then is only a comment\n    # spec: scripts/check-shell-portability.sh -- comment within a predicate\n    ! printf "%s" "a || b; then" \\\n        | cmp -s file -\nthen :; fi\nif ! probe\nthen\n    if ! other ||\n        ! final; then :; fi\nfi'
syntax_case guarded '' '! probe || false\n! printf x \\\n    | cmp -s file - || exit 1\nrun ! probe'
syntax_case standalone '1
3
5
7
8' '! false # ; then\nprintf "%s" "if"; true\n! false "then"\nprintf "%s" "if probe ||"\n! false "; then"; true\nfoo && ! bar\n! printf x | cmp -s file -\n! false; printf "%s" "then"\n! false "|| false"'
syntax_case later_command '2
5' 'if\n    ! probe\n    true\nthen\n    ! body\n    true\nfi'
syntax_case quoted_keywords '2
4
5
7' '"if" probe || true\n! false\nprintf "%s" "if\n! data; then"\n! false\nprintf "%s" '"'"'if; then'"'"'\n! false\n! false # || exit 1'
syntax_case heredoc '7
11
12' 'cat <<"END" <<-\\SECOND\nif false ||\nthen\nEND\nuntil false ||\nSECOND\n! false\nif cat <<END &&\nif fake; then\nEND\n    ! probe; then :; fi\n! false'
syntax_case boundaries '3
5' 'if ! probe; then :; fi\n# spec: scripts/check-shell-portability.sh -- then is comment text\n! body\nwhile ! probe; do\n    ! body\n    break\ndone; ! tail'
syntax_case escaped_keywords '2
4' '\\if probe || true\n! false\nprintf "%s" if\\;then\n! false'
syntax_case split_word '' 'i\\\nf ! probe ||\n    ! final; th\\\nen :; fi'
syntax_case groups '' 'if ! (cd dir && probe) ||\n    ! { probe && other; }; then :; fi\n(cd dir && ! probe) \\\n    || exit 1\nif ! result=$(probe "$(other)"); then :; fi\nif ! result=`probe`; then :; fi'
syntax_case group_assertions 4 '(foo && ! bar)\n{ ! probe; true; }\nif ! (probe); then\n    ! body\nfi; ! tail'
syntax_case substitution_assertions '2
6' 'result=$(\n    ! probe\n    true\n)\nresult="$(printf "%s" "if; then")"\n! false'
syntax_case pipeline_continuation '' '! printf "%s" x |\n    cmp -s file -\n! printf "%s" x |\n    cmp -s file - || exit 1\n! false \\\n    # spec: scripts/check-shell-portability.sh -- then is comment text\ntrue'
syntax_case data '2
4' 'printf "%s" "if\n! data; then"\ncat <<"END"\n! data\nEND\nprintf "%s" '"'"'! data; then'"'"''
syntax_case expansions '3
5
7' 'n=$((1 << 2))\nprintf "%s" ${missing:-if}\n! false\nprintf "%s" "${missing:-\\"if; then\\"}"\n! false\nprintf "%s" "$(printf "%s" "if; then")"\n! false'
syntax_case redirect_words '2
4' ': >if\n! false\n: 2>then\n! false'
syntax_case nested_predicate '' 'if if false; then :; fi ||\n    ! false; then\n    :\nfi'
syntax_case nested_predicate_group 5 'if if { :; }; then :; fi ||\n    ! false; then\n    :\nfi\n! false'
syntax_case redirect_substitution 2 ': < "$(\n    ! true\n    printf "%s" /dev/null\n)"'
syntax_case brace_argument 3 'if {\n    printf "%s\\n" }\n    ! false\n}; then\n    :\nfi'
syntax_case actual_sockets '' 'if false ||\n        ! "$PLISTBUDDY" -c '"'"'Print :Sockets:NetbiosDatagramServices'"'"' "$NETBIOSD_PLIST" >/dev/null 2>&1; then\n    :\nfi'
syntax_case actual_wrapper '' 'if false ||\n        ! printf '"'"'%s\\n'"'"' '"'"'#!/bin/sh'"'"' '"'"'# guest-macosx: initialize HUP before netbiosd exec (docs/decisions/0037)'"'"' "trap '"'"''"'"' HUP" '"'"'exec "$@"'"'"' | cmp -s "$nbv_wrapper" -; then\n    :\nfi'
syntax_case actual_mavericks_login '' 'if false ||\n        ! has "auto-login: on: $autologin'"'"'s password" "$FBLOG"; then\n    :\nfi'
syntax_case actual_sl_login '' 'if false ||\n        ! has "auto-login: on: $autologin'"'"'s password" "$FBLOG"; then\n    :\nfi'
syntax_case actual_verify_test '' 'if true &&\n        ! grep -q "guest-macosx-firstboot: kextd: " "$FBLOG"; then\n    :\nfi'
syntax_case quoted_hash_pipeline '' 'if false ||\n    ! printf "%s" "a#;b" | cmp -s "$file" - 2>&1; then # comment\n    :\nfi'
syntax_case terminal_loops '' 'while false ||\n    ! probe; do\n    break\ndone\nuntil false &&\n    ! probe; do\n    :\ndone'
syntax_case negated_compound_if 1 '! if true; then :; fi\n:'
syntax_case negated_pipeline 1 '! printf x | cmp -s file -\n:'
syntax_case skipped_status_then 2 'if false ||\n    ! true; :; then\n    :\nfi'
syntax_case skipped_status_do 2 'while false ||\n    ! true; :; do\n    break\ndone'
syntax_case heredoc_substitution 3 'cat <<EOF\n$(\n    ! true\n    printf x\n)\nEOF'
syntax_case nested_case '' 'if case x in x) :;; esac ||\n    ! false; then\n    :\nfi'
syntax_case hash_inside_word 2 'if false ||\n    ! true;foo#;then\n    :\nfi'
syntax_case quoted_terminal 1 '! true; "then"\n:'
syntax_case comment_terminal 1 '! true; # then\n:'
syntax_case uncertain_group 2 'if false ||\n    ! (true); then\n    :\nfi'
syntax_case uncertain_braces 2 'if false ||\n    ! { true; }; then\n    :\nfi'
syntax_case uncertain_substitution 2 'if false ||\n    ! echo "$(true)"; then\n    :\nfi'
syntax_case uncertain_backticks 2 'if false ||\n    ! echo "`true`"; then\n    :\nfi'
syntax_case background 2 'if false ||\n    ! true & :; then\n    :\nfi'
syntax_case escaped_redirect 2 'if false ||\n    ! true \\>& :; then\n    :\nfi'
syntax_case quoted_redirect 2 'if false ||\n    ! true ">"& :; then\n    :\nfi'
syntax_case background_after_dup 2 'if false ||\n    ! true 2>&1& :; then\n    :\nfi'
syntax_case escaped_hash_boundary 2 'if false ||\n    ! true x\\ #; :; then\n    :\nfi'
syntax_case quoted_hash_boundary 2 'if false ||\n    ! true " "#; :; then\n    :\nfi'
syntax_case uncertain_heredoc 2 'if false ||\n    ! cat <<END; then\nx\nEND\n    :\nfi'

syntax_case nonterminal_then '2' 'if false ||\n    ! true; then :\nfi'
syntax_case nonterminal_do '2' 'while false ||\n    ! true; do break\ndone'

# spec: scripts/check-shell-portability.sh -- HEAD can match logical operators
#       after an escaped ampersand. Raw operators, even quoted, stay uncertain.
syntax_case escaped_ampersand_or 2 'if false ||\n    ! true \\&|| :; then\n    :\nfi'
syntax_case escaped_ampersand_and 2 'if false ||\n    ! true \\|&& :; then\n    :\nfi'
syntax_case quoted_or 2 'if false ||\n    ! printf "%s" "&||"; then\n    :\nfi'
syntax_case quoted_and 2 'if false ||\n    ! printf "%s" "|&&"; then\n    :\nfi'
syntax_case negated_if_prefix 1 '! if true; then\n    :\nfi\n:'
syntax_case negated_for_prefix 1 '! for x in a; do\n    :\ndone\n:'
# spec: scripts/check-shell-portability.sh -- this mid-brace predicate remains a
#       HEAD false positive; the filter does not inspect surrounding lines.
syntax_case midbrace_predicate 3 'if {\n    :\n    ! false\n}; then\n    :\nfi'

# spec: scripts/check-shell-portability.sh -- static Bash sources, reviewed with
#       bash -n separately. The suite inspects their diagnostics without requiring
#       Bash: sh -n alone can misread these prefixes as ordinary command words.
for prefix in time coproc; do
  printf '! %s if true;then\n:\nfi\n:\n' "$prefix" > "$work/bash_$prefix.sh"
  diagnostic_case "bash_$prefix" 1
done
printf '! select x in a;do\n:\ndone\n:\n' > "$work/bash_select.sh"
diagnostic_case bash_select 1
printf '! true | coproc if true;then\n:\nfi\n:\n' > "$work/bash_pipeline_coproc.sh"
diagnostic_case bash_pipeline_coproc 1
printf '! true | select x in a;do\n:\ndone\n:\n' > "$work/bash_pipeline_select.sh"
diagnostic_case bash_pipeline_select 1

# spec: scripts/check-shell-portability.sh -- dollar-prefixed quotes and nested
#       expansions stay uncertain across shell grammars, even in quoted data.
#       These static Bash fixtures are syntax-checked separately, never executed.
printf '%s\n' "! true \$'x\\'\"'; : \"; then #\"" > "$work/bash_ansi_quote.sh"
diagnostic_case bash_ansi_quote 1
printf '%s\n' 'if false ||' "    ! true \$'x'; then" ':' 'fi' > "$work/bash_ansi_predicate.sh"
diagnostic_case bash_ansi_predicate 2
printf '%s\n' 'if false ||' '    ! true $"x"; then' ':' 'fi' > "$work/bash_locale_predicate.sh"
diagnostic_case bash_locale_predicate 2
syntax_case uncertain_parameter 2 'if false ||\n    ! true "${x:-value}"; then\n    :\nfi'
printf '%s\n' 'if false ||' '    ! true "$[1+2]"; then' ':' 'fi' > "$work/bash_arithmetic_predicate.sh"
diagnostic_case bash_arithmetic_predicate 2

# spec: scripts/check-shell-portability.sh -- parsing must never execute source.
#       Extract only the functions so direct guard and mutation probes share them.
sed -n '/^conditional_predicate() {/,/^TAB=/p' "$S" | sed '$d' > "$work/filter.sh"
# shellcheck source=/dev/null  # generated functions extracted from the checker
. "$work/filter.sh"
witness="$work/must-not-exist"
candidate='! echo "$(touch '"$witness"')"; then'
if conditional_predicate "$candidate"; then echo "FAIL substitution must stay uncertain"; exit 1; fi
printf 'if : ||\n%s\n:\nfi\n' "$candidate" | /bin/sh -n
conditional_predicate '! touch '"$witness"'; then' || { echo "FAIL simple predicate must pass"; exit 1; }
conditional_predicate '! : > '"$witness"'; do' || { echo "FAIL redirected predicate must pass"; exit 1; }
[ ! -e "$witness" ] || { echo "FAIL syntax check executed source"; exit 1; }
for uncertain in '! true "x; then' "! true 'x; then" "! true; then \\" ' ! true; then
:'; do
  if conditional_predicate "$uncertain"; then echo "FAIL incomplete/multiline guard: $uncertain"; exit 1; fi
done

# spec: scripts/check-shell-portability.sh -- kill mutations of the guard pieces
#       whose absence lets the trusted syntax parser accept status-replacing lists.
mutation_case() {  # $1 name, $2 sed mutation, $3 candidate that must be rejected
  if conditional_predicate "$3"; then echo "FAIL guard accepted $1"; exit 1; fi
  sed "$2" "$work/filter.sh" > "$work/mutant.sh"
  # A missing keyword guard exposes these forms only when the host grammar
  # accepts them as ordinary words. Probe the exact scaffolds independently of
  # the mutant; a stricter parser must still protect the unconditional regression.
  expected=0
  if [ "${4:-}" = host-grammar ]; then
    if printf 'if : ||\n%s\n:\nfi\n' "$3" | /bin/sh -n 2>/dev/null ||
       printf 'while : ||\n%s\n:\ndone\n' "$3" | /bin/sh -n 2>/dev/null; then
      expected=0
    else
      expected=1
    fi
  fi
  actual=0
  # shellcheck source=/dev/null  # generated mutation of the extracted functions
  ( . "$work/mutant.sh"; conditional_predicate "$3" ) || actual=1
  if [ "$actual" -ne "$expected" ]; then
    echo "FAIL $1 mutation: expected exit $expected, got $actual"; exit 1
  fi
}
mutation_case semicolon 's/semicolons != 1/semicolons < 1/' '! true; :; then'
mutation_case background '/if (c == "&"/d' '! true & :; then'
mutation_case groups '/if (index("(){}", c))/d' '! (true); then'
mutation_case substitution '/if (NR != 1/d' '! echo "$(true)"; then'
mutation_case backticks '/if (NR != 1/d' '! echo "`true`"; then'
mutation_case heredoc '/if (NR != 1/d' '! echo "<<"; then'
mutation_case terminal '/if (substr($0, separator/d' '! true; then :'
mutation_case comment_boundary 's/c == "#" \&\& boundary/c == "#"/' '! true;then#;then'
mutation_case escaped_redirection 's/previous != "<" \&\& previous != ">"/substr($0, i - 1, 1) != "<" \&\& substr($0, i - 1, 1) != ">"/' '! true \>& :; then'
mutation_case syntax_gate 's@/bin/sh -n@true@g' '! true >; then'
mutation_case logical_or '/if (index($0, "||")/d' '! true \&|| :; then'
mutation_case logical_and '/if (index($0, "||")/d' '! printf "%s" "|&&"; then'
mutation_case escaped_operator '/if (index($0, "||")/d' '! printf "%s" "\||"; then'
mutation_case ansi_quote '/if (index($0, "$\\047")/d' "! true \$'x'; then"
mutation_case locale_quote '/if (index($0, "$\\047")/d' '! true $"x"; then'
mutation_case parameter '/if (index($0, "$\\047")/d' '! true "${x:-value}"; then'
mutation_case arithmetic '/if (index($0, "$\\047")/d' '! true "$[1+2]"; then'
mutation_case bash_time '/if ($0 ~/d' '! time if true;then' host-grammar
mutation_case bash_coproc '/if ($0 ~/d' '! coproc if true;then' host-grammar
mutation_case bash_select '/if ($0 ~/d' '! select x in a;do' host-grammar
mutation_case bash_function '/if ($0 ~/d' '! function f;then' host-grammar
mutation_case bash_brackets '/if ($0 ~/d' '! [[ x;then' host-grammar
mutation_case pipeline_coproc '/if ($0 ~/d' '! true | coproc if true;then' host-grammar
mutation_case pipeline_select '/if ($0 ~/d' '! true | select x in a;do' host-grammar

# spec: scripts/check-shell-portability.sh -- a filter that hides the original
#       bare-negation sample must fail its extended self-check, even on clean input.
sed 's/if conditional_predicate "${hit#\*:}"; then/if :; then/' "$S" > "$work/dead-negation.sh"
if out="$(cd "$work/ok" && sh "$work/dead-negation.sh" 2>&1)"; then
  echo "FAIL a filter hiding its original sample must refuse clean"; exit 1
fi
printf '%s\n' "$out" | grep -qi 'lint is dead' || { echo "FAIL should name the dead filter: $out"; exit 1; }

sed 's/^sort\[\[:space:\]\]/sortXX[[:space:]]/' "$S" > "$work/dead.sh"
if out="$(cd "$work/ok" && sh "$work/dead.sh" 2>&1)"; then echo "FAIL: a rule that no longer matches its own sample is DEAD and must say so rather than pass"; exit 1; fi
printf '%s\n' "$out" | grep -qi 'lint is dead' || { echo "FAIL should say the lint is dead: $out"; exit 1; }

(cd "$here/.." && sh "$S" >/dev/null) || { echo "FAIL shipyard's own scripts must be clean"; exit 1; }

echo "PASS: shell-portability"
