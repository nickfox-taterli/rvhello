`timescale 1ns / 1ps

// 顶层仿真: CPU 命中 JAL 后 trap 应点亮全部 LED, 且数码管扫描出 PC=0x0C.
// 用极快的 REFRESH_HZ 加速扫描, 便于在仿真里覆盖全部 6 位.
// 段码校验只断言 "恰 1 位显示 C, 其余 5 位显示 0", 不绑定具体物理位序
// (位序反转由 seg_display 的 DIGIT0_IS_LSB 处理).
module tb_top;
  localparam integer CLOCK_HZ   = 50_000_000;
  localparam integer REFRESH_HZ = 8_000_000;

  reg        clk   = 0;
  reg        rst_n = 0;
  wire [7:0] led;
  wire [7:0] seg;
  wire [5:0] seg_digit;

  always #5 clk = ~clk;

  top #(
      .CLOCK_HZ  (CLOCK_HZ),
      .REFRESH_HZ(REFRESH_HZ)
  ) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .led      (led),
      .seg      (seg),
      .seg_digit(seg_digit)
  );

  reg [7:0] seg_at [0:5];
  integer   k, c6;

  initial begin
    $dumpfile("build/top.vcd");
    $dumpvars(0, dut);

    for (k = 0; k < 6; k = k + 1) seg_at[k] = 8'hFF;

    repeat (2) @(posedge clk);
    rst_n <= 1;

    // 等待 CPU 命中 JAL 拉高 trap.
    wait (dut.cpu.trap);
    #1;
    if (led !== 8'h00)
      $fatal(1, "trap 后 LED 应全亮(00), 得 %02x", led);
    if (dut.cpu.pc !== 32'h0000_000C)
      $fatal(1, "trap 时 PC 应为 0x0C, 得 %08x", dut.cpu.pc);

    // 采样覆盖多次完整扫描, 记录每位激活时的段码.
    repeat (300) @(posedge clk) begin
      #1;
      case (seg_digit)
        6'b111110: seg_at[0] = seg;
        6'b111101: seg_at[1] = seg;
        6'b111011: seg_at[2] = seg;
        6'b110111: seg_at[3] = seg;
        6'b101111: seg_at[4] = seg;
        6'b011111: seg_at[5] = seg;
        default: ;
      endcase
    end

    // PC=0x0C: 应恰有 1 位显示 C(段码 C6), 其余 5 位显示 0(段码 C0).
    // 未点亮的位保持初值 FF, 也会在此被捕获.
    c6 = 0;
    for (k = 0; k < 6; k = k + 1) begin
      if (seg_at[k] === 8'hC6) c6 = c6 + 1;
      else if (seg_at[k] !== 8'hC0)
        $fatal(1, "digit%0d 段码异常: 预期 C0 或 C6, 得 %02x", k, seg_at[k]);
    end
    if (c6 !== 1) $fatal(1, "应恰有 1 位显示 C, 实际 %0d 位", c6);

    $display("TOP PASS: trap->LED and PC=0x0C (one C + five 0) on display verified");
    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "tb_top watchdog timeout");
  end
endmodule
