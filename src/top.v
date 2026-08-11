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
  localparam integer MEM_AW = $clog2(MEM_WORDS);

  wire        trap;
  wire [31:0] pc;

  wire        mem_valid;
  wire        mem_ready;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [31:0] mem_rdata;
  wire [ 3:0] mem_wstrb;

  // sync_bram 的寄存读有 1 拍延迟; 把 mem_ready 也寄存一拍, 与读数据同时生效.
  reg mem_ready_r;
  always @(posedge clk) begin
    if (!rst_n) mem_ready_r <= 1'b0;
    else        mem_ready_r <= mem_valid;
  end

  rv32i_core #(
      .RESET_PC(32'h0000_0000)
  ) cpu (
      .clk      (clk),
      .resetn   (rst_n),
      .trap     (trap),
      .mem_valid(mem_valid),
      .mem_instr(),
      .mem_ready(mem_ready_r),
      .mem_addr (mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),
      .mem_rdata(mem_rdata),
      .retire   (),
      .pc       (pc)
  );

  sync_bram #(
      .WORDS  (MEM_WORDS),
      .MEMFILE(MEMFILE)
  ) mem (
      .clk  (clk),
      .en   (mem_valid),
      .we   (mem_wstrb),
      .addr (mem_addr[MEM_AW+1:2]),
      .wdata(mem_wdata),
      .rdata(mem_rdata)
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
