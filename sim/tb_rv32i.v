`timescale 1ns / 1ps

// rv32i_core 第 5 阶段仿真: JAL/JALR. 调用-返回流程后命中 ECALL.
// 核对链接寄存器(x1/x7)、跳转目标正确性、最终累加值 x3, 以及停机 PC.
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

    if (pc !== 32'h0000_001C)
      $fatal(1, "trap pc expected 0x1C got %08x", pc);
    if (dut.regs[1] !== 32'h0000_0018) $fatal(1, "x1 (JAL link)   %08x", dut.regs[1]);
    if (dut.regs[3] !== 32'h0000_0073) $fatal(1, "x3 (5+100+10)   %08x", dut.regs[3]);
    if (dut.regs[6] !== 32'h0000_0004) $fatal(1, "x6 (AUIPC)      %08x", dut.regs[6]);
    if (dut.regs[7] !== 32'h0000_000C) $fatal(1, "x7 (JALR link)  %08x", dut.regs[7]);

    $display("RV32I STAGE5 PASS: JAL/JALR verified, trap@pc=0x1C");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "tb_rv32i watchdog timeout (possible jump loop)");
  end
endmodule
