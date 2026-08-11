`timescale 1ns / 1ps

// halt 在数据事务中到达时,总线先完成并退休当前指令,然后才冻结 PC.
module tb_debug_halt;
  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg halt_req = 1'b0;
  reg resume_req = 1'b0;
  reg allow_ready = 1'b1;
  wire halted;
  wire mem_valid;
  wire mem_instr;
  wire mem_ready = mem_valid && allow_ready;
  wire [31:0] mem_addr;
  wire [31:0] mem_rdata =
      mem_addr == 32'h00 ? 32'h0100_0093 : // addi x1,x0,16
      mem_addr == 32'h04 ? 32'h0000_a103 : // lw x2,0(x1)
      mem_addr == 32'h08 ? 32'h0010_0193 : // addi x3,x0,1
      mem_addr == 32'h10 ? 32'hdead_beef : 32'h0000_0013;
  wire retire;
  wire [31:0] pc;

  always #5 clk = ~clk;

  rv32i_core dut (
    .clk(clk), .resetn(resetn), .dbg_halt_req(halt_req),
    .dbg_resume_req(resume_req), .dbg_halted(halted), .irq_pending(32'd0),
    .trap(), .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
    .mem_addr(mem_addr), .mem_wdata(), .mem_wstrb(), .mem_rdata(mem_rdata),
    .retire(retire), .pc(pc)
  );

  initial begin
    $dumpfile("build/debug_halt.vcd");
    $dumpvars(0, dut);
    repeat (2) @(posedge clk);
    resetn <= 1'b1;

    wait (dut.state == 3'd2 && mem_valid && !mem_instr);
    @(negedge clk);
    allow_ready <= 1'b0;
    halt_req <= 1'b1;
    @(negedge clk);
    halt_req <= 1'b0;

    repeat (3) begin
      @(posedge clk);
      #1;
      if (!mem_valid || pc !== 32'h0000_0004 || halted)
        $fatal(1, "halt 提前撤销事务或改变 PC: valid=%b pc=%08x halted=%b", mem_valid, pc, halted);
    end

    @(negedge clk);
    allow_ready <= 1'b1;
    wait (halted);
    #1;
    if (pc !== 32'h0000_0008 || dut.regs[2] !== 32'hdead_beef || mem_valid)
      $fatal(1, "事务完成后的 halt 边界错误: pc=%08x x2=%08x valid=%b", pc, dut.regs[2], mem_valid);

    repeat (3) begin
      @(posedge clk);
      #1;
      if (pc !== 32'h0000_0008 || mem_valid)
        $fatal(1, "halt 状态没有冻结 PC/总线");
    end

    @(negedge clk);
    resume_req <= 1'b1;
    @(negedge clk);
    resume_req <= 1'b0;
    wait (retire && pc == 32'h0000_000c);
    #1;
    if (dut.regs[3] !== 32'd1)
      $fatal(1, "resume 后没有继续执行");

    $display("DEBUG HALT PASS: 当前事务完成后冻结并可恢复");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "tb_debug_halt watchdog timeout");
  end
endmodule
