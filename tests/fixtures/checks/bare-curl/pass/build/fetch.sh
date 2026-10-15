#!/bin/sh
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"
shipyard_curl "$1" "$2"
echo "curl is wrapped by shipyard_curl"
