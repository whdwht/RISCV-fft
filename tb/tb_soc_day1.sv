// minimalistic simulation top module with clock gen and initial reset
`timescale 1ns/1ps
module tb_soc;

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
/*
  .inst_write_sel(inst_write_sel),
  .inst_write(inst_write),
  .inst_addr(inst_addr),
  .inst_wdata(inst_wdata)
*/
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
task mem_test();
   @(negedge clk);
    CEN <= 0;
    @(negedge clk);
    WEN <= 0;
    A<= 0;
    mem_in<= 3;
    @(negedge clk);
    WEN <= 0;
    A<= 32;
    mem_in<= 4;
    @(negedge clk);
    WEN <= 1;
    GWEN<=1;
    A <= 0;
    mem_in <=0;
    @(negedge clk);
    CEN <= 0;
endtask
    task mem_tran();
        begin
            inst_write_sel <= 1;
            @(negedge clk);
            for(i = 0 ; i < 1024;i++) begin
                @(negedge clk) begin
                       write_start = 1;
                    inst_write <= 1;
                    inst_addr <= i;
 		    //inst_wdata <= mem0[i];
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
    task task_rx;
    input [7:0] input_data;
    begin
    uart_rx = 0;
    for(i=0;i<8;i++)begin
    #(rx_count) uart_rx = input_data[i];
    end
    #(rx_count) uart_rx = 1;
    #(rx_count);
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
        #20;
        rstn = 1'b1;
        #10;
/*
        load_en = 1;
	# 20;
	task_rx(8'hff);
	task_rx(8'hff);
        task_rx(8'hff);
        task_rx(8'hff);
 	task_rx(8'h10);
	task_rx(8'h20);
	task_rx(8'h30);
	task_rx(8'h40);
*/
	mem_tran();
	//mem_test();
        # 100;
	load_en = 1'b0;
 	rstn = 1'b0;
	#20;
        rstn = 1'b1;
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
    $dumpvars(0);
  end

  initial begin
      $vcdplusfile("tb_soc.vpd");
      $vcdplusmemon();
      $vcdpluson();
  end

  initial begin
    for(i=0;i<1024;i++)begin
         mem0[i] <=0;
     end
     #10;
    $display("*****start to load program*****");
    //$readmemh("../sw/uart/uart.vmem",x_soc.x_isram_ahbl.sram_mem);
    //$readmemh("../sw/uart/uart.vmem",x_soc.x_isram_ahbl.i_sram_block.mem);
    $readmemh("../../gcc/gcc.vmem",mem0);
  end
/*
  initial begin

    $display("*****start to load data*****");
    $readmemh("../sw/uart/data.vmem",x_soc.x_data_sram.i_sram_block.mem);

  end
*/

endmodule
