`default_nettype none

// 独立 IO 上的标准 5 位 RISC-V JTAG TAP. IR 0x10 是 DTMCS,0x11 是 DMI.
module jtag_dtm_tap (
  input  wire        tck,
  input  wire        trst_n,
  input  wire        tms,
  input  wire        tdi,
  output reg         tdo,
  output wire        req_toggle,
  output wire        req_write,
  output wire [6:0]  req_addr,
  output wire [31:0] req_wdata,
  input  wire        ack_toggle,
  input  wire [31:0] rsp_rdata,
  input  wire        rsp_error
);
  localparam [3:0] RESET=0, IDLE=1, SEL_DR=2, CAP_DR=3, SHIFT_DR=4, EXIT1_DR=5,
                   PAUSE_DR=6, EXIT2_DR=7, UPDATE_DR=8, SEL_IR=9, CAP_IR=10,
                   SHIFT_IR=11, EXIT1_IR=12, PAUSE_IR=13, EXIT2_IR=14, UPDATE_IR=15;
  localparam [4:0] IR_IDCODE=5'h01, IR_DTMCS=5'h10, IR_DMI=5'h11;

  reg [3:0] state;
  reg [4:0] ir;
  reg [4:0] ir_shift;
  reg [31:0] idcode_shift;
  reg bypass;
  wire dtm_tdo;
  wire dtm_selected = ir == IR_DMI || ir == IR_DTMCS;

  always @(posedge tck or negedge trst_n) begin
    if (!trst_n) state <= RESET;
    else case (state)
      RESET: state <= tms ? RESET : IDLE;
      IDLE: state <= tms ? SEL_DR : IDLE;
      SEL_DR: state <= tms ? SEL_IR : CAP_DR;
      CAP_DR: state <= tms ? EXIT1_DR : SHIFT_DR;
      SHIFT_DR: state <= tms ? EXIT1_DR : SHIFT_DR;
      EXIT1_DR: state <= tms ? UPDATE_DR : PAUSE_DR;
      PAUSE_DR: state <= tms ? EXIT2_DR : PAUSE_DR;
      EXIT2_DR: state <= tms ? UPDATE_DR : SHIFT_DR;
      UPDATE_DR: state <= tms ? SEL_DR : IDLE;
      SEL_IR: state <= tms ? RESET : CAP_IR;
      CAP_IR: state <= tms ? EXIT1_IR : SHIFT_IR;
      SHIFT_IR: state <= tms ? EXIT1_IR : SHIFT_IR;
      EXIT1_IR: state <= tms ? UPDATE_IR : PAUSE_IR;
      PAUSE_IR: state <= tms ? EXIT2_IR : PAUSE_IR;
      EXIT2_IR: state <= tms ? UPDATE_IR : SHIFT_IR;
      default: state <= tms ? SEL_DR : IDLE;
    endcase
  end

  always @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      ir <= IR_IDCODE;
      ir_shift <= 5'b00001;
      idcode_shift <= 32'h1000_00db;
      bypass <= 1'b0;
    end else if (state == RESET) begin
      ir <= IR_IDCODE;
    end else if (state == CAP_IR) begin
      ir_shift <= 5'b00001;
    end else if (state == SHIFT_IR) begin
      ir_shift <= {tdi, ir_shift[4:1]};
    end else if (state == UPDATE_IR) begin
      ir <= ir_shift;
    end else if (state == CAP_DR) begin
      if (ir == IR_IDCODE) idcode_shift <= 32'h1000_00db;
      else if (!dtm_selected) bypass <= 1'b0;
    end else if (state == SHIFT_DR) begin
      if (ir == IR_IDCODE) idcode_shift <= {tdi, idcode_shift[31:1]};
      else if (!dtm_selected) bypass <= tdi;
    end
  end

  always @(negedge tck or negedge trst_n) begin
    if (!trst_n) tdo <= 1'b0;
    else if (state == SHIFT_IR) tdo <= ir_shift[0];
    else if (state == SHIFT_DR && ir == IR_IDCODE) tdo <= idcode_shift[0];
    else if (state == SHIFT_DR && dtm_selected) tdo <= dtm_tdo;
    else if (state == SHIFT_DR) tdo <= bypass;
    else tdo <= 1'b0;
  end

  jtag_dtm_cdc transport (
    .tck(tck), .trst_n(trst_n),
    .dr_capture(state == CAP_DR && dtm_selected),
    .dr_shift(state == SHIFT_DR && dtm_selected),
    .dr_update(state == UPDATE_DR && dtm_selected),
    .select_dmi(ir == IR_DMI), .tdi(tdi), .tdo(dtm_tdo),
    .req_toggle(req_toggle), .req_write(req_write), .req_addr(req_addr),
    .req_wdata(req_wdata), .ack_toggle(ack_toggle), .rsp_rdata(rsp_rdata),
    .rsp_error(rsp_error)
  );
endmodule

`default_nettype wire
