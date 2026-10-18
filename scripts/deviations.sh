#!/bin/sh
# platform: host-agnostic
#   usage: deviations.sh <repo>
#          Prints the deviations declared in <repo>/INGREDIENTS.md under "## Conformance deviations",
#          one per line as "<check> <glob or *> <reason>". The grammar is "- <check>[:<glob>[:<KEY>]]:
#          <reason>"; a deviation IS a product fact, so it lives with the other product facts, and
#          ONE parser keeps every checker reading it alike. Exit 1 if an entry has no reason: an
#          exception without one is indistinguishable from drift.
set -eu
root="${1:-.}"
[ -f "$root/INGREDIENTS.md" ] || exit 0
sed -n '/^## Conformance deviations/,/^## /p' "$root/INGREDIENTS.md" | awk '
  /^- *[a-z][a-z0-9_-]*(:[^ :]*)? *:/ {
    line = $0; sub(/^- */, "", line)
    i = index(line, ":"); check = substr(line, 1, i - 1); rest = substr(line, i + 1)
    glob = "*"
    if (rest !~ /^ /) {
      j = index(rest, ":"); glob = substr(rest, 1, j - 1); rest = substr(rest, j + 1)
      # spec: tests/deviations-test.sh -- no second colon leaves an EMPTY glob ("- check:reason",
      #       the same declaration written without the space). It fails SAFE, which is what makes it
      #       worth rejecting: an exception is written, the file looks like it carries one, and no
      #       checker honours it -- while every reader that splits on whitespace takes the FIRST WORD
      #       of the reason as the scope.
      if (glob == "") {
        print "deviations.sh: \"" check "\" has an empty glob -- write \"- " check ": <reason>\" or \"- " check ":<glob>: <reason>\"" > "/dev/stderr"
        bad = 1; next
      }
      # spec: tests/deviations-test.sh -- unlinked: scopes a pin, which is a file plus its KEY.
      if (match(rest, /^[A-Z*][A-Z0-9_*]*:/)) {
        glob = glob ":" substr(rest, 1, RLENGTH - 1); rest = substr(rest, RLENGTH + 1)
      }
    }
    sub(/^ */, "", rest)
    if (rest == "") { print "deviations.sh: \"" check "\" declares no reason" > "/dev/stderr"; bad = 1; next }
    print check " " glob " " rest
  }
  END { exit bad }'
