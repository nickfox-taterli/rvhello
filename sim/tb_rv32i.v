`timescale 1ns / 1ps

// rv32i_core 的 PCPI 仿真: 保留 FENCE 的访存回归, 并检查 8 条 M 指令.
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
      .dbg_halt_req(1'b0),
      .dbg_resume_req(1'b0),
      .dbg_halted(),
      .irq_pending(32'd0),
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

    if (pc !== 32'h0000_009c) $fatal(1, "trap pc expected 0x9c got %08x", pc);
    if (dut.regs[1] !== 32'hffff_ffff) $fatal(1, "x1 %08x", dut.regs[1]);
    if (dut.regs[15] !== 32'h0000_0005) $fatal(1, "x15 LW after FENCE %08x", dut.regs[15]);
    if (dut.regs[14] !== 32'h0000_0001) $fatal(1, "x14 branch poison leaked %08x", dut.regs[14]);
    if (dut.regs[3] !== 32'h0000_0000) $fatal(1, "x3 MUL zero %08x", dut.regs[3]);
    if (dut.regs[4] !== 32'hffff_ffff) $fatal(1, "x4 MUL -1*1 %08x", dut.regs[4]);
    if (dut.regs[5] !== 32'h0000_0000) $fatal(1, "x5 MULH -1*-1 %08x", dut.regs[5]);
    if (dut.regs[6] !== 32'hffff_ffff) $fatal(1, "x6 MULH -1*1 %08x", dut.regs[6]);
    if (dut.regs[7] !== 32'hffff_ffff) $fatal(1, "x7 MULHSU -1*0xffffffff %08x", dut.regs[7]);
    if (dut.regs[8] !== 32'hffff_fffe) $fatal(1, "x8 MULHU 0xffffffff^2 %08x", dut.regs[8]);
    if (dut.regs[9] !== 32'h8000_0000) $fatal(1, "x9 %08x", dut.regs[9]);
    if (dut.regs[10] !== 32'h0000_0000) $fatal(1, "x10 MUL INT_MIN^2 %08x", dut.regs[10]);
    if (dut.regs[11] !== 32'h4000_0000) $fatal(1, "x11 MULH INT_MIN^2 %08x", dut.regs[11]);
    if (dut.regs[12] !== 32'h8000_0000) $fatal(1, "x12 MULHSU INT_MIN*0xffffffff %08x", dut.regs[12]);
    if (dut.regs[13] !== 32'h7fff_ffff) $fatal(1, "x13 MULHU INT_MIN*0xffffffff %08x", dut.regs[13]);
    if (dut.regs[18] !== 32'h0000_0002) $fatal(1, "x18 DIV 7/3 %08x", dut.regs[18]);
    if (dut.regs[19] !== 32'h0000_0002) $fatal(1, "x19 DIVU 7/3 %08x", dut.regs[19]);
    if (dut.regs[21] !== 32'hffff_ffff) $fatal(1, "x21 REM -7/3 %08x", dut.regs[21]);
    if (dut.regs[22] !== 32'h0000_0001) $fatal(1, "x22 REMU 7/3 %08x", dut.regs[22]);
    if (dut.regs[23] !== 32'h8000_0000) $fatal(1, "x23 DIV INT_MIN/-1 %08x", dut.regs[23]);
    if (dut.regs[24] !== 32'h0000_0000) $fatal(1, "x24 REM INT_MIN/-1 %08x", dut.regs[24]);
    if (dut.regs[25] !== 32'hffff_ffff) $fatal(1, "x25 DIV 7/0 %08x", dut.regs[25]);
    if (dut.regs[26] !== 32'hffff_ffff) $fatal(1, "x26 DIVU 7/0 %08x", dut.regs[26]);
    if (dut.regs[27] !== 32'h0000_0007) $fatal(1, "x27 REM 7/0 %08x", dut.regs[27]);
    if (dut.regs[28] !== 32'h0000_0007) $fatal(1, "x28 REMU 7/0 %08x", dut.regs[28]);
    if (dut.regs[29] !== 32'hffff_fffe) $fatal(1, "x29 DIV -7/3 %08x", dut.regs[29]);

    $display("RV32I+M PCPI PASS: all M instructions, trap@pc=0x9c");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "tb_rv32i watchdog timeout");
  end
endmodule
