`timescale 1ns / 1ps

// 顶层仿真: trap 后 LED 全亮, 数码管扫描出当前阶段程序的 trap PC.
// TRAP_PC 每个阶段按程序长度改一处即可; 段码期望由 PC 的 6 个半字节经 hex7seg
// 计算得到, 并考虑本板 seg_digit[0] 为最左位 (DIGIT0_IS_LSB=0) 的位序反转.
module tb_top;
  localparam integer CLOCK_HZ   = 50_000_000;
  localparam integer REFRESH_HZ = 8_000_000;
  localparam [31:0]  TRAP_PC    = 32'h0000_0024;

  reg        clk   = 0;
  reg        rst_n = 0;
  wire [7:0] led;
  wire [7:0] seg;
  wire [5:0] seg_digit;

  always #5 clk = ~clk;

  top #(
      .CLOCK_HZ  (CLOCK_HZ),
      .REFRESH_HZ(REFRESH_HZ),
      .MEMFILE   ("src/program.hex")
  ) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .led      (led),
      .seg      (seg),
      .seg_digit(seg_digit)
  );

  // 段码参考译码 (共阳极低电平点亮), 与 seg_display 内的表保持一致.
  function [7:0] hex7seg;
    input [3:0] n;
    begin
      case (n)
        4'h0: hex7seg = 8'hC0;
        4'h1: hex7seg = 8'hF9;
        4'h2: hex7seg = 8'hA4;
        4'h3: hex7seg = 8'hB0;
        4'h4: hex7seg = 8'h99;
        4'h5: hex7seg = 8'h92;
        4'h6: hex7seg = 8'h82;
        4'h7: hex7seg = 8'hF8;
        4'h8: hex7seg = 8'h80;
        4'h9: hex7seg = 8'h90;
        4'hA: hex7seg = 8'h88;
        4'hB: hex7seg = 8'h83;
        4'hC: hex7seg = 8'hC6;
        4'hD: hex7seg = 8'hA1;
        4'hE: hex7seg = 8'h86;
        4'hF: hex7seg = 8'h8E;
        default: hex7seg = 8'hFF;
      endcase
    end
  endfunction

  reg [7:0] seg_at [0:5];
  reg [7:0] exp_seg [0:5];
  integer   k, m;

  initial begin
    $dumpfile("build/top.vcd");
    $dumpvars(0, dut);

    // seg_digit[k] 激活时显示 disp_data 的半字节 (5-k); 由 TRAP_PC 算期望段码.
    for (k = 0; k < 6; k = k + 1) begin
      m            = 5 - k;
      exp_seg[k]   = hex7seg((TRAP_PC >> (m * 4)) & 4'hF);
      seg_at[k]    = 8'hFF;
    end

    repeat (2) @(posedge clk);
    rst_n <= 1;

    wait (dut.cpu.trap);
    #1;
    if (led !== 8'h00)
      $fatal(1, "trap 后 LED 应全亮(00), 得 %02x", led);
    if (dut.cpu.pc !== TRAP_PC)
      $fatal(1, "trap 时 PC 应为 %08x, 得 %08x", TRAP_PC, dut.cpu.pc);

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

    for (k = 0; k < 6; k = k + 1)
      if (seg_at[k] !== exp_seg[k])
        $fatal(1, "digit%0d 段码预期 %02x 得 %02x", k, exp_seg[k], seg_at[k]);

    $display("TOP PASS: trap->LED and PC=%06x on 6-digit display verified", TRAP_PC[23:0]);
    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "tb_top watchdog timeout");
  end
endmodule
