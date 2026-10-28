# Windows x86-64 / WSL2 实验移植

这是上游 [AVD_Rooted_Integrity](https://github.com/tanishmeh/AVD_Rooted_Integrity) 的独立工作副本，基于上游提交 `2b9e1051cc6903522f0397b240d40c1c09f744a4`。目标是复现当前 Windows x86-64 + Ubuntu 22.04 WSL2 上的 Root Android 模拟器，而不是宣称已经通过 Google Play Integrity。

当前验证配置：Android 36 Google Play x86_64 系统镜像 revision 7，Pixel 9 Pro XL AVD，6.6.66 自定义内核，KernelSU-Next 3.2.0、SUSFS 2.1.0、ReZygisk 1.0.0、PlayIntegrityFork v16、TEESimulator 3.2。内核配置来自该原厂镜像的 `/proc/config.gz`。不同镜像修订版可能有不兼容的内核模块；创建脚本只接受 revision 7。SDK 当前下载不保证将来仍是该版本。

## 当前结果和限制

- Android 启动、KVM、ADB Root、ReZygisk 和 TEESimulator 进程已在本机验证；项目的结构检查通过。
- **没有取得实际的 Play Integrity 判定**。结构检查通过、伪装属性一致或 TEESimulator 运行，都不等于 `MEETS_STRONG_INTEGRITY`。
- 原 SUSFS 模块的 `ksu_susfs` 是 ARM64 原生可执行文件，在 x86_64 系统中执行失败；不能假设 SUSFS 用户空间功能完整。
- WSLg 中模拟器右侧栏可能无法点击，Windows 与模拟器的复制粘贴也未解决。Windows 原生窗口方案尚未实现。
- 网络必须分别验证；当前环境曾能访问百度和 Google 连通性检测地址，但 Google 主站及认证状态接口连接失败。
- 项目脚本按上游要求在模拟器内将 keybox 设为 **0644**，同一设备上的其他进程可能读取其中的私钥。只在隔离的测试设备中使用；不要提交、分享或在聊天中粘贴 keybox。
- 不提供 keybox，也没有确认它是否有效或被撤销。不要在运行中的生产设备或其他用户 AVD 上运行安装脚本。

## 准备环境

需要 Windows x86-64、WSL2 Ubuntu 22.04、足够的磁盘空间（Docker 数据盘所在的磁盘首次构建至少预留 20 GB，项目所在盘也需要空间）、Docker Desktop 的 Linux 引擎、Windows Git、WSL 中 Java 17、curl、unzip。Docker 默认数据盘可能在 C 盘，即使项目在 F 盘也会消耗 C 盘。Docker 和 Git 需要访问源码上游。内核构建从 Windows PowerShell 执行；模拟器运行在 WSL。

### 1. 安装 Windows 工具

这部分目前需要使用者自行安装，**不是一键自动安装**：

1. 在 Windows 设置或固件中确认硬件虚拟化可用。按照 [微软 WSL 安装说明](https://learn.microsoft.com/windows/wsl/install) 安装 WSL2 和 Ubuntu 22.04；例如在管理员 PowerShell 中运行 `wsl --install -d Ubuntu-22.04`，如系统提示请重启，首次启动 Ubuntu 时创建 Linux 用户。用 `wsl -l -v` 检查发行版版本为 2。
2. 安装并启动 [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/)，启用 Linux/WSL2 引擎；确保 `docker info` 可用。首次创建编译镜像可能需要下载几 GB。
3. 安装 [Git for Windows](https://git-scm.com/install/windows)，在 PowerShell 中确认 `git --version` 可用。
4. 在 GitHub 获得此私有仓库的访问权限，然后克隆。拥有私有仓库链接并不自动意味着有访问权限：

   ```powershell
   cd F:\test
   git clone https://github.com/ATLord/avd-rooted-integrity-x86.git
   cd avd-rooted-integrity-x86
   ```

   这里 `F:\test` 只是示例，可选择自己的工作目录；克隆时根据 GitHub 提示完成认证。若项目位于 F 盘，Ubuntu 中的对应路径通常以 `/mnt/f/` 开头。

### 2. 安装 Ubuntu 依赖与 Android SDK

在 WSL 的 Ubuntu 中安装依赖（如果尚未安装）：

```bash
sudo apt update
sudo apt install -y openjdk-17-jre-headless curl unzip git
```

以下 WSL 命令假设项目克隆到 `F:\test\avd-rooted-integrity-x86`；换目录时请相应修改路径。

```bash
cd /mnt/f/test/avd-rooted-integrity-x86
bash x86/scripts/install-sdk.sh
```

SDK 安装脚本使用 Google 官方命令行工具并校验 SHA-256；许可协议由使用者在提示中自行阅读和接受。

### 3. 启用 KVM

KVM 需要可用的嵌套虚拟化。在 Windows PowerShell 中加载模块（本例发行版名是 `Ubuntu-22.04`）：

```powershell
wsl -d Ubuntu-22.04 -u root -- sh -c 'modprobe kvm_intel && chgrp kvm /dev/kvm && chmod 660 /dev/kvm'
$WslUser = (wsl -d Ubuntu-22.04 -- id -un).Trim()
wsl -d Ubuntu-22.04 -u root -- usermod -aG kvm $WslUser
```

第二行读取 Ubuntu 默认用户的用户名；退出并重新进入 WSL 后组权限生效。AMD 主机需要根据实际环境使用 `kvm_amd`。这些 `/dev/kvm` 权限可能在 WSL 重启后需要重新设置；不要对不支持嵌套虚拟化的环境假定 KVM 可用。

## 构建和创建模拟器

在 Windows PowerShell 中：

```powershell
cd F:\test\avd-rooted-integrity-x86
.\x86\build.ps1
```

首次会下载源码并编译，产物是 `x86/out/bzImage-x86_64`。源码保存在专用 Docker volume `avd-integrity-x86-sources`，与原先的临时 volume 分开。构建脚本锁定 SUSFS、KernelSU、AOSP 和 Wild 补丁版本；容器镜像基于 Ubuntu 24.04 软件源，因此不同构建时间的编译器包版本可能不同，不保证二进制哈希相同。脚本检查 BTF 配置以保证模块结构所需的选项没有被自动关闭。不要在不可信的内核或模块上依赖此实验性的模块版本检查绕过。

在 WSL 中：

```bash
cd /mnt/f/test/avd-rooted-integrity-x86
bash x86/scripts/create-avd.sh
bash x86/scripts/doctor.sh
bash x86/scripts/start.sh
```

创建脚本拒绝覆盖同名 AVD；如已有 AVD，请先确认它确实是需要使用的设备。启动脚本使用端口 5554、不加载快照和上述自定义内核，并在开机后尝试连接 `VirtWifi`；图形界面依赖 WSLg。请在安装或重启前先同步模拟器数据，避免强制结束导致写入丢失。

## 模块和项目配置

模拟器正常开机后，在另一个 WSL 终端运行：

```bash
cd /mnt/f/test/avd-rooted-integrity-x86
bash x86/scripts/install-modules.sh
```

脚本从项目列出的第三方版本下载文件并核对本次已验证的 SHA-256。它先安装 KernelSU 管理器；如果 Shell 还没有 Root，打开管理器，在 **Superuser → Shell** 启用 Superuser，然后重跑命令。模块安装后重启 Android，等待完全开机。

将自己的 keybox 保存到安全的本机位置，然后：

```bash
bash x86/scripts/configure-device.sh /mnt/f/keybox.xml
# 使用模拟器内重启或 adb reboot；不要重启 keymint、keystore2 或 TEESimulator 服务
bash x86/scripts/check-device.sh
bash x86/scripts/check-network.sh
```

配置脚本直接读取你指定的 keybox，并把它写入模拟器；不会把它复制到项目目录，原始文件也不会被删除。模拟器内的 keybox 不会随本项目版本库分发。请勿把真实 keybox 放进 Docker 构建上下文或提交到 Git。

安装模块、配置脚本和实际 Play Integrity 检查会改动测试 AVD；本项目仅针对指定测试 AVD。`check-device.sh` 输出的上游检查可能以零退出码报告失败，需要查看每项结果；它不会生成 Google 的认证判定，也不会证明 keybox 有效。

## 本机保留的文件

`x86/out/`、`x86/downloads/` 和 `x86/cache/` 都被 Git 忽略。当前工作区中的产物和下载包可以复用，但复制或提交项目时默认不会包含它们；新机器应按上述步骤重新构建、下载。可用 `KERNEL`、`ANDROID_SDK_ROOT`、`AVD_NAME` 和 `ANDROID_SERIAL` 覆盖对应设置；启动脚本固定端口 5554。
