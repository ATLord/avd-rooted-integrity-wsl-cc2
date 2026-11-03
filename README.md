# AVD Rooted Integrity：WSL2 / x86 / ARM

在 **Windows（WSL2）、Linux 或 Apple Silicon Mac** 上，用一个带自定义内核的 Android 模拟器（AVD）模拟 Root 后的 Pixel 设备，并尝试让它通过 Google Play Integrity。

本项目改自 [tanishmeh/AVD_Rooted_Integrity](https://github.com/tanishmeh/AVD_Rooted_Integrity)（只支持 Apple Silicon 的 arm64）。在此基础上：

- 新增 **Windows x86-64（WSL2）** 流程，Intel 和 AMD 电脑都已从零部署验证；
- 保留上游的 **macOS arm64** 流程，功能不删减；
- 修复了验证脚本会给出错误结论等问题（见 [CHANGELOG](CHANGELOG.md)）。

> **这是开发和测试工具，部署成功不等于 Play Integrity 通过。**
> 作者在 Intel 本机上做过真实检测，Basic / Device / Strong 均为 **Failed**；AMD 虚拟机只取得网络错误，没有结论。结构检查全绿、TEESimulator 在运行，都不能证明服务端会认可。
> 项目**不提供 keybox**，需要你自己准备有权使用的文件，并且不验证它是否有效或已被撤销。

## 1. 先确认你的机器能不能用

Google 只提供 x86_64 和 Apple Silicon 的 Android 模拟器，**没有** Linux ARM64 和 Windows on ARM 版本。

| 你的机器 | 能否使用 | 怎么做 |
| --- | --- | --- |
| Windows，Intel 或 AMD CPU | ✅ | 看下面第 3 节，约 11 步 |
| Linux，Intel 或 AMD CPU | ⚠️ 未验证，没有单独写文档 | `x86/scripts/` 里的 SDK、AVD、启动、模块、诊断脚本不依赖 Windows，理论上可用；但内核构建只提供了 PowerShell 入口 `build.ps1`，需要你照着它的 `docker` 命令自己执行。`install-xserver.sh`、`start-x11.sh` 是 Windows 专用，Linux 用系统自带的 X 即可 |
| macOS，Apple Silicon（M 系列） | ✅ | 看第 4 节 |
| 骁龙笔记本（Windows on ARM）、Linux ARM64 | ❌ | 没有官方模拟器，本项目无法运行 |

**硬件和软件要求（Windows）：**

| 项目 | 要求 |
| --- | --- |
| CPU | 64 位 Intel 或 AMD，固件里已开启虚拟化（VT-x / AMD-V）。如果 Windows 本身跑在虚拟机里，宿主机还要开启嵌套虚拟化 |
| 内存 | 建议 16 GB 及以上；12 GB 的虚拟机有成功记录，但需要额外调整 |
| 磁盘 | Docker 数据盘至少剩 20 GB（`build.ps1` 会检查，低于就拒绝构建）。这只是构建前的门槛，不是总量：SDK、系统镜像（约 2 GB）、Ubuntu、Docker 和模拟器数据都要额外占空间，请给每个阶段留足余量。把项目放在别的盘，并不会让 Docker 和 Ubuntu 的数据也搬过去 |
| 软件 | WSL2 + Ubuntu 22.04、Docker Desktop（Linux 引擎）、Git for Windows |
| 网络 | 能访问 GitHub、Google（SDK 与系统镜像）。国内网络需要 Windows 侧的 TUN/VPN，见 [网络说明](docs/WINDOWS-NETWORK.zh-CN.md) |
| 其他 | 自备 `keybox.xml`（见 [keybox 教程](docs/KEYBOX.zh-CN.md)） |

## 2. 先读这两条（会浪费几天的坑）

1. **绝对不要手动重启 `keymint`、`keystore2`、`TEESimulator`。** 手动重启会让 TEESimulator 从正确的 GENERATE 模式掉进 PATCH 模式，Play Integrity 随之返回空结果。**要让任何改动生效，或要从丢失状态恢复，只能整机冷重启。**
2. **绝对不要运行 `autopif`。** 它会把固定好的 Pixel 9 配置换成别的机型，指纹对不上，验证就失败。

## 3. Windows 安装步骤

命令前的标签说明在哪里执行：**[PowerShell]** 是 Windows PowerShell，**[Ubuntu]** 是 WSL 里的 Ubuntu 终端（在 PowerShell 里输入 `wsl -d Ubuntu-22.04` 进入）。两种终端的命令不能混用。

下面用 `C:\avd-work` 作为示例目录，换成别的盘时要同步修改 `/mnt/c/...` 路径。

### 3.1 安装基础软件（只做一次）

1. **[PowerShell，管理员]** 安装 WSL2 和 Ubuntu 22.04，提示重启就重启，首次进入 Ubuntu 时创建 Linux 用户：
   ```powershell
   wsl --install -d Ubuntu-22.04
   wsl -l -v          # Ubuntu-22.04 的 VERSION 应为 2
   ```
2. 安装并启动 [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/)，确认 `docker info` 能正常输出。
3. 安装 [Git for Windows](https://git-scm.com/install/windows)，确认 `git --version` 可用。

### 3.2 下载项目

4. **[PowerShell]** 这是私有仓库，第一次克隆时通常会弹出 GitHub 登录窗口，用有权限的账号登录；没有权限会返回 404 或 403。`core.autocrlf=false` 不能省，否则脚本的换行会被改坏，容器里执行会失败：
   ```powershell
   New-Item -ItemType Directory -Force C:\avd-work | Out-Null
   cd C:\avd-work
   git -c core.autocrlf=false clone https://github.com/ATLord/avd-rooted-integrity-wsl-cc.git
   cd avd-rooted-integrity-wsl-cc
   ```

### 3.3 准备 Ubuntu 环境

5. **[Ubuntu]** 安装依赖、Android SDK 和显示组件。SDK 安装过程中会让你阅读并接受 Google 的许可协议；系统镜像约 2 GB，需要一些时间：
   ```bash
   sudo apt update
   sudo apt install -y openjdk-17-jre-headless curl unzip git python3 libpulse0 libxi6 libxkbfile1 libsm6 libice6 p7zip-full xauth x11-utils
   cd /mnt/c/avd-work/avd-rooted-integrity-wsl-cc
   bash x86/scripts/install-sdk.sh
   bash x86/scripts/install-xserver.sh
   ```
6. **[Ubuntu]** 开启 KVM（硬件加速）。Intel 用 `kvm_intel`，AMD 把第一条命令里的模块名换成 `kvm_amd`。执行完 **退出并重新进入 Ubuntu**，用户组才生效：
   ```bash
   sudo modprobe kvm_intel
   sudo usermod -aG kvm "$USER"
   sudo chgrp kvm /dev/kvm
   sudo chmod 660 /dev/kvm
   ```
   重新进入后检查，应看到 `KVM ... is installed and usable`：
   ```bash
   "$HOME/Android/Sdk/emulator/emulator" -accel-check
   ```
   > WSL 每次重启后 `/dev/kvm` 可能消失，启动前如果提示 KVM 不可用，重新执行这几条即可。`start.sh` 的提示会按你的 CPU 给出正确的命令。

### 3.4 编译内核并创建模拟器

7. **[PowerShell]** 编译自定义内核，第一次要下载源码并编译，耗时较长，取决于网络和 CPU。产物是 `x86\out\bzImage-x86_64`：
   ```powershell
   cd C:\avd-work\avd-rooted-integrity-wsl-cc
   .\x86\build.ps1
   ```
8. **[Ubuntu]** 创建模拟器并启动。`doctor.sh` 会逐项检查环境，出现 `FAIL` 的项要先处理。保持这个终端打开，关掉模拟器后显示服务会自动退出：
   ```bash
   cd /mnt/c/avd-work/avd-rooted-integrity-wsl-cc
   bash x86/scripts/create-avd.sh
   bash x86/scripts/doctor.sh
   bash x86/scripts/start-x11.sh
   ```

### 3.5 Root、模块和 keybox

9. **[另开一个 Ubuntu 终端]** 等模拟器完全开机后安装模块。脚本会校验下载文件的 SHA-256，自动取得 ADB Shell Root，不需要在 KernelSU 管理器里手动授权：
   ```bash
   cd /mnt/c/avd-work/avd-rooted-integrity-wsl-cc
   bash x86/scripts/install-modules.sh
   ```
10. **冷重启一次**，让模块生效：
    ```bash
    "$HOME/Android/Sdk/platform-tools/adb" -s emulator-5554 emu kill
    # 等模拟器窗口关闭、原来那个终端里 start-x11.sh 退出后，在那个终端再执行：
    bash x86/scripts/start-x11.sh
    ```
11. **[另一个 Ubuntu 终端]** 配置你自己的 keybox（路径换成你的文件位置，Windows 的 `C:\keys\keybox.xml` 对应 `/mnt/c/keys/keybox.xml`），然后再冷重启一次，方法同上：
    ```bash
    bash x86/scripts/configure-device.sh /mnt/c/keys/keybox.xml
    ```

### 3.6 检查结果

开机完成并且 Wi-Fi 显示连接到 `VirtWifi` 后：

```bash
bash x86/scripts/check-device.sh      # Root、网络、结构检查
bash x86/scripts/check-network.sh     # Wi-Fi、DNS、HTTPS 探测
```

这两个脚本会逐项打印结果，**需要你自己看每一项**，退出码不能单独代表全部成功。它们也不会给出 Google 的认证判定，真实结果要用实际的 Play Integrity 检测应用另行验证。

## 4. macOS Apple Silicon（上游流程）

此流程和上游完全一致，用 arm64 内核，需要先用 Android Studio 装好带 Google Play 的 Pixel 系统镜像，并创建 AVD，默认 AVD 名是 `Pixel_9_Pro_XL`，用 `AVD=你的名字 ./scripts/start_avd.sh` 可以改。完整步骤见 [docs/REPRODUCTION.md](docs/REPRODUCTION.md)，大致如下：

```bash
# 1. 编译内核（Docker，约 10 GB，5 到 25 分钟）。macOS 必须用命名卷，原因见 kernel-build/README.md
cd kernel-build && docker build -t kbuild . && \
  docker run --rm -v "$PWD":/work -v kbuild-sources:/work/sources -w /work kbuild ./scripts/build-all.sh && cd ..

# 2. 放入你自己的 keybox（已被 .gitignore，不会被提交）
cp /path/to/your/keybox.xml device/data_adb/tricky_store/keybox.xml

# 3. 用自定义内核冷启动 AVD
./scripts/start_avd.sh

# 4. 安装 Root 模块（见 device/modules.md），然后推送配置
./scripts/install-device-setup.sh

# 5. 冷重启，再验证
./scripts/verify-integrity.sh --trigger
```

## 5. 遇到问题

| 现象 | 看哪里 |
| --- | --- |
| KVM 不可用 | 重新执行第 3.3 节第 6 步 |
| Docker 构建失败、磁盘不足、拉镜像超时 | [完整指南 · 常见问题](docs/GUIDE.zh-CN.md#常见问题) |
| X 窗口连不上（VcXsrv） | [完整指南 · VcXsrv 无法从 WSL 连接](docs/GUIDE.zh-CN.md#vcxsrv-无法从-wsl-连接) |
| 刚开机 Wi-Fi 关闭、网络不通 | [Windows 网络说明](docs/WINDOWS-NETWORK.zh-CN.md) |
| Google 登录显示 Something went wrong、没有 GSF android_id | [完整指南 · 常见问题](docs/GUIDE.zh-CN.md#常见问题) |
| 验证结果为空，或日志显示 `patched certificate chain` | 说明进了 PATCH 模式，**冷重启**，见 [INTEGRITY_CHAIN](docs/INTEGRITY_CHAIN.md) |
| 想弄懂每一层为什么这样做 | [docs/INTEGRITY_CHAIN.md](docs/INTEGRITY_CHAIN.md) |

## 6. 常用环境变量

| 变量 | 作用 | 默认值 |
| --- | --- | --- |
| `ANDROID_SDK_ROOT` | Android SDK 位置 | `~/Android/Sdk` |
| `AVD_NAME` | 模拟器名称 | `Pixel_9_Pro_XL_x86` |
| `ANDROID_SERIAL` | 模拟器序列号，端口从中推导 | `emulator-5554` |
| `KERNEL` | 自定义内核路径 | `x86/out/bzImage-x86_64` |
| `AVD_KEEP_PROXY=1` | 把当前 shell 的代理变量传给模拟器 | 默认清除代理，走 Windows 路由 |
| `AVD_X11_DISPLAY` | VcXsrv 显示编号 | `3` |
| `AVD_X11_HOST` | 手动指定 Windows 主机地址 | 自动判断，NAT 用默认网关，镜像网络用 `127.0.0.1` |
| `AVD_XSERVER` | VcXsrv 可执行文件路径 | `x86/xserver/vcxsrv.exe` |

TEESimulator 看门狗默认只告警、不自动拉起；需要恢复上游的自动拉起行为，在设备上执行 `su -c touch /data/adb/avd-fake/tee-watchdog-relaunch`。原因见 [CHANGELOG](CHANGELOG.md)。

## 7. 项目结构

| 路径 | 作用 |
| --- | --- |
| `x86/` | Windows / x86-64 流程：内核构建、SDK 与 AVD 创建、启动、模块安装、诊断脚本 |
| `kernel-build/` | 上游的 arm64 内核构建；x86 构建也复用其中的源码获取和补丁脚本 |
| `device/` | 推送到模拟器 `/data/adb` 的配置和脚本，x86 与 ARM 共用 |
| `scripts/` | `start_avd.sh`（ARM 启动）、`install-device-setup.sh`、`verify-integrity.sh`（两种架构共用） |
| `tests/`、`x86/tests/` | 不依赖真机的脚本测试（用假的 adb 和 emulator） |
| `docs/` | 完整指南、安装手册、keybox 教程、网络说明、完整性原理、功能清单 |

每个入口适用于哪种平台，见 [docs/FEATURES.md](docs/FEATURES.md)。

## 8. 安全提示

- 本项目让 **ADB Shell 获得 Root**（启动参数 `kernelsu.allow_shell=1`），不自动授予普通应用 Root。只用于你自己的测试模拟器。
- keybox 在模拟器里的权限是 **0644**，这是 TEESimulator 能读取它的前提，但同一模拟器上的其他进程也能读到私钥。不要在含有个人数据的设备上使用，也不要提交、分享或粘贴 keybox。
- 下载的模块、APK、SDK 都校验了固定的 SHA-256，内核源码固定在指定提交，不要为了省事跳过校验。
- 不要在别人的 AVD 或运行中的生产设备上运行安装脚本。

## 9. 当前验证状态

- 已在 Intel 本机和 AMD Windows 虚拟机上从零完成：SDK、自定义内核、AVD、Root、四个模块、keybox 配置和结构检查。验证配置：Android 36 Google Play x86_64 系统镜像 **revision 7**（创建脚本只接受这个版本）、内核 6.6.66、KernelSU-Next 3.2.0、SUSFS 2.1.0、ReZygisk 1.0.0、PlayIntegrityFork v16、TEESimulator 3.2。
- 真实 Play Integrity 检测：Intel 本机 Basic / Device / Strong 均 Failed；AMD 虚拟机返回网络错误，无结论。
- 已知限制：SUSFS 模块自带的 `ksu_susfs` 是 ARM64 可执行文件，在 x86_64 上无法运行，所以 SUSFS 用户空间规则不完整生效；`uname` 仍会暴露内核构建标识；Google 账号登录和 Android 应用内的剪贴板尚未验证。
- **最近一轮改进**（验证脚本修复、Wi-Fi 与 check-in 时序、看门狗等，见 [CHANGELOG](CHANGELOG.md)）只通过了不依赖真机的脚本测试，**还没有在真机上复测**。macOS 流程同样没有在 Mac 上重跑。

## 10. 来源与许可

基于 [tanishmeh/AVD_Rooted_Integrity](https://github.com/tanishmeh/AVD_Rooted_Integrity)，上游英文说明保留在 [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md)。**上游仓库没有声明许可证**，因此本仓库也没有附带许可证，请保持私有；如要公开分发，先联系上游作者取得许可。
