`default_nettype none

// 精简的单 hart PLIC. 中断源编号从 1 开始,编号 0 永远表示没有中断.
// 所有源先经过两级同步,再由 pending 锁存,所以 CPU 不会直接看到异步信号.
// 固定优先级是小编号优先. priority 和 threshold 目前只提供兼容读值,
// 后续增加可编程优先级时可以保留现有地址地图.
module plic #(
  parameter integer SOURCES = 16
) (
  input  wire               clk,
  input  wire               resetn,
  input  wire [SOURCES-1:0] irq_async,
  input  wire               sel_valid,
  input  wire [31:0]        mem_addr,
  input  wire [31:0]        mem_wdata,
  input  wire [3:0]         mem_wstrb,
  output wire               mem_ready,
  output reg  [31:0]        mem_rdata,
  output wire               meip
);
  // 标准 PLIC 偏移加一个自定义触发配置区. trigger=0 是电平,trigger=1 是上升沿.
  localparam [23:0] PENDING0 = 24'h001000;
  localparam [23:0] TRIGGER0 = 24'h001080;
  localparam [23:0] ENABLE0  = 24'h002000;
  localparam [23:0] THRESHOLD = 24'h200000;
  localparam [23:0] CLAIM     = 24'h200004;
  localparam integer ID_W = $clog2(SOURCES + 1);

  (* ASYNC_REG = "TRUE" *) reg [SOURCES-1:0] sync_meta;
  (* ASYNC_REG = "TRUE" *) reg [SOURCES-1:0] sync_level;
  reg [SOURCES-1:0] sync_prev;
  reg [SOURCES:1]   pending;
  reg [SOURCES:1]   enable;
  reg [SOURCES:1]   trigger_edge;
  reg [SOURCES:1]   in_service;

  reg [ID_W-1:0] claim_id;
  reg            claim_found;
  integer source;
  integer byte_index;

  wire claim_read = sel_valid && !(|mem_wstrb) && (mem_addr[23:0] == CLAIM);
  wire complete_write = sel_valid && (|mem_wstrb) &&
                        (mem_addr[23:0] == CLAIM) &&
                        (mem_wdata > 0) && (mem_wdata <= SOURCES);

  assign mem_ready = sel_valid;
  assign meip = |(pending & enable & ~in_service);

  // 所有固定优先级都等价为 1,同优先级按 PLIC 规则选最小 source ID.
  always @* begin
    claim_id = {ID_W{1'b0}};
    claim_found = 1'b0;
    for (source = 1; source <= SOURCES; source = source + 1) begin
      if (!claim_found && pending[source] && enable[source] && !in_service[source]) begin
        claim_id = source[ID_W-1:0];
        claim_found = 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    if (!resetn) begin
      sync_meta   <= {SOURCES{1'b0}};
      sync_level  <= {SOURCES{1'b0}};
      sync_prev   <= {SOURCES{1'b0}};
      pending     <= {SOURCES{1'b0}};
      enable      <= {SOURCES{1'b0}};
      trigger_edge <= {SOURCES{1'b0}};
      in_service  <= {SOURCES{1'b0}};
    end else begin
      sync_meta  <= irq_async;
      sync_level <= sync_meta;
      sync_prev  <= sync_level;

      // 电平源在未处理时跟踪同步后的有效电平. 边沿源只置位不自动清除,
      // 因而同步器看到的一拍脉冲也会一直保留到 claim.
      for (source = 1; source <= SOURCES; source = source + 1) begin
        if (!in_service[source]) begin
          if (trigger_edge[source]) begin
            if (sync_level[source-1] && !sync_prev[source-1])
              pending[source] <= 1'b1;
          end else begin
            pending[source] <= sync_level[source-1];
          end
        end
      end

      // enable 和 trigger 使用 PLIC 的 source ID 位布局,bit 0 保留.
      if (sel_valid && (|mem_wstrb)) begin
        for (source = 1; source <= SOURCES; source = source + 1) begin
          for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
            if ((mem_addr[23:0] == (ENABLE0 + ((source / 32) * 4))) &&
                (source % 32 >= byte_index * 8) &&
                (source % 32 < (byte_index + 1) * 8) && mem_wstrb[byte_index])
              enable[source] <= mem_wdata[source % 32];
            if ((mem_addr[23:0] == (TRIGGER0 + ((source / 32) * 4))) &&
                (source % 32 >= byte_index * 8) &&
                (source % 32 < (byte_index + 1) * 8) && mem_wstrb[byte_index])
              trigger_edge[source] <= mem_wdata[source % 32];
          end
        end
      end

      if (claim_read && claim_found) begin
        pending[claim_id] <= 1'b0;
        in_service[claim_id] <= 1'b1;
      end

      // complete 只接受当前正在处理的合法 ID. 电平仍有效时会重新 pending.
      if (complete_write && in_service[mem_wdata[ID_W-1:0]]) begin
        in_service[mem_wdata[ID_W-1:0]] <= 1'b0;
        if (!trigger_edge[mem_wdata[ID_W-1:0]])
          pending[mem_wdata[ID_W-1:0]] <= sync_level[mem_wdata[ID_W-1:0]-1'b1];
      end
    end
  end

  always @* begin
    mem_rdata = 32'd0;

    // priority 寄存器先固定读 1,写入会被忽略.
    for (source = 1; source <= SOURCES; source = source + 1) begin
      if (mem_addr[23:0] == source * 4)
        mem_rdata = 32'd1;
      if (mem_addr[23:0] == (PENDING0 + ((source / 32) * 4)))
        mem_rdata[source % 32] = pending[source];
      if (mem_addr[23:0] == (ENABLE0 + ((source / 32) * 4)))
        mem_rdata[source % 32] = enable[source];
      if (mem_addr[23:0] == (TRIGGER0 + ((source / 32) * 4)))
        mem_rdata[source % 32] = trigger_edge[source];
    end

    if (mem_addr[23:0] == THRESHOLD)
      mem_rdata = 32'd0;
    if (mem_addr[23:0] == CLAIM)
      mem_rdata = {{(32-ID_W){1'b0}}, claim_id};
  end
endmodule

`default_nettype wire
