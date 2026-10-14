#!/bin/sh
set -eu
wget -q -O - "$1" | tar xf -
if ! curl -fsS "$1" > "$2"; then exit 1; fi
