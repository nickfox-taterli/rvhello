`default_nettype none

// CPU 时钟原语包装: 板载 50MHz -> MMCME2_BASE 提频 -> BUFG -> clk_cpu.
// LOCKED 后两级同步释放复位 (亚稳态防护); 复位极性与 SoC 一致 (active-low).
//
// 单旋钮 CPU_HZ_MHZ: 系数表 (CLKFBOUT_MULT_F / CLKOUT0_DIVIDE_F, DIVCLK=1)
// 按 Artix-7 -2 的 VCO 600~1200MHz 选定, 都是手算过的合法组合.
// 频率不在表里 -> 落回 100MHz 默认 (综合期报一条警告).
//
// SYNTHESIS_PLL 宏隔离原语: 定义它 (Vivado) 走真 MMCM; 不定义 (iverilog) 走直通
// 旁路, 这样行为仿真不依赖 Xilinx 原语模型.
module clk_pll #(
  parameter integer CPU_HZ_MHZ = 100
) (
  input  wire clk_in,     // 板载 50MHz
  input  wire ext_rst_n,  // 板载按键复位 (active-low)
  output wire clk_cpu,    // 提频后 CPU 时钟
  output wire resetn,     // LOCKED 后同步释放的复位 (active-low)
  output wire locked
);
`ifdef SYNTHESIS_PLL
  // CPU_HZ_MHZ -> (MULT, D0). DIVCLK_DIVIDE 固定 1, VCO = 50 * MULT.
  function automatic real pll_mult(input integer mhz);
    case (mhz)
       50: pll_mult = 12.0;  // VCO  600, /12
       60: pll_mult = 24.0;  // VCO 1200, /20
       70: pll_mult = 21.0;  // VCO 1050, /15
       75: pll_mult = 21.0;  // VCO 1050, /14
       80: pll_mult = 24.0;  // VCO 1200, /15
       90: pll_mult = 18.0;  // VCO  900, /10
      100: pll_mult = 20.0;  // VCO 1000, /10
      110: pll_mult = 22.0;  // VCO 1100, /10
      120: pll_mult = 24.0;  // VCO 1200, /10
      125: pll_mult = 20.0;  // VCO 1000, /8
      130: pll_mult = 13.0;  // VCO  650, /5
      135: pll_mult = 13.5;  // VCO  675, /5
      140: pll_mult = 14.0;  // VCO  700, /5
      150: pll_mult = 21.0;  // VCO 1050, /7
      160: pll_mult = 16.0;  // VCO  800, /5
      170: pll_mult = 17.0;  // VCO  850, /5
      175: pll_mult = 21.0;  // VCO 1050, /6
      180: pll_mult = 18.0;  // VCO  900, /5
      190: pll_mult = 19.0;  // VCO  950, /5
      200: pll_mult = 20.0;  // VCO 1000, /5
      default: pll_mult = 20.0;
    endcase
  endfunction

  function automatic real pll_div(input integer mhz);
    case (mhz)
       50: pll_div = 12.0;
       60: pll_div = 20.0;
       70: pll_div = 15.0;
       75: pll_div = 14.0;
       80: pll_div = 15.0;
       90: pll_div = 10.0;
      100: pll_div = 10.0;
      110: pll_div = 10.0;
      120: pll_div = 10.0;
      125: pll_div =  8.0;
      130: pll_div =  5.0;
      135: pll_div =  5.0;
      140: pll_div =  5.0;
      150: pll_div =  7.0;
      160: pll_div =  5.0;
      170: pll_div =  5.0;
      175: pll_div =  6.0;
      180: pll_div =  5.0;
      190: pll_div =  5.0;
      200: pll_div =  5.0;
      default: pll_div = 10.0;
    endcase
  endfunction

  localparam real MUL = pll_mult(CPU_HZ_MHZ);
  localparam real D0  = pll_div(CPU_HZ_MHZ);

  initial if (D0 == 10.0 && MUL == 20.0 && !(CPU_HZ_MHZ == 100))
    $display("clk_pll: CPU_HZ_MHZ=%0d 不在表里, 落回 100MHz", CPU_HZ_MHZ);

  wire mmcm_fb;
  wire mmcm_clk0;
  wire mmcm_locked;

  MMCME2_BASE #(
    .BANDWIDTH         ("OPTIMIZED"),
    .CLKFBOUT_MULT_F   (MUL),
    .CLKFBOUT_PHASE    (0.0),
    .DIVCLK_DIVIDE     (1.0),
    .REF_JITTER1       (0.010),
    .CLKIN1_PERIOD     (20.0),       // 50MHz -> 20ns
    .STARTUP_WAIT      ("FALSE"),
    .CLKOUT0_DIVIDE_F  (D0),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE     (0.0)
  ) mmcm (
    .CLKOUT0  (mmcm_clk0), .CLKOUT0B (),
    .CLKOUT1  (),           .CLKOUT1B (),
    .CLKOUT2  (),           .CLKOUT2B (),
    .CLKOUT3  (),           .CLKOUT3B (),
    .CLKOUT4  (),           .CLKOUT5  (), .CLKOUT6 (),
    .CLKFBOUT (mmcm_fb),    .CLKFBOUTB(),
    .LOCKED   (mmcm_locked),
    .CLKIN1   (clk_in),     .PWRDWN   (1'b0),
    .CLKFBIN  (mmcm_fb),    .RST      (~ext_rst_n)
  );

  BUFG bufg_cpu (.I(mmcm_clk0), .O(clk_cpu));

  assign locked = mmcm_locked;

  // LOCKED 且 ext_rst_n 已释放后, 在 clk_cpu 域两级同步再放开 resetn.
  reg [1:0] rst_sync;
  always @(posedge clk_cpu) begin
    rst_sync[0] <= mmcm_locked & ext_rst_n;
    rst_sync[1] <= rst_sync[0];
  end
  assign resetn = rst_sync[1];
`else
  // 行为仿真直通: clk_cpu = clk_in, 复位原样放行.
  assign clk_cpu = clk_in;
  assign resetn  = ext_rst_n;
  assign locked  = 1'b1;
`endif
endmodule

`default_nettype wire
