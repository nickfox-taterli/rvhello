`default_nettype none

// 完整 RV32I 主体 + FENCE (NOP)
// 取指与访存共用同一组总线握手; 引入 S_MEM 状态等待数据返回.

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
  localparam [1:0] S_MEM   = 2'd2;
  localparam [1:0] S_TRAP  = 2'd3;

  reg  [1:0]  state;
  reg  [31:0] ir;

  // 双异步读口, 同步写口. x0 通过读旁路固定为零, 不依赖数组单元内容.
  reg  [31:0] regs [0:31];

  // 指令字段只是 ir 的切片, 不占额外寄存器.
  wire [6:0] opcode = ir[6:0];
  wire [2:0] funct3 = ir[14:12];
  wire [6:0] funct7 = ir[31:25];
  wire [4:0] rd     = ir[11:7];
  wire [4:0] rs1    = ir[19:15];
  wire [4:0] rs2    = ir[24:20];

  wire [31:0] rs1_value = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
  wire [31:0] rs2_value = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

  // 用到的立即数: I/S/B/U/J 型 (移位 shamt 取 ir[24:20], 不走立即数重排).
  wire [31:0] imm_i = {{20{ir[31]}}, ir[31:20]};
  wire [31:0] imm_s = {{20{ir[31]}}, ir[31:25], ir[11:7]};
  wire [31:0] imm_u = {ir[31:12], 12'b0};
  wire [4:0]  shamt = ir[24:20];
  wire [31:0] imm_b = {{19{ir[31]}}, ir[31], ir[7], ir[30:25], ir[11:8], 1'b0};
  wire [31:0] imm_j = {{11{ir[31]}}, ir[31], ir[19:12], ir[20], ir[30:21], 1'b0};

  // 固定使用一拍完成的 barrel shift.
  wire [4:0] shift_amount = (opcode == 7'b0010011) ? shamt : rs2_value[4:0];
  wire shift_right = (funct3 == 3'b101);
  wire shift_arith = shift_right && (funct7 == 7'b0100000);
  wire [31:0] barrel_shift_result = shift_right ?
      (shift_arith ? ($signed(rs1_value) >>> shift_amount) : (rs1_value >> shift_amount)) :
      (rs1_value << shift_amount);

  // 组合译码只计算候选动作; 真正改 PC/寄存器/总线的操作集中在时序块.
  reg        decoded_legal;
  reg        decoded_write_rd;
  reg        decoded_start_mem;
  reg        decoded_is_load;
  reg [31:0] decoded_result;
  reg [31:0] decoded_next_pc;
  reg [31:0] decoded_address;
  reg [31:0] decoded_store_data;
  reg [ 3:0] decoded_store_strobe;

  always @* begin
    // 每条路径先给安全默认值, 避免组合 always 推断锁存器.
    decoded_legal        = 1'b1;
    decoded_write_rd     = 1'b0;
    decoded_start_mem    = 1'b0;
    decoded_is_load      = 1'b0;
    decoded_result       = 32'd0;
    decoded_next_pc      = pc + 32'd4;
    decoded_address      = 32'd0;
    decoded_store_data   = rs2_value;
    decoded_store_strobe = 4'b0000;

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
          3'b001: if (funct7 == 7'b0000000) decoded_result = barrel_shift_result;  // SLLI
          else decoded_legal = 1'b0;
          3'b101: if (funct7 == 7'b0000000) decoded_result = barrel_shift_result;  // SRLI
                  else if (funct7 == 7'b0100000) decoded_result = barrel_shift_result;  // SRAI
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
          3'b001: if (funct7 == 7'b0000000) decoded_result = barrel_shift_result;  // SLL
          else decoded_legal = 1'b0;
          3'b101: if (funct7 == 7'b0000000) decoded_result = barrel_shift_result;  // SRL
                  else if (funct7 == 7'b0100000) decoded_result = barrel_shift_result;  // SRA
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
        decoded_result   = pc + 32'd4;
        decoded_next_pc  = pc + imm_j;
        decoded_write_rd = 1'b1;
      end

      7'b1100111: begin  // JALR
        if (funct3 == 3'b000) begin
          decoded_result   = pc + 32'd4;
          decoded_next_pc  = (rs1_value + imm_i) & 32'hFFFF_FFFE;
          decoded_write_rd = 1'b1;
        end else begin
          decoded_legal = 1'b0;
        end
      end

      // 这一次复杂一点,因为可能涉及内存过程,就会置位decoded_start_mem.
      7'b0000011: begin  // LOAD
        decoded_address   = rs1_value + imm_i;
        decoded_start_mem = 1'b1;
        decoded_is_load   = 1'b1;
        // 只允许 LB/LH/LW/LBU/LHU; 其余 funct3 非法.
        if (!((funct3 == 3'b000) || (funct3 == 3'b001) || (funct3 == 3'b010) ||
              (funct3 == 3'b100) || (funct3 == 3'b101)))
          decoded_legal = 1'b0;
        // LH/LHU 要求地址半字对齐 (位 0 = 0).
        if (((funct3 == 3'b001) || (funct3 == 3'b101)) && decoded_address[0])
          decoded_legal = 1'b0;
        // LW 要求地址字对齐 (位 [1:0] = 0).
        if ((funct3 == 3'b010) && (|decoded_address[1:0]))
          decoded_legal = 1'b0;
      end

      7'b0100011: begin  // STORE
        decoded_address   = rs1_value + imm_s;
        decoded_start_mem = 1'b1;
        case (funct3)
          3'b000: begin  // SB: 低字节复制到 4 个通道, 由 wstrb 选中实际字节.
            decoded_store_strobe = 4'b0001 << decoded_address[1:0];
            decoded_store_data   = {4{rs2_value[7:0]}};
          end
          3'b001: begin  // SH
            decoded_store_strobe = decoded_address[1] ? 4'b1100 : 4'b0011;
            decoded_store_data   = {2{rs2_value[15:0]}};
            if (decoded_address[0]) decoded_legal = 1'b0;
          end
          3'b010: begin  // SW
            decoded_store_strobe = 4'b1111;
            decoded_store_data   = rs2_value;
            if (|decoded_address[1:0]) decoded_legal = 1'b0;
          end
          default: decoded_legal = 1'b0;
        endcase
      end

      7'b0001111: begin  // FENCE / FENCE.I
        // 本核顺序执行, 无乱序/缓存/写缓冲, 故无需任何排空, 直接当 NOP (仅要求 funct3=0).
        if (funct3 != 3'b000) decoded_legal = 1'b0;
      end

      7'b0001011: begin  // CUSTOM-0: GPO.WR rs1 -> 把 rs1 直接送总线写到 GPIO (0x1000_0000)
        // 固定字段 (funct7/funct3/rd/rs2 全 0) 锁死语义, 留出空间给未来子操作;
        // 不冒充任何标准 RV32I 指令. 仍走 S_MEM 握手, 故 CPU 与外设解耦,
        // 也支持精确异常/单步 (指令在写握手完成后才退休).
        if ((funct7 == 7'b0000000) && (funct3 == 3'b000) &&
            (rd == 5'd0) && (rs2 == 5'd0)) begin
          decoded_address      = 32'h1000_0000;
          decoded_start_mem    = 1'b1;
          decoded_store_strobe = 4'b1111;
          decoded_store_data   = rs1_value;   // rs1 的 32 位值就是 GPIO 输出
        end else begin
          decoded_legal        = 1'b0;        // 字段不符 -> 非法编码, trap
        end
      end

      // ECALL/EBREAK/其余 SYSTEM (1110011) 尚无特权架构, 由下面的 default 统一触发 trap.

      default: decoded_legal = 1'b0;  // 其余 opcode (含 ECALL/EBREAK/SYSTEM) 尚未实现
    endcase
  end

  // S_MEM 中使用的访存元数据必须提前锁存, 不能依赖下一次可能变化的译码结果.
  reg  [4:0]  load_rd;
  reg  [2:0]  load_funct3;
  reg  [1:0]  load_lane;
  reg         pending_load;
  reg  [15:0] selected_halfword;

  // 按字节通道从返回的 32 位数据中切出目标半字 (低 8 位即目标字节).
  always @* begin
    case (load_lane)
      2'd0:    selected_halfword = mem_rdata[15:0];
      2'd1:    selected_halfword = mem_rdata[23:8];
      2'd2:    selected_halfword = mem_rdata[31:16];
      default: selected_halfword = {8'b0, mem_rdata[31:24]};
    endcase
  end

  // 所有架构状态都只在时钟上升沿提交.
  always @(posedge clk) begin
    retire <= 1'b0;

    if (!resetn) begin
      state        <= S_FETCH;
      pc           <= RESET_PC;
      ir           <= 32'd0;
      trap         <= 1'b0;
      // 复位即预发起第一条取指, 每次退休也预发起下一条取指.
      mem_valid    <= 1'b1;
      mem_instr    <= 1'b1;
      mem_addr     <= RESET_PC;
      mem_wdata    <= 32'd0;
      mem_wstrb    <= 4'b0000;
      load_rd      <= 5'd0;
      load_funct3  <= 3'd0;
      load_lane    <= 2'd0;
      pending_load <= 1'b0;
      // 不复位通用寄存器, x0 的读旁路始终返回零.
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
            // 无 C 扩展, 控制流目标必须 4 字节对齐, 否则视为非法.
            trap  <= 1'b1;
            state <= S_TRAP;
          end else if (decoded_start_mem) begin
            // 一次性锁存完整访存请求; S_MEM 无论等待多久都不会重新译码.
            mem_valid    <= 1'b1;
            mem_instr    <= 1'b0;
            mem_addr     <= decoded_address;
            mem_wdata    <= decoded_store_data;
            mem_wstrb    <= decoded_is_load ? 4'b0000 : decoded_store_strobe; // 其实这里已经发起了写了,到S_MEM状态等待ready,ready后就完成了写,不需要再发起写了.
            load_rd      <= rd;
            load_funct3  <= funct3;
            load_lane    <= decoded_address[1:0];
            pending_load <= decoded_is_load;
            state        <= S_MEM;
          end else begin
            if (decoded_write_rd && rd != 5'd0)
              regs[rd] <= decoded_result;
            pc     <= decoded_next_pc;
            retire <= 1'b1;
            mem_valid <= 1'b1;
            mem_instr <= 1'b1;
            mem_addr  <= decoded_next_pc;
            mem_wstrb <= 4'b0000;
            state  <= S_FETCH;
          end
        end

        S_MEM: begin
          if (mem_valid && mem_ready) begin
            mem_valid <= 1'b0;
            if (pending_load && load_rd != 5'd0) begin
              case (load_funct3)
                3'b000: regs[load_rd] <= {{24{selected_halfword[7]}}, selected_halfword[7:0]};   // LB
                3'b001: regs[load_rd] <= {{16{selected_halfword[15]}}, selected_halfword};      // LH
                3'b010: regs[load_rd] <= mem_rdata;                                              // LW
                3'b100: regs[load_rd] <= {24'b0, selected_halfword[7:0]};                        // LBU
                3'b101: regs[load_rd] <= {16'b0, selected_halfword};                             // LHU
                default: regs[load_rd] <= regs[load_rd];  // 非法 funct3 已在 EXEC 拒绝.
              endcase
            end
            pc     <= pc + 32'd4;
            retire <= 1'b1;
            mem_valid <= 1'b1;
            mem_instr <= 1'b1;
            mem_addr  <= pc + 32'd4;
            mem_wstrb <= 4'b0000;
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
