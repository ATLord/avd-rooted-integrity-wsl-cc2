# 更新记录

本文记录对上游项目的行为变化，重点是可能改变现有用户结果的改动，以及如何恢复旧行为。日期为改动合入日期。

## 未发布

### 修复

- **`verify-integrity.sh` 的检查之前会给出错误结论。** 远端命令的引号嵌套有误，被设备外层 shell 重新解析：
  - 含 `tr -d "\""` 的命令是语法错误，所以设备名从未从 `profile.env` 读到，`security_patch` 与 profile 的比对也从未真正执行（一直走通过分支）。
  - 指纹一致性检查中的 `$n` 被外层 shell 展开成空，五次读取都落到同一个属性，检查永远通过。

  现在命令按单引号原样传给设备。**影响：** 之前显示全绿的设备可能开始出现 ✗，这是暴露此前被掩盖的真实问题，不是回归。
- **PATCH 模式检测不再写死 `uid=10146`。** GMS 的 uid 因安装而异，uid 不符时之前会把最关键的 GENERATE/PATCH 检查误报为通过。现在匹配任意 uid 的 integrity 别名。
- **`install-device-setup.sh` 不再在设备端步骤失败时谎报成功。** 保留“单步失败不中断后续步骤”的原设计，但现在累计失败、以非零码退出，并且无论成败都删除暂存的 keybox 副本。

### 变化（提供恢复旧行为的方式）

- **TEE 看门狗默认只告警。** `05-tee-watchdog.sh` 检测到 TEESimulator 退出时记录日志并提示冷重启，不再自动拉起——开机后拉起会进入 PATCH 模式（进程存活但 verdict 为空）。**恢复旧的自动拉起：** `su -c touch /data/adb/avd-fake/tee-watchdog-relaunch`（每 30 秒重新读取，立即生效）。
- **Wi-Fi 连接改由设备端脚本负责。** `10-wlan0-virtwifi.sh` 连上 VirtWifi 后把本次开机的 `boot_id` 写入 `/data/adb/avd-net-ready`。`start.sh` 在该服务存在时只等待标记，不再与之竞争；旧设备（未装该服务）仍走主机端连接，且约 10 分钟无标记时回退到主机端连接。
- **check-in 改为等网络就绪后再发。** `12-checkin.sh` 先等本次开机的网络标记（最多 10 分钟，匹配 Wi-Fi 重试窗口），再等 VALIDATED 网络，最后无论如何都会发送广播。之前只等 120 秒，可能在网络就绪前就 check-in，导致 GMS 退避数小时。
- **`start.sh` 默认清除代理变量。** 之前的提交已是如此。**保留当前代理：** `AVD_KEEP_PROXY=1 bash x86/scripts/start-x11.sh`。
- **设备端日志不再无限增长。** `wlan0-setup.log`、`checkin-nudge.log`、`tee-watchdog.log` 每次开机重写，上一次保留为 `.prev`。

### 新增与可移植性

- 平台矩阵（README「先确认你的机器」）和功能清单（[docs/FEATURES.md](docs/FEATURES.md)）。
- `start-x11.sh` 在 WSL 镜像网络模式下用 `127.0.0.1`（NAT 模式不变），`AVD_X11_HOST` 可覆盖；AVD 已运行时不再启动又立即关闭 X server。
- `start.sh` 支持 `ANDROID_SERIAL`（`emulator-<端口>`，默认 `emulator-5554`）；KVM 提示按 CPU 厂商选 `kvm_amd`/`kvm_intel`，使用实际的 `$WSL_DISTRO_NAME`，在非 WSL 的 Linux 上给出本机命令。
- `scripts/start_avd.sh`（ARM 流程）在保留 macOS 默认路径的同时也查找 `~/Android/Sdk`。
- `02-avd-deeper-spoof.sh` 同时隐藏 x86_64 的 Zygisk 库（路径不存在则跳过，ARM 行为不变）。
- CI（`.github/workflows/ci.yml`）运行 shellcheck 和基于 mock 的测试（`tests/`、`x86/tests/`），并构建共用的 `kernel-build` 工具链镜像。
