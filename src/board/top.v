`default_nettype none

// SoC 顶层: RV32I 核 + 地址译码器 + BRAM/GPIO/UART/Timer/PLIC/SRAM 从端.
// 外部 SRAM 固定映射为普通数据区 0x2000_0000-0x200f_ffff. 指令只能从 BRAM 取出.
// 数码管显示架构 PC. LED 平时由 GPIO 驱动, trap 时全亮覆盖.
module soc #(
  parameter integer CPU_HZ_MHZ = 100,
  parameter integer REFRESH_HZ = 400,
  parameter integer UART_BAUD  = 115200,
  parameter         MEMFILE    = "program.hex",
  parameter integer MEM_WORDS  = 4096,
  parameter integer PLIC_SOURCES = 16
) (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        cpu_ttck,
  input  wire        cpu_ttdi,
  output wire        cpu_ttdo,
  input  wire        cpu_ttms,
  output wire        cpu_trtck,
  input  wire        cpu_trst_n,
  input  wire [PLIC_SOURCES-1:0] irq_sources_async,
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
  wire        dbg_halt_req;
  wire        dbg_resume_req;
  wire        dbg_reg_valid;
  wire        dbg_reg_write;
  wire [15:0] dbg_reg_addr;
  wire [31:0] dbg_reg_wdata;
  wire [31:0] dbg_reg_rdata;
  wire        dbg_reg_ready;
  wire        dbg_reg_error;
  wire        dm_ndmreset;
  wire        hart_resetn = cpu_rstn && !dm_ndmreset;

  // Wishbone 互连下游仍转回原来的简单总线,外设不需要跟着改协议.
  wire        mem_valid;
  wire        mem_instr;
  wire        mem_ready;
  wire        mem_error;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [31:0] mem_rdata;
  wire [3:0]  mem_wstrb;
  wire        cpu_mem_valid;
  wire        cpu_mem_instr;
  wire        cpu_mem_ready;
  wire        cpu_mem_error;
  wire [31:0] cpu_mem_addr;
  wire [31:0] cpu_mem_wdata;
  wire [31:0] cpu_mem_rdata;
  wire [3:0]  cpu_mem_wstrb;
  wire        dbg_mem_valid;
  wire        dbg_mem_ready;
  wire [31:0] dbg_mem_addr;
  wire [31:0] dbg_mem_wdata;
  wire [31:0] dbg_mem_rdata;
  wire [3:0]  dbg_mem_wstrb;
  wire        cpu_wb_cyc;
  wire        cpu_wb_stb;
  wire        cpu_wb_we;
  wire [31:0] cpu_wb_adr;
  wire [31:0] cpu_wb_dat_w;
  wire [31:0] cpu_wb_dat_r;
  wire [3:0]  cpu_wb_sel;
  wire        cpu_wb_tga_instr;
  wire        cpu_wb_ack;
  wire        cpu_wb_err;
  wire        dbg_wb_cyc;
  wire        dbg_wb_stb;
  wire        dbg_wb_we;
  wire [31:0] dbg_wb_adr;
  wire [31:0] dbg_wb_dat_w;
  wire [31:0] dbg_wb_dat_r;
  wire [3:0]  dbg_wb_sel;
  wire        dbg_wb_tga_instr;
  wire        dbg_wb_ack;
  wire        dbg_wb_err;
  wire        bus_wb_cyc;
  wire        bus_wb_stb;
  wire        bus_wb_we;
  wire [31:0] bus_wb_adr;
  wire [31:0] bus_wb_dat_w;
  wire [31:0] bus_wb_dat_r;
  wire [3:0]  bus_wb_sel;
  wire        bus_wb_tga_instr;
  wire        bus_wb_ack;
  wire        bus_wb_err;

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
  wire        plic_valid;
  wire        plic_ready;
  wire [31:0] plic_rdata;
  wire        sram_valid;
  wire        sram_ready;
  wire [31:0] sram_rdata;
  wire [31:0] gpio_out;
  wire [0:0]  timer_mtip;
  wire [0:0]  timer_msip;
  wire        plic_meip;

  // 中断线
  wire [31:0] irq_pending = {20'd0, plic_meip, 3'd0, timer_mtip[0],
                             3'd0, timer_msip[0], 3'd0};

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
    .resetn   (hart_resetn),
    .dbg_halt_req(dbg_halt_req),
    .dbg_resume_req(dbg_resume_req),
    .dbg_halted(dbg_halted),
    .dbg_reg_valid(dbg_reg_valid),
    .dbg_reg_write(dbg_reg_write),
    .dbg_reg_addr(dbg_reg_addr),
    .dbg_reg_wdata(dbg_reg_wdata),
    .dbg_reg_rdata(dbg_reg_rdata),
    .dbg_reg_ready(dbg_reg_ready),
    .dbg_reg_error(dbg_reg_error),
    .irq_pending(irq_pending),
    .trap     (trap),
    .mem_valid(cpu_mem_valid),
    .mem_instr(cpu_mem_instr),
    .mem_ready(cpu_mem_ready),
    .mem_error(cpu_mem_error),
    .mem_addr (cpu_mem_addr),
    .mem_wdata(cpu_mem_wdata),
    .mem_wstrb(cpu_mem_wstrb),
    .mem_rdata(cpu_mem_rdata),
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

  riscv_debug_dm dmi_regs (
    .clk(cpu_clk), .resetn(cpu_rstn),
    .req_toggle(dmi_req_toggle), .req_write(dmi_req_write),
    .req_addr(dmi_req_addr), .req_wdata(dmi_req_wdata),
    .ack_toggle(dmi_ack_toggle), .rsp_rdata(dmi_rsp_rdata),
    .rsp_error(dmi_rsp_error),
    .hart_halt_req(dbg_halt_req), .hart_resume_req(dbg_resume_req),
    .hart_halted(dbg_halted), .ndmreset(dm_ndmreset),
    .hart_reg_valid(dbg_reg_valid), .hart_reg_write(dbg_reg_write),
    .hart_reg_addr(dbg_reg_addr), .hart_reg_wdata(dbg_reg_wdata),
    .hart_reg_rdata(dbg_reg_rdata), .hart_reg_ready(dbg_reg_ready),
    .hart_reg_error(dbg_reg_error),
    .sb_valid(dbg_mem_valid), .sb_addr(dbg_mem_addr),
    .sb_wdata(dbg_mem_wdata), .sb_wstrb(dbg_mem_wstrb),
    .sb_ready(dbg_mem_ready), .sb_rdata(dbg_mem_rdata)
  );

  simple_to_wb cpu_bus_adapter (
    .clk(cpu_clk), .resetn(hart_resetn),
    .s_valid(cpu_mem_valid), .s_instr(cpu_mem_instr),
    .s_addr(cpu_mem_addr), .s_wdata(cpu_mem_wdata), .s_wstrb(cpu_mem_wstrb),
    .s_ready(cpu_mem_ready), .s_error(cpu_mem_error), .s_rdata(cpu_mem_rdata),
    .wb_cyc(cpu_wb_cyc), .wb_stb(cpu_wb_stb), .wb_we(cpu_wb_we),
    .wb_adr(cpu_wb_adr), .wb_dat_w(cpu_wb_dat_w), .wb_sel(cpu_wb_sel),
    .wb_tga_instr(cpu_wb_tga_instr), .wb_ack(cpu_wb_ack),
    .wb_err(cpu_wb_err), .wb_dat_r(cpu_wb_dat_r)
  );

  // SBA 仍只在 hart 停住时进入系统总线,先保持现有调试一致性约束.
  simple_to_wb debug_bus_adapter (
    .clk(cpu_clk), .resetn(cpu_rstn),
    .s_valid(dbg_halted && dbg_mem_valid), .s_instr(1'b0),
    .s_addr(dbg_mem_addr), .s_wdata(dbg_mem_wdata), .s_wstrb(dbg_mem_wstrb),
    .s_ready(dbg_mem_ready), .s_error(), .s_rdata(dbg_mem_rdata),
    .wb_cyc(dbg_wb_cyc), .wb_stb(dbg_wb_stb), .wb_we(dbg_wb_we),
    .wb_adr(dbg_wb_adr), .wb_dat_w(dbg_wb_dat_w), .wb_sel(dbg_wb_sel),
    .wb_tga_instr(dbg_wb_tga_instr), .wb_ack(dbg_wb_ack),
    .wb_err(dbg_wb_err), .wb_dat_r(dbg_wb_dat_r)
  );

  wb_arbiter #(
    .MASTERS(2)
  ) bus_arbiter (
    .clk(cpu_clk), .resetn(cpu_rstn),
    .m_cyc({dbg_wb_cyc, cpu_wb_cyc}),
    .m_stb({dbg_wb_stb, cpu_wb_stb}),
    .m_we({dbg_wb_we, cpu_wb_we}),
    .m_adr({dbg_wb_adr, cpu_wb_adr}),
    .m_dat_w({dbg_wb_dat_w, cpu_wb_dat_w}),
    .m_sel({dbg_wb_sel, cpu_wb_sel}),
    .m_tga_instr({dbg_wb_tga_instr, cpu_wb_tga_instr}),
    .m_ack({dbg_wb_ack, cpu_wb_ack}),
    .m_err({dbg_wb_err, cpu_wb_err}),
    .m_dat_r({dbg_wb_dat_r, cpu_wb_dat_r}),
    .s_cyc(bus_wb_cyc), .s_stb(bus_wb_stb), .s_we(bus_wb_we),
    .s_adr(bus_wb_adr), .s_dat_w(bus_wb_dat_w), .s_sel(bus_wb_sel),
    .s_tga_instr(bus_wb_tga_instr), .s_ack(bus_wb_ack),
    .s_err(bus_wb_err), .s_dat_r(bus_wb_dat_r)
  );

  wb_to_simple bus_slave_adapter (
    .wb_cyc(bus_wb_cyc), .wb_stb(bus_wb_stb), .wb_we(bus_wb_we),
    .wb_adr(bus_wb_adr), .wb_dat_w(bus_wb_dat_w), .wb_sel(bus_wb_sel),
    .wb_tga_instr(bus_wb_tga_instr), .wb_ack(bus_wb_ack),
    .wb_err(bus_wb_err), .wb_dat_r(bus_wb_dat_r),
    .m_valid(mem_valid), .m_instr(mem_instr), .m_addr(mem_addr),
    .m_wdata(mem_wdata), .m_wstrb(mem_wstrb), .m_ready(mem_ready),
    .m_error(mem_error), .m_rdata(mem_rdata)
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
    .m_error      (mem_error),
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
    .s_plic_valid (plic_valid),
    .s_plic_ready (plic_ready),
    .s_plic_rdata (plic_rdata),
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

  timer #(
    .HARTS(1)
  ) timer_inst (
    .clk          (cpu_clk),
    .resetn       (cpu_rstn),
    .sel_valid    (timer_valid),
    .mem_addr     (mem_addr),
    .mem_wdata    (mem_wdata),
    .mem_wstrb    (mem_wstrb),
    .mem_ready    (timer_ready),
    .mem_rdata    (timer_rdata),
    .timer_mtip   (timer_mtip),
    .timer_msip   (timer_msip)
  );

  plic #(
    .SOURCES(PLIC_SOURCES)
  ) plic_inst (
    .clk       (cpu_clk),
    .resetn    (cpu_rstn),
    .irq_async (irq_sources_async),
    .sel_valid (plic_valid),
    .mem_addr  (mem_addr),
    .mem_wdata (mem_wdata),
    .mem_wstrb (mem_wstrb),
    .mem_ready (plic_ready),
    .mem_rdata (plic_rdata),
    .meip      (plic_meip)
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

  // 板载 LED 为低电平点亮.CLINT 和 PLIC 只接 CPU 的三个标准机器中断入口.
  assign led = trap ? 8'h00 : ~gpio_out[7:0];
endmodule

// 日常 BRAM 顶层. SRAM 端口未引出, 因而此顶层的固件不能访问外部 SRAM 地址区.
module top #(
  parameter integer CPU_HZ_MHZ = 100,
  parameter integer REFRESH_HZ = 400,
  parameter integer UART_BAUD  = 115200,
  parameter         MEMFILE    = "program.hex",
  parameter integer MEM_WORDS  = 4096,
  parameter integer PLIC_SOURCES = 16
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
    .MEM_WORDS (MEM_WORDS),
    .PLIC_SOURCES(PLIC_SOURCES)
  ) impl (
    .clk       (clk),
    .rst_n     (rst_n && cpu_tsrst_n),
    .cpu_ttck  (cpu_ttck),
    .cpu_ttdi  (cpu_ttdi),
    .cpu_ttdo  (cpu_ttdo),
    .cpu_ttms  (cpu_ttms),
    .cpu_trtck (cpu_trtck),
    .cpu_trst_n(cpu_trst_n),
    .irq_sources_async({PLIC_SOURCES{1'b0}}),
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
  parameter integer MEM_WORDS  = 16384,
  parameter integer PLIC_SOURCES = 16
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
    .MEM_WORDS (MEM_WORDS),
    .PLIC_SOURCES(PLIC_SOURCES)
  ) impl (
    .clk       (clk),
    .rst_n     (rst_n && cpu_tsrst_n),
    .cpu_ttck  (cpu_ttck),
    .cpu_ttdi  (cpu_ttdi),
    .cpu_ttdo  (cpu_ttdo),
    .cpu_ttms  (cpu_ttms),
    .cpu_trtck (cpu_trtck),
    .cpu_trst_n(cpu_trst_n),
    .irq_sources_async({PLIC_SOURCES{1'b0}}),
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
