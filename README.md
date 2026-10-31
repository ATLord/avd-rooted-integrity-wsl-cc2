# WSL x86-64 Android 模拟器：Windows 网络接管版

> **Windows 网络接管版：** 本分支包含完整项目。模拟器使用 Windows 的网络路由和用户自行启用的 TUN/VPN，不自动配置 HTTP 代理或开启 VPN。配置、测试结果与限制参见 [Windows 网络接管说明](docs/WINDOWS-NETWORK.zh-CN.md)。原界面修复版的 master 分支保持不变。

本项目是在 Windows x86-64 电脑上，通过 WSL2 Ubuntu 构建并运行 Root Android 模拟器的实验方案。它基于上游 [AVD_Rooted_Integrity](https://github.com/tanishmeh/AVD_Rooted_Integrity) 的提交 `2b9e1051cc6903522f0397b240d40c1c09f744a4`，针对 x86-64 系统镜像和内核进行了适配。上游英文说明保留在 [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md)；上游的 ARM64 使用方法及完整性结果不能直接视为本项目的结果。

> **请先阅读：** 本项目仅支持通过 WSL2 运行，尚非一键安装。WSL、Docker、Git、Java 和 KVM 需要人工准备；真实 keybox 需要使用者自行提供。后续在 Intel 本机与 AMD Windows 虚拟机上均完成从零部署、内核构建、启动、Root、模块和 keybox 结构检查。本机实际 Play Integrity 检测的 Basic/Device/Strong 均为 Failed；远程仅取得网络错误，没有服务端 verdict。部署成功不等于完整性认证通过，Google 账号登录仍未验证。

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

- 本节依据安装记录 `INSTALL-EXPERIENCE.md`（2026-10-30 至 31 日，测试 HEAD `c2bd686`）补充，覆盖 Intel 本机和 AMD Windows 虚拟机两次从零部署。两台均完成 SDK revision 7、自定义内核、AVD、Root、四个模块、keybox 配置和结构检查；处理均在环境层，未修改受 Git 跟踪的源码。本机因网络问题使用等价容器命令构建，远程直接执行 `build.ps1` 成功。较早 `26016f0` 测试曾复用构建缓存，不能与后续记录混为一谈。
- 本机环境：Windows `10.0.26300.9711`、Intel Core Ultra 5 225H、31.5 GB 内存、WSL 2.7.8、Ubuntu 22.04.5、Docker Engine 29.9.2 / Desktop 4.97.0、Java 17、Emulator 37.2.13.0、VcXsrv 21.1.16.1。远程环境：Windows 11 Pro `28000.3231` 虚拟机、AMD Ryzen 9 9950X3D（分配 4 核 / 8 线程）、12 GB 内存、WSL 3.0.3、Ubuntu 22.04、Docker Engine 29.8.2。均验证 KVM 可用；版本记录不保证其他组合兼容。
- 本机开启 Windows TUN 后 Google 网络打通；远程后期 Windows 访问 Google 返回 200，但 Android VirtWifi 未稳定取得 IP。必须分别验证 Windows、WSL、Android 的 Wi-Fi、DNS 和 HTTPS，Windows 可访问不代表 Android 可用，也不证明所有流量都经过 VPN。
- Google 添加账号曾显示 `Something went wrong`。Play 服务随后自动更新，重新进入登录流程后暂未复现原错误，但未确认账号登录成功；网站可访问不代表登录服务正常。
- 后续本机已捕获 `integrity.api.key.alias` 的 GENERATE 活动（记录为 13 次 GENERATE、0 次 PATCH），真实检测 Basic/Device/Strong **均 Failed**；仅凭这些证据不能确定是哪项配置导致拒绝。远程 Securify 返回 `Network Error (-3)`，没有 verdict，不能归类为完整性通过或失败。结构检查通过、属性一致或 TEESimulator 运行，都不等于 `MEETS_STRONG_INTEGRITY`。
- 原 SUSFS 模块的 `ksu_susfs` 是 ARM64 原生可执行文件；本次在 x86_64 上复现 `unsupported e_shentsize` 错误。模块安装成功不代表 SUSFS 用户空间功能完整。
- 较早的本机测试曾由用户确认右侧栏和 Windows↔Android 双向文本复制粘贴可用；本次只验证了 VcXsrv 启动，未重新验证这两项交互。直接使用 `start.sh` 的 WSLg 窗口仍可能出现原问题。
- 后续记录中 `uname` 仍显示 `6.6.66-g41978cd56da8-dirty`，Securify 仍能发现 Root 痕迹；结构检查没有覆盖所有检测器。Google 账号登录、Android 应用层剪贴板也仍未验证。
- 项目脚本按上游要求在模拟器内将 keybox 设为 **0644**，同一设备上的其他进程可能读取其中的私钥。只在隔离的测试设备中使用；不要提交、分享或在聊天中粘贴 keybox。
- 不提供 keybox，也没有确认它是否有效或被撤销。不要在运行中的生产设备或其他用户 AVD 上运行安装脚本。

| 后续验证项 | Intel 本机 | AMD Windows 虚拟机 |
| --- | --- | --- |
| 从零安装、内核构建、AVD 启动 | 完成 | 完成 |
| Root、四个模块、keybox 结构检查 | 通过 | 通过 |
| 显示 | 正常 | 正常 |
| VirtWifi / Google 网络 | 开启 TUN 后可用 | 曾连接；后续 Wi-Fi 未稳定取得 IP |
| Play Integrity | Basic / Device / Strong 均 Failed | `Network Error (-3)`，无 verdict |

## 准备环境

| 前置条件 | 说明 |
| --- | --- |
| 电脑与虚拟化 | Windows x86-64；CPU 虚拟化已开启。若 Windows 本身运行在虚拟机中，还需要宿主机提供嵌套虚拟化。 |
| WSL | WSL2、Ubuntu 22.04、可用的 `/dev/kvm` 和 WSL 与 Windows 之间的网络通信。模拟器运行在 WSL 中。 |
| 构建与图形依赖 | Windows 上安装 Git 和使用 Linux 引擎的 Docker Desktop；Ubuntu 中安装 Java 17、curl、unzip、git、python3 和模拟器的音频/X11 库（见下方命令）。 |
| 空间 | 首次内核构建前，Docker 数据盘至少留出 20 GB；Ubuntu、SDK、模拟器数据和项目还需要额外空间。项目放在 F 盘不代表 Docker 不占 C 盘。 |
| 内存 | 建议主机至少 16 GB。12 GB 虚拟机有成功记录，但需要调整 WSL/AVD 内存并在构建完成后退出 Docker Desktop，详见下方内存排错。 |
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
   git -c core.autocrlf=false clone --branch windows-network-integration https://github.com/ATLord/avd-rooted-integrity-wsl-ui.git avd-rooted-integrity-autoroot
   cd avd-rooted-integrity-autoroot
   ```

   原仓库不包含本版本的自动 Root 修改；如果使用其他目录，请替换后续命令中的路径。

   私有仓库在新机器或新 Windows 用户下需要先通过 Git Credential Manager 登录，或在已安装 GitHub CLI 时运行 `gh auth login`。匿名访问可能返回 404，权限不足也可能返回 403。不要把访问令牌写进克隆 URL。`core.autocrlf=false` 用于保留 Shell 脚本的 LF 换行，避免容器执行 CRLF 文件失败。

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

退出并重新进入 Ubuntu 终端后组权限生效。AMD 主机将第一条命令替换为 `sudo modprobe kvm_amd`，其余步骤相同；固件应开启 SVM/AMD-V，Windows 虚拟机的宿主还应提供嵌套虚拟化。Intel/AMD 使用同一个 x86_64 内核产物，无需按 CPU 厂商修改项目代码。

WSL 重启后不仅权限可能变化，KVM 模块和 `/dev/kvm` 也可能消失；启动前重新加载对应模块、设置权限并验证。当前 `start.sh` 的报错提示写死了 `kvm_intel`，AMD 用户应以本节为准使用 `kvm_amd`。远程测试中 `/etc/wsl.conf` 的 KVM 启动命令未生效，不能把写入启动配置当作已修复的证据。

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

远程测试在 `wsl --shutdown` 后曾丢失设备节点。应在启动用的 Ubuntu 会话中重新加载模块，然后立即启动，例如 AMD 主机：

```bash
sudo modprobe kvm_amd
sudo chgrp kvm /dev/kvm
sudo chmod 660 /dev/kvm
"${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/emulator/emulator" -accel-check
# 确认 KVM usable 后，在同一会话的项目根目录启动：
bash x86/scripts/start-x11.sh
```

### 内存不足、System UI ANR 或嵌套虚拟化下启动很慢

12 GB Windows 虚拟机中曾出现 System UI 卡死和 ANR。有效的环境调整是：内核构建完成后退出 Docker Desktop，将 WSL 内存上限设为 8 GB、swap 设为 4 GB，并将 AVD 内存从 2 GB 调整为 4 GB。WSL 限额包含其中运行的模拟器，不能把 Docker、WSL、AVD 的数字简单当作互不相关的物理内存相加；提高 AVD 内存也要求给 Windows 留出余量。此配置是该机器的成功记录，不是所有 12 GB 主机的通用保证。

在 Windows 的 `%USERPROFILE%\.wslconfig` 中合并以下设置，保留已有的其他选项：

```ini
[wsl2]
memory=8GB
swap=4GB
```

先正常关闭模拟器并保存所有 WSL 工作，再在 PowerShell 执行 `wsl --shutdown` 使设置生效；这会停止所有 WSL 发行版。重新进入 Ubuntu 后按上文恢复 KVM。模拟器关闭时，编辑该 Linux 用户的 `~/.android/avd/Pixel_9_Pro_XL_x86.avd/config.ini`（自定义 `ANDROID_AVD_HOME` 时以实际路径为准），将已有内存项设为 `hw.ramSize=4G`；这是 AVD 配置，不是项目源码，也无需重建同名 AVD。

远程首次成功启动约 179 秒，后续启动曾到 250 秒。出现 `Emulator Running in Nested Virtualization` 提示时在模拟器窗口确认；短暂 ANR 可选择 Wait 并观察，但持续卡死仍应检查内存与加速能力。等待 `sys.boot_completed=1` 后还要继续确认 Wi-Fi。

### Docker 构建失败或磁盘空间不足

先确认 Docker Desktop 已启动，`docker info` 能返回结果。`build.ps1` 会尝试检查默认 Docker 数据盘所在分区是否有至少 20 GB 空间；如果 Docker 数据盘使用了其他位置，请自行检查对应分区。不要为了清理空间随意删除其他项目的 Docker volume。

### Docker Hub 授权超时、TLS handshake timeout 或 connectex

本机拉取 `ubuntu:24.04` 时曾出现 `auth.docker.io` 异常解析和连接失败；安装记录中改用 Docker Desktop 手动代理后拉取成功。Windows 浏览器或系统代理可用，不足以证明 Docker 的镜像拉取链路正常；`--net=host` 只影响容器运行时网络，不会修复拉取阶段的授权超时。

在 Docker Desktop **Settings → Resources → Proxies** 中，把 **Docker Desktop proxy** 设为手动配置，HTTP 和 HTTPS 均填本机实际可用的 HTTP 代理。例如代理监听 `127.0.0.1:10808` 时，两项均为 `http://127.0.0.1:10808`；按实际端口替换并应用设置，保持代理客户端运行。不要把 VLESS 等节点 URI 填进 HTTP 代理栏。Docker Desktop 应在其设置中配置代理，不能依靠 `daemon.json` 代替，参见 [Docker 官方代理说明](https://docs.docker.com/engine/daemon/proxy/)。

先在 PowerShell 验证，再重跑构建：

```powershell
docker info
docker pull ubuntu:24.04
```

记录中的直接修改 `settings-store.json` 是当时的环境处理方式；该文件字段随 Desktop 版本变化，日常优先使用设置界面。若仍失败，分别排查 DNS、代理出口和 Docker 的生效配置，不要仅凭 TLS 超时断定某个节点失效。

### AOSP 下载慢、KernelSU early EOF 或 CRLF 错误

本机 AOSP 直连曾只有约 70 KB/s；改用 TUNA AOSP 镜像准备同一版本源码后完成构建。当前脚本没有镜像源参数，手动准备缓存属于环境修复；必须保持脚本要求的 tag 和 commit，不能改用分支最新版本：

| 源码 | 必须匹配的提交 |
| --- | --- |
| AOSP common kernel | `41978cd56da8895f9859f257e9c36405c234a4ea`（tag `android15-6.6-2025-02_r19`） |
| KernelSU-Next | `5a4a71874caaad06aa126f761c93391de1d32361` |

AOSP tag 是 annotated tag，应比较 `git rev-parse 'android15-6.6-2025-02_r19^{commit}'` 与上述提交，而非把 tag 对象的 SHA 当作提交。缓存中的内核还需能通过脚本的 tag 检查，否则会被重新下载。仅把浅克隆 HEAD 指向该提交而不保留 tag，并不足以复用缓存。

KernelSU 的 `kernel/setup.sh` 会在内核树里再次 clone；即使外层已有 `sources/kernelsu`，仍可能在这一步遇到 `early EOF`。安装记录通过容器内临时 Git `url.file:///ksu-src.insteadOf` 将 `https://github.com/KernelSU-Next/KernelSU-Next` 映射到已校验的本地只读副本解决。该副本应保留 Git 元数据、匹配固定提交并使用 LF 换行；Windows `core.autocrlf` 产生的 CRLF 曾导致 `set: -: invalid option`，需要用 `git -c core.autocrlf=false clone ...` 重新准备相应副本。主仓库的克隆选项不会自动控制所有后续独立克隆。

### 已有构建镜像仍重复下载编译依赖

记录中镜像 digest 变化造成 apt 层缓存未命中，重复安装 clang/llvm。先让 `build.ps1` 完成镜像与 SUSFS 缓存准备；如果两者已经成功、只是重试容器内编译，可以在项目根目录的 PowerShell 直接执行脚本最后一步的等价命令，复用现有源码 volume：

```powershell
$ProjectPath = (Get-Location).Path
$SusfsPath = Join-Path $ProjectPath 'x86\cache\susfs.git'
docker run --rm -v "${ProjectPath}:/work" `
  -v avd-integrity-x86-sources:/work/kernel-build/sources `
  -v "${SusfsPath}:/input/susfs.git:ro" `
  -w /work avd-integrity-x86-build bash /work/x86/scripts/build-in-container.sh
```

这不是首次构建替代方案，不会创建缺失镜像或准备 SUSFS 缓存；单独使用也不会自动添加上一节的 KernelSU 本地映射。需要该映射时，另行只读挂载已校验的副本并向容器传入临时 Git 配置。保留源码固定提交与校验，不要为了命中缓存跳过它们。

### GitHub Release TLS 失败，如何复用模块下载

远程安装曾报 `SSL routines::unexpected eof` 或 Windows `schannel: failed to receive handshake`。可在网络正常的机器用同一提交的 `install-modules.sh --download-only` 获取并校验文件，再复制到目标项目的 `x86/downloads/`，文件名必须为：

```text
KernelSU.apk
susfs.zip
rezygisk.zip
pif.zip
tee.zip
```

压缩传输时先在目标目录解压；仅放一个 `modules.zip` 不会被脚本识别。目标机器重新运行 `bash x86/scripts/install-modules.sh --download-only` 验证 SHA-256，再在 AVD 正常运行时不带该参数安装。脚本只复用哈希匹配的文件，缺失或不匹配会重新下载；不要重命名其他版本冒充固定版本，也不要绕过校验。KernelSU APK 是管理器，四个 ZIP 才是模块。

### VcXsrv 无法从 WSL 连接

遇到 `X server could not be reached from WSL`，检查 Windows 防火墙规则匹配的是否为**当前实际运行的** `vcxsrv.exe` 路径。本机曾存在针对新路径的显式 Block，而 Allow 规则只匹配旧安装路径；仅添加另一条 Allow 不保证能覆盖显式 Block。

如需放行，在管理员 PowerShell 中创建针对实际程序路径的入站规则，并按自己的 WSL 网络范围限制来源，例如：

```powershell
$XServerPath = (Resolve-Path '.\x86\xserver\vcxsrv.exe').Path
New-NetFirewallRule -DisplayName 'AVD VcXsrv X11' `
  -Direction Inbound -Program $XServerPath -Action Allow -Profile Any
```

运行前先进入项目根目录；已有显式 Block 时应检查并调整冲突规则。管理员/UAC 确认由使用者在 Windows 界面完成，不需要关闭防火墙或关闭 X11 认证。如果已有经过允许的 VcXsrv 安装，也可通过项目支持的覆盖变量指定其 WSL 路径：

```bash
AVD_XSERVER=/mnt/c/tools/vcxsrv/vcxsrv.exe bash x86/scripts/start-x11.sh
```

示例路径需换成实际存在且来源可信的程序；项目移动目录后应重新检查按路径匹配的防火墙规则。

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

后续本机记录将同样的条件检查写入 `/usr/local/sbin/wsl-interop-fix.sh`，通过 `/etc/wsl.conf` 的 `[boot] command=` 在启动时恢复；这是可选的 WSL 环境配置，不是项目自动安装的功能。需要持久化时应保留现有 boot 命令，并在重启后再次验证 `interop-ok`，不能直接覆盖其他启动任务。

### 刚开机 Wi-Fi 关闭或网络不可达

`sys.boot_completed=1` 不表示 Wi-Fi 已就绪。本次早期日志有 `Failed to create STA iface`；模块安装脚本部署的 `10-wlan0-virtwifi.sh` 会等开机完成后再等待 25 秒，创建 `wlan0` 并有界重试连接。等待服务完成后，本次自动连接成功。单独运行主机端 `start.sh` 的连接尝试不能替代设备端接口创建服务。

先确认已安装模块并重启，再查看状态和开机服务日志（Ubuntu 终端）：

```bash
adb="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/platform-tools/adb"
"$adb" -s emulator-5554 shell cmd wifi status
"$adb" -s emulator-5554 shell "su -c 'tail -n 30 /data/adb/wlan0-setup.log'"
```

等待出现 `Wifi is connected to "VirtWifi"`。若重试结束仍失败，检查服务是否安装、日志中的接口创建错误及宿主机网络，而非无限等待或关闭防火墙。安装模块前，服务日志可能尚不存在。

AMD 虚拟机曾先连接到 `10.0.2.15/24`，后续冷启动出现 `wlan0` 为 DOWN/NO-CARRIER，未稳定获得 IP；手动拉起接口也未形成稳定解决方案。应同时检查 `adb -s emulator-5554 shell ip addr show wlan0` 与上述服务日志；不要把历史连接成功或 Windows 网络恢复当作当前 Android 已联网。该问题仍待查。

### HTTPS 检查返回 126 或网站访问结果不一致

`check-network.sh` 的 HTTPS 探测依赖 ADB Shell Root 和 `/data/adb/ksu/bin/busybox`。本次模块安装前运行返回 126，不能解释为网站不可达。先确认 `su -c id` 返回 `uid=0`、BusyBox 存在且可执行，再运行网络检查；安装模块并完成开机服务后，本次四个 HTTPS 地址均成功。

逐项阅读输出，脚本退出码 0 不代表所有探测通过。WSL 的“localhost 代理未映射到 NAT”警告也不直接证明断网；本次出现该警告时仍可下载。Windows 系统 HTTP 代理与 TUN 接管不同，应分别检查 Windows、WSL、Android 的连接情况，参见 [Windows 网络接管说明](docs/WINDOWS-NETWORK.zh-CN.md)。

后续本机测试中，仅监听 Windows `127.0.0.1` 的 HTTP 代理可用，但 WSL NAT 无法直接使用该监听地址，WSL→Windows 的连接还受到防火墙限制；开启 TUN 后 Google 请求才打通。代理客户端显示 TUN 已启用或存在 Up 网卡，仍不足以证明出口可用。远程曾出现 DNS 返回 `198.18.x.x`（fake-IP）并伴随 HTTPS `Connection reset by peer`；fake-IP 地址本身不能证明故障，应结合出口、路由和实际 HTTPS 请求检查。

记录中的 `Google Server Unavailable (-12)`、`Network Error (-3)` 属于当次请求错误，不能当作 Basic/Device/Strong verdict，也不能据此认定 keybox 或 TEE 有问题。修复网络后需重新实际请求；本机网络恢复后取得的三项 Failed 才是本次完整性判定结果。

### Google 登录显示 Something went wrong

本次前台为 Google Play 服务的 `auth.uiflows.addaccount.ErrorActivity`。当时 VirtWifi 和所测 Google 网址可用；Play 服务随后更新至 26.42.31，重新打开 Play 商店并点击 Sign in 后进入登录流程，短时观察未再出现原错误，但**未确认登录成功**。更新发生在错误之后，无法证明它是最初错误的原因或彻底解决办法。

遇到此提示，先确认网络和 Play 服务更新状态，更新完成后重新进入登录流程并观察；若仍失败，检查该次登录的相关日志。不要仅凭通用错误页认定是 keybox、网络或 Play Integrity 问题。网址返回 200/204 不等于账号登录及设备认证通过，分享日志时请去除账号、令牌和密钥内容。

### 完整性触发后仍没有请求记录

较早测试运行 `scripts/verify-integrity.sh --trigger` 等待 30 秒后输出 `No integrity.api.key.alias activity captured`。这表示该检查没有捕获到目标活动，既不是通过结果，也不是明确的服务端拒绝；需要实际发起请求并查看服务端判定。后续本机实际请求已捕获 GENERATE 活动，三项 verdict 仍均为 Failed，说明捕获到请求也不代表认证通过。

实际脚本路径是项目根目录下的 `scripts/verify-integrity.sh`，不是 `x86/scripts/verify-integrity.sh`。`--trigger` 会清除测试 AVD 的 Play Store 数据、相关 DroidGuard 文件和 logcat，再启动 Play Store，不能作为日常只读诊断或保证有效的检测按钮。普通结构检查使用 `bash x86/scripts/check-device.sh` 即可。

### Android 16 提示 No GSF android_id

当前 `scripts/verify-integrity.sh` 查询 `com.google.android.gsf/databases/gservices.db`；安装记录中 Android 16 的数据库实际在 `com.google.android.gms/databases/gservices.db`，因此旧路径可能产生假阴性。仅凭 `No GSF android_id` 不能断定设备没有 ID、未注册或完整性失败。这里记录脚本的诊断局限，未修改脚本，也不需要为消除提示清除 Google 数据或复制数据库。查看日志时不要公开设备 ID、账号或令牌。

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
