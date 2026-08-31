// post-sim (gate-level) testbench: 与 day1 RTL 仿真同一测试台, 仅两处适配:
//   1) $readmemh 改为绝对路径 (day1 的 fft16.vmem)
//   2) 注释掉 VCD/VPD 双重 dump (门级网表19k单元, 只留 fsdb, 省 disk/时间)
//      如需恢复, 取消注释即可
`timescale 1ns/1ps
module tb_soc;

    localparam realtime RESET_RELEASE_TCO_NS = 0.30;

    logic clk, rstn;

    logic [31:0] mem0 [0:1023];
    logic inst_write_sel;
    logic inst_write;
    logic [31:0] inst_addr;
    logic [31:0] inst_wdata,inst_wdata1;
    logic        uart_rx,load_en;
logic write_start;
    parameter rx_count = 320 * 16;
soc_ahblite x_soc
(
  .sys_clk   ( clk  ),
  .rstn  (rstn),
  .load_en (load_en),
  .uart_rx(uart_rx),
  .cs_n_ext(1'b0),
  .sclk_ext(1'b0),
  .spi_di(1'b0),
  .sda_ext(1'b0),
  .scl_ext(1'b0),
   .inst_write(inst_write),
    .write_start(write_start),
   .inst_wdata(inst_wdata)
);
logic CEN;
logic WEN,GWEN;
logic [31:0] WEN_in;
logic [9:0] A;
logic [31:0] mem_in,mem_out;
    integer i;
always_comb begin
for (integer k=0;k<32;k++)begin
	WEN_in[k] = WEN;
end
end
  RA1HD_4KB test_mem
(
    .CLK(clk),
    .CEN(CEN),
    .WEN(WEN_in),
    .A(A),
    .D(mem_in),
    .EMA(3'b000),
     .GWEN(GWEN),
    .RETN(1'b1),
    .Q(mem_out)
);
task mem_tran();
        begin
            inst_write_sel <= 1;
            @(negedge clk);
            for(i = 0 ; i < 1024;i++) begin
                @(negedge clk) begin
                       write_start = 1;
                    inst_write <= 1;
                    inst_addr <= i;
		    inst_wdata1 <= mem0[i];
		    inst_wdata <= inst_wdata1;
                end
            end
            @(negedge clk);
            inst_write<= 0;
	      write_start = 0;
            @(negedge clk);
        end
endtask

    initial begin
        CEN <=1;
	WEN<=1;
	GWEN<=0;
        inst_wdata <= 0;
          inst_wdata1<=0;
	A<=0;
	mem_in<=0;
	load_en =0;
	 inst_write=1;
         write_start=0;
        rstn = 1'b0;
        repeat (2) @(posedge clk);
        #(RESET_RELEASE_TCO_NS) rstn = 1'b1;
        #10;
	mem_tran();
        # 100;
	load_en = 1'b0;
 	rstn = 1'b0;
	repeat (2) @(posedge clk);
        #(RESET_RELEASE_TCO_NS) rstn = 1'b1;
        #100000;
        $finish(2);
    end

    always begin
        clk = 1'b0;
        #5;
        clk = 1'b1;
        #5;
    end

  initial begin
    $fsdbDumpfile("tb_soc.fsdb");
    $fsdbDumpvars();
    $fsdbDumpMDA();
  end

  initial begin
    $dumpfile("tb_soc.vcd");
    $dumpvars(0, tb_soc.x_soc);
    $dumpoff;
    #10300 $dumpon;
    #5500 $dumpoff;
  end

  //initial begin
  //    $vcdplusfile("tb_soc.vpd");
  //    $vcdplusmemon();
  //    $vcdpluson();
  //end

  initial begin
    for(i=0;i<1024;i++)begin
         mem0[i] <=0;
     end
     #10;
    $display("*****start to load program*****");
    $readmemh("/home/master/project1/day1/IC_class/gcc/gcc.vmem",mem0);
  end

endmodule
