# 本地修复与冷启动复验

本轮修复保存在独立私有仓库 `ATLord/avd-rooted-integrity-wsl-cc2`，保留原项目提交历史。没有可用的 Android 客机，不能宣称已解决实测设备上的全部故障或通过 Play Integrity。

## 根因证据与修复范围

目录存在、Root 可用不等于模块生命周期执行过。旧日志缺失支持“启动链路异常”的判断，但不能单独排除脚本在写日志前失败、等待 boot_completed 或安全模式跳过。新安装在 post-fs-data.d 和 service.d 最前面分别记录当前 boot ID；check-boot.sh 拒绝旧启动标记，并检查模块禁用/待更新状态。该标记只证明入口执行，实际身份、挂载、TEE、Wi-Fi 仍由 verify-integrity.sh 检查。

内核固定版本的 KSUD_PATH 是 `/data/adb/ksud`。旧安装只启动 Manager 界面、等 Root，然后调用 bin 下的 ksud，没有显式确保 init 所需的用户态安装完成。现在从已校验 SHA-256 的 APK 提取 x86_64/libksud.so，执行其 `install` 并校验入口。它是对安装缺口的修复，不代表已从用户故障机日志证明这是唯一根因。

Wild 补丁移除原始 syscall 注册，SUSFS 内核补丁提供 read/stat/exec 调用。构建脚本原来容忍 SUSFS patch 失败；现在额外检查三个关键调用点，缺失即中止构建。统一 read-hook 的单参数声明与定义。其他 SUSFS 补丁仍需审阅构建日志；此检查不是完整内核验证。

TEESimulator 的首次启动由 tricky_store 模块完成；watchdog 默认只告警不意味着全新安装必然没有 TEE。验证失败会给出日志排查方向和显式恢复 flag；该 flag 要求 watchdog 已运行，晚启动可能进入 PATCH 模式。

## 在原测试环境复验

在 WSL Ubuntu 中，从此修改版仓库执行；自定义 SDK 路径和序列号时沿用你的设置：

```bash
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
export ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
bash x86/scripts/install-modules.sh
adb emu kill
# 等 start-x11.sh 及 emulator 退出后，在启动终端执行：
bash x86/scripts/start-x11.sh
```

另一个终端中：

```bash
bash scripts/check-boot.sh
# 必须先通过；失败时收集下方日志，不要在已启动系统手动补跑 post-fs-data。
bash x86/scripts/configure-device.sh /你的路径/keybox.xml
adb emu kill
# 再次等退出并运行 start-x11.sh；完成后：
bash x86/scripts/check-device.sh
bash x86/scripts/check-network.sh
```

若钩子仍缺失，保存 `adb shell su -c 'ls -lZ /data/adb/ksud /data/adb/ksu/bin/ksud'`、`adb shell su -c dmesg`、`adb logcat -b all -d` 和 `/data/adb/ksu/log/`，检查 init/ksud 错误、安全模式和模块 disable 标志。在 PowerShell 重跑 `x86/build.ps1`，确保新的关键调用检查通过，再使用新内核冷启动。日志可能包含设备信息，应先脱敏。

这里冷启动统一指关闭 emulator 进程，再由带 `-no-snapshot` 的启动脚本重新运行；`adb reboot` 只重启 guest，不能与它混称。

## 检查结论

- 安装脚本退出 0：仅文件部署完成，提示 activation PENDING；不自动重启正在使用的设备。
- check-boot.sh 退出 0：本次启动的两个入口和模块目录状态通过，不保证每个模块生效。
- check-device.sh / verify-integrity.sh：1 为结构或模式失败；2 为未捕获 attestation 活动；0 仍不代表 Google 服务端认可。
- `--trigger` 可传给 check-device.sh，但会清除 Play Store 数据、GMS droidguard 缓存和 logcat；仅在接受这些副作用时使用。打开 Play Store 不保证一定产生请求，无活动仍返回 2。
- profile.env 缺失、生成标记不是当前 boot、DEVICE/SECURITY_PATCH 缺失均不能通过；system/boot/vendor patch 分别精确比较。
- x86 跳过 ARM64-only SUSFS 用户态模块，并禁用旧安装的同名模块；不把内核 SUSFS 支持误报为用户态规则已生效。
- Wi-Fi 与 eth0/QEMU NAT 分开显示；每个 wget 探测输出原始内容、退出码或明确的空输出提示。HTTP 端点错误也可能表示已经连上服务器，不能直接推断为断网。
- devices.xml 警告保留，创建后核对 Pixel 9 Pro XL 的设备名及 1344×2992 分辨率；参数不符时失败并保留 AVD 供检查。

## 本地验证记录

12 个 mock/回归脚本全部通过（包含新增生命周期、profile/patch、内核调用检查、网络输出和 AVD 参数测试）；修改过的 Shell 脚本通过 ShellCheck 0.11.0，Python 编译检查及 git diff --check 通过。现有 watchdog/Wi-Fi 测试改为等待模拟状态，避免 Git Bash 下固定时长造成竞态。

没有编译完整内核、启动 AVD 或执行真实 attestation；本机没有 ADB/可用客机，Docker 引擎未运行。关键修复仍需按上述步骤在故障环境冷启动复验。
