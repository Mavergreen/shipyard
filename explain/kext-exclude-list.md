kext-exclude-list: no pkg script edits AppleKextExcludeList other than through stage_product.sh --boot-kext's generated block.

## Why
AppleKextExcludeList is Apple's file. The --boot-kext block adds and removes only the ids a product
declares, at their installed versions, and leaves every other key alone; a hand-written edit can drop
Apple's entries or outlive the product that made it.

## Incident
None recorded.

## Limits
kext-facts.sh reads the preinstall and postinstall for the names AppleKextExcludeList and
OSKextSigExceptionList; a script that reaches the file another way is not seen.

## Deviating
No deviation is read: declare the kext with stage_product.sh --boot-kext and drop the hand-written edit.

New in the flag day (from main's conformance kext-exclude-list)
