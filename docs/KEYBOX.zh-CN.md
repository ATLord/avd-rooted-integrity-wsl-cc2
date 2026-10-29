# keybox.xml 配置教程

> 本教程适用于本项目在 WSL2 中创建的 AVD，并使用 WSL 中的 ADB 操作。

本文说明如何将自己已有的 `keybox.xml` 配置到本项目的测试模拟器。文件名是 **keybox.xml**，不是 `checkbox.xml`。项目不提供真实 keybox，也不会根据示例文件生成可用的硬件证明密钥。

## 1. 准备工作

先按照 [安装手册](INSTALLATION.zh-CN.md)完成环境准备，使用本版本的 `start.sh` 启动 AVD，并运行 `install-modules.sh` 安装模块。模块安装后重启 Android，等系统完全启动。

在另一个 Ubuntu 终端执行：

```bash
"$HOME/Android/Sdk/platform-tools/adb" devices -l
"$HOME/Android/Sdk/platform-tools/adb" -s emulator-5554 shell getprop sys.boot_completed
"$HOME/Android/Sdk/platform-tools/adb" -s emulator-5554 shell su -c id
```

预期看到 `emulator-5554 device`、`1` 和 `uid=0(root)`。本版本通过启动参数自动为 ADB Shell 提供 Root，不需要在 KernelSU 管理器中手动授权；如果 `su` 仍不可用，确认使用的是本版本的启动脚本，并重新执行模块安装脚本。

## 2. 准备自己的 XML 文件

将你已有且有权使用的文件放在目标电脑上，例如：

```text
C:\avd-private\keybox.xml
```

这只是示例路径，不要覆盖其他文件。Windows 文件资源管理器可以开启“显示文件扩展名”，确认文件没有误命名为 `keybox.xml.xml`。不要把文件内容、私钥或证书粘贴到聊天里。

在 Ubuntu 中，Windows 磁盘通常对应 `/mnt/盘符小写/`：

| Windows 路径示例 | Ubuntu 对应路径 |
| --- | --- |
| `C:\avd-private\keybox.xml` | `/mnt/c/avd-private/keybox.xml` |
| `F:\keybox.xml` | `/mnt/f/keybox.xml` |

在 Ubuntu 检查自己的文件是否存在，例如：

```bash
ls -l /mnt/c/avd-private/keybox.xml
```

只查看文件名和权限即可，不需要打开或打印文件内容。如果实际文件在 F 盘，改成 `ls -l /mnt/f/keybox.xml`。项目中的 `device/data_adb/tricky_store/keybox.xml.example` 只是格式示例，不能替代真实文件。

## 3. 写入模拟器

在 Ubuntu 进入**本自动 Root 版本**的项目目录。下面是示例，按实际项目位置调整：

```bash
cd /mnt/c/avd-work/avd-rooted-integrity-autoroot
bash x86/scripts/configure-device.sh /mnt/c/avd-private/keybox.xml
```

若文件实际位于 `F:\keybox.xml`，第二条命令应改为：

```bash
bash x86/scripts/configure-device.sh /mnt/f/keybox.xml
```

脚本检查 XML 是否有 `AndroidAttestation` 根元素以及 `Key` 和 `Certificate` 元素，再把文件与项目配置写入目标模拟器的 `/data/adb/tricky_store/keybox.xml`。它不会修改原始文件，也不会将文件添加到 Git 仓库。出现完成提示后重启 Android：

```bash
"$HOME/Android/Sdk/platform-tools/adb" -s emulator-5554 reboot
```

不要手动重启 keymint、keystore2 或 TEESimulator 服务。等待 Android 完全启动，再进行下一步。

## 4. 检查配置

```bash
"$HOME/Android/Sdk/platform-tools/adb" -s emulator-5554 shell getprop sys.boot_completed
bash x86/scripts/check-device.sh
bash x86/scripts/check-network.sh
```

第一条应输出 `1`。检查脚本可以显示 Root、keybox 文件权限、模块进程和网络情况；这些只是结构和运行状态。XML 基本结构正确、文件可读取或 TEESimulator 进程运行，**都不证明 keybox 有效、未被撤销，也不代表 Google Play Integrity 已通过**。

## 常见问题

- `Usage: configure-device.sh ...`：没有提供路径或文件不存在；检查路径、盘符和文件扩展名。
- `Invalid keybox structure`：文件不是预期的 XML 结构；检查你自己的文件，别把密钥内容发出来。
- 找不到 `playintegrityfix`：先运行 `install-modules.sh` 并重启，等模块激活后再配置 XML。
- `su` 不可用：确认通过本版本 `start.sh` 启动，并在 Android 完全启动后运行 `install-modules.sh`。
- 结构检查通过但没有完整性结果：需要实际发起 Play Integrity 请求并查看服务器判定；项目不承诺通过。

按上游要求，模拟器内的 keybox 权限为 `0644`，设备中的其他进程可能读取私钥。请仅用于隔离的测试 AVD，不要使用生产设备的敏感密钥，也不要将真实文件提交或分享。
