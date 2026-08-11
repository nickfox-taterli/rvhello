`default_nettype none

// 单 hart 的 RISC-V Debug Module 0.13. 支持 abstract register 和 32 位 SBA.
module riscv_debug_dm (
  input  wire        clk,
  input  wire        resetn,

  input  wire [1:0]  req_toggle,
  input  wire [1:0]  req_write,
  input  wire [13:0] req_addr,
  input  wire [63:0] req_wdata,
  output reg  [1:0]  ack_toggle,
  output reg  [63:0] rsp_rdata,
  output reg  [1:0]  rsp_error,

  output wire        hart_halt_req,
  output reg         hart_resume_req,
  input  wire        hart_halted,
  output wire        ndmreset,

  output wire        hart_reg_valid,
  output wire        hart_reg_write,
  output wire [15:0] hart_reg_addr,
  output wire [31:0] hart_reg_wdata,
  input  wire [31:0] hart_reg_rdata,
  input  wire        hart_reg_ready,
  input  wire        hart_reg_error,

  output reg         sb_valid,
  output reg  [31:0] sb_addr,
  output reg  [31:0] sb_wdata,
  output reg  [3:0]  sb_wstrb,
  input  wire        sb_ready,
  input  wire [31:0] sb_rdata
);
  localparam [6:0] A_DATA0=7'h04, A_DMCONTROL=7'h10, A_DMSTATUS=7'h11,
                   A_HARTINFO=7'h12, A_ABSTRACTCS=7'h16, A_COMMAND=7'h17,
                   A_ABSTRACTAUTO=7'h18, A_SBCS=7'h38, A_SBADDRESS0=7'h39,
                   A_SBDATA0=7'h3c, A_HALTSUM0=7'h40;

  reg [1:0] req_sync1;
  reg [1:0] req_sync2;
  reg       select_port;
  wire pending_selected = req_sync2[select_port] != ack_toggle[select_port];
  wire chosen_port = pending_selected ? select_port : ~select_port;
  wire [6:0] chosen_addr = req_addr[chosen_port*7 +: 7];
  wire [31:0] chosen_wdata = req_wdata[chosen_port*32 +: 32];
  wire chosen_write = req_write[chosen_port];

  reg dmactive;
  reg haltreq;
  reg ndmreset_reg;
  reg resumeack;
  reg havereset;
  assign hart_halt_req = haltreq;
  assign ndmreset = ndmreset_reg;

  reg [31:0] data0;
  reg [31:0] command;
  reg        autoexec_data0;
  reg        abstract_busy;
  reg [2:0]  abstract_cmderr;

  assign hart_reg_valid = abstract_busy;
  assign hart_reg_write = command[16];
  assign hart_reg_addr  = command[15:0];
  assign hart_reg_wdata = data0;

  reg        sbreadonaddr;
  reg        sbautoincrement;
  reg        sbreadondata;
  reg [2:0]  sbaccess;
  reg [2:0]  sberror;
  reg        sbbusyerror;
  reg [31:0] sbdata;
  wire [31:0] sbcs_value = {
    3'd1, 6'd0, sbbusyerror, sb_valid, sbreadonaddr, sbaccess,
    sbautoincrement, sbreadondata, sberror, 7'd32, 5'b00111
  };

  function [31:0] dmi_rdata;
    input [6:0] addr;
    begin
      case (addr)
        A_DATA0: dmi_rdata = data0;
        A_DMCONTROL: dmi_rdata = {31'd0, dmactive};
        A_DMSTATUS: dmi_rdata = {
          9'd0, 1'b1, 2'd0, havereset, havereset, resumeack, resumeack,
          2'b00, 2'b00, !hart_halted, !hart_halted, hart_halted, hart_halted,
          1'b1, 1'b0, 1'b1, 1'b0, 4'd2
        };
        A_HARTINFO: dmi_rdata = {8'd0, 4'd0, 3'd0, 1'b0, 4'd1, 12'hbff};
        A_ABSTRACTCS: dmi_rdata = {3'd0, 5'd0, 11'd0, abstract_busy, 1'b0,
                                    abstract_cmderr, 4'd0, 4'd1};
        A_COMMAND: dmi_rdata = 32'd0;
        A_ABSTRACTAUTO: dmi_rdata = {31'd0, autoexec_data0};
        A_SBCS: dmi_rdata = sbcs_value;
        A_SBADDRESS0: dmi_rdata = sb_addr;
        A_SBDATA0: dmi_rdata = sbdata;
        A_HALTSUM0: dmi_rdata = {31'd0, hart_halted};
        default: dmi_rdata = 32'd0;
      endcase
    end
  endfunction

  task start_abstract;
    input [31:0] next_command;
    begin
      command <= next_command;
      if (next_command[31:24] != 8'd0 || next_command[22:20] != 3'd2 ||
          next_command[19] || next_command[18]) begin
        abstract_cmderr <= 3'd2;
      end else if (!hart_halted) begin
        abstract_cmderr <= 3'd4;
      end else if (next_command[17]) begin
        abstract_busy <= 1'b1;
      end
    end
  endtask

  task start_sba;
    input do_write;
    input [31:0] write_data;
    reg bad_align;
    begin
      bad_align = (sbaccess == 3'd1 && sb_addr[0]) ||
                  (sbaccess == 3'd2 && |sb_addr[1:0]);
      if (sbaccess > 3'd2)
        sberror <= 3'd4;
      else if (bad_align)
        sberror <= 3'd3;
      else if (!hart_halted)
        sberror <= 3'd2;
      else begin
        sb_valid <= 1'b1;
        if (do_write) begin
          case (sbaccess)
            3'd0: begin sb_wstrb <= 4'b0001 << sb_addr[1:0]; sb_wdata <= {4{write_data[7:0]}}; end
            3'd1: begin sb_wstrb <= sb_addr[1] ? 4'b1100 : 4'b0011; sb_wdata <= {2{write_data[15:0]}}; end
            default: begin sb_wstrb <= 4'b1111; sb_wdata <= write_data; end
          endcase
        end else begin
          sb_wstrb <= 4'b0000;
          sb_wdata <= 32'd0;
        end
      end
    end
  endtask

  always @(posedge clk) begin
    if (!resetn) begin
      req_sync1 <= 2'b00;
      req_sync2 <= 2'b00;
      ack_toggle <= 2'b00;
      rsp_rdata <= 64'd0;
      rsp_error <= 2'b00;
      select_port <= 1'b0;
      dmactive <= 1'b0;
      haltreq <= 1'b0;
      ndmreset_reg <= 1'b0;
      hart_resume_req <= 1'b0;
      resumeack <= 1'b0;
      havereset <= 1'b1;
      data0 <= 32'd0;
      command <= 32'd0;
      autoexec_data0 <= 1'b0;
      abstract_busy <= 1'b0;
      abstract_cmderr <= 3'd0;
      sbreadonaddr <= 1'b0;
      sbautoincrement <= 1'b0;
      sbreadondata <= 1'b0;
      sbaccess <= 3'd2;
      sberror <= 3'd0;
      sbbusyerror <= 1'b0;
      sbdata <= 32'd0;
      sb_valid <= 1'b0;
      sb_addr <= 32'd0;
      sb_wdata <= 32'd0;
      sb_wstrb <= 4'd0;
    end else begin
      req_sync1 <= req_toggle;
      req_sync2 <= req_sync1;
      hart_resume_req <= 1'b0;

      if (abstract_busy && hart_reg_ready) begin
        abstract_busy <= 1'b0;
        if (hart_reg_error)
          abstract_cmderr <= 3'd3;
        else if (!command[16])
          data0 <= hart_reg_rdata;
      end

      if (sb_valid && sb_ready) begin
        sb_valid <= 1'b0;
        if (sb_wstrb == 4'b0000) begin
          case (sbaccess)
            3'd0: begin
              case (sb_addr[1:0])
                2'd0: sbdata <= {24'd0, sb_rdata[7:0]};
                2'd1: sbdata <= {24'd0, sb_rdata[15:8]};
                2'd2: sbdata <= {24'd0, sb_rdata[23:16]};
                default: sbdata <= {24'd0, sb_rdata[31:24]};
              endcase
            end
            3'd1: sbdata <= sb_addr[1] ? {16'd0, sb_rdata[31:16]} : {16'd0, sb_rdata[15:0]};
            default: sbdata <= sb_rdata;
          endcase
        end
        if (sbautoincrement)
          sb_addr <= sb_addr + (sbaccess == 3'd0 ? 32'd1 : sbaccess == 3'd1 ? 32'd2 : 32'd4);
      end

      if ((req_sync2[0] != ack_toggle[0]) || (req_sync2[1] != ack_toggle[1])) begin
        rsp_rdata[chosen_port*32 +: 32] <= dmi_rdata(chosen_addr);
        rsp_error[chosen_port] <= 1'b0;

        if (chosen_write) begin
          case (chosen_addr)
            A_DATA0: begin
              if (abstract_busy) abstract_cmderr <= 3'd1;
              else begin
                data0 <= chosen_wdata;
                if (autoexec_data0 && abstract_cmderr == 3'd0)
                  start_abstract(command);
              end
            end
            A_DMCONTROL: begin
              dmactive <= chosen_wdata[0];
              if (!chosen_wdata[0]) begin
                haltreq <= 1'b0;
                ndmreset_reg <= 1'b0;
                abstract_busy <= 1'b0;
                abstract_cmderr <= 3'd0;
              end else begin
                ndmreset_reg <= chosen_wdata[1];
                haltreq <= chosen_wdata[31];
                if (chosen_wdata[30] && !chosen_wdata[31]) begin
                  hart_resume_req <= 1'b1;
                  resumeack <= 1'b1;
                end else if (!chosen_wdata[30]) begin
                  resumeack <= 1'b0;
                end
                if (chosen_wdata[28]) havereset <= 1'b0;
              end
            end
            A_ABSTRACTCS: if (!abstract_busy)
              abstract_cmderr <= abstract_cmderr & ~chosen_wdata[10:8];
            A_COMMAND: begin
              if (abstract_busy) abstract_cmderr <= 3'd1;
              else if (abstract_cmderr == 3'd0) start_abstract(chosen_wdata);
            end
            A_ABSTRACTAUTO: if (!abstract_busy) autoexec_data0 <= chosen_wdata[0];
            A_SBCS: begin
              sbbusyerror <= sbbusyerror && !chosen_wdata[22];
              sbreadonaddr <= chosen_wdata[20];
              sbaccess <= chosen_wdata[19:17];
              sbautoincrement <= chosen_wdata[16];
              sbreadondata <= chosen_wdata[15];
              sberror <= sberror & ~chosen_wdata[14:12];
            end
            A_SBADDRESS0: begin
              if (sb_valid) sbbusyerror <= 1'b1;
              else begin
                sb_addr <= chosen_wdata;
                if (sbreadonaddr && !(|sberror) && !sbbusyerror)
                  start_sba(1'b0, 32'd0);
              end
            end
            A_SBDATA0: begin
              if (sb_valid) sbbusyerror <= 1'b1;
              else if (!(|sberror) && !sbbusyerror) begin
                sbdata <= chosen_wdata;
                start_sba(1'b1, chosen_wdata);
              end
            end
            default: begin end
          endcase
        end else begin
          if (chosen_addr == A_DATA0 && autoexec_data0 && !abstract_busy && abstract_cmderr == 3'd0)
            start_abstract(command);
          if (chosen_addr == A_SBDATA0 && sbreadondata && !sb_valid && !(|sberror) && !sbbusyerror)
            start_sba(1'b0, 32'd0);
          if ((chosen_addr == A_SBDATA0 || chosen_addr == A_SBADDRESS0) && sb_valid)
            sbbusyerror <= 1'b1;
        end

        ack_toggle[chosen_port] <= req_sync2[chosen_port];
        select_port <= ~chosen_port;
      end
    end
  end
endmodule

`default_nettype wire
