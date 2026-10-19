EG4D20 与电脑千兆网口联通基线
更新：2026-10-18

用途
    使用板载 YT8531 PHY，先完成 ARP、ping 和 UDP 原样回传。
    这是独立 EG4D20 工程，不修改 PH1P35 摄像头工程。
    当前固定千兆模式；要求电脑千兆网口和全四对网线。
    暂未实现 10/100M 自适应、TCP、DHCP、CNN 或主副板图像传输。

打开工程
    D:\2026fpga\EG4D20\EG4D20.al
    顶层：udp_transmit_test
    器件：EG4D20EG176
    使用工具：TD 6.2.168116。
    如果 TD 原来打开的是空工程，请关闭后重新打开本文件，不要保存旧的空源文件列表覆盖它。
    原始空工程备份：D:\2026fpga\bank\eg4d_udp_20261018\EG4D20.original.al

IP 核配置
    现在已加入所需 HDL，不需要再生成 Ethernet MAC IP 或 MCU IP。
    MAC/ARP/IPv4/ICMP/UDP 由开发板配套例程的 Verilog 实现。
    FIFO 和 shift RAM 使用配套可综合源码，不要重复添加同名 IP。
    两个 PLL 已提供正确 EG4 版本 .v 和对应 .ipc；工程直接编译 .v。

    pll（al_ip/pll.v）：
        输入 25 MHz；Normal feedback / CLKC0；Reset 和 Lock 端口启用。
        CLK0 = 125 MHz，0°，发送和用户逻辑使用。
        CLK1 = 125 MHz，配置目标 30°，生成文件实际 28.125°，本顶层未使用。
        CLK2 = 25 MHz，0°，PHY 复位计时使用。
    PLL2（al_ip/PLL2.v）：
        输入来自 PHY RXC，千兆时 125 MHz；Normal feedback / CLKC0。
        CLK0 = 125 MHz，0°，GMII 接收使用。
        CLK1 = 125 MHz，0°，RGMII 输入 DDR 使用。
        Reset 和 Lock 端口启用；沿用配套 RGMII 接线。

    注意：配套资料有同名 PH1 版本 PLL 文件，本工程选用 EG_PHY_PLL 版本。
    不要根据旧变量 clk_125_90 的名字把发送时钟擅自改成 90°。
    PHY 内部延迟与 FPGA 时钟相位必须配套；本版先沿用该板参考工程的时序设置。
    相关厂商芯片资料：
    https://en.motor-comm.com/product/ethernet-physical-layer-chip
    本版没有 MDIO 配置模块，依赖板载 PHY 上电 strap；板上时序仍需实际验证。

已核对的管脚（均 LVCMOS33）
    25 MHz 系统时钟 P61；PHY RESET_N P62。
    RXC P63；RX_CTL P72；RXD[0..3] P73/P74/P75/P76。
    TXC P77；TX_CTL P78；TXD[0..3] P79/P81/P82/P83。
    实际约束文件：uisrc/04_pin/fpga_pin.adc。

电脑设置与下载后测试
    1. EG4D20 上电，板载 RJ45 用网线接电脑 Realtek 千兆网口。
    2. 下载编译验证通过后的 eg4d20_udp_loop.bit 到 EG4D20。
       成品位置：D:\2026fpga\bank\eg4d_udp_20261018\fpga\eg4d20_udp_loop.bit
       应先确认 build.log 包含 EG4D20_UDP_BUILD_COMPLETE，且 bit 时间为本次构建。
    3. 仅给电脑有线网卡设置静态 IPv4：
           IP        192.168.50.1
           子网掩码  255.255.255.0
           网关/DNS 留空
       保留 WLAN 设置。避免 192.168.137.x：该电脑虚拟热点已占用这个网段。
       FPGA 固定 IP 192.168.50.2，MAC 02:00:00:00:00:02。
    4. 运行只读诊断：
           powershell -ExecutionPolicy Bypass -File D:\2026fpga\EG4D20\tools\check_network.ps1
       有线链路应显示 Up / 1 Gbps。未连接时先检查电源、网线和下载结果。
    5. 测试 ping：
           ping 192.168.50.2
    6. 测试 UDP：
           python D:\2026fpga\EG4D20\tools\test_udp.py
       电脑绑定 6001，发送到板子 6002，板子回到固定电脑 IP 的 6001。
       PASS 表示返回字节、长度、来源 IP 和端口全部一致。
       超时且链路正常时，检查有线网卡 IP 与 Python/UDP 6001 的防火墙权限。
       不需要关闭整个 Windows 防火墙。

限制
    使用一发一收，不要同时开多个 UDP 发送器或进行持续满速压力测试。
    例程回传目标固定为 192.168.50.1:6001，不是自动回到任意发送方。
    ARP 缓存简化为一个条目，用于电脑直连；暂不支持同时保留多台主机的 MAC 缓存。
    软件测得的 RTT 包括电脑调度，不能当作 FPGA 内部处理延迟。
    MAC 速率 1 Gbps 不等于已测得的有效吞吐率。
    该参考栈不是完整通用网络栈；暂不承诺 IP 分片、IP options、任意 ping 长度或拥塞恢复。

验证与修改
    2026-10-18 最终构建：LUT 3768/19600，寄存器 3204/19600，BRAM9K 25/64，
    BRAM32K 0/16，DSP 0/29，PLL 2/4。
    按当前板级参考约束，布局布线后 Setup WNS +0.127 ns、Hold WNS +0.031 ns，TNS 均为 0。
    已通过：异步 RX/TX 时钟、ARP 应答、奇偶长度 ping、9 个 UDP 包逐字节比对、
    IPv4/ICMP 校验和、发送帧 CRC、错误 CRC 丢弃，以及坏帧后正常包恢复。
    尚未下载板子或完成电脑实网联通验证；最近电脑 Realtek 仍显示 Disconnected。
    tests/run_gmii.py 从 Python 独立构造网络包，经实际 MAC/ARP/IP/UDP RTL 仿真。
    PLL、物理 DDR 和 PHY 在该仿真中绕过，所以通过仿真不等于实板联通。
    修正了 MAC TX RAM 元数据直接进入长比较链的问题，增加一拍缓存。
    ARP 写缓存输入加寄存器，缩短地址比较路径。
    PC 直连版把原四项关联 ARP 缓存改为单项缓存，进一步减少逻辑和路径长度。
    MAC RX 将 CRC 错误标记与帧信息一起跨 FIFO 域，错误帧读空但不交给上层。
    ICMP echo checksum 改为 Type/Code 字段增量更新，避免奇数长度尾字节错误。
    修正 PAUSE FIFO 的未定义 reset 接线，改接 I_mac_reset。
    补齐 FIFO 未使用写端数据常量、PLL reset 的 1 bit 常量，消除未驱动/位宽告警。
    删除参考 SDC 中 TD 不接受且原本忽略的四条 -1 multicycle 设置。
    时钟自动推导改用 TD 当前支持的 derive_clocks。
    保留米联客、安路源码版权头；参考源码仅按其原始许可/说明使用。

重新编译
    PowerShell：
    & 'F:/AnlogicFpga/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe' 'D:/2026fpga/EG4D20/tools/build.tcl'
    脚本先检查 setup/hold，再生成 bit；日志即使失败也可能返回退出码 0，必须检查完成标记。
    所有大型编译文件保存在 D:\2026fpga\bank\eg4d_udp_20261018\fpga。
    仿真复现：python D:\2026fpga\EG4D20\tests\run_gmii.py
    仿真数据保存在同一 bank 目录的 sim 子目录。

参考资料
    D:\2026fpga\.DOC\01_F01_FC01_EG4D\02_hardware
    D:\2026fpga\.DOC\01_F01_FC01_EG4D\03_demo\3_1_ex_soc_fpga\3_1_01_fpga_udp\01_udp_loop
