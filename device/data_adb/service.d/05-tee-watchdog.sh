#!/system/bin/sh
# /data/adb/service.d/05-tee-watchdog.sh
# Late_start watchdog for the TEESimulator daemon.
#
# DEFAULT: ALERT ONLY. If TEESimulator dies, this logs it and tells you to cold
# reboot. It does NOT relaunch the daemon, because a relaunch after boot runs
# TEESimulator's "TEE functionality check" when keymint is already ready, which
# lands it in PATCH mode: the process is alive again, but the attestation chain
# is broken and the Play Integrity verdict comes back empty (see
# 08-tee-broken.sh and docs/INTEGRITY_CHAIN.md "Layer 1b"). A cold reboot is
# the only recovery that restores GENERATE mode.
#
# OPTIONAL: upstream auto-relaunch. Create the flag file below to restore the
# original behaviour (re-invoke tricky_store's own service.sh when the daemon
# is gone). The flag is re-read every cycle, so it takes effect without a
# reboot:
#     su -c touch /data/adb/avd-fake/tee-watchdog-relaunch     # enable
#     su -c rm    /data/adb/avd-fake/tee-watchdog-relaunch     # back to alert-only
#
# Logs to /data/adb/tee-watchdog.log
LOG="${TEE_WATCHDOG_LOG:-/data/adb/tee-watchdog.log}"
TS_DIR="${TEE_WATCHDOG_TS_DIR:-/data/adb/modules/tricky_store}"
RELAUNCH_FLAG="${TEE_WATCHDOG_FLAG:-/data/adb/avd-fake/tee-watchdog-relaunch}"

# Wait for boot completion so we don't fight the initial launch.
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 2
done
sleep 10

if [ -e "$RELAUNCH_FLAG" ]; then mode=relaunch; else mode=alert-only; fi
{
  echo "=== $(date) watchdog start (mode: $mode) ==="
} >> "$LOG" 2>&1

alerted=0
while true; do
  PID=$(pidof TEESimulator 2>/dev/null)
  if [ -z "$PID" ]; then
    if [ -e "$RELAUNCH_FLAG" ]; then
      echo "[$(date)] TEESimulator down, relaunching (flag $RELAUNCH_FLAG present; expect PATCH mode)" >> "$LOG"
      (
        cd "$TS_DIR" || exit
        nohup sh ./service.sh >/dev/null 2>&1 &
      )
      sleep 15
      NEW=$(pidof TEESimulator 2>/dev/null)
      echo "[$(date)] relaunch result pid=$NEW" >> "$LOG"
    elif [ "$alerted" -eq 0 ]; then
      {
        echo "[$(date)] TEESimulator is NOT running. Not relaunching: a post-boot relaunch"
        echo "  lands in PATCH mode and the Play Integrity verdict goes empty."
        echo "  Recover with a cold reboot (adb reboot)."
        echo "  To restore auto-relaunch instead: touch $RELAUNCH_FLAG"
      } >> "$LOG"
      log -t tee-watchdog "TEESimulator is not running; cold reboot required" 2>/dev/null
      alerted=1
    fi
  else
    alerted=0
  fi
  sleep 30
done
