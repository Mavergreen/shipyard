#!/bin/sh
# platform: host-agnostic
#   usage: ingredients-table.sh
#          Prints .mavergreen/ingredients/ as a Markdown table: name, roles, description, value (the
#          VERSION, the PIN's ref, or the COMMIT) and how it is tracked, with the reason when it is
#          not. Reads $MAVERGREEN_ROOT, else the git checkout around the working directory. Prints
#          nothing when there are no ingredients.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"

cell() { awk 'NF { gsub(/\|/, "\\|"); gsub(/^[ \t]+|[ \t]+$/, ""); printf "%s%s", s, $0; s = sep }' sep="$1"; }

names="$(mg_list ingredients)"
[ -n "$names" ] || exit 0
printf '| Ingredient | Role | Description | Value | Tracking |\n'
printf '| --- | --- | --- | --- | --- |\n'
for n in $names; do
  d="ingredients/$n"
  [ -d "$(mg_dir)/$d" ] || continue
  role="$(mg_lines "$d/role" 2>/dev/null | cell ', ')" || role=
  desc="$(mg_value "$d/description" 2>/dev/null | cell ' ')" || desc=
  value=
  if v="$(mg_value "$d/VERSION")"; then value="$v"
  elif v="$(mg_pin_ref "$d")"; then value="$v"
  elif v="$(mg_value "$d/COMMIT")"; then value="$(printf '%.12s' "$v")"
  fi
  value="$(printf '%s\n' "$value" | cell ' ')"
  tracking=
  for k in $(mg_list "$d"); do
    w="$(mg_renovate "$d/$k" 2>/dev/null)" || continue
    ds="$(printf '%s\n' "$w" | sed -n 's/^datasource=//p')"
    dep="$(printf '%s\n' "$w" | sed -n 's/^depName=//p')"
    tracking="tracked ($ds $dep)"
    break
  done
  if [ -z "$tracking" ]; then
    if f="$(mg_value "$d/from")"; then
      if [ "$f" = self ]; then tracking='tracked with the upstream'; else tracking="tracked with $f"; fi
    elif mg_has "$d/tracked-by"; then
      tracking="tracked by $(mg_lines "$d/tracked-by" | cell ' ')"
    elif mg_has "$d/untracked"; then
      tracking="untracked: $(mg_lines "$d/untracked" | cell ' ')"
    else
      tracking=untracked
    fi
  else
    tracking="$(printf '%s\n' "$tracking" | cell ' ')"
  fi
  printf '| %s | %s | %s | %s | %s |\n' "$n" "$role" "$desc" "$value" "$tracking"
done
