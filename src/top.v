`default_nettype none

module top #(
    parameter integer CLOCK_HZ     = 50_000_000,
    parameter         MEMFILE      = "program.hex",
    parameter integer CPU_PRESCALE = 500
) (
    input  wire       clk,
    input  wire       rst_n,
    output wire [7:0] led
);
  // 预分频产生单周期时钟使能 cpu_en, 让 microseq 在慢速时间基上运行.
  // delay=F000 计数 * 500 分频 / 50MHz 约 0.61s 每步, 人眼可观测.
  // 这是时钟使能而非门控时钟, 全模块共享同一个 50MHz 时钟.
  localparam integer PRESCALE_W   = (CPU_PRESCALE <= 1) ? 1 : $clog2(CPU_PRESCALE);
  localparam integer PRESCALE_MAX = CPU_PRESCALE - 1;

  reg  [PRESCALE_W-1:0] prescale_cnt;
  wire                  cpu_en = (prescale_cnt == PRESCALE_MAX[PRESCALE_W-1:0]);

  wire [7:0] cpu_led;

  always @(posedge clk) begin
    if (!rst_n)
      prescale_cnt <= {PRESCALE_W{1'b0}};
    else if (cpu_en)
      prescale_cnt <= {PRESCALE_W{1'b0}};
    else
      prescale_cnt <= prescale_cnt + 1'b1;
  end

  microseq #(
      .MEMFILE(MEMFILE)
  ) cpu_inst (
      .clk    (clk),
      .resetn (rst_n),
      .cpu_en (cpu_en),
      .led    (cpu_led),
      .pc     (),
      .retired()
  );

  // 板载 LED 低电平点亮, 因此把 CPU 输出取反后再送到引脚.
  // 指令 led=01 点亮 LED0, 与流水灯直觉一致.
  assign led = ~cpu_led;
endmodule

`default_nettype wire
