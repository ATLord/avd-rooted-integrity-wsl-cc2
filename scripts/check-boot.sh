#!/usr/bin/env bash
# Read-only: validate lifecycle execution for THIS boot, not directory presence.
set -uo pipefail
ADB="${ADB:-adb}"
read_root() { $ADB shell "su -c '$1'" 2>&1 | tr -d '\r'; }
failed=0
boot=$(read_root 'cat /proc/sys/kernel/random/boot_id')
if [[ ! "$boot" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "FAIL: cannot read boot ID as root: $boot" >&2; exit 1
fi
for stage in post-fs-data service; do
  seen=$(read_root "cat /data/adb/avd-boot/$stage.boot")
  if [[ "$seen" == "$boot" ]]; then
    echo "PASS: $stage hook entered during current boot"
  else
    echo "FAIL: $stage hook has no current-boot evidence ($seen)" >&2
    failed=1
  fi
done
for module in playintegrityfix rezygisk tricky_store; do
  state=$(read_root "test -d /data/adb/modules/$module && test ! -e /data/adb/modules/$module/disable && test ! -e /data/adb/modules/$module/remove && test ! -d /data/adb/modules_update/$module && echo enabled")
  if [[ "$state" != enabled ]]; then
    echo "FAIL: $module absent, disabled, removed or pending reboot" >&2; failed=1
  fi
done
if [[ "$failed" != 0 ]]; then
  echo 'Inspect /data/adb/ksud (init entry), KSU safe mode, module disable flags and /data/adb/ksu/log/.' >&2
  read_root 'ls -lZ /data/adb/ksud /data/adb/ksu/bin/ksud /data/adb/post-fs-data.d /data/adb/service.d'
  echo 'Re-run install-modules.sh to install userspace; cold boot and retry. If still absent, rebuild the kernel and inspect init/ksud boot logs. Do not replay post-fs-data after boot.' >&2
fi
exit "$failed"
