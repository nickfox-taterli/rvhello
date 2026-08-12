`default_nettype none

// 单 hart,单 context 的标准 PLIC.中断源编号从 1 开始,编号 0 永远保留.
// priority,pending,enable,threshold 和 claim/complete 使用规范地址布局.
// 所有外部源先做两级同步,再交给 gateway 锁存请求.
module plic #(
  parameter integer SOURCES = 16,
  parameter integer PRIORITY_BITS = 3
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
  output reg                meip
);
  function integer ceil_pow2;
    input integer value;
    integer result;
    begin
      result = 1;
      while (result < value)
        result = result * 2;
      ceil_pow2 = result;
    end
  endfunction

  localparam [23:0] PENDING0 = 24'h001000;
  // 这是平台扩展.trigger=0 表示高电平触发,trigger=1 表示上升沿触发.
  localparam [23:0] TRIGGER0 = 24'h001080;
  localparam [23:0] ENABLE0 = 24'h002000;
  localparam [23:0] THRESHOLD = 24'h200000;
  localparam [23:0] CLAIM = 24'h200004;
  localparam integer ID_W = $clog2(SOURCES + 1);
  localparam integer ARB_LEAVES = ceil_pow2(SOURCES);

  (* ASYNC_REG = "TRUE" *) reg [SOURCES-1:0] sync_meta;
  (* ASYNC_REG = "TRUE" *) reg [SOURCES-1:0] sync_level;
  reg [SOURCES-1:0] sync_prev;

  reg [PRIORITY_BITS-1:0] source_priority [1:SOURCES];
  reg [PRIORITY_BITS-1:0] threshold;
  reg [SOURCES:1] pending;
  reg [SOURCES:1] enable;
  reg [SOURCES:1] trigger_edge;
  reg [SOURCES:1] in_service;

  integer source;
  integer byte_index;
  integer priority_bit;

  wire claim_read = sel_valid && !(|mem_wstrb) &&
                    (mem_addr[23:0] == CLAIM);
  wire complete_write = sel_valid && (|mem_wstrb) &&
                        (mem_addr[23:0] == CLAIM) &&
                        (mem_wdata > 32'd0) && (mem_wdata <= SOURCES);

  assign mem_ready = sel_valid;

  // 平衡 tournament tree 只选严格高于 threshold 的最高优先级.
  // 左子树始终包含更小 ID,所以同级时选择左边就符合规范.
  wire [ID_W-1:0] arb_id [1:(2 * ARB_LEAVES)-1];
  wire [PRIORITY_BITS-1:0] arb_priority [1:(2 * ARB_LEAVES)-1];
  wire arb_valid [1:(2 * ARB_LEAVES)-1];
  genvar leaf;
  generate
    for (leaf = 0; leaf < ARB_LEAVES; leaf = leaf + 1) begin : gen_arb_leaf
      if (leaf < SOURCES) begin : gen_source
        localparam integer SOURCE_ID = leaf + 1;
        assign arb_id[ARB_LEAVES + leaf] = SOURCE_ID;
        assign arb_priority[ARB_LEAVES + leaf] = source_priority[SOURCE_ID];
        assign arb_valid[ARB_LEAVES + leaf] = pending[SOURCE_ID] &&
              enable[SOURCE_ID] && !in_service[SOURCE_ID] &&
              (source_priority[SOURCE_ID] > threshold);
      end else begin : gen_padding
        assign arb_id[ARB_LEAVES + leaf] = {ID_W{1'b0}};
        assign arb_priority[ARB_LEAVES + leaf] = {PRIORITY_BITS{1'b0}};
        assign arb_valid[ARB_LEAVES + leaf] = 1'b0;
      end
    end
  endgenerate

  genvar node;
  generate
    for (node = 1; node < ARB_LEAVES; node = node + 1) begin : gen_arb_node
      wire choose_right = arb_valid[(2 * node) + 1] &&
            (!arb_valid[2 * node] ||
             (arb_priority[(2 * node) + 1] > arb_priority[2 * node]));
      assign arb_id[node] = choose_right ? arb_id[(2 * node) + 1] :
                                         arb_id[2 * node];
      assign arb_priority[node] = choose_right ? arb_priority[(2 * node) + 1] :
                                               arb_priority[2 * node];
      assign arb_valid[node] = arb_valid[2 * node] || arb_valid[(2 * node) + 1];
    end
  endgenerate

  wire claim_found = arb_valid[1];
  wire [ID_W-1:0] claim_id = claim_found ? arb_id[1] : {ID_W{1'b0}};

  always @(posedge clk) begin
    if (!resetn) begin
      sync_meta <= {SOURCES{1'b0}};
      sync_level <= {SOURCES{1'b0}};
      sync_prev <= {SOURCES{1'b0}};
      meip <= 1'b0;
      threshold <= {PRIORITY_BITS{1'b0}};
      pending <= {SOURCES{1'b0}};
      enable <= {SOURCES{1'b0}};
      trigger_edge <= {SOURCES{1'b0}};
      in_service <= {SOURCES{1'b0}};
      for (source = 1; source <= SOURCES; source = source + 1)
        source_priority[source] <= {PRIORITY_BITS{1'b0}};
    end else begin
      sync_meta <= irq_async;
      sync_level <= sync_meta;
      sync_prev <= sync_level;
      // 规范允许通知相对 PLIC 内部状态有有限延迟.注册一拍可以切断仲裁比较树.
      meip <= claim_found;

      // Gateway 一旦转发请求就保持 pending 到 claim.同一源完成前不再转发.
      for (source = 1; source <= SOURCES; source = source + 1) begin
        if (!in_service[source]) begin
          if (trigger_edge[source]) begin
            if (sync_level[source-1] && !sync_prev[source-1])
              pending[source] <= 1'b1;
          end else if (sync_level[source-1]) begin
            pending[source] <= 1'b1;
          end
        end
      end

      if (sel_valid && (|mem_wstrb)) begin
        // priority 和 threshold 是 WARL,未实现的高位固定为 0.
        for (source = 1; source <= SOURCES; source = source + 1) begin
          if (mem_addr[23:0] == source * 4) begin
            for (priority_bit = 0; priority_bit < PRIORITY_BITS;
                 priority_bit = priority_bit + 1) begin
              if (mem_wstrb[priority_bit / 8])
                source_priority[source][priority_bit] <= mem_wdata[priority_bit];
            end
          end

          // enable 和 trigger 按 source ID 排列,所以 bit 0 永远是保留位.
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

        if (mem_addr[23:0] == THRESHOLD) begin
          for (priority_bit = 0; priority_bit < PRIORITY_BITS;
               priority_bit = priority_bit + 1) begin
            if (mem_wstrb[priority_bit / 8])
              threshold[priority_bit] <= mem_wdata[priority_bit];
          end
        end
      end

      // claim 读是原子的.返回 ID 的同时清 pending 并关闭对应 gateway.
      if (claim_read && claim_found) begin
        pending[claim_id] <= 1'b0;
        in_service[claim_id] <= 1'b1;
      end

      // complete 只对这个 context 已经 claim 的合法 ID 生效.
      if (complete_write && in_service[mem_wdata[ID_W-1:0]]) begin
        in_service[mem_wdata[ID_W-1:0]] <= 1'b0;
        if (!trigger_edge[mem_wdata[ID_W-1:0]] &&
            sync_level[mem_wdata[ID_W-1:0]-1'b1])
          pending[mem_wdata[ID_W-1:0]] <= 1'b1;
      end
    end
  end

  always @* begin
    mem_rdata = 32'd0;

    for (source = 1; source <= SOURCES; source = source + 1) begin
      if (mem_addr[23:0] == source * 4)
        mem_rdata[PRIORITY_BITS-1:0] = source_priority[source];
      if (mem_addr[23:0] == (PENDING0 + ((source / 32) * 4)))
        mem_rdata[source % 32] = pending[source];
      if (mem_addr[23:0] == (ENABLE0 + ((source / 32) * 4)))
        mem_rdata[source % 32] = enable[source];
      if (mem_addr[23:0] == (TRIGGER0 + ((source / 32) * 4)))
        mem_rdata[source % 32] = trigger_edge[source];
    end

    if (mem_addr[23:0] == THRESHOLD)
      mem_rdata[PRIORITY_BITS-1:0] = threshold;
    if (mem_addr[23:0] == CLAIM)
      mem_rdata[ID_W-1:0] = claim_id;
  end
endmodule

`default_nettype wire
