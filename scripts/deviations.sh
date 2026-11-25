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
    # spec: SKILL.md "Release notes" -- pin:<glob> declares ingredient pins the default list misses;
    #       unscoped, or of only "*" and "/", it would make every change a pin.
    if (check == "pin" && (!scoped || glob ~ /^[*\/]+$/)) {
      print "deviations.sh: \"pin\" names the pin files it declares: \"- pin:<glob>: <reason>\", never a bare form or a glob of nothing but wildcards" > "/dev/stderr"
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
    # spec: SKILL.md "Family conventions" check 37 -- arm64 and arm64-pure-go name install paths; a
    #       bare form or an all-wildcard glob would declare the whole pkg universal.
    if ((check == "arm64" || check == "arm64-pure-go") && (!scoped || glob ~ /^[*?\/]+$/)) {
      print "deviations.sh: \"" check "\" names the install paths it covers: \"- " check ":<install-path glob>: <reason>\", never a bare form or a glob of nothing but wildcards" > "/dev/stderr"
      bad = 1; next
    }
    # spec: SKILL.md "Artifact conformance" -- go-trimpath names the Go binaries it excuses; a bare form
    #       or an all-wildcard glob would let every Go binary differ by host.
    if (check == "go-trimpath" && (!scoped || glob ~ /^[*?\/]+$/)) {
      print "deviations.sh: \"go-trimpath\" names the install paths it covers: \"- go-trimpath:<install-path glob>: <reason>; exit: <how it goes away>\", never a bare form or a glob of nothing but wildcards" > "/dev/stderr"
      bad = 1; next
    }
    if (check == "cxxabi" && (!scoped || glob ~ /^[*?\/]+$/)) {
      print "deviations.sh: \"cxxabi\" names the install paths it covers: \"- cxxabi:<install-path glob>: <reason>; exit: <how it goes away>\", never a bare form or a glob of nothing but wildcards" > "/dev/stderr"
      bad = 1; next
    }
    # spec: SKILL.md "Conformance deviations" (build-equivalence) -- build-equivalence names the payload paths it excuses; a bare form
    #       or an all-wildcard glob would excuse every difference between two builds.
    if ((check == "build-equivalence" || check == "build-equivalence-interface") && (!scoped || glob ~ /^[*?\/]+$/)) {
      print "deviations.sh: \"" check "\" names the payload paths it excuses: \"- " check ":<payload-path glob>: <reason; revisit: ...>\", never a bare form or a glob of nothing but wildcards" > "/dev/stderr"
      bad = 1; next
    }
    # spec: SKILL.md "Standalone archive" -- standalone-text names the archive paths whose text it
    #       excuses; a bare form or an all-wildcard glob would excuse every script in the archive.
    if (check == "standalone-text" && (!scoped || glob ~ /^[*?\/]+$/)) {
      print "deviations.sh: \"standalone-text\" names the archive paths whose text it excuses: \"- standalone-text:<archive-path glob>: <reason>\", never a bare form or a glob of nothing but wildcards" > "/dev/stderr"
      bad = 1; next
    }
    # spec: SKILL.md "Standalone archive" -- standalone-install-name names the dylibs whose absolute
    #       install name it lets stand; a bare form or an all-wildcard glob would excuse every dylib.
    if (check == "standalone-install-name" && (!scoped || glob ~ /^[*?\/]+$/)) {
      print "deviations.sh: \"standalone-install-name\" names the archive paths whose install name it excuses: \"- standalone-install-name:<archive-path glob>: <reason>\", never a bare form or a glob of nothing but wildcards" > "/dev/stderr"
      bad = 1; next
    }
    # spec: SKILL.md "Family conventions" check 23 -- the gate verifies staged-by against
    #       components/<library>/version, so the scope is one repo name, never a path or a glob.
    if (check == "staged-by" && (!scoped || glob !~ /^[A-Za-z0-9._-]+$/)) {
      print "deviations.sh: \"staged-by\" names the pinned library that stages the pkg: \"- staged-by:<library>: <reason>\", with components/<library>/version tracked" > "/dev/stderr"
      bad = 1; next
    }
    if (check == "packager" && (!scoped || glob ~ /[*?[]/)) {
      print "deviations.sh: \"packager\" names one path: \"- packager:<path>: <reason, exit>\", never a wildcard" > "/dev/stderr"
      bad = 1; next
    }
    sub(/^ */, "", rest)
    # spec: scripts/assert_binary_compatible.sh header -- objc-api:<artifact glob> excuses reviewed findings of one
    #       artifact scope, each through one evidence record, evidence=<file>#<record id>, then the review reason.
    #       Unscoped or wildcards alone it would excuse every artifact; without its record, nothing names the finding.
    if (check == "objc-api") {
      if (!scoped || glob ~ /^[*?\/]+$/) {
        print "deviations.sh: \"objc-api\" must name the artifact it excuses: \"- objc-api:<artifact path>: evidence=<file>#<record id> <review reason>\"" > "/dev/stderr"
        bad = 1; next
      }
      if (rest !~ /^evidence=[^ #]+#[A-Za-z0-9._-]+ +[^ ]/) {
        print "deviations.sh: \"objc-api:" glob "\" needs evidence=<file>#<record id>, one record, and then the review reason" > "/dev/stderr"
        bad = 1; next
      }
    }
    if (rest == "") { print "deviations.sh: \"" check "\" declares no reason" > "/dev/stderr"; bad = 1; next }
    print check " " glob " " rest
  }
  END { exit bad }'
