### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Android17 kernel — Xiaomi Miatoll (SM6250).
##
## This file is overlaid onto a checkout of osm0sis/AnyKernel3 by
## scripts/package-anykernel.sh. It leaves the boot ramdisk untouched:
## Rootless 17S build with no KernelSU or SUSFS hooks.
##
## VERIFY THE BLOCK/DEVICE SETTINGS BELOW FOR YOUR ROM BEFORE FLASHING.
## miatoll is an A-only (non-A/B) device family; some ported ROMs differ.

### AnyKernel setup
# global properties
properties() { '
kernel.string=ゼロツー002-RTX Android17 Kernel for miatoll
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=curtana
device.name2=joyeuse
device.name3=excalibur
device.name4=gram
device.name5=miatoll
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
dump_boot;

# No ramdisk edits or module injection needed (rootless 17S kernel).

write_boot;
## end boot install
