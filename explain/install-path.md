install-path: a pkg installs only into its product's tree and the family's places.

## Why
Every product owns exactly one directory, /opt/mavergreen/<product>/. What installed a file is
readable from its path; an upgrade replaces the directory wholesale, so a file the newer payload stopped
carrying is gone rather than left behind; and uninstall is complete. Allowed besides the tree: an app under
Applications/Mavergreen/, opt/mavergreen/.base/ in an archive that carries dev.mavergreen.base, a
dev.mavergreen.* launchd plist, and the places the OS dictates: Library/Extensions/*.kext,
System/Library/Extensions/*.kext, System/Library/Filesystems/*.fs, Library/PreferencePanes/*.prefPane,
Library/Application Support/Apple/BezelServices/*.plugin and Library/Application Support/SIMBL/Plugins/*.bundle.
A bare /Applications is no longer the family's. Nothing installs under usr/local/: the family left it (vision
principle 6), and no deviation excuses it. Anything else collides with someone else's files.

## Incident
Undated in the conventions skill: swift-runtime kept /usr/lib/swift under a deviation until
6.4.0-mavericks.2, when programs began finding it through an rpath into its tree, and the exception went.

## Limits
Paths are relative to "/", after each component's install-location. It reports at most 20 offenders and a
count. It checks where files land, not their contents. A file the OS dictates is still in the manifest's
outside list, so uninstall removes it; manifest holds that half.

## Deviating
Write .mavergreen/deviations/install-path/<label>/ with a scope (<installed path glob>), a reason and a revisit; for example a scope of Library/Java/JavaVirtualMachines/*
and the reason "10.9's java_home looks only here". The glob matches the path in the payload; "*" spans "/" and
spaces. A good reason names the OS rule that forces a place not on the list above. A deviation never excuses
usr/local/.

Formerly the conformance rule install-path
