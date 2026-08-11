`timescale 1ns / 1ps

// addi_cpu 单元仿真: 跑完三条 ADDI 后命中 JAL 触发 trap.
// 通过层次路径读取内部寄存器, 逐条核对运算结果, 并确认停机时 PC=0x0C.
module tb_addi_cpu;
  reg        clk     = 0;
  reg        resetn  = 0;
  wire       trap;
  wire [31:0] pc;

  always #5 clk = ~clk;

  addi_cpu dut (
      .clk   (clk),
      .resetn(resetn),
      .trap  (trap),
      .pc    (pc)
  );

  // 各里程碑只校验一次.
  reg c1, c2, c3, c4;

  initial begin
    $dumpfile("build/addi_cpu.vcd");
    $dumpvars(0, dut);

    c1 = 0; c2 = 0; c3 = 0; c4 = 0;

    repeat (2) @(posedge clk);
    resetn <= 1;

    forever @(posedge clk) begin
      // 第一条 ADDI x1,x0,5 提交后 pc=4.
      if (!c1 && pc == 32'd4) begin
        c1 = 1;
        if (dut.regs[1] !== 32'd5)
          $fatal(1, "x1 expected 5 got %0d", dut.regs[1]);
      end
      // 第二条 ADDI x2,x1,-2 提交后 pc=8.
      if (!c2 && pc == 32'd8) begin
        c2 = 1;
        if (dut.regs[2] !== 32'd3)
          $fatal(1, "x2 expected 3 got %0d", dut.regs[2]);
      end
      // 第三条 ADDI x3,x2,9 提交后 pc=12.
      if (!c3 && pc == 32'd12) begin
        c3 = 1;
        if (dut.regs[3] !== 32'd12)
          $fatal(1, "x3 expected 12 got %0d", dut.regs[3]);
      end
      // 命中 JAL -> trap, 停机时 pc 应仍为 12.
      if (!c4 && trap) begin
        c4 = 1;
        if (pc !== 32'd12)
          $fatal(1, "trap pc expected 12 got %0d", pc);
        if (dut.regs[1] !== 32'd5 || dut.regs[2] !== 32'd3 || dut.regs[3] !== 32'd12)
          $fatal(1, "final regs wrong: x1=%0d x2=%0d x3=%0d",
                 dut.regs[1], dut.regs[2], dut.regs[3]);
        $display("ADDI PASS: x1=5 x2=3 x3=12, trap@pc=12");
        $finish;
      end
    end
  end

  initial begin
    #100000;
    $fatal(1, "tb_addi_cpu watchdog timeout");
  end
endmodule
