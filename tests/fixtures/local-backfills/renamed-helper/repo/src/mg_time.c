#include <sys/time.h>
#include <time.h>

int mg_monotonic_now(struct timespec *tp)
{
	struct timeval tv;

	if (gettimeofday(&tv, NULL) != 0)
		return -1;
	tp->tv_sec = tv.tv_sec;
	tp->tv_nsec = tv.tv_usec * 1000;
	return 0;
}
