`timescale 1ns/1ps

module tb_cnn_ddr_frame_crc_check;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start_toggle = 1'b0;
    reg [31:0] expected_crc = 32'd0;
    reg ddr_init_done = 1'b0;
    reg ddr_busy = 1'b0;
    wire app_rd_en;
    wire [22:0] app_rd_addr;
    reg [3:0] valid_pipe = 4'b0;
    reg [31:0] data_pipe [0:3];
    reg [31:0] memory [0:3];
    wire ddr_rd_valid = valid_pipe[3];
    wire [31:0] ddr_rd_data = data_pipe[3];
    wire check_done;
    wire check_pass;
    integer request_count = 0;
    integer done_count = 0;
    integer cycles;
    integer i;
    reg last_pass;
    reg [22:0] request_addresses [0:7];

    always #5 clk = ~clk;

    cnn_ddr_frame_crc_check #(
        .FRAME_WORDS(4),
        .CHECK_TIMEOUT_CYCLES(500)
    ) dut (
        .clk(clk),
        .rst(rst),
        .frame_start_toggle(start_toggle),
        .frame_crc32(expected_crc),
        .ddr_init_done(ddr_init_done),
        .ddr_busy(ddr_busy),
        .app_rd_en(app_rd_en),
        .app_rd_addr(app_rd_addr),
        .ddr_rd_valid(ddr_rd_valid),
        .ddr_rd_data(ddr_rd_data),
        .check_done(check_done),
        .check_pass(check_pass)
    );

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

    always @(posedge clk) begin
        valid_pipe <= {valid_pipe[2:0], app_rd_en};
        if (app_rd_en) begin
            if (app_rd_addr[0] || (app_rd_addr >> 1) >= 4)
                $fatal(1, "DDR read address out of range: %0d", app_rd_addr);
            request_addresses[request_count] <= app_rd_addr;
            data_pipe[0] <= memory[app_rd_addr >> 1];
            request_count <= request_count + 1;
        end else begin
            data_pipe[0] <= 32'd0;
        end
        for (i = 1; i < 4; i = i + 1)
            data_pipe[i] <= data_pipe[i - 1];

        if (check_done) begin
            done_count <= done_count + 1;
            last_pass <= check_pass;
        end
    end

    task wait_for_check;
        input integer target_count;
        begin
            cycles = 0;
            while (done_count < target_count && cycles < 1000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (done_count != target_count)
                $fatal(1, "timeout waiting for DDR CRC check %0d", target_count);
            repeat (3) @(negedge clk);
        end
    endtask

    initial begin
        memory[0] = 32'h13121110;
        memory[1] = 32'h17161514;
        memory[2] = 32'h1b1a1918;
        memory[3] = 32'h1f1e1d1c;
        expected_crc = 32'hffffffff;
        for (i = 0; i < 16; i = i + 1)
            expected_crc = crc32_byte(expected_crc, 8'h10 + i);
        expected_crc = ~expected_crc;

        repeat (4) @(negedge clk);
        rst = 1'b0;
        ddr_init_done = 1'b1;
        start_toggle = 1'b1;
        wait_for_check(1);
        if (!last_pass || request_count != 4)
            $fatal(1, "valid DDR contents failed CRC check");
        for (i = 0; i < 4; i = i + 1)
            if (request_addresses[i] !== (i * 2))
                $fatal(1, "DDR address[%0d] mismatch: %0d", i, request_addresses[i]);

        memory[2] = memory[2] ^ 32'h00000100;
        @(negedge clk);
        start_toggle = 1'b0;
        wait_for_check(2);
        if (last_pass || request_count != 8)
            $fatal(1, "corrupted DDR contents were not rejected");
        for (i = 4; i < 8; i = i + 1)
            if (request_addresses[i] !== ((i - 4) * 2))
                $fatal(1, "second DDR address[%0d] mismatch: %0d", i - 4,
                    request_addresses[i]);

        $display("PASS tb_cnn_ddr_frame_crc_check: address stride, byte order, pass/fail CRC");
        $finish;
    end
endmodule
