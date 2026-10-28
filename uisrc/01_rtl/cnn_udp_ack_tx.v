`timescale 1ns / 1ps

module cnn_udp_ack_tx(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [15:0] frame_id,
    input  wire [15:0] packet_index,
    input  wire [7:0]  status,
    input  wire        udp_busy,
    output reg         udp_req,
    output reg         udp_valid,
    output reg  [7:0]  udp_data,
    output wire [15:0] udp_len,
    output reg         done,
    output wire        busy
);

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_REQ = 3'd1;
    localparam [2:0] ST_SEND = 3'd2;
    localparam [2:0] ST_WAIT_DONE = 3'd3;

    reg [2:0] state;
    reg [3:0] byte_index;
    reg [15:0] frame_id_r;
    reg [15:0] packet_index_r;
    reg [7:0] status_r;

    assign udp_len = 16'd10;
    assign busy = state != ST_IDLE;

    always @* begin
        case (byte_index)
            4'd0: udp_data = 8'h41;
            4'd1: udp_data = 8'h43;
            4'd2: udp_data = 8'h4b;
            4'd3: udp_data = 8'h31;
            4'd4: udp_data = frame_id_r[15:8];
            4'd5: udp_data = frame_id_r[7:0];
            4'd6: udp_data = packet_index_r[15:8];
            4'd7: udp_data = packet_index_r[7:0];
            4'd8: udp_data = status_r;
            default: udp_data = 8'h00;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            byte_index <= 4'd0;
            frame_id_r <= 16'd0;
            packet_index_r <= 16'd0;
            status_r <= 8'd0;
            udp_req <= 1'b0;
            udp_valid <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    udp_req <= 1'b0;
                    udp_valid <= 1'b0;
                    if (start) begin
                        frame_id_r <= frame_id;
                        packet_index_r <= packet_index;
                        status_r <= status;
                        byte_index <= 4'd0;
                        udp_req <= 1'b1;
                        state <= ST_REQ;
                    end
                end
                ST_REQ: begin
                    if (udp_busy) begin
                        udp_req <= 1'b0;
                        udp_valid <= 1'b1;
                        byte_index <= 4'd0;
                        state <= ST_SEND;
                    end
                end
                ST_SEND: begin
                    if (byte_index == 4'd9) begin
                        udp_valid <= 1'b0;
                        state <= ST_WAIT_DONE;
                    end else begin
                        byte_index <= byte_index + 1'b1;
                    end
                end
                ST_WAIT_DONE: begin
                    if (!udp_busy) begin
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
