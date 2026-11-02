#!/bin/sh
# platform: host-agnostic
: "${SHIPYARD_CHECK_DIR:=$(cd "$(dirname "$0")" && pwd)}"
: "${SHIPYARD_SCRIPTS:=$SHIPYARD_CHECK_DIR}"
. "$SHIPYARD_CHECK_DIR/check-lib.sh"

_py_ok() {
  "$1" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1
}

_py_install_hint() {
  case "$(uname -s)" in
    Darwin) echo "/opt/mavergreen/bin/mavergreen install python315" ;;
    *) echo "install python3 >= 3.9" ;;
  esac
}

chk_python3() {
  if [ -n "${SHIPYARD_PYTHON3:-}" ]; then
    set -- "$SHIPYARD_PYTHON3"
    _py_tried="\$SHIPYARD_PYTHON3, which names the interpreter to use"
  else
    set -- "${SHIPYARD_OPT_PREFIX:-/opt/mavergreen}/bin/python3" \
      "${SHIPYARD_LOCAL_PREFIX:-/usr/local/mavergreen}/bin/python3-315" python3-315 python3
    _py_tried="/opt/mavergreen/bin/python3, /usr/local/mavergreen/bin/python3-315, and python3-315 and python3 on PATH"
  fi
  for _py_c in "$@"; do
    _py_p="$(command -v "$_py_c" 2>/dev/null)" || continue
    if _py_ok "$_py_p"; then
      printf '%s\n' "$_py_p"
      return 0
    fi
  done
  chk_fail python3 "no python3 >= 3.9 was found" \
    "the checks that read YAML run in python3, tried $_py_tried" \
    "$(_py_install_hint)"
  return 1
}

chk_py() {
  _py_script="$1"; shift
  _py_bin="$(chk_python3)" || return 1
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$SHIPYARD_SCRIPTS/vendor:$SHIPYARD_SCRIPTS/lib${PYTHONPATH:+:$PYTHONPATH}" "$_py_bin" "$_py_script" "$@"
}
