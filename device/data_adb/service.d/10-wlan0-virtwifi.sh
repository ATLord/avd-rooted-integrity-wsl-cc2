#!/system/bin/sh
# Bring up wlan0 as a virt_wifi wrapper over eth0 and connect to VirtWifi.
# On success, write the current boot_id to $READY so that 12-checkin.sh and the
# host-side x86/scripts/start.sh know the network is up for THIS boot (a marker
# left from a previous boot never matches).
LOG="${AVD_WLAN_LOG:-/data/adb/wlan0-setup.log}"
READY="${AVD_NET_READY:-/data/adb/avd-net-ready}"
BOOT_ID_FILE="${AVD_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
rm -f "$READY"

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
sleep 25

# Keep the previous boot's log for comparison instead of growing forever.
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.prev"
{
  echo "=== $(date) start ==="
  /system/bin/ip link set eth0 up
  if ! /system/bin/ip link show wlan0 2>/dev/null; then
    /system/bin/ip link add link eth0 name wlan0 type virt_wifi 2>&1
  fi
  /system/bin/ip link set wlan0 up
  sleep 3

  # boot_completed can become 1 before the settings and Wi-Fi services are ready.
  # Retry boundedly instead of treating a transient Binder failure as success.
  connected=0
  for attempt in $(seq 1 30); do
    if /system/bin/settings put global captive_portal_mode 0 >/dev/null 2>&1 &&
       /system/bin/settings put global captive_portal_detection_enabled 0 >/dev/null 2>&1 &&
       /system/bin/svc wifi enable >/dev/null 2>&1; then
      sleep 5
      /system/bin/cmd wifi connect-network VirtWifi open >/dev/null 2>&1 || true
      sleep 5
      if /system/bin/cmd wifi status 2>/dev/null | grep -q 'Wifi is connected to "VirtWifi"'; then
        connected=1
        echo "VirtWifi connected (attempt $attempt)"
        cat "$BOOT_ID_FILE" > "$READY"
        break
      fi
    fi
    sleep 5
  done
  [ "$connected" -eq 1 ] || echo 'VirtWifi did not connect after retries'

  echo "--- post-connect ---"
  /system/bin/dumpsys connectivity | grep -E "Active default|VALIDATED" | head -3
  /system/bin/ip addr show wlan0 | grep inet | head -3
  echo "=== done $(date) ==="
} >> "$LOG" 2>&1
