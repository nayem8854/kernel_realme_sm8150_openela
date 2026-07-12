/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_ATOMIC_COMPAT_A16_H
#define _LINUX_ATOMIC_COMPAT_A16_H

#include <linux/types.h>
#include <asm/atomic.h>

#ifndef atomic64_fetch_add_unless
static inline long atomic64_fetch_add_unless(atomic64_t *v, long a, long u)
{
	long c, old;

	c = atomic64_read(v);
	for (;;) {
		if (unlikely(c == (long)u))
			break;
		old = atomic64_cmpxchg(v, c, c + a);
		if (old == c)
			break;
		c = old;
	}
	return c;
}
#endif

#endif /* _LINUX_ATOMIC_COMPAT_A16_H */
