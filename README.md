# Windows x86-64 Android 模拟器：自动 Root 版

本项目是在 Windows x86-64 电脑上，通过 WSL2 Ubuntu 构建并运行 Root Android 模拟器的实验方案。它基于上游 [AVD_Rooted_Integrity](https://github.com/tanishmeh/AVD_Rooted_Integrity) 的提交 `2b9e1051cc6903522f0397b240d40c1c09f744a4`，针对 x86-64 系统镜像和内核进行了适配。上游英文说明保留在 [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md)；上游的 ARM64 使用方法及完整性结果不能直接视为本项目的结果。

> **请先阅读：** 本项目仅支持通过 WSL2 运行，尚非一键安装。WSL、Docker、Git、Java 和 KVM 需要人工准备；真实 keybox 需要使用者自行提供。已在同一台电脑的全新 Ubuntu 22.04 实例中测试构建、启动、自动 ADB Shell Root、模块和 XML 配置；尚未在另一台干净电脑上验证。

独立仓库：[avd-rooted-integrity-windows-autoroot](https://github.com/ATLord/avd-rooted-integrity-windows-autoroot)（私有仓库，需获得访问权限）。仓库名称保留原样，实际使用方式为 Windows 上的 WSL2 Ubuntu。

本版本在启动测试 AVD 时启用 KernelSU 的 `allow_shell` 参数，并由模块安装脚本自动启动管理器并取得 ADB Shell Root，无需在管理器中手动授权。此设置授予 ADB Shell Root；不自动授予普通应用 Root。请仅用于自己的测试 AVD。

如果原版模拟器已经打开，先正常关闭它，再从本版本运行 `start.sh`；仅在 Android 内重启无法给已经运行的模拟器追加新的启动参数。

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

- 在本机独立的全新 Ubuntu 实例中，从仓库克隆、安装 SDK revision 7、编译内核、启动 Android、自动 ADB Root、安装模块及配置 XML 已验证；Android 重启后 Root、XML 和 VirtWifi 自动连接也已检查。模块下载使用了针对本机网络临时配置的代理，其他网络环境需自行确认。
- 没有验证本 WSL 版本在新电脑上的 Play Integrity 判定。结构检查通过、伪装属性一致或 TEESimulator 运行，都不等于 `MEETS_STRONG_INTEGRITY`。
- 原 SUSFS 模块的 `ksu_susfs` 是 ARM64 原生可执行文件，在 x86_64 系统中执行失败；不能假设 SUSFS 用户空间功能完整。
- WSLg 中模拟器右侧栏可能无法点击，Windows 与模拟器的复制粘贴也可能异常，目前尚未在 WSL 方案中解决。
- 网络必须分别验证；当前环境曾能访问百度和 Google 连通性检测地址，但 Google 主站及认证状态接口连接失败。
- 项目脚本按上游要求在模拟器内将 keybox 设为 **0644**，同一设备上的其他进程可能读取其中的私钥。只在隔离的测试设备中使用；不要提交、分享或在聊天中粘贴 keybox。
- 不提供 keybox，也没有确认它是否有效或被撤销。不要在运行中的生产设备或其他用户 AVD 上运行安装脚本。

## 准备环境

| 前置条件 | 说明 |
| --- | --- |
| 电脑与虚拟化 | Windows x86-64；CPU 虚拟化已开启。若 Windows 本身运行在虚拟机中，还需要宿主机提供嵌套虚拟化。 |
| WSL | WSL2、Ubuntu 22.04、可用的 `/dev/kvm` 和 WSLg 图形支持。模拟器运行在 WSL 中。 |
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
   git clone https://github.com/ATLord/avd-rooted-integrity-windows-autoroot.git avd-rooted-integrity-autoroot
   cd avd-rooted-integrity-autoroot
   ```

   原仓库不包含本版本的自动 Root 修改；如果使用其他目录，请替换后续命令中的路径。

### 2. 安装 Ubuntu 依赖与 Android SDK

在 WSL 的 Ubuntu 中安装依赖（如果尚未安装）：

```bash
sudo apt update
sudo apt install -y openjdk-17-jre-headless curl unzip git python3 libpulse0 libxi6 libxkbfile1 libsm6 libice6
```

以下 WSL 命令假设项目位于 `F:\test\avd-rooted-integrity-autoroot`；换目录时请相应修改路径。

```bash
cd /mnt/f/test/avd-rooted-integrity-autoroot
bash x86/scripts/install-sdk.sh
```

SDK 安装脚本使用 Google 官方命令行工具并校验 SHA-256；许可协议由使用者在提示中自行阅读和接受。

### 3. 启用 KVM

KVM 需要可用的嵌套虚拟化。在 Ubuntu 终端中运行（以下适用于 Intel 主机）：

```bash
sudo modprobe kvm_intel
sudo usermod -aG kvm "$USER"
sudo chgrp kvm /dev/kvm
sudo chmod 660 /dev/kvm
```

退出并重新进入 Ubuntu 终端后组权限生效。AMD 主机需要根据实际环境使用 `kvm_amd`。这些 `/dev/kvm` 权限可能在 WSL 重启后需要重新设置；不要对不支持嵌套虚拟化的环境假定 KVM 可用。

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
bash x86/scripts/start.sh
```

创建脚本拒绝覆盖同名 AVD；如已有 AVD，请先确认它确实是需要使用的设备。启动脚本使用端口 5554、不加载快照和上述自定义内核，并在首次开机及 Android 重启后尝试连接 `VirtWifi`；图形界面依赖 WSLg。请在安装或重启前先同步模拟器数据，避免强制结束导致写入丢失。

## 模块和项目配置

模拟器正常开机后，在另一个 WSL 终端运行：

```bash
cd /mnt/f/test/avd-rooted-integrity-autoroot
bash x86/scripts/install-modules.sh
```

脚本从项目列出的第三方版本下载文件并核对 SHA-256，自动安装并启动 KernelSU 管理器，确认 ADB Shell Root 后安装模块。不需要手动进入管理器授权。必须使用本版本的 `start.sh` 启动测试 AVD，才能启用自动授权。模块安装后重启 Android，等待完全开机。

将自己的 keybox 保存到安全的本机位置，然后：

```bash
bash x86/scripts/configure-device.sh /mnt/f/keybox.xml
# 使用模拟器内重启或下面的 adb 命令；不要重启 keymint、keystore2 或 TEESimulator 服务
"$HOME/Android/Sdk/platform-tools/adb" -s emulator-5554 reboot
# 等待 Android 完全启动后再检查
bash x86/scripts/check-device.sh
bash x86/scripts/check-network.sh
```

配置脚本直接读取你指定的 keybox，并把它写入模拟器；不会把它复制到项目目录，原始文件也不会被删除。Windows 路径与 Ubuntu 路径的对应关系、文件准备及验证步骤详见 [keybox.xml 配置教程](docs/KEYBOX.zh-CN.md)。模拟器内的 keybox 不会随本项目版本库分发。

安装模块、配置脚本和实际 Play Integrity 检查会改动测试 AVD；本项目仅针对指定测试 AVD。`check-device.sh` 输出的上游检查可能以零退出码报告失败，需要查看每项结果；它不会生成 Google 的认证判定，也不会证明 keybox 有效。

## 日常启动、关闭和诊断

以后使用时，先确保 Docker 不用于构建也可以正常启动模拟器；但 WSL/KVM 必须可用。打开 Ubuntu，进入项目目录：

```bash
cd /mnt/f/test/avd-rooted-integrity-autoroot
bash x86/scripts/doctor.sh
bash x86/scripts/start.sh
```

`start.sh` 默认使用端口 5554。窗口启动后保持该终端运行；它会尝试在设备首次开机及 Android 重启后连接 `VirtWifi`，本机已验证连接，其他机器的连接仍取决于系统和网络状态。可在另一个 Ubuntu 终端运行 `bash x86/scripts/check-network.sh` 检查联网情况。关闭前在 Android 系统中保存工作；需要重启设备时优先使用 Android 内的重启或上面的 `adb reboot`，以避免未完成的写入丢失。

## 常见问题

### 提示 KVM 不可用

运行 `bash x86/scripts/doctor.sh` 并检查 `/dev/kvm` 是否可读写。确认宿主机虚拟化和 WSL 嵌套虚拟化可用，再按上面的步骤加载对应 CPU 的 KVM 模块。WSL 重启后设备权限可能需要重新设置。

### Docker 构建失败或磁盘空间不足

先确认 Docker Desktop 已启动，`docker info` 能返回结果。`build.ps1` 会尝试检查默认 Docker 数据盘所在分区是否有至少 20 GB 空间；如果 Docker 数据盘使用了其他位置，请自行检查对应分区。不要为了清理空间随意删除其他项目的 Docker volume。

### 已有同名 AVD 或端口被占用

创建脚本不会覆盖已有的 `Pixel_9_Pro_XL_x86`。先确认该设备是否为本项目创建的测试设备，再决定继续使用或选择其他 AVD 名称。启动脚本固定使用端口 5554；安装和诊断脚本默认使用 `emulator-5554`。更改 `AVD_NAME` 或 `ANDROID_SERIAL` 后，需要确保目标一致。

### Wi-Fi、Google 服务或剪贴板异常

先运行 `bash x86/scripts/check-network.sh`。能访问某个网站不代表所有 Google 服务均可访问；DNS、代理和宿主机网络均可能影响结果。若 Wi-Fi 未自动连接，可在模拟器内打开 Wi-Fi 并选择 `VirtWifi`。WSLg 下右侧栏不可点击以及 Windows 与模拟器之间复制粘贴异常，目前仍是已知限制。

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
| `x86/scripts/install-modules.sh`、`configure-device.sh` | 安装模块并配置使用者提供的 keybox |
| `x86/scripts/doctor.sh`、`check-device.sh`、`check-network.sh` | 环境、设备和网络诊断 |
| `kernel-build/`、`device/`、`scripts/` | 保留的上游构建与设备配置 |
| `docs/UPSTREAM_README.md` | 上游英文说明 |

## 本机保留的文件

`x86/out/`、`x86/downloads/` 和 `x86/cache/` 都被 Git 忽略。当前工作区中的产物和下载包可以复用，但复制或提交项目时默认不会包含它们；新机器应按上述步骤重新构建、下载。可用 `KERNEL`、`ANDROID_SDK_ROOT`、`AVD_NAME` 和 `ANDROID_SERIAL` 覆盖对应设置；启动脚本固定端口 5554。
