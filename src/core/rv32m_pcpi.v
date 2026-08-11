`default_nettype none

// 实现过程我突然想,用DSP不是挺好!
module rv32m_pcpi #(
    parameter USE_DSP_MUL = 1'b1
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire        pcpi_valid,
    input  wire [31:0] pcpi_insn,
    input  wire [31:0] pcpi_rs1,
    input  wire [31:0] pcpi_rs2,
    output wire        pcpi_wait,
    output reg         pcpi_ready,
    output reg         pcpi_wr,
    output reg  [31:0] pcpi_rd
);
  wire match = (pcpi_insn[6:0] == 7'b0110011) &&
               (pcpi_insn[31:25] == 7'b0000001);

  reg        busy;
  reg [2:0]  operation;
  reg [5:0]  count;

  // 快速乘法入口拍把完整积打入寄存器, 下一拍返回. use_dsp 属性让 Vivado
  // 为这个有符号乘法优先推断 DSP48, 不让乘法组合路径穿过主核.
  reg [63:0] mul_product;

  // 面积优先回退路径: 绝对值做无符号 shift-add, 最后恢复完整积符号.
  reg [63:0] mul_accumulator;
  reg [63:0] mul_multiplicand;
  reg [31:0] mul_multiplier;
  reg        mul_negative;

  // 除法状态: 恢复除法每轮移入 dividend 的下一位, 再试减 divisor.
  reg [31:0] div_quotient;
  reg [32:0] div_remainder;
  reg [31:0] div_divisor;
  reg        div_quotient_negative;
  reg        div_remainder_negative;
  reg        div_special;
  reg [31:0] div_special_quotient;
  reg [31:0] div_special_remainder;

  wire operation_is_divide = operation[2];
  wire [63:0] mul_sum = mul_accumulator +
      (mul_multiplier[0] ? mul_multiplicand : 64'd0);
  wire [63:0] mul_signed_result = mul_negative ? (~mul_sum + 1'b1) : mul_sum;

  wire [32:0] div_shifted_remainder = {div_remainder[31:0], div_quotient[31]};
  wire div_subtract = div_shifted_remainder >= {1'b0, div_divisor};
  wire [32:0] div_next_remainder = div_subtract ?
      div_shifted_remainder - {1'b0, div_divisor} : div_shifted_remainder;
  wire [31:0] div_next_quotient = {div_quotient[30:0], div_subtract};
  wire [31:0] div_signed_quotient = div_quotient_negative ?
      (~div_next_quotient + 1'b1) : div_next_quotient;
  wire [31:0] div_signed_remainder = div_remainder_negative ?
      (~div_next_remainder[31:0] + 1'b1) : div_next_remainder[31:0];

  assign pcpi_wait = pcpi_valid && match && !pcpi_ready;

  // 0x80000000 的 32 位补码 absolute 仍是 0x80000000. 它恰好是 2^31,
  // 因此对这一轮无符号移位数据通路不需要再扩展第 33 位.
  function automatic [31:0] magnitude;
    input [31:0] value;
    input        signed_enable;
    magnitude = (signed_enable && value[31]) ? (~value + 1'b1) : value;
  endfunction

  wire div_is_signed = !pcpi_insn[12];
  wire mul_a_is_signed = pcpi_insn[14:12] != 3'b011;
  wire mul_b_is_signed = (pcpi_insn[14:12] == 3'b000) ||
                         (pcpi_insn[14:12] == 3'b001);
  wire [31:0] div_abs_a = magnitude(pcpi_rs1, div_is_signed);
  wire [31:0] div_abs_b = magnitude(pcpi_rs2, div_is_signed);
  wire [31:0] mul_abs_a = magnitude(pcpi_rs1, mul_a_is_signed);
  wire [31:0] mul_abs_b = magnitude(pcpi_rs2, mul_b_is_signed);
  wire [63:0] dsp_mul_result;

  generate
    if (USE_DSP_MUL) begin : gen_dsp_mul
      wire signed [32:0] dsp_mul_a = mul_a_is_signed ?
          $signed({pcpi_rs1[31], pcpi_rs1}) : $signed({1'b0, pcpi_rs1});
      wire signed [32:0] dsp_mul_b = mul_b_is_signed ?
          $signed({pcpi_rs2[31], pcpi_rs2}) : $signed({1'b0, pcpi_rs2});
      (* use_dsp = "yes" *) wire signed [65:0] dsp_mul_product;
      assign dsp_mul_product = $signed(dsp_mul_a) * $signed(dsp_mul_b);
      assign dsp_mul_result = dsp_mul_product[63:0];
    end else begin : gen_no_dsp_mul
      assign dsp_mul_result = 64'd0;
    end
  endgenerate

  always @(posedge clk) begin
    pcpi_ready <= 1'b0;
    pcpi_wr    <= 1'b0;

    if (!resetn) begin
      busy                 <= 1'b0;
      operation            <= 3'd0;
      count                <= 6'd0;
      pcpi_rd              <= 32'd0;
      mul_product          <= 64'd0;
      mul_accumulator      <= 64'd0;
      mul_multiplicand     <= 64'd0;
      mul_multiplier       <= 32'd0;
      mul_negative         <= 1'b0;
      div_quotient         <= 32'd0;
      div_remainder        <= 33'd0;
      div_divisor          <= 32'd0;
      div_quotient_negative <= 1'b0;
      div_remainder_negative <= 1'b0;
      div_special          <= 1'b0;
      div_special_quotient <= 32'd0;
      div_special_remainder <= 32'd0;
    end else if (!busy && pcpi_valid && match && !pcpi_ready) begin
      operation <= pcpi_insn[14:12];
      count     <= 6'd0;
      busy      <= 1'b1;

      if (pcpi_insn[14]) begin
        div_quotient <= div_abs_a;
        div_remainder <= 33'd0;
        div_divisor <= div_abs_b;
        div_quotient_negative <= div_is_signed && (pcpi_rs1[31] ^ pcpi_rs2[31]);
        div_remainder_negative <= div_is_signed && pcpi_rs1[31];

        // 除零: quotient=全 1, remainder=dividend.
        // 有符号唯一溢出: INT_MIN / -1 => INT_MIN, remainder=0.
        div_special <= (pcpi_rs2 == 32'd0) ||
                       (div_is_signed && (pcpi_rs1 == 32'h8000_0000) &&
                        (pcpi_rs2 == 32'hffff_ffff));
        if (pcpi_rs2 == 32'd0) begin
          div_special_quotient <= 32'hffff_ffff;
          div_special_remainder <= pcpi_rs1;
        end else begin
          div_special_quotient <= 32'h8000_0000;
          div_special_remainder <= 32'd0;
        end
      end else begin
        if (USE_DSP_MUL) begin
          mul_product <= dsp_mul_result;
        end else begin
          // MUL 低半积对 signedness 不敏感. 三种 high 形式仍要保留各自符号规则.
          mul_accumulator <= 64'd0;
          mul_multiplicand <= {32'd0, mul_abs_a};
          mul_multiplier <= mul_abs_b;
          mul_negative <= (mul_a_is_signed && pcpi_rs1[31]) ^
                          (mul_b_is_signed && pcpi_rs2[31]);
        end
      end
    end else if (busy) begin
      if (!operation_is_divide) begin
        if (USE_DSP_MUL) begin
          pcpi_rd <= (operation == 3'b000) ? mul_product[31:0] : mul_product[63:32];
          pcpi_ready <= 1'b1;
          pcpi_wr <= 1'b1;
          busy <= 1'b0;
        end else begin
          mul_accumulator <= mul_sum;
          mul_multiplicand <= mul_multiplicand << 1;
          mul_multiplier <= mul_multiplier >> 1;
          if (count == 6'd31) begin
            pcpi_rd <= (operation == 3'b000) ? mul_signed_result[31:0] :
                                                 mul_signed_result[63:32];
            pcpi_ready <= 1'b1;
            pcpi_wr <= 1'b1;
            busy <= 1'b0;
          end else begin
            count <= count + 1'b1;
          end
        end
      end else if (div_special) begin
        // 特殊情况直接完成, 但仍使用同一组 ready/wr 握手.
        pcpi_rd <= operation[1] ? div_special_remainder : div_special_quotient;
        pcpi_ready <= 1'b1;
        pcpi_wr <= 1'b1;
        busy <= 1'b0;
      end else begin
        div_remainder <= div_next_remainder;
        div_quotient <= div_next_quotient;
        if (count == 6'd31) begin
          pcpi_rd <= operation[1] ? div_signed_remainder : div_signed_quotient;
          pcpi_ready <= 1'b1;
          pcpi_wr <= 1'b1;
          busy <= 1'b0;
        end else begin
          count <= count + 1'b1;
        end
      end
    end
  end
endmodule

`default_nettype wire
