#!/bin/sh
# platform: host-agnostic
set -eu
. "$(cd "$(dirname "$0")" && pwd)/lib/py.sh"
chk_python3 >/dev/null
