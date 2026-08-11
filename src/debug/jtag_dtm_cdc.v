`default_nettype none

// DTM 侧把请求字段保持到 ack 返回,所以这里只需要同步两个翻转位.
// 数据总线会在翻转位穿过两级同步器前稳定下来,返回方向也是同样的约束.
module jtag_dtm_cdc #(
  parameter [31:0] IDCODE = 32'h1363_1093
) (
  input  wire        tck,
  input  wire        trst_n,
  input  wire        dr_capture,
  input  wire        dr_shift,
  input  wire        dr_update,
  input  wire        select_dmi,
  input  wire        tdi,
  output wire        tdo,

  output reg         req_toggle,
  output reg         req_write,
  output reg  [6:0]  req_addr,
  output reg  [31:0] req_wdata,
  input  wire        ack_toggle,
  input  wire [31:0] rsp_rdata,
  input  wire        rsp_error
);
  localparam integer DMI_BITS = 41;

  reg [DMI_BITS-1:0] dr;
  reg [1:0]          dmi_error;
  reg                busy;
  reg                ack_sync1;
  reg                ack_sync2;
  reg [31:0]         last_rdata;

  wire [31:0] dtmcs = {14'd0, 1'b0, 1'b0, 1'b0, 3'd4, dmi_error, 6'd7, 4'd1};
  assign tdo = dr[0];

  always @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      dr         <= {DMI_BITS{1'b0}};
      dmi_error  <= 2'd0;
      busy       <= 1'b0;
      req_toggle <= 1'b0;
      req_write  <= 1'b0;
      req_addr   <= 7'd0;
      req_wdata  <= 32'd0;
      ack_sync1  <= 1'b0;
      ack_sync2  <= 1'b0;
      last_rdata <= 32'd0;
    end else begin
      ack_sync1 <= ack_toggle;
      ack_sync2 <= ack_sync1;

      if (busy && ack_sync2 == req_toggle) begin
        busy       <= 1'b0;
        last_rdata <= rsp_rdata;
        if (rsp_error)
          dmi_error <= 2'd2;
      end

      if (dr_capture) begin
        if (select_dmi)
          dr <= {7'd0, last_rdata, (busy && dmi_error == 2'd0) ? 2'd3 : dmi_error};
        else
          dr <= {{DMI_BITS-32{1'b0}}, dtmcs};
      end else if (dr_shift) begin
        dr <= {tdi, dr[DMI_BITS-1:1]};
        if (!select_dmi)
          dr[31] <= tdi;
      end

      if (dr_update) begin
        if (select_dmi) begin
          if ((dr[1:0] == 2'd1 || dr[1:0] == 2'd2) && !busy && dmi_error == 2'd0) begin
            req_write  <= dr[1] == 1'b1;
            req_addr   <= dr[40:34];
            req_wdata  <= dr[33:2];
            req_toggle <= ~req_toggle;
            busy       <= 1'b1;
          end else if (dr[1:0] != 2'd0 && dmi_error == 2'd0) begin
            dmi_error <= 2'd3;
          end
        end else begin
          if (dr[16])
            dmi_error <= 2'd0;
        end
      end
    end
  end
endmodule

`default_nettype wire
