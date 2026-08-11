`timescale 1ns / 1ps

// ACT4 自检 ELF 的通用运行器.结果通过固定 MMIO 地址返回.
module tb_arch;
  localparam integer WORDS = 65536;
  localparam [31:0] RESULT_ADDR = 32'h1000_00fc;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg [31:0] memory [0:WORDS-1];
  reg [8*1024-1:0] hexfile;
  integer max_cycles = 2000000;
  integer cycles;
  integer i;

  wire mem_valid;
  wire mem_instr;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [3:0] mem_wstrb;
  wire in_ram = mem_addr[31:18] == 14'd0;
  wire is_result = mem_addr == RESULT_ADDR;
  wire mem_ready = mem_valid;
  wire mem_error = mem_valid && !(in_ram || (!mem_instr && is_result));
  wire [31:0] mem_rdata = in_ram ? memory[mem_addr[17:2]] : 32'd0;

  always #5 clk = ~clk;

  rv32i_core dut (
    .clk(clk), .resetn(resetn), .dbg_halt_req(1'b0), .dbg_resume_req(1'b0),
    .dbg_halted(), .dbg_reg_valid(1'b0), .dbg_reg_write(1'b0),
    .dbg_reg_addr(16'd0), .dbg_reg_wdata(32'd0), .dbg_reg_rdata(),
    .dbg_reg_ready(), .dbg_reg_error(), .irq_pending(32'd0), .trap(),
    .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
    .mem_error(mem_error), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata), .retire(), .pc()
  );

  always @(posedge clk) begin
    if (resetn && mem_valid && mem_ready && in_ram && !mem_instr) begin
      if (mem_wstrb[0]) memory[mem_addr[17:2]][7:0]   <= mem_wdata[7:0];
      if (mem_wstrb[1]) memory[mem_addr[17:2]][15:8]  <= mem_wdata[15:8];
      if (mem_wstrb[2]) memory[mem_addr[17:2]][23:16] <= mem_wdata[23:16];
      if (mem_wstrb[3]) memory[mem_addr[17:2]][31:24] <= mem_wdata[31:24];
    end
    if (resetn && mem_valid && mem_ready && is_result && (|mem_wstrb)) begin
      if (mem_wdata == 32'd1) begin
        $display("ARCH PASS");
        $finish;
      end else begin
        $fatal(1, "ARCH FAIL code=%08x pc=%08x", mem_wdata, dut.pc);
      end
    end
  end

  initial begin
    for (i = 0; i < WORDS; i = i + 1)
      memory[i] = 32'h0000_0013;
    if (!$value$plusargs("HEX=%s", hexfile))
      $fatal(1, "missing +HEX=<file>");
    if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
      max_cycles = 2000000;
    $readmemh(hexfile, memory);
    repeat (2) @(posedge clk);
    resetn <= 1'b1;
    for (cycles = 0; cycles < max_cycles; cycles = cycles + 1)
      @(posedge clk);
    $fatal(1, "ARCH TIMEOUT pc=%08x", dut.pc);
  end
endmodule

