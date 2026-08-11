`default_nettype none

// SoC 地址译码器: 一主多从的纯组合分发, 没有时钟也没有状态.
// 核(唯一主端)的 valid/ready 总线在这里按地址高位拆给 BRAM / GPIO / UART / Timer;
// 命中谁就把请求转给谁, 没命中就当拍 ready 返回 0, 既不挂死也不传播 X.
// 取指只能落在 BRAM: 跑到别处一律返回非法指令编码让核 trap,
// 不许把外设读口当指令执行, 也不许对着 0x00000000 (NOP) 空转跑飞.
module bus_decode (
  // 主端: 接核
  input  wire        m_valid,
  input  wire        m_instr,
  input  wire [31:0] m_addr,
  input  wire [31:0] m_wdata,
  input  wire [3:0]  m_wstrb,
  output wire        m_ready,
  output wire [31:0] m_rdata,

  // 从端: BRAM (取指 + 读写)
  output wire        s_bram_valid,
  input  wire        s_bram_ready,
  input  wire [31:0] s_bram_rdata,

  // 从端: GPIO
  output wire        s_gpio_valid,
  input  wire        s_gpio_ready,
  input  wire [31:0] s_gpio_rdata,

  // 从端: UART
  output wire        s_uart_valid,
  input  wire        s_uart_ready,
  input  wire [31:0] s_uart_rdata,

  // 从端: Timer
  output wire        s_timer_valid,
  input  wire        s_timer_ready,
  input  wire [31:0] s_timer_rdata
);
  // 地址地图:
  //   0x0000_0000 - 0x0000_3fff  BRAM 16 KiB   (addr[31:14] == 0)
  //   0x1000_0000              GPIO           (addr[31:28]==1, [27:8]==0, [7:4]==0)
  //   0x1000_0010              UART           (同上, [7:4]==1)
  //   0x1000_0020 / 24 / 28    Timer          (同上, [7:4]==2, 内部再用 [3:2] 分址)
  wire sel_bram  = (m_addr[31:14] == 18'd0);
  wire sel_mmio  = (m_addr[31:28] == 4'h1) && (m_addr[27:8] == 20'd0);
  wire sel_gpio  = sel_mmio && (m_addr[7:4] == 4'h0);
  wire sel_uart  = sel_mmio && (m_addr[7:4] == 4'h1);
  wire sel_timer = sel_mmio && (m_addr[7:4] == 4'h2);

  // 只把 valid 发给命中的从端, 其余从端 valid=0, 不会产生任何写副作用.
  assign s_bram_valid  = m_valid && sel_bram;
  assign s_gpio_valid  = m_valid && sel_gpio;
  assign s_uart_valid  = m_valid && sel_uart;
  assign s_timer_valid = m_valid && sel_timer;

  // ready 多路: 命中谁就跟谁握手; 都没命中(含取指越界)当拍就绪, 不让核干等.
  assign m_ready =
       sel_bram  ? s_bram_ready  :
       sel_gpio  ? s_gpio_ready  :
       sel_uart  ? s_uart_ready  :
       sel_timer ? s_timer_ready :
                   m_valid;

  // 数据读口多路: 未映射的数据访问返回 0, 不传播 X.
  wire [31:0] data_rdata =
       sel_bram  ? s_bram_rdata  :
       sel_gpio  ? s_gpio_rdata  :
       sel_uart  ? s_uart_rdata  :
       sel_timer ? s_timer_rdata :
                   32'h0000_0000;

  // 取指越界保护: 核把 0x00000000 当合法 NOP, 所以读回 0 只会空转. 这里强制返回全 1,
  // opcode 字段非法 -> 核 default 走 trap, 把跑飞的 PC 当场拦住.
  assign m_rdata = (m_instr && !sel_bram) ? 32'hFFFF_FFFF : data_rdata;
endmodule

`default_nettype wire
