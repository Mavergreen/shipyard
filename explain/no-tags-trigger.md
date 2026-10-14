no-tags-trigger: no workflow has a tags: key under push:.

## Why
Tags are retired as a release input: a workflow_dispatch covers every case a tag used to
(gh workflow run release.yml --ref <any ref>). A new repo adds no tags: trigger, and an existing one removes
it. Only a tags: or tags-ignore: key under push: is a trigger; a dispatch input named tags is not. The
exception in assert_tag_publishable.sh for the tag that triggered the run serves only the legacy triggers and
goes when the last one does (QUEUE #26).

## Incident
None recorded. On 2026-09-26 twelve repos still carried push: tags: ['*-mavericks.*'] in release.yml (QUEUE
#26), the legacy state this check ends.

## Limits
It needs workflows that parse (workflow-yaml names the place) and python3. It reads the parsed on: key, so a
trigger written in a form the parser reads as something else is not caught.

## Deviating
Write "- no-tags-trigger:<workflow path>: <reason>". A good reason says why the workflow is still tag-driven
and when it moves to dispatch ("Revisit when <condition>.").

New in the flag day (K6, hand-rolled in recaulk, ca-certs and longboat)
