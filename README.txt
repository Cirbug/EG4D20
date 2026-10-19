EG4D20 电脑千兆网口回环工程
更新：2026-10-19

工程和成品
    工程：C:\Users\21397\Desktop\EG4D20\EG4D20.al
    下载文件：output/eg4d20_udp_loop.bit
    器件：EG4D20EG176；顶层：udp_transmit_test；PHY：YT8531。
    功能：ARP、ICMP echo（ping）、UDP 原样回传，固定千兆模式。
    电脑：192.168.50.1/24，UDP 6001。
    板子：192.168.50.2，MAC 02:00:00:00:00:02，UDP 6002。
    回传目标固定为电脑 192.168.50.1:6001，使用一发一收。

本次修复
    恢复 .al 中缺失的 30 个 HDL、管脚/时序约束和顶层模块配置。
    构建脚本的旧 D:/2026fpga 路径改为本机工程路径。
    仿真脚本支持 PATH 上的 Icarus，或 MODELSIM_BIN 指定的 ModelSim。
    本机默认 ModelSim 为 F:/win64；不依赖旧 E:/iverilog。
    保留已有 RTL 改动及原始版权头，本次未改变网络协议逻辑。
    修改前文件保存在桌面 bank/eg4d_udp_20261019/original。

本次重新验证的结果
    TD 6.2.168116 已完成综合、布局布线、时序检查和 bit 生成。
    Setup WNS +0.127 ns，Hold WNS +0.031 ns，TNS 均为 0。
    STA 覆盖率 99.97%，LUT 3768/19600，寄存器 3204/19600，BRAM9K 25/64，PLL 2/4。
    ModelSim 仿真通过异步 RX/TX、ARP、奇偶长度 ICMP、9 个 UDP 回包、
    地址/校验和/FCS 检查、坏 FCS 丢弃及后续包恢复。
    仿真绕过 PLL、RGMII DDR 和 PHY，不能替代实板测试。
    综合保留 FIFO RAM 输出初值被忽略的警告；使用复位和有效标记管理数据。
    仿真保留原始源码换行格式警告。
    output 内附报告和 SHA-256；完整日志位于桌面 bank/eg4d_udp_20261019。

上板测试
    1. 保持板子供电，将 output/eg4d20_udp_loop.bit 下载到 EG4D20。
       若下载到 SRAM，断电后需要重新下载。
    2. 板载 RJ45 直连电脑千兆网口，使用四对完整网线。
    3. 仅给对应有线网卡设置静态 IP 192.168.50.1、掩码 255.255.255.0，
       网关和 DNS 留空；保留 WLAN 配置。
    4. 在本工程目录打开 PowerShell，运行：
       powershell -ExecutionPolicy Bypass -File .\tools\check_network.ps1
       ping 192.168.50.2
       python .\tools\test_udp.py
    5. 验收：有线链路 1 Gbps；ARP 学到 02-00-00-00-00-02；ping 成功；
       UDP 20 包逐字节 PASS。允许对应 Python 的 UDP 6001 接收。

实板状态（2026-10-19 19:04 北京时间）
    已完成实板验收：以太网 Up / 1 Gbps，电脑 192.168.50.1/24。
    ARP：192.168.50.2 -> 02-00-00-00-00-02。
    ping：发送 4 包，收到 4 包，无丢包。
    UDP：20 包逐字节 PASS，长度覆盖 1/17/18/32/64/255/512/1024/1400/1472 字节。
    测试记录：output/hardware_test.log、output/hardware_udp.txt。
    用户确认板子已下载 192.168.50.2 版本；未读回板上 bit 的哈希。
    实板结果针对当前已加载程序，output 中新生成 bit 的离线验证单独记录。
    有线静态地址已设置，WLAN 和防火墙规则未修改。
    原网卡配置：桌面 bank/eg4d_udp_20261019/network_before.json。
    NI Domain Service 占用电脑 UDP 6001，测试中临时停止，测试后已恢复 Running。
    今后运行 UDP 测试前需先释放 6001 端口；不要同时启动占用该端口的程序。
    若需脚本配置地址，请在管理员 PowerShell 中运行 .\tools\setup_network.ps1。
    HANDOFF_20261019.md 为历史记录，当前状态以本文及 output/validation.json 为准。

复现
    仿真：python .\tests\run_gmii.py
    构建：powershell -ExecutionPolicy Bypass -File .\tools\build.ps1
    构建脚本调用本机 TD；可用 -TdExe 指定其他 TD 程序。
    tools/build.tcl 中 TD 专用命令使用本机绝对路径；移动工程前须更新。
    重建时会保留旧 bit，失败不会把旧文件作为本次新结果发布。

边界
    暂不支持 10/100M 自适应、DHCP、TCP、CNN 或双板图像传输。
    单项 ARP 缓存适用于电脑直连，不用于多主机并发或满速压力场景。
    RGMII 时序沿用本板参考约束，PHY strap 与采样相位仍需实板验证。
    PLL 使用 EG4 版本，勿混入同名 PH1 版本或仅凭变量名修改相位。

参考资料
    C:\Users\21397\Desktop\01_F01_FC01_EG4D
    03_demo/3_1_ex_soc_fpga/3_1_01_fpga_udp/01_udp_loop
