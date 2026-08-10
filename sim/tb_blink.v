`timescale 1ns / 1ps

module tb_blink;
  reg     clk = 0;
  reg     resetn = 0;
  wire    led;

  integer clock_edges = 0;
  integer toggles = 0;
  reg     previous_led = 0;

  always #5 clk = ~clk;

  blink #(
      .CLOCK_HZ(4)
  ) dut (
      .clk   (clk),
      .resetn(resetn),
      .led   (led)
  );

  always @(posedge clk) begin
    if (resetn) begin
      clock_edges <= clock_edges + 1;
      if (led != previous_led) begin
        if (clock_edges % 4 != 0) $fatal(1, "LED toggled on unexpected edge %0d", clock_edges);
        toggles      <= toggles + 1;
        previous_led <= led;
      end
    end
  end

  initial begin
    $dumpfile("build/blink.vcd");
    $dumpvars(0, dut);

    repeat (2) @(posedge clk);
    resetn <= 1;
    repeat (14) @(posedge clk);
    #1;

    if (toggles != 3) $fatal(1, "expected 3 toggles, got %0d", toggles);
    $display("LESSON 01 COUNTER PASS toggles=%0d", toggles);
    $finish;
  end
endmodule
