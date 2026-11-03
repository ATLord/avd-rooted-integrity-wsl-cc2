#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
server="${AVD_XSERVER:-$root/x86/xserver/vcxsrv.exe}"
control="$root/x86/scripts/xserver-control.ps1"
display_number="${AVD_X11_DISPLAY:-3}"
[[ "$display_number" =~ ^[0-9]+$ && "$display_number" -le 999 ]] || { echo 'Invalid X display number.' >&2; exit 1; }
for command in xauth xdpyinfo mcookie wslpath powershell.exe; do
  command -v "$command" >/dev/null || { echo "Missing dependency: $command" >&2; exit 1; }
done
[[ -f "$server" ]] || { echo 'Run bash x86/scripts/install-xserver.sh first.' >&2; exit 1; }
# NAT (default) networking: Windows is the default gateway. Mirrored networking
# (.wslconfig networkingMode=mirrored): the default gateway is the real LAN
# router, and Windows listeners are reached on localhost instead.
# AVD_X11_HOST overrides the detection.
networking_mode="$(wslinfo --networking-mode 2>/dev/null | tr -d '\r' || true)"
if [[ -n "${AVD_X11_HOST:-}" ]]; then
  host_ip="$AVD_X11_HOST"
elif [[ "$networking_mode" == mirrored ]]; then
  host_ip=127.0.0.1
else
  host_ip="$(ip route show default | awk 'NR==1 {print $3}')"
fi
[[ -n "$host_ip" ]] || { echo 'Unable to determine the Windows host address.' >&2; exit 1; }
runtime="$(mktemp -d "${TMPDIR:-/tmp}/avd-x11.XXXXXX")"
server_pid=''
cleanup() {
  if [[ -n "$server_pid" ]]; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$control")" -Action Stop -Executable "$(wslpath -w "$server")" -ProcessId "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$runtime"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
auth="$runtime/Xauthority"
touch "$auth"
chmod 600 "$auth"
xauth -f "$auth" add "$host_ip:$display_number" MIT-MAGIC-COOKIE-1 "$(mcookie)"
server_pid="$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$control")" -Action Start -Executable "$(wslpath -w "$server")" -Authority "$(wslpath -w "$auth")" -DisplayNumber "$display_number" | tr -d '\r')"
[[ "$server_pid" =~ ^[0-9]+$ ]] || { echo 'Failed to start X server.' >&2; exit 1; }
export DISPLAY="$host_ip:$display_number" XAUTHORITY="$auth" QT_QPA_PLATFORM=xcb
ready=0
for ((i=0; i<30; i++)); do
  if timeout 2 xdpyinfo >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[[ "$ready" -eq 1 ]] || { echo 'X server could not be reached from WSL; check its authorization and Windows firewall access.' >&2; exit 1; }
bash "$root/x86/scripts/start.sh"
