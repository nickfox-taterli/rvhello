`default_nettype none

// 6 位数码管动态扫描驱动. 板上为共阳极, 段 (seg) 与位选 (seg_digit) 均低电平有效.
// disp_data[3:0] 为最低位 (digit0), disp_data[23:20] 为最高位 (digit5).
// 同一时刻只点亮一位, 按 REFRESH_HZ 全帧率轮流扫描, 用少量引脚驱动多位显示.
module seg_display #(
    parameter integer CLOCK_HZ       = 50_000_000,
    parameter integer REFRESH_HZ     = 400,
    parameter integer DIGIT0_IS_LSB  = 0  // 板上 seg_digit[0]: 1=最右(最低)位, 0=最左(最高)位
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [23:0] disp_data,
    output reg  [7:0]  seg,
    output reg  [5:0]  seg_digit
);
  localparam integer N_DIGITS = 6;

  // 每位停留的时钟数: 全帧率分到 6 位上. 至少为 1, 兼容仿真里的极速刷新.
  localparam integer SCAN_DIV_RAW = CLOCK_HZ / (REFRESH_HZ * 6);
  localparam integer SCAN_DIV     = (SCAN_DIV_RAW < 1) ? 1 : SCAN_DIV_RAW;
  localparam integer SCAN_W       = (SCAN_DIV <= 1) ? 1 : $clog2(SCAN_DIV);

  reg [SCAN_W-1:0] div_cnt;
  reg [2:0]        digit_idx;  // 0..5, 直接驱动 seg_digit[digit_idx]
  wire [2:0]       next_idx = (digit_idx == 3'd5) ? 3'd0 : digit_idx + 3'd1;
  wire             tick     = (div_cnt == (SCAN_DIV - 1));

  // seg_digit[digit_idx] 对应的物理位序与数据高低的关系由 DIGIT0_IS_LSB 决定.
  // 本板 seg_digit[0] 为最左(最高)位, 故扫描索引需反转才能对上 disp_data 的半字节顺序.
  localparam [2:0] MSB_IDX = N_DIGITS - 1;
  wire [2:0]       nib_idx = (DIGIT0_IS_LSB != 0) ? next_idx : (MSB_IDX - next_idx);

  // 段码: {DP,PG,PF,PE,PD,PC,PB,PA}, 共阳极低电平点亮.
  function [7:0] hex7seg;
    input [3:0] n;
    begin
      case (n)
        4'h0: hex7seg = 8'hC0;
        4'h1: hex7seg = 8'hF9;
        4'h2: hex7seg = 8'hA4;
        4'h3: hex7seg = 8'hB0;
        4'h4: hex7seg = 8'h99;
        4'h5: hex7seg = 8'h92;
        4'h6: hex7seg = 8'h82;
        4'h7: hex7seg = 8'hF8;
        4'h8: hex7seg = 8'h80;
        4'h9: hex7seg = 8'h90;
        4'hA: hex7seg = 8'h88;
        4'hB: hex7seg = 8'h83;
        4'hC: hex7seg = 8'hC6;
        4'hD: hex7seg = 8'hA1;
        4'hE: hex7seg = 8'h86;
        4'hF: hex7seg = 8'h8E;
        default: hex7seg = 8'hFF;
      endcase
    end
  endfunction

  always @(posedge clk) begin
    if (!resetn) begin
      div_cnt   <= {SCAN_W{1'b0}};
      digit_idx <= 3'd0;
      seg       <= 8'hFF;  // 段全灭
      seg_digit <= 6'h3F;  // 位选全关
    end else if (tick) begin
      div_cnt   <= {SCAN_W{1'b0}};
      digit_idx <= next_idx;
      // 段和位选与 digit_idx 在同一拍更新, 避免切换瞬间的鬼影.
      // 段码用经位序反转后的 nib_idx 选半字节, 使最左位显示最高半字节.
      seg       <= hex7seg(disp_data >> {nib_idx, 2'b00});
      seg_digit <= ~(6'd1 << next_idx);
    end else begin
      div_cnt <= div_cnt + 1'b1;
    end
  end
endmodule

`default_nettype wire
