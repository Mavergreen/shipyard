#!/bin/sh
[ -n "${3:-}" ] || { echo "mavergreen-base: no target volume; installing nothing" >&2; exit 1; }
LC_ALL=C; export LC_ALL
. "$SELF/lib/root-chain.sh"
R="${3%/}"
mavergreen_root_dir "$R/opt" && mavergreen_chain_ok "$3/opt" "$3" \
  && mavergreen_root_dir "$R/opt/mavergreen" && mavergreen_chain_ok "$3/opt/mavergreen" "$3" || exit 1
A="$R/Applications/Mavergreen"
if [ -e "$A" ] || [ -L "$A" ]; then
  mavergreen_dir_ok "$A" || {
    echo "mavergreen-base: refusing $(mavergreen_chain_q "$A"), which root installs apps into; remove it, or apply the fix above" >&2
    exit 1
  }
fi
exit 0
