`default_nettype none

// 板载异步 SRAM 控制器. 两片 ISSI 61/64WV25616 组成 256K x 32:
// DQ[15:0] 是 sram0, DQ[31:16] 是 sram1, A[18:0] 共用.
// 固定 100MHz 时钟. 一笔读在 OE 有效后额外保持一拍, 保证 20ns 读访问窗口.
// 不做突发或缓存.
module sram_async (
  input  wire        clk,
  input  wire        resetn,
  input  wire        mem_valid,
  input  wire [31:0] mem_addr,
  input  wire [31:0] mem_wdata,
  input  wire [3:0]  mem_wstrb,
  output wire        mem_ready,
  output reg  [31:0] mem_rdata,

  output wire [18:0] sram_addr,
  inout  wire [31:0] sram_dq,
  output wire        sram0_ce_n,
  output wire        sram1_ce_n,
  output wire        sram0_oe_n,
  output wire        sram1_oe_n,
  output wire        sram0_we_n,
  output wire        sram1_we_n,
  output wire        sram0_lb_n,
  output wire        sram0_ub_n,
  output wire        sram1_lb_n,
  output wire        sram1_ub_n
);
  localparam [2:0] S_IDLE   = 3'd0;
  localparam [2:0] S_SETUP  = 3'd1;
  localparam [2:0] S_STROBE = 3'd2;
  localparam [2:0] S_HOLD   = 3'd3;
  localparam [2:0] S_SAMPLE = 3'd4;

  reg [2:0]  state;
  reg        active;
  reg        write_r;
  reg        oe_n_r;
  reg        we_n_r;
  reg        dq_drive_r;
  reg [3:0]  be_r;
  reg [18:0] addr_r;
  reg [31:0] data_r;

  wire cs0 = be_r[0] | be_r[1];
  wire cs1 = be_r[2] | be_r[3];

  // ready 仅在 SAMPLE 产生一个应答拍, 主端 valid 必须全程保持请求不变.
  assign mem_ready = (state == S_SAMPLE);
  assign sram_addr = addr_r;
  assign sram_dq = dq_drive_r ? data_r : 32'bz;
  assign sram0_ce_n = ~(active & cs0);
  assign sram1_ce_n = ~(active & cs1);
  assign sram0_oe_n = ~(~oe_n_r & cs0);
  assign sram1_oe_n = ~(~oe_n_r & cs1);
  assign sram0_we_n = ~(~we_n_r & cs0);
  assign sram1_we_n = ~(~we_n_r & cs1);
  assign sram0_lb_n = ~(be_r[0] & cs0);
  assign sram0_ub_n = ~(be_r[1] & cs0);
  assign sram1_lb_n = ~(be_r[2] & cs1);
  assign sram1_ub_n = ~(be_r[3] & cs1);

  always @(posedge clk) begin
    if (!resetn) begin
      state      <= S_IDLE;
      active     <= 1'b0;
      write_r    <= 1'b0;
      oe_n_r     <= 1'b1;
      we_n_r     <= 1'b1;
      dq_drive_r <= 1'b0;
      be_r       <= 4'd0;
      addr_r     <= 19'd0;
      data_r     <= 32'd0;
      mem_rdata  <= 32'd0;
    end else begin
      case (state)
        S_IDLE: if (mem_valid) begin
          // 地址按字节给入总线, SRAM 管脚是字地址, 因此丢掉低 2 位.
          addr_r     <= mem_addr[20:2];
          data_r     <= mem_wdata;
          // 总线读的 wstrb 为 0, 但外部 SRAM 读必须同时选中四个字节.
          be_r       <= (|mem_wstrb) ? mem_wstrb : 4'b1111;
          write_r    <= |mem_wstrb;
          dq_drive_r <= |mem_wstrb;
          active     <= 1'b1;
          oe_n_r     <= 1'b1;
          we_n_r     <= 1'b1;
          state      <= S_SETUP;
        end

        S_SETUP: begin
          if (write_r) we_n_r <= 1'b0;
          else oe_n_r <= 1'b0;
          state <= S_STROBE;
        end

        S_STROBE: begin
          // 保持读写选通信号一个完整 10ns 周期.
          state <= S_HOLD;
        end

        S_HOLD: begin
          // OE 从 S_SETUP 拉低至此已有 20ns, 再采样读数据.
          we_n_r <= 1'b1;
          oe_n_r <= 1'b1;
          if (!write_r) mem_rdata <= sram_dq;
          state <= S_SAMPLE;
        end

        S_SAMPLE: begin
          // 写数据额外保持一拍后释放, 同时向主端应答.
          dq_drive_r <= 1'b0;
          active <= 1'b0;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end
endmodule

`default_nettype wire
