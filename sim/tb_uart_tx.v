`timescale 1ns / 1ps

module tb_uart_tx;
  reg           clk = 0;
  reg           resetn = 0;
  reg           start = 0;
  reg     [7:0] data = 8'ha5;
  wire          tx;
  wire          busy;

  integer       i;
  reg     [9:0] expected = 10'b1_10100101_0;

  always #5 clk = ~clk;

  uart_tx #(
      .CLKS_PER_BIT(4)
  ) dut (
      .clk   (clk),
      .resetn(resetn),
      .start (start),
      .data  (data),
      .tx    (tx),
      .busy  (busy)
  );

  initial begin
    $dumpfile("build/uart.vcd");
    $dumpvars(0, dut);

    repeat (2) @(posedge clk);
    resetn <= 1;

    @(negedge clk);
    start <= 1;
    @(negedge clk);
    start <= 0;

    wait (busy);
    for (i = 0; i < 10; i = i + 1) begin
      if (tx !== expected[i]) $fatal(1, "UART bit %0d is wrong", i);
      repeat (4) @(posedge clk);
      #1;
    end

    wait (!busy);
    if (tx !== 1'b1) $fatal(1, "UART line did not return to idle high");
    $display("LESSON 01 UART PASS byte=a5");
    $finish;
  end
endmodule
