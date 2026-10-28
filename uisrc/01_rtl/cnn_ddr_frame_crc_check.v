`timescale 1ns / 1ps

module cnn_ddr_frame_crc_check #(
    parameter integer FRAME_WORDS = 14400,
    parameter integer CHECK_TIMEOUT_CYCLES = 2000000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        frame_start_toggle,
    input  wire [31:0] frame_crc32,
    input  wire        ddr_init_done,
    input  wire        ddr_busy,
    output wire        app_rd_en,
    output wire [22:0] app_rd_addr,
    input  wire        ddr_rd_valid,
    input  wire [31:0] ddr_rd_data,
    output reg         check_done,
    output reg         check_pass
);

    localparam integer INDEX_WIDTH = (FRAME_WORDS <= 1) ? 1 : $clog2(FRAME_WORDS);
    localparam [3:0] ST_IDLE = 4'd0;
    localparam [3:0] ST_WAIT_BUSY = 4'd1;
    localparam [3:0] ST_ISSUE = 4'd2;
    localparam [3:0] ST_WAIT_DATA = 4'd3;
    localparam [3:0] ST_CRC0 = 4'd4;
    localparam [3:0] ST_CRC1 = 4'd5;
    localparam [3:0] ST_CRC2 = 4'd6;
    localparam [3:0] ST_CRC3 = 4'd7;
    localparam [3:0] ST_COMPARE = 4'd8;

    reg start_meta;
    reg start_sync;
    reg start_seen;
    reg [3:0] state;
    reg [INDEX_WIDTH-1:0] word_index;
    reg [31:0] expected_crc;
    reg [31:0] crc_state;
    reg [31:0] read_word;
    reg [31:0] watchdog;

    assign app_rd_en = (state == ST_ISSUE);
    assign app_rd_addr = {{(22-INDEX_WIDTH){1'b0}}, word_index, 1'b0};

    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0] data_in;
        integer bit_index;
        reg [31:0] crc;
        begin
            crc = crc_in ^ data_in;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                crc = crc[0] ? ((crc >> 1) ^ 32'hedb88320) : (crc >> 1);
            crc32_byte = crc;
        end
    endfunction

    wire [31:0] crc_after_last_byte = crc32_byte(crc_state, read_word[31:24]);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            start_meta <= 1'b0;
            start_sync <= 1'b0;
            start_seen <= 1'b0;
            state <= ST_IDLE;
            word_index <= {INDEX_WIDTH{1'b0}};
            expected_crc <= 32'd0;
            crc_state <= 32'hffffffff;
            read_word <= 32'd0;
            watchdog <= 32'd0;
            check_done <= 1'b0;
            check_pass <= 1'b0;
        end else begin
            start_meta <= frame_start_toggle;
            start_sync <= start_meta;
            check_done <= 1'b0;

            if (state == ST_IDLE) begin
                watchdog <= 32'd0;
                if (start_sync != start_seen) begin
                    start_seen <= start_sync;
                    expected_crc <= frame_crc32;
                    word_index <= {INDEX_WIDTH{1'b0}};
                    crc_state <= 32'hffffffff;
                    check_pass <= 1'b0;
                    watchdog <= 32'd0;
                    state <= ST_WAIT_BUSY;
                end
            end else if (watchdog >= CHECK_TIMEOUT_CYCLES - 1) begin
                check_done <= 1'b1;
                check_pass <= 1'b0;
                watchdog <= 32'd0;
                state <= ST_IDLE;
            end else begin
                watchdog <= watchdog + 1'b1;
                case (state)
                    ST_WAIT_BUSY: begin
                        if (ddr_init_done && !ddr_busy)
                            state <= ST_ISSUE;
                    end
                    ST_ISSUE: state <= ST_WAIT_DATA;
                    ST_WAIT_DATA: begin
                        if (ddr_rd_valid) begin
                            read_word <= ddr_rd_data;
                            state <= ST_CRC0;
                        end
                    end
                    ST_CRC0: begin
                        crc_state <= crc32_byte(crc_state, read_word[7:0]);
                        state <= ST_CRC1;
                    end
                    ST_CRC1: begin
                        crc_state <= crc32_byte(crc_state, read_word[15:8]);
                        state <= ST_CRC2;
                    end
                    ST_CRC2: begin
                        crc_state <= crc32_byte(crc_state, read_word[23:16]);
                        state <= ST_CRC3;
                    end
                    ST_CRC3: begin
                        crc_state <= crc_after_last_byte;
                        if (word_index == FRAME_WORDS - 1) begin
                            state <= ST_COMPARE;
                        end else begin
                            word_index <= word_index + 1'b1;
                            state <= ST_WAIT_BUSY;
                        end
                    end
                    ST_COMPARE: begin
                        check_done <= 1'b1;
                        check_pass <= (~crc_state == expected_crc);
                        state <= ST_IDLE;
                    end
                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
