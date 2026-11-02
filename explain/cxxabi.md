cxxabi: one process gets one C++ runtime.

## Why
Two copies of libc++abi in one process each keep their own exception and type-info state, so a throw that
crosses from one to the other is not caught, or terminates. artifact-facts.sh reads every shipped
Mach-O with macho-cxxabi.sh and reports each C++ runtime symbol a slice defines beyond the allow-list
(what the pinned Recaulk's librecaulk.a defines), and each libc++abi it loads other than
/usr/lib/libc++abi.dylib or libcxx22's libc++abi.1.dylib. Either fails, once per path. Hidden definitions
count.

## Incident
Undated: codex-cli's bin/codex-code-mode-host carried a whole libc++abi as private externals, a second
runtime even though hidden.

## Limits
The allow-list moves with .mavergreen/ingredients/recaulk/VERSION. Failures are listed for the first twenty paths, then
counted. A path in scripts/conventions-grandfathered for this repo, known from $GITHUB_REPOSITORY, is
warned rather than failed.

## Deviating
Write "- cxxabi:<install-path glob>: <reason>; exit: <how it goes away>". The failure prints the line for
its path. deviations.sh refuses a bare form and a glob of only *, ? and /.

Formerly conformance's cxxabi rule
