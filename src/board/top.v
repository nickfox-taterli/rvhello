`default_nettype none

// SoC 顶层: RV32I 核 + 地址译码器 + BRAM/GPIO/UART/Timer/SRAM 从端.
// 外部 SRAM 固定映射为普通数据区 0x2000_0000-0x200f_ffff. 指令只能从 BRAM 取出.
// 数码管显示架构 PC. LED 平时由 GPIO 驱动, trap 时全亮覆盖.
module soc #(
  parameter integer CPU_HZ_MHZ = 100,
  parameter integer REFRESH_HZ = 400,
  parameter integer UART_BAUD  = 115200,
  parameter         MEMFILE    = "program.hex",
  parameter integer MEM_WORDS  = 4096
) (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        cpu_ttck,
  input  wire        cpu_ttdi,
  output wire        cpu_ttdo,
  input  wire        cpu_ttms,
  output wire        cpu_trtck,
  input  wire        cpu_trst_n,
  output wire [7:0]  led,
  output wire [7:0]  seg,
  output wire [5:0]  seg_digit,
  output wire        uart_tx,
  output wire [18:0] sram_addr,
  inout  wire [31:0] sram_dq,
  output wire        sram0_ce_n,
  output wire        sram1_ce_n,
  output wire        sram0_oe_n,
  output wire        sram1_oe_n,
  output wire        sram0_we_n,
  output wire        sram1_we_n,
  output wire        sram0_lb_n,
  output wire        sram0_ub_n,
  output wire        sram1_lb_n,
  output wire        sram1_ub_n
);
  // 板载 50MHz 经 MMCM 产生 cpu_clk. CLOCK_HZ 同时供 UART 和数码管分频使用.
  localparam integer CLOCK_HZ = CPU_HZ_MHZ * 1000000;

  wire        cpu_clk;
  wire        cpu_rstn;
  wire        pll_locked;
  wire        trap;
  wire [31:0] pc;
  wire        dbg_halted;

  // 核和译码器之间的总线.
  wire        mem_valid;
  wire        mem_instr;
  wire        mem_ready;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [31:0] mem_rdata;
  wire [3:0]  mem_wstrb;

  // 各从端独立的 valid/ready/rdata, 由译码器按地址分发.
  wire        bram_valid;
  wire        bram_ready;
  wire [31:0] bram_rdata;
  wire        gpio_valid;
  wire        gpio_ready;
  wire [31:0] gpio_rdata;
  wire        uart_valid;
  wire        uart_ready;
  wire [31:0] uart_rdata;
  wire        timer_valid;
  wire        timer_ready;
  wire [31:0] timer_rdata;
  wire        sram_valid;
  wire        sram_ready;
  wire [31:0] sram_rdata;
  wire [31:0] gpio_out;
  wire        timer_pending;

  // 中断线
  wire [31:0] irq_pending = {24'd0, timer_pending, 7'd0};

  clk_pll #(
    .CPU_HZ_MHZ(CPU_HZ_MHZ)
  ) pll (
    .clk_in   (clk),
    .ext_rst_n(rst_n),
    .clk_cpu  (cpu_clk),
    .resetn   (cpu_rstn),
    .locked   (pll_locked)
  );

  rv32i_core #(
    .RESET_PC(32'h0000_0000)
  ) cpu (
    .clk      (cpu_clk),
    .resetn   (cpu_rstn),
    // 第一阶段 DMI 只做传输验证,还不把命令寄存器接到 hart 控制线上.
    .dbg_halt_req(1'b0),
    .dbg_resume_req(1'b0),
    .dbg_halted(dbg_halted),
    .irq_pending(irq_pending),
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

  wire [1:0]  dmi_req_toggle;
  wire [1:0]  dmi_req_write;
  wire [13:0] dmi_req_addr;
  wire [63:0] dmi_req_wdata;
  wire [1:0]  dmi_ack_toggle;
  wire [63:0] dmi_rsp_rdata;
  wire [1:0]  dmi_rsp_error;

  assign cpu_trtck = cpu_ttck;

  jtag_dtm_tap io_dtm (
    .tck(cpu_ttck), .trst_n(cpu_trst_n), .tms(cpu_ttms), .tdi(cpu_ttdi),
    .tdo(cpu_ttdo), .req_toggle(dmi_req_toggle[0]), .req_write(dmi_req_write[0]),
    .req_addr(dmi_req_addr[6:0]), .req_wdata(dmi_req_wdata[31:0]),
    .ack_toggle(dmi_ack_toggle[0]), .rsp_rdata(dmi_rsp_rdata[31:0]),
    .rsp_error(dmi_rsp_error[0])
  );

  bscan_dtm xilinx_dtm (
    .sim_resetn(cpu_rstn), .req_toggle(dmi_req_toggle[1]),
    .req_write(dmi_req_write[1]), .req_addr(dmi_req_addr[13:7]),
    .req_wdata(dmi_req_wdata[63:32]), .ack_toggle(dmi_ack_toggle[1]),
    .rsp_rdata(dmi_rsp_rdata[63:32]), .rsp_error(dmi_rsp_error[1])
  );

  debug_dmi_regs dmi_regs (
    .clk(cpu_clk), .resetn(cpu_rstn), .hart_pc(pc), .hart_halted(dbg_halted),
    .req_toggle(dmi_req_toggle), .req_write(dmi_req_write),
    .req_addr(dmi_req_addr), .req_wdata(dmi_req_wdata),
    .ack_toggle(dmi_ack_toggle), .rsp_rdata(dmi_rsp_rdata),
    .rsp_error(dmi_rsp_error)
  );

  bus_decode #(
    .BRAM_WORDS(MEM_WORDS)
  ) bus (
    .m_valid      (mem_valid),
    .m_instr      (mem_instr),
    .m_addr       (mem_addr),
    .m_wdata      (mem_wdata),
    .m_wstrb      (mem_wstrb),
    .m_ready      (mem_ready),
    .m_rdata      (mem_rdata),
    .s_bram_valid (bram_valid),
    .s_bram_ready (bram_ready),
    .s_bram_rdata (bram_rdata),
    .s_gpio_valid (gpio_valid),
    .s_gpio_ready (gpio_ready),
    .s_gpio_rdata (gpio_rdata),
    .s_uart_valid (uart_valid),
    .s_uart_ready (uart_ready),
    .s_uart_rdata (uart_rdata),
    .s_timer_valid(timer_valid),
    .s_timer_ready(timer_ready),
    .s_timer_rdata(timer_rdata),
    .s_sram_valid (sram_valid),
    .s_sram_ready (sram_ready),
    .s_sram_rdata (sram_rdata)
  );

  // BRAM 保存程序镜像和片上数据. 外部 SRAM 只通过自己的地址区访问.
  prog_mem #(
    .WORDS  (MEM_WORDS),
    .MEMFILE(MEMFILE)
  ) mem (
    .clk       (cpu_clk),
    .mem_valid (bram_valid),
    .mem_addr  (mem_addr),
    .mem_wdata (mem_wdata),
    .mem_wstrb (mem_wstrb),
    .mem_ready (bram_ready),
    .mem_rdata (bram_rdata)
  );

  // 板级异步 SRAM 控制器按 100MHz 使用, 因此实际 SRAM 顶层固定为 top_sram.
  sram_async ext_mem (
    .clk       (cpu_clk),
    .resetn    (cpu_rstn),
    .mem_valid (sram_valid),
    .mem_addr  (mem_addr),
    .mem_wdata (mem_wdata),
    .mem_wstrb (mem_wstrb),
    .mem_ready (sram_ready),
    .mem_rdata (sram_rdata),
    .sram_addr (sram_addr),
    .sram_dq   (sram_dq),
    .sram0_ce_n(sram0_ce_n),
    .sram1_ce_n(sram1_ce_n),
    .sram0_oe_n(sram0_oe_n),
    .sram1_oe_n(sram1_oe_n),
    .sram0_we_n(sram0_we_n),
    .sram1_we_n(sram1_we_n),
    .sram0_lb_n(sram0_lb_n),
    .sram0_ub_n(sram0_ub_n),
    .sram1_lb_n(sram1_lb_n),
    .sram1_ub_n(sram1_ub_n)
  );

  gpio gpio_inst (
    .clk       (cpu_clk),
    .resetn    (cpu_rstn),
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
    .clk       (cpu_clk),
    .resetn    (cpu_rstn),
    .sel_valid (uart_valid),
    .mem_wdata (mem_wdata),
    .mem_wstrb (mem_wstrb),
    .mem_ready (uart_ready),
    .mem_rdata (uart_rdata),
    .ser_tx    (uart_tx)
  );

  timer timer_inst (
    .clk          (cpu_clk),
    .resetn       (cpu_rstn),
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
    .clk      (cpu_clk),
    .resetn   (cpu_rstn),
    .disp_data(pc[23:0]),
    .seg      (seg),
    .seg_digit(seg_digit)
  );

  // 板载 LED 为低电平点亮. timer_pending 已接到 CPU 的 MTIP 输入.
  assign led = trap ? 8'h00 : ~gpio_out[7:0];
endmodule

// 日常 BRAM 顶层. SRAM 端口未引出, 因而此顶层的固件不能访问外部 SRAM 地址区.
module top #(
  parameter integer CPU_HZ_MHZ = 100,
  parameter integer REFRESH_HZ = 400,
  parameter integer UART_BAUD  = 115200,
  parameter         MEMFILE    = "program.hex",
  parameter integer MEM_WORDS  = 4096
) (
  input  wire       clk,
  input  wire       rst_n,
  input  wire       cpu_ttck,
  input  wire       cpu_ttdi,
  output wire       cpu_ttdo,
  input  wire       cpu_ttms,
  output wire       cpu_trtck,
  input  wire       cpu_trst_n,
  input  wire       cpu_tsrst_n,
  output wire [7:0] led,
  output wire [7:0] seg,
  output wire [5:0] seg_digit,
  output wire       uart_tx
);
  soc #(
    .CPU_HZ_MHZ(CPU_HZ_MHZ),
    .REFRESH_HZ(REFRESH_HZ),
    .UART_BAUD (UART_BAUD),
    .MEMFILE   (MEMFILE),
    .MEM_WORDS (MEM_WORDS)
  ) impl (
    .clk       (clk),
    .rst_n     (rst_n && cpu_tsrst_n),
    .cpu_ttck  (cpu_ttck),
    .cpu_ttdi  (cpu_ttdi),
    .cpu_ttdo  (cpu_ttdo),
    .cpu_ttms  (cpu_ttms),
    .cpu_trtck (cpu_trtck),
    .cpu_trst_n(cpu_trst_n),
    .led       (led),
    .seg       (seg),
    .seg_digit (seg_digit),
    .uart_tx   (uart_tx),
    .sram_addr (),
    .sram_dq   (),
    .sram0_ce_n(),
    .sram1_ce_n(),
    .sram0_oe_n(),
    .sram1_oe_n(),
    .sram0_we_n(),
    .sram1_we_n(),
    .sram0_lb_n(),
    .sram0_ub_n(),
    .sram1_lb_n(),
    .sram1_ub_n()
  );
endmodule

// 外部 SRAM 顶层. CPU 固定 100MHz, SRAM 是普通数据区, 不保存程序镜像.
module top_sram #(
  parameter integer REFRESH_HZ = 400,
  parameter integer UART_BAUD  = 115200,
  parameter         MEMFILE    = "program.hex",
  parameter integer MEM_WORDS  = 16384
) (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        cpu_ttck,
  input  wire        cpu_ttdi,
  output wire        cpu_ttdo,
  input  wire        cpu_ttms,
  output wire        cpu_trtck,
  input  wire        cpu_trst_n,
  input  wire        cpu_tsrst_n,
  output wire [7:0]  led,
  output wire [7:0]  seg,
  output wire [5:0]  seg_digit,
  output wire        uart_tx,
  output wire [18:0] sram_addr,
  inout  wire [31:0] sram_dq,
  output wire        sram0_ce_n,
  output wire        sram1_ce_n,
  output wire        sram0_oe_n,
  output wire        sram1_oe_n,
  output wire        sram0_we_n,
  output wire        sram1_we_n,
  output wire        sram0_lb_n,
  output wire        sram0_ub_n,
  output wire        sram1_lb_n,
  output wire        sram1_ub_n
);
  soc #(
    .CPU_HZ_MHZ(100),
    .REFRESH_HZ(REFRESH_HZ),
    .UART_BAUD (UART_BAUD),
    .MEMFILE   (MEMFILE),
    .MEM_WORDS (MEM_WORDS)
  ) impl (
    .clk       (clk),
    .rst_n     (rst_n && cpu_tsrst_n),
    .cpu_ttck  (cpu_ttck),
    .cpu_ttdi  (cpu_ttdi),
    .cpu_ttdo  (cpu_ttdo),
    .cpu_ttms  (cpu_ttms),
    .cpu_trtck (cpu_trtck),
    .cpu_trst_n(cpu_trst_n),
    .led       (led),
    .seg       (seg),
    .seg_digit (seg_digit),
    .uart_tx   (uart_tx),
    .sram_addr (sram_addr),
    .sram_dq   (sram_dq),
    .sram0_ce_n(sram0_ce_n),
    .sram1_ce_n(sram1_ce_n),
    .sram0_oe_n(sram0_oe_n),
    .sram1_oe_n(sram1_oe_n),
    .sram0_we_n(sram0_we_n),
    .sram1_we_n(sram1_we_n),
    .sram0_lb_n(sram0_lb_n),
    .sram0_ub_n(sram0_ub_n),
    .sram1_lb_n(sram1_lb_n),
    .sram1_ub_n(sram1_ub_n)
  );
endmodule

`default_nettype wire
