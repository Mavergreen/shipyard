retired-name: no tracked file uses a retired family name.

## Why
The family was named for the OS it targets, and the names that said so are being retired one by one. scripts/retired-names lists each retired token with what replaces it, as exact, case-sensitive fixed strings matched as substrings, and the check reads every tracked text file for them. "Mavericks" names only the OS an artifact targets: MacOSX10.9.sdk, POST_10_9, the mavericks-vm repo and Action, MAVERICKS_VM_KEY, VoodooInputMavericks.kext, MavericksMultitouch.plugin and build-from-mavericks stay, so no row may be a substring of any of them. The same table drives each rename task, so the sweep and the guard that keeps it swept cannot disagree.

## Incident
2026-10-13: the names survey found 1,994 "mavericks" occurrences in shipyard, most of them meaning the family rather than the OS.

## Limits
It reads text, never meaning: a retired token quoted to explain its retirement is still a hit. It skips scripts/retired-names, the scope files of its own deviations (they spell the tokens they excuse), published release notes under .mavergreen/release-notes/, and the check fixtures under tests/fixtures/checks/. Binary files are skipped. A token spelled differently (another case, a split word) is not seen.

## Deviating
Write .mavergreen/deviations/retired-name/<label>/ with a scope, a reason and a revisit. The scope is one glob matched against <path>#<token>, so it names both the file and the retired token it may spell: tests/x-test.sh#msc.sh excuses that token in that file and no other, and a different retired token in the same file, or one a later task adds, still fails. A file that needs several tokens takes one deviation per token. A path glob with a * after the # excuses every token and is for dated history only (explain/*#*). A good reason says why the file must name the token, as a detector or a record of history does, and the revisit says what removes the need.

New in the flag day (P3, the denylist every rename task reads)
