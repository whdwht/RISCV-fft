`timescale 1ns/1ps

module tb_soc;
  localparam int MEM_WORDS = 1024;
  localparam int PC_HISTORY_WORDS = 64;
  localparam logic [31:0] FFT_BASE = 32'h4000_0000;
  localparam logic [31:0] RESULT_BASE = 32'h1000_0040;
  localparam logic [31:0] RESULT_LAST = 32'h1000_00bc;
  localparam int RESULT_WORD_OFFSET = 16;
  localparam realtime RESET_RELEASE_TCO_NS = 0.30;
  localparam realtime CLOCK_START_DELAY_NS = 5.00;

  logic clk, rstn, load_en, uart_rx, inst_write, write_start;
  logic [31:0] inst_wdata, inst_wdata_d;
  logic [31:0] mem0 [0:MEM_WORDS-1];
  logic [31:0] expected_fft_input [0:15];
  logic [31:0] expected_result [0:31];
  logic [31:0] pc_history [0:PC_HISTORY_WORDS-1];
  logic [31:0] insn_history [0:PC_HISTORY_WORDS-1];
  logic result_seen [0:31];
  logic [31:0] cycle_count, timeout_cycles;
  logic [31:0] last_pc_id;
  logic measure_enable, completion_pending, finished;
  logic fft_write_pending;
  logic [2:0] fft_write_index;
  logic dump_vcd_enable;
  realtime clk_half_ns, power_window_start_ns, power_window_end_ns;
  integer fft_input_count, fft_done_count, result_write_count;
  integer first_even_input_cycle, first_odd_input_cycle;
  integer first_trigger_cycle, first_done_cycle;
  integer second_trigger_cycle, second_done_cycle;
  integer first_result_cycle, final_result_cycle;
  integer result_bin_done_cycle [0:7];
  string vmem_file, fsdb_file, vcd_file, power_window_file;
  integer i, fd, power_window_fd, pc_history_count, pc_history_next;
  integer pc_history_init_index, result_scan_index, phase_init_index;

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

  // ICC removes address bits that do not participate in the implemented
  // memory-map decode.  The instruction low bits remain available for the
  // timeout diagnostic below.
  wire [31:0] observed_instr_addr = {
    20'h00000,
    x_soc.x_sub_system.x_core.instr_addr_o[11:2],
    2'b00
  };

  // These are stable output ports of the retained Ibex IF-stage instance.
  // Keeping a short history of distinct ID-stage PCs is much smaller and more
  // useful for a headless timeout diagnosis than dumping a full FSDB.
  wire [31:0] observed_pc_id = {
      x_soc.x_sub_system.x_core.if_stage_i.pc_id_o[31:1], 1'b0
  };
  wire [31:0] observed_insn_id =
      x_soc.x_sub_system.x_core.if_stage_i.instr_rdata_id_o;

  task automatic print_pc_history;
    integer history_entries;
    integer history_start;
    integer history_offset;
    integer history_slot;
    begin
      history_entries = (pc_history_count < PC_HISTORY_WORDS) ?
                        pc_history_count : PC_HISTORY_WORDS;
      history_start = (pc_history_count < PC_HISTORY_WORDS) ?
                      0 : pc_history_next;
      $display("Last %0d distinct ID-stage PCs:", history_entries);
      for (history_offset = 0; history_offset < history_entries;
           history_offset = history_offset + 1) begin
        history_slot = (history_start + history_offset) % PC_HISTORY_WORDS;
        $display("  PC[%0d]=%h INSN=%h", history_offset,
                 pc_history[history_slot], insn_history[history_slot]);
      end
    end
  endtask

  initial begin : clock_generator
    clk_half_ns = 1.5;
    void'($value$plusargs("CLK_HALF_NS=%f", clk_half_ns));
    if (clk_half_ns <= 0.0)
      $fatal(1, "CLK_HALF_NS must be positive");
    $display("Gate simulation clock period: %0.3f ns", 2.0 * clk_half_ns);
    clk = 1'b0;
    // Keep the first active clock edge away from time zero so routed reset and
    // SRAM control paths settle before timing checks become active.
    #(CLOCK_START_DELAY_NS);
    forever #(clk_half_ns) clk = ~clk;
  end

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

  task automatic check_loaded_program;
    integer word_index;
    integer bit_index;
    reg [31:0] loaded_word;
    begin
      // RA1HD_4KB stores four 32-bit words bit-interleaved in each 128-bit
      // model row.  Verify the serial SoC loader before releasing the CPU;
      // otherwise a bad image can masquerade as an instruction exception.
      for (word_index = 0; word_index < MEM_WORDS;
           word_index = word_index + 1) begin
        loaded_word = 32'h0;
        for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1)
          loaded_word[bit_index] =
              x_soc.x_isram_ahbl.i_sram_block.mem[word_index >> 2]
                  [4 * bit_index + (word_index & 3)];
        if (loaded_word !== mem0[word_index])
          $fatal(1,
                 "Instruction SRAM load mismatch at word %0d: expected=%h observed=%h",
                 word_index, mem0[word_index], loaded_word);
      end
      $display("Instruction SRAM load check PASS: %0d words", MEM_WORDS);
    end
  endtask

  function automatic [31:0] read_result_word(input integer result_index);
    integer data_word_index;
    integer bit_index;
    begin
      data_word_index = RESULT_WORD_OFFSET + result_index;
      read_result_word = 32'h0;
      for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1)
        read_result_word[bit_index] =
            x_soc.x_data_sram.i_sram_block.mem[data_word_index >> 2]
                [4 * bit_index + (data_word_index & 3)];
    end
  endfunction

  task automatic finish_test;
    integer phase_index;
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
      if (first_even_input_cycle < 0 || first_odd_input_cycle < 0)
        $fatal(1, "CPU+FFT16 TEST FAIL: detailed input milestones are missing");
      for (phase_index = 0; phase_index < 8; phase_index = phase_index + 1)
        if (result_bin_done_cycle[phase_index] < 0)
          $fatal(1, "CPU+FFT16 TEST FAIL: result bin %0d milestone is missing",
                 phase_index);

      // Keep the VCD interval and its metadata from the same simulation.  PT
      // uses these absolute times with read_vcd -time, avoiding accidental
      // averaging over reset/program-loading time or a stale manual window.
      if (dump_vcd_enable) begin
        power_window_end_ns = $realtime;
        power_window_fd = $fopen(power_window_file, "w");
        if (power_window_fd == 0)
          $fatal(1, "Cannot create power-window metadata: %s",
                 power_window_file);
        $fdisplay(power_window_fd, "POWER_START_NS %0.6f",
                  power_window_start_ns);
        $fdisplay(power_window_fd, "POWER_END_NS %0.6f",
                  power_window_end_ns);
        $fdisplay(power_window_fd, "POWER_DURATION_NS %0.6f",
                  power_window_end_ns - power_window_start_ns);
        $fdisplay(power_window_fd, "POWER_CYCLES %0d", final_result_cycle);
        $fclose(power_window_fd);
        $display("Power window: %0.3f ns to %0.3f ns (%0.3f ns, %0d cycles)",
                 power_window_start_ns, power_window_end_ns,
                 power_window_end_ns - power_window_start_ns,
                 final_result_cycle);
      end

      finished = 1'b1;
      if (dump_vcd_enable)
        $dumpoff;
      $display("============================================================");
      $display("CPU+FFT16 TEST PASS: 16 complex results matched the reference");
      $display("FFT8 accelerator calls: %0d", fft_done_count);
      $display("CPU execution cycles: %0d", final_result_cycle);
      $display("FFT16_METRIC cycles=%0d trigger1=%0d done1=%0d trigger2=%0d done2=%0d first_result=%0d final_result=%0d",
               final_result_cycle, first_trigger_cycle, first_done_cycle,
               second_trigger_cycle, second_done_cycle,
               first_result_cycle, final_result_cycle);
      $display("FFT16_PHASE_METRIC first_even_input=%0d first_odd_input=%0d bin0_done=%0d bin1_done=%0d bin2_done=%0d bin3_done=%0d bin4_done=%0d bin5_done=%0d bin6_done=%0d bin7_done=%0d",
               first_even_input_cycle, first_odd_input_cycle,
               result_bin_done_cycle[0], result_bin_done_cycle[1],
               result_bin_done_cycle[2], result_bin_done_cycle[3],
               result_bin_done_cycle[4], result_bin_done_cycle[5],
               result_bin_done_cycle[6], result_bin_done_cycle[7]);
      $display("Simulation time: %0t", $time);
      $display("============================================================");
      $finish;
    end
  endtask

  initial begin : reference_values
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

  initial begin : program_image
    for (i = 0; i < MEM_WORDS; i = i + 1)
      mem0[i] = 32'h0;
    if (!$value$plusargs("VMEM=%s", vmem_file))
      vmem_file = "../../sim_16/sw/gcc.vmem";
    fd = $fopen(vmem_file, "r");
    if (fd == 0)
      $fatal(1, "Cannot open VMEM file: %s", vmem_file);
    $fclose(fd);
    $display("Loading 16-point FFT program image: %s", vmem_file);
    $readmemh(vmem_file, mem0);
  end

  initial begin : optional_fsdb
    if ($test$plusargs("DUMP_FSDB")) begin
      if (!$value$plusargs("FSDB=%s", fsdb_file))
        fsdb_file = "tb_soc.fsdb";
      $display("FSDB dump enabled: %s", fsdb_file);
      $fsdbDumpfile(fsdb_file);
      $fsdbDumpvars(0, tb_soc);
      $fsdbDumpMDA();
    end
  end

  initial begin : measured_window_vcd
    dump_vcd_enable = $test$plusargs("DUMP_VCD");
    if (dump_vcd_enable) begin
      if (!$value$plusargs("VCD=%s", vcd_file))
        vcd_file = "tb_soc.vcd";
      if (!$value$plusargs("POWER_WINDOW=%s", power_window_file))
        power_window_file = "power_window.rpt";
      $display("Measured-window VCD enabled: %s", vcd_file);
      $display("Power-window metadata: %s", power_window_file);
      $dumpfile(vcd_file);
      $dumpvars(0, tb_soc.x_soc);
      $dumpoff;
      wait (measure_enable == 1'b1);
      power_window_start_ns = $realtime;
      $dumpon;
    end
  end

  initial begin : reset_and_load
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
    fft_write_pending = 1'b0;
    fft_write_index = 3'b0;
    finished = 1'b0;
    fft_input_count = 0;
    fft_done_count = 0;
    result_write_count = 0;
    first_even_input_cycle = -1;
    first_odd_input_cycle = -1;
    first_trigger_cycle = -1;
    first_done_cycle = -1;
    second_trigger_cycle = -1;
    second_done_cycle = -1;
    first_result_cycle = -1;
    final_result_cycle = -1;
    for (phase_init_index = 0; phase_init_index < 8;
         phase_init_index = phase_init_index + 1)
      result_bin_done_cycle[phase_init_index] = -1;
    last_pc_id = 32'hffff_ffff;
    pc_history_count = 0;
    pc_history_next = 0;
    for (pc_history_init_index = 0;
         pc_history_init_index < PC_HISTORY_WORDS;
         pc_history_init_index = pc_history_init_index + 1) begin
      pc_history[pc_history_init_index] = 32'h0;
      insn_history[pc_history_init_index] = 32'h0;
    end
    for (result_scan_index = 0; result_scan_index < 32;
         result_scan_index = result_scan_index + 1)
      result_seen[result_scan_index] = 1'b0;

    repeat (4) @(posedge clk);
    #(RESET_RELEASE_TCO_NS) rstn = 1'b1;
    load_program();
    check_loaded_program();
    repeat (10) @(negedge clk);

    // Re-enter reset after loading so the cycle/VCD window only contains the
    // program execution. Deassertion models a rising-edge-launched reset
    // source with a nonzero clock-to-Q delay.
    rstn = 1'b0;
    repeat (4) @(posedge clk);
    cycle_count = 32'h0;
    measure_enable = 1'b1;
    #(RESET_RELEASE_TCO_NS) rstn = 1'b1;
  end

  always @(posedge clk) begin
    if (measure_enable && rstn && !finished)
      cycle_count <= cycle_count + 1'b1;
  end

  always @(negedge clk) begin : pc_history_sampler
    if (!rstn) begin
      last_pc_id <= 32'hffff_ffff;
    end else if (measure_enable && observed_pc_id !== last_pc_id) begin
      pc_history[pc_history_next] <= observed_pc_id;
      insn_history[pc_history_next] <= observed_insn_id;
      last_pc_id <= observed_pc_id;
      pc_history_next <= (pc_history_next + 1) % PC_HISTORY_WORDS;
      pc_history_count <= pc_history_count + 1;
    end
  end

  // Observe accepted AHB writes at the destination slave and check their data
  // one cycle later (the AHB data phase).  Sampling the core request/grant
  // ports on the root clock is unreliable after clock-tree insertion because
  // those signals and the core clock arrive with routed skew.
  always @(posedge x_soc.u_fft8_top.pclk) begin : fft_input_scoreboard
    if (!x_soc.u_fft8_top.preset) begin
      fft_input_count <= 0;
      fft_write_pending <= 1'b0;
      fft_write_index <= 3'b0;
    end else if (measure_enable) begin
      if (fft_write_pending && fft_input_count < 16) begin
        if (fft_write_index != (fft_input_count & 7))
          $fatal(1, "FFT input address order mismatch: write=%0d index=%0d",
                 fft_input_count, fft_write_index);
        if ($isunknown(x_soc.u_fft8_top.slave0_hwdata) ||
            x_soc.u_fft8_top.slave0_hwdata !==
              expected_fft_input[fft_input_count])
          $fatal(1, "FFT input[%0d] mismatch: expected=%h observed=%h",
                 fft_input_count, expected_fft_input[fft_input_count],
                 x_soc.u_fft8_top.slave0_hwdata);
        $display("FFT16 INPUT[%0d] addr=%h data=%h PASS",
                 fft_input_count,
                 FFT_BASE + ({29'b0, fft_write_index} << 2),
                 x_soc.u_fft8_top.slave0_hwdata);
        if (fft_input_count == 0)
          first_even_input_cycle <= cycle_count;
        else if (fft_input_count == 7)
          first_trigger_cycle <= cycle_count;
        else if (fft_input_count == 8)
          first_odd_input_cycle <= cycle_count;
        else if (fft_input_count == 15)
          second_trigger_cycle <= cycle_count;
        fft_input_count <= fft_input_count + 1;
      end

      fft_write_pending <= x_soc.u_fft8_top.slave0_hready &&
                           x_soc.u_fft8_top.slave0_hsel &&
                           x_soc.u_fft8_top.slave0_htrans[1] &&
                           !x_soc.u_fft8_top.slave0_haddr[5];
      fft_write_index <= x_soc.u_fft8_top.slave0_haddr[4:2];
    end else begin
      fft_write_pending <= 1'b0;
    end
  end

  always @(posedge clk) begin
    if (!rstn) begin
      fft_done_count <= 0;
    end else if (measure_enable && x_soc.u_fft8_top.done) begin
      if (fft_done_count == 0)
        first_done_cycle <= cycle_count + 1;
      else if (fft_done_count == 1)
        second_done_cycle <= cycle_count + 1;
      fft_done_count <= fft_done_count + 1;
      $display("FFT8 accelerator call %0d completed", fft_done_count + 1);
    end
  end

  // Observe committed SRAM contents instead of sampling an AHB address/data
  // phase across the routed clock tree.  At max-delay SDF, hsel/address and
  // the local SRAM clock can legitimately cross the testbench sampling edge;
  // the macro contents are the architectural result and are race-free here.
  always @(negedge clk) begin : result_scoreboard
    if (!rstn) begin
      result_write_count = 0;
      completion_pending = 1'b0;
      for (result_scan_index = 0; result_scan_index < 32;
           result_scan_index = result_scan_index + 1)
        result_seen[result_scan_index] = 1'b0;
    end else if (measure_enable && !finished) begin
      for (result_scan_index = 0; result_scan_index < 32;
           result_scan_index = result_scan_index + 1) begin
        if (!result_seen[result_scan_index] &&
            !$isunknown(read_result_word(result_scan_index))) begin
          if (read_result_word(result_scan_index) !==
              expected_result[result_scan_index])
            $fatal(1,
                   "FFT16 result word[%0d] addr=%h expected=%h observed=%h",
                   result_scan_index,
                   RESULT_BASE + (result_scan_index << 2),
                   expected_result[result_scan_index],
                   read_result_word(result_scan_index));
          result_seen[result_scan_index] = 1'b1;
          // SRAM visibility trails the accepted AHB data phase by one cycle.
          // Report the architectural store cycle used by the RTL scoreboard.
          if (result_write_count == 0)
            first_result_cycle = cycle_count - 1;
          if (result_scan_index >= 17 && (result_scan_index % 2) == 1)
            result_bin_done_cycle[(result_scan_index - 17) / 2] =
              cycle_count - 1;
          result_write_count = result_write_count + 1;
          $display("FFT16 RESULT[%0d] addr=%h data=%h PASS",
                   result_scan_index,
                   RESULT_BASE + (result_scan_index << 2),
                   read_result_word(result_scan_index));
          if (result_write_count == 32) begin
            final_result_cycle = cycle_count - 1;
            completion_pending = 1'b1;
          end
        end
      end
    end
  end

  // The event is triggered after all scoreboard nonblocking assignments from
  // the final result have settled, so finish_test observes a count of 32.
  always @(posedge completion_pending)
    if (!finished)
      finish_test();

  initial begin : timeout_guard
    timeout_cycles = 20000;
    void'($value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles));
    wait (measure_enable == 1'b1);
    repeat (timeout_cycles) @(posedge clk);
    if (!finished) begin
      $display("ERROR: timeout after %0d cycles", timeout_cycles);
      $display("PC=%h FFT_start=%b FFT_done=%b FFT_valid=%b inputs=%0d calls=%0d results=%0d",
               observed_instr_addr,
               x_soc.u_fft8_top.start_r, x_soc.u_fft8_top.done,
               x_soc.u_fft8_top.valid, fft_input_count,
               fft_done_count, result_write_count);
      print_pc_history();
      $fatal(1, "CPU+FFT16 TEST FAIL: timeout");
    end
  end
endmodule
