`timescale 1ns / 1ps
`default_nettype none

module tb_plic;
  localparam [31:0] PENDING0 = 32'h0c00_1000;
  localparam [31:0] PENDING1 = 32'h0c00_1004;
  localparam [31:0] TRIGGER0 = 32'h0c00_1080;
  localparam [31:0] TRIGGER1 = 32'h0c00_1084;
  localparam [31:0] ENABLE0  = 32'h0c00_2000;
  localparam [31:0] ENABLE1  = 32'h0c00_2004;
  localparam [31:0] CLAIM    = 32'h0c20_0004;

  reg         clk = 1'b0;
  reg         resetn = 1'b0;
  reg  [31:0] irq_async = 32'd0;
  reg         sel_valid = 1'b0;
  reg  [31:0] mem_addr = 32'd0;
  reg  [31:0] mem_wdata = 32'd0;
  reg  [3:0]  mem_wstrb = 4'd0;
  wire        mem_ready;
  wire [31:0] mem_rdata;
  wire        meip;
  reg  [31:0] read_value;

  always #5 clk = ~clk;

  plic #(
    .SOURCES(32)
  ) dut (
    .clk(clk), .resetn(resetn), .irq_async(irq_async),
    .sel_valid(sel_valid), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb), .mem_ready(mem_ready), .mem_rdata(mem_rdata),
    .meip(meip)
  );

  task mmio_write;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
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

  task mmio_read;
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

  task pulse_source;
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

    // source 2,5,32 用上升沿.source 3 保持默认的高电平触发.
    mmio_write(TRIGGER0, 32'h0000_0024, 4'b1111);
    mmio_write(TRIGGER1, 32'h0000_0001, 4'b0001);
    mmio_write(ENABLE0, 32'h0000_002c, 4'b1111);
    mmio_write(ENABLE1, 32'h0000_0001, 4'b0001);

    // 一拍异步脉冲经过同步后必须保持 pending,不能因为脉冲结束而丢失.
    pulse_source(4);
    repeat (4) @(posedge clk);
    mmio_read(PENDING0, read_value);
    if (read_value[5] !== 1'b1 || meip !== 1'b1)
      $fatal(1, "source 5 脉冲没有保持 pending: %08x", read_value);

    // 同时加入更高固定优先级的 source 2 和电平 source 3.
    fork
      pulse_source(1);
      begin
        @(negedge clk);
        irq_async[2] = 1'b1;
      end
    join
    repeat (4) @(posedge clk);

    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd2)
      $fatal(1, "固定优先级应先 claim source 2,得到 %0d", read_value);
    mmio_write(CLAIM, 32'd2, 4'b1111);

    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd3)
      $fatal(1, "第二次应 claim source 3,得到 %0d", read_value);

    // complete 前同一电平源不能重入,complete 后若仍为高则必须再次 pending.
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd5)
      $fatal(1, "source 3 未 complete 时应跳到 source 5,得到 %0d", read_value);
    mmio_write(CLAIM, 32'd3, 4'b1111);
    repeat (2) @(posedge clk);
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd3)
      $fatal(1, "仍有效的电平 source 3 应重新 pending,得到 %0d", read_value);
    @(negedge clk);
    irq_async[2] = 1'b0;
    repeat (3) @(posedge clk);
    mmio_write(CLAIM, 32'd3, 4'b1111);
    mmio_write(CLAIM, 32'd5, 4'b1111);

    // source 32 使用第二个 pending/enable/trigger 字,claim ID 仍返回 32.
    pulse_source(31);
    repeat (4) @(posedge clk);
    mmio_read(PENDING1, read_value);
    if (read_value[0] !== 1'b1)
      $fatal(1, "source 32 没有出现在 pending1: %08x", read_value);
    mmio_read(CLAIM, read_value);
    if (read_value !== 32'd32)
      $fatal(1, "source 32 claim ID 错误: %0d", read_value);
    mmio_write(CLAIM, 32'd32, 4'b1111);
    if (meip !== 1'b0)
      $fatal(1, "全部 complete 后 MEIP 应清零");

    $display("PLIC PASS: 同步,脉冲保持,固定优先级,电平重触发和 32 路映射均通过");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "tb_plic watchdog timeout");
  end
endmodule

`default_nettype wire
