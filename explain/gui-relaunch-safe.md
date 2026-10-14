gui-relaunch-safe: a postinstall that relaunches a GUI app also stops the old instance.

## Why
The "two menu-bar icons after an update" bug: a postinstall that relaunches a GUI menu-bar app must also stop
the prior instance, or macOS runs both. The behaviour is dynamic, with no artifact to inspect like a
PackageInfo, so the check lints the postinstall script the pkg actually ships, from every component of every
pkg in the dist. "Relaunches a GUI menu-bar app" means open -a of an app, or launchctl asuser ... launchctl
load of a per-user agent. The shared update-check agent, loaded through launchctl bootstrap gui/ or sudo -u
... launchctl load, does not match, and neither does a root LaunchDaemon. "Stops the prior instance" means a
call to mav_stop_gui_instance (postinstall-stop-gui.sh), a pkill, or launchctl asuser ... unload.

## Incident
Undated: the bug the script's header names, "two menu-bar icons after an update". The conventions skill and
the queue record no date or product for it.

## Limits
It is a presence lint: it sees that a stop call exists, not that it runs before the relaunch or targets the
right process. A relaunch spelled some other way is not recognised. It needs bsdtar to read the pkg's
Scripts archive.

## Deviating
No deviation is read for this id. Call mav_stop_gui_instance before the relaunch, or pkill or unload the old
one.

Formerly assert_gui_relaunch_safe.sh
