#include <time.h>

int clock_gettime(clockid_t clk_id, struct timespec *tp)
{
	(void)clk_id;
	tp->tv_sec = 0;
	tp->tv_nsec = 0;
	return 0;
}
