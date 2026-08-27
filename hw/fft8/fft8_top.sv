module fft8_top(
    input  logic        pclk,
    input  logic        preset,   // = rstn (低有效)
    ahblite_interconnection.ahblite_slave  slave0
);
  // ---------- (1) AHB 地址相位→数据相位寄存 ----------
  logic        hsel_d0, hwrite_d0, htrans_d0;
  logic [31:0] haddr_d0;
  always_ff @(posedge pclk or negedge preset)
    if(!preset) begin
      hsel_d0<=0; hwrite_d0<=0; htrans_d0<=0; haddr_d0<=0;
    end else if(slave0.hready) begin
      hsel_d0   <= slave0.hsel;
      hwrite_d0 <= slave0.hwrite;
      htrans_d0 <= slave0.htrans[1];
      haddr_d0  <= slave0.haddr;
    end

  // ---------- (2) 输入寄存阵列 (8 个复数) ----------
  logic [31:0] in_word [0:7];
  wire wr_in     = hsel_d0 & hwrite_d0 & htrans_d0;
  wire input_wr  = wr_in & ~haddr_d0[5];           // 偏移 0x00..0x1C
  wire wr_last   = input_wr & (haddr_d0[4:2]==3'd7); // 写 0x1C 触发
  always_ff @(posedge pclk or negedge preset)
    if(!preset) for(int i=0;i<8;i++) in_word[i]<=0;
    else if(input_wr) in_word[haddr_d0[4:2]] <= slave0.hwdata;

  // ---------- (3) 拼 128 位总线 ----------
  wire [127:0] in_re, in_im;
  genvar gi;
  generate for(gi=0;gi<8;gi=gi+1) begin : g_bus
    assign in_re[16*gi+15:16*gi] = in_word[gi][31:16];  // 高16位=实部
    assign in_im[16*gi+15:16*gi] = in_word[gi][15:0];   // 低16位=虚部
  end endgenerate

  // ---------- (4) start 寄存打一拍 (消除锁存竞争) ----------
  logic start_r;
  always_ff @(posedge pclk or negedge preset)
    if(!preset) start_r<=0; else start_r<=wr_last;

  // ---------- (5) fft8_pl 核 + valid 握手 ----------
  wire [127:0] out_re, out_im; wire done; logic valid;
  fft8_pl u_fft (
    .clk(pclk), .rst(~preset), .start(start_r),
    .in_re(in_re), .in_im(in_im),
    .out_re(out_re), .out_im(out_im), .done(done)
  );
  always_ff @(posedge pclk or negedge preset)
    if(!preset)       valid<=0;
    else if(wr_last)  valid<=0;   // 触发写入当拍即清,堵住紧跟的lw
    else if(done)     valid<=1;

  // ---------- (6) 读通道 + 等待状态 ----------
  wire rd_phase = hsel_d0 & ~hwrite_d0 & htrans_d0 & haddr_d0[5]; // 偏移0x20..0x3C
  always_comb begin
    case(haddr_d0[4:2])
      0: slave0.hrdata = {out_re[15:0],    out_im[15:0]};
      1: slave0.hrdata = {out_re[31:16],   out_im[31:16]};
      2: slave0.hrdata = {out_re[47:32],   out_im[47:32]};
      3: slave0.hrdata = {out_re[63:48],   out_im[63:48]};
      4: slave0.hrdata = {out_re[79:64],   out_im[79:64]};
      5: slave0.hrdata = {out_re[95:80],   out_im[95:80]};
      6: slave0.hrdata = {out_re[111:96],  out_im[111:96]};
      7: slave0.hrdata = {out_re[127:112], out_im[127:112]};
      default: slave0.hrdata = 32'h0;
    endcase
  end
  assign slave0.hready = rd_phase ? valid : 1'b1;
  assign slave0.hresp  = 1'b0;
endmodule

