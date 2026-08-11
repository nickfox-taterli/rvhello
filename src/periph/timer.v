`default_nettype none

// 简单定时器从端: 自由计数器 + 比较阈值 + pending 标志.
// 地址 0x1000_0020-0x1000_002f 内部再用 addr[3:2] 分址:
//   0x...20 (2'b00) counter  RO  自由运行 32 位计数, 复位为 0
//   0x...24 (2'b01) compare  RW  阈值, 复位为全 1 (默认不命中)
//   0x...28 (2'b10) pending  R=状态; W(有 wstrb)=清除
// pending 置位用"上一拍稳定的 counter/compare"判定: counter==compare 那拍把它锁高,
// 这样两边都在变也不会漏掉命中. pending 直接作为 CPU 的机器定时器中断输入.
module timer (
  input  wire        clk,
  input  wire        resetn,
  input  wire        sel_valid,    // 译码器已 AND 上地址命中 (0x1000_002x)
  input  wire [31:0] mem_addr,     // 只用 [3:2] 分址
  input  wire [31:0] mem_wdata,
  input  wire [3:0]  mem_wstrb,
  output wire        mem_ready,
  output reg  [31:0] mem_rdata,
  output wire        timer_pending
);
  reg [31:0] counter;
  reg [31:0] compare;
  reg        pending;

  // 0 拍从端: 命中即就绪.
  assign mem_ready = sel_valid;

  wire wr_compare = sel_valid && (mem_addr[3:2] == 2'b01) && (|mem_wstrb);
  wire wr_pending = sel_valid && (mem_addr[3:2] == 2'b10) && (|mem_wstrb);

  always @(posedge clk) begin
    if (!resetn) begin
      counter  <= 32'd0;
      compare  <= 32'hFFFF_FFFF;
      pending  <= 1'b0;
    end else begin
      counter <= counter + 32'd1;
      // 用当前(本拍开始时已稳定)的 counter/compare 判命中 -> 命中则拉高 pending.
      if (counter == compare) pending <= 1'b1;
      // 写 compare: 按字节使能更新, 下一拍才参与比较.
      if (wr_compare) begin
        if (mem_wstrb[0]) compare[ 7: 0] <= mem_wdata[ 7: 0];
        if (mem_wstrb[1]) compare[15: 8] <= mem_wdata[15: 8];
        if (mem_wstrb[2]) compare[23:16] <= mem_wdata[23:16];
        if (mem_wstrb[3]) compare[31:24] <= mem_wdata[31:24];
      end
      // 软件写 0x...28 清 pending; 排在置位之后, 所以同一拍里清比置优先.
      if (wr_pending) pending <= 1'b0;
    end
  end

  // 组合读口: 按 addr[3:2] 选寄存器, 未定义偏移 (2'b11, 即 0x...2c) 返回 0.
  always @* begin
    case (mem_addr[3:2])
      2'b00:     mem_rdata = counter;
      2'b01:     mem_rdata = compare;
      2'b10:     mem_rdata = {31'd0, pending};
      default:   mem_rdata = 32'd0;
    endcase
  end

  assign timer_pending = pending;
endmodule

`default_nettype wire
