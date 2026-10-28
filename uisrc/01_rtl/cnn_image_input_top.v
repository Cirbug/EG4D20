`timescale 1ns / 1ps

module cnn_image_input_top(
    input  wire       I_sys_clk,
    input  wire [3:0] I_a_rgmii_rxd,
    input  wire       I_a_rgmii_rx_ctl,
    input  wire       I_a_rgmii_rxc,
    output wire [3:0] O_a_rgmii_txd,
    output wire       O_a_rgmii_tx_ctl,
    output wire       O_a_rgmii_txc,
    output wire       O_phy_rst,
    output wire [3:0] O_led,
    output wire       O_uart_tx
);
    wire clk_125;
    wire clk_125_90;
    wire clk_25;
    wire pll_locked;
    wire phy_reset_done;
    wire reset = ~phy_reset_done;

    wire ddr_clk0;
    wire ddr_clk90;
    wire ddr_clk180;
    wire ddr_pll_locked;
    wire ddr_init_done;
    wire ddr_init_ref_vld;
    wire ddr_busy;
    wire ddr_rd_en;
    wire [31:0] ddr_rd_data;
    wire ddr_rd_req;
    wire [22:0] ddr_rd_addr;
    wire ddr_wr_en;
    wire [22:0] ddr_wr_addr;
    wire [1:0] ddr_wr_dm;
    wire [31:0] ddr_wr_data;
    wire [11:0] ddr_addr;
    wire [1:0] ddr_ba;
    wire [1:0] ddr_dm;
    wire ddr_clk;
    wire ddr_clkn;
    wire ddr_cke;
    wire ddr_cs_n;
    wire ddr_ras_n;
    wire ddr_cas_n;
    wire ddr_we_n;
    wire [15:0] ddr_dq;
    wire [1:0] ddr_dqs;

    pll pll0_inst(
        .refclk(I_sys_clk),
        .reset(1'b0),
        .extlock(pll_locked),
        .clk0_out(clk_125),
        .clk1_out(clk_125_90),
        .clk2_out(clk_25)
    );

    ddr_pll ddr_pll_inst(
        .refclk(I_sys_clk),
        .reset(1'b0),
        .extlock(ddr_pll_locked),
        .clk0_out(ddr_clk0),
        .clk1_out(ddr_clk90),
        .clk2_out(ddr_clk180),
        .clk3_out(),
        .clk4_out()
    );

    uiphyrst #(
        .CLK_FREQ(32'd25_000_000)
    ) uiphyrst_inst (
        .I_CLK(clk_25),
        .I_rstn(pll_locked),
        .I_phyrst(pll_locked),
        .O_phyrst(O_phy_rst),
        .O_phyrst_done(phy_reset_done)
    );

    ddr1_as_ram #(
        .self_refresh_open(1'b0)
    ) u_ddr_controller (
        .Clk0(ddr_clk0),
        .Clk90(ddr_clk90),
        .Clk180(ddr_clk180),
        .Rst(~ddr_pll_locked),
        .Sdr_init_done(ddr_init_done),
        .Sdr_init_ref_vld(ddr_init_ref_vld),
        .Sdr_busy(ddr_busy),
        .App_ref_req(1'b0),
        .App_wr_en(ddr_wr_en),
        .App_wr_addr(ddr_wr_addr),
        .App_wr_dm(ddr_wr_dm),
        .App_wr_din(ddr_wr_data),
        .App_rd_en(ddr_rd_req),
        .App_rd_addr(ddr_rd_addr),
        .Sdr_rd_en(ddr_rd_en),
        .Sdr_rd_dout(ddr_rd_data),
        .CLK(ddr_clk),
        .CLKN(ddr_clkn),
        .CKE(ddr_cke),
        .CS_N(ddr_cs_n),
        .RAS_N(ddr_ras_n),
        .CAS_N(ddr_cas_n),
        .WE_N(ddr_we_n),
        .BA(ddr_ba),
        .ADDR(ddr_addr),
        .DM(ddr_dm),
        .DQ(ddr_dq),
        .DQS(ddr_dqs)
    );

    EG_PHY_DDR_8M_16 u_ddr_phy (
        .clk(ddr_clk),
        .clk_n(ddr_clkn),
        .ras_n(ddr_ras_n),
        .cas_n(ddr_cas_n),
        .we_n(ddr_we_n),
        .cs_n(ddr_cs_n),
        .addr(ddr_addr),
        .ba(ddr_ba),
        .dq(ddr_dq),
        .ldqs(ddr_dqs[0]),
        .udqs(ddr_dqs[1]),
        .ldm(ddr_dm[0]),
        .udm(ddr_dm[1]),
        .cke(ddr_cke)
    );

    wire udp_tx_busy;
    wire udp_tx_req;
    wire udp_tx_valid;
    wire [7:0] udp_tx_data;
    wire [15:0] udp_tx_len;
    wire udp_rx_valid;
    wire [7:0] udp_rx_data;
    wire [15:0] udp_rx_len;
    wire [15:0] udp_rx_src_port;
    wire [7:0] gmii_tx_data;
    wire gmii_tx_valid;
    wire [7:0] gmii_rx_data;
    wire gmii_rx_valid;
    wire gmii_rx_clk;
    wire phy_link_status;
    wire ip_rx_error;
    wire mac_rx_error;

    wire image_pixel_valid;
    wire [7:0] image_pixel_data;
    wire image_frame_start;
    wire image_frame_complete;
    wire [31:0] image_frame_crc32;
    reg frame_complete_toggle;
    wire ddr_writer_idle;
    wire ddr_writer_overflow;
    wire [31:0] ddr_words_written;
    wire [31:0] ddr_busy_timeouts;
    wire ack_start;
    wire [15:0] ack_frame_id;
    wire [15:0] ack_packet_index;
    wire [7:0] ack_status;
    wire ack_tx_done;
    wire ack_tx_busy;
    wire [31:0] accepted_packets;
    wire [31:0] rejected_packets;
    wire ddr_check_done;
    wire ddr_check_pass;
    wire frame_check_done_125;
    wire frame_check_pass_125;
    wire digit0_done;
    wire [3:0] digit0_class;
    wire digit0_busy;

    cnn_udp_image_rx u_image_rx (
        .clk(clk_125),
        .rst(reset),
        .udp_valid(udp_rx_valid),
        .udp_data(udp_rx_data),
        .udp_len(udp_rx_len),
        .udp_src_port(udp_rx_src_port),
        .writer_idle(ddr_writer_idle),
        .frame_check_done(frame_check_done_125),
        .frame_check_pass(frame_check_pass_125),
        .ack_done(ack_tx_done),
        .pixel_valid(image_pixel_valid),
        .pixel_data(image_pixel_data),
        .frame_start(image_frame_start),
        .frame_complete(image_frame_complete),
        .ack_start(ack_start),
        .ack_frame_id(ack_frame_id),
        .ack_packet_index(ack_packet_index),
        .ack_status(ack_status),
        .frame_crc32(image_frame_crc32),
        .accepted_packets(accepted_packets),
        .rejected_packets(rejected_packets)
    );

    cnn_ddr_frame_writer u_frame_writer (
        .wr_clk(clk_125),
        .rd_clk(ddr_clk0),
        .rst(reset | ~ddr_pll_locked),
        .pixel_valid(image_pixel_valid),
        .pixel_data(image_pixel_data),
        .frame_start(image_frame_start),
        .ddr_init_done(ddr_init_done),
        .ddr_busy(ddr_busy),
        .app_wr_en(ddr_wr_en),
        .app_wr_addr(ddr_wr_addr),
        .app_wr_dm(ddr_wr_dm),
        .app_wr_din(ddr_wr_data),
        .writer_idle(ddr_writer_idle),
        .overflow(ddr_writer_overflow),
        .words_written(ddr_words_written),
        .busy_timeouts(ddr_busy_timeouts)
    );

    cnn_ddr_frame_crc_check u_ddr_frame_crc_check (
        .clk(ddr_clk0),
        .rst(reset | ~ddr_pll_locked),
        .frame_start_toggle(frame_complete_toggle),
        .frame_crc32(image_frame_crc32),
        .ddr_init_done(ddr_init_done),
        .ddr_busy(ddr_busy),
        .app_rd_en(ddr_rd_req),
        .app_rd_addr(ddr_rd_addr),
        .ddr_rd_valid(ddr_rd_en),
        .ddr_rd_data(ddr_rd_data),
        .check_done(ddr_check_done),
        .check_pass(ddr_check_pass)
    );

    cnn_frame_digit0_pipe u_digit0_pipe (
        .capture_clk(clk_125),
        .infer_clk(clk_25),
        .rst(reset),
        .frame_start(image_frame_start),
        .pixel_valid(image_pixel_valid),
        .pixel_data(image_pixel_data),
        .frame_complete(image_frame_complete),
        .digit_done(digit0_done),
        .digit_class(digit0_class),
        .digit_busy(digit0_busy)
    );

    cnn_udp_ack_tx u_ack_tx (
        .clk(clk_125),
        .rst(reset),
        .start(ack_start),
        .frame_id(ack_frame_id),
        .packet_index(ack_packet_index),
        .status(ack_status),
        .udp_busy(udp_tx_busy),
        .udp_req(udp_tx_req),
        .udp_valid(udp_tx_valid),
        .udp_data(udp_tx_data),
        .udp_len(udp_tx_len),
        .done(ack_tx_done),
        .busy(ack_tx_busy)
    );

    reg ddr_check_done_toggle;
    reg ddr_check_pass_hold;
    reg check_done_meta_125;
    reg check_done_sync_125;
    reg check_done_seen_125;
    reg check_pass_meta_125;
    reg check_pass_sync_125;
    reg check_complete_toggle_125;
    reg check_toggle_meta_25;
    reg check_toggle_sync_25;
    reg check_toggle_seen_25;
    reg check_pass_meta_25;
    reg check_pass_sync_25;
    wire uart_check_done = check_toggle_sync_25 ^ check_toggle_seen_25;

    always @(posedge clk_125 or posedge reset) begin
        if (reset)
            frame_complete_toggle <= 1'b0;
        else if (image_frame_complete)
            frame_complete_toggle <= ~frame_complete_toggle;
    end

    always @(posedge ddr_clk0 or posedge reset) begin
        if (reset) begin
            ddr_check_done_toggle <= 1'b0;
            ddr_check_pass_hold <= 1'b0;
        end else if (ddr_check_done) begin
            ddr_check_done_toggle <= ~ddr_check_done_toggle;
            ddr_check_pass_hold <= ddr_check_pass;
        end
    end

    always @(posedge clk_125 or posedge reset) begin
        if (reset) begin
            check_done_meta_125 <= 1'b0;
            check_done_sync_125 <= 1'b0;
            check_done_seen_125 <= 1'b0;
            check_pass_meta_125 <= 1'b0;
            check_pass_sync_125 <= 1'b0;
            check_complete_toggle_125 <= 1'b0;
        end else begin
            check_done_meta_125 <= ddr_check_done_toggle;
            check_done_sync_125 <= check_done_meta_125;
            check_done_seen_125 <= check_done_sync_125;
            check_pass_meta_125 <= ddr_check_pass_hold;
            check_pass_sync_125 <= check_pass_meta_125;
            if (frame_check_done_125)
                check_complete_toggle_125 <= ~check_complete_toggle_125;
        end
    end

    assign frame_check_done_125 = check_done_sync_125 ^ check_done_seen_125;
    assign frame_check_pass_125 = check_pass_sync_125;

    always @(posedge clk_25 or posedge reset) begin
        if (reset) begin
            check_toggle_meta_25 <= 1'b0;
            check_toggle_sync_25 <= 1'b0;
            check_toggle_seen_25 <= 1'b0;
            check_pass_meta_25 <= 1'b0;
            check_pass_sync_25 <= 1'b0;
        end else begin
            check_toggle_meta_25 <= check_complete_toggle_125;
            check_toggle_sync_25 <= check_toggle_meta_25;
            check_toggle_seen_25 <= check_toggle_sync_25;
            check_pass_meta_25 <= frame_check_pass_125;
            check_pass_sync_25 <= check_pass_meta_25;
        end
    end

    uiudp_stack #(
        .CRC_GEN_EN(1'b1),
        .INTER_FRAME_GAP(4'd12)
    ) udp_stack_inst (
        .I_uclk(clk_125),
        .I_reset(reset),
        .I_mac_local_addr(48'h020000000002),
        .I_ip_local_addr(32'hc0a83202),
        .I_udp_local_port(16'd6002),
        .I_ip_dest_addr(32'hc0a83201),
        .I_udp_dest_port(16'd6001),
        .O_W_udp_busy(udp_tx_busy),
        .I_W_udp_req(udp_tx_req),
        .I_W_udp_valid(udp_tx_valid),
        .I_W_udp_data(udp_tx_data),
        .I_W_udp_len(udp_tx_len),
        .O_R_udp_valid(udp_rx_valid),
        .O_R_udp_data(udp_rx_data),
        .O_R_udp_len(udp_rx_len),
        .O_R_udp_src_port(udp_rx_src_port),
        .I_gmii_rclk(gmii_rx_clk),
        .I_gmii_rvalid(gmii_rx_valid),
        .I_gmii_rdata(gmii_rx_data),
        .I_gmii_tclk(clk_125),
        .O_gmii_tvalid(gmii_tx_valid),
        .O_gmii_tdata(gmii_tx_data),
        .O_ip_rerror(ip_rx_error),
        .O_mac_rerror(mac_rx_error)
    );

    rgmii_interface rgmii_interface_inst (
        .speed_10_100(1'b0),
        .gmii_tx_clk_d(clk_125),
        .gmii_tx_reset_d(reset),
        .gmii_tx_reset(reset),
        .gmii_tx_clk(clk_125),
        .gmii_txd(gmii_tx_data),
        .gmii_tx_en(gmii_tx_valid),
        .gmii_tx_er(1'b0),
        .gmii_rx_reset(reset),
        .gmii_rx_clk(gmii_rx_clk),
        .gmii_rxd(gmii_rx_data),
        .gmii_rx_dv(gmii_rx_valid),
        .gmii_rx_er(),
        .rgmii_txd(O_a_rgmii_txd),
        .rgmii_tx_ctl(O_a_rgmii_tx_ctl),
        .rgmii_txc(O_a_rgmii_txc),
        .rgmii_rxd(I_a_rgmii_rxd),
        .rgmii_rx_ctl(I_a_rgmii_rx_ctl),
        .rgmii_rxc(I_a_rgmii_rxc),
        .gmii_crs(),
        .gmii_col(),
        .link_status(phy_link_status),
        .clock_speed(),
        .duplex_status()
    );

    cnn_uart_frame_report u_uart_report (
        .clk(clk_25),
        .rst_n(~reset),
        .check_complete(uart_check_done),
        .check_pass(check_pass_sync_25),
        .digit_done(digit0_done),
        .digit_class(digit0_class),
        .uart_tx(O_uart_tx)
    );

    localparam [23:0] LED_ACTIVITY_HOLD_CYCLES = 24'd12_500_000;
    reg link_meta;
    reg link_sync;
    reg ip_error_meta;
    reg ip_error_sync;
    reg mac_error_meta;
    reg mac_error_sync;
    reg [31:0] rejected_packets_d;
    reg [23:0] rx_led_count;
    reg [23:0] tx_led_count;
    reg rx_led_on;
    reg tx_led_on;
    reg error_led_on;

    assign O_led = {~link_sync, ~rx_led_on, ~tx_led_on, ~error_led_on};

    always @(posedge clk_125 or posedge reset) begin
        if (reset) begin
            link_meta <= 1'b0;
            link_sync <= 1'b0;
            ip_error_meta <= 1'b0;
            ip_error_sync <= 1'b0;
            mac_error_meta <= 1'b0;
            mac_error_sync <= 1'b0;
            rejected_packets_d <= 32'd0;
            rx_led_count <= 24'd0;
            tx_led_count <= 24'd0;
            rx_led_on <= 1'b0;
            tx_led_on <= 1'b0;
            error_led_on <= 1'b0;
        end else begin
            link_meta <= phy_link_status;
            link_sync <= link_meta;
            ip_error_meta <= ip_rx_error;
            ip_error_sync <= ip_error_meta;
            mac_error_meta <= mac_rx_error;
            mac_error_sync <= mac_error_meta;
            rejected_packets_d <= rejected_packets;

            if (udp_rx_valid) begin
                rx_led_count <= LED_ACTIVITY_HOLD_CYCLES;
                rx_led_on <= 1'b1;
            end else if (rx_led_count != 0) begin
                rx_led_count <= rx_led_count - 1'b1;
                rx_led_on <= 1'b1;
            end else begin
                rx_led_on <= 1'b0;
            end

            if (gmii_tx_valid) begin
                tx_led_count <= LED_ACTIVITY_HOLD_CYCLES;
                tx_led_on <= 1'b1;
            end else if (tx_led_count != 0) begin
                tx_led_count <= tx_led_count - 1'b1;
                tx_led_on <= 1'b1;
            end else begin
                tx_led_on <= 1'b0;
            end

            if (ip_error_sync || mac_error_sync || ddr_writer_overflow ||
                ddr_busy_timeouts != 0 || rejected_packets != rejected_packets_d ||
                (frame_check_done_125 && !frame_check_pass_125))
                error_led_on <= 1'b1;
        end
    end
endmodule
