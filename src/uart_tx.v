`default_nettype none

module uart_tx #(
    parameter integer CLKS_PER_BIT = 8
) (
    input  wire       clk,
    input  wire       resetn,
    input  wire       start,
    input  wire [7:0] data,
    output wire       tx,
    output wire       busy
);
  localparam integer COUNT_WIDTH = $clog2(CLKS_PER_BIT);
  localparam integer LAST_COUNT = CLKS_PER_BIT - 1;

  reg [COUNT_WIDTH-1:0] baud_count;
  reg [            3:0] bits_left;
  reg [            9:0] shift_reg;

  assign busy = (bits_left != 0);
  assign tx   = busy ? shift_reg[0] : 1'b1;

  always @(posedge clk) begin
    if (!resetn) begin
      baud_count <= 0;
      bits_left  <= 0;
      shift_reg  <= 10'h3ff;
    end else if (!busy && start) begin
      shift_reg  <= {1'b1, data, 1'b0};
      bits_left  <= 10;
      baud_count <= 0;
    end else if (busy) begin
      if (baud_count == LAST_COUNT) begin
        baud_count <= 0;
        shift_reg  <= {1'b1, shift_reg[9:1]};
        bits_left  <= bits_left - 1'b1;
      end else begin
        baud_count <= baud_count + 1'b1;
      end
    end
  end
endmodule

`default_nettype wire
