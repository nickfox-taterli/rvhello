`default_nettype none

// 最小 RISC-V 取指执行核: 只支持 ADDI (opcode 0010011, funct3 000).
module addi_cpu (
    input  wire        clk,
    input  wire        resetn,
    output reg         trap,
    output reg  [31:0] pc
);
  // FETCH 发起 ROM 读取, WAIT 把 rom_q 送入 ir; 只有 EXEC 能修改架构寄存器或 PC.
  localparam FETCH = 2'd0, WAIT = 2'd1, EXEC = 2'd2;
  reg [1:0] state;
  reg [31:0] ir;
  reg [31:0] regs[0:31];
  // 下方寄存读让私有程序 ROM 具有与 BRAM 相似的时序.
  (* ram_style = "block" *) reg [31:0] rom[0:15];
  reg [31:0] rom_q;
  integer i;
  initial begin
    // 依次执行三条 ADDI, 最后遇到本课尚不支持的 JAL.
    rom[0] = 32'h00500093;  // ADDI x1, x0, 5   -> x1 = 5
    rom[1] = 32'hffe08113;  // ADDI x1, x1, -2  -> x2 = 3
    rom[2] = 32'h00910193;  // ADDI x3, x2, 9   -> x3 = 12
    rom[3] = 32'h0000006f;  // JAL  x0, 0       -> trap
  end
  // 字段提取和符号扩展都是组合连线网络.
  wire [ 4:0] rs1 = ir[19:15], rd = ir[11:7];
  // 每次读取都强制 x0=0, 不依赖数组单元中的实际内容.
  wire [31:0] rs1v = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
  wire [31:0] imm_i = {{20{ir[31]}}, ir[31:20]};
  always @(posedge clk) begin
    if (!resetn) begin
      state <= FETCH;
      pc    <= 32'd0;
      ir    <= 32'd0;
      trap  <= 1'b0;
      for (i = 0; i < 32; i = i + 1) regs[i] <= 32'd0;
    end else
      case (state)
        FETCH: begin
          // pc 是字节地址; [5:2] 去掉两个字对齐低位.
          rom_q <= rom[pc[5:2]];
          state <= WAIT;
        end
        WAIT: begin
          // 即使 ROM 端口随后变化, ir 在整个 EXEC 阶段仍保持稳定.
          ir    <= rom_q;
          state <= EXEC;
        end
        EXEC:
          // opcode=0010011 且 funct3=000 才能准确识别 ADDI.
          if (ir[6:0] == 7'b0010011 && ir[14:12] == 3'b000) begin
            // rd!=0 的保护构成架构 x0 规则的写入侧.
            if (rd != 5'd0) regs[rd] <= rs1v + imm_i;
            pc    <= pc + 32'd4;
            state <= FETCH;
          end else begin
            // trap 拉高后停在 EXEC, 形成最简单的终止错误状态.
            trap <= 1'b1;
          end
      endcase
  end
endmodule

`default_nettype wire
