# Windows 网络接管与 WSL 模拟器

本版本依赖 Windows 的实际网络路由，不在 Android 或启动脚本里配置 HTTP 代理。Windows 的 VPN/TUN 开关和路由规则由用户的网络软件管理；本项目不会自动开启 VPN，也不能保证所有 VPN 都会接管 WSL 或所有 UDP、DNS 流量。VPN 断开时网络可直连不代表 Google 服务一定可访问。

## 本机测试环境

Windows 11、WSL 2.7.8、Ubuntu 22.04 NAT 网络及 v2rayN 7.25.4 TUN 模式。一次测试中，TUN 开启时，新建 AVD 不设置 Android HTTP 代理，可访问百度、Google、Google 连通性检测和认证状态接口；关闭 TUN 后百度可访问，而 Google 和认证接口超时；重新开启 TUN、重启 WSL 和 AVD 后，HTTPS 探测再次通过。测试 AVD 的检查报告 Wi-Fi 关闭，虽然网络探测成功，VirtWifi 自动连接未验证通过。此结果只适用于当时的机器、网络和路由规则；不是 Play Integrity 判定，也不能证明所有协议都被接管。

同机的 WSL 镜像网络模式在 TUN 开启时直连测试超时，因此本方案在此环境使用 NAT。不同设备上的行为可能不同。更改 `.wslconfig` 会影响所有 WSL 发行版及 Docker Desktop：先保存原配置、关闭工作并自行确认影响，不能在脚本中静默执行 `wsl --shutdown`。本仓库不自动改写该配置。

## 使用

1. 在 Windows 网络软件中按需开启或关闭 TUN/VPN，确认它确实接管 WSL 流量。代理软件只设置系统 HTTP 代理，不等同于 TUN。
2. 在 Android 的 VirtWifi 网络详情中，将 Proxy 设为 **None**。删除之前配置的手动 Wi-Fi 代理；它不会随网络地址改变而自动更新。
3. 按 README 启动 AVD。启动脚本不会继承 shell 中的 HTTP/SOCKS 代理环境变量；外部网络由 Windows 的网络路由决定。
4. 用 `AVD_NAME=你的AVD名称 bash x86/scripts/check-network.sh` 检查 Wi-Fi、DNS 和 HTTP 连接。该脚本打印各项结果，退出码不能单独代表所有探测均成功。
5. 测试 TUN 打开与关闭两种情况，并在切换后重新启动模拟器验证。需要完全走 VPN 时，也要检查 VPN 的分流策略，以及 UDP、DNS 和其他应用行为。无 VPN 时 Google 超时不一定是程序错误。

如果当前 VPN 与 WSL NAT 不兼容，请检查该 VPN 软件的 WSL/虚拟网卡支持；不要通过关闭防火墙解决。排查时先分别检查 Windows、WSL 和 AVD，再查看 VPN 软件日志。无论哪种网络方式，Play Integrity 必须通过实际请求与服务端返回结果另行验证。
