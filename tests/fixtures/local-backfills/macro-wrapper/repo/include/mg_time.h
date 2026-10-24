#include <time.h>

#define clock_gettime(clk, ts) mg_time_now((clk), (ts))
# define aligned_alloc mg_aligned_alloc
#define MG_CLOCK clock_gettime

int mg_time_now(int clk, struct timespec *ts);
void *mg_aligned_alloc(size_t alignment, size_t size);
