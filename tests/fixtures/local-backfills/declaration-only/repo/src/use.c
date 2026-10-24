#include "mg_decls.h"

int now(struct timespec *ts)
{
	void *p;

	clock_gettime(CLOCK_MONOTONIC, ts);
	p = aligned_alloc(16, 32);
	if (timingsafe_bcmp(p, p, 0) != 0)
		return -1;
	return clock_gettime(CLOCK_REALTIME, ts);
}

void reset(void)
{
	struct timespec ts;
clock_gettime(CLOCK_REALTIME, &ts);
}
