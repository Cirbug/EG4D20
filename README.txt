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
    D3-D6 为低电平点亮：D3/P112=PHY 链路，D4/P109=接收活动，D5/P104=发送活动，D6/P91=IP/MAC 接收错误（锁存到复位）。

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
    2026-10-26 旧版 CNN DDR CRC bit 的实板以太网验证：Realtek 链路 1 Gbps，板端 ping 成功；
    旧版 320x240 UDP 收图、DDR 写入及回读 CRC 另见下方 CNN 图像输入阶段记录；320x180 新版已完成实板验证。
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

EG4D20 CNN 图像输入阶段（cnn 分支）
    独立工程：D:\2026fpga\EG4D20\EG4D20_CNN_INPUT.al，顶层 cnn_image_input_top。
    当前阶段实现 PC UDP 收图、DDR 单帧写入、逐包 ACK，以及整帧 DDR 回读 CRC 校验；CNN 推理尚未实现。
    PC 十分类基准位于 cnn：OpenCV 从 320x180 帧中分割单字，统一为 28x28，再用 PyTorch 三层小 CNN 识别 0-9。
    训练前安装 GPU 版：python -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu130；再安装 python -m pip install numpy opencv-python-headless Pillow。
    训练命令：python cnn/train_digits.py --epochs 5；默认优先使用 CUDA，打印 PyTorch/CUDA 版本及 GPU 名称；无 GPU 时可换 CPU wheel。使用 torchvision MNIST 并报告独立 MNIST test 准确率。
    2026-10-26 PC 基准：PyTorch 2.14.1 CPU build，5 epoch，MNIST test accuracy=94.35%。电脑有 RTX 4070 Laptop GPU；这次用 CPU 是因为 CUDA wheel 约 2 GB 且下载极慢，训练脚本在安装 CUDA build 后会自动优先 GPU。
    OBS 分割检查：python cnn/segment_digits.py xuniji/ph1p35_obs_frame_320x180_gray.png --expect 10；默认 ROI=24,38,296,112，用于排除画面状态叠字。
    PC 预测：python cnn/predict_digits.py xuniji/ph1p35_obs_frame_320x180_gray.png --expect 10。
    该 OBS 帧单次输出 0123456784，末位手写 9 误判为 4；仅为一帧冒烟检查，不是摄像头准确率。该帧每个数字只有一个样本，不能当训练集结论；MNIST 准确率也不等于摄像头准确率。
    PC 模型和脚本不是 FPGA 推理实现；当前 bit 的实板验证范围仍只有 UDP 收图、DDR 写入及回读 CRC。
    官方板卡手册说明 EG4D20 内置 128 Mbit（16 MiB）、16-bit DDR SDRAM，最高 200 MHz。
    旧版 320x240 灰度输入为 76,800 bytes，已完成 2026-10-26 实板验证；其测试证据保留在下文。
    当前改版目标为 320x180（16:9）灰度图，共 57,600 bytes；DDR 回读 CRC 扫描 14,400 个 32-bit word。
    当前写入缓冲按 32-bit 组字，通过官方 EG4 DDR 控制器写入。
    本工程使用官方例程中的 ddr1_as_ram / ddr1_wrrd 及 EG_PHY_DDR_8M_16 接法。

    编译工程：D:\2026fpga\EG4D20\tools\build_cnn_input.tcl
    新版 build log 必须出现 EG4D20_CNN_320X180_BUILD_COMPLETE、时序通过且 bit 时间为本次构建，才可下载。
    旧版构建日志：D:\2026fpga\bank\eg4d20_cnn_input_20261025\fpga\build_ddr_crc_168.log
    旧版布线时序：SWNS +0.092 ns，HWNS +0.011 ns，STNS/HTNS 均为 0；LUT 5446/19600，BRAM9K 23/64，DSP 0/29。
    旧版已烧录并实测 bit：D:\2026fpga\EG4D20\xuniji\eg4d20_cnn_ddr_crc_check.bit（320x240）。
    新版构建日志：D:\2026fpga\bank\eg4d20_cnn_320x180_20261026\fpga\build_cnn_320x180.log。
    新版布线时序：Setup WNS +0.100 ns、Hold WNS +0.024 ns，TNS 均为 0；LUT 5443/19600、寄存器 4778/19600、BRAM9K 23/64、DSP 0/29。
    新版 bit：D:\2026fpga\EG4D20\xuniji\eg4d20_cnn_320x180.bit；SHA-256=D981556CB99E38C12C1588F49230EE0C2964650D6609F42EB7D7AD9A00ABB6CC。
    已完成离线综合布局布线及新版 320x180 实板 DDR CRC 验证。
    PC 有线网卡需设 192.168.50.1/24；板端固定 192.168.50.2:6002，PC 绑定 192.168.50.1:6001。
    PNG/JPEG/BMP 输入由发送工具转灰度、中心裁成 16:9 再缩放至 320x180；1920x1080 输入不会裁掉内容，也不会补黑边。
    训练使用完全相同的预处理。RAW 输入须已是 320x180 灰度，文件恰好 57,600 bytes；图片输入需安装 Pillow。
    发送命令：python D:\2026fpga\EG4D20\tools\send_cnn_image.py D:\2026fpga\EG4D20\xuniji\ph1p35_obs_frame_320x180_gray.png
    每包发出后等待板端 ACK，再发下一包；超时重发当前包，拒收时从帧首重发。
    40 个包，每包最多 1,456 个像素字节；最后一包 816 bytes。ACK status 0=普通包已写入，1=整帧 DDR 回读 CRC 匹配，2=拒收。
    最后一包成功后 PC 显示 FRAME VERIFIED；串口 115200 8N1 输出 DDR OK。校验失败时串口输出 DDR ERR，D6 点亮。
    D3/P112=PHY 链路，D4/P109=UDP RX 活动，D5/P104=TX 活动，D6/P91=接收/DDR 错误；LED 均低电平点亮。
    旧版先前曾收到 FRAME OK；这只证明 DDR 写事务完成，不证明回读正确。
    2026-10-26 旧版实测：COM11 收到 DDR OK；测试帧 76,800 bytes，53/53 包 ACK，末包 status=1，PC 显示 FRAME VERIFIED。
    本次测试使用 frame_id=54572，bit SHA-256=4621EEEBA5287755F48C7AD5BCDB46FF2A654F27D3070C75B5775B603F8AAFCF。
    2026-10-26 新版实测：frame_id=36605，OBS 图像 57,600 bytes，40/40 包 ACK，末包 status=1；PC 显示 FRAME VERIFIED，COM11 收到 DDR OK。
    新版 bit SHA-256 与上方记录一致；本次实测只证明图像接收、DDR 写入和回读 CRC，不代表 FPGA 已运行 CNN 分类。

    官方本地 DDR 参考：
    D:\2026fpga\.DOC\01_F01_FC01_EG4D\03_demo\3_1_ex_soc_fpga\3_1_01_fpga_base\24_inside_sdram_test\fdma_sdram_test
    重点看 uisrc\01_rtl\eg4d_sram_fdma_test.v 的控制器/DDR PHY连接，以及 uisrc\03_ip\uieg4d_dram 中的官方控制器。
    官方以太网、图像处理例程分别位于 3_1_ex_soc_fpga\3_1_01_fpga_udp 和 3_2_ex_fpga_image。

    网络 CNN 参考（仅借鉴架构，不能直接生成 EG4D20/TD bit）：
    https://github.com/m-kvlk/FPGA-8bit-Quantized-CNN-Accelerator：MAX10/DE10-Lite 的 8-bit、FSM 顺序执行、BRAM 权重和 32-bit 累加器示例；可参考低资源复用结构。
    https://github.com/Xilinx/finn：量化网络的数据流式 FPGA 架构和 examples；工具链主要面向 AMD/Xilinx，不是安路 TD 移植包。
    https://github.com/fastmachinelearning/hls4ml：含 3-layer CNN 示例和 HLS 后端；可参考定点化/复用策略，不会直接输出本工程可用的 Anlogic RTL。
    本板仅 29 个 DSP，后续网络要量化并复用少量 MAC；需用训练集定标、Python golden model 与 RTL 位精确结果验证，再判断分类效果。

    PC 协议工具测试：python D:\2026fpga\EG4D20\tests\test_cnn_udp_sender.py
    RTL 输入/DDR 写调度仿真：python D:\2026fpga\EG4D20\tests\run_cnn_rtl.py
