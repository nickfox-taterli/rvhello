`timescale 1ns / 1ps

// rv32i_core 第 3 阶段仿真: 移位. 跑完 9 条后命中 ECALL 触发 trap.
// 停机时一次性核对全部结果寄存器与 PC. 重点对照算术移位(保留符号)与逻辑移位(补零).
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

    if (pc !== 32'h0000_0024)
      $fatal(1, "trap pc expected 0x24 got %08x", pc);
    if (dut.regs[1] !== 32'h0000_0001) $fatal(1, "x1 %08x", dut.regs[1]);
    if (dut.regs[2] !== 32'h0000_0010) $fatal(1, "x2 %08x (SLLI)", dut.regs[2]);
    if (dut.regs[3] !== 32'hFFFF_FFF0) $fatal(1, "x3 %08x", dut.regs[3]);
    if (dut.regs[4] !== 32'hFFFF_FFFC) $fatal(1, "x4 %08x (SRAI)", dut.regs[4]);
    if (dut.regs[5] !== 32'h0000_000F) $fatal(1, "x5 %08x (SRLI)", dut.regs[5]);
    if (dut.regs[6] !== 32'h0000_0002) $fatal(1, "x6 %08x", dut.regs[6]);
    if (dut.regs[7] !== 32'h0000_0040) $fatal(1, "x7 %08x (SLL)", dut.regs[7]);
    if (dut.regs[8] !== 32'hFFFF_FFFC) $fatal(1, "x8 %08x (SRA)", dut.regs[8]);
    if (dut.regs[9] !== 32'h3FFF_FFFC) $fatal(1, "x9 %08x (SRL)", dut.regs[9]);

    $display("RV32I STAGE3 PASS: shifts verified, trap@pc=0x24");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "tb_rv32i watchdog timeout");
  end
endmodule
