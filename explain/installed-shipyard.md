installed-shipyard: an installed shipyard is what we meant to ship.

## Why
Asserts that the cmake product beside shipyard is the CMake in components/cmake/version and universal;
that the farm's shipyard-cmake, shipyard-ctest, shipyard-cpack and shipyard-check are executable on the
default PATH, and shipyard-check runs from there; that a probe under a stripped environment finds shipyard
through shipyard-cmake; that the installed updater is
universal; that nothing is left in /usr/local/bin from the old layout; that an installed mavergreen helper
passes its own check; and that any other cmake is refused, by name. --root defaults to "/" (a real install);
a fixture root makes it unit-testable. It is shipyard's own check, run in its install smoke.

## Incident
Undated: the assertions used to live inline in release.yml's install smoke, a step that runs only on a push to
main. That left them unrunnable until the very push that must not be a rehearsal, so release.yml, ci.yml and
this script's test now share one statement of what an installed shipyard looks like.

## Limits
macOS-only: lipo checks the installed universal binaries. It examines a prefix, so it says nothing about a
package that installed into a different one. Exit 2 is a usage error, never "the installed shipyard is
wrong".

## Deviating
No deviation is read for this id; it checks shipyard's own install, not a product repo. Fix the install or
the pin it names (--cmake-version).

Formerly assert-installed-shipyard.sh
