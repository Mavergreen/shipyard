sign-call-shape: every call to sign_and_appcast.sh passes --product and --feed-dir and redirects nothing.

## Why
sign_and_appcast.sh writes the feed itself, as <feed-dir>/<product>.xml, and every release carries one feed
per updater its pkgs install. The retired shape, sign_and_appcast.sh --pkg ... > dist/appcast.xml, wrote
a single appcast.xml that nothing polls any more; this fails it on the pull request instead of at signing
time. The call is read as one command across lines that end in a backslash, so a flag on a continuation
line counts. A redirection (> other than 2>) fails, because output on stdout is not the feed.

## Incident
None recorded.

## Limits
It reads the call as text. It cannot tell that the product name is the registered one (the conformance
feed and updater ids hold the artifacts to the registry), and it does not follow a call hidden behind a
variable or a wrapper script.

## Deviating
No deviation is read for this id. Write the call as one command: sh "$SHIPYARD_SCRIPTS/sign_and_appcast.sh"
--product <short> --feed-dir dist ..., continued with a trailing backslash, with no > after it.

Formerly gate check 12b
