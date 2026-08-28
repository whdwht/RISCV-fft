`timescale 1ns/1ps

module tb_soc;
  localparam int MEM_WORDS = 1024;
  localparam logic [31:0] FFT_BASE = 32'h4000_0000;

  logic clk, rstn, load_en, uart_rx, inst_write, write_start;
  logic [31:0] inst_wdata, inst_wdata_d;
  logic [31:0] mem0 [0:MEM_WORDS-1];
  logic [31:0] expected_input [0:7];
  logic [31:0] expected_reg [0:7];
  logic [31:0] cycle_count, timeout_cycles;
  logic measure_enable, fft_completed, completion_pending, finished;
  string vmem_file, fsdb_file;
  integer i, fd;

  soc_ahblite x_soc (
    .sys_clk(clk), .rstn(rstn), .load_en(load_en),
    .uart_rx(uart_rx), .uart_tx(),
    .spi_rstn(1'b0), .cs_n_ext(1'b0), .sclk_ext(1'b0),
    .cs_n(), .sclk(), .spi_do(), .spi_di(1'b0),
    .rx_dma_ack(1'b0), .tx_dma_ack(1'b0),
    .rx_dma_req(), .tx_dma_req(),
    .sda_ext(1'b0), .scl_ext(1'b0), .sda(), .scl(),
    .inst_write(inst_write), .write_start(write_start),
    .inst_wdata(inst_wdata)
  );

  always #5 clk = ~clk;

  task automatic load_program;
    begin
      @(negedge clk);
      for (i = 0; i < MEM_WORDS; i = i + 1) begin
        @(negedge clk);
        write_start = 1'b1;
        inst_write = 1'b1;
        // The SoC loader pipelines the AHB address phase by one cycle.
        inst_wdata_d <= mem0[i];
        inst_wdata <= inst_wdata_d;
      end
      @(negedge clk);
      inst_write = 1'b0;
      write_start = 1'b0;
      @(negedge clk);
    end
  endtask

  task automatic check_registers;
    integer k, errors;
    logic [31:0] actual;
    begin
      errors = 0;
      for (k = 0; k < 8; k = k + 1) begin
        actual = x_soc.x_sub_system.x_core.gen_regfile_ff.register_file_i.rf_reg_q[k+11];
        if ($isunknown(actual)) begin
          $display("ERROR: x%0d contains X/Z: %h", k + 11, actual);
          errors = errors + 1;
        end else if (actual !== expected_reg[k]) begin
          $display("ERROR: x%0d expected=%h observed=%h",
                   k + 11, expected_reg[k], actual);
          errors = errors + 1;
        end else begin
          $display("REGISTER x%0d = %h PASS", k + 11, actual);
        end
      end
      if (errors != 0)
        $fatal(1, "CPU+FFT TEST FAIL: %0d mismatched registers", errors);

      finished = 1'b1;
      $display("============================================================");
      $display("CPU+FFT TEST PASS: x11-x18 matched the course reference");
      $display("CPU execution cycles: %0d", cycle_count);
      $display("Simulation time: %0t", $time);
      $display("============================================================");
      $finish;
    end
  endtask

  initial begin
    expected_input[0] = 32'h2150013d;
    expected_input[1] = 32'hed80dda0;
    expected_input[2] = 32'h052fefa1;
    expected_input[3] = 32'h149a121b;
    expected_input[4] = 32'hff3dff75;
    expected_input[5] = 32'h1143ff10;
    expected_input[6] = 32'h1a04e3a1;
    expected_input[7] = 32'h077a2370;

    expected_reg[0] = 32'h5a97e62f;
    expected_reg[1] = 32'he79e1b3b;
    expected_reg[2] = 32'ha87f4ac1;
    expected_reg[3] = 32'h14bf0857;
    expected_reg[4] = 32'h24e9c1b9;
    expected_reg[5] = 32'h748811ff;
    expected_reg[6] = 32'h5a35101f;
    expected_reg[7] = 32'h1767d18f;
  end

  initial begin
    for (i = 0; i < MEM_WORDS; i = i + 1)
      mem0[i] = 32'h0;
    if (!$value$plusargs("VMEM=%s", vmem_file))
      vmem_file = "../sw/gcc.vmem";
    fd = $fopen(vmem_file, "r");
    if (fd == 0)
      $fatal(1, "Cannot open VMEM file: %s", vmem_file);
    $fclose(fd);
    $display("Loading program image: %s", vmem_file);
    $readmemh(vmem_file, mem0);
  end

  initial begin
    if ($test$plusargs("DUMP_FSDB")) begin
      if (!$value$plusargs("FSDB=%s", fsdb_file))
        fsdb_file = "tb_soc.fsdb";
      $display("FSDB dump enabled: %s", fsdb_file);
      $fsdbDumpfile(fsdb_file);
      $fsdbDumpvars(0, tb_soc);
      $fsdbDumpMDA();
    end
  end

  initial begin
    clk = 1'b0;
    rstn = 1'b0;
    load_en = 1'b0;
    uart_rx = 1'b1;
    inst_write = 1'b1;
    write_start = 1'b0;
    inst_wdata = 32'h0;
    inst_wdata_d = 32'h0;
    cycle_count = 32'h0;
    measure_enable = 1'b0;
    fft_completed = 1'b0;
    completion_pending = 1'b0;
    finished = 1'b0;

    #20 rstn = 1'b1;
    #10 load_program();
    #100;
    load_en = 1'b0;
    rstn = 1'b0;
    #20;
    cycle_count = 32'h0;
    measure_enable = 1'b1;
    rstn = 1'b1;
  end

  always @(posedge clk)
    if (measure_enable && rstn && !finished)
      cycle_count <= cycle_count + 1'b1;

  // Check accepted CPU writes so a stale VMEM fails at the source.
  always @(posedge clk) begin : input_scoreboard
    integer input_index;
    if (measure_enable && rstn &&
        x_soc.x_sub_system.data_req && x_soc.x_sub_system.data_gnt &&
        x_soc.x_sub_system.data_we &&
        x_soc.x_sub_system.data_addr >= FFT_BASE &&
        x_soc.x_sub_system.data_addr <= FFT_BASE + 32'h1c) begin
      input_index = (x_soc.x_sub_system.data_addr - FFT_BASE) >> 2;
      if ($isunknown(x_soc.x_sub_system.data_wdata) ||
          x_soc.x_sub_system.data_wdata !== expected_input[input_index])
        $fatal(1, "FFT input[%0d] mismatch: expected=%h observed=%h",
               input_index, expected_input[input_index],
               x_soc.x_sub_system.data_wdata);
      $display("FFT INPUT[%0d] addr=%h data=%h PASS", input_index,
               x_soc.x_sub_system.data_addr,
               x_soc.x_sub_system.data_wdata);
    end
  end

  // Reset startup also writes x18. Arm only after the FFT has completed.
  always @(posedge clk) begin
    if (!rstn) begin
      fft_completed <= 1'b0;
      completion_pending <= 1'b0;
    end else if (measure_enable) begin
      if (x_soc.u_fft8_top.done)
        fft_completed <= 1'b1;
      if (fft_completed && x_soc.x_sub_system.x_core.rf_we_wb &&
          x_soc.x_sub_system.x_core.rf_waddr_wb == 5'd18)
        completion_pending <= 1'b1;
    end
  end

  // Sample after the final writeback nonblocking assignment has settled.
  always @(negedge clk)
    if (completion_pending && !finished)
      check_registers();

  initial begin : timeout_guard
    timeout_cycles = 20000;
    void'($value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles));
    wait (measure_enable == 1'b1);
    repeat (timeout_cycles) @(posedge clk);
    if (!finished) begin
      $display("ERROR: timeout after %0d cycles", timeout_cycles);
      $display("PC=%h FFT_start=%b FFT_done=%b FFT_valid=%b x18=%h",
               x_soc.x_sub_system.instr_addr,
               x_soc.u_fft8_top.start_r, x_soc.u_fft8_top.done,
               x_soc.u_fft8_top.valid,
               x_soc.x_sub_system.x_core.gen_regfile_ff.register_file_i.rf_reg_q[18]);
      $fatal(1, "CPU+FFT TEST FAIL: timeout");
    end
  end
endmodule
