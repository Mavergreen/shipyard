#!/bin/sh
. "$SHIPYARD_SCRIPTS/mavergreen_fetch.sh"
curl -fsSL -o "$2" "$1"
