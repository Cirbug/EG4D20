`timescale 1ns / 1ps

module cnn_uart_detect_report #(
    parameter integer CLK_HZ = 25_000_000,
    parameter integer BAUD = 115_200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       check_complete,
    input  wire       check_pass,
    input  wire       model_check_done,
    input  wire [31:0] model_weight_crc32,
    input  wire       digit_done,
    input  wire [3:0] digit_class,
    input  wire [9:0] digit_x,
    input  wire [8:0] digit_y,
    input  wire [9:0] digit_w,
    input  wire [8:0] digit_h,
    input  wire [31:0] digit_patch_crc32,
    input  wire [31:0] digit_conv1_signature,
    input  wire [31:0] digit_pool1_signature,
    input  wire [31:0] digit_conv2_signature,
    input  wire [31:0] digit_pool2_signature,
    input  wire [31:0] digit_conv3_signature,
    input  wire [31:0] digit_pool3_signature,
    input  wire [31:0] digit_conv1_input_signature,
    input  wire [31:0] digit_conv1_weight_signature,
    input  wire [31:0] digit_conv1_product_signature,
    input  wire [31:0] digit_conv1_accumulator_signature,
    input  wire [31:0] digit_conv1_raw_signature,
    input  wire [255:0] digit_conv1_channel_signatures,
    input  wire [255:0] digit_pool1_channel_signatures,
    input  wire [7:0] digit_conv1_first_weight,
    input  wire [7:0] digit_conv1_first_activation,
    input  wire [15:0] digit_conv1_first_product,
    input  wire       frame_done,
    input  wire [4:0] frame_digit_count,
    output wire       uart_tx
);
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_REQUEST = 3'd1;
    localparam [2:0] ST_WAIT_START = 3'd2;
    localparam [2:0] ST_WAIT_DONE = 3'd3;

    reg [2:0] state;
    reg [7:0] byte_index;
    reg uart_req;
    reg [7:0] uart_data;
    reg pending_check;
    reg pending_pass;
    reg active_pass;
    reg pending_model;
    reg [31:0] pending_model_crc32;
    reg active_model;
    reg [31:0] active_model_crc32;
    reg pending_digit;
    reg [3:0] pending_digit_class;
    reg [9:0] pending_digit_x;
    reg [8:0] pending_digit_y;
    reg [9:0] pending_digit_w;
    reg [8:0] pending_digit_h;
    reg [31:0] pending_digit_patch_crc32;
    reg [31:0] pending_digit_conv1_signature;
    reg [31:0] pending_digit_pool1_signature;
    reg [31:0] pending_digit_conv2_signature;
    reg [31:0] pending_digit_pool2_signature;
    reg [31:0] pending_digit_conv3_signature;
    reg [31:0] pending_digit_pool3_signature;
    reg [31:0] pending_digit_conv1_input_signature;
    reg [31:0] pending_digit_conv1_weight_signature;
    reg [31:0] pending_digit_conv1_product_signature;
    reg [31:0] pending_digit_conv1_accumulator_signature;
    reg [31:0] pending_digit_conv1_raw_signature;
    reg [255:0] pending_digit_conv1_channel_signatures;
    reg [255:0] pending_digit_pool1_channel_signatures;
    reg [7:0] pending_digit_conv1_first_weight;
    reg [7:0] pending_digit_conv1_first_activation;
    reg [15:0] pending_digit_conv1_first_product;
    reg active_digit;
    reg active_channel;
    reg [3:0] active_digit_class;
    reg [9:0] active_digit_x;
    reg [8:0] active_digit_y;
    reg [9:0] active_digit_w;
    reg [8:0] active_digit_h;
    reg [31:0] active_digit_patch_crc32;
    reg [31:0] active_digit_conv1_signature;
    reg [31:0] active_digit_pool1_signature;
    reg [31:0] active_digit_conv2_signature;
    reg [31:0] active_digit_pool2_signature;
    reg [31:0] active_digit_conv3_signature;
    reg [31:0] active_digit_pool3_signature;
    reg [31:0] active_digit_conv1_input_signature;
    reg [31:0] active_digit_conv1_weight_signature;
    reg [31:0] active_digit_conv1_product_signature;
    reg [31:0] active_digit_conv1_accumulator_signature;
    reg [31:0] active_digit_conv1_raw_signature;
    reg [255:0] active_digit_conv1_channel_signatures;
    reg [255:0] active_digit_pool1_channel_signatures;
    reg [7:0] active_digit_conv1_first_weight;
    reg [7:0] active_digit_conv1_first_activation;
    reg [15:0] active_digit_conv1_first_product;
    reg pending_frame;
    reg [4:0] pending_frame_count;
    reg [4:0] active_frame_count;
    reg active_frame;
    wire uart_busy;

    function [3:0] hex_nibble;
        input [31:0] value;
        input [2:0] index;
        begin
            case (index)
                3'd0: hex_nibble = value[31:28];
                3'd1: hex_nibble = value[27:24];
                3'd2: hex_nibble = value[23:20];
                3'd3: hex_nibble = value[19:16];
                3'd4: hex_nibble = value[15:12];
                3'd5: hex_nibble = value[11:8];
                3'd6: hex_nibble = value[7:4];
                default: hex_nibble = value[3:0];
            endcase
        end
    endfunction

    function [31:0] channel_word;
        input [255:0] value;
        input [3:0] index;
        begin
            channel_word = value[index * 32 +: 32];
        end
    endfunction

    function [7:0] hex_ascii;
        input [3:0] value;
        begin
            hex_ascii = value < 10 ? (8'h30 + {4'd0, value}) : (8'h41 + {4'd0, value - 4'd10});
        end
    endfunction

    function [3:0] decimal_digit;
        input [9:0] value;
        input [1:0] place;
        reg [9:0] remainder;
        begin
            case (place)
                2'd2: decimal_digit = value / 10'd100;
                2'd1: begin
                    remainder = value % 10'd100;
                    decimal_digit = remainder / 10'd10;
                end
                default: begin
                    remainder = value % 10'd10;
                    decimal_digit = remainder[3:0];
                end
            endcase
        end
    endfunction

    always @* begin
        uart_data = 8'h00;
        if (active_model) begin
            case (byte_index)
                5'd0: uart_data = 8'h4d;
                5'd1: uart_data = 8'h4f;
                5'd2: uart_data = 8'h44;
                5'd3: uart_data = 8'h45;
                5'd4: uart_data = 8'h4c;
                5'd5: uart_data = 8'h2c;
                5'd6: uart_data = 8'h52;
                5'd7: uart_data = 8'h38;
                5'd8: uart_data = 8'h44;
                5'd9: uart_data = 8'h31;
                5'd10: uart_data = 8'h2c;
                5'd11: uart_data = hex_ascii(hex_nibble(active_model_crc32, 3'd0));
                5'd12: uart_data = hex_ascii(hex_nibble(active_model_crc32, 3'd1));
                5'd13: uart_data = hex_ascii(hex_nibble(active_model_crc32, 3'd2));
                5'd14: uart_data = hex_ascii(hex_nibble(active_model_crc32, 3'd3));
                5'd15: uart_data = hex_ascii(hex_nibble(active_model_crc32, 3'd4));
                5'd16: uart_data = hex_ascii(hex_nibble(active_model_crc32, 3'd5));
                5'd17: uart_data = hex_ascii(hex_nibble(active_model_crc32, 3'd6));
                5'd18: uart_data = hex_ascii(hex_nibble(active_model_crc32, 3'd7));
                5'd19: uart_data = 8'h0d;
                default: uart_data = 8'h0a;
            endcase
        end else if (active_digit) begin
            if (byte_index >= 7'd29 && byte_index <= 7'd36)
                uart_data = hex_ascii(hex_nibble(active_digit_conv1_signature, byte_index - 7'd29));
            else if (byte_index >= 7'd38 && byte_index <= 7'd45)
                uart_data = hex_ascii(hex_nibble(active_digit_pool1_signature, byte_index - 7'd38));
            else if (byte_index >= 7'd47 && byte_index <= 7'd54)
                uart_data = hex_ascii(hex_nibble(active_digit_conv2_signature, byte_index - 7'd47));
            else if (byte_index >= 7'd56 && byte_index <= 7'd63)
                uart_data = hex_ascii(hex_nibble(active_digit_pool2_signature, byte_index - 7'd56));
            else if (byte_index >= 7'd65 && byte_index <= 7'd72)
                uart_data = hex_ascii(hex_nibble(active_digit_conv3_signature, byte_index - 7'd65));
            else if (byte_index >= 7'd74 && byte_index <= 7'd81)
                uart_data = hex_ascii(hex_nibble(active_digit_pool3_signature, byte_index - 7'd74));
            else if (byte_index >= 8'd83 && byte_index <= 8'd90)
                uart_data = hex_ascii(hex_nibble(active_digit_conv1_input_signature, byte_index - 8'd83));
            else if (byte_index >= 8'd92 && byte_index <= 8'd99)
                uart_data = hex_ascii(hex_nibble(active_digit_conv1_weight_signature, byte_index - 8'd92));
            else if (byte_index >= 8'd101 && byte_index <= 8'd108)
                uart_data = hex_ascii(hex_nibble(active_digit_conv1_product_signature, byte_index - 8'd101));
            else if (byte_index >= 8'd110 && byte_index <= 8'd117)
                uart_data = hex_ascii(hex_nibble(active_digit_conv1_accumulator_signature, byte_index - 8'd110));
            else if (byte_index >= 8'd119 && byte_index <= 8'd126)
                uart_data = hex_ascii(hex_nibble(active_digit_conv1_raw_signature, byte_index - 8'd119));
            else case (byte_index)
                5'd0: uart_data = 8'h44;
                5'd1: uart_data = 8'h2c;
                5'd2: uart_data = 8'h30 + {4'd0, decimal_digit(active_digit_x, 2'd2)};
                5'd3: uart_data = 8'h30 + {4'd0, decimal_digit(active_digit_x, 2'd1)};
                5'd4: uart_data = 8'h30 + {4'd0, decimal_digit(active_digit_x, 2'd0)};
                5'd5: uart_data = 8'h2c;
                5'd6: uart_data = 8'h30 + {4'd0, decimal_digit({1'b0, active_digit_y}, 2'd2)};
                5'd7: uart_data = 8'h30 + {4'd0, decimal_digit({1'b0, active_digit_y}, 2'd1)};
                5'd8: uart_data = 8'h30 + {4'd0, decimal_digit({1'b0, active_digit_y}, 2'd0)};
                5'd9: uart_data = 8'h2c;
                5'd10: uart_data = 8'h30 + {4'd0, decimal_digit(active_digit_w, 2'd2)};
                5'd11: uart_data = 8'h30 + {4'd0, decimal_digit(active_digit_w, 2'd1)};
                5'd12: uart_data = 8'h30 + {4'd0, decimal_digit(active_digit_w, 2'd0)};
                5'd13: uart_data = 8'h2c;
                5'd14: uart_data = 8'h30 + {4'd0, decimal_digit({1'b0, active_digit_h}, 2'd2)};
                5'd15: uart_data = 8'h30 + {4'd0, decimal_digit({1'b0, active_digit_h}, 2'd1)};
                5'd16: uart_data = 8'h30 + {4'd0, decimal_digit({1'b0, active_digit_h}, 2'd0)};
                5'd17: uart_data = 8'h2c;
                5'd18: uart_data = 8'h30 + {4'd0, active_digit_class};
                5'd19: uart_data = 8'h2c;
                5'd20: uart_data = hex_ascii(hex_nibble(active_digit_patch_crc32, 3'd0));
                5'd21: uart_data = hex_ascii(hex_nibble(active_digit_patch_crc32, 3'd1));
                5'd22: uart_data = hex_ascii(hex_nibble(active_digit_patch_crc32, 3'd2));
                5'd23: uart_data = hex_ascii(hex_nibble(active_digit_patch_crc32, 3'd3));
                5'd24: uart_data = hex_ascii(hex_nibble(active_digit_patch_crc32, 3'd4));
                5'd25: uart_data = hex_ascii(hex_nibble(active_digit_patch_crc32, 3'd5));
                5'd26: uart_data = hex_ascii(hex_nibble(active_digit_patch_crc32, 3'd6));
                5'd27: uart_data = hex_ascii(hex_nibble(active_digit_patch_crc32, 3'd7));
                5'd28: uart_data = 8'h2c;
                7'd37: uart_data = 8'h2c;
                7'd46: uart_data = 8'h2c;
                7'd55: uart_data = 8'h2c;
                7'd64: uart_data = 8'h2c;
                7'd73: uart_data = 8'h2c;
                8'd82: uart_data = 8'h2c;
                8'd91: uart_data = 8'h2c;
                8'd100: uart_data = 8'h2c;
                8'd109: uart_data = 8'h2c;
                8'd118: uart_data = 8'h2c;
                8'd127: uart_data = 8'h0d;
                default: uart_data = 8'h0a;
            endcase
        end else if (active_channel) begin
            if (byte_index >= 8'd2 && byte_index <= 8'd72 &&
                ((byte_index - 8'd2) % 9) < 8)
                uart_data = hex_ascii(hex_nibble(
                    channel_word(active_digit_conv1_channel_signatures,
                                 (byte_index - 8'd2) / 9),
                    (byte_index - 8'd2) % 9));
            else if (byte_index >= 8'd74 && byte_index <= 8'd144 &&
                     ((byte_index - 8'd74) % 9) < 8)
                uart_data = hex_ascii(hex_nibble(
                    channel_word(active_digit_pool1_channel_signatures,
                                 (byte_index - 8'd74) / 9),
                    (byte_index - 8'd74) % 9));
            else if (byte_index == 8'd146 || byte_index == 8'd147)
                uart_data = hex_ascii(hex_nibble(
                    {24'd0, active_digit_conv1_first_weight}, byte_index - 8'd140));
            else if (byte_index == 8'd149 || byte_index == 8'd150)
                uart_data = hex_ascii(hex_nibble(
                    {24'd0, active_digit_conv1_first_activation}, byte_index - 8'd143));
            else if (byte_index >= 8'd152 && byte_index <= 8'd155)
                uart_data = hex_ascii(hex_nibble(
                    {16'd0, active_digit_conv1_first_product}, byte_index - 8'd148));
            else case (byte_index)
                8'd0: uart_data = 8'h43;
                8'd1: uart_data = 8'h2c;
                8'd10, 8'd19, 8'd28, 8'd37, 8'd46, 8'd55, 8'd64, 8'd73,
                8'd82, 8'd91, 8'd100, 8'd109, 8'd118, 8'd127, 8'd136: uart_data = 8'h2c;
                8'd145, 8'd148, 8'd151: uart_data = 8'h2c;
                8'd156: uart_data = 8'h0d;
                default: uart_data = 8'h0a;
            endcase
        end else if (active_frame) begin
            case (byte_index)
                5'd0: uart_data = 8'h46;
                5'd1: uart_data = 8'h52;
                5'd2: uart_data = 8'h41;
                5'd3: uart_data = 8'h4d;
                5'd4: uart_data = 8'h45;
                5'd5: uart_data = 8'h5f;
                5'd6: uart_data = 8'h44;
                5'd7: uart_data = 8'h4f;
                5'd8: uart_data = 8'h4e;
                5'd9: uart_data = 8'h45;
                5'd10: uart_data = 8'h2c;
                5'd11: uart_data = 8'h30 + {5'd0, active_frame_count / 5'd10};
                5'd12: uart_data = 8'h30 + {5'd0, active_frame_count % 5'd10};
                5'd13: uart_data = 8'h0d;
                default: uart_data = 8'h0a;
            endcase
        end else if (active_pass) begin
            case (byte_index)
                5'd0: uart_data = 8'h44;
                5'd1: uart_data = 8'h44;
                5'd2: uart_data = 8'h52;
                5'd3: uart_data = 8'h20;
                5'd4: uart_data = 8'h4f;
                5'd5: uart_data = 8'h4b;
                5'd6: uart_data = 8'h0d;
                default: uart_data = 8'h0a;
            endcase
        end else begin
            case (byte_index)
                5'd0: uart_data = 8'h44;
                5'd1: uart_data = 8'h44;
                5'd2: uart_data = 8'h52;
                5'd3: uart_data = 8'h20;
                5'd4: uart_data = 8'h45;
                5'd5: uart_data = 8'h52;
                5'd6: uart_data = 8'h52;
                5'd7: uart_data = 8'h0d;
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
            byte_index <= 5'd0;
            uart_req <= 1'b0;
            pending_check <= 1'b0;
            pending_pass <= 1'b0;
            active_pass <= 1'b0;
            pending_model <= 1'b0;
            pending_model_crc32 <= 32'd0;
            active_model <= 1'b0;
            active_model_crc32 <= 32'd0;
            pending_digit <= 1'b0;
            pending_digit_class <= 4'd0;
            pending_digit_x <= 10'd0;
            pending_digit_y <= 9'd0;
            pending_digit_w <= 10'd0;
            pending_digit_h <= 9'd0;
            pending_digit_patch_crc32 <= 32'd0;
            pending_digit_conv1_signature <= 32'd0;
            pending_digit_pool1_signature <= 32'd0;
            pending_digit_conv2_signature <= 32'd0;
            pending_digit_pool2_signature <= 32'd0;
            pending_digit_conv3_signature <= 32'd0;
            pending_digit_pool3_signature <= 32'd0;
            pending_digit_conv1_input_signature <= 32'd0;
            pending_digit_conv1_weight_signature <= 32'd0;
            pending_digit_conv1_product_signature <= 32'd0;
            pending_digit_conv1_accumulator_signature <= 32'd0;
            pending_digit_conv1_raw_signature <= 32'd0;
            pending_digit_conv1_channel_signatures <= 256'd0;
            pending_digit_pool1_channel_signatures <= 256'd0;
            pending_digit_conv1_first_weight <= 8'd0;
            pending_digit_conv1_first_activation <= 8'd0;
            pending_digit_conv1_first_product <= 16'd0;
            active_digit <= 1'b0;
            active_channel <= 1'b0;
            active_digit_class <= 4'd0;
            active_digit_x <= 10'd0;
            active_digit_y <= 9'd0;
            active_digit_w <= 10'd0;
            active_digit_h <= 9'd0;
            active_digit_patch_crc32 <= 32'd0;
            active_digit_conv1_signature <= 32'd0;
            active_digit_pool1_signature <= 32'd0;
            active_digit_conv2_signature <= 32'd0;
            active_digit_pool2_signature <= 32'd0;
            active_digit_conv3_signature <= 32'd0;
            active_digit_pool3_signature <= 32'd0;
            active_digit_conv1_input_signature <= 32'd0;
            active_digit_conv1_weight_signature <= 32'd0;
            active_digit_conv1_product_signature <= 32'd0;
            active_digit_conv1_accumulator_signature <= 32'd0;
            active_digit_conv1_raw_signature <= 32'd0;
            active_digit_conv1_channel_signatures <= 256'd0;
            active_digit_pool1_channel_signatures <= 256'd0;
            active_digit_conv1_first_weight <= 8'd0;
            active_digit_conv1_first_activation <= 8'd0;
            active_digit_conv1_first_product <= 16'd0;
            pending_frame <= 1'b0;
            pending_frame_count <= 5'd0;
            active_frame_count <= 5'd0;
            active_frame <= 1'b0;
        end else begin
            if (model_check_done) begin
                pending_model <= 1'b1;
                pending_model_crc32 <= model_weight_crc32;
            end
            if (check_complete) begin
                pending_check <= 1'b1;
                pending_pass <= check_pass;
            end
            if (digit_done) begin
                pending_digit <= 1'b1;
                pending_digit_class <= digit_class;
                pending_digit_x <= digit_x;
                pending_digit_y <= digit_y;
                pending_digit_w <= digit_w;
                pending_digit_h <= digit_h;
                pending_digit_patch_crc32 <= digit_patch_crc32;
                pending_digit_conv1_signature <= digit_conv1_signature;
                pending_digit_pool1_signature <= digit_pool1_signature;
                pending_digit_conv2_signature <= digit_conv2_signature;
                pending_digit_pool2_signature <= digit_pool2_signature;
                pending_digit_conv3_signature <= digit_conv3_signature;
                pending_digit_pool3_signature <= digit_pool3_signature;
                pending_digit_conv1_input_signature <= digit_conv1_input_signature;
                pending_digit_conv1_weight_signature <= digit_conv1_weight_signature;
                pending_digit_conv1_product_signature <= digit_conv1_product_signature;
                pending_digit_conv1_accumulator_signature <= digit_conv1_accumulator_signature;
                pending_digit_conv1_raw_signature <= digit_conv1_raw_signature;
                pending_digit_conv1_channel_signatures <= digit_conv1_channel_signatures;
                pending_digit_pool1_channel_signatures <= digit_pool1_channel_signatures;
                pending_digit_conv1_first_weight <= digit_conv1_first_weight;
                pending_digit_conv1_first_activation <= digit_conv1_first_activation;
                pending_digit_conv1_first_product <= digit_conv1_first_product;
            end
            if (frame_done) begin
                pending_frame <= 1'b1;
                pending_frame_count <= frame_digit_count;
            end

            case (state)
                ST_IDLE: begin
                    uart_req <= 1'b0;
                    if (pending_check || check_complete) begin
                        active_pass <= pending_check ? pending_pass : check_pass;
                        active_model <= 1'b0;
                        active_digit <= 1'b0;
                        active_frame <= 1'b0;
                        pending_check <= 1'b0;
                        active_model <= 1'b0;
                        byte_index <= 5'd0;
                        state <= ST_REQUEST;
                    end else if (pending_model || model_check_done) begin
                        active_model <= 1'b1;
                        active_model_crc32 <= pending_model ? pending_model_crc32 : model_weight_crc32;
                        active_digit <= 1'b0;
                        active_frame <= 1'b0;
                        pending_model <= 1'b0;
                        byte_index <= 5'd0;
                        state <= ST_REQUEST;
                    end else if (pending_digit || digit_done) begin
                        active_model <= 1'b0;
                        active_digit <= 1'b1;
                        active_frame <= 1'b0;
                        active_digit_class <= pending_digit ? pending_digit_class : digit_class;
                        active_digit_x <= pending_digit ? pending_digit_x : digit_x;
                        active_digit_y <= pending_digit ? pending_digit_y : digit_y;
                        active_digit_w <= pending_digit ? pending_digit_w : digit_w;
                        active_digit_h <= pending_digit ? pending_digit_h : digit_h;
                        active_digit_patch_crc32 <= pending_digit ? pending_digit_patch_crc32 : digit_patch_crc32;
                        active_digit_conv1_signature <= pending_digit ? pending_digit_conv1_signature : digit_conv1_signature;
                        active_digit_pool1_signature <= pending_digit ? pending_digit_pool1_signature : digit_pool1_signature;
                        active_digit_conv2_signature <= pending_digit ? pending_digit_conv2_signature : digit_conv2_signature;
                        active_digit_pool2_signature <= pending_digit ? pending_digit_pool2_signature : digit_pool2_signature;
                        active_digit_conv3_signature <= pending_digit ? pending_digit_conv3_signature : digit_conv3_signature;
                        active_digit_pool3_signature <= pending_digit ? pending_digit_pool3_signature : digit_pool3_signature;
                        active_digit_conv1_input_signature <= pending_digit ? pending_digit_conv1_input_signature : digit_conv1_input_signature;
                        active_digit_conv1_weight_signature <= pending_digit ? pending_digit_conv1_weight_signature : digit_conv1_weight_signature;
                        active_digit_conv1_product_signature <= pending_digit ? pending_digit_conv1_product_signature : digit_conv1_product_signature;
                        active_digit_conv1_accumulator_signature <= pending_digit ? pending_digit_conv1_accumulator_signature : digit_conv1_accumulator_signature;
                        active_digit_conv1_raw_signature <= pending_digit ? pending_digit_conv1_raw_signature : digit_conv1_raw_signature;
                        active_digit_conv1_channel_signatures <= pending_digit ? pending_digit_conv1_channel_signatures : digit_conv1_channel_signatures;
                        active_digit_pool1_channel_signatures <= pending_digit ? pending_digit_pool1_channel_signatures : digit_pool1_channel_signatures;
                        active_digit_conv1_first_weight <= pending_digit ? pending_digit_conv1_first_weight : digit_conv1_first_weight;
                        active_digit_conv1_first_activation <= pending_digit ? pending_digit_conv1_first_activation : digit_conv1_first_activation;
                        active_digit_conv1_first_product <= pending_digit ? pending_digit_conv1_first_product : digit_conv1_first_product;
                        active_channel <= 1'b0;
                        pending_digit <= 1'b0;
                        byte_index <= 5'd0;
                        state <= ST_REQUEST;
                    end else if (pending_frame || frame_done) begin
                        active_model <= 1'b0;
                        active_digit <= 1'b0;
                        active_frame <= 1'b1;
                        active_frame_count <= pending_frame ? pending_frame_count : frame_digit_count;
                        pending_frame <= 1'b0;
                        byte_index <= 5'd0;
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
                        if ((active_model && byte_index == 7'd20) ||
                            (active_digit && byte_index == 8'd128) ||
                            (active_channel && byte_index == 8'd157) ||
                            (active_frame && byte_index == 5'd14) ||
                            (!active_model && !active_digit && !active_channel && !active_frame && active_pass && byte_index == 5'd7) ||
                            (!active_model && !active_digit && !active_channel && !active_frame && !active_pass && byte_index == 5'd8)) begin
                            if (active_digit && byte_index == 8'd128) begin
                                active_digit <= 1'b0;
                                active_channel <= 1'b1;
                                byte_index <= 8'd0;
                                state <= ST_REQUEST;
                            end else begin
                                active_model <= 1'b0;
                                active_digit <= 1'b0;
                                active_channel <= 1'b0;
                                active_frame <= 1'b0;
                                state <= ST_IDLE;
                            end
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
