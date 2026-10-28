`timescale 1ns / 1ps

module tb_cnn_frame_digit0_pipe;
    localparam integer FRAME_BYTES = 320 * 180;
    reg capture_clk = 1'b0;
    reg infer_clk = 1'b0;
    reg rst = 1'b1;
    reg frame_start = 1'b0;
    reg pixel_valid = 1'b0;
    reg [7:0] pixel_data = 8'd0;
    reg frame_complete = 1'b0;
    wire digit_done;
    wire [3:0] digit_class;
    wire digit_busy;
    reg [7:0] image [0:FRAME_BYTES-1];
    integer index;
    integer cycles;
    integer expected;
    reg [1023:0] image_path;

    always #5 capture_clk = ~capture_clk;
    always #25 infer_clk = ~infer_clk;

    cnn_frame_digit0_pipe dut (
        .capture_clk(capture_clk),
        .infer_clk(infer_clk),
        .rst(rst),
        .frame_start(frame_start),
        .pixel_valid(pixel_valid),
        .pixel_data(pixel_data),
        .frame_complete(frame_complete),
        .digit_done(digit_done),
        .digit_class(digit_class),
        .digit_busy(digit_busy)
    );

    initial begin
        if (!$value$plusargs("IMAGE=%s", image_path))
            $fatal(1, "missing +IMAGE=<hex path>");
        if (!$value$plusargs("EXPECTED=%d", expected))
            $fatal(1, "missing +EXPECTED=<class>");
        $readmemh(image_path, image);
        repeat (5) @(negedge capture_clk);
        rst = 1'b0;

        for (index = 0; index < FRAME_BYTES; index = index + 1) begin
            @(negedge capture_clk);
            pixel_valid = 1'b1;
            pixel_data = image[index];
            frame_start = (index == 0);
        end
        @(negedge capture_clk);
        pixel_valid = 1'b0;
        pixel_data = 8'd0;
        frame_start = 1'b0;
        frame_complete = 1'b1;
        @(negedge capture_clk);
        frame_complete = 1'b0;

        cycles = 0;
        while (!digit_done && cycles < 3000000) begin
            @(negedge infer_clk);
            cycles = cycles + 1;
        end
        if (!digit_done)
            $fatal(1, "timeout waiting for digit inference busy=%b", digit_busy);
        if (digit_class !== expected[3:0])
            $fatal(1, "class mismatch expected=%0d actual=%0d", expected, digit_class);
        $display("CNN_FRAME_DIGIT0_PASS class=%0d infer_cycles=%0d", digit_class, cycles);
        $finish;
    end
endmodule
