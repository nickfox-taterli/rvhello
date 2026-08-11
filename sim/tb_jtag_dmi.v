`timescale 1ns / 1ps

// 独立 IO TAP 冒烟测试: 读 DTMCS,再通过 DMI 读 ID 并回读 scratch.
module tb_jtag_dmi;
  reg clk = 1'b0;
  reg tck = 1'b0;
  reg trst_n = 1'b1;
  reg tms = 1'b1;
  reg tdi = 1'b0;
  wire tdo;
  wire req_toggle;
  wire req_write;
  wire [6:0] req_addr;
  wire [31:0] req_wdata;
  wire [1:0] ack_bus;
  wire [63:0] rdata_bus;
  wire [1:0] error_bus;
  reg [40:0] scan_out;
  integer i;

  always #5 clk = ~clk;

  jtag_dtm_tap tap (
    .tck(tck), .trst_n(trst_n), .tms(tms), .tdi(tdi), .tdo(tdo),
    .req_toggle(req_toggle), .req_write(req_write), .req_addr(req_addr),
    .req_wdata(req_wdata), .ack_toggle(ack_bus[0]), .rsp_rdata(rdata_bus[31:0]),
    .rsp_error(error_bus[0])
  );

  debug_dmi_regs regs (
    .clk(clk), .resetn(trst_n), .hart_pc(32'h1234_5678), .hart_halted(1'b0),
    .req_toggle({1'b0, req_toggle}), .req_write({1'b0, req_write}),
    .req_addr({7'd0, req_addr}), .req_wdata({32'd0, req_wdata}),
    .ack_toggle(ack_bus), .rsp_rdata(rdata_bus), .rsp_error(error_bus)
  );

  task jtag_clock(input reg next_tms, input reg next_tdi);
    begin
      tms = next_tms;
      tdi = next_tdi;
      #5 tck = 1'b1;
      #5 tck = 1'b0;
      #1;
    end
  endtask

  task set_ir(input [4:0] value);
    begin
      jtag_clock(1'b1, 1'b0);
      jtag_clock(1'b1, 1'b0);
      jtag_clock(1'b0, 1'b0);
      jtag_clock(1'b0, 1'b0);
      for (i = 0; i < 5; i = i + 1)
        jtag_clock(i == 4, value[i]);
      jtag_clock(1'b1, 1'b0);
      jtag_clock(1'b0, 1'b0);
    end
  endtask

  task scan_dr(input integer width, input [40:0] value);
    begin
      scan_out = 41'd0;
      jtag_clock(1'b1, 1'b0);
      jtag_clock(1'b0, 1'b0);
      jtag_clock(1'b0, 1'b0);
      for (i = 0; i < width; i = i + 1) begin
        // TDO 在下降沿更新,下一次上升沿前就是当前移出位.
        scan_out[i] = tdo;
        jtag_clock(i == width-1, value[i]);
      end
      jtag_clock(1'b1, 1'b0);
      jtag_clock(1'b0, 1'b0);
    end
  endtask

  task dmi_access(input [6:0] addr, input [31:0] data, input [1:0] op);
    begin
      scan_dr(41, {addr, data, op});
      repeat (8) jtag_clock(1'b0, 1'b0);
      scan_dr(41, 41'd0);
    end
  endtask

  initial begin
    $dumpfile("build/jtag_dmi.vcd");
    $dumpvars(0, tap);
    #1 trst_n = 1'b0;
    #20;
    trst_n = 1'b1;
    repeat (5) jtag_clock(1'b1, 1'b0);
    jtag_clock(1'b0, 1'b0);

    set_ir(5'h10);
    scan_dr(32, 41'd0);
    if (scan_out[3:0] !== 4'd1 || scan_out[9:4] !== 6'd7)
      $fatal(1, "DTMCS 错误: %08x", scan_out[31:0]);

    set_ir(5'h11);
    dmi_access(7'h70, 32'd0, 2'd1);
    if (scan_out[1:0] !== 2'd0 || scan_out[33:2] !== 32'h5256_4831)
      $fatal(1, "DMI ID 读取错误: %010x", scan_out);

    dmi_access(7'h71, 32'h89ab_cdef, 2'd2);
    dmi_access(7'h71, 32'd0, 2'd1);
    if (scan_out[1:0] !== 2'd0 || scan_out[33:2] !== 32'h89ab_cdef)
      $fatal(1, "DMI scratch 回读错误: %010x", scan_out);

    dmi_access(7'h72, 32'd0, 2'd1);
    if (scan_out[33:2] !== 32'h1234_5678)
      $fatal(1, "DMI PC 观察寄存器错误: %010x", scan_out);

    $display("JTAG DMI PASS: DTMCS,ID,scratch,PC");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "tb_jtag_dmi watchdog timeout");
  end
endmodule
