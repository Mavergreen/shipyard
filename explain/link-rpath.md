link-rpath: a family dylib is loaded by @rpath from outside its own product tree, and libc++ through an LC_RPATH that finds the installed libcxx22 first.

## Why
dyld on 10.9 dedupes an @rpath load by its install name: the first copy loaded serves the whole process. A
standalone archive bundles libcxx22's libc++ beside the image, and the pkg relies on the installed one;
with @rpath and the installed tree's LC_RPATH first, the same bytes use the installed copy when there is one,
and one libc++ serves every image in the process. An image that loads a family dylib by its absolute path
cannot use a bundled copy, and mixed absolute and @rpath loads of one dylib give a process two copies.
artifact-facts.sh reads each linked slice's loads and LC_RPATHs in order. A load of a path under
/opt/mavergreen/<short>/ or /usr/local/mavergreen/<short>/ fails unless the image is installed in that same
tree, so libcxx22's absolute libc++abi.1.dylib passes only from inside opt/mavergreen/libcxx22/. An image
that loads @rpath/libc++.1.dylib fails unless its first LC_RPATH, with @loader_path or @executable_path
resolved from where the pkg installs the image, is opt/mavergreen/libcxx22/lib. A standalone archive's
SHORT-VERSION/ is read as opt/mavergreen/SHORT/, where its pkg installs it.

## Incident
None recorded. On 2026-11-23 libcxx22's libc++ moved to an @rpath install name, so the bundled and the
installed copy have one identity; a consumer still linked against the old absolute path keeps a second one.

## Limits
Only libc++.1.dylib's rpath order is judged; an @rpath load of another dylib may find it anywhere. A bundled
copy listed after the installed tree is not yet read for its release. @executable_path is resolved from the
image itself, which is right for an executable and only a guess for a dylib.

## Deviating
Write .mavergreen/deviations/link-rpath/<label>/ with a scope (<path glob>, as the payload or archive
installs the image), a reason and a revisit. A consumer of a release pinned at /usr/local/mavergreen/
declares q2-pinned-releases until every pin is a -mavergreen.N release.

New in the flag day (P6, link facts)
