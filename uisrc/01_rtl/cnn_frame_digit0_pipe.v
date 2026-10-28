`timescale 1ns / 1ps

// First board bring-up path: capture the known upper-left digit ROI from a
// 320x180 binary frame, reduce it to 28x28, and reuse cnn_digit_infer.
module cnn_frame_digit0_pipe #(
    parameter integer ROI_X = 24,
    parameter integer ROI_Y = 10,
    parameter integer ROI_SIZE = 56
)(
    input  wire       capture_clk,
    input  wire       infer_clk,
    input  wire       rst,
    input  wire       frame_start,
    input  wire       pixel_valid,
    input  wire [7:0] pixel_data,
    input  wire       frame_complete,
    output reg        digit_done,
    output reg  [3:0] digit_class,
    output reg        digit_busy
);
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_START = 3'd1;
    localparam [2:0] ST_SEND = 3'd2;
    localparam [2:0] ST_WAIT = 3'd3;

    reg [9:0] pixel_x;
    reg [8:0] pixel_y;
    reg [9:0] roi_write_index;
    reg [7:0] roi_mem [0:783];
    reg [12:0] roi_bright_count;
    reg [12:0] roi_dark_count;
    reg roi_invert;
    reg frame_capture_enabled;
    reg capture_pixel_valid;
    reg [7:0] capture_pixel_data;
    reg capture_pixel_in_roi;
    reg capture_pixel_sample;
    reg capture_pixel_enabled;
    reg frame_complete_d;
    reg digit_busy_meta;
    reg digit_busy_sync;
    reg [2:0] state;
    reg [9:0] send_count;
    reg frame_toggle;
    reg frame_toggle_meta;
    reg frame_toggle_sync;
    reg frame_toggle_seen;
    wire infer_start = (state == ST_START);
    wire infer_pixel_valid = (state == ST_SEND);
    wire [7:0] roi_pixel = roi_mem[send_count];
    wire [7:0] infer_pixel_data = roi_invert ? (8'hff - roi_pixel) : roi_pixel;
    wire infer_busy;
    wire infer_done;
    wire [3:0] infer_class;
    wire [9:0] current_x = frame_start ? 10'd0 : pixel_x;
    wire [8:0] current_y = frame_start ? 9'd0 : pixel_y;
    wire in_roi = (current_x >= ROI_X) && (current_x < ROI_X + ROI_SIZE) &&
                  (current_y >= ROI_Y) && (current_y < ROI_Y + ROI_SIZE);
    wire [5:0] roi_x = current_x - ROI_X;
    wire [5:0] roi_y = current_y - ROI_Y;
    wire roi_sample = !roi_x[0] && !roi_y[0];

    cnn_digit_infer u_infer (
        .clk(infer_clk),
        .rst_n(~rst),
        .start(infer_start),
        .pixel_valid(infer_pixel_valid),
        .pixel_data(infer_pixel_data),
        .busy(infer_busy),
        .done(infer_done),
        .class_id(infer_class)
    );

    always @(posedge capture_clk or posedge rst) begin
        if (rst) begin
            pixel_x <= 10'd0;
            pixel_y <= 9'd0;
            roi_write_index <= 10'd0;
            roi_bright_count <= 13'd0;
            roi_dark_count <= 13'd0;
            roi_invert <= 1'b0;
            frame_capture_enabled <= 1'b0;
            capture_pixel_valid <= 1'b0;
            capture_pixel_data <= 8'd0;
            capture_pixel_in_roi <= 1'b0;
            capture_pixel_sample <= 1'b0;
            capture_pixel_enabled <= 1'b0;
            frame_complete_d <= 1'b0;
            frame_toggle <= 1'b0;
            digit_busy_meta <= 1'b0;
            digit_busy_sync <= 1'b0;
        end else begin
            digit_busy_meta <= digit_busy;
            digit_busy_sync <= digit_busy_meta;
            capture_pixel_valid <= pixel_valid;
            capture_pixel_data <= pixel_data;
            capture_pixel_in_roi <= in_roi;
            capture_pixel_sample <= roi_sample;
            capture_pixel_enabled <= frame_start ? !digit_busy_sync : frame_capture_enabled;
            frame_complete_d <= frame_complete;

            if (capture_pixel_valid && capture_pixel_enabled && capture_pixel_in_roi) begin
                if (capture_pixel_sample) begin
                    roi_mem[roi_write_index] <= capture_pixel_data;
                    roi_write_index <= roi_write_index + 1'b1;
                end
                if (capture_pixel_data >= 8'd128)
                    roi_bright_count <= roi_bright_count + 1'b1;
                else
                    roi_dark_count <= roi_dark_count + 1'b1;
            end

            if (frame_start) begin
                pixel_x <= pixel_valid ? 10'd1 : 10'd0;
                pixel_y <= 9'd0;
                frame_capture_enabled <= !digit_busy_sync;
                if (!digit_busy_sync) begin
                    roi_write_index <= 10'd0;
                    roi_bright_count <= 13'd0;
                    roi_dark_count <= 13'd0;
                end
            end else if (pixel_valid) begin
                if (current_x == 10'd319) begin
                    pixel_x <= 10'd0;
                    if (current_y == 9'd179)
                        pixel_y <= 9'd0;
                    else
                        pixel_y <= current_y + 1'b1;
                end else begin
                    pixel_x <= current_x + 1'b1;
                    pixel_y <= current_y;
                end
            end

            if (frame_complete_d) begin
                if (frame_capture_enabled && roi_bright_count >= 13'd32 && roi_dark_count >= 13'd32) begin
                    roi_invert <= (roi_bright_count > roi_dark_count);
                    frame_toggle <= ~frame_toggle;
                end
                frame_capture_enabled <= 1'b0;
                roi_bright_count <= 13'd0;
                roi_dark_count <= 13'd0;
            end
        end
    end

    always @(posedge infer_clk or posedge rst) begin
        if (rst) begin
            frame_toggle_meta <= 1'b0;
            frame_toggle_sync <= 1'b0;
            frame_toggle_seen <= 1'b0;
            state <= ST_IDLE;
            send_count <= 10'd0;
            digit_done <= 1'b0;
            digit_class <= 4'd0;
            digit_busy <= 1'b0;
        end else begin
            frame_toggle_meta <= frame_toggle;
            frame_toggle_sync <= frame_toggle_meta;
            digit_done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    digit_busy <= 1'b0;
                    if (frame_toggle_sync != frame_toggle_seen) begin
                        frame_toggle_seen <= frame_toggle_sync;
                        state <= ST_START;
                        send_count <= 10'd0;
                        digit_busy <= 1'b1;
                    end
                end
                ST_START: begin
                    state <= ST_SEND;
                    send_count <= 10'd0;
                end
                ST_SEND: begin
                    if (send_count == 10'd783)
                        state <= ST_WAIT;
                    else
                        send_count <= send_count + 1'b1;
                end
                ST_WAIT: begin
                    if (infer_done) begin
                        digit_class <= infer_class;
                        digit_done <= 1'b1;
                        digit_busy <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
