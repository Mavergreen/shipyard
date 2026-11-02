#!/bin/sh
# platform: host-agnostic
#   usage: ingredient-pins.sh
#          Prints the names of this repo's ingredients, the directories under .mavergreen/ingredients/,
#          one per line in C order. A repo with none prints nothing and exits 0.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
mg_list ingredients
