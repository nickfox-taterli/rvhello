`default_nettype none

// 完整 RV32I 主体 + M 扩展乘法 + FENCE (NOP)
// 取指与访存共用同一组总线握手; 引入 S_MEM 状态等待数据返回.

// | 格式 | 主要用途 | 典型指令 |
// | R 型 | 寄存器-寄存器 ALU | ADD, SUB, AND, OR, SLT |
// | I 型 | 立即数 ALU、Load、JALR、系统指令 | ADDI, LW, JALR |
// | S 型 | Store | SW, SH, SB |
// | B 型 | 条件分支 | BEQ, BNE, BLT |
// | U 型 | 高位立即数 | LUI, AUIPC |
// | J 型 | 跳转 | JAL |
module rv32i_core #(
    parameter [31:0] RESET_PC = 32'h0000_0000,
    parameter         ENABLE_M_PCPI = 1'b1,
    parameter         USE_DSP_MUL   = 1'b1
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire        dbg_halt_req,
    input  wire        dbg_resume_req,
    output wire        dbg_halted,
    input  wire        dbg_reg_valid,
    input  wire        dbg_reg_write,
    input  wire [15:0] dbg_reg_addr,
    input  wire [31:0] dbg_reg_wdata,
    output reg  [31:0] dbg_reg_rdata,
    output reg         dbg_reg_ready,
    output reg         dbg_reg_error,
    // irq_pending[n] 对应 mcause=n,方便后续直接扩展软件/定时器/外部 IRQ.
    input  wire [31:0] irq_pending,
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
  localparam [2:0] S_FETCH = 3'd0;
  localparam [2:0] S_EXEC  = 3'd1;
  localparam [2:0] S_MEM   = 3'd2;
  localparam [2:0] S_PCPI  = 3'd3;
  localparam [2:0] S_TRAP  = 3'd4;
  localparam [2:0] S_HALT  = 3'd5;

  reg  [2:0]  state;
  reg  [31:0] ir;
  reg         halt_pending;
  reg         halt_resume_exec;
  reg         step_active;
  reg  [31:0] csr_dcsr;

  assign dbg_halted = state == S_HALT;

  // 机器模式中断实现标准 CSR,中断位号直接使用 mcause 编号.
  reg  [31:0] csr_mstatus;
  reg  [31:0] csr_mie;
  reg  [31:0] csr_mtvec;
  reg  [31:0] csr_mepc;
  reg  [31:0] csr_mcause;

  reg         irq_any;
  reg  [4:0]  irq_cause;
  integer     irq_index;

  // 多个 IRQ 同拍到达时选择编号较大的一个. 当前标准外部中断 11 因此优先于
  // 定时器 7 和软件中断 3,未来加入 16-31 的平台中断也不需要再改状态机.
  always @* begin
    irq_any   = 1'b0;
    irq_cause = 5'd0;
    for (irq_index = 0; irq_index < 32; irq_index = irq_index + 1) begin
      if (irq_pending[irq_index] && csr_mie[irq_index]) begin
        irq_any   = 1'b1;
        irq_cause = irq_index[4:0];
      end
    end
  end

  wire interrupt_enabled = csr_mstatus[3] && irq_any;
  wire [31:0] interrupt_pc = (csr_mtvec[1:0] == 2'b01) ?
                             ({csr_mtvec[31:2], 2'b00} + {25'd0, irq_cause, 2'b00}) :
                             {csr_mtvec[31:2], 2'b00};

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
  reg        decoded_start_pcpi;
  reg        decoded_csr_write;
  reg        decoded_mret;
  reg        decoded_ebreak;
  reg [31:0] decoded_result;
  reg [31:0] decoded_next_pc;
  reg [31:0] decoded_address;
  reg [31:0] decoded_store_data;
  reg [ 3:0] decoded_store_strobe;
  reg [11:0] decoded_csr_addr;
  reg [31:0] decoded_csr_wdata;

  reg        csr_addr_legal;
  reg [31:0] csr_rdata;

  always @* begin
    csr_addr_legal = 1'b1;
    case (ir[31:20])
      12'h300: csr_rdata = csr_mstatus;
      12'h304: csr_rdata = csr_mie;
      12'h305: csr_rdata = csr_mtvec;
      12'h341: csr_rdata = csr_mepc;
      12'h342: csr_rdata = csr_mcause;
      12'h344: csr_rdata = irq_pending;
      default: begin
        csr_rdata      = 32'd0;
        csr_addr_legal = 1'b0;
      end
    endcase
  end

  always @* begin
    // 每条路径先给安全默认值, 避免组合 always 推断锁存器.
    decoded_legal        = 1'b1;
    decoded_write_rd     = 1'b0;
    decoded_start_mem    = 1'b0;
    decoded_is_load      = 1'b0;
    decoded_start_pcpi   = 1'b0;
    decoded_csr_write    = 1'b0;
    decoded_mret         = 1'b0;
    decoded_ebreak       = 1'b0;
    decoded_result       = 32'd0;
    decoded_next_pc      = pc + 32'd4;
    decoded_address      = 32'd0;
    decoded_store_data   = rs2_value;
    decoded_store_strobe = 4'b0000;
    decoded_csr_addr     = ir[31:20];
    decoded_csr_wdata    = 32'd0;

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
        if (funct7 == 7'b0000001) begin
          // M 指令由独立 PCPI 协处理器执行, 主 ALU 不保留慢单元数据通路.
          case (funct3)
            3'b000, 3'b001, 3'b010, 3'b011,
            3'b100, 3'b101, 3'b110, 3'b111: begin
              if (ENABLE_M_PCPI) decoded_start_pcpi = 1'b1;
              else decoded_legal = 1'b0;
            end
            default: decoded_legal = 1'b0;
          endcase
        end else begin
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

      7'b1110011: begin  // SYSTEM: 机器模式 CSR, MRET 和 WFI
        if (funct3 == 3'b000) begin
          // MRET 恢复中断前 PC; WFI 在这个小核里允许当 NOP 使用.
          if ((ir[31:20] == 12'h302) && (rs1 == 5'd0) && (rd == 5'd0)) begin
            decoded_mret = 1'b1;
          end else if ((ir[31:20] == 12'h001) && (rs1 == 5'd0) && (rd == 5'd0)) begin
            decoded_ebreak = 1'b1;
          end else if ((ir[31:20] == 12'h105) && (rs1 == 5'd0) && (rd == 5'd0)) begin
            decoded_next_pc = pc + 32'd4;
          end else begin
            decoded_legal = 1'b0;
          end
        end else if (csr_addr_legal) begin
          decoded_result   = csr_rdata;
          decoded_write_rd = 1'b1;
          case (funct3)
            3'b001: begin  // CSRRW
              decoded_csr_write = 1'b1;
              decoded_csr_wdata = rs1_value;
            end
            3'b010: begin  // CSRRS
              decoded_csr_write = (rs1 != 5'd0);
              decoded_csr_wdata = csr_rdata | rs1_value;
            end
            3'b011: begin  // CSRRC
              decoded_csr_write = (rs1 != 5'd0);
              decoded_csr_wdata = csr_rdata & ~rs1_value;
            end
            3'b101: begin  // CSRRWI
              decoded_csr_write = 1'b1;
              decoded_csr_wdata = {27'd0, rs1};
            end
            3'b110: begin  // CSRRSI
              decoded_csr_write = (rs1 != 5'd0);
              decoded_csr_wdata = csr_rdata | {27'd0, rs1};
            end
            3'b111: begin  // CSRRCI
              decoded_csr_write = (rs1 != 5'd0);
              decoded_csr_wdata = csr_rdata & ~{27'd0, rs1};
            end
            default: decoded_legal = 1'b0;
          endcase
        end else begin
          decoded_legal = 1'b0;
        end
      end

      default: decoded_legal = 1'b0;
    endcase
  end

  // S_MEM 中使用的访存元数据必须提前锁存, 不能依赖下一次可能变化的译码结果.
  reg  [4:0]  load_rd;
  reg  [2:0]  load_funct3;
  reg  [1:0]  load_lane;
  reg         pending_load;
  reg  [15:0] selected_halfword;

  // PCPI 接口让慢单元拥有独立握手. 当前仅内部连接 rv32m_pcpi,
  // 后续可以不动主核状态机而把这组线引到外部协处理器.
  wire        pcpi_valid = ENABLE_M_PCPI &&
                           (((state == S_EXEC) && decoded_start_pcpi) || (state == S_PCPI));
  wire        pcpi_wait;
  wire        pcpi_ready;
  wire        pcpi_wr;
  wire [31:0] pcpi_rd;

  generate
    if (ENABLE_M_PCPI) begin : gen_m_pcpi
      rv32m_pcpi #(
          .USE_DSP_MUL(USE_DSP_MUL)
      ) m_pcpi (
          .clk       (clk),
          .resetn    (resetn),
          .pcpi_valid(pcpi_valid),
          .pcpi_insn (ir),
          .pcpi_rs1  (rs1_value),
          .pcpi_rs2  (rs2_value),
          .pcpi_wait (pcpi_wait),
          .pcpi_ready(pcpi_ready),
          .pcpi_wr   (pcpi_wr),
          .pcpi_rd   (pcpi_rd)
      );
    end else begin : gen_no_m_pcpi
      assign pcpi_wait  = 1'b0;
      assign pcpi_ready = 1'b0;
      assign pcpi_wr    = 1'b0;
      assign pcpi_rd    = 32'd0;
    end
  endgenerate

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
      csr_mstatus  <= 32'd0;
      csr_mie      <= 32'd0;
      csr_mtvec    <= 32'd0;
      csr_mepc     <= 32'd0;
      csr_mcause   <= 32'd0;
      halt_pending <= 1'b0;
      halt_resume_exec <= 1'b0;
      step_active  <= 1'b0;
      csr_dcsr     <= 32'h4000_0003;
      dbg_reg_rdata <= 32'd0;
      dbg_reg_ready <= 1'b0;
      dbg_reg_error <= 1'b0;
      // 不复位通用寄存器, x0 的读旁路始终返回零.
    end else begin
      dbg_reg_ready <= 1'b0;
      dbg_reg_error <= 1'b0;
      // halt 请求可能只保持一拍,先锁存下来,等当前总线或 PCPI 事务完成再停.
      if (dbg_halt_req)
        halt_pending <= 1'b1;
      case (state)
        S_FETCH: begin
          // 已经发出的取指不能撤销. ready 后可以带着取到的 IR 停住,恢复时再执行.
          if (mem_valid && mem_ready) begin
            mem_valid <= 1'b0;
            ir        <= mem_rdata;
            if (halt_pending || dbg_halt_req) begin
              state            <= S_HALT;
              halt_resume_exec <= 1'b1;
              halt_pending     <= 1'b0;
              csr_dcsr[8:6]    <= 3'd3;
            end else if (interrupt_enabled) begin
              csr_mepc           <= {pc[31:2], 2'b00};
              csr_mcause         <= {1'b1, 26'd0, irq_cause};
              csr_mstatus[7]     <= csr_mstatus[3];
              csr_mstatus[3]     <= 1'b0;
              csr_mstatus[12:11] <= 2'b11;
              pc                 <= interrupt_pc;
            end else begin
              state <= S_EXEC;
            end
          end else if (mem_valid) begin
            // 等待中的取指保持所有请求信号不变.
          end else if (halt_pending || dbg_halt_req) begin
            state            <= S_HALT;
            halt_resume_exec <= 1'b0;
            halt_pending     <= 1'b0;
            csr_dcsr[8:6]    <= 3'd3;
          end else if (interrupt_enabled) begin
            csr_mepc         <= {pc[31:2], 2'b00};
            csr_mcause       <= {1'b1, 26'd0, irq_cause};
            csr_mstatus[7]   <= csr_mstatus[3];
            csr_mstatus[3]   <= 1'b0;
            csr_mstatus[12:11] <= 2'b11;
            pc               <= interrupt_pc;
          end else begin
            mem_valid <= 1'b1;
            mem_instr <= 1'b1;
            mem_addr  <= pc;
            mem_wstrb <= 4'b0000;
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
          end else if (decoded_mret) begin
            pc                 <= csr_mepc;
            csr_mstatus[3]     <= csr_mstatus[7];
            csr_mstatus[7]     <= 1'b1;
            csr_mstatus[12:11] <= 2'b00;
            retire             <= 1'b1;
            if (halt_pending || dbg_halt_req || step_active) begin
              mem_valid        <= 1'b0;
              state            <= S_HALT;
              halt_resume_exec <= 1'b0;
              halt_pending     <= 1'b0;
              step_active      <= 1'b0;
              csr_dcsr[8:6]    <= step_active ? 3'd4 : 3'd3;
            end else begin
              mem_valid <= 1'b1;
              mem_instr <= 1'b1;
              mem_addr  <= csr_mepc;
              mem_wstrb <= 4'b0000;
              state     <= S_FETCH;
            end
          end else if (decoded_ebreak) begin
            // EBREAK 在调试功能启用后进入 halt,PC 留在断点指令上供调试器检查.
            mem_valid        <= 1'b0;
            state            <= S_HALT;
            // 调试器可能在 resume 前把软件断点恢复成原指令,所以必须重新取指.
            halt_resume_exec <= 1'b0;
            halt_pending     <= 1'b0;
            step_active      <= 1'b0;
            csr_dcsr[8:6]    <= 3'd1;
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
          end else if (decoded_start_pcpi) begin
            // 发起拍 pcpi_valid=1, 协处理器锁存请求. 后续完成前 PC 和 IR 都保持不动.
            state <= S_PCPI;
          end else begin
            if (decoded_write_rd && rd != 5'd0)
              regs[rd] <= decoded_result;
            if (decoded_csr_write) begin
              case (decoded_csr_addr)
                12'h300: csr_mstatus <= decoded_csr_wdata & 32'h0000_1888;
                12'h304: csr_mie     <= decoded_csr_wdata;
                12'h305: csr_mtvec   <= {decoded_csr_wdata[31:2],
                                         (decoded_csr_wdata[1:0] == 2'b01) ? 2'b01 : 2'b00};
                12'h341: csr_mepc    <= {decoded_csr_wdata[31:2], 2'b00};
                12'h342: csr_mcause  <= decoded_csr_wdata;
                default: begin end  // mip 的 MTIP 来自硬件, 软件写入不改变它.
              endcase
            end
            pc     <= decoded_next_pc;
            retire <= 1'b1;
            if (halt_pending || dbg_halt_req || step_active) begin
              mem_valid        <= 1'b0;
              state            <= S_HALT;
              halt_resume_exec <= 1'b0;
              halt_pending     <= 1'b0;
              step_active      <= 1'b0;
              csr_dcsr[8:6]    <= step_active ? 3'd4 : 3'd3;
            end else begin
              mem_valid <= 1'b1;
              mem_instr <= 1'b1;
              mem_addr  <= decoded_next_pc;
              mem_wstrb <= 4'b0000;
              state     <= S_FETCH;
            end
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
            if (halt_pending || dbg_halt_req || step_active) begin
              mem_valid        <= 1'b0;
              state            <= S_HALT;
              halt_resume_exec <= 1'b0;
              halt_pending     <= 1'b0;
              step_active      <= 1'b0;
              csr_dcsr[8:6]    <= step_active ? 3'd4 : 3'd3;
            end else begin
              mem_valid <= 1'b1;
              mem_instr <= 1'b1;
              mem_addr  <= pc + 32'd4;
              mem_wstrb <= 4'b0000;
              state     <= S_FETCH;
            end
          end
        end

        S_PCPI: begin
          // 协处理器给出 ready 后才退休, 这样任意慢单元都不会影响主核提交语义.
          if (pcpi_ready) begin
            if (pcpi_wr && rd != 5'd0)
              regs[rd] <= pcpi_rd;
            pc        <= pc + 32'd4;
            retire    <= 1'b1;
            if (halt_pending || dbg_halt_req || step_active) begin
              mem_valid        <= 1'b0;
              state            <= S_HALT;
              halt_resume_exec <= 1'b0;
              halt_pending     <= 1'b0;
              step_active      <= 1'b0;
              csr_dcsr[8:6]    <= step_active ? 3'd4 : 3'd3;
            end else begin
              mem_valid <= 1'b1;
              mem_instr <= 1'b1;
              mem_addr  <= pc + 32'd4;
              mem_wstrb <= 4'b0000;
              state     <= S_FETCH;
            end
          end
        end

        S_HALT: begin
          // 这里只冻结核状态,系统时钟和外设继续运行. resume 后从精确边界接着走.
          mem_valid <= 1'b0;
          if (dbg_reg_valid) begin
            dbg_reg_ready <= 1'b1;
            if (dbg_reg_addr[15:5] == 11'h080) begin
              dbg_reg_rdata <= dbg_reg_addr[4:0] == 5'd0 ? 32'd0 : regs[dbg_reg_addr[4:0]];
              if (dbg_reg_write && dbg_reg_addr[4:0] != 5'd0)
                regs[dbg_reg_addr[4:0]] <= dbg_reg_wdata;
            end else begin
              case (dbg_reg_addr)
                16'h0300: begin dbg_reg_rdata <= csr_mstatus; if (dbg_reg_write) csr_mstatus <= dbg_reg_wdata & 32'h0000_1888; end
                16'h0301: begin dbg_reg_rdata <= ENABLE_M_PCPI ? 32'h4000_1100 : 32'h4000_0100; if (dbg_reg_write) dbg_reg_error <= 1'b1; end
                16'h0304: begin dbg_reg_rdata <= csr_mie;     if (dbg_reg_write) csr_mie <= dbg_reg_wdata; end
                16'h0305: begin dbg_reg_rdata <= csr_mtvec;   if (dbg_reg_write) csr_mtvec <= {dbg_reg_wdata[31:2], 2'b00}; end
                16'h0341: begin dbg_reg_rdata <= csr_mepc;    if (dbg_reg_write) csr_mepc <= {dbg_reg_wdata[31:2], 2'b00}; end
                16'h0342: begin dbg_reg_rdata <= csr_mcause;  if (dbg_reg_write) csr_mcause <= dbg_reg_wdata; end
                16'h0344: begin dbg_reg_rdata <= irq_pending; if (dbg_reg_write) dbg_reg_error <= 1'b1; end
                16'h07b0: begin
                  dbg_reg_rdata <= csr_dcsr;
                  if (dbg_reg_write)
                    csr_dcsr <= {4'd4, 17'd0, csr_dcsr[10:6], 3'd0, dbg_reg_wdata[2], 2'b11};
                end
                16'h07b1: begin
                  dbg_reg_rdata <= pc;
                  if (dbg_reg_write) begin
                    pc <= {dbg_reg_wdata[31:1], 1'b0};
                    // DPC 被调试器改写后,之前预取的 IR 已经不再对应这个 PC.
                    halt_resume_exec <= 1'b0;
                  end
                end
                16'h0f11,
                16'h0f12,
                16'h0f13,
                16'h0f14: begin dbg_reg_rdata <= 32'd0; if (dbg_reg_write) dbg_reg_error <= 1'b1; end
                default: begin dbg_reg_rdata <= 32'd0; dbg_reg_error <= 1'b1; end
              endcase
            end
          end else if (dbg_resume_req && !dbg_halt_req) begin
            halt_pending <= 1'b0;
            step_active <= csr_dcsr[2];
            if (halt_resume_exec) begin
              state <= S_EXEC;
            end else begin
              mem_valid <= 1'b1;
              mem_instr <= 1'b1;
              mem_addr  <= pc;
              mem_wstrb <= 4'b0000;
              state     <= S_FETCH;
            end
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
