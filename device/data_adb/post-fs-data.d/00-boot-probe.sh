#!/system/bin/sh
# Proves entry only; actual effects are checked separately.
mkdir -p /data/adb/avd-boot || exit 1
cat /proc/sys/kernel/random/boot_id > /data/adb/avd-boot/post-fs-data.boot
