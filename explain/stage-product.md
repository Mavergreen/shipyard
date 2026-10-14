stage-product: a repo that builds a .pkg calls stage_product.sh.

## Why
Conformance enforces the install layout, and stage_product.sh produces it: the manifest, and the
unlink-remove-link install scripts that make an upgrade replace the tree while keeping the group's
selection. A hand-rolled pkg fails the manifest conformance rule only at package time; this finds it on
the pull request. The call must be at command position on a non-comment line of a tracked, non-test *.sh,
*.yml, *.yaml, *.cmake or CMakeLists.txt, spelled sh or /bin/sh (with option flags) and a word ending
stage_product.sh, or a word ending /stage_product.sh. A mention is not a call: echo "sh stage_product.sh"
does not count, and neither does an assignment.

## Incident
None recorded.

## Limits
Known false negatives: a bare stage_product.sh found on PATH; bash or "." instead of sh; a call behind a
prefix command (sudo, env, time, command) or opening a brace group or a subshell; a path containing a space
or "=" ("$(dirname "$0")"/stage_product.sh); and a call followed directly by ";" or ")" (then sh
"$S/stage_product.sh"; fi). Give the call its own line, or a space before the separator.

## Deviating
Write "- stage-product: <reason>", for the whole repo. A good reason says why the product cannot be staged
by the helper, and the exit.

Formerly gate check 23
