`timescale 1ns / 1ps

// SoC 顶层仿真: 跑 fw/main.c 固件, 验收两件事:
//   1) UART 串口线 uart_tx 上还原出 'O','K','\n' 三个字节;
//   2) main 第一条 GPIO=1 真的落到总线 (抓写握手).
// 仿真把 UART_BAUD 提到 CLOCK_HZ/20 (每 bit 20 拍), 加速发送, 否则要等上万时钟.
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

  always #5 clk = ~clk;

  top #(
    .CPU_HZ_MHZ(CLOCK_HZ / 1000000),
    .REFRESH_HZ(REFRESH_HZ),
    .UART_BAUD (UART_BAUD),
    .MEMFILE   ("src/program.hex")
  ) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .led      (led),
    .seg      (seg),
    .seg_digit(seg_digit),
    .uart_tx  (uart_tx)
  );

  // 仿真 UART 接收机: 在 uart_tx 上按 CB 拍采一位, 还原字节 (LSB 先发).
  integer   bit_timer;
  reg [3:0] bit_idx;       // 0=start 中点待确认, 1..8=data, 9=stop
  reg [7:0] rx_shift;
  reg       rx_busy;
  integer   got_n;
  reg [7:0] got [0:7];

  initial begin
    rx_busy = 1'b0; bit_idx = 4'd0; bit_timer = 0; rx_shift = 8'd0; got_n = 0;
  end

  always @(posedge clk) begin
    if (!rx_busy) begin
      if (uart_tx === 1'b0) begin            // 检测到 start 位 (idle 为高)
        rx_busy   <= 1'b1;
        bit_timer <= CB/2;                   // 走到 start 中点再确认
        bit_idx   <= 4'd0;
        rx_shift  <= 8'd0;
      end
    end else begin
      if (bit_timer > 1) begin
        bit_timer <= bit_timer - 1;
      end else begin
        if (bit_idx == 4'd0) begin
          bit_timer <= CB;                   // start 确认, 准备采 bit0
          bit_idx   <= 4'd1;
        end else if (bit_idx <= 4'd8) begin
          rx_shift  <= {uart_tx, rx_shift[7:1]};   // 先发的低位右移到低位
          bit_timer <= CB;
          bit_idx   <= bit_idx + 4'd1;
        end else begin
          got[got_n] <= rx_shift;            // bit_idx==9: stop 位, 收一个字节
          got_n      <= got_n + 1;
          rx_busy    <= 1'b0;
        end
      end
    end
  end

  // GPIO 首写监视: 复位后第一次 GPIO 写握手抓 wdata, 期望 main 第一条 GPIO=1.
  reg [31:0] gpio_first;
  reg        gpio_seen;

  initial begin
    gpio_seen = 1'b0; gpio_first = 32'd0;
  end

  // 第一次 GPIO 写握手: 抓 wdata, 并确认它来自 GPO.WR (custom-0, ir.opcode=0x0b)
  // 而非普通 SW -- 这条断言就是 GPO.WR 译码走通的直接证据.
  always @(posedge clk) begin
    if (rst_n && !gpio_seen && dut.impl.gpio_valid && dut.impl.gpio_ready && (|dut.impl.mem_wstrb)) begin
      gpio_first <= dut.impl.mem_wdata;
      gpio_seen  <= 1'b1;
      if (dut.impl.cpu.ir[6:0] !== 7'b0001011)
        $fatal(1, "首次 GPIO 写应来自 GPO.WR(custom-0 0x0b), 实际 ir.opcode=%07b", dut.impl.cpu.ir[6:0]);
    end
  end

  initial begin
    $dumpfile("build/top.vcd");
    $dumpvars(0, dut);

    repeat (2) @(posedge clk);
    rst_n <= 1;

    wait (got_n == 3);

    if (got[0] !== 8'h4F) $fatal(1, "byte0 预期 'O'(4f) 得 %02x", got[0]);
    if (got[1] !== 8'h4B) $fatal(1, "byte1 预期 'K'(4b) 得 %02x", got[1]);
    if (got[2] !== 8'h0A) $fatal(1, "byte2 预期 '\\n'(0a) 得 %02x", got[2]);
    if (!gpio_seen)           $fatal(1, "未观察到 GPIO 写");
    if (gpio_first !== 32'd1) $fatal(1, "GPIO 首写预期 1 得 %08x", gpio_first);

    $display("TOP PASS: UART=\"OK\\n\", GPIO first=%0d", gpio_first);
    $finish;
  end

  initial begin
    #500000;
    $fatal(1, "tb_top watchdog timeout (got_n=%0d)", got_n);
  end
endmodule
