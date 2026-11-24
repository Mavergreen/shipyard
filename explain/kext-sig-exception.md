kext-sig-exception: a kext a pkg installs in Library/Extensions that loads at boot is listed in 10.9's OSKextSigExceptionList through stage_product.sh --boot-kext, and the list names only kexts the pkg ships.

## Why
10.9's kextd refuses an unsigned kext in /Library/Extensions unless its CFBundleIdentifier is in
AppleKextExcludeList's OSKextSigExceptionList. stage_product.sh --boot-kext writes that entry at the
installed kext's CFBundleVersion in the generated postinstall, and the product's pre-uninstall removes
it. kext-facts.sh reads each pkg's kexts and the ids its generated postinstall lists; a boot kext with
no entry would install and never load, and an entry for a kext the pkg does not ship would widen 10.9's
exception list for nothing.

## Incident
None recorded.

## Limits
A library kext (OSBundleCompatibleVersion and no IOKitPersonalities) loads only as another kext's
dependency and is not judged. A kext nested in another bundle, or outside Library/Extensions, is not
required to be listed, though it may be.

## Deviating
Write .mavergreen/deviations/kext-sig-exception/<label>/ with a scope (the kext's CFBundleIdentifier),
a reason saying how the kext loads without the entry, and a revisit.

New in the flag day (from main's conformance kext-sig-exception)
