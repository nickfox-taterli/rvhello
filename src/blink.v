`default_nettype none

module blink #(
    parameter integer CLOCK_HZ = 100_000_000
) (
    input  wire clk,
    input  wire resetn,
    output reg  led
);
  localparam integer COUNT_WIDTH = $clog2(CLOCK_HZ);
  localparam integer LAST_COUNT = CLOCK_HZ - 1;

  reg [COUNT_WIDTH-1:0] count;

  always @(posedge clk) begin
    if (!resetn) begin
      count <= 0;
      led   <= 0;
    end else if (count == LAST_COUNT) begin
      count <= 0;
      led   <= ~led;
    end else begin
      count <= count + 1'b1;
    end
  end
endmodule

`default_nettype wire
