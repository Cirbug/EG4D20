`timescale 1ns / 1ps

module tb_cnn_uart_detect_report;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg check_complete = 1'b0;
    reg check_pass = 1'b0;
    reg model_check_done = 1'b0;
    reg [31:0] model_weight_crc32 = 32'h89abcdef;
    reg digit_done = 1'b0;
    reg [3:0] digit_class = 4'd0;
    reg [9:0] digit_x = 10'd0;
    reg [8:0] digit_y = 9'd0;
    reg [9:0] digit_w = 10'd0;
    reg [8:0] digit_h = 9'd0;
    reg [31:0] digit_patch_crc32 = 32'h0123abcd;
    reg [31:0] digit_conv1_signature = 32'h11223344;
    reg [31:0] digit_pool1_signature = 32'h55667788;
    reg [31:0] digit_conv2_signature = 32'h99aabbcc;
    reg [31:0] digit_pool2_signature = 32'hddeeff00;
    reg [31:0] digit_conv3_signature = 32'h12345678;
    reg [31:0] digit_pool3_signature = 32'h89abcdef;
    reg [31:0] digit_conv1_input_signature = 32'ha1b2c3d4;
    reg [31:0] digit_conv1_weight_signature = 32'he5f60718;
    reg [31:0] digit_conv1_product_signature = 32'h192a3b4c;
    reg [31:0] digit_conv1_accumulator_signature = 32'h5d6e7f80;
    reg [31:0] digit_conv1_raw_signature = 32'h91a2b3c4;
    reg [255:0] digit_conv1_channel_signatures = {
        32'ha0000007, 32'ha0000006, 32'ha0000005, 32'ha0000004,
        32'ha0000003, 32'ha0000002, 32'ha0000001, 32'ha0000000
    };
    reg [255:0] digit_pool1_channel_signatures = {
        32'hb0000007, 32'hb0000006, 32'hb0000005, 32'hb0000004,
        32'hb0000003, 32'hb0000002, 32'hb0000001, 32'hb0000000
    };
    reg [7:0] digit_conv1_first_weight = 8'hfe;
    reg [7:0] digit_conv1_first_activation = 8'h23;
    reg [15:0] digit_conv1_first_product = 16'hfbcd;
    reg frame_done = 1'b0;
    reg [4:0] frame_digit_count = 5'd0;
    wire uart_tx;
    reg [7:0] expected [0:330];
    reg [7:0] received [0:330];
    integer received_count = 0;
    integer index;
    integer cycles;
    integer channel_index;
    integer nibble_index;

    function [7:0] ascii_hex_test;
        input [3:0] value;
        begin
            ascii_hex_test = value < 10 ? (8'h30 + {4'd0, value}) :
                                           (8'h41 + {4'd0, value - 4'd10});
        end
    endfunction

    always #5 clk = ~clk;

    cnn_uart_detect_report #(
        .CLK_HZ(10),
        .BAUD(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .check_complete(check_complete),
        .check_pass(check_pass),
        .model_check_done(model_check_done),
        .model_weight_crc32(model_weight_crc32),
        .digit_done(digit_done),
        .digit_class(digit_class),
        .digit_x(digit_x),
        .digit_y(digit_y),
        .digit_w(digit_w),
        .digit_h(digit_h),
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
        .digit_conv1_first_product(digit_conv1_first_product),
        .frame_done(frame_done),
        .frame_digit_count(frame_digit_count),
        .uart_tx(uart_tx)
    );

    always @(posedge clk) begin
        if (rst_n && dut.u_uart_tx.I_uart_wreq && !dut.u_uart_tx.O_uart_wbusy) begin
            received[received_count] <= dut.u_uart_tx.I_uart_wdata;
            received_count <= received_count + 1;
        end
    end

    initial begin
        expected[0] = "D"; expected[1] = "D"; expected[2] = "R"; expected[3] = " ";
        expected[4] = "O"; expected[5] = "K"; expected[6] = 8'h0d; expected[7] = 8'h0a;
        expected[8] = "M"; expected[9] = "O"; expected[10] = "D"; expected[11] = "E";
        expected[12] = "L"; expected[13] = ","; expected[14] = "R"; expected[15] = "8";
        expected[16] = "D"; expected[17] = "1"; expected[18] = ",";
        expected[19] = "8"; expected[20] = "9"; expected[21] = "A"; expected[22] = "B";
        expected[23] = "C"; expected[24] = "D"; expected[25] = "E"; expected[26] = "F";
        expected[27] = 8'h0d; expected[28] = 8'h0a;
        expected[29] = "D"; expected[30] = ","; expected[31] = "0"; expected[32] = "3";
        expected[33] = "7"; expected[34] = ","; expected[35] = "0"; expected[36] = "1";
        expected[37] = "9"; expected[38] = ","; expected[39] = "0"; expected[40] = "3";
        expected[41] = "3"; expected[42] = ","; expected[43] = "0"; expected[44] = "4";
        expected[45] = "4"; expected[46] = ","; expected[47] = "0"; expected[48] = ",";
        expected[49] = "0"; expected[50] = "1"; expected[51] = "2"; expected[52] = "3";
        expected[53] = "A"; expected[54] = "B"; expected[55] = "C"; expected[56] = "D";
        expected[57] = ","; expected[58] = "1"; expected[59] = "1"; expected[60] = "2";
        expected[61] = "2"; expected[62] = "3"; expected[63] = "3"; expected[64] = "4";
        expected[65] = "4"; expected[66] = ","; expected[67] = "5"; expected[68] = "5";
        expected[69] = "6"; expected[70] = "6"; expected[71] = "7"; expected[72] = "7";
        expected[73] = "8"; expected[74] = "8"; expected[75] = ","; expected[76] = "9";
        expected[77] = "9"; expected[78] = "A"; expected[79] = "A"; expected[80] = "B";
        expected[81] = "B"; expected[82] = "C"; expected[83] = "C"; expected[84] = ",";
        expected[85] = "D"; expected[86] = "D"; expected[87] = "E"; expected[88] = "E";
        expected[89] = "F"; expected[90] = "F"; expected[91] = "0"; expected[92] = "0";
        expected[93] = ","; expected[94] = "1"; expected[95] = "2"; expected[96] = "3";
        expected[97] = "4"; expected[98] = "5"; expected[99] = "6"; expected[100] = "7";
        expected[101] = "8"; expected[102] = ","; expected[103] = "8"; expected[104] = "9";
        expected[105] = "A"; expected[106] = "B"; expected[107] = "C"; expected[108] = "D";
        expected[109] = "E"; expected[110] = "F"; expected[111] = ",";
        expected[112] = "A"; expected[113] = "1"; expected[114] = "B"; expected[115] = "2";
        expected[116] = "C"; expected[117] = "3"; expected[118] = "D"; expected[119] = "4";
        expected[120] = ","; expected[121] = "E"; expected[122] = "5"; expected[123] = "F";
        expected[124] = "6"; expected[125] = "0"; expected[126] = "7"; expected[127] = "1";
        expected[128] = "8"; expected[129] = ","; expected[130] = "1"; expected[131] = "9";
        expected[132] = "2"; expected[133] = "A"; expected[134] = "3"; expected[135] = "B";
        expected[136] = "4"; expected[137] = "C"; expected[138] = ","; expected[139] = "5";
        expected[140] = "D"; expected[141] = "6"; expected[142] = "E"; expected[143] = "7";
        expected[144] = "F"; expected[145] = "8"; expected[146] = "0"; expected[147] = ",";
        expected[148] = "9"; expected[149] = "1"; expected[150] = "A"; expected[151] = "2";
        expected[152] = "B"; expected[153] = "3"; expected[154] = "C"; expected[155] = "4";
        expected[156] = 8'h0d; expected[157] = 8'h0a;
        expected[158] = "C"; expected[159] = ",";
        for (channel_index = 0; channel_index < 8; channel_index = channel_index + 1) begin
            for (nibble_index = 0; nibble_index < 8; nibble_index = nibble_index + 1) begin
                expected[160 + channel_index * 9 + nibble_index] = ascii_hex_test(
                    digit_conv1_channel_signatures[channel_index * 32 + (7 - nibble_index) * 4 +: 4]);
                expected[232 + channel_index * 9 + nibble_index] = ascii_hex_test(
                    digit_pool1_channel_signatures[channel_index * 32 + (7 - nibble_index) * 4 +: 4]);
            end
            expected[168 + channel_index * 9] = ",";
            if (channel_index < 7)
                expected[240 + channel_index * 9] = ",";
        end
        expected[303] = ","; expected[304] = "F"; expected[305] = "E";
        expected[306] = ","; expected[307] = "2"; expected[308] = "3";
        expected[309] = ","; expected[310] = "F"; expected[311] = "B";
        expected[312] = "C"; expected[313] = "D";
        expected[314] = 8'h0d; expected[315] = 8'h0a;
        expected[316] = "F"; expected[317] = "R"; expected[318] = "A"; expected[319] = "M";
        expected[320] = "E"; expected[321] = "_"; expected[322] = "D"; expected[323] = "O";
        expected[324] = "N"; expected[325] = "E"; expected[326] = ","; expected[327] = "0";
        expected[328] = "1"; expected[329] = 8'h0d; expected[330] = 8'h0a;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        model_check_done = 1'b1;
        check_complete = 1'b1;
        check_pass = 1'b1;
        @(negedge clk);
        model_check_done = 1'b0;
        check_complete = 1'b0;

        cycles = 0;
        while (received_count < 8 && cycles < 1000) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        if (received_count != 8)
            $fatal(1, "timeout waiting for DDR report bytes=%0d", received_count);

        @(negedge clk);
        digit_done = 1'b1;
        digit_class = 4'd0;
        digit_x = 10'd37;
        digit_y = 9'd19;
        digit_w = 10'd33;
        digit_h = 9'd44;
        frame_done = 1'b1;
        frame_digit_count = 5'd1;
        @(negedge clk);
        digit_done = 1'b0;
        frame_done = 1'b0;

        cycles = 0;
        while (received_count < 331 && cycles < 30000) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        if (received_count != 331)
            $fatal(1, "timeout waiting for detection reports bytes=%0d", received_count);
        for (index = 0; index < 331; index = index + 1)
            if (received[index] !== expected[index])
                $fatal(1, "UART byte %0d expected=0x%02x actual=0x%02x",
                       index, expected[index], received[index]);
        $display("CNN_UART_DETECT_REPORT_PASS bytes=%0d", received_count);
        $finish;
    end
endmodule

module uiuart_tx #(
    parameter integer BAUD_DIV = 0
)(
    input wire I_clk,
    input wire I_uart_rstn,
    input wire I_uart_wreq,
    input wire [7:0] I_uart_wdata,
    output reg O_uart_wbusy,
    output wire O_uart_tx
);
    reg [1:0] busy_cycles;
    assign O_uart_tx = 1'b1;

    always @(posedge I_clk or negedge I_uart_rstn) begin
        if (!I_uart_rstn) begin
            O_uart_wbusy <= 1'b0;
            busy_cycles <= 2'd0;
        end else if (I_uart_wreq && !O_uart_wbusy) begin
            O_uart_wbusy <= 1'b1;
            busy_cycles <= 2'd2;
        end else if (O_uart_wbusy) begin
            if (busy_cycles == 0)
                O_uart_wbusy <= 1'b0;
            else
                busy_cycles <= busy_cycles - 1'b1;
        end
    end
endmodule
