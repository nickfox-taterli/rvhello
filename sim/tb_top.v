`timescale 1ns / 1ps

// SoC 顶层仿真: 跑固件并把首次定时器比较提前,验证 MTIP 进入 ISR 后翻转 LED.
module tb_top;
  localparam integer CLOCK_HZ     = 50_000_000;
  localparam integer REFRESH_HZ   = 8_000_000;
  localparam integer UART_BAUD    = CLOCK_HZ / 20;                                  // 仿真加速
  localparam integer CLKS_PER_BIT = (CLOCK_HZ + UART_BAUD/2) / UART_BAUD;           // = 20
  localparam integer CB           = CLKS_PER_BIT;

  reg        clk   = 0;
  reg        rst_n = 0;
  wire [7:0] led;
  wire [7:0] seg;
  wire [5:0] seg_digit;
  wire       uart_tx;
  reg        cpu_ttck = 1'b0;
  reg        cpu_ttdi = 1'b0;
  reg        cpu_ttms = 1'b1;
  wire       cpu_ttdo;
  wire       cpu_trtck;

  always #5 clk = ~clk;

  top #(
    .CPU_HZ_MHZ(CLOCK_HZ / 1000000),
    .REFRESH_HZ(REFRESH_HZ),
    .UART_BAUD (UART_BAUD),
    .MEMFILE   ("src/program.hex")
  ) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .cpu_ttck (cpu_ttck),
    .cpu_ttdi (cpu_ttdi),
    .cpu_ttdo (cpu_ttdo),
    .cpu_ttms (cpu_ttms),
    .cpu_trtck(cpu_trtck),
    .cpu_trst_n(rst_n),
    .cpu_tsrst_n(rst_n),
    .led      (led),
    .seg      (seg),
    .seg_digit(seg_digit),
    .uart_tx  (uart_tx)
  );

  reg [31:0] gpio_value [0:1];
  integer    gpio_writes;

  initial begin
    gpio_writes = 0;
  end

  // 第一次写来自 main 初始化,第二次写必须来自中断处理函数.
  always @(posedge clk) begin
    if (rst_n && dut.impl.gpio_valid && dut.impl.gpio_ready && (|dut.impl.mem_wstrb)) begin
      if (gpio_writes < 2) gpio_value[gpio_writes] <= dut.impl.mem_wdata;
      gpio_writes <= gpio_writes + 1;
    end
  end

  initial begin
    $dumpfile("build/top.vcd");
    $dumpvars(0, dut);

    repeat (2) @(posedge clk);
    rst_n <= 1;

    // 等固件写完 CSR,再把硬件 mtimecmp 拉近,不用仿真 50M 个时钟周期.
    wait (dut.impl.cpu.csr_mstatus[3] && dut.impl.cpu.csr_mie[7]);
    @(negedge dut.impl.cpu_clk);
    dut.impl.timer_inst.mtimecmp[0] = dut.impl.timer_inst.mtime + 64'd20;

    wait (gpio_writes >= 2);
    wait (dut.impl.cpu.csr_mstatus[3]);
    #1;

    if (gpio_value[0] !== 32'h0000_0000)
      $fatal(1, "GPIO 初始化预期 0 得 %08x", gpio_value[0]);
    if (gpio_value[1] !== 32'h0000_00ff)
      $fatal(1, "定时器 ISR 应把 GPIO 翻转为 ff 得 %08x", gpio_value[1]);
    if (dut.impl.cpu.csr_mcause !== 32'h8000_0007)
      $fatal(1, "mcause 应为 machine timer interrupt 得 %08x", dut.impl.cpu.csr_mcause);
    if (dut.impl.cpu.csr_mepc[1:0] !== 2'b00)
      $fatal(1, "mepc 未按指令对齐 %08x", dut.impl.cpu.csr_mepc);

    // 同时送入 bit 11 和 bit 7,确认通用 IRQ 向量会选择较高编号的外部中断.
    @(negedge dut.impl.cpu_clk);
    dut.impl.cpu.csr_mie[11] = 1'b1;
    force dut.impl.irq_pending = 32'h0000_0880;
    wait (dut.impl.cpu.csr_mcause == 32'h8000_000b);
    release dut.impl.irq_pending;
    wait (dut.impl.cpu.csr_mstatus[3]);
    #1;
    if (dut.impl.cpu.csr_mcause !== 32'h8000_000b)
      $fatal(1, "多 IRQ 优先级预期 cause 11 得 %08x", dut.impl.cpu.csr_mcause);

    // 单独置 MSIP,确认 CLINT 软件中断接到标准 cause 3.
    @(negedge dut.impl.cpu_clk);
    dut.impl.cpu.csr_mie[3] = 1'b1;
    dut.impl.timer_inst.msip[0] = 1'b1;
    wait (dut.impl.cpu.csr_mcause == 32'h8000_0003);
    @(negedge dut.impl.cpu_clk);
    dut.impl.timer_inst.msip[0] = 1'b0;
    wait (dut.impl.cpu.csr_mstatus[3]);
    if (dut.impl.cpu.csr_mcause !== 32'h8000_0003)
      $fatal(1, "MSIP 应进入 machine software interrupt 得 %08x", dut.impl.cpu.csr_mcause);

    $display("TOP IRQ PASS: MSIP cause=%08x, GPIO %02x->%02x, MRET restored MIE",
             dut.impl.cpu.csr_mcause, gpio_value[0], gpio_value[1]);
    $finish;
  end

  initial begin
    #500000;
    $fatal(1, "tb_top watchdog timeout (gpio_writes=%0d)", gpio_writes);
  end
endmodule
