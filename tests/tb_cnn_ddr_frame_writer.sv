`timescale 1ns/1ps

module tb_cnn_ddr_frame_writer;
    reg wr_clk = 1'b0;
    reg rd_clk = 1'b0;
    reg rst = 1'b1;
    reg pixel_valid = 1'b0;
    reg [7:0] pixel_data = 8'd0;
    reg frame_start = 1'b0;
    reg ddr_init_done = 1'b0;
    reg [2:0] busy_cycles = 3'd0;
    wire ddr_busy = busy_cycles != 0;
    wire app_wr_en;
    wire [22:0] app_wr_addr;
    wire [1:0] app_wr_dm;
    wire [31:0] app_wr_din;
    wire writer_idle;
    wire overflow;
    wire [31:0] words_written;
    wire [31:0] busy_timeouts;
    integer write_count = 0;
    reg [22:0] addresses [0:3];
    reg [31:0] write_words [0:3];
    integer timeout_cycles;

    always #5 wr_clk = ~wr_clk;
    always #7 rd_clk = ~rd_clk;

    cnn_ddr_frame_writer dut (
        .wr_clk(wr_clk),
        .rd_clk(rd_clk),
        .rst(rst),
        .pixel_valid(pixel_valid),
        .pixel_data(pixel_data),
        .frame_start(frame_start),
        .ddr_init_done(ddr_init_done),
        .ddr_busy(ddr_busy),
        .app_wr_en(app_wr_en),
        .app_wr_addr(app_wr_addr),
        .app_wr_dm(app_wr_dm),
        .app_wr_din(app_wr_din),
        .writer_idle(writer_idle),
        .overflow(overflow),
        .words_written(words_written),
        .busy_timeouts(busy_timeouts)
    );

    always @(posedge rd_clk) begin
        if (rst) begin
            busy_cycles <= 3'd0;
        end else begin
            if (app_wr_en) begin
                addresses[write_count] <= app_wr_addr;
                write_words[write_count] <= app_wr_din;
                write_count <= write_count + 1;
                busy_cycles <= 3'd3;
            end else if (busy_cycles != 0) begin
                busy_cycles <= busy_cycles - 1'b1;
            end
        end
    end

    task push_pixel;
        input [7:0] value;
        input first_pixel;
        begin
            @(negedge wr_clk);
            pixel_valid = 1'b1;
            pixel_data = value;
            frame_start = first_pixel;
            @(negedge wr_clk);
            pixel_valid = 1'b0;
            frame_start = 1'b0;
        end
    endtask

    initial begin
        repeat (5) @(negedge wr_clk);
        rst = 1'b0;
        ddr_init_done = 1'b1;
        push_pixel(8'h11, 1'b1);
        push_pixel(8'h22, 1'b0);
        push_pixel(8'h33, 1'b0);
        push_pixel(8'h44, 1'b0);
        push_pixel(8'h55, 1'b0);
        push_pixel(8'h66, 1'b0);
        push_pixel(8'h77, 1'b0);
        push_pixel(8'h88, 1'b0);

        timeout_cycles = 0;
        while (write_count < 2 && timeout_cycles < 500) begin
            @(negedge rd_clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (write_count != 2)
            $fatal(1, "timed out waiting for two DDR writes, got %0d", write_count);
        while (!writer_idle && timeout_cycles < 600) begin
            @(negedge wr_clk);
            timeout_cycles = timeout_cycles + 1;
        end

        if (addresses[0] !== 23'd0 || addresses[1] !== 23'd2)
            $fatal(1, "DDR addresses mismatch: %0d, %0d", addresses[0], addresses[1]);
        if (write_words[0] !== 32'h44332211 || write_words[1] !== 32'h88776655)
            $fatal(1, "DDR pixel packing mismatch: %h, %h", write_words[0], write_words[1]);
        if (app_wr_dm !== 2'b00 || overflow || busy_timeouts != 0 || words_written != 2)
            $fatal(1, "DDR writer status mismatch");

        $display("PASS tb_cnn_ddr_frame_writer: byte packing, address stride, busy handshake");
        $finish;
    end
endmodule
