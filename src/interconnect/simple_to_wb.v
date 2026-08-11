`default_nettype none

// 把核内单事务 valid/ready 接口转成 Wishbone B4 Classic 主端.
// 请求会先锁存,随后一直保持 CYC/STB 和负载不变,直到 ACK 或 ERR 结束事务.
module simple_to_wb (
  input  wire        clk,
  input  wire        resetn,

  input  wire        s_valid,
  input  wire        s_instr,
  input  wire [31:0] s_addr,
  input  wire [31:0] s_wdata,
  input  wire [3:0]  s_wstrb,
  output wire        s_ready,
  output wire        s_error,
  output wire [31:0] s_rdata,

  output reg         wb_cyc,
  output reg         wb_stb,
  output reg         wb_we,
  output reg  [31:0] wb_adr,
  output reg  [31:0] wb_dat_w,
  output reg  [3:0]  wb_sel,
  output reg         wb_tga_instr,
  input  wire        wb_ack,
  input  wire        wb_err,
  input  wire [31:0] wb_dat_r
);
  wire wb_done = wb_cyc && (wb_ack || wb_err);

  assign s_ready = wb_done;
  assign s_error = wb_cyc && wb_err;
  assign s_rdata = wb_dat_r;

  always @(posedge clk) begin
    if (!resetn) begin
      wb_cyc       <= 1'b0;
      wb_stb       <= 1'b0;
      wb_we        <= 1'b0;
      wb_adr       <= 32'd0;
      wb_dat_w     <= 32'd0;
      wb_sel       <= 4'd0;
      wb_tga_instr <= 1'b0;
    end else if (!wb_cyc) begin
      if (s_valid) begin
        wb_cyc       <= 1'b1;
        wb_stb       <= 1'b1;
        wb_we        <= |s_wstrb;
        wb_adr       <= s_addr;
        wb_dat_w     <= s_wdata;
        wb_sel       <= (|s_wstrb) ? s_wstrb : 4'b1111;
        wb_tga_instr <= s_instr;
      end
    end else if (wb_done) begin
      wb_cyc <= 1'b0;
      wb_stb <= 1'b0;
    end
  end
endmodule

`default_nettype wire
