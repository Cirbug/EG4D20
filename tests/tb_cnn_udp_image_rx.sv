`timescale 1ns/1ps

module tb_cnn_udp_image_rx;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg udp_valid = 1'b0;
    reg [7:0] udp_data = 8'd0;
    reg [15:0] udp_len = 16'd0;
    reg [15:0] udp_src_port = 16'd6001;
    wire pixel_valid;
    wire [7:0] pixel_data;
    wire frame_start;
    wire frame_complete;
    wire ack_start;
    wire [15:0] ack_frame_id;
    wire [15:0] ack_packet_index;
    wire [7:0] ack_status;
    wire [31:0] frame_crc32;
    wire [31:0] accepted_packets;
    wire [31:0] rejected_packets;
    reg ack_done = 1'b0;
    integer ack_count = 0;
    integer pixel_count = 0;
    integer frame_start_count = 0;
    integer frame_complete_count = 0;
    reg [15:0] ack_frames [0:15];
    reg [15:0] ack_indices [0:15];
    reg [7:0] ack_statuses [0:15];
    reg [7:0] pixels [0:31];
    integer i;
    reg [31:0] expected_frame_crc;

    always #5 clk = ~clk;

    cnn_udp_image_rx #(
        .IMAGE_BYTES(8),
        .CHUNK_BYTES(4),
        .HOST_PORT(16'd6001)
    ) dut (
        .clk(clk),
        .rst(rst),
        .udp_valid(udp_valid),
        .udp_data(udp_data),
        .udp_len(udp_len),
        .udp_src_port(udp_src_port),
        .writer_idle(1'b1),
        .frame_check_done(1'b1),
        .frame_check_pass(1'b1),
        .ack_done(ack_done),
        .pixel_valid(pixel_valid),
        .pixel_data(pixel_data),
        .frame_start(frame_start),
        .frame_complete(frame_complete),
        .ack_start(ack_start),
        .ack_frame_id(ack_frame_id),
        .ack_packet_index(ack_packet_index),
        .ack_status(ack_status),
        .frame_crc32(frame_crc32),
        .accepted_packets(accepted_packets),
        .rejected_packets(rejected_packets)
    );

    always @(posedge clk) begin
        if (rst) begin
            ack_done <= 1'b0;
        end else begin
            ack_done <= ack_start;
            if (ack_start) begin
                ack_frames[ack_count] <= ack_frame_id;
                ack_indices[ack_count] <= ack_packet_index;
                ack_statuses[ack_count] <= ack_status;
                ack_count <= ack_count + 1;
            end
            if (pixel_valid) begin
                pixels[pixel_count] <= pixel_data;
                pixel_count <= pixel_count + 1;
            end
            if (frame_start)
                frame_start_count <= frame_start_count + 1;
            if (frame_complete)
                frame_complete_count <= frame_complete_count + 1;
        end
    end

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

    task send_packet;
        input [15:0] frame_id;
        input [15:0] packet_index;
        input [31:0] payload;
        input corrupt_crc;
        integer byte_index;
        reg [7:0] packet [0:19];
        reg [31:0] crc;
        begin
            packet[0] = 8'h43;
            packet[1] = 8'h4e;
            packet[2] = 8'h4e;
            packet[3] = 8'h31;
            packet[4] = 8'd1;
            packet[5] = 8'd0;
            packet[6] = frame_id[15:8];
            packet[7] = frame_id[7:0];
            packet[8] = packet_index[15:8];
            packet[9] = packet_index[7:0];
            packet[10] = 8'd0;
            packet[11] = 8'd4;
            packet[12] = payload[31:24];
            packet[13] = payload[23:16];
            packet[14] = payload[15:8];
            packet[15] = payload[7:0];
            crc = 32'hffffffff;
            for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1)
                crc = crc32_byte(crc, packet[byte_index]);
            crc = ~crc;
            packet[16] = crc[31:24];
            packet[17] = crc[23:16];
            packet[18] = crc[15:8];
            packet[19] = crc[7:0] ^ (corrupt_crc ? 8'h01 : 8'h00);

            for (byte_index = 0; byte_index < 20; byte_index = byte_index + 1) begin
                @(negedge clk);
                udp_valid = 1'b1;
                udp_data = packet[byte_index];
                udp_len = 16'd20;
                udp_src_port = 16'd6001;
            end
            @(negedge clk);
            udp_valid = 1'b0;
        end
    endtask

    task wait_for_ack;
        input integer target_count;
        integer cycles;
        begin
            cycles = 0;
            while (ack_count < target_count && cycles < 100) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (ack_count != target_count)
                $fatal(1, "timeout waiting for ACK %0d, got %0d", target_count, ack_count);
            repeat (2) @(negedge clk);
        end
    endtask

    task check_ack;
        input integer entry;
        input [15:0] expected_frame;
        input [15:0] expected_index;
        input [7:0] expected_status;
        begin
            if (ack_frames[entry] !== expected_frame ||
                ack_indices[entry] !== expected_index ||
                ack_statuses[entry] !== expected_status)
                $fatal(1, "ACK[%0d] mismatch: frame=%h index=%h status=%h",
                    entry, ack_frames[entry], ack_indices[entry], ack_statuses[entry]);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;

        send_packet(16'h0001, 16'd0, 32'h10111213, 1'b0);
        wait_for_ack(1);
        check_ack(0, 16'h0001, 16'd0, 8'd0);
        if (pixel_count != 4 || frame_start_count != 1)
            $fatal(1, "packet 0 pixel/frame-start count mismatch");

        send_packet(16'h0001, 16'd0, 32'h10111213, 1'b0);
        wait_for_ack(2);
        check_ack(1, 16'h0001, 16'd0, 8'd0);
        if (pixel_count != 4)
            $fatal(1, "duplicate packet wrote pixels");

        send_packet(16'h0001, 16'd1, 32'h14151617, 1'b0);
        wait_for_ack(3);
        check_ack(2, 16'h0001, 16'd1, 8'd1);
        if (pixel_count != 8 || frame_complete_count != 1)
            $fatal(1, "complete frame pixel/complete count mismatch");
        for (i = 0; i < 8; i = i + 1)
            if (pixels[i] !== (8'h10 + i))
                $fatal(1, "pixel[%0d] mismatch: %h", i, pixels[i]);
        expected_frame_crc = 32'hffffffff;
        for (i = 0; i < 8; i = i + 1)
            expected_frame_crc = crc32_byte(expected_frame_crc, 8'h10 + i);
        if (frame_crc32 !== ~expected_frame_crc)
            $fatal(1, "frame CRC mismatch: got %h expected %h",
                frame_crc32, ~expected_frame_crc);

        send_packet(16'h0001, 16'd1, 32'h14151617, 1'b0);
        wait_for_ack(4);
        check_ack(3, 16'h0001, 16'd1, 8'd1);
        if (pixel_count != 8 || frame_complete_count != 1)
            $fatal(1, "duplicate completed packet changed frame output");

        send_packet(16'h0002, 16'd0, 32'h20212223, 1'b1);
        wait_for_ack(5);
        check_ack(4, 16'h0002, 16'd0, 8'd2);
        if (frame_complete_count != 1 || rejected_packets != 1 || frame_crc32 != 0)
            $fatal(1, "bad CRC was not rejected");

        send_packet(16'h0002, 16'd1, 32'h24252627, 1'b0);
        wait_for_ack(6);
        check_ack(5, 16'h0002, 16'd1, 8'd2);
        if (frame_complete_count != 1 || accepted_packets != 4 || rejected_packets != 2)
            $fatal(1, "out-of-order packet/counters mismatch");

        $display("PASS tb_cnn_udp_image_rx: complete, duplicate, CRC reject, sequence reject");
        $finish;
    end
endmodule
