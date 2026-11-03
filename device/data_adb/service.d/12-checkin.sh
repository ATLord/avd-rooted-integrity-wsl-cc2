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
# Logs to /data/adb/checkin-nudge.log

LOG=/data/adb/checkin-nudge.log

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done

# Wait (up to ~120s) for a validated default network.
i=0
while [ "$i" -lt 60 ]; do
  if dumpsys connectivity 2>/dev/null | grep -q VALIDATED; then break; fi
  sleep 2; i=$((i + 1))
done
sleep 5

{
  echo "=== $(date) checkin-nudge: network up after ~$((i * 2))s ==="
  am broadcast -a android.server.checkin.CHECKIN 2>&1
  echo "=== broadcast sent ==="
} >> "$LOG" 2>&1
