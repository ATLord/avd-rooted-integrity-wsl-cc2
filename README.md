# WSL x86-64 Android 模拟器：Windows 网络接管版

> **Windows 网络接管版：** 本分支包含完整项目。模拟器使用 Windows 的网络路由和用户自行启用的 TUN/VPN，不自动配置 HTTP 代理或开启 VPN。配置、测试结果与限制参见 [Windows 网络接管说明](docs/WINDOWS-NETWORK.zh-CN.md)。原界面修复版的 master 分支保持不变。

本项目是在 Windows x86-64 电脑上，通过 WSL2 Ubuntu 构建并运行 Root Android 模拟器的实验方案。它基于上游 [AVD_Rooted_Integrity](https://github.com/tanishmeh/AVD_Rooted_Integrity) 的提交 `2b9e1051cc6903522f0397b240d40c1c09f744a4`，针对 x86-64 系统镜像和内核进行了适配。上游英文说明保留在 [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md)；上游的 ARM64 使用方法及完整性结果不能直接视为本项目的结果。

> **请先阅读：** 本项目仅支持通过 WSL2 运行，尚非一键安装。WSL、Docker、Git、Java 和 KVM 需要人工准备；真实 keybox 需要使用者自行提供。2026-10-30 在本机新安装的 Ubuntu 22.04 中完成了部署与启动测试，但内核构建复用了已有 Docker 缓存。Google 账号登录和真实 Play Integrity 判定尚未验证成功，不能据此认定已在完全干净的电脑上完成全部功能验证。

本仓库是 [WSL 自动 Root 版](https://github.com/ATLord/avd-rooted-integrity-windows-autoroot) 的独立界面修复版，不改变原仓库。模拟器、Android 系统和内核仍运行在 WSL；窗口通过 Windows 上的 VcXsrv 显示。

本版本在启动测试 AVD 时启用 KernelSU 的 `allow_shell` 参数，并由模块安装脚本自动启动管理器并取得 ADB Shell Root，无需在管理器中手动授权。此设置授予 ADB Shell Root；不自动授予普通应用 Root。请仅用于自己的测试 AVD。

如果原版模拟器已经打开，先正常关闭它，再从本版本运行 `start-x11.sh`；仅在 Android 内重启无法给已经运行的模拟器追加新的启动参数。

首次安装建议阅读 **[从零安装操作手册（详细版）](docs/INSTALLATION.zh-CN.md)**，其中区分了 Windows PowerShell 和 Ubuntu 命令，并给出每步检查方法及常见错误处理。

配置 XML 请阅读 **[keybox.xml 配置教程](docs/KEYBOX.zh-CN.md)**。项目不会提供或自动生成有效 keybox。

## 目录

- [当前结果和限制](#当前结果和限制)
- [环境准备与安装](#准备环境)
- [构建和创建模拟器](#构建和创建模拟器)
- [模块和项目配置](#模块和项目配置)
- [日常启动、关闭和诊断](#日常启动关闭和诊断)
- [常见问题](#常见问题)
- [目录与脚本说明](#目录与脚本说明)

当前验证配置：Android 36 Google Play x86_64 系统镜像 revision 7，Pixel 9 Pro XL AVD，6.6.66 自定义内核，KernelSU-Next 3.2.0、SUSFS 2.1.0、ReZygisk 1.0.0、PlayIntegrityFork v16、TEESimulator 3.2。内核配置来自该原厂镜像的 `/proc/config.gz`。不同镜像修订版可能有不兼容的内核模块；创建脚本只接受 revision 7。SDK 当前下载不保证将来仍是该版本。

## 当前结果和限制

- 2026-10-30 本机测试基于本分支提交 `26016f0`：新安装 Ubuntu、克隆仓库、安装 SDK revision 7、构建内核、启动 Android、自动 ADB Shell Root、安装模块和配置 XML 均完成。配置后冷启动验证了 Root、XML 权限、TEESimulator 进程和 VirtWifi 连接；构建复用了已有 Docker 镜像层及源码/对象缓存，未验证无缓存完整构建。
- 本次环境：Windows `10.0.26300.9711`、Intel Core Ultra 5 225H、WSL 2.7.8、Ubuntu 22.04.5、Docker 29.9.2、Java 17、Emulator 37.2.13.0、VcXsrv 21.1.16.1。KVM 加速自检通过。以上是测试版本记录，不保证其他组合兼容。
- 网络必须分别验证。本次等待开机服务完成后，百度、Google 主站和认证状态接口返回 HTTP 200，Google 连通性检测返回 204；此前环境曾有部分 Google 地址访问失败。本次未切换测试 TUN 开关，不能证明所有流量均被 VPN 接管。
- Google 添加账号曾显示 `Something went wrong`。Play 服务随后自动更新，重新进入登录流程后暂未复现原错误，但未确认账号登录成功；网站可访问不代表登录服务正常。
- 本次运行完整性触发脚本后未捕获到 `integrity.api.key.alias` 请求活动，未取得真实 Play Integrity 服务端判定。结构检查通过、伪装属性一致或 TEESimulator 运行，都不等于 `MEETS_STRONG_INTEGRITY`。
- 原 SUSFS 模块的 `ksu_susfs` 是 ARM64 原生可执行文件；本次在 x86_64 上复现 `unsupported e_shentsize` 错误。模块安装成功不代表 SUSFS 用户空间功能完整。
- 较早的本机测试曾由用户确认右侧栏和 Windows↔Android 双向文本复制粘贴可用；本次只验证了 VcXsrv 启动，未重新验证这两项交互。直接使用 `start.sh` 的 WSLg 窗口仍可能出现原问题。
- 项目脚本按上游要求在模拟器内将 keybox 设为 **0644**，同一设备上的其他进程可能读取其中的私钥。只在隔离的测试设备中使用；不要提交、分享或在聊天中粘贴 keybox。
- 不提供 keybox，也没有确认它是否有效或被撤销。不要在运行中的生产设备或其他用户 AVD 上运行安装脚本。

## 准备环境

| 前置条件 | 说明 |
| --- | --- |
| 电脑与虚拟化 | Windows x86-64；CPU 虚拟化已开启。若 Windows 本身运行在虚拟机中，还需要宿主机提供嵌套虚拟化。 |
| WSL | WSL2、Ubuntu 22.04、可用的 `/dev/kvm` 和 WSL 与 Windows 之间的网络通信。模拟器运行在 WSL 中。 |
| 构建与图形依赖 | Windows 上安装 Git 和使用 Linux 引擎的 Docker Desktop；Ubuntu 中安装 Java 17、curl、unzip、git、python3 和模拟器的音频/X11 库（见下方命令）。 |
| 空间 | 首次内核构建前，Docker 数据盘至少留出 20 GB；Ubuntu、SDK、模拟器数据和项目还需要额外空间。项目放在 F 盘不代表 Docker 不占 C 盘。 |
| 网络 | 需要能访问 GitHub、Google Android SDK 和项目使用的源码、模块发布源；Google Play 服务连通性也要单独检查。 |
| XML | 自行准备有权使用的 `keybox.xml`；仓库不会提供真实文件。 |
| 版本与权限 | 需要该私有仓库的访问权限；当前内核仅与 Android 36 Google Play x86_64 系统镜像 revision 7 验证过。 |

内核构建命令在 Windows PowerShell 执行；SDK 安装、设备创建和启动命令在 Ubuntu 中执行。不同电脑的网络、虚拟化和镜像版本需要分别确认。

### 1. 安装 Windows 工具

这部分目前需要使用者自行安装，**不是一键自动安装**：

1. 在 Windows 设置或固件中确认硬件虚拟化可用。按照 [微软 WSL 安装说明](https://learn.microsoft.com/windows/wsl/install) 安装 WSL2 和 Ubuntu 22.04；例如在管理员 PowerShell 中运行 `wsl --install -d Ubuntu-22.04`，如系统提示请重启，首次启动 Ubuntu 时创建 Linux 用户。用 `wsl -l -v` 检查发行版版本为 2。
2. 安装并启动 [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/)，启用 Linux/WSL2 引擎；确保 `docker info` 可用。首次创建编译镜像可能需要下载几 GB。
3. 安装 [Git for Windows](https://git-scm.com/install/windows)，在 PowerShell 中确认 `git --version` 可用。
4. 获得私有仓库的访问权限，在 Windows PowerShell 克隆项目（以下目录是示例）：

   ```powershell
   New-Item -ItemType Directory -Force F:\test | Out-Null
   cd F:\test
   git clone --branch windows-network-integration https://github.com/ATLord/avd-rooted-integrity-wsl-ui.git avd-rooted-integrity-autoroot
   cd avd-rooted-integrity-autoroot
   ```

   原仓库不包含本版本的自动 Root 修改；如果使用其他目录，请替换后续命令中的路径。

### 2. 安装 Ubuntu 依赖与 Android SDK

先进入 **Ubuntu-22.04**，不要在 Docker Desktop 自用的 `docker-desktop` 发行版中安装 SDK。SDK、AVD 和日常启动应使用同一个 Linux 用户，否则默认的 `$HOME/Android/Sdk` 和 `$HOME/.android` 会指向不同位置。若使用专用用户，在 Windows PowerShell 中执行 `wsl -d Ubuntu-22.04 -u <Linux用户名>`；不要照抄尖括号占位符。

在 WSL 的 Ubuntu 中安装依赖（如果尚未安装）：

```bash
sudo apt update
sudo apt install -y openjdk-17-jre-headless curl unzip git python3 libpulse0 libxi6 libxkbfile1 libsm6 libice6 p7zip-full xauth x11-utils
```

以下 WSL 命令假设项目位于 `F:\test\avd-rooted-integrity-autoroot`；换目录时请相应修改路径。

```bash
cd /mnt/f/test/avd-rooted-integrity-autoroot
bash x86/scripts/install-sdk.sh
bash x86/scripts/install-xserver.sh
```

SDK 安装脚本使用 Google 官方命令行工具并校验 SHA-256；许可协议由使用者在提示中自行阅读和接受。显示组件脚本下载 VcXsrv 官方版本并校验 SHA-256，解压到被 Git 忽略的 `x86/xserver/`。

本次系统镜像压缩包约 1.92 GB，下载和解压需要时间。安装结束后再执行创建/诊断脚本，并确认镜像版本；不要跳过 revision 7 的兼容性检查：

```bash
grep '^Pkg.Revision=' "${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/system-images/android-36/google_apis_playstore/x86_64/source.properties"
# 预期：Pkg.Revision=7
```

### 3. 启用 KVM

KVM 需要可用的嵌套虚拟化。在 Ubuntu 终端中运行（以下适用于 Intel 主机）：

```bash
sudo modprobe kvm_intel
sudo usermod -aG kvm "$USER"
sudo chgrp kvm /dev/kvm
sudo chmod 660 /dev/kvm
```

退出并重新进入 Ubuntu 终端后组权限生效。AMD 主机需要根据实际环境使用 `kvm_amd`。这些 `/dev/kvm` 权限可能在 WSL 重启后需要重新设置；不要对不支持嵌套虚拟化的环境假定 KVM 可用。

SDK 安装完成后，以运行模拟器的普通用户检查实际加速能力：

```bash
"${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/emulator/emulator" -accel-check
```

本次返回 `KVM (version 12) is installed and usable`；仅有 `/dev/kvm` 文件或可读写权限，还不足以证明加速可用。

## 构建和创建模拟器

在 Windows PowerShell 中：

```powershell
cd F:\test\avd-rooted-integrity-autoroot
.\x86\build.ps1
```

首次会下载源码并编译，产物是 `x86/out/bzImage-x86_64`。源码保存在专用 Docker volume `avd-integrity-x86-sources`，与原先的临时 volume 分开。构建脚本锁定 SUSFS、KernelSU、AOSP 和 Wild 补丁版本；容器镜像基于 Ubuntu 24.04 软件源，因此不同构建时间的编译器包版本可能不同，不保证二进制哈希相同。脚本检查 BTF 配置以保证模块结构所需的选项没有被自动关闭。不要在不可信的内核或模块上依赖此实验性的模块版本检查绕过。

在 WSL 中：

```bash
cd /mnt/f/test/avd-rooted-integrity-autoroot
bash x86/scripts/create-avd.sh
bash x86/scripts/doctor.sh
bash x86/scripts/start-x11.sh
```

创建脚本拒绝覆盖同名 AVD；如已有 AVD，请先确认它确实是需要使用的设备。`start-x11.sh` 启动带独立认证的 VcXsrv，再调用 WSL 的 `start.sh`；模拟器端口为 5554，并在首次开机及 Android 重启后尝试连接 `VirtWifi`。保持启动终端打开，关闭模拟器后显示服务会随之退出。

## 模块和项目配置

模拟器正常开机后，在另一个 WSL 终端运行：

```bash
cd /mnt/f/test/avd-rooted-integrity-autoroot
bash x86/scripts/install-modules.sh
```

脚本从项目列出的第三方版本下载文件并核对 SHA-256，自动安装并启动 KernelSU 管理器，确认 ADB Shell Root 后安装模块，并安装 VirtWifi 开机服务。不需要手动进入管理器授权。`start-x11.sh` 会调用本版本的 `start.sh` 启用自动授权。可先运行 `bash x86/scripts/install-modules.sh --download-only` 单独验证下载；该选项不安装模块。

**模块安装后先冷启动一次，待模块生效再配置 XML。** 本机曾在 `adb reboot` 后出现模拟器进程退出，日志包含 `stop: Not implemented`；根因未确认。可按以下方式关闭并重新启动指定测试 AVD：

```bash
"${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/platform-tools/adb" -s emulator-5554 emu kill
# 等原模拟器窗口关闭、原 start-x11.sh 返回后，再在启动终端执行：
bash x86/scripts/start-x11.sh
```

保持启动终端运行，在另一个同用户的 Ubuntu 终端继续操作。等待 `sys.boot_completed` 为 `1`，并在网络测试前确认 VirtWifi 已连接。

将自己的 keybox 保存到安全的本机位置，然后：

```bash
bash x86/scripts/configure-device.sh /mnt/f/keybox.xml
```

配置完成后，再按上面的关闭/启动步骤冷启动一次。不要单独重启 keymint、keystore2 或 TEESimulator 服务。随后在另一个 Ubuntu 终端检查：

```bash
"${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/platform-tools/adb" -s emulator-5554 shell getprop sys.boot_completed
"${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/platform-tools/adb" -s emulator-5554 shell cmd wifi status
# boot_completed=1 且显示连接到 VirtWifi 后，再检查：
bash x86/scripts/check-device.sh
bash x86/scripts/check-network.sh
```

配置脚本直接读取你指定的 keybox，并把它写入模拟器；不会把它复制到项目目录，原始文件也不会被删除。Windows 路径与 Ubuntu 路径的对应关系、文件准备及验证步骤详见 [keybox.xml 配置教程](docs/KEYBOX.zh-CN.md)。模拟器内的 keybox 不会随本项目版本库分发。

安装模块、配置脚本和实际 Play Integrity 检查会改动测试 AVD；本项目仅针对指定测试 AVD。`check-device.sh` 输出的上游检查可能以零退出码报告失败，需要查看每项结果；它不会生成 Google 的认证判定，也不会证明 keybox 有效。

## 日常启动、关闭和诊断

内核构建完成后，日常启动模拟器不需要运行 Docker 构建；WSL/KVM 必须可用。使用安装 SDK 和创建 AVD 时的 Linux 用户打开 Ubuntu，进入项目目录：

```bash
cd /mnt/f/test/avd-rooted-integrity-autoroot
bash x86/scripts/doctor.sh
bash x86/scripts/start-x11.sh
```

`start-x11.sh` 默认使用 X 显示号 3 和模拟器端口 5554。窗口启动后保持终端运行；它会尝试在首次开机及 Android 重启后连接 `VirtWifi`。显示服务使用每次启动生成的 X11 认证，不使用关闭访问控制的 `-ac`。如果 X 端口被占用，可设置 `AVD_X11_DISPLAY` 为其他显示号；不同防火墙环境可能需要允许 WSL 连接该显示服务，不需要关闭防火墙。

## 常见问题

### 提示 KVM 不可用

运行 `bash x86/scripts/doctor.sh` 并检查 `/dev/kvm` 是否可读写。确认宿主机虚拟化和 WSL 嵌套虚拟化可用，再按上面的步骤加载对应 CPU 的 KVM 模块。WSL 重启后设备权限可能需要重新设置。

### Docker 构建失败或磁盘空间不足

先确认 Docker Desktop 已启动，`docker info` 能返回结果。`build.ps1` 会尝试检查默认 Docker 数据盘所在分区是否有至少 20 GB 空间；如果 Docker 数据盘使用了其他位置，请自行检查对应分区。不要为了清理空间随意删除其他项目的 Docker volume。

### 已有同名 AVD 或端口被占用

创建脚本不会覆盖已有的 `Pixel_9_Pro_XL_x86`。先确认该设备是否为本项目创建的测试设备，再决定继续使用或选择其他 AVD 名称。启动脚本固定使用端口 5554；安装和诊断脚本默认使用 `emulator-5554`。更改 `AVD_NAME` 或 `ANDROID_SERIAL` 后，需要确保目标一致。

### 创建时提示 devices.xml 加载失败

本次 `avdmanager` 提示系统镜像目录下 `Could not load devices .../devices.xml`，但仍创建了 AVD。检查 `emulator -list-avds`、生成的 AVD `config.ini` 中的 `hw.device.name=pixel_9_pro_xl` 和镜像路径，再运行 `doctor.sh` 和启动测试；本次这些检查及实际启动通过。原因未确认，不能把此报错一概视为无害，也不要为消除提示随意创建空 XML。

### powershell.exe 提示 Exec format error

`start-x11.sh` 需要从 WSL 调用 Windows PowerShell。本次失败时 `/proc/sys/fs/binfmt_misc/WSLInterop` 注册项缺失。在 **Ubuntu 终端**先检查：

```bash
cat /proc/sys/fs/binfmt_misc/WSLInterop
powershell.exe -NoProfile -Command 'Write-Output interop-ok'
```

仅当注册项缺失，且 `/proc/sys/fs/binfmt_misc/register` 已存在时，可尝试本次验证过的临时恢复：

```bash
if [ ! -e /proc/sys/fs/binfmt_misc/WSLInterop ] && [ -e /proc/sys/fs/binfmt_misc/register ]; then
  printf ':WSLInterop:M::MZ::/init:PF\n' | sudo tee /proc/sys/fs/binfmt_misc/register >/dev/null
fi
powershell.exe -NoProfile -Command 'Write-Output interop-ok'
```

确认输出 `interop-ok` 后再启动。这只恢复当前会话的注册，不保证 WSL 重启后仍有效；若注册项已存在但调用仍失败，应继续排查 WSL 互操作配置，不能反复写入注册项。未验证此办法能处理所有 `Exec format error`。

### 刚开机 Wi-Fi 关闭或网络不可达

`sys.boot_completed=1` 不表示 Wi-Fi 已就绪。本次早期日志有 `Failed to create STA iface`；模块安装脚本部署的 `10-wlan0-virtwifi.sh` 会等开机完成后再等待 25 秒，创建 `wlan0` 并有界重试连接。等待服务完成后，本次自动连接成功。单独运行主机端 `start.sh` 的连接尝试不能替代设备端接口创建服务。

先确认已安装模块并重启，再查看状态和开机服务日志（Ubuntu 终端）：

```bash
adb="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/platform-tools/adb"
"$adb" -s emulator-5554 shell cmd wifi status
"$adb" -s emulator-5554 shell "su -c 'tail -n 30 /data/adb/wlan0-setup.log'"
```

等待出现 `Wifi is connected to "VirtWifi"`。若重试结束仍失败，检查服务是否安装、日志中的接口创建错误及宿主机网络，而非无限等待或关闭防火墙。安装模块前，服务日志可能尚不存在。

### HTTPS 检查返回 126 或网站访问结果不一致

`check-network.sh` 的 HTTPS 探测依赖 ADB Shell Root 和 `/data/adb/ksu/bin/busybox`。本次模块安装前运行返回 126，不能解释为网站不可达。先确认 `su -c id` 返回 `uid=0`、BusyBox 存在且可执行，再运行网络检查；安装模块并完成开机服务后，本次四个 HTTPS 地址均成功。

逐项阅读输出，脚本退出码 0 不代表所有探测通过。WSL 的“localhost 代理未映射到 NAT”警告也不直接证明断网；本次出现该警告时仍可下载。Windows 系统 HTTP 代理与 TUN 接管不同，应分别检查 Windows、WSL、Android 的连接情况，参见 [Windows 网络接管说明](docs/WINDOWS-NETWORK.zh-CN.md)。

### Google 登录显示 Something went wrong

本次前台为 Google Play 服务的 `auth.uiflows.addaccount.ErrorActivity`。当时 VirtWifi 和所测 Google 网址可用；Play 服务随后更新至 26.42.31，重新打开 Play 商店并点击 Sign in 后进入登录流程，短时观察未再出现原错误，但**未确认登录成功**。更新发生在错误之后，无法证明它是最初错误的原因或彻底解决办法。

遇到此提示，先确认网络和 Play 服务更新状态，更新完成后重新进入登录流程并观察；若仍失败，检查该次登录的相关日志。不要仅凭通用错误页认定是 keybox、网络或 Play Integrity 问题。网址返回 200/204 不等于账号登录及设备认证通过，分享日志时请去除账号、令牌和密钥内容。

### 完整性触发后仍没有请求记录

本次 `verify-integrity.sh --trigger` 等待 30 秒后仍输出 `No integrity.api.key.alias activity captured`。这表示该检查没有捕获到目标活动，既不是通过结果，也不是明确的服务端拒绝；需要实际发起请求并查看服务端判定。该选项会清除测试 AVD 的 Play Store 数据、相关 DroidGuard 文件和 logcat，再启动 Play Store，不能作为日常只读诊断或保证有效的检测按钮。普通结构检查使用 `check-device.sh` 即可。

### 侧栏或剪贴板异常

确认通过 `start-x11.sh` 启动，并检查 VcXsrv 与 WSL 的连接及 X11 认证。按需允许对应显示服务的防火墙访问，不需要关闭 Windows 防火墙。本次未重新测试侧栏操作和双向剪贴板。

### SUSFS 报错或结构检查全绿

模块附带的 `ksu_susfs` 是 ARM64 可执行文件，当前 x86-64 模拟器不能直接运行；内核识别到 SUSFS 不表示全部用户空间规则已生效。项目的结构检查、TEESimulator 进程和 Root 状态也不等于真实的 Play Integrity 服务器判定。

### 如何安全处理 keybox

由使用者自行保管 keybox。仓库忽略真实 `keybox.xml`，配置命令从指定的本地路径直接读取。按上游方案写入测试模拟器后文件权限为 0644，设备上的其他进程可能读取私钥，因此不要在生产设备或包含敏感数据的设备上使用。项目不验证 keybox 是否有效或已撤销。

## 目录与脚本说明

| 路径 | 作用 |
| --- | --- |
| `x86/README.md` | 指向本中文使用说明的入口 |
| `x86/build.ps1` | Windows 上准备 Docker 构建环境并构建 x86 内核 |
| `x86/config/`、`x86/scripts/patch-kernelsu.py` | 已验证的原厂内核配置和 x86 兼容修改 |
| `x86/scripts/install-sdk.sh` | 下载并校验 Android 命令行工具，安装 SDK 组件 |
| `x86/scripts/create-avd.sh`、`start.sh` | 创建和启动测试模拟器 |
| `x86/scripts/install-xserver.sh`、`start-x11.sh` | 准备并启动用于窗口与剪贴板的显示服务 |
| `x86/scripts/install-modules.sh`、`configure-device.sh` | 安装模块并配置使用者提供的 keybox |
| `x86/scripts/doctor.sh`、`check-device.sh`、`check-network.sh` | 环境、设备和网络诊断 |
| `kernel-build/`、`device/`、`scripts/` | 保留的上游构建与设备配置 |
| `docs/UPSTREAM_README.md` | 上游英文说明 |

## 本机保留的文件

`x86/out/`、`x86/downloads/` 和 `x86/cache/` 都被 Git 忽略。当前工作区中的产物和下载包可以复用，但复制或提交项目时默认不会包含它们；新机器应按上述步骤重新构建、下载。可用 `KERNEL`、`ANDROID_SDK_ROOT`、`AVD_NAME` 和 `ANDROID_SERIAL` 覆盖对应设置；启动脚本固定端口 5554。
