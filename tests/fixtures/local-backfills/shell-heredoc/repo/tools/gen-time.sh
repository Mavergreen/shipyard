#!/bin/sh
# platform: host-agnostic
set -eu
cat > "$1" <<'SRC'
#include <time.h>
int clock_gettime(clockid_t c, struct timespec *t) { (void)c; t->tv_sec = 0; t->tv_nsec = 0; return 0; }
SRC
