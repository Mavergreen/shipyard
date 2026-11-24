#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-shell-portability.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/unchecked-subshell.XXXXXX")"; trap 'rm -rf "$work"' EXIT

flagged() {  # $1 = file: the lines the subshell rule reports, one per line
  sh "$S" "$1" 2>&1 | sed -n 's/^check-shell-portability: .*:\([0-9][0-9]*\) uses an unchecked subshell.*/\1/p' | tr '\n' ' '
}
expect() {  # $1 = name, $2 = expected lines ("1 2 " or ""), $3 = printf-escaped source
  printf '%b\n' "$3" > "$work/$1.sh"
  got="$(flagged "$work/$1.sh")"
  [ "$got" = "$2" ] || { echo "FAIL $1: expected lines [$2], got [$got]"; sh "$S" "$work/$1.sh" 2>&1 | sed 's/^/    | /'; exit 1; }
}

# spec: scripts/check-shell-portability.sh -- each of these was measured on 10.9.5's /bin/sh
#       (bash 3.2.53) under sh -e: the script carried on past the failing subshell.
expect masked_top '1 ' '( false )\n:'
expect masked_redirected '1 ' '( false ) > /dev/null 2>&1\n:'
expect masked_and_tail '1 ' 'true && ( false )\n:'
expect masked_or_tail '1 ' 'false || ( false )\n:'
expect masked_pipeline_tail '1 ' 'true | ( false )\n:'
expect masked_if_body '1 ' 'if true; then ( false ); fi\n:'
expect masked_else_body '1 ' 'if false; then :; else ( false ); fi\n:'
expect masked_for_body '1 ' 'for i in 1; do ( false ); done\n:'
expect masked_while_body '1 ' 'while :; do ( false ); break; done\n:'
expect masked_case_body '1 ' 'case a in a) ( false ) ;; esac\n:'
expect masked_group '1 ' '{ ( false ); }\n:'
expect masked_function_not_last '1 ' 'f() { ( false ); echo; }\nf'
expect masked_arith '1 ' '(( 0 ))\n:'
expect masked_multiline '1 ' '( cd /\n  false\n)\n:'
expect masked_multiline_redirected '1 ' '(\n  false\n) > /dev/null\n:'
expect masked_inner_not_last '1 2 ' '(\n  ( false )\n  true\n)\n:'
expect masked_two '1 3 ' '( false )\n:\n( false ); :'

# spec: scripts/check-shell-portability.sh -- each of these stops on 10.9 (or is ignored by every
#       shell alike), so none is reported.
expect stops_or_exit '' '( false ) || exit 1\n:'
expect stops_or_return '' 'f() { ( false ) || return 1; :; }\nf'
expect stops_or_capture '' 'rc=0\n( false ) || rc=$?\n:'
expect stops_multiline_or '' '( cd /\n  false\n) || exit 1\n:'
expect stops_multiline_or_next_line '' '( cd / &&\n  false\n) \\\n  || exit 1\n:'
expect stops_and_more '' '( false ) && echo more\n:'
expect stops_pipeline_head '' '( false ) | cat\n:'
expect stops_background '' '( false ) &\nwait\n:'
expect stops_if_condition '' 'if ( false ); then :; fi\n:'
expect stops_elif_condition '' 'if false; then :; elif ( false ); then :; fi\n:'
expect stops_while_condition '' 'while ( false ); do :; done\n:'
expect stops_negated '' '! ( false )\n:'
expect stops_status_next_line '' '( false )\n[ $? -eq 0 ] || exit 1\n:'
expect stops_status_same_line '' '( false ); rc=$?\n:'
expect stops_function_last '' 'f() { :; ( false ); }\nf'
expect stops_function_last_redirected '' 'f() {\n  ( false ) >/dev/null\n}\nf'
expect stops_function_body '' 'f() ( false )\nf'
expect stops_function_keyword '' 'function f { ( false ); }\nf'
expect stops_function_last_if '' 'f() { if true; then ( false ); fi; }\nf'
expect stops_checked_group '' '{ ( false ); } || exit 1\n:'
expect stops_checked_if '' 'if true; then ( false ); fi || exit 1\n:'
expect stops_nested_last '' '( true; ( false ) ) || exit 1\n:'
expect stops_cmdsub '' 'x=$( ( false ) )\ny="$( ( false ); echo )"\n:'
expect stops_script_last '' ':\n( false )'
expect stops_group_plain '' '{ false; }\ntrue && false\nx=$(false)\n:'
expect stops_bats_test_last '' '@test "t" {\n  ( false )\n}'
expect masked_bats_test_not_last '2 ' '@test "t" {\n  ( false )\n  true\n}'

# spec: scripts/check-shell-portability.sh -- parentheses that are not a subshell at command position.
expect fp_substitutions '' 'y="$(echo "(a)")"\nz=$((1 + (2 * 3)))\necho $(( (1) ))\necho `( false )`\n:'
expect fp_case_patterns '' 'case $x in\n  a) echo ;;\n  (b) echo ;;\n  *.sh|*.bats) echo ;;\nesac\n:'
expect fp_quotes_comments '' 'echo "( false )" '"'"'( false )'"'"' # ( false )\n# ( false )\n:'
expect fp_heredocs '' 'cat <<EOF\n( false )\nEOF\ncat <<-'"'"'EOF'"'"'\n\t( false )\n\tEOF\ncat <<"A" <<B\n( false )\nA\n( false )\nB\n:'
expect fp_function_definitions '' 'k() {\n  :\n}\nm () { :; }\n:'
expect fp_bash_words '' 'arr=(a b)\ndiff <(a) <(b) || :\n[[ $x =~ (a|b) ]] || false\n:'
expect fp_exempt '' '( false ) # portability-ok: a fixture\n:'

# spec: scripts/check-shell-portability.sh -- mavericks-vm's guest check refuses and passes these
#       too (its tests/subshell_check.bats); the two rules must agree. It does not look inside a
#       subshell, so this one is stricter there.
expect mvm_or_right_side '1 ' 'make || ( echo no; exit 1 )\ntrue'
expect mvm_while_body '2 ' 'while read l; do\n  ( false )\n  echo "$l"\ndone < list\ntrue'
expect mvm_function_not_last '1 ' 'f() { ( false ); true; }\nf'
expect mvm_conditions '' 'if [ -d x ] && ( cd x && false ); then :; elif ( false ); then :; fi\ntrue'
expect mvm_substitutions '' 'echo "$( (cd x; ls) )"\nx=`(false)`\nfor ((i = 0; i < 2; i++)); do :; done\necho a\\(b\ntrue'
expect mvm_heredoc_pipe '' 'cat <<'"'"'X'"'"' | sh\n( false )\nX\ntrue'
expect for_positional '2 ' 'for c do\n  ( false )\n  :\ndone\n:'
expect mvm_case_no_terminator '' 'case $x in\n  a) echo a ;;\n  *) echo other\nesac\ntrue'

# spec: scripts/check-shell-portability.sh -- a file the parser cannot follow warns and is skipped.
printf 'echo "unterminated\n' > "$work/broken.sh"
out="$(sh "$S" "$work/broken.sh" 2>&1)" || { echo "FAIL an unparseable file must not fail the gate: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'broken.sh:.* cannot be parsed' || { echo "FAIL an unparseable file must say so: $out"; exit 1; }

out="$(sh "$S" "$work/masked_top.sh" 2>&1)" && { echo "FAIL a masked subshell must fail the gate"; exit 1; }
printf '%s\n' "$out" | grep -q '|| exit 1' || { echo "FAIL the fix must name || exit 1: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '\[ \$? -eq 0 \] || exit 1' || { echo "FAIL the fix must name the \$? form: $out"; exit 1; }

# spec: scripts/check-shell-portability.sh -- the guest's run:/prepare: text is shell on 10.9 too;
#       a run: step on a GitHub runner is not, so it is not read.
mkdir -p "$work/wf/.github/workflows"
cat > "$work/wf/.github/workflows/release.yml" <<'EOF'
jobs:
  vm-test:
    runs-on: ubuntu-latest
    steps:
      - run: |
          ( false )
          :
      - name: gate
        uses: Mavergreen/mavericks-vm@v1
        with:
          prepare: ( false ); true
          run: |
            ( cd gate && sh run.sh )
            ( cd gate && sh run.sh ) || exit 1
            cat <<EOT
            ( false )
            EOT
            :
      - uses: actions/checkout@v7
        with:
          run: ( false ); true
  self:
    runs-on: ubuntu-latest
    steps:
    - shell: mavericks {0}
      run: >-
        ( false ); true
EOF
got="$(flagged "$work/wf/.github/workflows/release.yml")"
[ "$got" = '11 13 27 ' ] || { echo "FAIL guest steps: expected lines [11 13 27 ], got [$got]"; exit 1; }
(cd "$work/wf" && git init -q && git add -A) || exit 1
got="$(cd "$work/wf" && sh "$S" 2>&1 | sed -n 's/.*release.yml:\([0-9]*\) uses an unchecked subshell.*/\1/p' | tr '\n' ' ')"
[ "$got" = '11 13 27 ' ] || { echo "FAIL a checkout must scan its workflows: expected [11 13 27 ], got [$got]"; exit 1; }

# spec: scripts/conventions-grandfathered -- an "unchecked-subshell <repo> <path>" line turns that
#       path's findings into warnings, in that repo only.
cp -R "$here/../scripts" "$work/sc"
mkdir -p "$work/gf" && (cd "$work/gf" && git init -q) || exit 1
printf '( false )\n:\n' > "$work/gf/a.sh"; printf '( false )\n:\n' > "$work/gf/b.sh"
(cd "$work/gf" && git add -A) || exit 1
printf 'unchecked-subshell gf a.sh\n' > "$work/sc/conventions-grandfathered"
out="$(cd "$work/gf" && GITHUB_REPOSITORY=Mavergreen/gf sh "$work/sc/check-shell-portability.sh" 2>&1)" && { echo "FAIL b.sh is not grandfathered: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '::warning::.*a.sh:1 .*grandfathered' || { echo "FAIL a grandfathered path must warn: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '^check-shell-portability: b.sh:1 uses an unchecked subshell' || { echo "FAIL b.sh must fail: $out"; exit 1; }
printf 'unchecked-subshell gf a.sh\nunchecked-subshell gf b.sh\n' > "$work/sc/conventions-grandfathered"
(cd "$work/gf" && GITHUB_REPOSITORY=Mavergreen/gf sh "$work/sc/check-shell-portability.sh" >/dev/null 2>&1) || { echo "FAIL both paths grandfathered must pass"; exit 1; }
if (cd "$work/gf" && GITHUB_REPOSITORY=Mavergreen/other sh "$work/sc/check-shell-portability.sh" >/dev/null 2>&1); then
  echo "FAIL another repo's grandfathered lines must not excuse this one"; exit 1
fi

# spec: scripts/check-shell-portability.sh -- an analyzer that reports nothing is dead, not clean.
sed 's/if (!masked(i)) continue/continue/' "$S" > "$work/dead.sh"
out="$(sh "$work/dead.sh" "$work/stops_or_exit.sh" 2>&1)" && { echo "FAIL a dead subshell rule must refuse clean: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'lint is dead' || { echo "FAIL should say the lint is dead: $out"; exit 1; }

echo "PASS: unchecked-subshell"
