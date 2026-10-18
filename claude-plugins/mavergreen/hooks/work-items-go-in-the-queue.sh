#!/bin/sh
# platform: host-agnostic
#   A PreToolUse hook (hooks.json). Reads the tool call's JSON on stdin. When an agent is about to open
#   a GitHub issue or pull request (gh issue/pr create, or an MCP create_issue/create_pull_request) on
#   a Mavergreen repo, by its checkout or by name, prints a decision to ask the maintainer first, and
#   says where work items go. Prints nothing otherwise, so the call proceeds as it would have.
# spec: SKILL.md "Where superpowers working files go" -- work items go in QUEUE.md under .superpowers/; an
#       issue or pull request needs the maintainer's express permission each time.
set -u
input="$(cat)"
case "$input" in *gh*|*mcp__*) ;; *) exit 0 ;; esac

opens=no
if printf '%s' "$input" | grep -Eq '"tool_name" *: *"mcp__[^"]*(create_issue|create_pull_request)'; then
  opens=yes
elif printf '%s' "$input" | grep -Eq '"tool_name" *: *"Bash"' \
     && printf '%s' "$input" | grep -Eq '(^|[^A-Za-z0-9_.-])gh +(issue|pr) +create([^A-Za-z0-9_-]|$)'; then
  opens=yes
fi
[ "$opens" = yes ] || exit 0

ours=no
if printf '%s' "$input" | grep -q 'Mavergreen'; then
  ours=yes
else
  cwd="$(printf '%s' "$input" | sed -n 's/.*"cwd" *: *"\([^"]*\)".*/\1/p')"
  if [ -n "$cwd" ] && top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"; then
    case "${top##*/}" in mavergreen-*) ours=yes ;; esac
    git -C "$top" remote -v 2>/dev/null | grep -Eq 'github\.com[:/]Mavergreen/' && ours=yes
  fi
fi
[ "$ours" = yes ] || exit 0

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Mavergreen: work items go in the repo's QUEUE.md under .superpowers/, not GitHub issues, and an issue or pull request needs the maintainer's express permission for this one. Approve only if you asked for it."}}
JSON
