// SPDX-License-Identifier: GPL-2.0-only
/*
 * smbx_ctl - control the qcom-smbx (SMB5) charger from userspace.
 *
 * Two knobs, both 0644 module parameters:
 *
 *   charging   : 1 = allow battery charging, 0 = stop charging
 *                (/sys/module/smbx_ctl/parameters/charging)
 *   usb_input  : 1 = draw power from USB, 0 = suspend USB input
 *                (/sys/module/smbx_ctl/parameters/usb_input)
 *
 * Used to cap a phone-server at ~80% SoC: stop charging at the top and
 * (optionally) let the battery drain once by suspending USB input.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/regmap.h>
#include <linux/device.h>
#include <linux/kstrtox.h>
#include <linux/sysfs.h>

/* register offsets, relative to the charger node base (0x1000 on SMB5) */
#define CHARGING_ENABLE_CMD	0x42
#define CHARGING_ENABLE_CMD_BIT	BIT(0)
#define USBIN_CMD_IL		0x340
#define USBIN_SUSPEND_BIT	BIT(0)

static struct regmap *smb_regmap;
static unsigned int smb_base;
static struct device *smb_dev;

static int smbx_write_bit(unsigned int off, unsigned int bit, bool on,
			  const char *what)
{
	unsigned int reg = 0;
	int ret;

	ret = regmap_update_bits(smb_regmap, smb_base + off, bit, on ? bit : 0);
	if (ret)
		return ret;

	ret = regmap_read(smb_regmap, smb_base + off, &reg);
	if (ret)
		return ret;

	pr_info("smbx_ctl: %s %s (reg 0x%04x=0x%02x)\n",
		what, on ? "on" : "off", smb_base + off, reg);
	return 0;
}

static int smbx_chg_set(const char *val, const struct kernel_param *kp)
{
	bool on;
	int ret = kstrtobool(val, &on);

	if (ret)
		return ret;
	return smbx_write_bit(CHARGING_ENABLE_CMD, CHARGING_ENABLE_CMD_BIT,
			      on, "charging");
}

static int smbx_chg_get(char *buf, const struct kernel_param *kp)
{
	unsigned int reg = 0;
	int ret = regmap_read(smb_regmap,
			      smb_base + CHARGING_ENABLE_CMD, &reg);

	if (ret)
		return ret;
	return sysfs_emit(buf, "%d\n", !!(reg & CHARGING_ENABLE_CMD_BIT));
}

static int smbx_usb_set(const char *val, const struct kernel_param *kp)
{
	bool on;
	int ret = kstrtobool(val, &on);

	if (ret)
		return ret;
	return smbx_write_bit(USBIN_CMD_IL, USBIN_SUSPEND_BIT, !on, "usb input");
}

static int smbx_usb_get(char *buf, const struct kernel_param *kp)
{
	unsigned int reg = 0;
	int ret = regmap_read(smb_regmap, smb_base + USBIN_CMD_IL, &reg);

	if (ret)
		return ret;
	return sysfs_emit(buf, "%d\n", !(reg & USBIN_SUSPEND_BIT));
}

static const struct kernel_param_ops smbx_chg_ops = {
	.set = smbx_chg_set,
	.get = smbx_chg_get,
};

static const struct kernel_param_ops smbx_usb_ops = {
	.set = smbx_usb_set,
	.get = smbx_usb_get,
};

module_param_cb(charging, &smbx_chg_ops, NULL, 0644);
MODULE_PARM_DESC(charging, "1 = allow battery charging, 0 = stop charging");

module_param_cb(usb_input, &smbx_usb_ops, NULL, 0644);
MODULE_PARM_DESC(usb_input, "1 = draw power from USB, 0 = suspend USB input");

static int smbx_match(struct device *dev, const void *data)
{
	if (dev->of_node &&
	    of_device_is_compatible(dev->of_node, "qcom,pm8150b-charger"))
		return 1;
	return 0;
}

static int __init smbx_ctl_init(void)
{
	unsigned int chg = 0, usb = 0;
	u32 base;
	int ret;

	smb_dev = bus_find_device(&platform_bus_type, NULL, NULL, smbx_match);
	if (!smb_dev)
		return -ENODEV;

	smb_regmap = dev_get_regmap(smb_dev->parent, NULL);
	if (!smb_regmap) {
		put_device(smb_dev);
		return -ENODEV;
	}

	ret = device_property_read_u32(smb_dev, "reg", &base);
	if (ret) {
		put_device(smb_dev);
		return ret;
	}
	smb_base = base;

	ret = regmap_read(smb_regmap, smb_base + CHARGING_ENABLE_CMD, &chg);
	if (ret) {
		put_device(smb_dev);
		return ret;
	}
	ret = regmap_read(smb_regmap, smb_base + USBIN_CMD_IL, &usb);
	if (ret) {
		put_device(smb_dev);
		return ret;
	}

	pr_info("smbx_ctl: base=0x%04x charging=%u usb_input=%u\n", smb_base,
		!!(chg & CHARGING_ENABLE_CMD_BIT),
		!(usb & USBIN_SUSPEND_BIT));
	return 0;
}

static void __exit smbx_ctl_exit(void)
{
	if (smb_dev)
		put_device(smb_dev);
	pr_info("smbx_ctl: unloaded, hardware state left as-is\n");
}

module_init(smbx_ctl_init);
module_exit(smbx_ctl_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Qualcomm SMB5 charger control for charge limiting");
