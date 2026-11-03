#!/system/bin/sh
# Nudge a Google check-in once the network is actually up.
#
# On a fresh device GMS fires its first check-in during early boot — before
# wlan0 (brought up by 10-wlan0-virtwifi.sh via virt_wifi ~25s in) is connected.
# That early attempt fails and GMS backs off for hours, so the device never gets
# a GSF android_id and Google never evaluates it: result is uncertified +
# empty Play Integrity deviceIntegrity. A single check-in after the network
# validates registers the device with the spoofed (tokay) fingerprint.
#
# 10-wlan0-virtwifi.sh retries for up to ~8 minutes, so when it is installed we
# first wait (up to 10 minutes) for its ready marker for THIS boot, then for a
# validated network as before. The broadcast is always sent at the end.
#
# Logs to /data/adb/checkin-nudge.log

LOG="${AVD_CHECKIN_LOG:-/data/adb/checkin-nudge.log}"
READY="${AVD_NET_READY:-/data/adb/avd-net-ready}"
BOOT_ID_FILE="${AVD_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
WLAN_SERVICE="${AVD_WLAN_SERVICE:-/data/adb/service.d/10-wlan0-virtwifi.sh}"

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done

ready=skipped
if [ -f "$WLAN_SERVICE" ]; then
  ready=timeout
  boot_id=$(cat "$BOOT_ID_FILE" 2>/dev/null)
  w=0
  while [ "$w" -lt 300 ]; do
    if [ -n "$boot_id" ] && [ "$(cat "$READY" 2>/dev/null)" = "$boot_id" ]; then ready=yes; break; fi
    sleep 2; w=$((w + 1))
  done
fi

# Wait (up to ~120s) for a validated default network.
i=0
while [ "$i" -lt 60 ]; do
  if dumpsys connectivity 2>/dev/null | grep -q VALIDATED; then break; fi
  sleep 2; i=$((i + 1))
done
sleep 5

[ -f "$LOG" ] && mv -f "$LOG" "$LOG.prev"
{
  echo "=== $(date) checkin-nudge: wlan ready=$ready, validated wait ~$((i * 2))s ==="
  am broadcast -a android.server.checkin.CHECKIN 2>&1
  echo "=== broadcast sent ==="
} >> "$LOG" 2>&1
