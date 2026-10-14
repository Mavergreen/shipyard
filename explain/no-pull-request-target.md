no-pull-request-target: no workflow uses pull_request_target.

## Why
pull_request_target runs with the base repo's secrets on a fork pull request's code, so it would hand a fork
PR this repo's secrets; no family workflow needs it. Use pull_request, which gets no secrets from a fork.
Fork pull requests never touch SPARKLE_PRIVATE_KEY for the same reason: they resolve release=no.

## Incident
None recorded.

## Limits
It looks for the word on a non-comment line of each workflow, so a mention in a string also counts. It
reads workflow files only.

## Deviating
Write "- no-pull-request-target:<workflow path>: <reason>". A good reason says what the workflow does with the
fork's code and how secrets stay out of reach, and the exit.

New in the flag day (K6, hand-rolled in rust, longboat and rg)
