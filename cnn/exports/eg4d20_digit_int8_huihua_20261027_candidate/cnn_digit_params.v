module cnn_digit_params(
    input wire [1:0] layer,
    input wire [4:0] channel,
    output reg signed [31:0] bias_value,
    output wire [3:0] conv1_shift,
    output wire [3:0] conv2_shift,
    output wire [3:0] conv3_shift
);
    assign conv1_shift = 4'd10;
    assign conv2_shift = 4'd10;
    assign conv3_shift = 4'd9;
    always @* begin
        case ({layer, channel})
            7'd0: bias_value = 32'h00003121;
            7'd1: bias_value = 32'h000009A2;
            7'd2: bias_value = 32'hFFFFFFE0;
            7'd3: bias_value = 32'h00003660;
            7'd4: bias_value = 32'h0000281A;
            7'd5: bias_value = 32'h00002CC7;
            7'd6: bias_value = 32'h0000027A;
            7'd7: bias_value = 32'h00000275;
            7'd32: bias_value = 32'hFFFFFE70;
            7'd33: bias_value = 32'hFFFFFE80;
            7'd34: bias_value = 32'hFFFFFF8F;
            7'd35: bias_value = 32'h000000D3;
            7'd36: bias_value = 32'h00000294;
            7'd37: bias_value = 32'h00000166;
            7'd38: bias_value = 32'h00000206;
            7'd39: bias_value = 32'hFFFFFF86;
            7'd40: bias_value = 32'h00000140;
            7'd41: bias_value = 32'h0000010B;
            7'd42: bias_value = 32'h000001DB;
            7'd43: bias_value = 32'h000000B5;
            7'd44: bias_value = 32'h000005EC;
            7'd45: bias_value = 32'h00000033;
            7'd46: bias_value = 32'h00000218;
            7'd47: bias_value = 32'h00000152;
            7'd64: bias_value = 32'h00000004;
            7'd65: bias_value = 32'h00000000;
            7'd66: bias_value = 32'h00000023;
            7'd67: bias_value = 32'hFFFFFFF2;
            7'd68: bias_value = 32'hFFFFFFE6;
            7'd69: bias_value = 32'hFFFFFFD9;
            7'd70: bias_value = 32'h00000027;
            7'd71: bias_value = 32'hFFFFFFED;
            7'd72: bias_value = 32'h00000024;
            7'd73: bias_value = 32'h0000002E;
            7'd74: bias_value = 32'h00000025;
            7'd75: bias_value = 32'hFFFFFFE7;
            7'd76: bias_value = 32'hFFFFFFF1;
            7'd77: bias_value = 32'hFFFFFFD4;
            7'd78: bias_value = 32'hFFFFFFFD;
            7'd79: bias_value = 32'h0000000E;
            7'd96: bias_value = 32'h000001DC;
            7'd97: bias_value = 32'h00000009;
            7'd98: bias_value = 32'hFFFFFEBD;
            7'd99: bias_value = 32'hFFFFFE2C;
            7'd100: bias_value = 32'hFFFFFF46;
            7'd101: bias_value = 32'hFFFFFFE2;
            7'd102: bias_value = 32'hFFFFFEA6;
            7'd103: bias_value = 32'hFFFFFF1C;
            7'd104: bias_value = 32'h00000053;
            7'd105: bias_value = 32'hFFFFFF81;
            default: bias_value = 32'sd0;
        endcase
    end
endmodule
