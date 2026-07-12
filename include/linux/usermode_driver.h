/* SPDX-License-Identifier: GPL-2.0 */
/* Minimal stub for A16 eBPF port without full usermode driver support. */
#ifndef _LINUX_USERMODE_DRIVER_H
#define _LINUX_USERMODE_DRIVER_H

#include <linux/types.h>
#include <linux/pid.h>

struct umd_info {
	const char *driver_name;
	struct file *pipe_to_umh;
	struct file *pipe_from_umh;
	struct list_head list;
	void *wd; /* working directory blob if any */
	pid_t tgid;
};

static inline int umd_load_blob(struct umd_info *info, const void *data, size_t len)
{
	return -ENODEV;
}

static inline void umd_unload_blob(struct umd_info *info) { }

static inline int fork_usermode_driver(struct umd_info *info)
{
	return -ENODEV;
}

#endif /* _LINUX_USERMODE_DRIVER_H */
