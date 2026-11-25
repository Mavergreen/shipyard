#!/bin/sh
# platform: host-agnostic
#   usage: versioning.sh [--root DIR] [--product SHORT]
#          Reads INGREDIENTS.md's "## Versioning" section: "- <scheme>" (one product, short "*") or
#          "- <short>: <scheme>" per product; port and counter may add an upstream file:
#          "- [<short>: ]port <file>". Schemes: port, self-upstream-date, semver, date-semver, counter.
#          No --product: "<short><TAB><scheme><TAB><upstream-file>" per entry, in declaration order.
#          --product: "<scheme><TAB><upstream-file>" for SHORT's entry, else the "*" entry.
#          Exit 0 with no output when there is no INGREDIENTS.md or no section (without --product);
#          1 for a malformed section or an undeclared product; 2 for a usage error.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Versioning"
set -eu
root=.
product=
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "versioning.sh: --root needs a directory" >&2; exit 2; }; root="$2"; shift 2 ;;
    --product) [ $# -ge 2 ] || { echo "versioning.sh: --product needs a short name" >&2; exit 2; }; product="$2"; shift 2 ;;
    *) echo "usage: versioning.sh [--root DIR] [--product SHORT]" >&2; exit 2 ;;
  esac
done

entries=
if [ -f "$root/INGREDIENTS.md" ]; then
  entries="$(sed -n '/^## Versioning/,/^## /p' "$root/INGREDIENTS.md" | awk '
    function fail(m) { print "versioning: " m > "/dev/stderr"; bad = 1 }
    /^- / {
      line = $0; sub(/^- */, "", line); sub(/ *$/, "", line)
      short = "*"
      i = index(line, ":")
      if (i > 0) {
        short = substr(line, 1, i - 1); line = substr(line, i + 1); sub(/^ */, "", line)
        gsub(/ /, "", short)
        if (short !~ /^[a-z0-9][a-z0-9-]*$/) { fail("entry \"" short "\" is not a product short name (lowercase, digits, -)"); next }
      }
      n = split(line, f, / +/)
      scheme = f[1]; file = (n >= 2) ? f[2] : ""
      if (scheme !~ /^(port|self-upstream-date|semver|date-semver|counter)$/) {
        fail("entry \"" short "\": \"" scheme "\" is not a scheme -- use port, self-upstream-date, semver, date-semver or counter"); next
      }
      if (n > 2 || (n == 2 && scheme != "port" && scheme != "counter")) {
        fail("entry \"" short "\": only port and counter take an upstream file, and only one"); next
      }
      if (short in seen) { fail("entry \"" short "\" is declared twice -- one product, one scheme"); next }
      seen[short] = 1
      order[++m] = short
      if (short == "*") star = 1
      sch[short] = scheme; fl[short] = file
    }
    END {
      if (star && m > 1) fail("a bare \"- <scheme>\" entry is the single form and cannot sit beside other entries")
      if (bad) exit 1
      for (k = 1; k <= m; k++) printf "%s\t%s\t%s\n", order[k], sch[order[k]], fl[order[k]]
    }
  ')" || exit 1
fi

if [ -z "$product" ]; then
  [ -z "$entries" ] || printf '%s\n' "$entries"
  exit 0
fi

TAB="$(printf '\t')"
hit="$(printf '%s\n' "$entries" | awk -F"$TAB" -v p="$product" '
  $1 == p { print $2 "\t" $3; found = 1; exit }
  $1 == "*" { star = $2 "\t" $3 }
  END { if (!found && star != "") print star }
')"
if [ -z "$hit" ]; then
  echo "versioning: INGREDIENTS.md declares no versioning scheme for $product — add \"## Versioning\" with \"- <scheme>\" or \"- $product: <scheme>\"" >&2
  exit 1
fi
printf '%s\n' "$hit"
