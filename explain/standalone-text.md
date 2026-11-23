standalone-text: text in a standalone archive names a Mavergreen prefix only where a deviation says why, and only while it does.

## Why
check-standalone-archive.sh refuses a script or text file in a standalone archive that names a
Mavergreen prefix, since the archive is meant to work wherever it is unpacked. Some text must name one
(a toolchain's sources holding the CA paths its programs read). A standalone-text deviation turns the
text findings of the archive paths its scope matches into warnings. One that excuses nothing in any
standalone archive of the release fails the standalone check, so it cannot outlive its reason.

## Incident
None recorded.

## Limits
It excuses text findings only, never a Mach-O load or a link. The scope is an archive-path glob,
relative to SHORT-VERSION/, matched in every archive of the release.

## Deviating
Write .mavergreen/deviations/standalone-text/<label>/ with a scope (<archive-path glob>), a reason and a
revisit. deviations.sh refuses a glob of only *, ? and /.

New in the flag day (from main's standalone-text entries)
