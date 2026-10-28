`timescale 1ns / 1ps

module tb_cnn_digit_infer;
`ifndef SAMPLE_COUNT
`define SAMPLE_COUNT 80
`endif
    localparam SAMPLE_COUNT = `SAMPLE_COUNT;
    localparam PIXELS_PER_SAMPLE = 784;
    localparam TOTAL_PIXELS = SAMPLE_COUNT * PIXELS_PER_SAMPLE;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg pixel_valid = 1'b0;
    reg [7:0] pixel_data = 8'd0;
    wire busy;
    wire done;
    wire [3:0] class_id;
    wire weight_check_done;
    wire [31:0] weight_crc32;

    reg [7:0] stimulus [0:TOTAL_PIXELS-1];
    reg [3:0] expected [0:SAMPLE_COUNT-1];
    integer sample_index;
    integer sample_base;
    integer pixel_index;
    integer cycles;
    reg [1023:0] stimulus_path;
    reg [1023:0] expected_path;

    always #5 clk = ~clk;

    cnn_digit_infer dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .pixel_valid(pixel_valid),
        .pixel_data(pixel_data),
        .busy(busy),
        .done(done),
        .class_id(class_id),
        .weight_check_done(weight_check_done),
        .weight_crc32(weight_crc32)
    );

    initial begin
        if (!$value$plusargs("STIMULUS=%s", stimulus_path))
            $fatal(1, "missing +STIMULUS=<path>");
        if (!$value$plusargs("EXPECTED=%s", expected_path))
            $fatal(1, "missing +EXPECTED=<path>");
        if (!$value$plusargs("START_INDEX=%d", sample_base))
            sample_base = 0;
        $readmemh(stimulus_path, stimulus);
        $readmemh(expected_path, expected);

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        cycles = 0;
        while (!weight_check_done && cycles < 20000) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        if (!weight_check_done)
            $fatal(1, "timeout waiting for weight scan");
        if (weight_crc32 !== 32'heec8e020)
            $fatal(1, "weight CRC mismatch expected=eec8e020 actual=%08x", weight_crc32);
        $display("CNN_WEIGHT_CRC_PASS crc=%08x", weight_crc32);

        for (sample_index = 0; sample_index < SAMPLE_COUNT; sample_index = sample_index + 1) begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            for (pixel_index = 0; pixel_index < PIXELS_PER_SAMPLE; pixel_index = pixel_index + 1) begin
                pixel_valid = 1'b1;
                pixel_data = stimulus[sample_index * PIXELS_PER_SAMPLE + pixel_index];
                @(negedge clk);
            end
            pixel_valid = 1'b0;
            pixel_data = 8'd0;

            cycles = 0;
            while (!done && cycles < 3000000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (!done)
                $fatal(1, "timeout sample=%0d busy=%b", sample_base + sample_index, busy);
            if (class_id !== expected[sample_index])
                $fatal(1, "mismatch sample=%0d expected=%0d actual=%0d cycles=%0d",
                       sample_base + sample_index, expected[sample_index], class_id, cycles);
            $display("CNN_DIGIT_SAMPLE_PASS index=%0d class=%0d cycles=%0d",
                     sample_base + sample_index, class_id, cycles);
        end

        $display("CNN_DIGIT_RTL_PASS samples=%0d", SAMPLE_COUNT);
        $finish;
    end
endmodule
