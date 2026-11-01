#!/bin/sh
# platform: host-agnostic -- measures only where /bin/sh is bash 3.2; elsewhere it fails, or is excused by a `host` deviation
#   usage: check-bash32-parse.sh
#          `/bin/sh -n` on every tracked shell script (a .sh file, or a shebang naming sh), and
#          `/bin/bash -n` on those whose shebang names bash. SHIPYARD_BASH32_SH and
#          SHIPYARD_BASH32_BASH name other bash 3.2 shells to run in place of them.
# spec: SKILL.md, the `bash32-parse` row of the checks table -- bash 3.2 is the /bin/sh of 10.9 and
#       macOS and rejects quoting that dash and newer bashes accept; the canary below is the construct
#       that broke longboat's release run 38569568867 (an apostrophe in ${VAR:?word} inside double
#       quotes).
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
: "${SHIPYARD_CHECK_DIR:=$SELF}"
. "$SELF/check-lib.sh"
. "$SELF/deviation-reason.sh"

sh_="${SHIPYARD_BASH32_SH:-/bin/sh}"
bash_="${SHIPYARD_BASH32_BASH:-/bin/bash}"
w="$(mktemp -d "${TMPDIR:-/tmp}/check-bash32-parse.XXXXXX")"; trap 'rm -rf "$w"' EXIT

shipyard_deviations . > /dev/null 2>&1 || :

cant_measure() {
  _host="$(uname -s | tr 'A-Z' 'a-z')"
  _why="$(shipyard_deviated host "$_host" || true)"
  if [ -n "$_why" ]; then
    chk_notrun bash32-parse "skipped by deviation (host:$_host): $_why"
    exit 0
  fi
  chk_fail bash32-parse "can't measure here: $1" \
    "only a bash 3.2 /bin/sh reports bash 3.2's parse errors, so a pass from any other shell would vouch for nothing" \
    "run this on a host whose /bin/sh is bash 3.2 (10.9 or macOS), or declare '- host:$_host: <reason>. Revisit when <exit>.' under ## Conformance deviations"
  exit 1
}

for _s in "$sh_" "$bash_"; do
  ver="$("$_s" -c 'printf %s "$BASH_VERSION"' 2>/dev/null)" || ver=""
  case "$ver" in
    3.2.*) ;;
    *) cant_measure "$_s is bash '${ver:-not bash}', not 3.2" ;;
  esac
  printf ': "${X:?it%ss}"\n' "'" > "$w/canary.sh"
  if "$_s" -n "$w/canary.sh" 2>/dev/null; then
    cant_measure "$_s (bash $ver) accepts the construct bash 3.2 refuses"
  fi
done
chk_ran bash32-parse

if ! chk_tracked_files > "$w/tracked" 2> "$w/err"; then
  chk_fail bash32-parse "the tracked-file list couldn't be read, so nothing was checked" \
    "an empty list would read as every script parsing" \
    "run it from the root of a git checkout, or set SHIPYARD_CHECK_FILES"
  exit 1
fi
grep -v '^tests/fixtures/checks/' "$w/tracked" | chk_shell_scripts > "$w/scripts" || :
n=0; excused=0
while IFS= read -r f; do
  if shipyard_deviated bash32-parse "$f" > /dev/null; then excused=$((excused + 1)); continue; fi
  n=$((n + 1))
  _s="$sh_"
  head -n 1 "$f" | grep -Eq '^#!(/bin/bash|/usr/bin/env bash)([[:space:]]|$)' && _s="$bash_"
  "$_s" -n "$f" 2> "$w/err" && continue
  chk_fail bash32-parse "$f does not parse under bash $ver: $(head -n 1 "$w/err")" \
    "bash 3.2 is what macOS runs this script with, and it refuses quoting and syntax that dash and newer bashes accept" \
    "rewrite the construct the parser names; a ' inside \${VAR:?word} in double quotes is the usual one"
done < "$w/scripts"
if [ "$((n + excused))" -eq 0 ]; then
  chk_notrun bash32-parse "this repo tracks no shell script"
  exit 0
fi
[ "$chk_status" -eq 0 ] && echo "bash32-parse: ok -- $n tracked shell scripts parse under bash $ver ($excused excused by deviation)"
exit "$chk_status"
