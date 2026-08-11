`default_nettype none

// Xilinx USER3/USER4 分别承载 DTMCS/DMI,与下载 bitstream 的主 JTAG 共用引脚.
module bscan_dtm (
  input  wire        sim_resetn,
  output wire        req_toggle,
  output wire        req_write,
  output wire [6:0]  req_addr,
  output wire [31:0] req_wdata,
  input  wire        ack_toggle,
  input  wire [31:0] rsp_rdata,
  input  wire        rsp_error
);
`ifdef SYNTHESIS
  wire tck_raw;
  wire tck;
  wire tdi;
  wire capture;
  wire shift;
  wire update;
  wire tap_reset;
  wire sel_dtmcs;
  wire sel_dmi;
  wire tdo;

  BSCANE2 #(.JTAG_CHAIN(3)) user3 (
    .CAPTURE(capture), .DRCK(), .RESET(tap_reset), .RUNTEST(), .SEL(sel_dtmcs),
    .SHIFT(shift), .TCK(tck_raw), .TDI(tdi), .TMS(), .UPDATE(update), .TDO(tdo)
  );
  BSCANE2 #(.JTAG_CHAIN(4)) user4 (
    .CAPTURE(), .DRCK(), .RESET(), .RUNTEST(), .SEL(sel_dmi),
    .SHIFT(), .TCK(), .TDI(), .TMS(), .UPDATE(), .TDO(tdo)
  );
  BUFG tck_buf (.I(tck_raw), .O(tck));

  jtag_dtm_cdc transport (
    .tck(tck), .trst_n(!tap_reset),
    .dr_capture(capture && (sel_dtmcs || sel_dmi)),
    .dr_shift(shift && (sel_dtmcs || sel_dmi)),
    .dr_update(update && (sel_dtmcs || sel_dmi)),
    .select_dmi(sel_dmi), .tdi(tdi), .tdo(tdo),
    .req_toggle(req_toggle), .req_write(req_write), .req_addr(req_addr),
    .req_wdata(req_wdata), .ack_toggle(ack_toggle), .rsp_rdata(rsp_rdata),
    .rsp_error(rsp_error)
  );
`else
  // 行为仿真不实例化器件原语,独立 IO TAP 会覆盖协议和 DMI 后端测试.
  assign req_toggle = 1'b0;
  assign req_write  = 1'b0;
  assign req_addr   = 7'd0;
  assign req_wdata  = 32'd0;
  wire unused = &{1'b0, sim_resetn, ack_toggle, rsp_rdata, rsp_error};
`endif
endmodule

`default_nettype wire
