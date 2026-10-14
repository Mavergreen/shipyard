#!/bin/sh
# platform: host-agnostic
set -eu
. "$(cd "$(dirname "$0")" && pwd)/lib/py.sh"
chk_ran python3
chk_python3 >/dev/null
