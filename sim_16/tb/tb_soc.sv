`timescale 1ns/1ps

module tb_soc;
  localparam int MEM_WORDS = 1024;
  localparam logic [31:0] FFT_BASE = 32'h4000_0000;
  localparam logic [31:0] RESULT_BASE = 32'h1000_0040;
  localparam logic [31:0] RESULT_LAST = 32'h1000_00bc;
  localparam realtime RESET_RELEASE_TCO_NS = 0.30;

  logic clk, rstn, load_en, uart_rx, inst_write, write_start;
  logic [31:0] inst_wdata, inst_wdata_d;
  logic [31:0] mem0 [0:MEM_WORDS-1];
  logic [31:0] expected_fft_input [0:15];
  logic [31:0] expected_result [0:31];
  logic [31:0] cycle_count, timeout_cycles;
  logic measure_enable, completion_pending, finished;
  integer fft_input_count, fft_done_count, result_write_count;
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

  task automatic finish_test;
    begin
      if (fft_input_count != 16)
        $fatal(1, "CPU+FFT16 TEST FAIL: expected 16 FFT input writes, observed %0d",
               fft_input_count);
      if (fft_done_count != 2)
        $fatal(1, "CPU+FFT16 TEST FAIL: expected 2 FFT completions, observed %0d",
               fft_done_count);
      if (result_write_count != 32)
        $fatal(1, "CPU+FFT16 TEST FAIL: expected 32 result writes, observed %0d",
               result_write_count);

      finished = 1'b1;
      $display("============================================================");
      $display("CPU+FFT16 TEST PASS: 16 complex results matched the reference");
      $display("FFT8 accelerator calls: %0d", fft_done_count);
      $display("CPU execution cycles: %0d", cycle_count);
      $display("Simulation time: %0t", $time);
      $display("============================================================");
      $finish;
    end
  endtask

  initial begin
    // First call: even-indexed samples x[0],x[2],...,x[14].
    expected_fft_input[0]  = 32'h2150_013d;
    expected_fft_input[1]  = 32'h052f_efa1;
    expected_fft_input[2]  = 32'hff3d_ff75;
    expected_fft_input[3]  = 32'h1a04_e3a1;
    expected_fft_input[4]  = 32'h0be7_04ef;
    expected_fft_input[5]  = 32'h0ee7_ede3;
    expected_fft_input[6]  = 32'h10ac_f9cb;
    expected_fft_input[7]  = 32'h0920_152d;

    // Second call: odd-indexed samples x[1],x[3],...,x[15].
    expected_fft_input[8]  = 32'hed80_e2b4;
    expected_fft_input[9]  = 32'h149a_121b;
    expected_fft_input[10] = 32'h1143_ff10;
    expected_fft_input[11] = 32'h077a_1d4c;
    expected_fft_input[12] = 32'hf62a_0b9e;
    expected_fft_input[13] = 32'hfa3f_0925;
    expected_fft_input[14] = 32'hf4b3_0f4d;
    expected_fft_input[15] = 32'hf8dd_f39a;

    // Address order: X[0].re, X[0].im, ..., X[15].re, X[15].im.
    expected_result[0]  = 32'h0000_6d2a;
    expected_result[1]  = 32'hffff_fe93;
    expected_result[2]  = 32'hffff_c9ab;
    expected_result[3]  = 32'hffff_b53f;
    expected_result[4]  = 32'hffff_d02c;
    expected_result[5]  = 32'h0000_0bfe;
    expected_result[6]  = 32'hffff_fd67;
    expected_result[7]  = 32'hffff_9a2b;
    expected_result[8]  = 32'hffff_d66f;
    expected_result[9]  = 32'h0000_4eaa;
    expected_result[10] = 32'h0000_5a0f;
    expected_result[11] = 32'h0000_34f5;
    expected_result[12] = 32'h0000_4bc3;
    expected_result[13] = 32'h0000_29d5;
    expected_result[14] = 32'h0000_2ea6;
    expected_result[15] = 32'h0000_21de;
    expected_result[16] = 32'h0000_7b8a;
    expected_result[17] = 32'hffff_ace9;
    expected_result[18] = 32'h0000_0343;
    expected_result[19] = 32'h0000_a49d;
    expected_result[20] = 32'h0000_33dc;
    expected_result[21] = 32'h0000_2bf6;
    expected_result[22] = 32'h0000_041f;
    expected_result[23] = 32'hffff_e8e9;
    expected_result[24] = 32'h0000_355d;
    expected_result[25] = 32'h0000_038a;
    expected_result[26] = 32'h0000_454f;
    expected_result[27] = 32'hffff_a823;
    expected_result[28] = 32'h0000_256d;
    expected_result[29] = 32'hffff_d1e7;
    expected_result[30] = 32'h0000_0ed0;
    expected_result[31] = 32'h0000_068a;
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
    $display("Loading 16-point FFT program image: %s", vmem_file);
    $readmemh(vmem_file, mem0);
  end

  initial begin
    if ($test$plusargs("DUMP_FSDB")) begin
      if (!$value$plusargs("FSDB=%s", fsdb_file))
        fsdb_file = "tb_soc_fft16.fsdb";
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
    completion_pending = 1'b0;
    finished = 1'b0;
    fft_input_count = 0;
    fft_done_count = 0;
    result_write_count = 0;

    repeat (2) @(posedge clk);
    #(RESET_RELEASE_TCO_NS) rstn = 1'b1;
    #10 load_program();
    #100;
    load_en = 1'b0;
    rstn = 1'b0;
    repeat (2) @(posedge clk);
    cycle_count = 32'h0;
    measure_enable = 1'b1;
    #(RESET_RELEASE_TCO_NS) rstn = 1'b1;
  end

  always @(posedge clk) begin
    if (measure_enable && rstn && !finished)
      cycle_count <= cycle_count + 1'b1;
  end

  // Check each accepted CPU write to the FFT input window. The two calls use
  // the same eight addresses, so fft_input_count also identifies the call.
  always @(posedge clk) begin : fft_input_scoreboard
    integer input_address_index;
    if (!rstn) begin
      fft_input_count <= 0;
    end else if (measure_enable &&
        x_soc.x_sub_system.data_req && x_soc.x_sub_system.data_gnt &&
        x_soc.x_sub_system.data_we &&
        x_soc.x_sub_system.data_addr >= FFT_BASE &&
        x_soc.x_sub_system.data_addr <= FFT_BASE + 32'h1c) begin
      if (fft_input_count >= 16)
        $fatal(1, "CPU+FFT16 TEST FAIL: unexpected extra FFT input write");
      input_address_index =
        (x_soc.x_sub_system.data_addr - FFT_BASE) >> 2;
      if (input_address_index != (fft_input_count & 7))
        $fatal(1, "FFT input address order mismatch: write=%0d addr=%h",
               fft_input_count, x_soc.x_sub_system.data_addr);
      if ($isunknown(x_soc.x_sub_system.data_wdata) ||
          x_soc.x_sub_system.data_wdata !== expected_fft_input[fft_input_count])
        $fatal(1, "FFT input[%0d] mismatch: expected=%h observed=%h",
               fft_input_count, expected_fft_input[fft_input_count],
               x_soc.x_sub_system.data_wdata);
      $display("FFT16 INPUT[%0d] addr=%h data=%h PASS",
               fft_input_count, x_soc.x_sub_system.data_addr,
               x_soc.x_sub_system.data_wdata);
      fft_input_count <= fft_input_count + 1;
    end
  end

  always @(posedge clk) begin
    if (!rstn) begin
      fft_done_count <= 0;
    end else if (measure_enable && x_soc.u_fft8_top.done) begin
      fft_done_count <= fft_done_count + 1;
      $display("FFT8 accelerator call %0d completed", fft_done_count + 1);
    end
  end

  // Final values are stored as separate signed 32-bit real/imaginary words.
  // Checking accepted CPU stores avoids depending on the SRAM macro internals.
  always @(posedge clk) begin : result_scoreboard
    integer result_index;
    if (!rstn) begin
      result_write_count <= 0;
      completion_pending <= 1'b0;
    end else if (measure_enable &&
        x_soc.x_sub_system.data_req && x_soc.x_sub_system.data_gnt &&
        x_soc.x_sub_system.data_we &&
        x_soc.x_sub_system.data_addr >= RESULT_BASE &&
        x_soc.x_sub_system.data_addr <= RESULT_LAST) begin
      result_index = (x_soc.x_sub_system.data_addr - RESULT_BASE) >> 2;
      if ($isunknown(x_soc.x_sub_system.data_wdata) ||
          x_soc.x_sub_system.data_wdata !== expected_result[result_index])
        $fatal(1, "FFT16 result word[%0d] addr=%h expected=%h observed=%h",
               result_index, x_soc.x_sub_system.data_addr,
               expected_result[result_index],
               x_soc.x_sub_system.data_wdata);
      $display("FFT16 RESULT[%0d] addr=%h data=%h PASS",
               result_index, x_soc.x_sub_system.data_addr,
               x_soc.x_sub_system.data_wdata);
      result_write_count <= result_write_count + 1;
      if (x_soc.x_sub_system.data_addr == RESULT_LAST)
        completion_pending <= 1'b1;
    end
  end

  // Sample after scoreboard nonblocking assignments have settled.
  always @(negedge clk)
    if (completion_pending && !finished)
      finish_test();

  initial begin : timeout_guard
    timeout_cycles = 20000;
    void'($value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles));
    wait (measure_enable == 1'b1);
    repeat (timeout_cycles) @(posedge clk);
    if (!finished) begin
      $display("ERROR: timeout after %0d cycles", timeout_cycles);
      $display("PC=%h FFT_start=%b FFT_done=%b FFT_valid=%b inputs=%0d calls=%0d results=%0d",
               x_soc.x_sub_system.instr_addr,
               x_soc.u_fft8_top.start_r, x_soc.u_fft8_top.done,
               x_soc.u_fft8_top.valid, fft_input_count,
               fft_done_count, result_write_count);
      $fatal(1, "CPU+FFT16 TEST FAIL: timeout");
    end
  end
endmodule
