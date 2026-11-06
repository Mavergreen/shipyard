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
  printf '%s\n' "$out" | grep -qF -- "$2" || { echo "FAIL $1: complaint lacked '$2': $out"; exit 1; }
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
if out="$(sh "$S" "$work/missing" 2>&1)"; then echo "FAIL should fail: missing file"; exit 1; fi
printf '%s\n' "$out" | grep -q "cannot read the file" || { echo "FAIL missing file: $out"; exit 1; }
if [ "$(id -u)" != 0 ]; then
  printf 'Stop now stays stopped.\n' > "$work/locked.txt"; chmod 000 "$work/locked.txt"
  if out="$(sh "$S" "$work/locked.txt" 2>&1)"; then echo "FAIL should fail: unreadable file"; exit 1; fi
  printf '%s\n' "$out" | grep -q "cannot read the file" || { echo "FAIL unreadable file: $out"; exit 1; }
  chmod 600 "$work/locked.txt"
fi
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
printf ' - Stop now stays.\n' | no "indented bullet" "formatting character"
w31="a b c d e f g h i j k l m n o p q r s t u v w x y z aa bb cc dd ee."
printf '%s\n' "$w31" | no "31 words" "30 words"
w30="a b c d e f g h i j k l m n o p q r s t u v w x y z aa bb cc dd."
printf '%s\n' "$w30" | ok "30 words"
no "no final punctuation" "end with" <<'X'
Stop now stays stopped
X

for pair in '`=Stop `now` stays stopped.' '*=Stop *now* stays stopped.' '#=Stop #1 stays stopped.' \
  '[=Stop [now] stays stopped.' ']=Stop now] stays stopped.' '<=Stop <now> stays stopped.' \
  '>=Stop now> stays stopped.' '|=Stop now | stays stopped.' '~=Stop ~~now~~ stays stopped.' \
  '_=Stop _now stays stopped.' '_=Stop now_ stays stopped.' '_=Stop now_.' '_=_Stop now stays stopped.' \
  '_=Stop (_now) stays stopped.' '_=Stop now (stays_) stopped.' \
  '-=- Stop now stays stopped.' '+=+ Stop now stays stopped.'; do
  printf '%s\n' "${pair#*=}" | no "formatting: ${pair#*=}" "contains formatting character '${pair%%=*}'"
done
printf '%s\n' '1. Stop now stays stopped.' | no "numbered list" "list number"
printf '%s\n' 'Stop *now* and `then` go.' | no "one of several formatting characters is named" "formatting character '\`'"
printf '%s\n' 'Write to me at me@example.com for help.' | no "email autolink" "@-mention"
printf '%s\n' 'Your ~/ folder stays.' | no "tilde" "formatting character '~'"
ok "env var" <<'X'
Set SSL_CERT_FILE to use your own certificates.
X
ok "env var with digits" <<'X'
Set GODEBUG_X2 to see more.
X
printf 'The caf\303\251_au file opens now.\n' | ok "underscore between non-ASCII and ASCII letters"
printf 'The caf\303\251_ file opens now.\n' | no "underscore after a non-ASCII letter at a word edge" "formatting character '_'"
printf 'The _\303\251cole file opens now.\n' | no "underscore before a non-ASCII letter at a word edge" "formatting character '_'"
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
for term in runners commits ingredients pins agents workflows plans Renovates SHAs; do
  printf 'The %s stay stopped.\n' "$term" | no "plural internal term: $term" "internal term"
done
for word in planes pines; do
  printf 'The %s stay stopped.\n' "$word" | ok "not a plural internal term: $word"
done
no "base64" "base64" <<'X'
The key QUJDREVGR0hJSk1TU5P0 is gone.
X

for term in CI runner workflow conformance dogfood agent subagent plan QUEUE commit SHA shipyard Renovate ingredient pin \
  "base recipe" "check 22" ".yml" "ci"; do
  printf 'The %s stays stopped.\n' "$term" | no "internal term: $term" "internal term"
done
for snake in "Run the release_workflow now." "The CI_runner stays." "Automatically cut via workflow_dispatch local_release."; do
  printf '%s\n' "$snake" | no "internal term inside an identifier: $snake" "internal term"
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
no "all-caps next to an identifier" "all-caps run 'CERT'" <<'X'
Set CERT to SSL_CERT_FILE please.
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
  printf '%s\n' "$bad" | no "numbered list: $bad" "list number"
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
no "corpus: backtick path" "formatting character" <<'X'
`docs/decisions/0009` has the measurements.
X

# spec: scripts/check-release-sentence.sh -- examples quoted from the release-notes survey: each bad one fails, each good one, converted, passes
corpus_no() { printf '%s\n' "$3" | no "survey: $1" "$2"; }
corpus_no "swift 6.3.3-mavericks.2" "formatting character '\`'" "Cut to exercise the shared \`publish-release.yml\`."
corpus_no "swift 6.3.3-mavericks.2 caveat" "internal term" "ACCEPTANCE IS STILL MANUAL: a macOS 26 runner cannot exercise the 10.9-only behaviour this runtime exists to fix."
corpus_no "swift 6.3.3-mavericks.3" "end with" "First release through the artifact conformance check, which asserts the .pkg, the appcast and the tag agree…"
corpus_no "swift 6.3.3-mavericks.4 key" "base64" "The updater now trusts the Mavergreen org-wide signing key (/XQ+fNmP4nxdj9jnKmJDwL8rnsKYz6Kg5X61REAIqkI=)."
corpus_no "swift-toolchain commit" "formatting character '\`'" "commit \`82cdc19fa54d566969527b56f587ea8ea30bef51\`."
corpus_no "packer .7 comment" "30 words" "Nothing a box does has changed. This release changes only a comment in the Aqua Transport layer's template, \`mavericks-aquatransport\`, which now says that nothing in that template's directory is part of the base recipe."
corpus_no "packer .7 purpose" "internal term" "That comment is the release's whole purpose: it proves the base recipe works as v0.20261005.6 promised."
corpus_no "packer .8" "internal term" "This is the Mavergreen family's check 22, which now fails the build when a new script doesn't say where it runs."
corpus_no "packer 0040" "formatting character '\`'" "This release exists to capture the next stall, and \`docs/decisions/0040\` describes what is read."
corpus_no "packer .4" "internal term" "v0.20261005.3's build peaked at 80 GiB of a GitHub runner's 85 GiB free."
corpus_no "container-tools dispatch" "internal term" "Automatically cut via workflow_dispatch local_release."
corpus_no "container-tools template" "internal term" "Automatically cut from a build-ingredient bump."
corpus_no "container-tools bold" "end with" "**Migration hardening (found by dogfooding on a real 10.9 box):**"
corpus_no "golang-126 bold" "end with" "**Pure-Go programs now run on Mavericks.**"
corpus_no "golang-127 bold" "formatting character '*'" "**The cross toolchain needs macOS 13 or later**, as upstream Go 1.27 does."
corpus_no "packer warning bold" "end with" "Images and boxes contain Apple's operating system. **Never publish them.**"
corpus_no "claude-code benchmark" "formatting character '\`'" "\`rg\` 1.50x, \`ugrep\` 1.47x, \`bfs\` 4.19x."
corpus_no "claude-code avxemu" "formatting character '\`'" "Second release. Mavergreen's \`avxemu\` (which lets Claude Code run on CPUs without AVX2) is now linked into the patched binary instead of being injected with \`DYLD_INSERT_LIBRARIES\`."
corpus_no "rust" "formatting character '\`'" "\`rustc\` and \`cargo\` now link with Mavergreen clang22 by default."
for good in "Docker tells you when your Mac's disk is full." "Docker won't start into a full disk." \
  "Long VM image updates are left alone." "Free some space and Docker carries on by itself." \
  "Cold builds work on Ubuntu 26.04 hosts." \
  "No rebuild is needed: this release changes nothing inside the guest, and builds that already had their media cached were never affected." \
  "Images and boxes contain Apple's operating system. Never publish them." \
  "Go 1.27 for Mac OS X 10.9 Mavericks." "The cross toolchain needs macOS 13 or later, as upstream Go 1.27 does." \
  "A new shared CA location." "On darwin, SSL_CERT_FILE and SSL_CERT_DIR add CA files to the keychain-union trust store." \
  "Go's verifier does not fetch missing intermediate certificates; a server that omits them fails verification, as with Go on Linux." \
  "A program that brings its own static C++ runtime now links." "Pure-Go programs now run on Mavericks."; do
  printf '%s\n' "$good" | ok "survey good: $good"
done

echo PASS
