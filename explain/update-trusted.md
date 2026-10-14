update-trusted: the new signature verifies against the key installed clients already trust.

## Why
A Sparkle client verifies against the SUPublicEDKey of the updater it already has, which came from the pkg the
feed offered last time: not the repo's .pub, and not the key the new pkg ships. ed25519-sign's self-check
cannot see a mismatch, since it checks against the public half of the key it was handed. So
sign_and_appcast.sh, after signing, reads the new pkg's SUFeedURL, fetches the live feed's enclosure pkg, and
ed25519-verifies the new signature against that pkg's updater key (updater_pubkey.sh reads a pkg's key and
feed). No appcast is emitted on a refusal. A first release (feed 404) is checked against the new pkg's own
key; a feed that cannot be read fails closed rather than pretend to be a first release.

Changing a product's key is a bridge: ship the new .pub in a release signed with the old key, which passes
and says the next release needs the new key, then switch SPARKLE_PRIVATE_KEY after it publishes. Swapping key
and secret together fails the check, because every installed updater would reject that release.

## Incident
None recorded.

## Limits
It verifies against the key in the live release's updater. A client that has not updated through the bridge
stays on the old key. The check and the Sparkle key rules retire with Sparkle (the Engine's signing key
keeps "never on a command line" as an id).

## Deviating
No deviation is read for this id. Only a deliberate decision to strand installed clients passes
--allow-key-change, where the signature must verify against the new key, and the workflow that passes it
must say why.

Formerly assert_update_trusted.sh
