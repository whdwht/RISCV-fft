# =============================================================================
# soc_ahblite synthesis timing constraints
#
# The external component timing is not fixed yet. Keep all board/device
# assumptions in the parameter section below so that they can be replaced
# without changing the constraint structure.
#
# Supported analysis modes (override with the STA_MODE environment variable):
#   functional : execute from instruction SRAM (default)
#   program    : externally program instruction SRAM
#   rom        : execute/load through the ROM-selected path
# =============================================================================

# -----------------------------------------------------------------------------
# Parameter defaults
# A variable that has already been set by the caller is intentionally preserved.
# -----------------------------------------------------------------------------
foreach {parameter default_value} {
    T_CLKV_PER                 3.0
    T_CLKV_RISE                0.0
    T_CLK_SETUP_UNCERTAINTY    0.30
    T_CLK_HOLD_UNCERTAINTY     0.05
    T_CLK_TRANSITION           0.10
    T_IO_MAX_RATIO             0.30
    T_SYNC_INPUT_MIN           0.00
    T_INPUT_TRANSITION         0.20
    T_RESET_RELEASE_MIN        0.10
    T_RESET_RELEASE_MAX        0.50
    T_SYNC_OUTPUT_MIN         -0.20
    C_OUTPUT_LOAD              0.05
    MAX_DESIGN_TRANSITION      0.50
    MAX_DESIGN_FANOUT         32
    MAX_DESIGN_CAPACITANCE     0.20
    ENABLE_FIX_HOLD            1
    ENABLE_POST_HOLD_RECOVERY  1
} {
    if {![info exists $parameter]} {
        set $parameter $default_value
    }
}

if {![info exists T_CLKV_FALL]} {
    set T_CLKV_FALL [expr {$T_CLKV_PER / 2.0}]
}
if {![info exists T_SYNC_INPUT_MAX]} {
    set T_SYNC_INPUT_MAX [expr {$T_CLKV_PER * $T_IO_MAX_RATIO}]
}
if {![info exists T_SYNC_OUTPUT_MAX]} {
    set T_SYNC_OUTPUT_MAX [expr {$T_CLKV_PER * $T_IO_MAX_RATIO}]
}

if {[info exists env(STA_MODE)] && $env(STA_MODE) ne ""} {
    set STA_MODE $env(STA_MODE)
} elseif {![info exists STA_MODE]} {
    set STA_MODE functional
}

set VALID_STA_MODES {functional program rom}
if {[lsearch -exact $VALID_STA_MODES $STA_MODE] < 0} {
    error "Unsupported STA_MODE '$STA_MODE'; expected one of: $VALID_STA_MODES"
}

# -----------------------------------------------------------------------------
# Primary clock and clock quality assumptions
# -----------------------------------------------------------------------------
set SYS_CLK_PORT [get_ports sys_clk]
create_clock \
    -name clk1 \
    -period $T_CLKV_PER \
    -waveform [list $T_CLKV_RISE $T_CLKV_FALL] \
    $SYS_CLK_PORT

set SYS_CLK [get_clocks clk1]
set_clock_uncertainty -setup $T_CLK_SETUP_UNCERTAINTY $SYS_CLK
set_clock_uncertainty -hold  $T_CLK_HOLD_UNCERTAINTY  $SYS_CLK
set_clock_transition $T_CLK_TRANSITION $SYS_CLK

# -----------------------------------------------------------------------------
# Design-rule constraints
# Library pin limits remain active; these values add project-level limits.
# -----------------------------------------------------------------------------
set_max_transition  $MAX_DESIGN_TRANSITION  [current_design]
set_max_fanout      $MAX_DESIGN_FANOUT      [current_design]
set_max_capacitance $MAX_DESIGN_CAPACITANCE [current_design]

# -----------------------------------------------------------------------------
# Reset protocol
# rstn may assert asynchronously (falling edge). Its rising/deasserting edge
# is required to be launched synchronously from the same rising-edge clock and
# is checked for recovery/removal using the provisional external tCO values.
# -----------------------------------------------------------------------------
set RESET_PORT [get_ports rstn]
set_input_transition $T_INPUT_TRANSITION $RESET_PORT
set_input_delay \
    -clock clk1 -rise -min $T_RESET_RELEASE_MIN \
    $RESET_PORT
set_input_delay \
    -clock clk1 -rise -max $T_RESET_RELEASE_MAX \
    $RESET_PORT
set_false_path -fall_from $RESET_PORT

# -----------------------------------------------------------------------------
# Mutually exclusive operating modes
# load_en and inst_write are mode controls and may change only while reset is
# asserted. The program-mode payload/control is rising-edge synchronous.
# -----------------------------------------------------------------------------
switch -exact -- $STA_MODE {
    functional {
        set_case_analysis 0 [get_ports load_en]
        set_case_analysis 0 [get_ports inst_write]
        set_case_analysis 0 [get_ports write_start]
    }

    program {
        set_case_analysis 0 [get_ports load_en]
        set_case_analysis 1 [get_ports inst_write]

        set PROGRAM_SYNC_INPUTS \
            [get_ports {write_start inst_wdata[*]}]
        set_input_transition $T_INPUT_TRANSITION $PROGRAM_SYNC_INPUTS
        set_input_delay \
            -clock clk1 -max $T_SYNC_INPUT_MAX \
            $PROGRAM_SYNC_INPUTS
        set_input_delay \
            -clock clk1 -min $T_SYNC_INPUT_MIN \
            $PROGRAM_SYNC_INPUTS
    }

    rom {
        set_case_analysis 1 [get_ports load_en]
        set_case_analysis 0 [get_ports inst_write]
        set_case_analysis 0 [get_ports write_start]
    }
}

# -----------------------------------------------------------------------------
# Currently inactive/asynchronous peripheral inputs
# The corresponding peripheral block is not instantiated in the current RTL.
# Reclassify these ports and add their clocks/CDC constraints before enabling
# any of those interfaces.
# -----------------------------------------------------------------------------
set INACTIVE_ASYNC_INPUTS [get_ports {
    uart_rx
    spi_rstn
    cs_n_ext
    sclk_ext
    spi_di
    rx_dma_ack
    tx_dma_ack
    sda_ext
    scl_ext
}]
set_false_path -from $INACTIVE_ASYNC_INPUTS

# -----------------------------------------------------------------------------
# Output environment
# All current top-level outputs are constant in the active RTL, so associating
# them with clk1 would invent a false synchronous interface. Keep a realistic
# provisional capacitive load. If synchronous outputs are enabled later, use
# T_SYNC_OUTPUT_MAX/T_SYNC_OUTPUT_MIN as their default delay variables.
# -----------------------------------------------------------------------------
set CURRENT_OUTPUTS [all_outputs]
set_load $C_OUTPUT_LOAD $CURRENT_OUTPUTS

# -----------------------------------------------------------------------------
# Hold optimization request
# Final hold signoff still requires BC/FF libraries, CTS and min parasitics.
# -----------------------------------------------------------------------------
if {$ENABLE_FIX_HOLD} {
    set_fix_hold $SYS_CLK
}

echo "INFO: STA_MODE                  = $STA_MODE"
echo "INFO: clk1 period               = $T_CLKV_PER ns"
echo "INFO: clk1 setup/hold margin    = $T_CLK_SETUP_UNCERTAINTY / $T_CLK_HOLD_UNCERTAINTY ns"
echo "INFO: synchronous input max/min = $T_SYNC_INPUT_MAX / $T_SYNC_INPUT_MIN ns"
echo "INFO: reset release max/min     = $T_RESET_RELEASE_MAX / $T_RESET_RELEASE_MIN ns"
echo "INFO: output load               = $C_OUTPUT_LOAD pF"
echo "INFO: set_fix_hold enabled      = $ENABLE_FIX_HOLD"
echo "INFO: post-hold recovery        = $ENABLE_POST_HOLD_RECOVERY"
