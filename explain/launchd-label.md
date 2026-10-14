launchd-label: every installed launchd job has a Label inside dev.mavergreen.*, and its plist is named for the Label.

## Why
Two installs that claim one Label silently overwrite each other, and launchctl and every uninstaller look
for <Label>.plist. The rule covers every Library/LaunchAgents and Library/LaunchDaemons plist in a pkg
payload.

## Incident
Undated in the conventions skill: tailscale once installed its daemon as com.tailscale.tailscaled, the
Label upstream's own tailscaled install-system-daemon writes, so the two installs could silently overwrite
each other.

## Limits
It reads the plist's Label as the facts producer expands the payload. A job installed by a postinstall
script rather than the payload is not seen.

## Deviating
Write "- launchd-label:<the Label>: <reason>", scoped to the Label. A good reason says why the Label must be
upstream's, and the exit.

Formerly the conformance rule launchd-label
