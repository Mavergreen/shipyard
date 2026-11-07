apple-clang: not a check but a deviation key: an apple-clang deviation whose scope is a path says that this file builds with Apple's clang (/usr/bin/clang, AppleClang, RequireAppleClang) because clang22 cannot do the job there.

## Why
Products build with clang22 on every host. Its clang.cfg links librecaulk.a before -lSystem, so a Recaulk fix
reaches every product at its next build, and nothing a build needs comes from the Command Line Tools. A build
that uses Apple's clang misses both, so it is allowed only where clang22 cannot do the job, and declared.

## Incident
None recorded.

## Limits
No check finds a use of Apple's clang yet, so an undeclared use passes; the declarations are the inventory of
what is left to move. The products that used Apple's clang before this rule are leftovers queued to move,
not exceptions to copy.

## Deviating
Write .mavergreen/deviations/apple-clang/<label>/ with a scope (the path that calls it), a reason and a revisit. A good reason names what clang22
cannot do there; a good revisit names the shared fix that would retire the use.

New in the flag day (merged from main's rule that products build with clang22 on every host)
