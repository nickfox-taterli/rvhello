`default_nettype none

// GPIO 输出口: 一组按字节可写的输出寄存器, 字读回当前值.
// 挂在 bus_decode 的 valid/ready 总线上当从端: 0 拍组合读口 + 单拍写.
// 板载 LED 低电平点亮, 这里只存逻辑值, 极性转换交给顶层 top.
module gpio (
  input  wire        clk,
  input  wire        resetn,
  input  wire        sel_valid,   // 译码器已 AND 上地址命中 (0x1000_0000)
  input  wire [31:0] mem_wdata,
  input  wire [3:0]  mem_wstrb,
  output wire        mem_ready,
  output wire [31:0] mem_rdata,
  output wire [31:0] gpio_out
);
  reg [31:0] out;

  // 0 拍从端: 命中即就绪. 写门显式带上 ready, 当前与 sel_valid 等价;
  // 以后若改成寄存读口(多拍), 也不会在 valid 还在 ready 没回的拍里重复写.
  assign mem_ready  = sel_valid;
  wire write_pulse  = sel_valid && (|mem_wstrb) && mem_ready;

  always @(posedge clk) begin
    if (!resetn) begin
      out <= 32'd0;
    end else if (write_pulse) begin
      if (mem_wstrb[0]) out[ 7: 0] <= mem_wdata[ 7: 0];
      if (mem_wstrb[1]) out[15: 8] <= mem_wdata[15: 8];
      if (mem_wstrb[2]) out[23:16] <= mem_wdata[23:16];
      if (mem_wstrb[3]) out[31:24] <= mem_wdata[31:24];
    end
  end

  assign mem_rdata = out;
  assign gpio_out  = out;
endmodule

`default_nettype wire
