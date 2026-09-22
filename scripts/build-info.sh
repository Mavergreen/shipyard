#!/bin/sh
#   usage: build-info.sh <outfile> key=value [key=value ...]
#          Keys are free-form; conformance compares any key that appears in more than one variant,
#          except the ones that are SUPPOSED to differ (variant, arch, prefix, pkg, identifier).
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact
#       conformance", "Record what a variant was built FROM" -- the artifacts cannot answer this on
#       their own (golang's native .pkg carries the CA bundle and the legacy-support shim, its cross
#       .pkg legitimately does not); "both variants used the same shim" is a claim about inputs,
#       knowable only at build time, so this writes them down rather than reconstructing them later.
set -eu
out="${1:?build-info: output file required}"; shift
[ "$#" -gt 0 ] || { echo "build-info: at least one key=value required" >&2; exit 2; }
: > "$out"
for kv in "$@"; do
  case "$kv" in
    *=*) : ;;
    *) echo "build-info: '$kv' is not key=value" >&2; exit 2 ;;
  esac
  k="${kv%%=*}"; v="${kv#*=}"
  # spec: scripts/artifact-facts.sh -- a value with whitespace would break the whitespace-delimited
  #       fact stream downstream.
  printf '%s=%s\n' "$k" "$(printf '%s' "$v" | tr -s '[:space:]' '_')"
done | sort >> "$out"
