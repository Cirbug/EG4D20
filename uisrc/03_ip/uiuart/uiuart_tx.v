
/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2024/8/16
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) _n activ low
*4) _dg debug signal 
*5) _r delay or register
*6) _s state mechine
*********************************************************************/
`timescale 1ns / 1ns

module uiuart_tx#
(
 parameter integer BAUD_DIV     = 216 //设置采样系数(时钟/采样率-1),便于外部修改
)
(
	input       I_clk,
    input       I_uart_rstn,
	input       I_uart_wreq,//发送数据请求
    input [7:0] I_uart_wdata,//发送数据
    output      O_uart_wbusy,//发送状态忙,即是否正在发送数据
	output      O_uart_tx//发送总线
);

localparam UART_LEN = 4'd10;//设置uart发送的bit数量为10,代表1bit起始位,8bits数据,1bit停止位
wire        bps_en ;//发送使能
reg         uart_wreq_r   = 1'b0;//寄存一次发送数据请求
reg         bps_start_en    = 1'b0;//波特率计数器启动使能，也是发送启动使能
reg [13:0]  baud_div        = 14'd0;//波特率计数器
reg [9 :0]  uart_wdata_r  = 10'h3ff;//寄存10bit数据(1+8+1)
reg [3 :0]  tx_cnt          = 4'd0;//计数已经发送出多少位数据

assign O_uart_tx = uart_wdata_r[0];//从低位开始输出,且总线上的数据始终为uart_wdata_r[0]

assign O_uart_wbusy = bps_start_en;//发送启动使能有效时,处于发送忙状态

// uart tx Baud rate divider
assign bps_en = (baud_div == BAUD_DIV);//产生一次发送使能信号,条件是baud_div == BAUD_DIV,波特率计数达成

//波特率计数器
always@(posedge I_clk )begin
    if((I_uart_rstn== 1'b0) || (I_uart_wreq==1'b1&uart_wreq_r==1'b0))begin
        baud_div <= 14'd0;
    end
    else begin
        if(bps_start_en && baud_div < BAUD_DIV)//发送使能为1时,进行波特率计数
            baud_div <= baud_div + 1'b1;
        else 
            baud_div <= 14'd0;
    end
end

always@(posedge I_clk)begin
    uart_wreq_r <= I_uart_wreq;//寄存一次发送请求
end

//UART transmit enable ,Support gapless continuous enable
always@(posedge I_clk)begin
    if(I_uart_rstn == 1'b0)
        bps_start_en    <= 1'b0;
    else if(I_uart_wreq==1'b1&uart_wreq_r==1'b0) 
        bps_start_en    <= 1'b1;
    else if(tx_cnt == UART_LEN)
        bps_start_en    <= 1'b0;
    else 
        bps_start_en    <= bps_start_en;
end

//UART transmiter BIT counter
always@(posedge I_clk)begin
    if(((I_uart_rstn== 1'b0) || (I_uart_wreq==1'b1&uart_wreq_r==1'b0))||(tx_cnt == 10))
        tx_cnt <=4'd0;//复位、启动发送、发送完成,重置tx_cnt
    else if(bps_en && (tx_cnt < UART_LEN))
        tx_cnt <= tx_cnt + 1'b1;//tx_cnt计数器,每发送一个bit加1
end

//uart send controller shift control
always@(posedge I_clk)begin
    if((I_uart_wreq==1'b1&uart_wreq_r==1'b0)) 
        //寄存需要发送的数据,包括1bit起始位,8bits数据,1bit停止位
        uart_wdata_r  <= {1'b1,I_uart_wdata[7:0],1'b0};
    else if(bps_en && (tx_cnt < (UART_LEN - 1'b1)))//shift 9 bits
        //并串转换，将并行数据依次传输
        uart_wdata_r <= {uart_wdata_r[0],uart_wdata_r[9:1]};
    else 
        uart_wdata_r <= uart_wdata_r;

end   

endmodule