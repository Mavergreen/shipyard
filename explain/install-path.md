install-path: a pkg installs only into its product's tree and the family's places.

## Why
Every product owns exactly one directory, /usr/local/mavergreen/<product>/. What installed a file is
readable from its path; an upgrade replaces the directory wholesale, so a file the newer payload stopped
carrying is gone rather than left behind; and uninstall is complete. Allowed besides the tree:
Applications/, Library/Application Support/Mavergreen/, a dev.mavergreen.* launchd plist, and
usr/local/mavergreen/.base/ in an archive that carries dev.mavergreen.base. Anything else collides with
someone else's files. Some products genuinely must go elsewhere, only where the OS dictates (a kext loads
only from /Library/Extensions, a prefpane only from /Library/PreferencePanes), and those say so.

## Incident
Undated in the conventions skill: swift-runtime kept /usr/lib/swift under a deviation until
6.4.0-mavericks.2, when programs began finding it through an rpath into its tree, and the exception went.

## Limits
Paths are relative to "/", after each component's install-location. It reports at most 20 offenders and a
count. It checks where files land, not their contents. A file the OS dictates is still in the manifest's
outside list, so uninstall removes it; manifest holds that half.

## Deviating
Write .mavergreen/deviations/install-path/<label>/ with a scope (<installed path glob>), a reason and a revisit; for example a scope of Library/Extensions/*
and the reason "10.9 loads third-party kexts only from here". The glob matches the path in the payload; "*" spans "/" and
spaces. A good reason names the OS rule that forces the place.

Formerly the conformance rule install-path
