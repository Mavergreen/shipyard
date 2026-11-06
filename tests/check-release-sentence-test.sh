#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-release-sentence.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/check-release-sentence.XXXXXX")"; trap 'rm -rf "$work"' EXIT

ok() {  # $1 = label; file content on stdin; extra args via $OPTS
  cat > "$work/s.txt"
  sh "$S" ${OPTS:-} "$work/s.txt" >/dev/null 2>&1 || { echo "FAIL should pass: $1"; exit 1; }
}
no() {  # $1 = label, $2 = expected substring of the complaint; content on stdin
  cat > "$work/s.txt"
  if out="$(sh "$S" ${OPTS:-} "$work/s.txt" 2>&1)"; then echo "FAIL should fail: $1"; exit 1; fi
  printf '%s\n' "$out" | grep -q "$2" || { echo "FAIL $1: complaint lacked '$2': $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "^check-release-sentence: $work/s.txt: " || { echo "FAIL $1: complaint not in the standard shape: $out"; exit 1; }
}

ok "plain" <<'X'
Stop now stays stopped until you start Docker again.
X
ok "hyphenated word" <<'X'
Pure-Go programs now run on Mavericks.
X
ok "rebuild instruction" <<'X'
Rebuild your Go programs to use the new SDK.
X
ok "two sentences, one line" <<'X'
Does it work? Yes.
X
printf 'Stop now stays stopped.\r' > "$work/s.txt"
sh "$S" "$work/s.txt" >/dev/null 2>&1 || { echo "FAIL should pass: CRLF, no final newline"; exit 1; }
ok "stoplist acronym" <<'X'
ECDSA keys now load.
X
ok "trailing blank line is not a second line" <<'X'
Stop now stays stopped.

X
OPTS="--allow shipyard"; ok "allowed term" <<'X'
Shipyard now installs beside cmake.
X
OPTS=

: > "$work/s.txt"
if out="$(sh "$S" "$work/s.txt" 2>&1)"; then echo "FAIL should fail: empty"; exit 1; fi
printf '%s\n' "$out" | grep -q "empty" || { echo "FAIL empty: $out"; exit 1; }
if sh "$S" "$work/missing" >/dev/null 2>&1; then echo "FAIL should fail: missing file"; exit 1; fi
if sh "$S" >/dev/null 2>&1; then echo "FAIL should fail: no args"; exit 1; fi
[ "$(sh "$S" >/dev/null 2>&1 || echo $?)" = 2 ] || { echo "FAIL usage exit is not 2"; exit 1; }
[ "$(sh "$S" --bogus x >/dev/null 2>&1 || echo $?)" = 2 ] || { echo "FAIL unknown option exit is not 2"; exit 1; }

no "two lines" "one line" <<'X'
Stop now stays stopped.
Start it again.
X
no "blank first line" "one line" <<'X'

Stop now stays stopped.
X
printf '  We fixed Stop.\n' | no "indented opener" "opens with"
printf ' - Stop now stays.\n' | no "indented bullet" "Markdown"
w31="a b c d e f g h i j k l m n o p q r s t u v w x y z aa bb cc dd ee."
printf '%s\n' "$w31" | no "31 words" "30 words"
w30="a b c d e f g h i j k l m n o p q r s t u v w x y z aa bb cc dd."
printf '%s\n' "$w30" | ok "30 words"
no "no final punctuation" "end with" <<'X'
Stop now stays stopped
X

for bad in 'Stop `now` stays stopped.' 'Stop *now* stays stopped.' 'Stop #1 stays stopped.' \
  'Stop [now] stays stopped.' 'Stop now] stays stopped.' 'Stop <now> stays stopped.' 'Stop now | stays stopped.' \
  'Stop _now stays stopped.' 'Stop now_ stays stopped.' '- Stop now stays stopped.' \
  '+ Stop now stays stopped.' '1. Stop now stays stopped.'; do
  printf '%s\n' "$bad" | no "Markdown: $bad" "Markdown"
done
ok "inner underscore" <<'X'
The set_value call now works.
X
no "URL" "URL" <<'X'
See https://x.org for more.
X
no "hex" "hex" <<'X'
Fixed in 3f2a9c1 today.
X
ok "short hex-looking word" <<'X'
Fixed in decade today.
X
ok "all-letter hex-looking word" <<'X'
Stop now stays defaced and accede.
X
ok "date version is not hex" <<'X'
Recaulk 20261025 now links.
X
ok "20+ letter word" <<'X'
The internationalizationally word is fine.
X
no "base64 needs letter and digit mix" "base64" <<'X'
The key gHiJkLmNoPqRsTuVwXyZ12 is gone.
X
for term in runners commits ingredients pins agents workflows plans Renovates; do
  printf 'The %s stay stopped.\n' "$term" | no "plural internal term: $term" "internal term"
done
no "base64" "base64" <<'X'
The key QUJDREVGR0hJSk1TU5P0 is gone.
X

for term in CI runner workflow conformance dogfood agent subagent plan QUEUE commit SHA shipyard Renovate ingredient pin \
  "base recipe" "check 22" ".yml" "ci"; do
  printf 'The %s stays stopped.\n' "$term" | no "internal term: $term" "internal term"
done
ok "CIA is not CI" <<'X'
The CIA stays stopped.
X
ok "pinned is not pin" <<'X'
Stop stays pinned.
X
ok "check without number" <<'X'
Stop now checks the disk.
X
no "internal term, mixed case" "internal term" <<'X'
Stop stays RUNNER.
X

for op in "This release fixes Stop." "This version fixes Stop." "We fixed Stop." "I fixed Stop." "Cut to fix Stop." "Note: Stop is fixed."; do
  printf '%s\n' "$op" | no "opener: $op" "opens with"
done
ok "opener word inside" <<'X'
Stop now works as we expected.
X
no "all-caps" "all-caps" <<'X'
ACCEPTANCE IS STILL MANUAL.
X
ok "short all-caps" <<'X'
Stop now works with the SDK.
X
no "internal term without allow" "internal term" <<'X'
Shipyard now installs beside cmake.
X
OPTS="--allow shipyard"; no "allow does not exempt others" "internal term" <<'X'
Shipyard now installs beside the runner.
X
OPTS=

printf 'Works\001 now.\n' | no "control character" "control character"
printf 'Works now.\f\n' | no "trailing form feed" "control character"
printf 'Works\tnow.\n' | ok "tab"
printf 'Caf\351 opens now.\n' | no "Latin-1 byte" "not valid UTF-8"
printf 'Caf\303\251 opens now.\n' | ok "UTF-8 e-acute"

ok "leading version number" <<'X'
10.9 users can now open files.
X
for bad in '1) Stop.' '1. Stop.'; do
  printf '%s\n' "$bad" | no "numbered list: $bad" "Markdown"
done

ok "path is not base64" <<'X'
Go now installs in /usr/local/mavergreen/go127 by default.
X
ok "setting is not base64" <<'X'
Set GODEBUG=x509usefallbackroots=0 to use them.
X
no "base64 with plus" "base64" <<'X'
The key XQ+fNmP4kL9sT2vW8yZ1aB3c is gone.
X

no "mention" "@-mention" <<'X'
Thanks to @wowfunhappy for the patch.
X
ok "name without mention" <<'X'
Wowfunhappy wrote the patch.
X

no "corpus: yml" "internal term" <<'X'
Cut to exercise the shared publish-release.yml.
X
no "corpus: backtick path" "Markdown" <<'X'
`docs/decisions/0009` has the measurements.
X

echo PASS
