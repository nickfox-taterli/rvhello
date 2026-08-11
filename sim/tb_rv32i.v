`timescale 1ns / 1ps

// rv32i_core 第 7 阶段仿真: 完整 RV32I 主体 + FENCE (NOP).
// FENCE 夹在 SW 与 LW 之间, 验证它对顺序核透明 (LW 仍读回刚存的值); BEQ 跳过 poison.
module tb_rv32i;
  reg        clk    = 0;
  reg        resetn = 0;
  wire       trap;
  wire       mem_valid;
  wire       mem_ready;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [31:0] mem_rdata;
  wire [ 3:0] mem_wstrb;
  wire       retire;
  wire [31:0] pc;

  always #5 clk = ~clk;

  rv32i_core dut (
      .clk      (clk),
      .resetn   (resetn),
      .trap     (trap),
      .mem_valid(mem_valid),
      .mem_instr(),
      .mem_ready(mem_ready),
      .mem_addr (mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),
      .mem_rdata(mem_rdata),
      .retire   (retire),
      .pc       (pc)
  );

  // 核单元测试: prog_mem 直连核, 不过译码器, 跑 sim/program_core.hex 的 ECALL trap 程序.
  prog_mem #(
      .WORDS  (1024),
      .MEMFILE("sim/program_core.hex")
  ) mem (
      .clk       (clk),
      .mem_valid (mem_valid),
      .mem_addr  (mem_addr),
      .mem_wdata (mem_wdata),
      .mem_wstrb (mem_wstrb),
      .mem_ready (mem_ready),
      .mem_rdata (mem_rdata)
  );

  initial begin
    $dumpfile("build/rv32i.vcd");
    $dumpvars(0, dut);

    repeat (2) @(posedge clk);
    resetn <= 1;

    wait (trap);
    #1;

    if (pc !== 32'h0000_0020) $fatal(1, "trap pc expected 0x20 got %08x", pc);
    if (dut.regs[10] !== 32'h0000_0100) $fatal(1, "x10 %08x", dut.regs[10]);
    if (dut.regs[1] !== 32'h0000_0005) $fatal(1, "x1 %08x", dut.regs[1]);
    if (dut.regs[2] !== 32'h0000_0005) $fatal(1, "x2 LW after FENCE %08x", dut.regs[2]);
    if (dut.regs[3] !== 32'h0000_0001) $fatal(1, "x3 (poison skipped) %08x", dut.regs[3]);

    $display("RV32I STAGE7 PASS: FENCE=NOP + full body smoke test, trap@pc=0x20");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "tb_rv32i watchdog timeout");
  end
endmodule
