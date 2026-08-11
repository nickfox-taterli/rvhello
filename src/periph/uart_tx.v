`default_nettype none

// UART 发送从端: 一条串口 TX 线, 挂在 bus_decode 的 valid/ready 总线上.
// 地址 0x1000_0010 同址读写分离:
//   写(任意 wstrb, 取 wdata[7:0]) -> 装入要发送的字节;
//   读 -> bit0 = busy (移位核正在发).
// 握手区分读写: 读(查 busy)随时就绪, 软件 polling 才转得动;
//   写(发字节)只在空闲时 ready, 忙则让核在 S_MEM 停等.
// 软件可轮询 busy 再写, 也可直接连续写让硬件 stall 兜底. 移位核 {stop, data, start}
// 每 CLKS_PER_BIT 拍移一位.
module uart_tx #(
  parameter integer CLK_HZ = 50_000_000,
  parameter integer BAUD   = 115200
) (
  input  wire        clk,
  input  wire        resetn,
  input  wire        sel_valid,   // 译码器已 AND 上地址命中 (0x1000_0010)
  input  wire [31:0] mem_wdata,
  input  wire [3:0]  mem_wstrb,
  output wire        mem_ready,
  output wire [31:0] mem_rdata,
  output wire        ser_tx       // 物理串口线, idle 为高
);
  // 四舍五入算每比特时钟数: 50 MHz / 115200 ~= 434.
  localparam integer CLKS_PER_BIT = (CLK_HZ + BAUD/2) / BAUD;
  localparam integer CBW          = $clog2(CLKS_PER_BIT);
  localparam [CBW-1:0] LAST_COUNT = CLKS_PER_BIT - 1;

  reg [CBW-1:0] baud_count;
  reg [3:0]     bits_left;   // 还要移出多少 bit (含 start + 8 data + stop = 10)
  reg [9:0]     shift_reg;   // {stop=1, data[7:0], start=0}, 从 bit0 先出

  wire busy     = (bits_left != 4'd0);
  wire is_write = (|mem_wstrb);

  // 读随时就绪; 写只在空闲时就绪, 同拍把字节装进移位核. busy 自锁, 装入只发生一次.
  assign mem_ready = sel_valid && (!is_write || !busy);
  wire load_pulse  = is_write && sel_valid && !busy;

  // 读口: bit0 = busy, 其余位补 0.
  assign mem_rdata = {31'd0, busy};

  // 空闲时保持串口线为高(停止位电平); 发送时从移位寄存器最低位顺序吐出.
  assign ser_tx = busy ? shift_reg[0] : 1'b1;

  always @(posedge clk) begin
    if (!resetn) begin
      baud_count <= {CBW{1'b0}};
      bits_left  <= 4'd0;
      shift_reg  <= 10'h3FF;     // 全 1 = 空闲电平
    end else if (load_pulse) begin
      shift_reg  <= {1'b1, mem_wdata[7:0], 1'b0};
      bits_left  <= 4'd10;
      baud_count <= {CBW{1'b0}};
    end else if (busy) begin
      if (baud_count == LAST_COUNT) begin
        baud_count <= {CBW{1'b0}};
        shift_reg  <= {1'b1, shift_reg[9:1]};   // 右移, 高位补停止位电平
        bits_left  <= bits_left - 1'b1;
      end else begin
        baud_count <= baud_count + 1'b1;
      end
    end
  end
endmodule

`default_nettype wire
