#include <stdlib.h>

static inline void *aligned_alloc(size_t alignment, size_t size)
{
	void *p = NULL;

	return posix_memalign(&p, alignment, size) == 0 ? p : NULL;
}

static __inline__ int
timingsafe_bcmp(const void *a, const void *b, size_t n)
{
	const unsigned char *x = a, *y = b;
	int r = 0;

	while (n--)
		r |= *x++ ^ *y++;
	return r != 0;
}
