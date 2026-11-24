link-requires: every family dylib a shipped image loads is listed by the release manifest of a dependency declared as a library, and every library requirement is loaded.

## Why
A product that loads another product's dylib needs that product installed, and only a declared requirement
makes the Engine install it. artifact-facts.sh reads each linked slice's loads, the repo's
.mavergreen/products/<short>/requires/<dep>/kind, and, for each library dependency, the RELEASE-MANIFEST.txt
of its pinned release (dep-manifest.sh, cached). A load by @rpath or under /opt/mavergreen/ that is not one
of this release's own install names must be a dylib row of the manifest of a library dependency its own
product declares. A library
requirement that nothing loads fails too: it installs a dependency for no reason, or names the wrong one.
An unreadable manifest fails closed.

## Incident
None recorded. Products have linked family dylibs no requirement named, which worked only where the
maintainer's own boxes happened to have the dependency installed.

## Limits
A load is judged against the requirements of the product whose opt/mavergreen/<short>/ holds the image (a
standalone archive's SHORT-VERSION/ read as that tree), and each product's requirement must be loaded by
that product. An image outside every product's tree, such as an app under Applications/Mavergreen/, is
judged against every product's requirements, pooled. A dependency pinned to a -mavericks.N release, which predates manifests, resolves its dylibs by its
install prefix under /usr/local/mavergreen/ (the Q2 tolerance, until every pin is a -mavergreen.N release).
An @rpath load is a family load only when one of the image's LC_RPATHs, resolved from where it installs,
reaches another product's tree under opt/mavergreen/ or usr/local/mavergreen/; an @rpath load of a system
or SDK library, such as libswiftCore through /usr/lib/swift, is not judged. When no manifest lists it, it is
credited to the q2 library dependencies only if every family tree those LC_RPATHs reach is one of theirs.
Which tree actually holds the dylib is not read.

## Deviating
Write .mavergreen/deviations/link-requires/<label>/ with a scope (a <path glob> for a load, or the
dependency's name for a requirement), a reason and a revisit.

New in the flag day (P6, link facts)
