/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_NS_COMMON_H
#define _LINUX_NS_COMMON_H

#include <linux/types.h>
#include <linux/kdev_t.h>

struct proc_ns_operations;

struct ns_common {
	atomic_long_t stashed;
	const struct proc_ns_operations *ops;
	unsigned int inum;
};

/**
 * ns_match - check if namespace matches the given (dev,ino) pair
 * @ns: namespace common object
 * @dev: device number (ignored on this 4.14 backport; ino is enough)
 * @ino: inode number of the nsfs entry
 */
static inline bool ns_match(const struct ns_common *ns, dev_t dev, ino_t ino)
{
	return ns && ns->inum == (unsigned int)ino;
}

#endif
