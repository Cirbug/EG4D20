`timescale 1ns / 1ps

module cnn_udp_image_rx #(
    parameter integer IMAGE_BYTES = 57600,
    parameter integer CHUNK_BYTES = 1456,
    parameter [15:0]  HOST_PORT = 16'd6001
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        udp_valid,
    input  wire [7:0]  udp_data,
    input  wire [15:0] udp_len,
    input  wire [15:0] udp_src_port,
    input  wire        writer_idle,
    input  wire        frame_check_done,
    input  wire        frame_check_pass,
    input  wire        ack_done,
    output reg         pixel_valid,
    output reg  [7:0]  pixel_data,
    output reg         frame_start,
    output reg         frame_complete,
    output reg         ack_start,
    output reg  [15:0] ack_frame_id,
    output reg  [15:0] ack_packet_index,
    output reg  [7:0]  ack_status,
    output reg  [31:0] frame_crc32,
    output reg  [31:0] accepted_packets,
    output reg  [31:0] rejected_packets
);

    localparam [1:0] ST_RX = 2'd0;
    localparam [1:0] ST_DRAIN = 2'd1;
    localparam [1:0] ST_ACK = 2'd2;
    localparam [1:0] ST_CHECK = 2'd3;
    localparam integer PACKET_COUNT = (IMAGE_BYTES + CHUNK_BYTES - 1) / CHUNK_BYTES;
    localparam [15:0] LAST_PAYLOAD = IMAGE_BYTES - ((PACKET_COUNT - 1) * CHUNK_BYTES);
    localparam [31:0] MAGIC = 32'h434e4e31;

    reg [1:0] state;
    reg in_packet;
    reg [10:0] byte_index;
    reg [10:0] packet_last_index;
    reg [15:0] packet_len;
    reg [15:0] packet_port;
    reg [31:0] magic_shift;
    reg [7:0] version_byte;
    reg [7:0] flags_byte;
    reg [15:0] rx_frame_id;
    reg [15:0] rx_packet_index;
    reg [7:0] payload_len_hi;
    reg [15:0] payload_len;
    reg packet_accept;
    reg packet_duplicate;
    reg [31:0] crc_state;
    reg [31:0] crc_rx;
    reg [31:0] frame_crc_state;
    reg frame_active;
    reg [15:0] active_frame_id;
    reg [15:0] expected_packet_index;
    reg [15:0] last_frame_id;
    reg [15:0] last_packet_index;
    reg last_packet_valid;
    reg last_frame_complete;
    reg pending_frame_complete;
    reg [7:0] pending_status;
    reg [15:0] pending_frame_id;
    reg [15:0] pending_packet_index;

    wire [10:0] current_index = in_packet ? byte_index : 11'd0;
    wire current_last = in_packet ? (byte_index == packet_last_index) :
                        (udp_len == 16'd1);
    wire [15:0] current_packet_index = {rx_packet_index[15:8], rx_packet_index[7:0]};
    wire [15:0] current_frame = rx_frame_id;
    wire [15:0] expected_payload =
        (current_packet_index == PACKET_COUNT - 1) ? LAST_PAYLOAD : CHUNK_BYTES;
    wire duplicate_active = frame_active &&
        (current_frame == active_frame_id) &&
        (current_packet_index == last_packet_index) &&
        (current_frame == last_frame_id) && last_packet_valid;
    wire duplicate_complete = last_frame_complete && last_packet_valid &&
        (current_frame == last_frame_id) &&
        (current_packet_index == last_packet_index) &&
        (current_packet_index == PACKET_COUNT - 1);
    wire duplicate_packet = duplicate_active || duplicate_complete;
    wire sequence_ok = (current_packet_index == 16'd0) ||
        (frame_active && current_frame == active_frame_id &&
         current_packet_index == expected_packet_index);
    wire [15:0] header_payload_now = {payload_len_hi, udp_data};
    wire [15:0] expected_udp_len = 16'd16 + header_payload_now;

    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0] data_in;
        integer i;
        reg [31:0] crc;
        begin
            crc = crc_in ^ data_in;
            for (i = 0; i < 8; i = i + 1)
                crc = crc[0] ? ((crc >> 1) ^ 32'hedb88320) : (crc >> 1);
            crc32_byte = crc;
        end
    endfunction

    wire [31:0] received_crc = {crc_rx[23:0], udp_data};
    wire crc_matches = received_crc == ~crc_state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_RX;
            in_packet <= 1'b0;
            byte_index <= 11'd0;
            packet_last_index <= 11'd0;
            packet_len <= 16'd0;
            packet_port <= 16'd0;
            magic_shift <= 32'd0;
            version_byte <= 8'd0;
            flags_byte <= 8'd0;
            rx_frame_id <= 16'd0;
            rx_packet_index <= 16'd0;
            payload_len_hi <= 8'd0;
            payload_len <= 16'd0;
            packet_accept <= 1'b0;
            packet_duplicate <= 1'b0;
            crc_state <= 32'hffffffff;
            crc_rx <= 32'd0;
            frame_crc_state <= 32'hffffffff;
            frame_active <= 1'b0;
            active_frame_id <= 16'd0;
            expected_packet_index <= 16'd0;
            last_frame_id <= 16'd0;
            last_packet_index <= 16'd0;
            last_packet_valid <= 1'b0;
            last_frame_complete <= 1'b0;
            pending_frame_complete <= 1'b0;
            pending_status <= 8'd2;
            pending_frame_id <= 16'd0;
            pending_packet_index <= 16'd0;
            pixel_valid <= 1'b0;
            pixel_data <= 8'd0;
            frame_start <= 1'b0;
            frame_complete <= 1'b0;
            ack_start <= 1'b0;
            ack_frame_id <= 16'd0;
            ack_packet_index <= 16'd0;
            ack_status <= 8'd0;
            frame_crc32 <= 32'd0;
            accepted_packets <= 32'd0;
            rejected_packets <= 32'd0;
        end else begin
            pixel_valid <= 1'b0;
            frame_start <= 1'b0;
            frame_complete <= 1'b0;
            ack_start <= 1'b0;

            if (state == ST_RX && udp_valid) begin
                if (!in_packet) begin
                    in_packet <= 1'b1;
                    byte_index <= 11'd0;
                    packet_last_index <= udp_len[10:0] - 11'd1;
                    packet_len <= udp_len;
                    packet_port <= udp_src_port;
                    magic_shift <= 32'd0;
                    version_byte <= 8'd0;
                    flags_byte <= 8'd0;
                    rx_frame_id <= 16'd0;
                    rx_packet_index <= 16'd0;
                    payload_len_hi <= 8'd0;
                    payload_len <= 16'd0;
                    packet_accept <= 1'b0;
                    packet_duplicate <= 1'b0;
                    crc_state <= 32'hffffffff;
                    crc_rx <= 32'd0;
                end

                case (current_index)
                    11'd0: magic_shift <= {24'd0, udp_data};
                    11'd1: magic_shift <= {magic_shift[23:0], udp_data};
                    11'd2: magic_shift <= {magic_shift[23:0], udp_data};
                    11'd3: magic_shift <= {magic_shift[23:0], udp_data};
                    11'd4: version_byte <= udp_data;
                    11'd5: flags_byte <= udp_data;
                    11'd6: rx_frame_id[15:8] <= udp_data;
                    11'd7: rx_frame_id[7:0] <= udp_data;
                    11'd8: rx_packet_index[15:8] <= udp_data;
                    11'd9: rx_packet_index[7:0] <= udp_data;
                    11'd10: payload_len_hi <= udp_data;
                    11'd11: begin
                        payload_len <= header_payload_now;
                        packet_duplicate <= duplicate_packet;
                        packet_accept <= (magic_shift == MAGIC) &&
                            (version_byte == 8'd1) && (flags_byte == 8'd0) &&
                            (packet_port == HOST_PORT) &&
                            (current_packet_index < PACKET_COUNT) &&
                            (header_payload_now == expected_payload) &&
                            (packet_len == expected_udp_len) &&
                            (sequence_ok || duplicate_packet);
                    end
                    default: begin end
                endcase

                if (current_index == 0)
                    crc_state <= crc32_byte(32'hffffffff, udp_data);
                else if (current_index < 12 ||
                         (packet_accept && current_index < 12 + payload_len))
                    crc_state <= crc32_byte(crc_state, udp_data);

                if (current_index >= 12 + payload_len &&
                    current_index < 16 + payload_len)
                    crc_rx <= {crc_rx[23:0], udp_data};

                if (packet_accept && !packet_duplicate &&
                    current_index >= 12 && current_index < 12 + payload_len) begin
                    pixel_valid <= 1'b1;
                    pixel_data <= udp_data;
                    if (current_packet_index == 16'd0 && current_index == 11'd12)
                        frame_crc_state <= crc32_byte(32'hffffffff, udp_data);
                    else
                        frame_crc_state <= crc32_byte(frame_crc_state, udp_data);
                    if (current_packet_index == 16'd0 && current_index == 12)
                        frame_start <= 1'b1;
                end

                if (current_last) begin
                    in_packet <= 1'b0;
                    state <= ST_DRAIN;
                    pending_frame_id <= rx_frame_id;
                    pending_packet_index <= rx_packet_index;
                    pending_frame_complete <= 1'b0;

                    if (packet_accept && crc_matches) begin
                        accepted_packets <= accepted_packets + 1'b1;
                        pending_status <= (current_packet_index == PACKET_COUNT - 1) ? 8'd1 : 8'd0;
                        if (!packet_duplicate) begin
                            active_frame_id <= current_frame;
                            last_frame_id <= current_frame;
                            last_packet_index <= current_packet_index;
                            last_packet_valid <= 1'b1;
                            if (current_packet_index == 0) begin
                                frame_active <= 1'b1;
                                expected_packet_index <= 16'd1;
                                last_frame_complete <= 1'b0;
                            end else if (current_packet_index == PACKET_COUNT - 1) begin
                                frame_active <= 1'b0;
                                expected_packet_index <= 16'd0;
                                last_frame_complete <= 1'b1;
                                pending_frame_complete <= 1'b1;
                                frame_crc32 <= ~frame_crc_state;
                            end else begin
                                frame_active <= 1'b1;
                                expected_packet_index <= current_packet_index + 1'b1;
                            end
                        end
                    end else begin
                        rejected_packets <= rejected_packets + 1'b1;
                        pending_status <= 8'd2;
                        frame_active <= 1'b0;
                        expected_packet_index <= 16'd0;
                        last_frame_complete <= 1'b0;
                        frame_crc32 <= 32'd0;
                    end
                end else begin
                    byte_index <= current_index + 1'b1;
                end
            end else if (state == ST_RX && in_packet && !udp_valid) begin
                in_packet <= 1'b0;
                state <= ST_DRAIN;
                pending_status <= 8'd2;
                pending_frame_id <= rx_frame_id;
                pending_packet_index <= rx_packet_index;
                pending_frame_complete <= 1'b0;
                rejected_packets <= rejected_packets + 1'b1;
                frame_active <= 1'b0;
                expected_packet_index <= 16'd0;
                last_frame_complete <= 1'b0;
                frame_crc32 <= 32'd0;
            end

            if (state == ST_DRAIN && writer_idle) begin
                if (pending_frame_complete) begin
                    frame_complete <= 1'b1;
                    state <= ST_CHECK;
                end else begin
                    ack_frame_id <= pending_frame_id;
                    ack_packet_index <= pending_packet_index;
                    ack_status <= pending_status;
                    ack_start <= 1'b1;
                    state <= ST_ACK;
                end
            end

            if (state == ST_CHECK && frame_check_done) begin
                ack_frame_id <= pending_frame_id;
                ack_packet_index <= pending_packet_index;
                ack_status <= frame_check_pass ? 8'd1 : 8'd2;
                ack_start <= 1'b1;
                state <= ST_ACK;
            end

            if (state == ST_ACK && ack_done)
                state <= ST_RX;
        end
    end
endmodule
