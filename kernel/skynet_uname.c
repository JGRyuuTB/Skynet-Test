// SPDX-License-Identifier: GPL-2.0
/*
 * SKYNET uname spoof.
 *
 * Runtime control through /proc/skynet_uname (root only):
 *   echo off            > /proc/skynet_uname   # real values
 *   echo 3              > /proc/skynet_uname   # preset by number
 *   echo 5.10           > /proc/skynet_uname   # preset by name
 *   echo "custom 5.4.1-foo" > /proc/skynet_uname
 *   echo "version #1 SMP Foo" > /proc/skynet_uname
 *   cat /proc/skynet_uname                      # list presets + current
 *
 * Boot default: build with -DSKYNET_UNAME_DEFAULT=<preset number> (0 = off).
 * Hooked from the newuname syscall (see scripts/apply-skynet-uname.py).
 */
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/spinlock.h>
#include <linux/string.h>
#include <linux/ctype.h>
#include <linux/utsname.h>

#ifndef SKYNET_UNAME_DEFAULT
#define SKYNET_UNAME_DEFAULT 0
#endif

struct skynet_preset {
	const char *name;
	const char *release;
	const char *version;
};

static const struct skynet_preset presets[] = {
	{ "4.19", "4.19.325-perf",
	  "#1 SMP PREEMPT Tue Jan 14 10:21:09 UTC 2025" },
	{ "5.4",  "5.4.289-android12-9-00001-g5a1b2c3d4e5f",
	  "#1 SMP PREEMPT Wed Feb 12 08:15:42 UTC 2025" },
	{ "5.10", "5.10.226-android13-4-00001-g7c8d9e0f1a2b",
	  "#1 SMP PREEMPT Mon Mar 10 11:02:27 UTC 2025" },
	{ "5.15", "5.15.170-android14-11-00001-g3b4c5d6e7f80",
	  "#1 SMP PREEMPT Thu Apr 17 09:44:10 UTC 2025" },
	{ "6.1",  "6.1.115-android14-11-00001-g9a8b7c6d5e4f",
	  "#1 SMP PREEMPT Fri May 23 13:30:55 UTC 2025" },
	{ "6.6",  "6.6.66-android15-8-00001-g1f2e3d4c5b6a",
	  "#1 SMP PREEMPT Tue Jun 10 07:12:03 UTC 2025" },
};
#define NPRESETS ARRAY_SIZE(presets)

static DEFINE_SPINLOCK(skynet_lock);
static int cur_preset = SKYNET_UNAME_DEFAULT;	/* 0 off, 1..N preset, -1 custom */
static char cust_release[__NEW_UTS_LEN + 1];
static char cust_version[__NEW_UTS_LEN + 1];

void skynet_uname_spoof(struct new_utsname *u)
{
	unsigned long flags;

	spin_lock_irqsave(&skynet_lock, flags);
	if (cur_preset >= 1 && cur_preset <= (int)NPRESETS) {
		strlcpy(u->release, presets[cur_preset - 1].release,
			sizeof(u->release));
		strlcpy(u->version, presets[cur_preset - 1].version,
			sizeof(u->version));
	} else if (cur_preset == -1) {
		if (cust_release[0])
			strlcpy(u->release, cust_release, sizeof(u->release));
		if (cust_version[0])
			strlcpy(u->version, cust_version, sizeof(u->version));
	}
	spin_unlock_irqrestore(&skynet_lock, flags);
}

static bool valid_str(const char *s)
{
	if (!*s || strlen(s) > __NEW_UTS_LEN)
		return false;
	/* allow UTF-8 (bytes >= 0x80), reject control chars */
	for (; *s; s++)
		if ((unsigned char)*s < 0x20 || *s == 0x7f)
			return false;
	return true;
}

static int skynet_show(struct seq_file *m, void *v)
{
	unsigned long flags;
	int i, cur;

	spin_lock_irqsave(&skynet_lock, flags);
	cur = cur_preset;
	spin_unlock_irqrestore(&skynet_lock, flags);

	seq_printf(m, "current: %s\n",
		   cur == 0 ? "off" : cur == -1 ? "custom" : presets[cur - 1].name);
	seq_puts(m, "0) off\n");
	for (i = 0; i < (int)NPRESETS; i++)
		seq_printf(m, "%d) %s  %s\n", i + 1, presets[i].name,
			   presets[i].release);
	seq_puts(m, "custom <release> | version <string>\n");
	return 0;
}

static int skynet_open(struct inode *inode, struct file *file)
{
	return single_open(file, skynet_show, NULL);
}

static ssize_t skynet_write(struct file *file, const char __user *ubuf,
			    size_t len, loff_t *off)
{
	char buf[2 * __NEW_UTS_LEN];
	char *s;
	unsigned long flags;
	int n, i, val = -2;

	if (!len || len >= sizeof(buf))
		return -EINVAL;
	if (copy_from_user(buf, ubuf, len))
		return -EFAULT;
	buf[len] = '\0';
	s = strim(buf);

	if (!strncmp(s, "custom ", 7)) {
		s = strim(s + 7);
		if (!valid_str(s))
			return -EINVAL;
		spin_lock_irqsave(&skynet_lock, flags);
		strlcpy(cust_release, s, sizeof(cust_release));
		cur_preset = -1;
		spin_unlock_irqrestore(&skynet_lock, flags);
		return len;
	}
	if (!strncmp(s, "version ", 8)) {
		s = strim(s + 8);
		if (!valid_str(s))
			return -EINVAL;
		spin_lock_irqsave(&skynet_lock, flags);
		strlcpy(cust_version, s, sizeof(cust_version));
		cur_preset = -1;
		spin_unlock_irqrestore(&skynet_lock, flags);
		return len;
	}

	if (!strcmp(s, "off")) {
		val = 0;
	} else if (!kstrtoint(s, 10, &n)) {
		if (n >= 0 && n <= (int)NPRESETS)
			val = n;
	} else {
		for (i = 0; i < (int)NPRESETS; i++)
			if (!strcmp(s, presets[i].name))
				val = i + 1;
	}
	if (val == -2)
		return -EINVAL;

	spin_lock_irqsave(&skynet_lock, flags);
	cur_preset = val;
	spin_unlock_irqrestore(&skynet_lock, flags);
	return len;
}

static const struct file_operations skynet_fops = {
	.owner   = THIS_MODULE,
	.open    = skynet_open,
	.read    = seq_read,
	.write   = skynet_write,
	.llseek  = seq_lseek,
	.release = single_release,
};

static int __init skynet_uname_init(void)
{
	proc_create("skynet_uname", 0600, NULL, &skynet_fops);
	return 0;
}
late_initcall(skynet_uname_init);
