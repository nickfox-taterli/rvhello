`default_nettype none

module top #(
    parameter integer CLOCK_HZ = 50_000_000,
    parameter integer BAUD_RATE = 115_200
) (
    input  wire clk,
    input  wire rst_n,
    output wire led,
    output wire ttl_tx
);
  localparam integer CLKS_PER_BIT = CLOCK_HZ / BAUD_RATE;
  localparam integer MESSAGE_LEN = 13;

  wire blink_level;
  reg        tx_start;
  reg  [7:0] tx_data;
  wire       tx_busy;
  reg  [3:0] message_index;

  function [7:0] message_byte;
    input [3:0] index;
    begin
      case (index)
        4'd0:  message_byte = "H";
        4'd1:  message_byte = "e";
        4'd2:  message_byte = "l";
        4'd3:  message_byte = "l";
        4'd4:  message_byte = "o";
        4'd5:  message_byte = " ";
        4'd6:  message_byte = "F";
        4'd7:  message_byte = "P";
        4'd8:  message_byte = "G";
        4'd9:  message_byte = "A";
        4'd10: message_byte = "!";
        4'd11: message_byte = 8'h0d;
        default: message_byte = 8'h0a;
      endcase
    end
  endfunction

  blink #(
      .CLOCK_HZ(CLOCK_HZ)
  ) blink_inst (
      .clk(clk),
      .resetn(rst_n),
      .led(blink_level)
  );

  // 板载 LED 低电平点亮.
  assign led = ~blink_level;

  uart_tx #(
      .CLKS_PER_BIT(CLKS_PER_BIT)
  ) uart_tx_inst (
      .clk(clk),
      .resetn(rst_n),
      .start(tx_start),
      .data(tx_data),
      .tx(ttl_tx),
      .busy(tx_busy)
  );

  // UART 空闲后立即提交下一个字节,循环背靠背发送固定测试行.
  always @(posedge clk) begin
    if (!rst_n) begin
      tx_start     <= 1'b0;
      tx_data      <= message_byte(0);
      message_index <= 0;
    end else begin
      tx_start <= 1'b0;
      if (!tx_busy && !tx_start) begin
        tx_data  <= message_byte(message_index);
        tx_start <= 1'b1;
        if (message_index == MESSAGE_LEN - 1)
          message_index <= 0;
        else
          message_index <= message_index + 1'b1;
      end
    end
  end
endmodule

`default_nettype wire
