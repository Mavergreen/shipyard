#include <sys/time.h>
#include <time.h>

int clock_gettime(clockid_t clk_id, struct timespec *tp)
{
	struct timeval tv;

	(void)clk_id;
	if (gettimeofday(&tv, NULL) != 0)
		return -1;
	tp->tv_sec = tv.tv_sec;
	tp->tv_nsec = tv.tv_usec * 1000;
	return 0;
}

int
clock_getres(clockid_t clk_id, struct timespec *res)
{
	(void)clk_id;
	res->tv_sec = 0;
	res->tv_nsec = 1000;
	return 0;
}
