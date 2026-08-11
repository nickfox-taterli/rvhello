`default_nettype none

// Wishbone B4 Classic 从端转回现有 valid/ready 总线.
// Wishbone 地址按字节寻址,TGA[0] 保留取指标记.
module wb_to_simple (
  input  wire        wb_cyc,
  input  wire        wb_stb,
  input  wire        wb_we,
  input  wire [31:0] wb_adr,
  input  wire [31:0] wb_dat_w,
  input  wire [3:0]  wb_sel,
  input  wire        wb_tga_instr,
  output wire        wb_ack,
  output wire        wb_err,
  output wire [31:0] wb_dat_r,

  output wire        m_valid,
  output wire        m_instr,
  output wire [31:0] m_addr,
  output wire [31:0] m_wdata,
  output wire [3:0]  m_wstrb,
  input  wire        m_ready,
  input  wire        m_error,
  input  wire [31:0] m_rdata
);
  assign m_valid = wb_cyc && wb_stb;
  assign m_instr = wb_tga_instr;
  assign m_addr  = wb_adr;
  assign m_wdata = wb_dat_w;
  assign m_wstrb = wb_we ? wb_sel : 4'b0000;

  // ACK 和 ERR 都是终止响应,二者不能在同一拍同时拉高.
  assign wb_ack   = m_valid && m_ready && !m_error;
  assign wb_err   = m_valid && m_ready && m_error;
  assign wb_dat_r = m_rdata;
endmodule

`default_nettype wire
