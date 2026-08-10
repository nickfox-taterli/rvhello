`timescale 1ns / 1ps

// 顶层仿真: 用小分频和短延时程序, 验证流水灯在引脚上的可见序列.
// CPU led 走 01->02->04->08, 板载低电平点亮, 故引脚电平为 FE->FD->FB->F7 循环.
module tb_top;
  localparam integer CPU_PRESCALE = 2;

  reg        clk   = 0;
  reg        rst_n = 0;
  wire [7:0] led;

  always #5 clk = ~clk;

  top #(
      .MEMFILE     ("sim/program_sim.hex"),
      .CPU_PRESCALE(CPU_PRESCALE)
  ) dut (
      .clk  (clk),
      .rst_n(rst_n),
      .led  (led)
  );

  // 期望的引脚电平序列 (取反后的值), 取模 4 覆盖循环.
  reg [7:0] exp_led [0:3];
  integer   step;

  initial begin
    exp_led[0] = 8'hFE;  // ~01
    exp_led[1] = 8'hFD;  // ~02
    exp_led[2] = 8'hFB;  // ~04
    exp_led[3] = 8'hF7;  // ~08

    $dumpfile("build/top.vcd");
    $dumpvars(0, dut);

    repeat (2) @(posedge clk);
    rst_n <= 1;

    // 等待第一次 EXECUTE 后的引脚翻转 (复位后为 FF), 然后连续校验 8 步 (两圈).
    @(led);
    for (step = 0; step < 8; step = step + 1) begin
      #1;
      if (led !== exp_led[step % 4])
        $fatal(1, "step %0d: expected led=%02x got %02x",
               step, exp_led[step % 4], led);
      @(led);
    end

    $display("TOP PASS: walking LED FE->FD->FB->F7 loop verified");
    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "tb_top watchdog timeout");
  end
endmodule
