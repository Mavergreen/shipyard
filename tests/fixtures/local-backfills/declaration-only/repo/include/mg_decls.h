#include <stddef.h>
#include <time.h>

extern int clock_gettime(clockid_t clk_id, struct timespec *tp);
void *aligned_alloc(size_t alignment,
                    size_t size);
__attribute__((weak_import)) extern int timingsafe_bcmp(const void *, const void *, size_t);
