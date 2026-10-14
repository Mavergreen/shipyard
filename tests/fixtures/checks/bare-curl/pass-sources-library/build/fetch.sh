#!/bin/sh
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"
curl -fsSL -o "$2" "$1"
