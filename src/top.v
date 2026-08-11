`default_nettype none

module top #(
    parameter integer CLOCK_HZ   = 50_000_000,
    parameter integer REFRESH_HZ = 400
) (
    input  wire       clk,
    input  wire       rst_n,
    output wire [7:0] led,
    output wire [7:0] seg,
    output wire [5:0] seg_digit
);
  wire        trap;
  wire [31:0] pc;

  addi_cpu cpu (
      .clk   (clk),
      .resetn(rst_n),
      .trap  (trap),
      .pc    (pc)
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

  // trap 拉高表示 CPU 命中不支持的指令而停机; 板载 LED 低电平点亮, 故全取反.
  assign led = {8{~trap}};
endmodule

`default_nettype wire
