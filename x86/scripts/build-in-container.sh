#!/usr/bin/env bash
set -euo pipefail
root=/work
src="$root/kernel-build/sources"
kernel="$src/kernel"
susfs_commit=2df41de789026a6422521606402576507c687435
wild_commit=c78291aeb0dca025f21e6b197e0aa4fde42e065d
mkdir -p "$src"
# The host supplies an exact-commit mirror because full GitLab clones can hang.
if [[ ! -d "$src/susfs/.git" ]]; then
  git clone -b pinned /input/susfs.git "$src/susfs"
fi
[[ "$(git -C "$src/susfs" rev-parse HEAD)" = "$susfs_commit" ]] || { echo 'Wrong SUSFS commit' >&2; exit 1; }
if [[ ! -d "$src/wild-patches/.git" ]]; then
  git init "$src/wild-patches"
  git -C "$src/wild-patches" fetch --depth=1 https://github.com/WildKernels/kernel_patches.git "$wild_commit"
  git -C "$src/wild-patches" checkout --detach FETCH_HEAD
fi
[[ "$(git -C "$src/wild-patches" rev-parse HEAD)" = "$wild_commit" ]] || { echo 'Wrong Wild patches commit' >&2; exit 1; }
bash "$root/kernel-build/scripts/fetch-sources.sh"
[[ "$(git -C "$kernel" rev-parse HEAD)" = '41978cd56da8895f9859f257e9c36405c234a4ea' ]] || { echo 'AOSP tag does not resolve to the validated commit.' >&2; exit 1; }
[[ "$(git -C "$src/kernelsu" rev-parse HEAD)" = '5a4a71874caaad06aa126f761c93391de1d32361' ]] || { echo 'Wrong KernelSU commit.' >&2; exit 1; }
if [[ ! -f "$kernel/.avd-patches-applied" ]]; then
  bash "$root/kernel-build/scripts/apply-patches.sh"
fi
python3 "$root/x86/scripts/patch-kernelsu.py" "$kernel"
python3 "$root/kernel-build/scripts/check-boot-hooks.py" "$kernel"
cd "$kernel"
export ARCH=x86_64 LLVM=1 LLVM_IAS=1 CC=clang HOSTCC=clang
export CCACHE_DIR="$src/.ccache"
cp "$root/x86/config/android36-google-play-x86_64-r07.config" .config
scripts/config --enable KSU --enable KSU_SUSFS --enable KSU_SUSFS_SUS_PATH \
  --enable KSU_SUSFS_SUS_MOUNT --enable KSU_SUSFS_SUS_KSTAT --enable KSU_SUSFS_SUS_MAP \
  --enable KSU_SUSFS_OPEN_REDIRECT --enable KSU_SUSFS_SPOOF_UNAME \
  --enable KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG --enable KSU_SUSFS_ENABLE_LOG \
  --enable KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
make olddefconfig
for setting in CONFIG_KSU=y CONFIG_KSU_SUSFS=y CONFIG_DEBUG_INFO_BTF=y CONFIG_DEBUG_INFO_BTF_MODULES=y; do
  grep -qx "$setting" .config || { echo "Missing required setting: $setting" >&2; exit 1; }
done
make -j "${JOBS:-8}" bzImage
mkdir -p "$root/x86/out"
cp arch/x86/boot/bzImage "$root/x86/out/bzImage-x86_64"
sha256sum "$root/x86/out/bzImage-x86_64"
