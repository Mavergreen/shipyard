enclosure: an appcast's enclosure names a published asset.

## Why
An update that points at a file the release does not carry is a 404 for every installed client at the
moment they try to update. The check compares each appcast's enclosure to the assets of this release.

## Incident
None recorded.

## Limits
It compares names with the dist directory's assets, not with what GitHub actually serves after upload;
publish-release.yml regenerates SHA256SUMS over what it attaches.

## Deviating
Write "- enclosure:<appcast file glob>: <reason>". A good reason says where the enclosure lives instead, and
the exit.

Formerly the conformance rule enclosure
