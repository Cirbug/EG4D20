`timescale 1ns / 1ps

module cnn_ddr_frame_writer #(
    parameter integer FIFO_ADDR_WIDTH = 9,
    parameter integer FIFO_ALMOST_FULL = 480,
    parameter integer BUSY_TIMEOUT = 1024
)(
    input  wire        wr_clk,
    input  wire        rd_clk,
    input  wire        rst,
    input  wire        pixel_valid,
    input  wire [7:0]  pixel_data,
    input  wire        frame_start,
    input  wire        ddr_init_done,
    input  wire        ddr_busy,
    output wire        app_wr_en,
    output wire [22:0] app_wr_addr,
    output wire [1:0]  app_wr_dm,
    output wire [31:0] app_wr_din,
    output wire        writer_idle,
    output reg         overflow,
    output reg  [31:0] words_written,
    output reg  [31:0] busy_timeouts
);

    localparam [1:0] OP_IDLE = 2'd0;
    localparam [1:0] OP_WAIT_BUSY = 2'd1;
    localparam [1:0] OP_WAIT_IDLE = 2'd2;

    reg [1:0] byte_lane;
    reg [23:0] partial_word;
    reg first_word_pending;
    reg drop_frame;
    reg fifo_we;
    reg [32:0] fifo_din;
    wire fifo_full;
    wire fifo_empty;
    wire fifo_afull;
    wire fifo_re;
    wire [32:0] fifo_dout;
    wire [FIFO_ADDR_WIDTH-1:0] fifo_wrusedw;
    wire [FIFO_ADDR_WIDTH-1:0] fifo_rdusedw;

    udp_pkg_buf #(
        .DATA_WIDTH_W(33),
        .DATA_WIDTH_R(33),
        .ADDR_WIDTH_W(FIFO_ADDR_WIDTH),
        .ADDR_WIDTH_R(FIFO_ADDR_WIDTH),
        .AL_FULL_NUM(FIFO_ALMOST_FULL),
        .AL_EMPTY_NUM(2),
        .SHOW_AHEAD_EN(1'b1),
        .OUTREG_EN("NOREG")
    ) u_frame_fifo (
        .rst(rst),
        .clkw(wr_clk),
        .we(fifo_we),
        .di(fifo_din),
        .clkr(rd_clk),
        .re(fifo_re),
        .dout(fifo_dout),
        .wrusedw(fifo_wrusedw),
        .rdusedw(fifo_rdusedw),
        .full_flag(fifo_full),
        .empty_flag(fifo_empty),
        .afull(fifo_afull),
        .aempty(),
        .valid()
    );

    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            byte_lane <= 2'd0;
            partial_word <= 24'd0;
            first_word_pending <= 1'b0;
            drop_frame <= 1'b0;
            fifo_we <= 1'b0;
            fifo_din <= 33'd0;
            overflow <= 1'b0;
        end else begin
            fifo_we <= 1'b0;
            if (frame_start) begin
                byte_lane <= 2'd0;
                partial_word <= 24'd0;
                first_word_pending <= 1'b1;
                drop_frame <= 1'b0;
            end

            if (pixel_valid) begin
                if (drop_frame || fifo_afull || fifo_full) begin
                    drop_frame <= 1'b1;
                    overflow <= 1'b1;
                end else begin
                    case (frame_start ? 2'd0 : byte_lane)
                        2'd0: begin
                            partial_word[7:0] <= pixel_data;
                            byte_lane <= 2'd1;
                        end
                        2'd1: begin
                            partial_word[15:8] <= pixel_data;
                            byte_lane <= 2'd2;
                        end
                        2'd2: begin
                            partial_word[23:16] <= pixel_data;
                            byte_lane <= 2'd3;
                        end
                        default: begin
                            fifo_din <= {first_word_pending, pixel_data, partial_word};
                            fifo_we <= 1'b1;
                            first_word_pending <= 1'b0;
                            byte_lane <= 2'd0;
                        end
                    endcase
                end
            end
        end
    end

    reg [1:0] op_state;
    reg [22:0] next_addr;
    reg [31:0] busy_timer;
    reg q_valid;
    reg q_first;
    reg [31:0] q_data;
    reg [1:0] rd_reset;
    reg idle_meta;
    reg idle_sync;

    wire rd_rst = rd_reset[1];
    wire issue = q_valid && op_state == OP_IDLE && ddr_init_done && !ddr_busy;
    wire pop = !fifo_empty && (!q_valid || issue) && !rd_rst;
    wire [22:0] issue_addr = q_first ? 23'd0 : next_addr;
    wire idle_rd = fifo_empty && !q_valid && op_state == OP_IDLE;

    assign app_wr_en = issue;
    assign app_wr_addr = issue_addr;
    assign app_wr_dm = 2'b00;
    assign app_wr_din = q_data;
    assign fifo_re = pop;
    assign writer_idle = idle_sync;

    always @(posedge rd_clk or posedge rst) begin
        if (rst)
            rd_reset <= 2'b11;
        else
            rd_reset <= {rd_reset[0], 1'b0};
    end

    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            idle_meta <= 1'b0;
            idle_sync <= 1'b0;
        end else begin
            idle_meta <= idle_rd;
            idle_sync <= idle_meta;
        end
    end

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            op_state <= OP_IDLE;
            next_addr <= 23'd0;
            busy_timer <= 32'd0;
            q_valid <= 1'b0;
            q_first <= 1'b0;
            q_data <= 32'd0;
            words_written <= 32'd0;
            busy_timeouts <= 32'd0;
        end else begin
            if (pop) begin
                q_valid <= 1'b1;
                q_first <= fifo_dout[32];
                q_data <= fifo_dout[31:0];
            end else if (issue) begin
                q_valid <= 1'b0;
            end

            case (op_state)
                OP_IDLE: begin
                    if (issue) begin
                        next_addr <= issue_addr + 23'd2;
                        words_written <= words_written + 1'b1;
                        busy_timer <= 32'd0;
                        op_state <= OP_WAIT_BUSY;
                    end
                end
                OP_WAIT_BUSY: begin
                    if (ddr_busy) begin
                        busy_timer <= 32'd0;
                        op_state <= OP_WAIT_IDLE;
                    end else if (busy_timer >= BUSY_TIMEOUT) begin
                        busy_timeouts <= busy_timeouts + 1'b1;
                        busy_timer <= 32'd0;
                        op_state <= OP_IDLE;
                    end else begin
                        busy_timer <= busy_timer + 1'b1;
                    end
                end
                OP_WAIT_IDLE: begin
                    if (!ddr_busy) begin
                        busy_timer <= 32'd0;
                        op_state <= OP_IDLE;
                    end else begin
                        busy_timer <= busy_timer + 1'b1;
                    end
                end
                default: op_state <= OP_IDLE;
            endcase
        end
    end
endmodule
