#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
target="$root/x86/xserver"
url='https://github.com/marchaesen/vcxsrv/releases/download/21.1.16.1/vcxsrv-64.21.1.16.1.installer.noadmin.exe'
digest='dea6c7d67d3d15b4ed45c87b63a83c88f4aceaaef5425630f0e97a0bad70d620'
for command in curl sha256sum 7z xauth xdpyinfo wslpath; do
  command -v "$command" >/dev/null || { echo "Missing dependency: $command" >&2; exit 1; }
done
if [[ -f "$target/vcxsrv.exe" ]]; then echo "X server already installed: $target"; exit 0; fi
[[ ! -e "$target" ]] || { echo "Incomplete directory: $target" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fL --retry 2 --connect-timeout 15 -o "$tmp/vcxsrv.exe" "$url"
echo "$digest  $tmp/vcxsrv.exe" | sha256sum -c -
mkdir -p "$target"
7z x -y "-o$target" "$tmp/vcxsrv.exe" -bso0 -bsp0
[[ -f "$target/vcxsrv.exe" && -d "$target/xkbdata" ]] || { echo 'Extraction incomplete.' >&2; exit 1; }
echo "X server installed: $target"
