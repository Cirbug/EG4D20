`timescale 1ns / 1ps

module cnn_uart_frame_report #(
    parameter integer CLK_HZ = 25_000_000,
    parameter integer BAUD = 115_200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire check_complete,
    input  wire check_pass,
    input  wire digit_done,
    input  wire [3:0] digit_class,
    output wire uart_tx
);
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_REQUEST = 3'd1;
    localparam [2:0] ST_WAIT_START = 3'd2;
    localparam [2:0] ST_WAIT_DONE = 3'd3;

    reg [2:0] state;
    reg [3:0] byte_index;
    reg uart_req;
    reg [7:0] uart_data;
    reg check_pending;
    reg pending_pass;
    reg active_pass;
    reg check_is_digit;
    reg pending_digit;
    reg [3:0] pending_digit_class;
    reg [3:0] active_digit_class;
    wire uart_busy;

    always @* begin
        if (check_is_digit) begin
            case (byte_index)
                4'd0: uart_data = 8'h44;
                4'd1: uart_data = 8'h49;
                4'd2: uart_data = 8'h47;
                4'd3: uart_data = 8'h49;
                4'd4: uart_data = 8'h54;
                4'd5: uart_data = 8'h3d;
                4'd6: uart_data = 8'h30 + {4'd0, active_digit_class};
                4'd7: uart_data = 8'h0d;
                default: uart_data = 8'h0a;
            endcase
        end else if (active_pass) begin
            case (byte_index)
                4'd0: uart_data = 8'h44;
                4'd1: uart_data = 8'h44;
                4'd2: uart_data = 8'h52;
                4'd3: uart_data = 8'h20;
                4'd4: uart_data = 8'h4f;
                4'd5: uart_data = 8'h4b;
                4'd6: uart_data = 8'h0d;
                default: uart_data = 8'h0a;
            endcase
        end else begin
            case (byte_index)
                4'd0: uart_data = 8'h44;
                4'd1: uart_data = 8'h44;
                4'd2: uart_data = 8'h52;
                4'd3: uart_data = 8'h20;
                4'd4: uart_data = 8'h45;
                4'd5: uart_data = 8'h52;
                4'd6: uart_data = 8'h52;
                4'd7: uart_data = 8'h0d;
                default: uart_data = 8'h0a;
            endcase
        end
    end

    uiuart_tx #(
        .BAUD_DIV(CLK_HZ / BAUD - 1)
    ) u_uart_tx (
        .I_clk(clk),
        .I_uart_rstn(rst_n),
        .I_uart_wreq(uart_req),
        .I_uart_wdata(uart_data),
        .O_uart_wbusy(uart_busy),
        .O_uart_tx(uart_tx)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            byte_index <= 4'd0;
            uart_req <= 1'b0;
            check_pending <= 1'b0;
            pending_pass <= 1'b0;
            active_pass <= 1'b0;
            check_is_digit <= 1'b0;
            pending_digit <= 1'b0;
            pending_digit_class <= 4'd0;
            active_digit_class <= 4'd0;
        end else begin
            if (check_complete) begin
                check_pending <= 1'b1;
                pending_pass <= check_pass;
            end
            if (digit_done) begin
                pending_digit <= 1'b1;
                pending_digit_class <= digit_class;
            end

            case (state)
                ST_IDLE: begin
                    uart_req <= 1'b0;
                    if (check_pending || check_complete) begin
                        if (check_pending) begin
                            active_pass <= pending_pass;
                            check_is_digit <= 1'b0;
                            if (!check_complete)
                                check_pending <= 1'b0;
                        end else begin
                            active_pass <= check_pass;
                            check_is_digit <= 1'b0;
                            check_pending <= 1'b0;
                        end
                        byte_index <= 4'd0;
                        state <= ST_REQUEST;
                    end else if (pending_digit || digit_done) begin
                        check_is_digit <= 1'b1;
                        active_digit_class <= pending_digit ? pending_digit_class : digit_class;
                        pending_digit <= 1'b0;
                        byte_index <= 4'd0;
                        state <= ST_REQUEST;
                    end
                end
                ST_REQUEST: begin
                    if (!uart_busy) begin
                        uart_req <= 1'b1;
                        state <= ST_WAIT_START;
                    end
                end
                ST_WAIT_START: begin
                    uart_req <= 1'b0;
                    if (uart_busy)
                        state <= ST_WAIT_DONE;
                end
                ST_WAIT_DONE: begin
                    if (!uart_busy) begin
                        if ((check_is_digit && byte_index == 4'd8) ||
                            (!check_is_digit && active_pass && byte_index == 4'd7) ||
                            (!check_is_digit && !active_pass && byte_index == 4'd8)) begin
                            state <= ST_IDLE;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                            state <= ST_REQUEST;
                        end
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
