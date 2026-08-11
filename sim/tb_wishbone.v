`timescale 1ns / 1ps
`default_nettype none

module tb_wishbone;
  reg clk = 1'b0;
  reg resetn = 1'b0;
  always #5 clk = ~clk;

  reg         v0 = 1'b0;
  reg         i0 = 1'b0;
  reg  [31:0] a0 = 32'd0;
  reg  [31:0] d0 = 32'd0;
  reg  [3:0]  b0 = 4'd0;
  wire        r0;
  wire        e0;
  wire [31:0] q0;
  reg         v1 = 1'b0;
  reg  [31:0] a1 = 32'd0;
  reg  [31:0] d1 = 32'd0;
  reg  [3:0]  b1 = 4'd0;
  wire        r1;
  wire        e1;
  wire [31:0] q1;

  wire c0, s0, w0, t0, k0, x0;
  wire [31:0] wa0, wd0, rd0;
  wire [3:0]  bs0;
  wire c1, s1, w1, t1, k1, x1;
  wire [31:0] wa1, wd1, rd1;
  wire [3:0]  bs1;
  reg c2 = 1'b0;
  reg s2 = 1'b0;
  reg w2 = 1'b0;
  reg t2 = 1'b0;
  reg [31:0] wa2 = 32'd0;
  reg [31:0] wd2 = 32'd0;
  reg [3:0] bs2 = 4'd0;
  wire k2, x2;
  wire [31:0] rd2;
  wire bc, bstb, bwe, btga, back, berr;
  wire [31:0] badr, bwd, brd;
  wire [3:0]  bsel;
  wire mv, mi, mr, me;
  wire [31:0] ma, mw, mq;
  wire [3:0]  mb;

  simple_to_wb adapter0 (
    .clk(clk), .resetn(resetn), .s_valid(v0), .s_instr(i0),
    .s_addr(a0), .s_wdata(d0), .s_wstrb(b0),
    .s_ready(r0), .s_error(e0), .s_rdata(q0),
    .wb_cyc(c0), .wb_stb(s0), .wb_we(w0), .wb_adr(wa0),
    .wb_dat_w(wd0), .wb_sel(bs0), .wb_tga_instr(t0),
    .wb_ack(k0), .wb_err(x0), .wb_dat_r(rd0)
  );

  simple_to_wb adapter1 (
    .clk(clk), .resetn(resetn), .s_valid(v1), .s_instr(1'b0),
    .s_addr(a1), .s_wdata(d1), .s_wstrb(b1),
    .s_ready(r1), .s_error(e1), .s_rdata(q1),
    .wb_cyc(c1), .wb_stb(s1), .wb_we(w1), .wb_adr(wa1),
    .wb_dat_w(wd1), .wb_sel(bs1), .wb_tga_instr(t1),
    .wb_ack(k1), .wb_err(x1), .wb_dat_r(rd1)
  );

  wb_arbiter #(
    .MASTERS(3)
  ) arbiter (
    .clk(clk), .resetn(resetn),
    .m_cyc({c2, c1, c0}), .m_stb({s2, s1, s0}), .m_we({w2, w1, w0}),
    .m_adr({wa2, wa1, wa0}), .m_dat_w({wd2, wd1, wd0}),
    .m_sel({bs2, bs1, bs0}), .m_tga_instr({t2, t1, t0}),
    .m_ack({k2, k1, k0}), .m_err({x2, x1, x0}),
    .m_dat_r({rd2, rd1, rd0}),
    .s_cyc(bc), .s_stb(bstb), .s_we(bwe), .s_adr(badr),
    .s_dat_w(bwd), .s_sel(bsel), .s_tga_instr(btga),
    .s_ack(back), .s_err(berr), .s_dat_r(brd)
  );

  wb_to_simple bridge (
    .wb_cyc(bc), .wb_stb(bstb), .wb_we(bwe), .wb_adr(badr),
    .wb_dat_w(bwd), .wb_sel(bsel), .wb_tga_instr(btga),
    .wb_ack(back), .wb_err(berr), .wb_dat_r(brd),
    .m_valid(mv), .m_instr(mi), .m_addr(ma), .m_wdata(mw),
    .m_wstrb(mb), .m_ready(mr), .m_error(me), .m_rdata(mq)
  );

  reg        slave_busy = 1'b0;
  reg [1:0]  slave_wait = 2'd0;
  reg [31:0] slave_addr = 32'd0;
  reg [31:0] slave_data = 32'd0;
  reg [3:0]  slave_strb = 4'd0;
  reg        slave_instr = 1'b0;
  reg [31:0] accepted_addr [0:7];
  reg [3:0]  accepted_strb [0:7];
  reg        accepted_instr [0:7];
  integer accepted_count = 0;

  assign mr = slave_busy && (slave_wait == 0);
  assign me = mr && (slave_addr == 32'hdead_0000);
  assign mq = slave_addr ^ 32'ha5a5_5a5a;

  always @(posedge clk) begin
    if (!resetn) begin
      slave_busy    <= 1'b0;
      slave_wait    <= 2'd0;
      accepted_count <= 0;
    end else if (!slave_busy && mv) begin
      slave_busy    <= 1'b1;
      slave_wait    <= 2'd2;
      slave_addr    <= ma;
      slave_data    <= mw;
      slave_strb    <= mb;
      slave_instr   <= mi;
      accepted_addr[accepted_count] <= ma;
      accepted_strb[accepted_count] <= mb;
      accepted_instr[accepted_count] <= mi;
      accepted_count <= accepted_count + 1;
    end else if (slave_busy && slave_wait != 0) begin
      slave_wait <= slave_wait - 1'b1;
    end else if (mr) begin
      slave_busy <= 1'b0;
    end
  end

  task automatic issue0;
    input [31:0] addr;
    input        instr;
    input [3:0]  strb;
    input        expect_error;
    begin
      @(negedge clk);
      a0 = addr; d0 = 32'h1122_3344; b0 = strb; i0 = instr; v0 = 1'b1;
      do @(posedge clk); while (!r0);
      if (e0 !== expect_error) $fatal(1, "M0 error 路由错误 addr=%08x", addr);
      if (!expect_error && q0 !== (addr ^ 32'ha5a5_5a5a))
        $fatal(1, "M0 读数据错误 addr=%08x data=%08x", addr, q0);
      @(negedge clk);
      v0 = 1'b0;
    end
  endtask

  task automatic issue1;
    input [31:0] addr;
    input [3:0]  strb;
    begin
      @(negedge clk);
      a1 = addr; d1 = 32'h5566_7788; b1 = strb; v1 = 1'b1;
      do @(posedge clk); while (!r1);
      if (e1) $fatal(1, "M1 意外收到 error addr=%08x", addr);
      @(negedge clk);
      v1 = 1'b0;
    end
  endtask

  task automatic issue2;
    input [31:0] addr;
    begin
      @(negedge clk);
      wa2 = addr; wd2 = 32'h99aa_bbcc; bs2 = 4'b1111;
      w2 = 1'b1; t2 = 1'b0; c2 = 1'b1; s2 = 1'b1;
      do @(posedge clk); while (!k2);
      if (x2) $fatal(1, "M2 意外收到 error addr=%08x", addr);
      @(negedge clk);
      c2 = 1'b0; s2 = 1'b0;
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    resetn <= 1'b1;

    // M0 已经拿到总线后 M1 才请求,检查高优先级主端不能抢占在途事务.
    fork
      issue0(32'h0000_0010, 1'b1, 4'b0000, 1'b0);
      begin
        wait (mv && ma == 32'h0000_0010);
        issue1(32'h1000_0020, 4'b0011);
      end
    join
    if (accepted_addr[0] !== 32'h0000_0010 || accepted_addr[1] !== 32'h1000_0020)
      $fatal(1, "在途事务被抢占: %08x %08x", accepted_addr[0], accepted_addr[1]);
    if (accepted_strb[0] !== 4'b0000 || accepted_instr[0] !== 1'b1)
      $fatal(1, "读请求的 strobe 或取指标记错误");
    if (accepted_strb[1] !== 4'b0011 || accepted_instr[1] !== 1'b0)
      $fatal(1, "写请求的 strobe 或取指标记错误");

    // 同拍请求时 M1 优先,完成后 M0 也必须继续得到服务.
    fork
      issue0(32'h0000_0030, 1'b0, 4'b0000, 1'b0);
      issue1(32'h1000_0040, 4'b1000);
    join
    if (accepted_addr[2] !== 32'h1000_0040 || accepted_addr[3] !== 32'h0000_0030)
      $fatal(1, "空闲优先级错误: %08x %08x", accepted_addr[2], accepted_addr[3]);

    // 参数化实例使用 3 个主端,三路同拍请求应从最高编号依次向下服务.
    fork
      issue0(32'h0000_0050, 1'b0, 4'b0000, 1'b0);
      issue1(32'h1000_0060, 4'b0101);
      issue2(32'h2000_0070);
    join
    if (accepted_addr[4] !== 32'h2000_0070 ||
        accepted_addr[5] !== 32'h1000_0060 ||
        accepted_addr[6] !== 32'h0000_0050)
      $fatal(1, "三主端优先级错误: %08x %08x %08x",
             accepted_addr[4], accepted_addr[5], accepted_addr[6]);

    issue0(32'hdead_0000, 1'b0, 4'b0000, 1'b1);
    if (accepted_count != 8) $fatal(1, "事务数量错误: %0d", accepted_count);
    $display("WISHBONE PASS: 三主端锁定仲裁,固定优先级,SEL/TGA 和 ERR 路由正确");
    $finish;
  end

  initial begin
    #5000;
    $fatal(1, "Wishbone 仿真超时");
  end
endmodule

`default_nettype wire
