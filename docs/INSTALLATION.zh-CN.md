# Windows x86-64 模拟器从零安装操作手册

> 本手册适用于 Windows 网络接管版：请克隆 `windows-network-integration` 分支。界面修复版在本机独立测试 AVD 中验证了侧栏和双向文本复制粘贴；尚未在另一台干净电脑上完成复现。网络配置及测试边界见 [Windows 网络接管说明](WINDOWS-NETWORK.zh-CN.md)。

本手册面向第一次在 Windows 电脑上部署本项目的使用者。按顺序执行，每一阶段先检查结果，再继续下一阶段。它也适用于通过远程桌面操作的 Windows 电脑：**所有安装命令都要在目标电脑上运行**。

这是原 GitHub 项目的独立自动 Root 版本，发布在独立仓库，不会改变原仓库。不要从旧仓库克隆后假定其中已包含自动 Root 修改。

> 项目目前属于实验性 x86-64 移植：尚未验证本 WSL 版本在新电脑上的 Google Play Integrity 结果；SUSFS 的 ARM64 用户空间工具不能直接在 x86-64 上运行。WSLg 原生窗口的侧栏和剪贴板可能有问题，本版本使用独立显示服务。

## 0. 阅读前先知道

### 两种终端，命令不能混用

| 终端 | 提示符示例 | 本手册标识 | 用途 |
| --- | --- | --- | --- |
| Windows PowerShell | `PS C:\Users\name>` | **Windows PowerShell** | 安装 WSL、检查磁盘、克隆项目、运行 `build.ps1` |
| Ubuntu 22.04 | `name@computer:~$` | **Ubuntu** | 安装 Android SDK、检查 KVM、创建和启动模拟器 |

在 Windows PowerShell 输入 `wsl -d Ubuntu-22.04` 进入 Ubuntu；在 Ubuntu 输入 `exit` 返回 PowerShell。`sudo` 的密码是创建 Ubuntu 用户时设置的 **Linux 密码**，输入时不显示字符属于正常现象，输入完按回车即可。

不要输入提示符本身。例如显示 `PS C:\>` 时，只输入代码块里的命令。

### 自动和手动部分

- 手动：安装 WSL、Docker Desktop、Git、Java；启用虚拟化/KVM；审阅 Android SDK 许可；准备自己的 keybox。
- 脚本完成：下载 Android SDK 和显示组件、编译内核、创建 AVD、自动启用 ADB Shell Root、下载并校验模块、写入项目配置、运行检查。`start-x11.sh` 调用本版本 `start.sh` 并启用自动 Root。
- 密钥：本仓库不包含真实 keybox。不要在聊天、截图或 GitHub 中发送私钥。配置脚本按上游要求把设备里的 keybox 设为 0644，同一设备上的其他进程可能读取它；只在隔离的测试设备中使用。

### 空间规划

Windows、Ubuntu 的虚拟磁盘、Android SDK/AVD、Docker 数据盘可能分别位于不同位置。**单独把仓库放到 D 盘或 F 盘，并不会自动把 Docker 和 Ubuntu 的数据搬过去。**

在目标电脑的 **Windows PowerShell** 查看所有磁盘：

```powershell
Get-PSDrive -PSProvider FileSystem |
  Select-Object Name,Root,@{Name='FreeGB';Expression={[math]::Round($_.Free/1GB,2)}}
```

`build.ps1` 对能够识别的 Docker 默认数据盘要求至少 20 GB 可用空间；这只是**构建前检查阈值，不是整个项目的总空间保证**。SDK、系统镜像、Ubuntu、Docker 和模拟器数据也会占空间，建议为全部阶段留出明显高于 20 GB 的余量，并在 SDK 安装后、构建前再次检查。

不要通过删除其他 Docker volume 或 `wsl --unregister` 来盲目腾空间。`wsl --unregister` 会永久删除指定发行版内部的数据；先确认内容并单独备份，再自行决定是否删除。

## 1. 安装 WSL2 和 Ubuntu 22.04

1. 确认目标电脑的 CPU 虚拟化已启用；如果目标电脑本身是一台虚拟机，其宿主平台还必须提供嵌套虚拟化。远程桌面能连接并不代表嵌套虚拟化可用。
2. 以管理员身份打开 **Windows PowerShell**，查看可安装的发行版：

   ```powershell
   wsl --list --online
   ```

3. 如果还没有 Ubuntu 22.04，在 **Windows PowerShell** 运行：

   ```powershell
   wsl --install -d Ubuntu-22.04
   ```

   按 Windows 提示重启。第一次打开 Ubuntu 时创建 Linux 用户名和密码。参考 [微软 WSL 安装文档](https://learn.microsoft.com/windows/wsl/install)。
4. 回到 **Windows PowerShell** 检查：

   ```powershell
   wsl -l -v
   ```

   找到 `Ubuntu-22.04`，其 `VERSION` 应为 `2`。`docker-desktop` 是 Docker 自己的发行版，不要把它当作普通 Ubuntu 删除。若有多个 Ubuntu，以 `Ubuntu-22.04` 为本项目目标；没有必要为本项目删除其他发行版。
5. 在 **Windows PowerShell** 进入 Ubuntu，检查版本：

   ```powershell
   wsl -d Ubuntu-22.04
   ```

   然后在 **Ubuntu** 执行：

   ```bash
   cat /etc/os-release
   uname -m
   ```

   架构应显示 `x86_64`。安装其他架构或 Linux 发行版不属于本次验证范围。

## 2. 安装并检查 Docker 和 Windows Git

1. 在目标 Windows 电脑安装 [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/)，使用 Linux/WSL2 引擎并启动它。
2. 安装 [Git for Windows](https://git-scm.com/install/windows)。
3. 新开一个 **Windows PowerShell**，运行：

   ```powershell
   git --version
   docker version
   docker info
   ```

   `git --version` 应显示版本；`docker version` 要能看到 **Server**，仅有 Client 不代表 Docker 引擎可用。`docker info` 如果报引擎不可连接，请先启动 Docker Desktop，等待启动完成后重试。
4. 如果 Docker 无法拉取基础镜像或 GitHub/GitLab 无法连接，先处理目标机器的网络或 DNS；不要把连接失败当成代码编译错误。

   Windows、WSL、Docker 容器和 Android 模拟器使用不同的网络环境。Windows 浏览器能连接不代表 WSL 或模拟器一定能连接；如使用代理，需要确认相应环境能够访问代理地址。特别是 WSL 的 NAT 环境无法直接使用 Windows 仅监听在 `127.0.0.1` 的代理，本机从零测试需要额外的代理转发才能下载部分模块。代理地址和端口因电脑而异，不要直接照搬其他机器的值。

## 3. 准备本版本的项目文件

获得该私有仓库的访问权限，然后在 **Windows PowerShell** 克隆到目标电脑。例如：

```powershell
New-Item -ItemType Directory -Force C:\avd-work | Out-Null
cd C:\avd-work
git clone --branch windows-network-integration https://github.com/ATLord/avd-rooted-integrity-wsl-ui.git avd-rooted-integrity-autoroot
cd C:\avd-work\avd-rooted-integrity-autoroot
dir
```

应能看到 `README.md`、`x86`、`kernel-build`、`device` 等目录。`C:\avd-work` 只是示例，可改用空间充足的其他盘；后文的 `/mnt/c/avd-work/...` 也要相应调整。真实 keybox 不随项目提供；重新分发源码时，编译好的内核和安装包默认被 Git 忽略，需要重新构建和下载。

## 4. 安装 Ubuntu 依赖与 Android SDK

在 **Windows PowerShell** 输入 `wsl -d Ubuntu-22.04`，然后在 **Ubuntu** 执行：

```bash
sudo apt update
sudo apt install -y openjdk-17-jre-headless curl unzip git python3 libpulse0 libxi6 libxkbfile1 libsm6 libice6 p7zip-full xauth x11-utils
java -version
cd /mnt/c/avd-work/avd-rooted-integrity-autoroot
bash x86/scripts/install-sdk.sh
bash x86/scripts/install-xserver.sh
```

如果克隆在其他磁盘，替换 `cd` 路径。SDK 脚本下载 Google 官方命令行工具并检查哈希，然后提示你阅读和接受 SDK 协议，接着安装 ADB、模拟器和 Android 36 Google Play x86-64 镜像。显示组件脚本下载并校验 VcXsrv，解压到项目的 `x86/xserver/`。根据你的决定在协议提示中输入 `y` 或 `n`；未接受所需协议则无法完成安装。

安装后在 **Ubuntu** 检查：

```bash
grep Pkg.Revision "$HOME/Android/Sdk/system-images/android-36/google_apis_playstore/x86_64/source.properties"
"$HOME/Android/Sdk/platform-tools/adb" version
"$HOME/Android/Sdk/emulator/emulator" -version
```

本项目的内核配置使用 **revision 7**，预期是 `Pkg.Revision=7`。如果 SDK 安装脚本报镜像版本不是 7，不要强行当作已验证环境：当前 SDK 下载的是 Google 当时提供的版本，仓库并不保证能自动获取历史 revision 7。需要另行取得可信、匹配的镜像并验证其兼容性。

现在回到 **Windows PowerShell** 再次运行 `Get-PSDrive C`；如果 Docker 数据盘在别的盘，也检查该盘。Docker 数据盘少于 20 GB 时不要开始构建。

## 5. 检查 KVM

在 **Ubuntu** 按 CPU 类型加载模块。Intel 示例：

```bash
sudo modprobe kvm_intel
sudo usermod -aG kvm "$USER"
sudo chgrp kvm /dev/kvm
sudo chmod 660 /dev/kvm
```

AMD 环境需要使用 `kvm_amd` 并确认虚拟化配置。退出 Ubuntu 后重新进入，使用户组变更生效；随后运行：

```bash
id
ls -l /dev/kvm
"$HOME/Android/Sdk/emulator/emulator" -accel-check
```

检查用户是否属于 `kvm` 组，且加速检查提示 KVM 可用。`/dev/kvm` 权限在 WSL 完全重启后可能需要重新设置；如果加载模块失败或没有 `/dev/kvm`，先检查虚拟化/嵌套虚拟化，不要继续假设模拟器能正常运行。

## 6. 编译自定义内核

在 **Windows PowerShell**，而不是 Ubuntu 终端：

```powershell
cd C:\avd-work\avd-rooted-integrity-autoroot
.\x86\build.ps1
```

脚本会在 Windows 侧获取固定版本的 SUSFS，构建 Docker 镜像，在专用 volume 中下载和修补内核源码，并编译 x86-64 内核。首次可能花费较长时间，下载或编译时不要关闭 Docker。成功后确认：

```powershell
Test-Path .\x86\out\bzImage-x86_64
Get-Item .\x86\out\bzImage-x86_64 | Select-Object FullName,Length
```

应显示 `True`，文件大小应大于 0。输出不会进入 Git 仓库。构建时如果 C 盘或 Docker 数据盘空间快速下降，应先停止并腾出空间；如果 Docker 因磁盘写满变成只读，释放空间后可能需要恢复 Docker/WSL，再继续诊断。构建脚本会锁定源码版本和检查 BTF，但软件包和编译时间可能变化，因此二进制哈希不保证相同。

## 7. 创建并启动模拟器

在 **Ubuntu** 中：

```bash
cd /mnt/c/avd-work/avd-rooted-integrity-autoroot
bash x86/scripts/create-avd.sh
bash x86/scripts/doctor.sh
bash x86/scripts/start-x11.sh
```

`create-avd.sh` 拒绝覆盖已有同名 AVD；不要用强制覆盖处理不认识的现有设备。`doctor.sh` 会检查 SDK、内核文件和 KVM；如果出现 `FAIL`，先处理该项。`start-x11.sh` 启动 Windows 显示服务并调用 WSL 模拟器，使用模拟器端口 5554；保持该终端运行，启动后另开 Ubuntu 终端进行后续操作。退出模拟器后，该显示服务也会关闭。

如果原版同名 AVD 已经在运行，先正常关闭模拟器，再运行本版本 `start-x11.sh`。本版本在模拟器进程启动时添加 Shell 自动 Root 参数，只有在 Android 内执行 `adb reboot` 不会给旧的模拟器进程添加该参数。

在另一个 **Ubuntu** 终端检查：

```bash
"$HOME/Android/Sdk/platform-tools/adb" devices -l
"$HOME/Android/Sdk/platform-tools/adb" -s emulator-5554 shell getprop sys.boot_completed
```

预期看到 `emulator-5554 device`，且第二条命令输出 `1`。首次开机可能需要较长时间；`offline` 或空结果时等待并重试，不要立刻执行安装。

## 8. 自动 Root 和模块安装

模拟器开机完成后，在另一个 **Ubuntu** 终端：

```bash
cd /mnt/c/avd-work/avd-rooted-integrity-autoroot
bash x86/scripts/install-modules.sh
```

脚本会下载指定版本并校验 SHA-256，自动安装并启动 KernelSU 管理器、检查 ADB Shell Root，然后安装模块；不需要手动授权 Shell。启动脚本启用的 KernelSU 参数只自动授权 ADB Shell，不自动授权普通应用。由于 Shell 具有 Root 权限，请仅在自己的测试 AVD 中使用。

安装结束后，用模拟器内重启或在 **Ubuntu** 执行：

```bash
"$HOME/Android/Sdk/platform-tools/adb" -s emulator-5554 reboot
```

等待完全开机后检查：

```bash
"$HOME/Android/Sdk/platform-tools/adb" -s emulator-5554 shell su -c id
```

看到 `uid=0(root)` 表示 ADB Shell 已获得 Root。它只说明 Root 可用，不能说明完整性认证通过。如果下载失败，可先检查目标电脑访问各发布源的网络；不要跳过校验或从不可信来源替换文件。

## 9. 配置自己的 keybox

只对本项目的测试 AVD 操作。把自己有权使用的 keybox 保存在目标电脑的本地安全位置，例如 `C:\avd-private\keybox.xml`，然后在 **Ubuntu**：

```bash
cd /mnt/c/avd-work/avd-rooted-integrity-autoroot
bash x86/scripts/configure-device.sh /mnt/c/avd-private/keybox.xml
"$HOME/Android/Sdk/platform-tools/adb" -s emulator-5554 reboot
```

路径只是示例，必须替换成自己的实际路径。具体的文件准备、Windows 与 Ubuntu 路径转换、验证命令和常见错误，参见 [keybox.xml 配置教程](KEYBOX.zh-CN.md)。脚本直接读取该文件，不把真实 keybox 加入项目目录或 Git；但会将其写入测试模拟器。文件格式可参考 `device/data_adb/tricky_store/keybox.xml.example`，该示例不是有效密钥。项目不会帮你获得 keybox，也不能证明它没有被撤销。

**不要通过手动重启 keymint、keystore2 或 TEESimulator 来应用变更。** 按上游说明，使用完整重启；认证模式只能在实际触发认证请求后检查。

## 10. 验证结果

等 Android 完全启动，在 **Ubuntu**：

```bash
bash x86/scripts/check-device.sh
bash x86/scripts/check-network.sh
```

逐项查看输出：

- 启动完成、`uid=0(root)`：说明系统和 ADB Root 工作。
- Wi-Fi、IP、HTTPS 检测：分别说明局部连接情况；一个站点能访问不代表 Google 所有服务均可访问。
- 项目属性检查和 TEESimulator 进程：只是结构状态。即使显示全部通过，也不是 Google 的最终认证结果。
- `ksu_susfs` 执行错误：本版本已知 ARM64 工具与 x86-64 不兼容，不能据此声称全部 SUSFS 规则已生效。
- 未出现 `integrity.api.key.alias` 活动或没有检测应用返回的 verdict：仍无法判断 `MEETS_DEVICE_INTEGRITY` 或 `MEETS_STRONG_INTEGRITY`。

上游检查脚本可能在显示失败时仍返回零退出码，因此必须阅读文字结果，不能只看命令返回值。

## 11. 日常使用与故障处理

每次使用时，在 Ubuntu 进入项目目录后运行 `bash x86/scripts/start-x11.sh`。WSL 重启后如 `/dev/kvm` 不可用，重复第 5 节的 KVM 模块和权限步骤。正常重启优先使用 Android 内置重启或 `adb reboot`，不要强行终止正在写入数据的模拟器。

| 现象 | 先检查什么 |
| --- | --- |
| `docker info` 失败 | Docker Desktop 是否启动、Linux 引擎是否可用，Docker 数据盘是否有空间 |
| `Pkg.Revision` 不是 7 | 脚本下载到其他镜像修订版；不要视为已验证的兼容版本 |
| `/dev/kvm` 不存在 | CPU 虚拟化、远程虚拟机嵌套虚拟化及 KVM 模块 |
| `already exists` | 已有同名 AVD；先确认数据，不要覆盖 |
| `adb` 无设备或 `offline` | 等待完整开机，确认 AVD 端口及 `adb devices -l` |
| `su` 找不到 | 等待开机，用本版本 `start-x11.sh` 启动 AVD，再重新运行模块安装脚本 |
| 网络部分可用 | 检查 Wi-Fi、IP、DNS、代理及 Google 服务各自的 HTTPS 测试 |
| 右侧栏点不动或无法复制粘贴 | 确认使用 `start-x11.sh`；检查 X 显示端口及 WSL 到 Windows 显示服务的网络连接 |
| 检查脚本全绿但没有认证结果 | 结构检查不是服务端判定；需要实际触发 Play Integrity 请求并查看结果 |

如需反馈错误，提供：执行步骤、报错文字、发行版和磁盘空间信息。不要提供密码、keybox 内容、认证令牌或包含隐私的完整日志。

## 12. 文件位置与版本来源

项目主目录的 `x86/build.ps1` 是 Windows 构建入口；`x86/scripts/` 包含 SDK、AVD、启动、模块配置和检查脚本；`x86/config/` 包含与已验证镜像对应的原厂内核配置。`x86/out/`、`x86/downloads/`、`x86/cache/` 及真实 keybox 均被 Git 忽略。上游项目及其提交版本、详细限制见仓库首页 [README.md](../README.md)。
