`timescale 1ns / 1ps

module tb_cnn_frame_digit_detector #(
    parameter integer MAX_DETECTIONS = 16
);
    localparam integer FRAME_PIXELS = 320 * 180;
`ifdef REAL_CNN_ALL
    localparam integer EXPECTED_COUNT = 10;
`elsif REAL_CNN
    localparam integer EXPECTED_COUNT = 1;
`else
    localparam integer EXPECTED_COUNT = 10;
`endif

    reg capture_clk = 1'b0;
    reg infer_clk = 1'b0;
    reg rst = 1'b1;
    reg frame_start = 1'b0;
    reg pixel_valid = 1'b0;
    reg [7:0] pixel_data = 8'd0;
    reg frame_complete = 1'b0;
    wire digit_done;
    wire [3:0] digit_class;
    wire [9:0] digit_x;
    wire [8:0] digit_y;
    wire [9:0] digit_w;
    wire [8:0] digit_h;
    wire frame_done;
    wire [4:0] frame_digit_count;
    wire busy;
    wire model_check_done;
    wire [31:0] model_weight_crc32;
    wire [31:0] digit_patch_crc32;
    wire [31:0] digit_conv1_signature;
    wire [31:0] digit_pool1_signature;
    wire [31:0] digit_conv2_signature;
    wire [31:0] digit_pool2_signature;
    wire [31:0] digit_conv3_signature;
    wire [31:0] digit_pool3_signature;
    wire [31:0] digit_conv1_input_signature;
    wire [31:0] digit_conv1_weight_signature;
    wire [31:0] digit_conv1_product_signature;
    wire [31:0] digit_conv1_accumulator_signature;
    wire [31:0] digit_conv1_raw_signature;
    wire [255:0] digit_conv1_channel_signatures;
    wire [255:0] digit_pool1_channel_signatures;
    wire [7:0] digit_conv1_first_weight;
    wire [7:0] digit_conv1_first_activation;
    wire [15:0] digit_conv1_first_product;
    reg [7:0] image [0:FRAME_PIXELS-1];
    integer expected_x [0:9];
    integer expected_y [0:9];
    integer expected_class [0:9];
    integer index;
    integer cycles;
    integer found;
    integer class_errors;
    integer patch_index;
    reg [31:0] expected_patch_crc32;
    reg [1023:0] image_path;
    reg [1023:0] dump_patch_path;
    reg dump_patch_enabled;
    reg weight_crc_seen;
    reg [31:0] weight_crc_seen_value;
`ifdef REPORT_ONLY
    localparam integer CHECK_LABELS = 0;
`else
    localparam integer CHECK_LABELS = 1;
`endif

    always #4 capture_clk = ~capture_clk;
    always #20 infer_clk = ~infer_clk;

    always @(posedge infer_clk or posedge rst) begin
        if (rst) begin
            weight_crc_seen <= 1'b0;
            weight_crc_seen_value <= 32'd0;
        end else if (model_check_done) begin
            weight_crc_seen <= 1'b1;
            weight_crc_seen_value <= model_weight_crc32;
        end
    end

    function [31:0] crc32_byte;
        input [31:0] crc;
        input [7:0] data;
        reg [31:0] value;
        integer bit_index;
        begin
            value = crc ^ {24'd0, data};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                value = value[0] ? ((value >> 1) ^ 32'hedb88320) : (value >> 1);
            crc32_byte = value;
        end
    endfunction

    cnn_frame_digit_detector #(
        .MAX_DIGITS(MAX_DETECTIONS)
    ) dut (
        .capture_clk(capture_clk),
        .infer_clk(infer_clk),
        .rst(rst),
        .frame_start(frame_start),
        .pixel_valid(pixel_valid),
        .pixel_data(pixel_data),
        .frame_complete(frame_complete),
        .digit_done(digit_done),
        .digit_class(digit_class),
        .digit_x(digit_x),
        .digit_y(digit_y),
        .digit_w(digit_w),
        .digit_h(digit_h),
        .frame_done(frame_done),
        .frame_digit_count(frame_digit_count),
        .busy(busy),
        .model_check_done(model_check_done),
        .model_weight_crc32(model_weight_crc32),
        .digit_patch_crc32(digit_patch_crc32),
        .digit_conv1_signature(digit_conv1_signature),
        .digit_pool1_signature(digit_pool1_signature),
        .digit_conv2_signature(digit_conv2_signature),
        .digit_pool2_signature(digit_pool2_signature),
        .digit_conv3_signature(digit_conv3_signature),
        .digit_pool3_signature(digit_pool3_signature),
        .digit_conv1_input_signature(digit_conv1_input_signature),
        .digit_conv1_weight_signature(digit_conv1_weight_signature),
        .digit_conv1_product_signature(digit_conv1_product_signature),
        .digit_conv1_accumulator_signature(digit_conv1_accumulator_signature),
        .digit_conv1_raw_signature(digit_conv1_raw_signature),
        .digit_conv1_channel_signatures(digit_conv1_channel_signatures),
        .digit_pool1_channel_signatures(digit_pool1_channel_signatures),
        .digit_conv1_first_weight(digit_conv1_first_weight),
        .digit_conv1_first_activation(digit_conv1_first_activation),
        .digit_conv1_first_product(digit_conv1_first_product)
    );

    initial begin
        expected_x[0] = 32;  expected_y[0] = 14;
        expected_x[1] = 99;  expected_y[1] = 17;
        expected_x[2] = 147; expected_y[2] = 16;
        expected_x[3] = 206; expected_y[3] = 8;
        expected_x[4] = 253; expected_y[4] = 17;
        expected_x[5] = 38;  expected_y[5] = 95;
        expected_x[6] = 92;  expected_y[6] = 82;
        expected_x[7] = 160; expected_y[7] = 90;
        expected_x[8] = 209; expected_y[8] = 85;
        expected_x[9] = 264; expected_y[9] = 82;
        for (index = 0; index < 10; index = index + 1)
            expected_class[index] = index;
        class_errors = 0;
        dump_patch_enabled = $value$plusargs("DUMP_PATCH=%s", dump_patch_path);
        if (!$value$plusargs("IMAGE=%s", image_path))
            $fatal(1, "missing +IMAGE=<hex path>");
        $readmemh(image_path, image);
        repeat (5) @(negedge capture_clk);
        rst = 1'b0;

        for (index = 0; index < FRAME_PIXELS; index = index + 1) begin
            @(negedge capture_clk);
            pixel_valid = 1'b1;
            pixel_data = image[index];
            frame_start = (index == 0);
        end
        @(negedge capture_clk);
        pixel_valid = 1'b0;
        frame_start = 1'b0;
        frame_complete = 1'b1;
        @(negedge capture_clk);
        frame_complete = 1'b0;

`ifdef REAL_CNN
        if (!weight_crc_seen)
            $fatal(1, "weight scan did not finish during frame capture");
        if (weight_crc_seen_value !== 32'heec8e020)
            $fatal(1, "weight CRC mismatch expected=eec8e020 actual=%08x", weight_crc_seen_value);
        $display("CNN_WEIGHT_CRC_PASS crc=%08x", weight_crc_seen_value);
`endif

        found = 0;
        cycles = 0;
        while (!frame_done && cycles < 40000000) begin
            @(negedge infer_clk);
            cycles = cycles + 1;
            if (digit_done) begin
                expected_patch_crc32 = 32'hffffffff;
                for (patch_index = 0; patch_index < 784; patch_index = patch_index + 1)
                    expected_patch_crc32 = crc32_byte(expected_patch_crc32, dut.patch_mem[patch_index]);
                expected_patch_crc32 = ~expected_patch_crc32;
                if (digit_patch_crc32 !== expected_patch_crc32)
                    $fatal(1, "patch CRC mismatch expected=%08x actual=%08x",
                           expected_patch_crc32, digit_patch_crc32);
                if (dump_patch_enabled && found == 0)
                    $writememh(dump_patch_path, dut.patch_mem);
                if (found >= (CHECK_LABELS ? EXPECTED_COUNT : MAX_DETECTIONS))
                    $fatal(1, "more detections than expected");
                if (CHECK_LABELS && ((digit_x > expected_x[found] + 18) ||
                    (digit_x + 18 < expected_x[found]) ||
                    (digit_y > expected_y[found] + 18) ||
                    (digit_y + 18 < expected_y[found])))
                    $fatal(1, "bbox %0d far from label: x=%0d y=%0d w=%0d h=%0d",
                           found, digit_x, digit_y, digit_w, digit_h);
                if (digit_w < 3 || digit_h < 13 || digit_class > 9)
                    $fatal(1, "invalid detection %0d bbox=%0d,%0d class=%0d",
                           found, digit_w, digit_h, digit_class);
`ifdef REAL_CNN_ALL
                if (CHECK_LABELS && digit_class != expected_class[found])
                    begin
                        class_errors = class_errors + 1;
                        $display("CLASS_MISMATCH index=%0d expected=%0d got=%0d",
                                 found, expected_class[found], digit_class);
                    end
`endif
                $display("DETECT index=%0d bbox=%0d,%0d,%0d,%0d class=%0d patch_crc=%08x conv1=%08x pool1=%08x conv2=%08x pool2=%08x conv3=%08x pool3=%08x input1=%08x weight1=%08x product1=%08x accum1=%08x raw1=%08x conv1_channels=%064x pool1_channels=%064x first_weight=%02x first_activation=%02x first_product=%04x",
                         found, digit_x, digit_y, digit_w, digit_h, digit_class,
                         digit_patch_crc32, digit_conv1_signature, digit_pool1_signature,
                         digit_conv2_signature, digit_pool2_signature,
                         digit_conv3_signature, digit_pool3_signature,
                         digit_conv1_input_signature, digit_conv1_weight_signature,
                         digit_conv1_product_signature, digit_conv1_accumulator_signature,
                         digit_conv1_raw_signature, digit_conv1_channel_signatures,
                         digit_pool1_channel_signatures, digit_conv1_first_weight,
                         digit_conv1_first_activation, digit_conv1_first_product);
                found = found + 1;
            end
        end

        if (!frame_done)
            $fatal(1, "timeout waiting for detector busy=%b", busy);
        if ((CHECK_LABELS && found != EXPECTED_COUNT) || frame_digit_count != found)
            $fatal(1, "detection count expected=%0d events=%0d frame=%0d",
                   EXPECTED_COUNT, found, frame_digit_count);
`ifdef REAL_CNN_ALL
        $display("CNN_FRAME_DIGIT_CLASS_RESULT correct=%0d/%0d errors=%0d",
                 EXPECTED_COUNT - class_errors, EXPECTED_COUNT, class_errors);
        if (class_errors != 0)
            $fatal(1, "quantized CNN misclassified %0d annotated digits", class_errors);
`endif
        $display("CNN_FRAME_DIGIT_DETECT_PASS count=%0d infer_cycles=%0d",
                 frame_digit_count, cycles);
        $finish;
    end
endmodule

`ifndef REAL_CNN
module cnn_digit_infer(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire pixel_valid,
    input wire [7:0] pixel_data,
    output reg busy,
    output reg done,
    output reg [3:0] class_id,
    output reg weight_check_done,
    output reg [31:0] weight_crc32,
    output reg [31:0] conv1_signature,
    output reg [31:0] pool1_signature,
    output reg [31:0] conv2_signature,
    output reg [31:0] pool2_signature,
    output reg [31:0] conv3_signature,
    output reg [31:0] pool3_signature,
    output reg [31:0] conv1_input_signature,
    output reg [31:0] conv1_weight_signature,
    output reg [31:0] conv1_product_signature,
    output reg [31:0] conv1_accumulator_signature,
    output reg [31:0] conv1_raw_signature,
    output reg [255:0] conv1_channel_signatures,
    output reg [255:0] pool1_channel_signatures
);
    reg [9:0] pixel_count;
    reg [9:0] ink_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
            class_id <= 4'd0;
            weight_check_done <= 1'b0;
            weight_crc32 <= 32'heec8e020;
            conv1_signature <= 32'd0;
            pool1_signature <= 32'd0;
            conv2_signature <= 32'd0;
            pool2_signature <= 32'd0;
            conv3_signature <= 32'd0;
            pool3_signature <= 32'd0;
            conv1_input_signature <= 32'd0;
            conv1_weight_signature <= 32'd0;
            conv1_product_signature <= 32'd0;
            conv1_accumulator_signature <= 32'd0;
            conv1_raw_signature <= 32'd0;
            conv1_channel_signatures <= 256'd0;
            pool1_channel_signatures <= 256'd0;
            pixel_count <= 10'd0;
            ink_count <= 10'd0;
        end else begin
            done <= 1'b0;
            weight_check_done <= 1'b1;
            if (start && !busy) begin
                busy <= 1'b1;
                pixel_count <= 10'd0;
                ink_count <= 10'd0;
            end else if (busy && pixel_valid) begin
                if (pixel_data != 8'd0)
                    ink_count <= ink_count + 1'b1;
                if (pixel_count == 10'd783) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    class_id <= (ink_count != 0 || pixel_data != 0) ? 4'd5 : 4'd0;
                end else begin
                    pixel_count <= pixel_count + 1'b1;
                end
            end
        end
    end
endmodule
`endif

`ifdef SIM_BRAM_MODEL
module EG_LOGIC_BRAM #(
    parameter integer DATA_WIDTH_A = 1,
    parameter integer ADDR_WIDTH_A = 15,
    parameter integer DATA_DEPTH_A = 32768,
    parameter integer DATA_WIDTH_B = 1,
    parameter integer ADDR_WIDTH_B = 15,
    parameter integer DATA_DEPTH_B = 32768,
    parameter MODE = "DP",
    parameter REGMODE_A = "NOREG",
    parameter REGMODE_B = "NOREG",
    parameter IMPLEMENT = "32K",
    parameter DEBUGGABLE = "NO",
    parameter PACKABLE = "NO",
    parameter INIT_FILE = "NONE",
    parameter FILL_ALL = "NONE"
)(
    input wire [DATA_WIDTH_A-1:0] dia,
    input wire [DATA_WIDTH_B-1:0] dib,
    input wire [ADDR_WIDTH_A-1:0] addra,
    input wire [ADDR_WIDTH_B-1:0] addrb,
    input wire cea,
    input wire ceb,
    input wire ocea,
    input wire oceb,
    input wire clka,
    input wire clkb,
    input wire wea,
    input wire web,
    input wire bea,
    input wire beb,
    input wire rsta,
    input wire rstb,
    output reg [DATA_WIDTH_A-1:0] doa,
    output reg [DATA_WIDTH_B-1:0] dob
);
    reg [DATA_WIDTH_A-1:0] memory [0:DATA_DEPTH_A-1];

    initial begin
        if (DATA_WIDTH_A == 8 && DATA_DEPTH_A == 4096)
            $readmemh("cnn/exports/eg4d20_digit_int8_20261026_v2/cnn_digit_weights.hex", memory);
    end

    always @(posedge clka) begin
        if (cea) begin
            if (wea)
                memory[addra] <= dia;
            doa <= memory[addra];
        end
    end

    always @(posedge clkb) begin
        if (ceb) begin
            if (web)
                memory[addrb] <= dib;
            dob <= memory[addrb];
        end
    end
endmodule
`endif
