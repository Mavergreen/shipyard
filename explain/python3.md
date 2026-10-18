python3: a python3 of version 3.9 or newer is available for the checks that need one.

## Why
Cannot-verify is a failure, never a pass. The checks that parse workflows and Renovate JSON (workflow-yaml,
renovate-json-valid, no-tags-trigger, checkout-drops-credentials, the package-manager ids and others) run
in python3. The check looks for $SHIPYARD_PYTHON3 if set, else /opt/mavergreen/bin/python3,
/usr/local/mavergreen/bin/python3-315 (a 10.9 non-login shell's PATH lacks that directory), python3-315
and python3 on PATH, and takes the first that is 3.9 or newer. When none is, it fails and names what to
install (on macOS, /opt/mavergreen/bin/mavergreen install python315) instead of letting those checks skip.
The install action also makes PyYAML importable for the job's python3, so a repo neither provisions it nor
skips the gate for want of it; shipyard vendors a copy for its own checks.

## Incident
Undated in the conventions skill: drydock and pi each provisioned their own PyYAML while fd and rg skipped
the gate, and a skipped gate checks nothing. That is why the install action provisions it for every job.

## Limits
Stock 10.9 has Python 2 only, so on a bare 10.9 box these checks need the family's python315. The design spec
(K4) wants the checks in POSIX sh and awk with no python3, using one awk reader of the workflow YAML subset;
this id goes when that lands.

## Deviating
No deviation is read for this id, and the old "- python3:" line in INGREDIENTS.md is read by nothing: delete
it. Install python3 3.9 or newer, or set SHIPYARD_PYTHON3 to the interpreter to use.

New in the flag day (P1; the gate used to skip these checks without it)
