`timescale 1ns / 1ps

// 独立 IO TAP 冒烟测试: 读 DTMCS/DMSTATUS,再执行 abstract register 命令.
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
  wire hart_reg_valid;
  wire hart_reg_write;
  wire [15:0] hart_reg_addr;
  wire [31:0] hart_reg_wdata;
  reg [40:0] scan_out;
  integer i;

  always #5 clk = ~clk;

  jtag_dtm_tap tap (
    .tck(tck), .trst_n(trst_n), .tms(tms), .tdi(tdi), .tdo(tdo),
    .req_toggle(req_toggle), .req_write(req_write), .req_addr(req_addr),
    .req_wdata(req_wdata), .ack_toggle(ack_bus[0]), .rsp_rdata(rdata_bus[31:0]),
    .rsp_error(error_bus[0])
  );

  riscv_debug_dm regs (
    .clk(clk), .resetn(trst_n),
    .req_toggle({1'b0, req_toggle}), .req_write({1'b0, req_write}),
    .req_addr({7'd0, req_addr}), .req_wdata({32'd0, req_wdata}),
    .ack_toggle(ack_bus), .rsp_rdata(rdata_bus), .rsp_error(error_bus),
    .hart_halt_req(), .hart_resume_req(), .hart_halted(1'b1), .ndmreset(),
    .hart_reg_valid(hart_reg_valid), .hart_reg_write(hart_reg_write),
    .hart_reg_addr(hart_reg_addr), .hart_reg_wdata(hart_reg_wdata),
    .hart_reg_rdata(32'ha5a5_5a5a), .hart_reg_ready(hart_reg_valid),
    .hart_reg_error(1'b0), .sb_valid(), .sb_addr(), .sb_wdata(), .sb_wstrb(),
    .sb_ready(1'b0), .sb_rdata(32'd0)
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
    dmi_access(7'h10, 32'h0000_0001, 2'd2);
    dmi_access(7'h11, 32'd0, 2'd1);
    if (scan_out[1:0] !== 2'd0 || scan_out[5:2] !== 4'd2 ||
        !scan_out[9] || !scan_out[10])
      $fatal(1, "DMSTATUS 错误: %010x", scan_out);

    dmi_access(7'h17, 32'h0022_1005, 2'd2);
    repeat (8) jtag_clock(1'b0, 1'b0);
    dmi_access(7'h04, 32'd0, 2'd1);
    if (scan_out[1:0] !== 2'd0 || scan_out[33:2] !== 32'ha5a5_5a5a)
      $fatal(1, "abstract GPR 读取错误: %010x", scan_out);
    if (hart_reg_addr !== 16'h1005 || hart_reg_write)
      $fatal(1, "abstract 命令字段错误");

    $display("JTAG DMI PASS: DTMCS,DMSTATUS,abstract GPR");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "tb_jtag_dmi watchdog timeout");
  end
endmodule
