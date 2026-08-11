`default_nettype none
`timescale 1ns / 1ps

// 异步 SRAM 控制器回归: 覆盖 32 位读写及四个独立字节写.
module tb_sram_async;
  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg mem_valid = 1'b0;
  reg [31:0] mem_addr = 32'd0;
  reg [31:0] mem_wdata = 32'd0;
  reg [3:0] mem_wstrb = 4'd0;
  wire mem_ready;
  wire [31:0] mem_rdata;
  wire [18:0] sram_addr;
  tri [31:0] sram_dq;
  wire sram0_ce_n, sram1_ce_n, sram0_oe_n, sram1_oe_n;
  wire sram0_we_n, sram1_we_n, sram0_lb_n, sram0_ub_n, sram1_lb_n, sram1_ub_n;

  reg [15:0] mem0 [0:1023];
  reg [15:0] mem1 [0:1023];
  wire cs0 = ~sram0_ce_n;
  wire cs1 = ~sram1_ce_n;
  wire rd0 = cs0 && ~sram0_oe_n && sram0_we_n;
  wire rd1 = cs1 && ~sram1_oe_n && sram1_we_n;

  always #10 clk = ~clk;

  sram_async dut (
    .clk(clk), .resetn(resetn), .mem_valid(mem_valid), .mem_addr(mem_addr),
    .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_ready(mem_ready), .mem_rdata(mem_rdata),
    .sram_addr(sram_addr), .sram_dq(sram_dq), .sram0_ce_n(sram0_ce_n), .sram1_ce_n(sram1_ce_n),
    .sram0_oe_n(sram0_oe_n), .sram1_oe_n(sram1_oe_n), .sram0_we_n(sram0_we_n), .sram1_we_n(sram1_we_n),
    .sram0_lb_n(sram0_lb_n), .sram0_ub_n(sram0_ub_n), .sram1_lb_n(sram1_lb_n), .sram1_ub_n(sram1_ub_n)
  );

  always @(posedge sram0_we_n) if (cs0) begin
    if (!sram0_lb_n) mem0[sram_addr][7:0]  <= sram_dq[7:0];
    if (!sram0_ub_n) mem0[sram_addr][15:8] <= sram_dq[15:8];
  end
  always @(posedge sram1_we_n) if (cs1) begin
    if (!sram1_lb_n) mem1[sram_addr][7:0]  <= sram_dq[23:16];
    if (!sram1_ub_n) mem1[sram_addr][15:8] <= sram_dq[31:24];
  end
  assign sram_dq[7:0]   = (rd0 && !sram0_lb_n) ? mem0[sram_addr][7:0]  : 8'bz;
  assign sram_dq[15:8]  = (rd0 && !sram0_ub_n) ? mem0[sram_addr][15:8] : 8'bz;
  assign sram_dq[23:16] = (rd1 && !sram1_lb_n) ? mem1[sram_addr][7:0]  : 8'bz;
  assign sram_dq[31:24] = (rd1 && !sram1_ub_n) ? mem1[sram_addr][15:8] : 8'bz;

  task automatic access;
    input [31:0] addr;
    input [31:0] wdata;
    input [3:0] wstrb;
    input [31:0] expected;
    begin
      @(posedge clk);
      mem_addr <= addr;
      mem_wdata <= wdata;
      mem_wstrb <= wstrb;
      mem_valid <= 1'b1;
      do @(posedge clk); while (!mem_ready);
      if (wstrb == 0 && mem_rdata !== expected)
        $fatal(1, "SRAM read addr=%08x expected=%08x got=%08x", addr, expected, mem_rdata);
      mem_valid <= 1'b0;
      mem_wstrb <= 4'd0;
    end
  endtask

  integer i;
  initial begin
    for (i = 0; i < 1024; i = i + 1) begin mem0[i] = 16'd0; mem1[i] = 16'd0; end
    repeat (2) @(posedge clk);
    resetn <= 1'b1;
    access(32'h2000_0040, 32'h1122_3344, 4'b1111, 32'd0);
    access(32'h2000_0040, 32'd0,          4'b0000, 32'h1122_3344);
    access(32'h2000_0040, 32'hAA00_0000, 4'b1000, 32'd0);
    access(32'h2000_0040, 32'h0000_BB00, 4'b0010, 32'd0);
    access(32'h2000_0040, 32'd0,          4'b0000, 32'hAA22_BB44);
    $display("SRAM ASYNC PASS: 32-bit read/write + byte enables");
    $finish;
  end
endmodule

`default_nettype wire
