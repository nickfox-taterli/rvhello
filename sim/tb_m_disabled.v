`timescale 1ns / 1ps

// 关闭内部 PCPI 后, M 指令必须和其他未实现编码一样触发非法指令 trap.
module tb_m_disabled;
  reg clk = 1'b0;
  reg resetn = 1'b0;
  wire trap;
  wire mem_valid;
  wire mem_ready;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [3:0] mem_wstrb;
  wire [31:0] mem_rdata;

  always #5 clk = ~clk;

  rv32i_core #(
      .ENABLE_M_PCPI(1'b0)
  ) dut (
      .clk      (clk),
      .resetn   (resetn),
      .irq_pending(32'd0),
      .trap     (trap),
      .mem_valid(mem_valid),
      .mem_instr(),
      .mem_ready(mem_ready),
      .mem_addr (mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),
      .mem_rdata(mem_rdata),
      .retire   (),
      .pc       ()
  );

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
    repeat (2) @(posedge clk);
    resetn <= 1'b1;
    wait (trap);
    #1;
    if (dut.pc !== 32'h0000_0030)
      $fatal(1, "M disabled trap pc expected 0x30 got %08x", dut.pc);
    $display("M PCPI DISABLED PASS: M instruction traps at pc=0x30");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "tb_m_disabled watchdog timeout");
  end
endmodule
