`timescale 1ns / 1ps

// rv32i_core 第 1 阶段仿真: 跑 LUI/AUIPC/ADDI 四条, 末尾 ECALL 触发 trap.
// 通过层次路径读取内部寄存器, 逐条核对结果, 并确认停机时 PC=0x10.
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

  // 每个里程碑只校验一次.
  reg c1, c2, c3, c4, c5;

  initial begin
    $dumpfile("build/rv32i.vcd");
    $dumpvars(0, dut);

    c1 = 0; c2 = 0; c3 = 0; c4 = 0; c5 = 0;

    repeat (2) @(posedge clk);
    resetn <= 1;

    forever @(posedge clk) begin
      if (!c1 && pc == 32'd4) begin
        c1 = 1;
        if (dut.regs[1] !== 32'h0000_1000)
          $fatal(1, "LUI: x1 expected 00001000 got %08x", dut.regs[1]);
      end
      if (!c2 && pc == 32'd8) begin
        c2 = 1;
        if (dut.regs[2] !== 32'h0000_0004)
          $fatal(1, "AUIPC: x2 expected 00000004 got %08x", dut.regs[2]);
      end
      if (!c3 && pc == 32'd12) begin
        c3 = 1;
        if (dut.regs[3] !== 32'h0000_1005)
          $fatal(1, "ADDI: x3 expected 00001005 got %08x", dut.regs[3]);
      end
      if (!c4 && pc == 32'd16) begin
        c4 = 1;
        if (dut.regs[4] !== 32'hFFFF_FFFF)
          $fatal(1, "ADDI: x4 expected FFFFFFFF got %08x", dut.regs[4]);
      end
      if (!c5 && trap) begin
        c5 = 1;
        if (pc !== 32'h0000_0010)
          $fatal(1, "trap pc expected 0x10 got %08x", pc);
        if (dut.regs[1] !== 32'h0000_1000 || dut.regs[2] !== 32'h0000_0004 ||
            dut.regs[3] !== 32'h0000_1005 || dut.regs[4] !== 32'hFFFF_FFFF)
          $fatal(1, "final regs wrong");
        $display("RV32I STAGE1 PASS: LUI/AUIPC/ADDI verified, trap@pc=0x10");
        $finish;
      end
    end
  end

  initial begin
    #200000;
    $fatal(1, "tb_rv32i watchdog timeout");
  end
endmodule
