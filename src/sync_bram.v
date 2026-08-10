`default_nettype none

module sync_bram #(
    parameter integer WORDS   = 1024,
    parameter         MEMFILE = ""
) (
    input  wire                     clk,
    input  wire                     en,
    input  wire [              3:0] we,
    input  wire [$clog2(WORDS)-1:0] addr,
    input  wire [             31:0] wdata,
    output reg  [             31:0] rdata
);
  (* ram_style = "block" *) reg [31:0] mem[0:WORDS-1];

  initial begin
    if (MEMFILE != "") $readmemh(MEMFILE, mem);
  end

  always @(posedge clk) begin
    if (en) begin
      if (we[0]) mem[addr][ 7: 0] <= wdata[ 7: 0];
      if (we[1]) mem[addr][15: 8] <= wdata[15: 8];
      if (we[2]) mem[addr][23:16] <= wdata[23:16];
      if (we[3]) mem[addr][31:24] <= wdata[31:24];

      rdata <= mem[addr];
    end
  end
endmodule

`default_nettype wire
