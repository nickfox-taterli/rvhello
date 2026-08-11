`timescale 1ns / 1ps

// timer 单元测试: 验证 counter 自由跑, counter==compare 时 pending 置位,
// 写 0x28 清除, 重设 compare 后能再次命中. 全程 sel_valid=1 恒选中, 组合读口.
module tb_timer;
  reg         clk = 0;
  reg         resetn = 0;
  reg  [31:0] mem_addr;
  reg  [31:0] mem_wdata;
  reg  [3:0]  mem_wstrb;
  wire        mem_ready;
  wire [31:0] mem_rdata;
  wire        timer_pending;

  always #5 clk = ~clk;

  timer dut (
    .clk          (clk),
    .resetn       (resetn),
    .sel_valid    (1'b1),
    .mem_addr     (mem_addr),
    .mem_wdata    (mem_wdata),
    .mem_wstrb    (mem_wstrb),
    .mem_ready    (mem_ready),
    .mem_rdata    (mem_rdata),
    .timer_pending(timer_pending)
  );

  // 写寄存器: negedge 放好地址/数据/选通, 让一个 posedge 落进去, 再撤选通.
  task wr_reg(input [31:0] a, input [31:0] d);
    begin
      @(negedge clk);
      mem_addr  = a;
      mem_wdata = d;
      mem_wstrb = 4'hF;
      @(posedge clk);
      @(negedge clk);
      mem_wstrb = 4'h0;
    end
  endtask

  reg [31:0] cnt;
  initial begin
    $dumpfile("build/timer.vcd");
    $dumpvars(0, dut);

    mem_addr = 32'h0; mem_wdata = 32'h0; mem_wstrb = 4'h0;
    repeat (2) @(posedge clk);
    resetn = 1;

    // compare 复位应为全 1 (默认不命中).
    @(negedge clk); mem_addr = 32'h24; #1;
    if (mem_rdata !== 32'hFFFF_FFFF)
      $fatal(1, "compare 复位预期 FFFFFFFF 得 %08x", mem_rdata);

    // 设 compare=10, counter 自由跑到 10 时 pending 应置位.
    wr_reg(32'h24, 32'd10);
    wait (timer_pending);
    #1;
    if (timer_pending !== 1'b1)
      $fatal(1, "counter==compare 时 pending 未置位");

    // 读 counter, 命中那拍之后 counter 仍在涨, 应 >= 10.
    @(negedge clk); mem_addr = 32'h20; #1;
    if (mem_rdata < 32'd10)
      $fatal(1, "counter 应 >= 10 得 %08x", mem_rdata);
    cnt = mem_rdata;

    // 写 0x28 清 pending.
    wr_reg(32'h28, 32'd1);
    #1;
    if (timer_pending !== 1'b0)
      $fatal(1, "写 0x28 未清除 pending");

    // 重设 compare = 读到的 counter + 10, 应再次命中.
    wr_reg(32'h24, cnt + 32'd10);
    wait (timer_pending);
    #1;
    if (timer_pending !== 1'b1)
      $fatal(1, "重设 compare 后 pending 未再次置位");

    // 再清一次, 确认可重复.
    wr_reg(32'h28, 32'd1);
    #1;
    if (timer_pending !== 1'b0)
      $fatal(1, "第二次清除失败");

    $display("TIMER PASS: counter/compare/pending 置位与清除正确");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "tb_timer watchdog timeout");
  end
endmodule
