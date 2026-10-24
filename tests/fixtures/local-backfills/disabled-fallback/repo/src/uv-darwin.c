#include <time.h>

#if !defined(MAVERGREEN_HAVE_RECAULK)
/* Fallback implementation for macOS 10.9, which lacks this API. */
int clock_gettime(clockid_t clk_id, struct timespec *tp) {
	(void)clk_id;
	tp->tv_sec = 0;
	tp->tv_nsec = 0;
	return 0;
}
#endif

#if 0
int mkostemp(char *path, int oflags)
{
	(void)oflags;
	return mkstemp(path);
}
#endif
