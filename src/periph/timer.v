`default_nettype none

// CLINT 风格的机器态定时器和软件中断从端.
// 基址由总线译码器固定为 0x0200_0000,这里使用低 16 位分址:
//   0x0000 + 4*hart       msip[hart]      RW,只有 bit 0 有效
//   0x4000 + 8*hart       mtimecmp[hart]  RW,低 32 位
//   0x4004 + 8*hart       mtimecmp[hart]  RW,高 32 位
//   0xbff8                mtime           RW,低 32 位
//   0xbffc                mtime           RW,高 32 位
// MTIP 是电平信号,mtime >= mtimecmp 时为 1.软件通过更新 mtimecmp 撤销它.
module timer #(
  parameter integer HARTS = 1
) (
  input  wire             clk,
  input  wire             resetn,
  input  wire             sel_valid,
  input  wire [31:0]      mem_addr,
  input  wire [31:0]      mem_wdata,
  input  wire [3:0]       mem_wstrb,
  output wire             mem_ready,
  output reg  [31:0]      mem_rdata,
  output wire [HARTS-1:0] timer_mtip,
  output wire [HARTS-1:0] timer_msip
);
  localparam [15:0] MTIMECMP_BASE = 16'h4000;
  localparam [15:0] MTIME_LO       = 16'hbff8;
  localparam [15:0] MTIME_HI       = 16'hbffc;

  reg [63:0] mtime;
  reg [63:0] mtimecmp [0:HARTS-1];
  reg [HARTS-1:0] msip;
  integer hart;

  assign mem_ready  = sel_valid;
  assign timer_msip = msip;

  genvar gen_hart;
  generate
    for (gen_hart = 0; gen_hart < HARTS; gen_hart = gen_hart + 1) begin : gen_irq
      assign timer_mtip[gen_hart] = (mtime >= mtimecmp[gen_hart]);
    end
  endgenerate

  always @(posedge clk) begin
    if (!resetn) begin
      mtime <= 64'd0;
      msip  <= {HARTS{1'b0}};
      for (hart = 0; hart < HARTS; hart = hart + 1)
        mtimecmp[hart] <= 64'hffff_ffff_ffff_ffff;
    end else begin
      mtime <= mtime + 64'd1;

      if (sel_valid && (|mem_wstrb)) begin
        // RV32 软件会分两次访问 64 位寄存器,每次写仍保留字节使能.
        if (mem_addr[15:0] == MTIME_LO) begin
          if (mem_wstrb[0]) mtime[ 7: 0] <= mem_wdata[ 7: 0];
          if (mem_wstrb[1]) mtime[15: 8] <= mem_wdata[15: 8];
          if (mem_wstrb[2]) mtime[23:16] <= mem_wdata[23:16];
          if (mem_wstrb[3]) mtime[31:24] <= mem_wdata[31:24];
        end
        if (mem_addr[15:0] == MTIME_HI) begin
          if (mem_wstrb[0]) mtime[39:32] <= mem_wdata[ 7: 0];
          if (mem_wstrb[1]) mtime[47:40] <= mem_wdata[15: 8];
          if (mem_wstrb[2]) mtime[55:48] <= mem_wdata[23:16];
          if (mem_wstrb[3]) mtime[63:56] <= mem_wdata[31:24];
        end

        for (hart = 0; hart < HARTS; hart = hart + 1) begin
          if (mem_addr[15:0] == (16'h0000 + hart * 4)) begin
            if (mem_wstrb[0]) msip[hart] <= mem_wdata[0];
          end
          if (mem_addr[15:0] == (MTIMECMP_BASE + hart * 8)) begin
            if (mem_wstrb[0]) mtimecmp[hart][ 7: 0] <= mem_wdata[ 7: 0];
            if (mem_wstrb[1]) mtimecmp[hart][15: 8] <= mem_wdata[15: 8];
            if (mem_wstrb[2]) mtimecmp[hart][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) mtimecmp[hart][31:24] <= mem_wdata[31:24];
          end
          if (mem_addr[15:0] == (MTIMECMP_BASE + hart * 8 + 4)) begin
            if (mem_wstrb[0]) mtimecmp[hart][39:32] <= mem_wdata[ 7: 0];
            if (mem_wstrb[1]) mtimecmp[hart][47:40] <= mem_wdata[15: 8];
            if (mem_wstrb[2]) mtimecmp[hart][55:48] <= mem_wdata[23:16];
            if (mem_wstrb[3]) mtimecmp[hart][63:56] <= mem_wdata[31:24];
          end
        end
      end
    end
  end

  always @* begin
    mem_rdata = 32'd0;
    if (mem_addr[15:0] == MTIME_LO) mem_rdata = mtime[31:0];
    if (mem_addr[15:0] == MTIME_HI) mem_rdata = mtime[63:32];
    for (hart = 0; hart < HARTS; hart = hart + 1) begin
      if (mem_addr[15:0] == (16'h0000 + hart * 4))
        mem_rdata = {31'd0, msip[hart]};
      if (mem_addr[15:0] == (MTIMECMP_BASE + hart * 8))
        mem_rdata = mtimecmp[hart][31:0];
      if (mem_addr[15:0] == (MTIMECMP_BASE + hart * 8 + 4))
        mem_rdata = mtimecmp[hart][63:32];
    end
  end
endmodule

`default_nettype wire
