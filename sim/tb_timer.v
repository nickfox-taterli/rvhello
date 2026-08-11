`timescale 1ns / 1ps

// CLINT 单元测试: 覆盖 64 位寄存器,MTIP 电平语义,MSIP 和多 hart 布局.
module tb_timer;
  reg         clk = 0;
  reg         resetn = 0;
  reg         sel_valid = 1;
  reg  [31:0] mem_addr;
  reg  [31:0] mem_wdata;
  reg  [3:0]  mem_wstrb;
  wire        mem_ready;
  wire [31:0] mem_rdata;
  wire [1:0]  timer_mtip;
  wire [1:0]  timer_msip;

  always #5 clk = ~clk;

  timer #(
    .HARTS(2)
  ) dut (
    .clk       (clk),
    .resetn    (resetn),
    .sel_valid (sel_valid),
    .mem_addr  (mem_addr),
    .mem_wdata (mem_wdata),
    .mem_wstrb (mem_wstrb),
    .mem_ready (mem_ready),
    .mem_rdata (mem_rdata),
    .timer_mtip(timer_mtip),
    .timer_msip(timer_msip)
  );

  task wr_reg(input [31:0] a, input [31:0] d);
    begin
      @(negedge clk);
      mem_addr  = a;
      mem_wdata = d;
      mem_wstrb = 4'hf;
      @(posedge clk);
      @(negedge clk);
      mem_wstrb = 4'h0;
    end
  endtask

  task expect_reg(input [31:0] a, input [31:0] d);
    begin
      @(negedge clk);
      mem_addr = a;
      #1;
      if (mem_rdata !== d)
        $fatal(1, "地址 %08x 预期 %08x 得 %08x", a, d, mem_rdata);
    end
  endtask

  initial begin
    $dumpfile("build/timer.vcd");
    $dumpvars(0, dut);

    mem_addr = 0; mem_wdata = 0; mem_wstrb = 0;
    repeat (2) @(posedge clk);
    resetn = 1;

    expect_reg(32'h0200_4000, 32'hffff_ffff);
    expect_reg(32'h0200_4004, 32'hffff_ffff);
    expect_reg(32'h0200_4008, 32'hffff_ffff);
    expect_reg(32'h0200_400c, 32'hffff_ffff);
    if (timer_mtip !== 2'b00 || timer_msip !== 2'b00)
      $fatal(1, "复位后的中断输出错误");

    // 写 mtime 的高低半,证明计数器超过 32 位仍连续递增.
    wr_reg(32'h0200_bffc, 32'h0000_0001);
    wr_reg(32'h0200_bff8, 32'hffff_fff0);
    repeat (24) @(posedge clk);
    expect_reg(32'h0200_bffc, 32'h0000_0002);

    // hart 0 的阈值放在过去应置 MTIP,调高后应立即撤销.
    wr_reg(32'h0200_4004, 32'h0000_0002);
    wr_reg(32'h0200_4000, 32'h0000_0000);
    #1;
    if (timer_mtip !== 2'b01)
      $fatal(1, "hart 0 MTIP 未按 mtime >= mtimecmp 置位");
    wr_reg(32'h0200_4004, 32'hffff_ffff);
    #1;
    if (timer_mtip !== 2'b00)
      $fatal(1, "调高 hart 0 mtimecmp 后 MTIP 未撤销");

    // 第二个 hart 使用下一组寄存器,不能影响 hart 0.
    wr_reg(32'h0200_400c, 32'h0000_0002);
    wr_reg(32'h0200_4008, 32'h0000_0000);
    #1;
    if (timer_mtip !== 2'b10)
      $fatal(1, "hart 1 mtimecmp 布局或 MTIP 输出错误");

    wr_reg(32'h0200_0004, 32'h0000_0001);
    if (timer_msip !== 2'b10)
      $fatal(1, "hart 1 MSIP 未置位");
    expect_reg(32'h0200_0004, 32'h0000_0001);
    wr_reg(32'h0200_0004, 32'h0000_0000);
    if (timer_msip !== 2'b00)
      $fatal(1, "hart 1 MSIP 未清零");

    $display("TIMER PASS: CLINT 64-bit mtime/mtimecmp, MTIP, MSIP and 2-hart layout");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "tb_timer watchdog timeout");
  end
endmodule
