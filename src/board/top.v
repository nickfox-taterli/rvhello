`default_nettype none

// SoC 顶层: RV32I 核 + 地址译码器 + BRAM/GPIO/UART/Timer 四个从端.
// 地址地图见 bus_decode: BRAM 0x0-0x3fff, GPIO 0x1000_0000, UART 0x1000_0010,
// Timer 0x1000_0020/24/28. 数码管仍显示架构 PC, LED 平时由 GPIO 驱动, trap 时全亮覆盖.
// 板上串口 TX 接 CP2102 (L18, 115200-8N1).
module top #(
  parameter integer CLOCK_HZ   = 50_000_000,
  parameter integer REFRESH_HZ = 400,
  parameter integer UART_BAUD  = 115200,
  parameter         MEMFILE    = "program.hex",
  parameter integer MEM_WORDS  = 4096          // 16 KiB, 覆盖代码/数据/栈
) (
    input  wire       clk,
    input  wire       rst_n,
    output wire [7:0] led,
    output wire [7:0] seg,
    output wire [5:0] seg_digit,
    output wire       uart_tx
);
  wire        trap;
  wire [31:0] pc;

  // 核(主端) <-> 译码器 之间的总线. mem_instr 现在要送进译码器做取指越界保护.
  wire        mem_valid;
  wire        mem_instr;
  wire        mem_ready;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [31:0] mem_rdata;
  wire [ 3:0] mem_wstrb;

  // 各从端独立的 valid/ready/rdata, 由译码器按地址分发.
  wire        bram_valid,  bram_ready;  wire [31:0] bram_rdata;
  wire        gpio_valid,  gpio_ready;  wire [31:0] gpio_rdata;
  wire        uart_valid,  uart_ready;  wire [31:0] uart_rdata;
  wire        timer_valid, timer_ready; wire [31:0] timer_rdata;
  wire [31:0] gpio_out;
  wire        timer_pending;

  rv32i_core #(
    .RESET_PC(32'h0000_0000)
  ) cpu (
    .clk      (clk),
    .resetn   (rst_n),
    .trap     (trap),
    .mem_valid(mem_valid),
    .mem_instr(mem_instr),
    .mem_ready(mem_ready),
    .mem_addr (mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(mem_rdata),
    .retire   (),
    .pc       (pc)
  );

  bus_decode bus (
    .m_valid      (mem_valid),
    .m_instr      (mem_instr),
    .m_addr       (mem_addr),
    .m_wdata      (mem_wdata),
    .m_wstrb      (mem_wstrb),
    .m_ready      (mem_ready),
    .m_rdata      (mem_rdata),
    .s_bram_valid (bram_valid),  .s_bram_ready (bram_ready),  .s_bram_rdata (bram_rdata),
    .s_gpio_valid (gpio_valid),  .s_gpio_ready (gpio_ready),  .s_gpio_rdata (gpio_rdata),
    .s_uart_valid (uart_valid),  .s_uart_ready (uart_ready),  .s_uart_rdata (uart_rdata),
    .s_timer_valid(timer_valid), .s_timer_ready(timer_ready), .s_timer_rdata(timer_rdata)
  );

  // 统一程序/数据后端: 自己管 valid/ready 握手, 核只管按住 valid 等 ready.
  prog_mem #(
    .WORDS  (MEM_WORDS),
    .MEMFILE(MEMFILE)
  ) mem (
    .clk       (clk),
    .mem_valid (bram_valid),
    .mem_addr  (mem_addr),
    .mem_wdata (mem_wdata),
    .mem_wstrb (mem_wstrb),
    .mem_ready (bram_ready),
    .mem_rdata (bram_rdata)
  );

  gpio gpio_inst (
    .clk       (clk),
    .resetn    (rst_n),
    .sel_valid (gpio_valid),
    .mem_wdata (mem_wdata),
    .mem_wstrb (mem_wstrb),
    .mem_ready (gpio_ready),
    .mem_rdata (gpio_rdata),
    .gpio_out  (gpio_out)
  );

  uart_tx #(
    .CLK_HZ(CLOCK_HZ),
    .BAUD  (UART_BAUD)
  ) uart0 (
    .clk       (clk),
    .resetn    (rst_n),
    .sel_valid (uart_valid),
    .mem_wdata (mem_wdata),
    .mem_wstrb (mem_wstrb),
    .mem_ready (uart_ready),
    .mem_rdata (uart_rdata),
    .ser_tx    (uart_tx)
  );

  timer timer_inst (
    .clk          (clk),
    .resetn       (rst_n),
    .sel_valid    (timer_valid),
    .mem_addr     (mem_addr),
    .mem_wdata    (mem_wdata),
    .mem_wstrb    (mem_wstrb),
    .mem_ready    (timer_ready),
    .mem_rdata    (timer_rdata),
    .timer_pending(timer_pending)
  );

  seg_display #(
    .CLOCK_HZ  (CLOCK_HZ),
    .REFRESH_HZ(REFRESH_HZ)
  ) seg_inst (
    .clk      (clk),
    .resetn   (rst_n),
    .disp_data(pc[23:0]),
    .seg      (seg),
    .seg_digit(seg_digit)
  );

  // 平时 LED 反映 GPIO 输出(板载低电平点亮, 故取反); trap 时全亮, 把停机顶出来.
  // timer_pending 暂时只内部观测, 没接中断也没占 LED.
  assign led = trap ? 8'h00 : ~gpio_out[7:0];
endmodule

`default_nettype wire
