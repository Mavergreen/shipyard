#!/bin/sh
# platform: host-agnostic
#   usage: deviations.sh <repo>
#          Prints the deviations declared in <repo>/INGREDIENTS.md under "## Conformance deviations",
#          one per line as "<check> <glob or *> <reason>". The grammar is "- <check>[:<glob>]:
#          <reason>"; unlinked alone may add a KEY, "- unlinked:<glob>[:<KEY>]: <reason>", and must
#          name a scope. A deviation IS a product fact, so it lives with the other product facts, and
#          ONE parser keeps every checker reading it alike. Exit 1 if an entry has no reason: an
#          exception without one is indistinguishable from drift.
set -eu
root="${1:-.}"
[ -f "$root/INGREDIENTS.md" ] || exit 0
rc=0
sed -n '/^## Conformance deviations/,/^## /p' "$root/INGREDIENTS.md" | awk '
  /^- *[a-z][a-z0-9_-]*(:[^ :]*)? *:/ {
    line = $0; sub(/^- */, "", line)
    i = index(line, ":"); check = substr(line, 1, i - 1); rest = substr(line, i + 1)
    glob = "*"; scoped = 0
    if (rest !~ /^ /) {
      scoped = 1
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
      # spec: tests/deviations-test.sh -- unlinked: scopes a pin, which is a file plus its KEY; on
      #       any other kind a :KEY could never match a subject, so it would excuse nothing, silently.
      if (match(rest, /^[A-Z*][A-Z0-9_*]*:/)) {
        if (check != "unlinked") {
          print "deviations.sh: \"" check ":" glob ":" substr(rest, 1, RLENGTH - 1) "\" -- only unlinked: takes a :KEY scope" > "/dev/stderr"
          bad = 1; next
        }
        glob = glob ":" substr(rest, 1, RLENGTH - 1); rest = substr(rest, RLENGTH + 1)
      }
    }
    # spec: tests/deviations-test.sh -- an unscoped or "*" unlinked: would switch the release-notes
    #       link rule off for the whole repo.
    if (check == "unlinked" && glob == "*") {
      print "deviations.sh: \"unlinked\" must name the pins it excuses: \"- unlinked:<pin path>[:KEY]: <reason>\"" > "/dev/stderr"
      bad = 1; next
    }
    # spec: tests/deviations-test.sh -- a self-upstream-exclude: of only "*" and "/" would make no
    #       change own code, so every release would keep the last date.
    if (check == "self-upstream-exclude" && glob ~ /^[*\/]+$/) {
      print "deviations.sh: \"self-upstream-exclude\" must name what it excludes: \"- self-upstream-exclude:<glob>: <reason>\"" > "/dev/stderr"
      bad = 1; next
    }
    # spec: SKILL.md "Acceptance on real 10.9" -- on-target:<part> names one gap in what the 10.9 guest
    #       covers; a glob there would read as the bare on-target, which exempts the repo from
    #       check 29.
    if (check == "on-target" && scoped && glob ~ /[*?]|\[/) {
      print "deviations.sh: \"on-target:" glob "\" -- on-target:<part> is one word naming what stays untested in the guest, never a glob; a bare \"- on-target: <reason>\" is the one that stands in for the job" > "/dev/stderr"
      bad = 1; next
    }
    # spec: SKILL.md "Family conventions" checks 35 and 36 -- a wildcard would excuse every path or job
    #       at once, which defeats a check meant to be burned down one entry at a time. macos-runner
    #       is keyed "<workflow file>:<job>", so a job id alone cannot excuse the same id elsewhere.
    if (check == "macos-runner" && scoped && match(rest, /^[A-Za-z0-9_-]+:/)) {
      glob = glob ":" substr(rest, 1, RLENGTH - 1); rest = substr(rest, RLENGTH + 1)
    }
    if (check == "macos-runner" && (index(glob, "*") || index(glob, "?") || index(glob, "[") || split(glob, jobparts, ":") != 2 || jobparts[1] == "" || jobparts[2] == "")) {
      print "deviations.sh: \"macos-runner\" names one job: \"- macos-runner:<workflow file>:<job>: <reason, exit>\", never a wildcard" > "/dev/stderr"
      bad = 1; next
    }
    # spec: SKILL.md "Family conventions" check 37 -- arm64 names install paths; a bare form or an
    #       all-wildcard glob would declare the whole pkg universal.
    if (check == "arm64" && (!scoped || glob ~ /^[*?\/]+$/)) {
      print "deviations.sh: \"arm64\" names the install paths it covers: \"- arm64:<install-path glob>: <reason>\", never a bare form or a glob of nothing but wildcards" > "/dev/stderr"
      bad = 1; next
    }
    if (check == "cxxabi" && (!scoped || glob ~ /^[*?\/]+$/)) {
      print "deviations.sh: \"cxxabi\" names the install paths it covers: \"- cxxabi:<install-path glob>: <reason>; exit: <how it goes away>\", never a bare form or a glob of nothing but wildcards" > "/dev/stderr"
      bad = 1; next
    }
    if (check == "packager" && (!scoped || glob ~ /[*?[]/)) {
      print "deviations.sh: \"packager\" names one path: \"- packager:<path>: <reason, exit>\", never a wildcard" > "/dev/stderr"
      bad = 1; next
    }
    sub(/^ */, "", rest)
    if (rest == "") { print "deviations.sh: \"" check "\" declares no reason" > "/dev/stderr"; bad = 1; next }
    print check " " glob " " rest
  }
  END { exit bad }' || rc=$?
sed -n 's/^.*No upstream release notes: *\([^ ].*\)$/upstream-notes * \1/p' "$root/INGREDIENTS.md" | head -1
exit "$rc"
