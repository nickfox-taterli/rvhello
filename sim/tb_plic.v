`timescale 1ns / 1ps
`default_nettype none

module tb_plic;
  localparam [31:0] PRIORITY0 = 32'h0c00_0000;
  localparam [31:0] PRIORITY2 = 32'h0c00_0008;
  localparam [31:0] PRIORITY3 = 32'h0c00_000c;
  localparam [31:0] PRIORITY5 = 32'h0c00_0014;
  localparam [31:0] PRIORITY32 = 32'h0c00_0080;
  localparam [31:0] PENDING0 = 32'h0c00_1000;
  localparam [31:0] PENDING1 = 32'h0c00_1004;
  localparam [31:0] TRIGGER0 = 32'h0c00_1080;
  localparam [31:0] TRIGGER1 = 32'h0c00_1084;
  localparam [31:0] ENABLE0 = 32'h0c00_2000;
  localparam [31:0] ENABLE1 = 32'h0c00_2004;
  localparam [31:0] THRESHOLD = 32'h0c20_0000;
  localparam [31:0] CLAIM = 32'h0c20_0004;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg [31:0] irq_async = 32'd0;
  reg sel_valid = 1'b0;
  reg [31:0] mem_addr = 32'd0;
  reg [31:0] mem_wdata = 32'd0;
  reg [3:0] mem_wstrb = 4'd0;
  wire mem_ready;
  wire [31:0] mem_rdata;
  wire meip;
  reg [31:0] read_value;

  always #5 clk = ~clk;

  plic #(
    .SOURCES(32),
    .PRIORITY_BITS(3)
  ) dut (
    .clk(clk), .resetn(resetn), .irq_async(irq_async),
    .sel_valid(sel_valid), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb), .mem_ready(mem_ready), .mem_rdata(mem_rdata),
    .meip(meip)
  );

  task automatic mmio_write;
    input [31:0] addr;
    input [31:0] data;
    input [3:0] strb;
    begin
      @(negedge clk);
      sel_valid = 1'b1;
      mem_addr = addr;
      mem_wdata = data;
      mem_wstrb = strb;
      #1;
      if (!mem_ready) $fatal(1, "PLIC 写没有 ready");
      @(negedge clk);
      sel_valid = 1'b0;
      mem_wstrb = 4'd0;
    end
  endtask

  task automatic mmio_read;
    input [31:0] addr;
    output [31:0] data;
    begin
      @(negedge clk);
      sel_valid = 1'b1;
      mem_addr = addr;
      mem_wstrb = 4'd0;
      #1;
      if (!mem_ready) $fatal(1, "PLIC 读没有 ready");
      data = mem_rdata;
      @(negedge clk);
      sel_valid = 1'b0;
    end
  endtask

  task automatic pulse_source;
    input integer index;
    begin
      @(negedge clk);
      irq_async[index] = 1'b1;
      @(negedge clk);
      irq_async[index] = 1'b0;
    end
  endtask

  initial begin
    $dumpfile("build/plic.vcd");
    $dumpvars(0, dut);

    repeat (3) @(posedge clk);
    resetn = 1'b1;

    // source 0 保留且硬连为 0.priority 和 threshold 的实现宽度是 3 bit.
    mmio_write(PRIORITY0, 32'hffff_ffff, 4'b1111);
    mmio_read(PRIORITY0, read_value);
    if (read_value !== 32'd0)
      $fatal(1, "source 0 priority 必须为 0: %08x", read_value);
    mmio_write(PRIORITY2, 32'hffff_ffff, 4'b1111);
    mmio_read(PRIORITY2, read_value);
    if (read_value !== 32'd7)
      $fatal(1, "priority WARL 掩码错误: %08x", read_value);
    mmio_write(PRIORITY2, 32'd4, 4'b0010);
    mmio_read(PRIORITY2, read_value);
    if (read_value !== 32'd7)
      $fatal(1, "priority 字节写选通错误: %08x", read_value);

    // 配置四个源.source 2,5,32 使用 edge 扩展,source 3 使用标准 level gateway.
    mmio_write(PRIORITY2, 32'd4, 4'b0001);
    mmio_write(PRIORITY3, 32'd4, 4'b0001);
    mmio_write(PRIORITY5, 32'd6, 4'b0001);
    mmio_write(PRIORITY32, 32'd7, 4'b0001);
    mmio_write(TRIGGER0, 32'h0000_0024, 4'b1111);
    mmio_write(TRIGGER1, 32'h0000_0001, 4'b0001);
    mmio_write(ENABLE0, 32'h0000_002c, 4'b1111);
    mmio_write(ENABLE1, 32'h0000_0001, 4'b0001);

    // 最高 priority 胜出.priority 相同时必须选择最小 source ID.
    fork
      pulse_source(1);
      pulse_source(4);
      begin
        @(negedge clk);
        irq_async[2] = 1'b1;
      end
    join
    repeat (4) @(posedge clk);
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd5)
      $fatal(1, "最高 priority 应选择 source 5,得到 %0d", read_value);
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd2)
      $fatal(1, "同 priority 应选择较小 source 2,得到 %0d", read_value);
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd3)
      $fatal(1, "第三次应 claim source 3,得到 %0d", read_value);
    @(negedge clk);
    irq_async[2] = 1'b0;
    repeat (3) @(posedge clk);
    mmio_write(CLAIM, 32'd2, 4'b1111);
    mmio_write(CLAIM, 32'd3, 4'b1111);
    mmio_write(CLAIM, 32'd5, 4'b1111);

    // threshold 使用严格大于关系.等于 7 的 source 也会被 threshold 7 屏蔽.
    mmio_write(THRESHOLD, 32'hffff_ffff, 4'b0001);
    mmio_read(THRESHOLD, read_value);
    if (read_value !== 32'd7)
      $fatal(1, "threshold WARL 掩码错误: %08x", read_value);
    pulse_source(31);
    repeat (4) @(posedge clk);
    mmio_read(PENDING1, read_value);
    if (read_value[0] !== 1'b1 || meip !== 1'b0)
      $fatal(1, "threshold 不应清 pending,也不应拉起 MEIP: %08x", read_value);
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd0)
      $fatal(1, "被 threshold 屏蔽时 claim 必须返回 0,得到 %0d", read_value);
    mmio_write(THRESHOLD, 32'd6, 4'b0001);
    @(posedge clk);
    #1;
    if (meip !== 1'b1)
      $fatal(1, "降低 threshold 后已有 pending 应立即拉起 MEIP");
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd32)
      $fatal(1, "source 32 claim ID 错误: %0d", read_value);
    mmio_write(CLAIM, 32'd32, 4'b1111);

    // priority 0 表示永不递送,但 pending 位仍必须保存 gateway 请求.
    mmio_write(THRESHOLD, 32'd0, 4'b0001);
    mmio_write(PRIORITY2, 32'd0, 4'b0001);
    pulse_source(1);
    repeat (4) @(posedge clk);
    mmio_read(PENDING0, read_value);
    if (read_value[2] !== 1'b1 || meip !== 1'b0)
      $fatal(1, "priority 0 的 pending/MEIP 语义错误: %08x", read_value);
    mmio_write(PRIORITY2, 32'd1, 4'b0001);
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd2)
      $fatal(1, "提高 priority 后应递送已有请求,得到 %0d", read_value);
    mmio_write(CLAIM, 32'd2, 4'b1111);

    // level gateway 在 complete 前不能重入.complete 后若仍为高则再次请求.
    @(negedge clk);
    irq_async[2] = 1'b1;
    repeat (4) @(posedge clk);
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd3)
      $fatal(1, "level source 首次 claim 错误: %0d", read_value);
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd0)
      $fatal(1, "complete 前同一 gateway 不得重入: %0d", read_value);
    mmio_write(CLAIM, 32'd3, 4'b1111);
    repeat (2) @(posedge clk);
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd3)
      $fatal(1, "保持有效的 level source 应再次请求: %0d", read_value);
    @(negedge clk);
    irq_async[2] = 1'b0;
    repeat (3) @(posedge clk);
    mmio_write(CLAIM, 32'd3, 4'b1111);

    // edge gateway 在输入一直为高时不会因 complete 重触发,新上升沿才会再次请求.
    @(negedge clk);
    irq_async[4] = 1'b1;
    repeat (4) @(posedge clk);
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd5)
      $fatal(1, "edge source 首次 claim 错误: %0d", read_value);
    mmio_write(CLAIM, 32'd5, 4'b1111);
    repeat (3) @(posedge clk);
    if (meip !== 1'b0)
      $fatal(1, "edge source 保持为高时不应重触发");
    @(negedge clk);
    irq_async[4] = 1'b0;
    repeat (3) @(posedge clk);
    pulse_source(4);
    repeat (4) @(posedge clk);
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd5)
      $fatal(1, "edge source 新上升沿没有再次请求: %0d", read_value);
    mmio_write(CLAIM, 32'd5, 4'b1111);

    $display("PLIC PASS: priority,threshold,仲裁,claim/complete 和 gateway 语义均通过");
    $finish;
  end

  initial begin
    #20000;
    $fatal(1, "tb_plic watchdog timeout");
  end
endmodule

`default_nettype wire
