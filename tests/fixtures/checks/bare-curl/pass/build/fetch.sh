#!/bin/sh
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"
mav_curl "$1" "$2"
echo "curl is wrapped by mav_curl"
