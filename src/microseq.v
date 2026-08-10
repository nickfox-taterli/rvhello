`default_nettype none

// 最小微程序序列机: 从 BRAM 取 32 位指令字, 提交 LED 输出, 跳转 PC 并延时.
// 指令格式: {delay[31:16], led[15:8], next[7:0]}.
// 状态机:
//   READ     -> 在该时钟使能沿让 BRAM 采样 pc;
//   WAIT_MEM -> 锁存 BRAM 输出, 解除后续端口时序依赖;
//   EXECUTE  -> 一次性提交 led/pc/delay, retired 拉高一拍;
//   DELAY    -> delay_count 倒计时, 到 0 回到 READ.
//
// cpu_en 是单周期时钟使能, 不是门控时钟: 全模块共用同一个 clk,
// 只有用 cpu_en 限定时寄存器才前进. 顶层用预分频器把 50MHz 拉慢,
// 使 delay=F000 对应约 0.6s 的人眼可观测节拍.
module microseq #(
    parameter MEMFILE = "program.hex"
) (
    input  wire       clk,
    input  wire       resetn,
    input  wire       cpu_en,
    output reg  [7:0] led,
    output reg  [7:0] pc,
    output reg        retired
);
  localparam READ     = 2'd0;
  localparam WAIT_MEM = 2'd1;
  localparam EXECUTE  = 2'd2;
  localparam DELAY    = 2'd3;

  reg  [ 1:0] state;
  // instruction 锁存 BRAM 输出, 使执行阶段不依赖端口后续变化.
  reg  [31:0] instruction;
  // delay_count 是可综合的硬件倒计时器, 不是仿真 delay.
  reg  [15:0] delay_count;
  wire [31:0] memory_rdata;

  sync_bram #(
      .WORDS  (4),
      .MEMFILE(MEMFILE)
  ) program_memory (
      // 存储器暂时只读, 因此所有写使能恒为零; 读使能跟随 cpu_en,
      // 保证 BRAM 的单拍读延迟与状态机的使能节拍对齐.
      .clk  (clk),
      .en   (cpu_en),
      .we   (4'b0000),
      .addr (pc[1:0]),
      .wdata(32'b0),
      .rdata(memory_rdata)
  );

  always @(posedge clk) begin
    // retired 是事件脉冲: 默认拉低, 仅在 EXECUTE 状态置高一拍.
    if (!resetn) begin
      state       <= READ;
      pc          <= 8'd0;
      led         <= 8'd0;
      instruction <= 32'd0;
      delay_count <= 16'd0;
      retired     <= 1'b0;
    end else if (cpu_en) begin
      retired <= 1'b0;
      case (state)
        READ: begin
          // BRAM 在此使能沿采样 pc.
          state <= WAIT_MEM;
        end

        WAIT_MEM: begin
          // 此时 BRAM rdata 已有效, 先锁存再执行.
          instruction <= memory_rdata;
          state       <= EXECUTE;
        end

        EXECUTE: begin
          // 一个程序字产生的全部可见效果在此使能沿一起提交.
          led         <= instruction[15:8];
          pc          <= instruction[7:0];
          delay_count <= instruction[31:16];
          retired     <= 1'b1;
          state       <= DELAY;
        end

        DELAY: begin
          // 延时为 0 或 1 时直接前进, 避免无符号计数器下溢.
          if (delay_count <= 16'd1) state <= READ;
          else delay_count <= delay_count - 16'd1;
        end

        default: state <= READ;
      endcase
    end
  end
endmodule

`default_nettype wire
