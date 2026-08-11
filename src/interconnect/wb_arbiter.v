`default_nettype none

// 多主一从 Wishbone B4 Classic 仲裁器.高编号主端优先,在途事务不能被抢占.
// 各主端使用打包向量,主端 N 的字段位于 N*WIDTH +: WIDTH.
module wb_arbiter #(
  parameter integer MASTERS = 2,
  parameter integer ADDR_W  = 32,
  parameter integer DATA_W  = 32,
  parameter integer SEL_W   = DATA_W / 8
) (
  input  wire                    clk,
  input  wire                    resetn,

  input  wire [MASTERS-1:0]      m_cyc,
  input  wire [MASTERS-1:0]      m_stb,
  input  wire [MASTERS-1:0]      m_we,
  input  wire [MASTERS*ADDR_W-1:0] m_adr,
  input  wire [MASTERS*DATA_W-1:0] m_dat_w,
  input  wire [MASTERS*SEL_W-1:0]  m_sel,
  input  wire [MASTERS-1:0]      m_tga_instr,
  output wire [MASTERS-1:0]      m_ack,
  output wire [MASTERS-1:0]      m_err,
  output wire [MASTERS*DATA_W-1:0] m_dat_r,

  output wire                    s_cyc,
  output wire                    s_stb,
  output wire                    s_we,
  output wire [ADDR_W-1:0]       s_adr,
  output wire [DATA_W-1:0]       s_dat_w,
  output wire [SEL_W-1:0]        s_sel,
  output wire                    s_tga_instr,
  input  wire                    s_ack,
  input  wire                    s_err,
  input  wire [DATA_W-1:0]       s_dat_r
);
  localparam integer MASTER_W = (MASTERS <= 1) ? 1 : $clog2(MASTERS);

  reg                    grant_valid;
  reg [MASTER_W-1:0]     grant_index;
  reg                    request_valid;
  reg [MASTER_W-1:0]     request_index;
  integer master_index;

  // 从低到高扫描,后命中的高编号覆盖前者,所以高编号优先.
  always @* begin
    request_valid = 1'b0;
    request_index = {MASTER_W{1'b0}};
    for (master_index = 0; master_index < MASTERS; master_index = master_index + 1) begin
      if (m_cyc[master_index]) begin
        request_valid = 1'b1;
        request_index = master_index;
      end
    end
  end

  wire [MASTER_W-1:0] selected_index = grant_valid ? grant_index : request_index;
  wire selected_valid = grant_valid ? m_cyc[grant_index] : request_valid;

  assign s_cyc       = selected_valid;
  assign s_stb       = selected_valid ? m_stb[selected_index] : 1'b0;
  assign s_we        = selected_valid ? m_we[selected_index] : 1'b0;
  assign s_adr       = selected_valid ? m_adr[selected_index*ADDR_W +: ADDR_W] : {ADDR_W{1'b0}};
  assign s_dat_w     = selected_valid ? m_dat_w[selected_index*DATA_W +: DATA_W] : {DATA_W{1'b0}};
  assign s_sel       = selected_valid ? m_sel[selected_index*SEL_W +: SEL_W] : {SEL_W{1'b0}};
  assign s_tga_instr = selected_valid ? m_tga_instr[selected_index] : 1'b0;

  genvar response_index;
  generate
    for (response_index = 0; response_index < MASTERS; response_index = response_index + 1) begin : gen_response
      assign m_ack[response_index] = selected_valid &&
                                     (selected_index == response_index) && s_ack;
      assign m_err[response_index] = selected_valid &&
                                     (selected_index == response_index) && s_err;
      assign m_dat_r[response_index*DATA_W +: DATA_W] = s_dat_r;
    end
  endgenerate

  always @(posedge clk) begin
    if (!resetn) begin
      grant_valid <= 1'b0;
      grant_index <= {MASTER_W{1'b0}};
    end else if (grant_valid) begin
      if (!m_cyc[grant_index] || s_ack || s_err)
        grant_valid <= 1'b0;
    end else if (request_valid && !(s_ack || s_err)) begin
      grant_valid <= 1'b1;
      grant_index <= request_index;
    end
  end
endmodule

`default_nettype wire
