# 功能清单与平台矩阵

本文列出仓库的每个入口及其适用平台。任何改动都不应让下表中的入口消失或改变用法；行为若有变化，记录在 [`CHANGELOG.md`](../CHANGELOG.md) 中，并提供恢复旧行为的开关。

平台：

- **ARM**：macOS Apple Silicon，arm64 AVD，即上游原有流程，详见 [`UPSTREAM_README.md`](UPSTREAM_README.md) 和 [`REPRODUCTION.md`](REPRODUCTION.md)。
- **x86**：Windows + WSL2，x86_64 AVD，即本仓库新增的流程，详见 [`../README.md`](../README.md) 和 [`INSTALLATION.zh-CN.md`](INSTALLATION.zh-CN.md)。

Google 官方只发布 linux_x64、darwin_x64、darwin_aarch64、windows_x64 四种 Android 模拟器，没有 Linux ARM64 或 Windows on ARM 版本，所以这两种宿主不在支持范围内。

## 内核构建

| 入口 | 平台 | 产物 | 说明 |
| --- | --- | --- | --- |
| `kernel-build/Dockerfile` + `kernel-build/scripts/build-all.sh` | ARM | `kernel-build/out/Image.gz` | fetch → apply-patches（含 customize-kernel）→ build |
| `kernel-build/scripts/{fetch-sources,apply-patches,customize-kernel,build}.sh` | ARM（fetch/apply 也被 x86 复用） | — | 单步执行 |
| `x86/build.ps1` → `x86/Dockerfile` → `x86/scripts/build-in-container.sh` | x86 | `x86/out/bzImage-x86_64` | 基于 `kernel-build` 镜像；复用 fetch-sources、apply-patches，再执行 `patch-kernelsu.py` |

## 宿主端准备与启动

| 入口 | 平台 | 作用 |
| --- | --- | --- |
| `scripts/start_avd.sh` | ARM | 用自定义内核冷启动 AVD；环境变量 `AVD`、`KERNEL`、`EMULATOR`、`LOG` |
| `x86/scripts/install-sdk.sh` | x86 | 下载并校验 cmdline-tools，安装 SDK 组件 |
| `x86/scripts/create-avd.sh` | x86 | 创建 `Pixel_9_Pro_XL_x86`，打开键盘和 Wi-Fi |
| `x86/scripts/start.sh` | x86 | 用 `bzImage-x86_64` 启动，并在后台确保 Wi-Fi 连接 |
| `x86/scripts/install-xserver.sh`、`start-x11.sh`、`xserver-control.ps1` | x86 | 用 VcXsrv 提供窗口和剪贴板 |
| `x86/scripts/doctor.sh` | x86 | 宿主环境检查 |

## 设备端安装与配置

| 入口 | 平台 | 作用 |
| --- | --- | --- |
| `device/modules.md` | 共享 | 依赖模块及其版本 |
| `x86/scripts/install-modules.sh` | x86 | 下载并校验模块，自动获取 Root，安装模块和 VirtWifi 服务 |
| `scripts/install-device-setup.sh` | 共享 | 推送 `device/data_adb/`、keybox 和 PIF profile |
| `x86/scripts/configure-device.sh` | x86 | 校验 keybox 结构后调用 `install-device-setup.sh` |

## 设备端脚本（`/data/adb`，两种架构共用）

| 脚本 | 作用 |
| --- | --- |
| `post-fs-data.d/00-make-fakes.sh` | 从 PIF profile 生成各分区属性、`build.prop`、`dt_compatible`、安全补丁日期 |
| `post-fs-data.d/00-zygisk-sepolicy.sh`、`rezygisk.sh` | Zygisk 所需的 sepolicy 和启动配置 |
| `post-fs-data.d/01-avd-prop-spoof.sh`、`04-prop-sweep.sh` | 属性伪装与清理 |
| `post-fs-data.d/02-avd-deeper-spoof.sh` | 通过 SUSFS 重定向 `/proc`，隐藏 qemu 设备节点和 Zygisk 库 |
| `post-fs-data.d/07-procbind-safe.sh`、`09-buildprop-bind.sh` | bind mount 伪造的 `/proc` 文件和 `build.prop` |
| `service.d/05-tee-watchdog.sh` | 检测 TEESimulator 是否退出（默认只告警，可选择自动拉起，见 CHANGELOG） |
| `service.d/08-tee-broken.sh` | 设置 `tee_status`、`security_patch` 并加不可变位 |
| `service.d/09-display.sh` | 分辨率和 DPI 与 Pixel 9 一致 |
| `service.d/10-wlan0-virtwifi.sh` | 创建 virt_wifi 的 `wlan0` 并连接 VirtWifi |
| `service.d/12-checkin.sh` | 网络就绪后触发一次 GMS check-in |
| `susfs4ksu/*`、`tricky_store/*`、`avd-fake/*`、`pif/custom.pif.prop` | 配置和伪造数据 |

## 诊断

| 入口 | 平台 | 作用 |
| --- | --- | --- |
| `scripts/verify-integrity.sh [--trigger]` | 共享 | 结构检查，以及 GENERATE/PATCH 模式检查 |
| `x86/scripts/check-device.sh` | x86 | Root、网络检查，并调用 verify-integrity |
| `x86/scripts/check-network.sh` | x86 | DNS/HTTPS 探测 |

## 测试

| 入口 | 覆盖 |
| --- | --- |
| `x86/tests/test-start-wifi.sh` | `start.sh` 的 Wi-Fi 处理与代理清除 |
| `x86/tests/test-configure.sh` | keybox 从外部路径推送、不写入仓库 |
| `tests/*.sh` | 共享脚本和 ARM 流程的回归测试（mock adb/emulator） |
| `.github/workflows/ci.yml` | 运行 shellcheck 和上述全部测试，并构建 `kernel-build` 镜像 |
