no-queue-citation: no tracked line cites a queue entry by number.

## Why
The queue lives in the gitignored .superpowers/, so a citation such as QUEUE.md, entry 12, resolves only in
the checkout that holds it; a reader anywhere else gets a number and no reason. Each tracked line says the
reason itself. The check matches BACKLOG or QUEUE, with or without .md, followed by a space or nothing and
a hash and a digit, and the same split across a line break, where the next line starts (after a comment
leader) with the hash and the digit.

## Incident
Undated: a code comment cited a tracked BACKLOG.md entry by number, which no other checkout could look up.

## Limits
It is a text match on every tracked text file, binaries skipped. A citation spelled another way (the queue,
item 12; Q12) is not seen.

## Deviating
No deviation is read for this id. Write the reason on the line instead of the number.

Formerly gate check 27
