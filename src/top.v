`default_nettype none

module top #(
    parameter integer CLOCK_HZ   = 50_000_000,
    parameter integer REFRESH_HZ = 400,
    parameter         MEMFILE    = "program.hex",
    parameter integer MEM_WORDS  = 1024
) (
    input  wire       clk,
    input  wire       rst_n,
    output wire [7:0] led,
    output wire [7:0] seg,
    output wire [5:0] seg_digit
);
  wire        trap;
  wire [31:0] pc;

  wire        mem_valid;
  wire        mem_ready;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [31:0] mem_rdata;
  wire [ 3:0] mem_wstrb;

  rv32i_core #(
      .RESET_PC(32'h0000_0000)
  ) cpu (
      .clk      (clk),
      .resetn   (rst_n),
      .trap     (trap),
      .mem_valid(mem_valid),
      .mem_instr(),
      .mem_ready(mem_ready),
      .mem_addr (mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),
      .mem_rdata(mem_rdata),
      .retire   (),
      .pc       (pc)
  );

  // 统一程序/数据后端: 自己管 valid/ready 握手, 核只管按住 valid 等 ready.
  prog_mem #(
      .WORDS  (MEM_WORDS),
      .MEMFILE(MEMFILE)
  ) mem (
      .clk       (clk),
      .mem_valid (mem_valid),
      .mem_addr  (mem_addr),
      .mem_wdata (mem_wdata),
      .mem_wstrb (mem_wstrb),
      .mem_ready (mem_ready),
      .mem_rdata (mem_rdata)
  );

  seg_display #(
      .CLOCK_HZ  (CLOCK_HZ),
      .REFRESH_HZ(REFRESH_HZ)
  ) seg_inst (
      .clk      (clk),
      .resetn   (rst_n),
      .disp_data(pc[23:0]),
      .seg      (seg),
      .seg_digit(seg_digit)
  );

  // trap 拉高表示命中非法指令而停机; 板载 LED 低电平点亮, 故全取反.
  assign led = {8{~trap}};
endmodule

`default_nettype wire
