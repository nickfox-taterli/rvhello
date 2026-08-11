`default_nettype none

// 程序/数据存储后端: 一块寄存读口 BRAM, 外面套一层标准 valid/ready 握手.
// 主端 (核) 在 valid 期间必须把地址/数据按住不动, 等 ready 回来再锁 rdata;
// 本模块做从端, 采样拍抓请求, 次拍给 ready + rdata, 每次访问固定 2 拍.
// 这样主端不关心后端到底几拍出数, 以后换个慢内存也不影响核.
module prog_mem #(
    parameter integer WORDS   = 1024,
    parameter         MEMFILE = ""
) (
    input  wire        clk,
    input  wire        mem_valid,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wstrb,
    output wire        mem_ready,
    output reg  [31:0] mem_rdata
);
  localparam integer AW = $clog2(WORDS);

  // 字内字节地址低 2 位交给 wstrb 区分, 这里只取字地址.
  wire [AW-1:0] word_addr = mem_addr[AW+1:2];

  (* ram_style = "block" *) reg [31:0] mem [0:WORDS-1];

  initial begin
    if (MEMFILE != "") $readmemh(MEMFILE, mem);
  end

  // busy 标记一次访问进行中: 采样拍 0, 应答拍 1.
  // ready 直接由 busy 给出, 所以 busy 这一拍就是应答拍, rdata 已在上拍采好.
  reg busy;
  assign mem_ready = busy;

  always @(posedge clk) begin
    if (!busy) begin
      if (mem_valid) begin
        // 采样拍: 写则按字节使能落盘, 同时沿上读 BRAM, 次拍 rdata 有效.
        if (mem_wstrb[0]) mem[word_addr][ 7: 0] <= mem_wdata[ 7: 0];
        if (mem_wstrb[1]) mem[word_addr][15: 8] <= mem_wdata[15: 8];
        if (mem_wstrb[2]) mem[word_addr][23:16] <= mem_wdata[23:16];
        if (mem_wstrb[3]) mem[word_addr][31:24] <= mem_wdata[31:24];
        mem_rdata <= mem[word_addr];
        busy      <= 1'b1;
      end
    end else begin
      // 应答拍: busy=1 即 ready, 主端据此锁 rdata, 本拍结束后回空闲.
      busy <= 1'b0;
    end
  end
endmodule

`default_nettype wire
