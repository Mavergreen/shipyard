enclosure-url: an appcast's enclosure URL names this release.

## Why
An appcast whose enclosure points at another release's file would send installed clients to the wrong
version, or to a file that is later replaced. The URL must carry this release's own tag.

## Incident
Undated in the conventions skill: a dist with an empty RELEASE_NOTES.md once printed "conformance: ok"
while its appcast described other notes and pointed at another release's file.

## Limits
It reads the URL's path for the tag; it does not fetch it. A feed that only carries a stand-in has no
meaningful URL to compare.

## Deviating
Write "- enclosure-url:<appcast file glob>: <reason>". A good reason says why the URL is not this
release's, and the exit.

Formerly the conformance rule enclosure-url
