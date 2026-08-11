`default_nettype none

// 第一阶段 DMI 端点. 只验证传输和 CDC,命令寄存器不会控制 hart.
module debug_dmi_regs (
  input  wire        clk,
  input  wire        resetn,
  input  wire [31:0] hart_pc,
  input  wire        hart_halted,

  input  wire [1:0]  req_toggle,
  input  wire [1:0]  req_write,
  input  wire [13:0] req_addr,
  input  wire [63:0] req_wdata,
  output reg  [1:0]  ack_toggle,
  output reg  [63:0] rsp_rdata,
  output reg  [1:0]  rsp_error
);
  reg [1:0] req_sync1;
  reg [1:0] req_sync2;
  reg [31:0] scratch;
  reg [31:0] command_shadow;
  reg        select_port;
  wire       pending_selected = req_sync2[select_port] != ack_toggle[select_port];
  wire       chosen_port = pending_selected ? select_port : ~select_port;
  wire [6:0] chosen_addr = req_addr[chosen_port*7 +: 7];
  wire [31:0] chosen_wdata = req_wdata[chosen_port*32 +: 32];
  wire chosen_write = req_write[chosen_port];

  always @(posedge clk) begin
    if (!resetn) begin
      req_sync1     <= 2'b00;
      req_sync2     <= 2'b00;
      ack_toggle    <= 2'b00;
      rsp_rdata     <= 64'd0;
      rsp_error     <= 2'b00;
      scratch       <= 32'd0;
      command_shadow <= 32'd0;
      select_port   <= 1'b0;
    end else begin
      req_sync1 <= req_toggle;
      req_sync2 <= req_sync1;

      // 两个端口同拍请求时轮流优先,避免其中一个持续挨饿.
      if ((req_sync2[select_port] != ack_toggle[select_port]) ||
          (req_sync2[~select_port] != ack_toggle[~select_port])) begin
        rsp_error[chosen_port] <= 1'b0;

        case (chosen_addr)
          7'h70: begin
            rsp_rdata[chosen_port*32 +: 32] <= 32'h5256_4831; // "RVH1"
            if (chosen_write) rsp_error[chosen_port] <= 1'b1;
          end
          7'h71: begin
            if (chosen_write) scratch <= chosen_wdata;
            rsp_rdata[chosen_port*32 +: 32] <= chosen_write ? chosen_wdata : scratch;
          end
          7'h72: begin
            rsp_rdata[chosen_port*32 +: 32] <= hart_pc;
            if (chosen_write) rsp_error[chosen_port] <= 1'b1;
          end
          7'h73: begin
            rsp_rdata[chosen_port*32 +: 32] <= {31'd0, hart_halted};
            if (chosen_write) rsp_error[chosen_port] <= 1'b1;
          end
          7'h74: begin
            if (chosen_write) command_shadow <= chosen_wdata;
            rsp_rdata[chosen_port*32 +: 32] <= chosen_write ? chosen_wdata : command_shadow;
          end
          default: begin
            rsp_rdata[chosen_port*32 +: 32] <= 32'd0;
            rsp_error[chosen_port] <= 1'b1;
          end
        endcase
        ack_toggle[chosen_port] <= req_sync2[chosen_port];
        select_port <= ~chosen_port;
      end
    end
  end
endmodule

`default_nettype wire
