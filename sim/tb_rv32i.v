`timescale 1ns / 1ps

// rv32i_core 第 2 阶段仿真: 基础 ALU 与比较. 跑完 14 条后命中 ECALL 触发 trap.
// 停机时一次性核对全部结果寄存器与 PC.
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

    if (pc !== 32'h0000_0038)
      $fatal(1, "trap pc expected 0x38 got %08x", pc);
    if (dut.regs[ 1] !== 32'h0000_0007) $fatal(1, "x1  %08x", dut.regs[ 1]);
    if (dut.regs[ 2] !== 32'hFFFF_FFFD) $fatal(1, "x2  %08x", dut.regs[ 2]);
    if (dut.regs[ 3] !== 32'h0000_0004) $fatal(1, "x3  %08x", dut.regs[ 3]);
    if (dut.regs[ 4] !== 32'h0000_000A) $fatal(1, "x4  %08x", dut.regs[ 4]);
    if (dut.regs[ 5] !== 32'h0000_0001) $fatal(1, "x5  %08x", dut.regs[ 5]);
    if (dut.regs[ 6] !== 32'h0000_0000) $fatal(1, "x6  %08x", dut.regs[ 6]);
    if (dut.regs[ 7] !== 32'hFFFF_FFFA) $fatal(1, "x7  %08x", dut.regs[ 7]);
    if (dut.regs[ 8] !== 32'hFFFF_FFFF) $fatal(1, "x8  %08x", dut.regs[ 8]);
    if (dut.regs[ 9] !== 32'h0000_0005) $fatal(1, "x9  %08x", dut.regs[ 9]);
    if (dut.regs[10] !== 32'h0000_0001) $fatal(1, "x10 %08x", dut.regs[10]);
    if (dut.regs[11] !== 32'h0000_0000) $fatal(1, "x11 %08x", dut.regs[11]);
    if (dut.regs[12] !== 32'h0000_0004) $fatal(1, "x12 %08x", dut.regs[12]);
    if (dut.regs[13] !== 32'h0000_0087) $fatal(1, "x13 %08x", dut.regs[13]);
    if (dut.regs[14] !== 32'h0000_0007) $fatal(1, "x14 %08x", dut.regs[14]);

    $display("RV32I STAGE2 PASS: ALU/compare verified, trap@pc=0x38");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "tb_rv32i watchdog timeout");
  end
endmodule
