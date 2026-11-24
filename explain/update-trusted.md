update-trusted: the new signature verifies against the family key.

## Why
Every installed client trusts one public key, keys/feed-ed25519.pub in shipyard. ed25519-sign's self-check
cannot see a mismatch, since it checks against the public half of the key it was handed. So
sign_and_appcast.sh, after signing, ed25519-verifies the new signature against that file, beside the
scripts, and nothing else; nothing is fetched. No appcast is emitted on a refusal.

## Incident
None recorded.

## Limits
A rotation is a commit to keys/feed-ed25519.pub. The Engine embeds the same file, so a rotation needs an
Engine release that carries the new key before any release is signed by it.

## Deviating
No deviation is read for this id. --pubkey and --allow-key-change are refused: the trusted key is
keys/feed-ed25519.pub; rotate it there.

Formerly assert_update_trusted.sh
