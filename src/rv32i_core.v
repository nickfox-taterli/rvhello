`default_nettype none

// 第5阶段实现 => 之前已经完成的内容 + 无条件跳转与链接 (JAL/JALR)

// | 格式 | 主要用途 | 典型指令 |
// | R 型 | 寄存器-寄存器 ALU | ADD, SUB, AND, OR, SLT |
// | I 型 | 立即数 ALU、Load、JALR、系统指令 | ADDI, LW, JALR |
// | S 型 | Store | SW, SH, SB |
// | B 型 | 条件分支 | BEQ, BNE, BLT |
// | U 型 | 高位立即数 | LUI, AUIPC |
// | J 型 | 跳转 | JAL |
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
  wire [6:0] funct7 = ir[31:25];
  wire [4:0] rd     = ir[11:7];
  wire [4:0] rs1    = ir[19:15];
  wire [4:0] rs2    = ir[24:20];

  // x0 必须始终读出零, 不依赖数组单元内容.
  wire [31:0] rs1_value = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
  wire [31:0] rs2_value = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

  // 用到的立即数: I/U/B/J 型 (移位 shamt 取 ir[24:20], 不走立即数重排).
  wire [31:0] imm_i = {{20{ir[31]}}, ir[31:20]};
  wire [31:0] imm_u = {ir[31:12], 12'b0};
  wire [4:0]  shamt = ir[24:20];
  wire [31:0] imm_b = {{19{ir[31]}}, ir[31], ir[7], ir[30:25], ir[11:8], 1'b0};
  wire [31:0] imm_j = {{11{ir[31]}}, ir[31], ir[19:12], ir[20], ir[30:21], 1'b0};

  // 组合译码只计算候选动作; 真正改 PC/寄存器/总线的操作集中在时序块.
  reg        decoded_legal;
  reg        decoded_write_rd;
  reg [31:0] decoded_result;
  reg [31:0] decoded_next_pc;  // 默认 pc+4, 分支/跳转命中时改为目标地址

  always @* begin
    // 每条路径先给安全默认值, 避免组合 always 推断锁存器.
    decoded_legal    = 1'b1;
    decoded_write_rd = 1'b0;
    decoded_result   = 32'd0;
    decoded_next_pc  = pc + 32'd4;  // 如果没有分支/跳转, 这是默认.

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
        decoded_write_rd = 1'b1;
        case (funct3)
          3'b000: decoded_result = rs1_value + imm_i;                          // ADDI
          3'b010: decoded_result = {31'b0, $signed(rs1_value) < $signed(imm_i)};  // SLTI
          3'b011: decoded_result = {31'b0, rs1_value < imm_i};                 // SLTIU
          3'b100: decoded_result = rs1_value ^ imm_i;                          // XORI
          3'b110: decoded_result = rs1_value | imm_i;                          // ORI
          3'b111: decoded_result = rs1_value & imm_i;                          // ANDI
          3'b001: if (funct7 == 7'b0000000) decoded_result = rs1_value << shamt;  // SLLI
                  else decoded_legal = 1'b0;
          3'b101: if (funct7 == 7'b0000000) decoded_result = rs1_value >> shamt;  // SRLI
                  else if (funct7 == 7'b0100000) decoded_result = $signed(rs1_value) >>> shamt;  // SRAI
                  else decoded_legal = 1'b0;
          default: decoded_legal = 1'b0;
        endcase
      end

      7'b0110011: begin  // OP (R 型)
        decoded_write_rd = 1'b1;
        case (funct3)
          3'b000: if (funct7 == 7'b0000000) decoded_result = rs1_value + rs2_value;       // ADD
                  else if (funct7 == 7'b0100000) decoded_result = rs1_value - rs2_value;  // SUB
                  else decoded_legal = 1'b0;
          3'b010: if (funct7 == 7'b0000000) decoded_result = {31'b0, $signed(rs1_value) < $signed(rs2_value)};  // SLT
                  else decoded_legal = 1'b0;
          3'b011: if (funct7 == 7'b0000000) decoded_result = {31'b0, rs1_value < rs2_value};  // SLTU
                  else decoded_legal = 1'b0;
          3'b100: if (funct7 == 7'b0000000) decoded_result = rs1_value ^ rs2_value;  // XOR
                  else decoded_legal = 1'b0;
          3'b110: if (funct7 == 7'b0000000) decoded_result = rs1_value | rs2_value;  // OR
                  else decoded_legal = 1'b0;
          3'b111: if (funct7 == 7'b0000000) decoded_result = rs1_value & rs2_value;  // AND
                  else decoded_legal = 1'b0;
          3'b001: if (funct7 == 7'b0000000) decoded_result = rs1_value << rs2_value[4:0];  // SLL
                  else decoded_legal = 1'b0;
          3'b101: if (funct7 == 7'b0000000) decoded_result = rs1_value >> rs2_value[4:0];  // SRL
                  else if (funct7 == 7'b0100000) decoded_result = $signed(rs1_value) >>> rs2_value[4:0];  // SRA
                  else decoded_legal = 1'b0;
          default: decoded_legal = 1'b0;
        endcase
      end

      7'b1100011: begin  // BRANCH
        case (funct3)
          3'b000: if (rs1_value == rs2_value) decoded_next_pc = pc + imm_b;                       // BEQ
          3'b001: if (rs1_value != rs2_value) decoded_next_pc = pc + imm_b;                       // BNE
          3'b100: if ($signed(rs1_value) <  $signed(rs2_value)) decoded_next_pc = pc + imm_b;     // BLT
          3'b101: if ($signed(rs1_value) >= $signed(rs2_value)) decoded_next_pc = pc + imm_b;     // BGE
          3'b110: if (rs1_value <  rs2_value) decoded_next_pc = pc + imm_b;                       // BLTU
          3'b111: if (rs1_value >= rs2_value) decoded_next_pc = pc + imm_b;                       // BGEU
          default: decoded_legal = 1'b0;
        endcase
      end

      7'b1101111: begin  // JAL
        decoded_result   = pc + 32'd4;   // 链接寄存器 = 返回地址
        decoded_next_pc  = pc + imm_j;
        decoded_write_rd = 1'b1;
      end

      7'b1100111: begin  // JALR
        if (funct3 == 3'b000) begin
          decoded_result   = pc + 32'd4;  // 链接寄存器 = 返回地址
          decoded_next_pc  = (rs1_value + imm_i) & 32'hFFFF_FFFE;
          decoded_write_rd = 1'b1;
        end else begin
          decoded_legal = 1'b0;
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
          end else if (((opcode == 7'b1100011) || (opcode == 7'b1101111) ||
                        (opcode == 7'b1100111)) && (|decoded_next_pc[1:0])) begin
            // 无 C 扩展, 控制流 (分支/JAL/JALR) 目标必须 4 字节对齐, 否则视为非法.
            trap  <= 1'b1;
            state <= S_TRAP;
          end else begin
            if (decoded_write_rd && rd != 5'd0)
              regs[rd] <= decoded_result;
            pc     <= decoded_next_pc;
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
