`default_nettype none

// 第1阶段实现 => LUI / AUIPC / ADDI
module rv32i_core #(
    parameter [31:0] RESET_PC = 32'h0000_0000
) (
    input  wire        clk,
    input  wire        resetn,
    output reg         trap,

    output reg         mem_valid,
    output reg         mem_instr,
    input  wire        mem_ready,
    output reg  [31:0] mem_addr,
    output reg  [31:0] mem_wdata,
    output reg  [ 3:0] mem_wstrb,
    input  wire [31:0] mem_rdata,

    // retire 每完成一条指令脉冲一拍; pc 暴露架构 PC, 供顶层显示与波形观测.
    output reg         retire,
    output reg  [31:0] pc
);
  localparam [1:0] S_FETCH = 2'd0;
  localparam [1:0] S_EXEC  = 2'd1;
  localparam [1:0] S_TRAP  = 2'd3;

  reg  [1:0]  state;
  reg  [31:0] ir;

  // 教学版采用异步读口, 同步写口. 易读, 综合为 LUT/FF; 后续再比较寄存器堆实现.
  reg  [31:0] regs [0:31];
  integer     register_index;

  // 指令字段只是 ir 的切片, 不占额外寄存器.
  wire [6:0] opcode = ir[6:0];
  wire [2:0] funct3 = ir[14:12];
  wire [4:0] rd     = ir[11:7];
  wire [4:0] rs1    = ir[19:15];

  // x0 必须始终读出零, 不依赖数组单元内容.
  wire [31:0] rs1_value = (rs1 == 5'd0) ? 32'd0 : regs[rs1];

  // 第 1 阶段用到的立即数: I 型与 U 型.
  wire [31:0] imm_i = {{20{ir[31]}}, ir[31:20]};
  wire [31:0] imm_u = {ir[31:12], 12'b0};

  // 组合译码只计算候选动作; 真正改 PC/寄存器/总线的操作集中在时序块.
  reg        decoded_legal;
  reg        decoded_write_rd;
  reg [31:0] decoded_result;

  always @* begin
    // 每条路径先给安全默认值, 避免组合 always 推断锁存器.
    decoded_legal    = 1'b1;
    decoded_write_rd = 1'b0;
    decoded_result   = 32'd0;

    case (opcode)
      7'b0110111: begin  // LUI
        decoded_result   = imm_u;
        decoded_write_rd = 1'b1;
      end

      7'b0010111: begin  // AUIPC
        decoded_result   = pc + imm_u;
        decoded_write_rd = 1'b1;
      end

      7'b0010011: begin  // OP-IMM
        if (funct3 == 3'b000) begin  // ADDI
          decoded_result   = rs1_value + imm_i;
          decoded_write_rd = 1'b1;
        end else begin
          decoded_legal = 1'b0;  // 其余 OP-IMM (SLTI/XORI/...) 留到后续阶段
        end
      end

      default: decoded_legal = 1'b0;  // 其余 opcode 尚未实现
    endcase
  end

  // 所有架构状态都只在时钟上升沿提交.
  always @(posedge clk) begin
    retire <= 1'b0;

    if (!resetn) begin
      state     <= S_FETCH;
      pc        <= RESET_PC;
      ir        <= 32'd0;
      trap      <= 1'b0;
      mem_valid <= 1'b0;
      mem_instr <= 1'b0;
      mem_addr  <= 32'd0;
      mem_wdata <= 32'd0;
      mem_wstrb <= 4'b0000;
      for (register_index = 0; register_index < 32; register_index = register_index + 1)
        regs[register_index] <= 32'd0;
    end else begin
      case (state)
        S_FETCH: begin
          // 第一次进入时发请求; 等待期间不改地址, 直到 ready 完成传输.
          if (!mem_valid) begin
            mem_valid <= 1'b1;
            mem_instr <= 1'b1;
            mem_addr  <= pc;
            mem_wstrb <= 4'b0000;
          end
          if (mem_valid && mem_ready) begin
            mem_valid <= 1'b0;
            ir        <= mem_rdata;
            state     <= S_EXEC;
          end
        end

        S_EXEC: begin
          if (!decoded_legal) begin
            trap  <= 1'b1;
            state <= S_TRAP;
          end else begin
            if (decoded_write_rd && rd != 5'd0)
              regs[rd] <= decoded_result;
            pc     <= pc + 32'd4;
            retire <= 1'b1;
            state  <= S_FETCH;
          end
        end

        default: begin  // S_TRAP: 终止态, 停止发出存储器请求.
          state     <= S_TRAP;
          trap      <= 1'b1;
          mem_valid <= 1'b0;
        end
      endcase
    end
  end
endmodule

`default_nettype wire
