#!/bin/sh
# platform: host-agnostic
#   usage: check-release-sentence.sh [--allow WORD]... FILE
#          Is FILE one release-note sentence a reader of the update dialog can use? Exit 0 silently,
#          1 with a one-line complaint naming the first rule broken, 2 on bad usage.
#   rules, in the order checked:
#     - valid UTF-8; no control character but tab (after CRs are dropped)
#     - after trimming each line's leading and trailing whitespace: not empty; exactly one non-empty line
#     - at most 30 words; ends with '.', '!' or '?'
#     - no formatting: ` * # < > | [ ] ~, '_' at a word edge (an inner '_' is fine), a leading '-' or
#       '+', or a leading number followed by '.' or ')' and then whitespace or the end of the line
#       ("1. ", "1) "); the complaint names the character
#     - no URL (scheme:// or www.)
#     - no hex run of 7 or more that has a digit and a letter a-f
#     - no base64-looking run: 20 or more [A-Za-z0-9+] in a row (any other character, '/' and '='
#       included, ends a run) holding a digit, an uppercase and a lowercase letter
#     - no '@' before a letter or digit (a GitHub @-mention notifies that user from every release)
#     - no internal term, any case, whole word, plural -s included: CI runner workflow conformance
#       dogfood agent subagent plan QUEUE commit SHA shipyard Renovate ingredient pin, "base recipe(s)",
#       "check <number>", ".yml"; '_' separates words here, so release_workflow is refused; --allow WORD exempts one of these words
#     - does not open with "This release", "This version", "We ", "I ", "Cut to" or "Note:" (any case)
#     - no all-caps word of 4 or more letters except ECDSA DHCP HTTP HTTPS JSON NVRAM UEFI QEMU LLVM
#       GODEBUG EPYC; a token with an inner '_' (SSL_CERT_FILE) is an identifier and exempt
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Release notes" --
#       a sentence is shown to end users verbatim, so it carries no markup, no link, no identifier
#       and none of the project's own process vocabulary.
set -eu

fail() { echo "check-release-sentence: $f: $1" >&2; exit 1; }
usage() { echo "usage: check-release-sentence.sh [--allow WORD]... FILE" >&2; exit 2; }

allowed=
while [ $# -gt 0 ]; do
  case "$1" in
    --allow) [ $# -ge 2 ] || usage; allowed="$allowed $2"; shift 2 ;;
    --*) usage ;;
    *) break ;;
  esac
done
[ $# -eq 1 ] || usage
f="$1"

[ -f "$f" ] && [ -r "$f" ] || fail "cannot read the file"
iconv -f UTF-8 -t UTF-8 < "$f" >/dev/null 2>&1 || fail "not valid UTF-8"
LC_ALL=C tr -d '\r\t' < "$f" | LC_ALL=C grep '[[:cntrl:]]' >/dev/null 2>&1 \
  && fail "control character other than tab is not allowed"

norm="$(tr -d '\r' < "$f" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
[ -n "$norm" ] || fail "empty; a sentence must say something"

count="$(printf '%s\n' "$norm" | awk 'NF { n++ } END { print n + 0 }')"
first="$(printf '%s\n' "$norm" | sed -n '1p')"
[ "$count" -eq 1 ] && [ -n "$first" ] || fail "must be exactly one line"

words="$(printf '%s\n' "$first" | awk '{ print NF }')"
[ "$words" -le 30 ] || fail "$words words; at most 30 words"

case "$first" in
  *[.!?]) ;;
  *) fail "must end with '.', '!' or '?'" ;;
esac

has() { printf '%s\n' "$first" | grep -E "$@" >/dev/null 2>&1; }

bad="$(printf '%s\n' "$first" | LC_ALL=C awk '{
  n = split("` * # < > | [ ] ~", chars, " ")
  for (i = 1; i <= n; i++) if (index($0, chars[i])) { print chars[i]; exit }
  if (match($0, /(^|[^A-Za-z0-9_\200-\377])_|_([^A-Za-z0-9_\200-\377]|$)/)) { print "_"; exit }
  if (match($0, /^[-+]/)) print substr($0, 1, 1)
}')"
[ -z "$bad" ] || fail "contains formatting character '$bad'"
has '^[0-9]+[.)]([[:space:]]|$)' && fail "starts with a list number"
has -i '[a-z][a-z0-9+.-]*://|(^|[^[:alnum:]])www\.' && fail "URL is not allowed"
run() {
  printf '%s\n' "$first" | awk -v bad="$1" -v min="$2" -v letters="$3" -v also="$4" '{
    gsub(bad, " ")
    for (i = 1; i <= NF; i++)
      if (length($i) >= min && $i ~ /[0-9]/ && $i ~ letters && $i ~ also) found = 1
  } END { exit !found }'
}
run '[^0-9A-Fa-f]' 7 '[A-Fa-f]' '.' && fail "hex run of 7 or more is not allowed"
run '[^A-Za-z0-9+]' 20 '[A-Z]' '[a-z]' && fail "base64-looking run of 20 or more is not allowed"
has '@[[:alnum:]]' && fail "@-mention is not allowed"

terms="CI runner workflow conformance dogfood agent subagent plan QUEUE commit SHA shipyard Renovate ingredient pin"
pattern=
for t in $terms; do
  skip=false
  for a in $allowed; do
    [ "$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')" ] && skip=true
  done
  $skip || pattern="$pattern|$t"
done
pattern="(${pattern#|})s?|base recipes?|check [0-9]+"
printf '%s\n' "$first" | tr _ ' ' | grep -iwE "$pattern" >/dev/null 2>&1 && fail "internal term is not allowed"
has -i '\.yml' && fail "internal term '.yml' is not allowed"

has -i '^(this release|this version|we |i |cut to|note:)' && fail "opens with process talk"

stop=" ECDSA DHCP HTTP HTTPS JSON NVRAM UEFI QEMU LLVM GODEBUG EPYC "
caps="$(printf '%s\n' "$first" | awk -v stop="$stop" '{
  gsub(/[^A-Za-z0-9_]/, " ")
  for (i = 1; i <= NF; i++) {
    if (index($i, "_")) continue
    t = $i; gsub(/[^A-Za-z]/, " ", t); m = split(t, parts, " ")
    for (j = 1; j <= m; j++)
      if (parts[j] ~ /^[A-Z][A-Z][A-Z][A-Z]+$/ && index(stop, " " parts[j] " ") == 0) { print parts[j]; exit }
  }
}')"
[ -z "$caps" ] || fail "all-caps run '$caps' is not allowed"

exit 0
