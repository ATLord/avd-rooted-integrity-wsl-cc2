#!/system/bin/sh
mkdir -p /data/adb/avd-boot || exit 1
cat /proc/sys/kernel/random/boot_id > /data/adb/avd-boot/service.boot
