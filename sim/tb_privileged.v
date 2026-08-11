`timescale 1ns / 1ps

// 机器态 CSR,精确异常,WFI 和 FENCE.I 的定向架构回归.
module tb_privileged;
  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg [31:0] irq_pending = 32'd0;
  reg [31:0] mem [0:127];
  integer i;

  wire trap;
  wire mem_valid;
  wire mem_instr;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [3:0] mem_wstrb;
  wire mem_ready = mem_valid;
  wire mem_error = mem_valid && (mem_addr[31:9] != 23'd0);
  wire [31:0] mem_rdata = mem_error ? 32'd0 : mem[mem_addr[8:2]];
  wire retire;
  wire [31:0] pc;

  always #5 clk = ~clk;

  rv32i_core dut (
    .clk(clk), .resetn(resetn), .dbg_halt_req(1'b0), .dbg_resume_req(1'b0),
    .dbg_halted(), .dbg_reg_valid(1'b0), .dbg_reg_write(1'b0),
    .dbg_reg_addr(16'd0), .dbg_reg_wdata(32'd0), .dbg_reg_rdata(),
    .dbg_reg_ready(), .dbg_reg_error(), .irq_pending(irq_pending), .trap(trap),
    .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
    .mem_error(mem_error), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata), .retire(retire), .pc(pc)
  );

  task clear_mem;
    begin
      for (i = 0; i < 128; i = i + 1)
        mem[i] = 32'h0000_0013;
    end
  endtask

  task start_case;
    begin
      resetn = 1'b0;
      irq_pending = 32'd0;
      repeat (2) @(posedge clk);
      @(negedge clk);
      resetn = 1'b1;
      dut.csr_mtvec = 32'h0000_0100;
    end
  endtask

  task expect_trap;
    input [31:0] cause;
    input [31:0] epc;
    input [31:0] tval;
    integer n;
    begin
      n = 0;
      while (!trap && n < 40) begin
        @(posedge clk);
        n = n + 1;
      end
      #1;
      if (!trap) $fatal(1, "trap timeout cause=%0d", cause);
      if (dut.csr_mcause !== cause || dut.csr_mepc !== epc || dut.csr_mtval !== tval)
        $fatal(1, "trap mismatch cause/mepc/mtval=%0d/%08x/%08x expected=%0d/%08x/%08x",
               dut.csr_mcause, dut.csr_mepc, dut.csr_mtval, cause, epc, tval);
      if (pc !== 32'h0000_0100)
        $fatal(1, "trap target expected 0x100 got %08x", pc);
    end
  endtask

  initial begin
    clear_mem();
    mem[0] = 32'h0000_0073; // ECALL
    start_case();
    expect_trap(32'd11, 32'd0, 32'd0);

    clear_mem();
    mem[0] = 32'hffff_ffff;
    start_case();
    expect_trap(32'd2, 32'd0, 32'hffff_ffff);

    clear_mem();
    mem[0] = 32'h0020_006f; // jal x0,2
    start_case();
    expect_trap(32'd0, 32'd0, 32'd2);

    clear_mem();
    mem[0] = 32'h0010_2083; // lw x1,1(x0)
    start_case();
    expect_trap(32'd4, 32'd0, 32'd1);

    clear_mem();
    mem[0] = 32'h0010_20a3; // sw x1,1(x0)
    start_case();
    expect_trap(32'd6, 32'd0, 32'd1);

    clear_mem();
    mem[0] = 32'h4000_00b7; // lui x1,0x40000
    mem[1] = 32'h0000_a103; // lw x2,0(x1)
    start_case();
    dut.regs[2] = 32'h55aa_33cc;
    expect_trap(32'd5, 32'd4, 32'h4000_0000);
    if (dut.regs[2] !== 32'h55aa_33cc)
      $fatal(1, "faulting load changed destination register");

    clear_mem();
    mem[0] = 32'h4000_00b7;
    mem[1] = 32'h0020_a023; // sw x2,0(x1)
    start_case();
    expect_trap(32'd7, 32'd4, 32'h4000_0000);

    clear_mem();
    mem[0] = 32'h4000_00b7;
    mem[1] = 32'h0000_8067; // jalr x0,0(x1)
    start_case();
    expect_trap(32'd1, 32'h4000_0000, 32'h4000_0000);

    // CSR 标识,计数器别名,mscratch 和明确的 WARL 掩码.
    clear_mem();
    mem[0]  = 32'hb000_20f3; // csrr x1,mcycle
    mem[1]  = 32'hb020_2173; // csrr x2,minstret
    mem[2]  = 32'hc000_21f3; // csrr x3,cycle
    mem[3]  = 32'hc020_2273; // csrr x4,instret
    mem[4]  = 32'hf110_22f3; // csrr x5,mvendorid
    mem[5]  = 32'hf120_2373; // csrr x6,marchid
    mem[6]  = 32'hf130_23f3; // csrr x7,mimpid
    mem[7]  = 32'hf140_2473; // csrr x8,mhartid
    mem[8]  = 32'h3405_14f3; // csrrw x9,mscratch,x10
    mem[9]  = 32'h3400_25f3; // csrr x11,mscratch
    mem[10] = 32'h3005_1073; // csrw mstatus,x10
    mem[11] = 32'h3000_2673; // csrr x12,mstatus
    mem[12] = 32'h3045_1073; // csrw mie,x10
    mem[13] = 32'h3040_26f3; // csrr x13,mie
    mem[14] = 32'h0000_100f; // fence.i
    mem[15] = 32'h1050_0073; // wfi
    start_case();
    dut.regs[10] = 32'hffff_ffff;
    wait (retire && pc == 32'h0000_003c);
    #1;
    if (dut.state !== 3'd0 || mem_valid || dut.ir !== 32'd0)
      $fatal(1, "FENCE.I did not clear the fetch state");
    wait (dut.state == 3'd4);
    #1;
    if (dut.regs[3] <= dut.regs[1] || dut.regs[4] <= dut.regs[2])
      $fatal(1, "cycle/instret aliases did not advance");
    if (dut.regs[5] !== 32'd0 || dut.regs[6] !== 32'd0 ||
        dut.regs[7] !== 32'd1 || dut.regs[8] !== 32'd0)
      $fatal(1, "machine ID CSR values mismatch");
    if (dut.regs[9] !== 32'd0 || dut.regs[11] !== 32'hffff_ffff)
      $fatal(1, "mscratch read/write mismatch");
    if (dut.regs[12] !== 32'h0000_1888 || dut.regs[13] !== 32'hffff_0888)
      $fatal(1, "WARL masks mismatch mstatus/mie=%08x/%08x", dut.regs[12], dut.regs[13]);
    if (dut.ir !== 32'h1050_0073 || pc !== 32'h0000_0040)
      $fatal(1, "WFI did not retire at an exact boundary");
    dut.csr_mie = 32'h0000_0080;
    irq_pending[7] = 1'b1;
    repeat (3) @(posedge clk);
    if (dut.state == 3'd4)
      $fatal(1, "WFI did not wake on a locally enabled interrupt");

    // 对只读 cycle 发起真实写必须产生非法指令异常.
    clear_mem();
    mem[0] = 32'hc000_9073; // csrw cycle,x1
    start_case();
    expect_trap(32'd2, 32'd0, 32'hc000_9073);

    $display("PRIVILEGED PASS: CSR counters, WARL, precise exceptions, WFI and FENCE.I");
    $finish;
  end

  initial begin
    #50000;
    $fatal(1, "tb_privileged watchdog timeout");
  end
endmodule
