`timescale 1ns / 1ps

module tb_top;
  localparam integer CLOCK_HZ = 40;
  localparam integer BAUD_RATE = 10;
  localparam integer CLKS_PER_BIT = CLOCK_HZ / BAUD_RATE;

  reg clk = 0;
  reg rst_n = 0;
  wire led;
  wire ttl_tx;
  integer i;
  integer byte_index;
  reg [7:0] received;

  always #5 clk = ~clk;

  top #(.CLOCK_HZ(CLOCK_HZ), .BAUD_RATE(BAUD_RATE)) dut (
      .clk(clk), .rst_n(rst_n), .led(led), .ttl_tx(ttl_tx)
  );

  function [7:0] expected_byte;
    input integer index;
    begin
      case (index)
        0: expected_byte = "H"; 1: expected_byte = "e";
        2: expected_byte = "l"; 3: expected_byte = "l";
        4: expected_byte = "o"; 5: expected_byte = " ";
        6: expected_byte = "F"; 7: expected_byte = "P";
        8: expected_byte = "G"; 9: expected_byte = "A";
        10: expected_byte = "!"; 11: expected_byte = 8'h0d;
        default: expected_byte = 8'h0a;
      endcase
    end
  endfunction

  task receive_byte;
    begin
      @(negedge ttl_tx);
      repeat (CLKS_PER_BIT + CLKS_PER_BIT/2) @(posedge clk);
      for (i = 0; i < 8; i = i + 1) begin
        received[i] = ttl_tx;
        repeat (CLKS_PER_BIT) @(posedge clk);
      end
      if (ttl_tx !== 1'b1) $fatal(1, "missing UART stop bit");
    end
  endtask

  initial begin
    $dumpfile("build/top.vcd");
    $dumpvars(0, dut);
    repeat (2) @(posedge clk);
    rst_n <= 1;
    for (byte_index = 0; byte_index < 13; byte_index = byte_index + 1) begin
      receive_byte();
      if (received !== expected_byte(byte_index))
        $fatal(1, "byte %0d: expected %02x, got %02x",
               byte_index, expected_byte(byte_index), received);
    end
    $display("TOP PASS: received Hello FPGA! CR LF");
    $finish;
  end
endmodule
