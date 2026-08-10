`timescale 1ns / 1ps

// microseq 单元仿真: cpu_en 恒为 1, 直接验证取指/锁存/提交/延时/回跳.
// 加载 sim/program_sim.hex (delay=4): led 走 01->02->04->08->01, next 走 01->02->03->00.
module tb_microseq;
  reg        clk      = 0;
  reg        resetn   = 0;
  reg        cpu_en   = 1'b1;
  wire [7:0] led;
  wire [7:0] pc;
  wire       retired;

  // 50MHz 时钟.
  always #5 clk = ~clk;

  microseq #(
      .MEMFILE("sim/program_sim.hex")
  ) dut (
      .clk   (clk),
      .resetn(resetn),
      .cpu_en(cpu_en),
      .led   (led),
      .pc    (pc),
      .retired(retired)
  );

  // 期望的提交值序列 (按事件顺序, 取模 4 即可覆盖循环).
  reg [7:0] exp_led [0:3];
  reg [7:0] exp_pc  [0:3];
  integer   events;
  time      prev_t;
  time      period;
  integer   i;

  initial begin
    exp_led[0] = 8'h01; exp_led[1] = 8'h02; exp_led[2] = 8'h04; exp_led[3] = 8'h08;
    exp_pc[0]  = 8'h01; exp_pc[1]  = 8'h02; exp_pc[2]  = 8'h03; exp_pc[3]  = 8'h00;

    $dumpfile("build/microseq.vcd");
    $dumpvars(0, dut);

    repeat (2) @(posedge clk);
    resetn <= 1;

    events = 0;
    prev_t = 0;
    // 连续采集 6 次 retire: 01,02,04,08,01,02, 同时验证循环与节拍周期.
    while (events < 6) begin
      @(posedge clk);
      if (retired) begin
        // led/pc 已是本次提交后的新值.
        if (led !== exp_led[events % 4])
          $fatal(1, "event %0d: led expected %02x got %02x",
                 events, exp_led[events % 4], led);
        if (pc !== exp_pc[events % 4])
          $fatal(1, "event %0d: pc expected %02x got %02x",
                 events, exp_pc[events % 4], pc);
        // delay=4 -> EXECUTE + 4*DELAY + READ + WAIT_MEM = 7 拍, 即 70ns.
        if (events > 0) begin
          period = $time - prev_t;
          if (period !== 70)
            $fatal(1, "event %0d: retire period expected 70ns got %0d", events, period);
        end
        prev_t = $time;
        events = events + 1;
      end
    end

    $display("MICROSEQ PASS: led/next sequence and delay period verified");
    $finish;
  end

  // 看门狗, 防止状态机卡死导致仿真挂起.
  initial begin
    #100000;
    $fatal(1, "tb_microseq watchdog timeout");
  end
endmodule
