workflow-yaml: every workflow parses, with duplicate keys rejected.

## Why
A second with: on one step is legal YAML where the last key wins, so ordinary parsers accept it, and GitHub
refuses to run the workflow. No other gate sees it, because CI never starts. The check reads every
.github/workflows/*.yml with a parser that rejects duplicate keys, and names the place that does not parse.
Checks that read workflows (no-tags-trigger, checkout-drops-credentials, the package-manager ids) refuse to
pass on a workflow they cannot read, and point here.

## Incident
None recorded.

## Limits
It checks that the file parses and has no repeated key. It does not check that GitHub accepts the schema
(a misspelled key, a bad expression) or that a composite action's action.yml is well formed. It needs a
python3 3.9 or newer (see the python3 id); PyYAML comes from the copy shipyard vendors.

## Deviating
No deviation is read for this id. Correct the file at the line the message names.

Formerly gate check 8
