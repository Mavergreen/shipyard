#!/bin/sh
# platform: host-agnostic
#   usage: check-release-sentence.sh [--allow WORD]... FILE
#          Is FILE one release-note sentence a reader of the update dialog can use? Exit 0 silently,
#          1 with a one-line complaint naming the first rule broken, 2 on bad usage.
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

if has '[`*#<>|]|\[|\]|(^|[[:space:]])_|_([[:space:]]|$)|^[-+]|^[0-9]+\.'; then
  fail "Markdown or formatting characters are not allowed"
fi
has -i '[a-z][a-z0-9+.-]*://|(^|[^[:alnum:]])www\.' && fail "URL is not allowed"
run() {
  printf '%s\n' "$first" | awk -v bad="$1" -v min="$2" -v whole="$3" -v letters="$4" '{
    gsub(bad, " ")
    for (i = 1; i <= NF; i++)
      if (length($i) >= min && $i ~ /[0-9]/ && $i ~ whole && $i ~ letters) found = 1
  } END { exit !found }'
}
run '[^0-9A-Fa-f]' 7 '^[0-9A-Fa-f]+$' '[A-Fa-f]' && fail "hex run of 7 or more is not allowed"
run '[^A-Za-z0-9+/]' 20 '.' '[A-Za-z]' && fail "base64-looking run of 20 or more is not allowed"

terms="CI runner workflow conformance dogfood agent subagent plan QUEUE commit SHA shipyard Renovate ingredient pin"
pattern=
for t in $terms; do
  skip=false
  for a in $allowed; do
    [ "$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')" ] && skip=true
  done
  $skip || pattern="$pattern|$t"
done
pattern="(${pattern#|})(s|es)?|base recipes?|check [0-9]+"
has -i -w "$pattern" && fail "internal term is not allowed"
has -i '\.yml' && fail "internal term '.yml' is not allowed"

has -i '^(this release|this version|we |i |cut to|note:)' && fail "opens with process talk"

stop=" ECDSA DHCP HTTP HTTPS JSON NVRAM UEFI QEMU LLVM GODEBUG EPYC "
caps="$(printf '%s\n' "$first" | awk -v stop="$stop" '{
  gsub(/[^A-Za-z]/, " ")
  for (i = 1; i <= NF; i++)
    if ($i ~ /^[A-Z][A-Z][A-Z][A-Z]+$/ && index(stop, " " $i " ") == 0) { print $i; exit }
}')"
[ -z "$caps" ] || fail "all-caps run '$caps' is not allowed"

exit 0
