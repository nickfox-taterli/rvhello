`timescale 1ns / 1ps

// rv32i_core 第 4 阶段仿真: 条件分支. 6 条分支各走预期路径后命中 ECALL.
// 全对时 x3 = 0x3F (bit0..5 各代表一条分支正确), PC 停在 0x48.
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

    if (pc !== 32'h0000_0048)
      $fatal(1, "trap pc expected 0x48 got %08x", pc);
    if (dut.regs[1] !== 32'h0000_0005) $fatal(1, "x1 %08x", dut.regs[1]);
    if (dut.regs[2] !== 32'hFFFF_FFFF) $fatal(1, "x2 %08x", dut.regs[2]);
    // x3 = 0x3F 表示 6 条分支 (BEQ/BNE/BLT/BLTU/BGE/BGEU) 全部按预期跳/不跳.
    if (dut.regs[3] !== 32'h0000_003F)
      $fatal(1, "x3 %08x (expected 0x3F, some branch went wrong)", dut.regs[3]);

    $display("RV32I STAGE4 PASS: branches verified (x3=0x3F), trap@pc=0x48");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "tb_rv32i watchdog timeout");
  end
endmodule
