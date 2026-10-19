`timescale 1ns / 1ps



module udp_transmit_test(

input  wire        I_sys_clk,			//系统时钟输入

output wire        O_phy_rst,			//以太网芯片复位信号，低电平有效 

   

input  wire[3:0]   I_a_rgmii_rxd,   	//RGMII输入数据

input  wire        I_a_rgmii_rx_ctl,	//RGMII输入数据有效信号

input  wire        I_a_rgmii_rxc,   	//RGMII接收数据时钟

output wire[3:0]   O_a_rgmii_txd,   	//RGMII输出数据 

output wire        O_a_rgmii_tx_ctl, 	//RGMII输出数据有效信号

output wire        O_a_rgmii_txc    	//RGMII发送数据时钟    

    );





wire [7:0]	gmii_tdata;

wire        gmii_tvalid;

wire [7:0]	gmii_rdata;

wire        gmii_rvalid;
wire gmii_rclk, ip_rx_error, mac_rx_error;



wire       	R_udp_valid;

wire [7:0]	R_udp_data;

wire [15:0] R_udp_len;

wire [15:0] R_udp_src_port;





wire        W_udp_busy;

reg         W_udp_req;

reg         W_udp_valid;

wire [7:0]  W_udp_data;

reg  [15:0] W_udp_len;

reg         W_udp_data_read;



wire [11:0] udp_pkg_buf_cnt;

reg [11:0]  fifo_read_data_cnt;

reg [1:0]   STATE;



wire        pll_locked;



localparam  WAIT_UDP_DATA 	= 2'd0;

localparam  WAIT_ACK 		= 2'd1;

localparam  SEND_UDP_DATA 	= 2'd2;

localparam  DELAY 			= 2'd3;



parameter  WAIT_UDP_READY = 0;

parameter  WAIT_UDP_ACK = 1;

parameter  SEND_DATA = 2;

parameter	WAIT_DONE = 3;

reg	[15:0]	test_data;

reg	[15:0]	cnt;



wire O_phyrst_done;

wire clk_25,clk_125,clk_125_90;

wire phy_rst;

assign O_phy_rst = phy_rst;



wire         reset   =	~O_phyrst_done;



uiphyrst#

(

.CLK_FREQ(32'd25_000_000)         	//时钟参数

)

uiphyrst_inst                       //设置分频系数，降低流水灯的变化速度

(                                   //该参数可以由上层调用时修改

.I_CLK(clk_25),                   	//系统时钟信号

.I_rstn(pll_locked),               //全局复位

.I_phyrst(pll_locked),             //复位时钟

.O_phyrst(phy_rst),               //复位输出

.O_phyrst_done(O_phyrst_done)

);



pll pll0_inst(

.refclk		(I_sys_clk),

.reset	(1'b0),

.extlock		(pll_locked),

.clk0_out	(clk_125),

.clk1_out	(clk_125_90),

.clk2_out	(clk_25)

);

//=================================================

// --              		 测速

//=================================================



/*

always@(posedge clk_125 or posedge reset)begin

   if(reset) begin

		W_udp_req 		<= 1'b0;

		W_udp_valid 		<= 1'b0;

		W_udp_len 		<= 16'd0;

		test_data 			<= 8'd0;

		cnt					<=	'd0;

		STATE 				<= WAIT_UDP_READY;

		

	end

	else begin	

		case(STATE)

			WAIT_UDP_READY:begin

				if(~W_udp_busy) begin

					W_udp_req 			<= 1'b1;

					STATE 					<= WAIT_UDP_ACK;

				end

				else begin

					W_udp_req 			<= 1'b0;

					STATE 					<= WAIT_UDP_READY;

				end

			end

			WAIT_UDP_ACK:begin

				if(W_udp_busy) begin

					W_udp_len 			<= 16'd1472;

					W_udp_valid 			<= 1'b1;

					W_udp_req 			<= 1'b0;				

					STATE 					<= SEND_DATA;

				end

				else

					STATE <= WAIT_UDP_ACK;

			end

			SEND_DATA:begin

				if(test_data == 16'd1471) begin

					W_udp_valid 			<= 1'b0;

					W_udp_len 			<= 16'd0;

					test_data				<= 0;

					STATE 					<= WAIT_DONE;

				end

				else begin

					W_udp_valid 			<= 1'b1;

					test_data 				<= test_data + 1'b1;

					STATE 					<= SEND_DATA;

				end

			end

			WAIT_DONE:begin

					STATE	<=	WAIT_UDP_READY;

			end

		endcase

	end

end



assign	W_udp_data	=	test_data[7:0];

*/



//=================================================

// --              		 回环

//=================================================



udp_pkg_buf #(

.DATA_WIDTH_W(8), 

.DATA_WIDTH_R(8)  , 

.ADDR_WIDTH_W(12) , 

.ADDR_WIDTH_R(12) , 

.SHOW_AHEAD_EN(1'b1), 

.OUTREG_EN("NOREG")

) 

udp_pkg_buf_inst(

.rst	(reset),  //asynchronous port,active hight

.clkw	(clk_125),  //write clock

.we		(R_udp_valid),  //write enable,active hight

.di		(R_udp_data),  //write data

.clkr	(clk_125),  //read clock

.re		(W_udp_valid),  //read enable,active hight

.dout	(W_udp_data),  //read data

.wrusedw(),  //stored data number in fifo

.rdusedw(udp_pkg_buf_cnt) //available data number for read      

) ;





always@(posedge clk_125 or posedge reset)begin

	if(reset) 

		W_udp_len <= 16'd0;

	else begin 

		if(R_udp_valid)

		    W_udp_len <= R_udp_len; //读到的数据长度

		else

			W_udp_len <= W_udp_len;

	end

end



always@(posedge clk_125 or posedge reset)begin

	if(reset) begin

		W_udp_req 			<= 1'b0;

		W_udp_data_read 	<= 1'b0;

		W_udp_valid 		<= 1'b0;

		fifo_read_data_cnt 	<= 12'd0;

		STATE 				<= WAIT_UDP_DATA;

	end

	else begin

		case(STATE)

			WAIT_UDP_DATA:begin	

				if((udp_pkg_buf_cnt > 12'd0) && (~R_udp_valid) && ~W_udp_busy) begin//当udp_layer写操作不忙，并且udp_layer读操作完成，发起回传写操作

					W_udp_req 			<= 1'b1;		//请求发送udp写操作

					STATE 				<= WAIT_ACK;

				end

				else begin

					W_udp_req 			<= 1'b0;

					STATE 				<= WAIT_UDP_DATA;

				end

			end

			WAIT_ACK:begin

				if(W_udp_busy) begin					//等待udp_layer写操作变忙，代表可以发送写操作的数据

					W_udp_req 			<= 1'b0;		//清除本次写请求

					W_udp_data_read 	<= 1'b1;		//从fifo中读数据

					W_udp_valid 		<= 1'b1;		//写操作有效

					STATE 				<= SEND_UDP_DATA;

				end

				else begin

					W_udp_req 			<= 1'b1;		

					W_udp_data_read 	<= 1'b0;

					W_udp_valid 		<= 1'b0;

					STATE 				<= WAIT_ACK;

				end

			end

			SEND_UDP_DATA:begin

				if(fifo_read_data_cnt == (W_udp_len - 1'b1)) begin	//发送指定计数器长度的数据

					fifo_read_data_cnt 	<= 12'd0;

					W_udp_valid 		<= 1'b0;

					W_udp_data_read 	<= 1'b0;

					STATE 				<= WAIT_UDP_DATA;

				end

				else begin

					fifo_read_data_cnt <= fifo_read_data_cnt + 1'b1;//发送指定计数器长度的数据

					W_udp_valid 		<= 1'b1;					//从fifo中读数据

					W_udp_data_read 	<= 1'b1;					//写操作有效			

					STATE 				<= SEND_UDP_DATA;

				end						

			end

			DELAY:begin

				if(R_udp_valid)

					STATE 				<= WAIT_UDP_DATA;

				else

					STATE 				<= DELAY;

			end

			default: STATE <= WAIT_UDP_DATA;

		endcase

	end

end







//UDP协议栈	 

uiudp_stack #

(	

.CRC_GEN_EN         	(1'b1),				//使能MAC层CRC校验

.INTER_FRAME_GAP    	(4'd12)				//插入帧间隔，2帧之间最少需要IFGmini=96bit/speed,比如1000M 96ns 100M 960ns 10M 9600ns，对于1000M 125M发送时钟，为12

)

udp_stack_inst

(

.I_uclk					(clk_125		), 

.I_reset				(reset			), 



.I_mac_local_addr  		(48'h020000000002),//本地MAC地址	

.I_udp_local_port     	(16'd6002		), //本地端口号

.I_ip_local_addr   		({8'd192, 8'd168,8'd50, 8'd2}		), //本地ip地址



.I_udp_dest_port		(16'd6001		), //目的端口

.I_ip_dest_addr	   		({8'd192, 8'd168,8'd50, 8'd1}	), //目的IP地址



.O_W_udp_busy			(W_udp_busy		), //udp写忙

.I_W_udp_req		   	(W_udp_req		), //udp写数据请求

.I_W_udp_valid 	   		(W_udp_valid	), //udp写数据有效

.I_W_udp_data			(W_udp_data		), //udp写数据

.I_W_udp_len	      	(W_udp_len		), //udp写数据长度



.O_R_udp_valid	      	(R_udp_valid	), //udp读数据有效

.O_R_udp_data			(R_udp_data		), //udp读数据

.O_R_udp_len 			(R_udp_len		), //udp读数据长度

.O_R_udp_src_port		(R_udp_src_port	), //udp读数据的远端主机端口号



.I_gmii_rclk           	(gmii_rclk		), //mac层接收GMII时钟

.I_gmii_rvalid	      	(gmii_rvalid	), //mac层接收GMII数据有效

.I_gmii_rdata			(gmii_rdata		), //mac层接收GMII数据



.I_gmii_tclk         	(clk_125		), //mac层发送GMII时钟

.O_gmii_tvalid	    	(gmii_tvalid	), //mac层发送GMII数据有效

.O_gmii_tdata			(gmii_tdata		), //mac层发送GMII数据有

.O_ip_rerror			(ip_rx_error	), //接收数据IP层数据校验错误

.O_mac_rerror			(mac_rx_error	)  //接收数据MAC层数据校验错误

);





rgmii_interface rgmii_interface_inst(



.speed_10_100	(1'b0				),   // 指示当前运行速度为10/100 或者1000

.gmii_tx_clk_d	(clk_125			),   //RGMII发送时序调整，当PHY 接收来自FPGA的TX信号，没有使用内部2ns延迟情况需要在fpga端设置2ns延迟 

.gmii_tx_reset_d(reset				),  

.gmii_tx_reset	(reset				),

.gmii_tx_clk	(clk_125			),     

.gmii_txd		(gmii_tdata			),

.gmii_tx_en		(gmii_tvalid		),

.gmii_tx_er		(1'b0					),



.gmii_rx_reset	(reset				),

.gmii_rx_clk	(gmii_rclk			),    //output： 125mhz（1gbps） 25mhz(100mbps)    2.5mhz(10mbps)

.gmii_rxd		(gmii_rdata			),

.gmii_rx_dv		(gmii_rvalid		),

.gmii_rx_er		(					),



// 以下端口是RGMII物理接口：这些端口将位于FPGA的引脚上

.rgmii_txd		(O_a_rgmii_txd		),

.rgmii_tx_ctl	(O_a_rgmii_tx_ctl	),

.rgmii_txc		(O_a_rgmii_txc		),



.rgmii_rxd		(I_a_rgmii_rxd		),

.rgmii_rx_ctl	(I_a_rgmii_rx_ctl	),

.rgmii_rxc		(I_a_rgmii_rxc		),

.gmii_crs		(					),

.gmii_col		(					),

// 以下信号为RGMII状态信号

.link_status	(					),

.clock_speed	(					),

.duplex_status	(					)

);







endmodule