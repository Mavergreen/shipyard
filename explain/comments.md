comments: every comment cites a reason, # platform: or # spec:.

## Why
A comment is the one artifact that can be confidently wrong while every test stays green. The default is no
comment: make the code say it, in a named function or a test whose failure message is the sentence you were
about to write. A comment that survives cites one of two reasons, and the set is closed. # platform: states
an external fact about a platform or a tool. # spec: points at where a decision lives, and its first line
must carry a locatable citation: a path, a filename with an extension, a YYYY-MM-DD date, or a numbered
decision. An unrecognised tag fails, and the answer is to propose a new reason to the maintainer, never to
invent a tag. The check verifies that a reason is cited, never that it is true.

It is opt-in, by a repo-local comment-reasons file that lists one recognised tag per line, so adopting the
check is a repo's own sweep and the moving @v1 does not redden fourteen consumers at once.

## Incident
2026-09-13: the comments sweep found that 111 of 202 # spec: tags under tests/ were the original untagged
comment with a four-character prefix bolted on, and the tag-line rule closed that. The convention itself
began with three false claims that reached review (a parser claim, a conformance-checker claim and a
stale-marker claim), each confidently wrong and each living in a comment (undated).

## Limits
Shebangs, machine directives, # usage: blocks and heredoc bodies are exempt, and so is an inline trailing
comment, because finding a # reliably inside a shell line needs a parser. The usage-block exemption is the
one nobody can police. It does not read a repo that has no comment-reasons file.

## Deviating
Write .mavergreen/deviations/comments/<label>/ with a scope, a reason and a revisit. A scope of * switches
comment checking off for the whole repo; any other scope excuses only the tracked files it matches, and each
excused file is named in the output. A good reason says what makes tagging impossible, and the revisit says
what ends it: usually the sweep that tags them. Prefer tagging or deleting the comments.

Formerly gate check 15
