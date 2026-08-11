`timescale 1ns / 1ps

// rv32i_core 第 6 阶段仿真: Load/Store. 跑完 18 条后命中 ECALL.
// 停机时核对全部结果寄存器与 PC, 重点看字节/半字的通道选择与符号/零扩展.
module tb_rv32i;
  reg        clk    = 0;
  reg        resetn = 0;
  wire       trap;
  wire       mem_valid;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [31:0] mem_rdata;
  wire [ 3:0] mem_wstrb;
  wire       retire;
  wire [31:0] pc;

  always #5 clk = ~clk;

  // 复用 sync_bram 做总线存储, 与顶层一致; mem_ready 同样寄存一拍.
  reg mem_ready_r;
  always @(posedge clk) begin
    if (!resetn) mem_ready_r <= 1'b0;
    else         mem_ready_r <= mem_valid;
  end

  rv32i_core dut (
      .clk      (clk),
      .resetn   (resetn),
      .trap     (trap),
      .mem_valid(mem_valid),
      .mem_instr(),
      .mem_ready(mem_ready_r),
      .mem_addr (mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),
      .mem_rdata(mem_rdata),
      .retire   (retire),
      .pc       (pc)
  );

  sync_bram #(
      .WORDS  (1024),
      .MEMFILE("src/program.hex")
  ) mem (
      .clk  (clk),
      .en   (mem_valid),
      .we   (mem_wstrb),
      .addr (mem_addr[11:2]),
      .wdata(mem_wdata),
      .rdata(mem_rdata)
  );

  initial begin
    $dumpfile("build/rv32i.vcd");
    $dumpvars(0, dut);

    repeat (2) @(posedge clk);
    resetn <= 1;

    wait (trap);
    #1;

    if (pc !== 32'h0000_0048) $fatal(1, "trap pc expected 0x48 got %08x", pc);
    if (dut.regs[10] !== 32'h0000_0100) $fatal(1, "x10 %08x", dut.regs[10]);
    if (dut.regs[11] !== 32'h1234_5678) $fatal(1, "x11 %08x", dut.regs[11]);
    if (dut.regs[12] !== 32'h1234_5678) $fatal(1, "x12 LW  %08x", dut.regs[12]);
    if (dut.regs[13] !== 32'h0000_0078) $fatal(1, "x13 LB0 %08x", dut.regs[13]);
    if (dut.regs[14] !== 32'h0000_0078) $fatal(1, "x14 LBU %08x", dut.regs[14]);
    if (dut.regs[15] !== 32'h0000_0056) $fatal(1, "x15 LB1 %08x", dut.regs[15]);
    if (dut.regs[16] !== 32'h0000_0034) $fatal(1, "x16 LB2 %08x", dut.regs[16]);
    if (dut.regs[17] !== 32'h0000_0012) $fatal(1, "x17 LB3 %08x", dut.regs[17]);
    if (dut.regs[18] !== 32'hFFFF_FF80) $fatal(1, "x18 %08x", dut.regs[18]);
    if (dut.regs[19] !== 32'hFFFF_FF80) $fatal(1, "x19 LB signed %08x", dut.regs[19]);
    if (dut.regs[20] !== 32'h0000_0080) $fatal(1, "x20 LBU %08x", dut.regs[20]);
    if (dut.regs[21] !== 32'hFFFF_FFFF) $fatal(1, "x21 %08x", dut.regs[21]);
    if (dut.regs[22] !== 32'hFFFF_FFFF) $fatal(1, "x22 LH signed %08x", dut.regs[22]);
    if (dut.regs[23] !== 32'h0000_FFFF) $fatal(1, "x23 LHU %08x", dut.regs[23]);

    $display("RV32I STAGE6 PASS: load/store (byte/halfword/word) verified, trap@pc=0x48");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "tb_rv32i watchdog timeout");
  end
endmodule
