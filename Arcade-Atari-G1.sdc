# ===========================================================================
#  Atari G1 for MiSTer
#  Arcade-Atari-G1.sdc -- timing constraints specific to this core
#
#  sys/sys_top.sdc supplies the framework constraints (CLK_50M, HPS, video
#  output, PLL clock groups). This file adds the SDRAM interface, multicycle
#  paths for clock-enabled logic, and false paths for static configuration.
#
#  After a compile, check hold slack on every SDRAM read-return path, not
#  just the summary: a small negative hold there passes most reads and
#  corrupts a few (report commands at the end of this file).
# ===========================================================================

# ---------------------------------------------------------------------------
#  Derived clocks
# ---------------------------------------------------------------------------
#  clk_sys =  57.272724 MHz = 4 x the 14.318181 MHz master oscillator
#  clk_ram = 114.545448 MHz = 2 x clk_sys
#
#  The exact 2:1 ratio from one PLL makes the SDRAM crossing synchronous.
#  Moving clk_ram to an unrelated frequency needs real CDC synchronisers.
#
#  Do not call derive_pll_clocks or derive_clock_uncertainty here:
#  sys/sys_top.sdc already does both. A second call creates duplicate clock
#  objects and the constraints below apply to only one copy. sys_top.sdc also
#  puts all outputs of this PLL in one clock group, so clk_sys and clk_ram are
#  analysed against each other, as they must be.
# ---------------------------------------------------------------------------

set clk_sys {*|pll|pll_inst|altera_pll_i|*[0].*|divclk}
set clk_ram {*|pll|pll_inst|altera_pll_i|*[1].*|divclk}

# ---------------------------------------------------------------------------
#  SDRAM clock
# ---------------------------------------------------------------------------
#  SDRAM_CLK comes from PLL output 2, phase-shifted 6052 ps (249.5 degrees,
#  -110.5; it was 6548 ps, -90 degrees, up to build 161: build 162 moved it
#  0.496 ns earlier to clear the output hold failures, -0.347 ns worst, that
#  the Fitter had no delay left to fix). The delay figures below are the
#  standard MiSTer values for a -7 grade 32 MB module.
#
#  -source names an internal PLL node, so get_pins needs -compatibility_mode
#  (as in sys_top.sdc). Without it the collection is empty, the clock is not
#  created, and every SDRAM delay constraint that references it is dropped.
#  The guard reports that case in the compilation messages.
#
#  A collection is a handle, not a list: llength is 1 even when it holds
#  nothing, so a guard written with llength never fires. g1_count asks
#  get_collection_size instead, and returns -1 where that is not available;
#  the tests below treat -1 as "not known", which for the clock means create it.
# ---------------------------------------------------------------------------
proc g1_count {collection} {
    if {[catch {get_collection_size $collection} count]} {
        return -1
    }
    return $count
}

if {[g1_count [get_clocks -nowarn SDRAM_CLK_pin]] <= 0} {
    create_generated_clock -name SDRAM_CLK_pin \
        -source [get_pins -compatibility_mode {*|pll|pll_inst|altera_pll_i|*[2].*|divclk}] \
        [get_ports SDRAM_CLK]

    if {[g1_count [get_clocks -nowarn SDRAM_CLK_pin]] == 0} {
        puts "ERROR (Arcade-Atari-G1.sdc): SDRAM_CLK_pin was NOT created --\
the -source pattern matched no pin. Every SDRAM I/O delay below this point\
will silently fail too. Check the pattern against the actual PLL instance\
name in the CLOCKS section of a timing report."
    }
}

# ---------------------------------------------------------------------------
#  SDRAM read data
# ---------------------------------------------------------------------------
#  Brace every get_ports/get_pins pattern that contains '[', even a single
#  port: an unbraced SDRAM_DQ[*] is a Tcl command substitution, and the error
#  aborts every constraint after it.
#
#  What the Timing Analyzer sees (build 157 compile of 2026-11-13; the only
#  delay model is Slow 1100 mV 100 C, TIMEQUEST_MULTICORNER_ANALYSIS is OFF in
#  the .qsf, so no fast-corner hold is checked; worst of the 16 data bits).
#  (All figures in this table are from the compiles up to build 161, with
#  SDRAM_CLK_pin 6.548 ns after clk_ram; build 162 moved it to 6.052 ns, so the
#  figures that depend on that edge move by 0.496 ns.)
#  SDRAM_CLK_pin is PLL output 2 at 270 degrees: 6.548 ns after clk_ram, and
#  its clock path to the pin is about 6.2 ns longer than clk_ram's to the
#  registers (clock skew -6.2 ns). Left alone, STA captures the data at the
#  first clk_ram edge after the SDRAM clock edge (2.182 ns later for a rising
#  edge, 6.547 ns for a falling one). sdram.sv samples later than that, one
#  or two clocks, so that default is the wrong question and fails by 8 to 17 ns:
#
#      SDRAM_DQ -> dq_negedge   falling edge, in the I/O cell (settings S4-S7)
#          default (1 cycle)    setup  -8.149   hold  +9.116
#          -setup 2             setup  +0.581   hold  +0.386   <- used below
#          -setup 3             setup  +9.311   hold  -8.344
#      SDRAM_DQ -> dout         rising edge, straight into the core (S0-S3)
#          default (1 cycle)    setup -17.378   hold +15.303
#          -setup 2             setup  -8.648   hold  +6.573
#          -setup 3             setup  +0.082   hold  -2.157
#
#  Setup plus hold of one bit is the same at every cycle count, so it says
#  whether any count can pass both: 1.35 to 1.38 ns for the falling paths
#  (yes: 2), 0.77 to 1.04 ns for 13 of the rising paths (no: the window sits
#  between two rising edges) and -0.7 to -0.9 ns for DQ4, DQ8 and DQ11 (no
#  count can). The rising paths are 3.8 to 6.6 ns of core routing from the pad
#  to the register; the falling ones end in the I/O cell.
#
#  Fitter placement moves the real window between compiles, so by default the
#  core's boot-time self-test measures all eight settings and uses the best.
#  That measurement is what checks the rising settings; STA cannot.
# ---------------------------------------------------------------------------
set_input_delay  -clock SDRAM_CLK_pin -max 6.4 [get_ports {SDRAM_DQ[*]}]
set_input_delay  -clock SDRAM_CLK_pin -min 3.2 [get_ports {SDRAM_DQ[*]}]

# ---------------------------------------------------------------------------
#  SDRAM read capture
# ---------------------------------------------------------------------------
#  Falling edge (dq_negedge, settings S4-S7): the data an SDRAM clock edge
#  launches is first stable at the SECOND falling clk_ram edge after it. That
#  is t9.5, setting S6, inside the window the self-test measured on hardware
#  (S5, S1, S6, S2 clean in build 111). It is the one falling edge this checks:
#  S4 (t7.5, the CAP_DEFAULT used before the self-test), S5 and S7 sample the
#  same register at other edges and are not verified here.
#
#  Setup 2 AND hold 1 (build 161). Build 159 and 160 gave -setup 2 alone, so
#  the hold check moved one clock later with it, to the edge that really
#  matters (the previous word is still being captured at the first falling
#  edge). The build 160 compile showed what that did: the Fitter put 3 to 11
#  steps of D1 and 2 of D3 input delay chain on every SDRAM_DQ pin (the Fitter
#  report's Delay Chain Summary: all zero in build 157), about 2.45 ns more data
#  delay, and TimeQuest then read setup -1.746 ns and hold +2.793 ns on the same
#  16 endpoints. The chains also move when the core samples SDRAM, which no
#  hardware test has covered. -hold 1 puts the hold check back where it was in
#  every build up to 157, on the same edge as one cycle would, so the Fitter has
#  nothing to fix. The cost: STA no longer checks that the previous word is
#  gone before the next arrives; on the build 157 numbers that margin was
#  +0.386 ns (slow model only), and the self-test measures the real window.
#
#  Rising edge (SDRAM_DQ straight into dout, settings S0-S3): see the table.
#  No cycle count passes setup and hold together, so STA would report these 16
#  paths failing at any count, whatever the hardware does (S1 and S2 were clean
#  in build 111). They are a false path, as rd_phase_q is below: the boot-time
#  self-test is their only check. If it picks S0-S3, nothing in the timing
#  report covers the running capture. Registering the data in the I/O cell
#  instead (as the falling settings do) would make them checkable; that is an
#  RTL change, not an SDC one.
#
#  Both are skipped, with a warning, when either clock is missing: an empty
#  collection in a constraint is an error that drops every constraint after it.
# ---------------------------------------------------------------------------
set g1_rd_src [get_clocks -nowarn SDRAM_CLK_pin]
set g1_rd_dst [get_clocks -nowarn $clk_ram]
if {[g1_count $g1_rd_src] == 0 || [g1_count $g1_rd_dst] == 0} {
    puts "WARNING (Arcade-Atari-G1.sdc): SDRAM_CLK_pin or the clk_ram clock\
was not found -- the SDRAM read-capture multicycle and false path are skipped,\
so the read paths are analysed as one cycle and will fail."
} else {
    set_multicycle_path -setup -end 2 -from $g1_rd_src -fall_to $g1_rd_dst
    set_multicycle_path -hold  -end 1 -from $g1_rd_src -fall_to $g1_rd_dst
    set_false_path -from $g1_rd_src -rise_to $g1_rd_dst
}

# ---------------------------------------------------------------------------
#  SDRAM outputs
# ---------------------------------------------------------------------------
#  Applied per port group. If get_ports is given a list in which any name
#  matches nothing (for example a pin Quartus removed because the RTL drives
#  it with a constant), the whole call fails and every port in the list loses
#  its constraint. Per group, a missing port costs only that group, and it is
#  reported.
# ---------------------------------------------------------------------------
foreach sdram_grp {
    {SDRAM_A[*]}
    {SDRAM_BA[*]}
    {SDRAM_DQ[*]}
    {SDRAM_DQML}
    {SDRAM_DQMH}
    {SDRAM_nCS}
    {SDRAM_nRAS}
    {SDRAM_nCAS}
    {SDRAM_nWE}
    {SDRAM_CKE}
} {
    set grp_ports [get_ports -nowarn $sdram_grp]
    if {[g1_count $grp_ports] == 0} {
        puts "WARNING (Arcade-Atari-G1.sdc): no port matches $sdram_grp --\
skipping its output delay. If this is nCS or CKE, the signal has probably\
been optimised away as a constant in sdram.sv."
    } else {
        set_output_delay -clock SDRAM_CLK_pin -max  1.5 $grp_ports
        set_output_delay -clock SDRAM_CLK_pin -min -0.8 $grp_ports
    }
}

# ---------------------------------------------------------------------------
#  Multicycle paths
# ---------------------------------------------------------------------------
#  Everything runs on clk_sys with clock enables, so logic that advances only
#  on an enable has several clocks to settle. Claim a multicycle only where
#  the enable rate is guaranteed: a wrong one passes timing analysis and
#  fails on hardware.
# ---------------------------------------------------------------------------

#  68000: ce_cpu_p1/p2 are 2 clk_sys cycles apart at 14.318 MHz. The OSD's
#  7.159 MHz setting only relaxes this.
set_multicycle_path -from [get_registers {*u_cpu|*}] -to [get_registers {*u_cpu|*}] -setup -end 2
set_multicycle_path -from [get_registers {*u_cpu|*}] -to [get_registers {*u_cpu|*}] -hold  -end 1

#  JSA II 6502 at 1.79 MHz: 32 clk_sys cycles per enable. Only 8 are claimed,
#  leaving margin if the enable generator changes.
set_multicycle_path -from [get_registers {*u_jsa2|u_cpu|*}] -to [get_registers {*u_jsa2|u_cpu|*}] -setup -end 8
set_multicycle_path -from [get_registers {*u_jsa2|u_cpu|*}] -to [get_registers {*u_jsa2|u_cpu|*}] -hold  -end 7

#  RLE scaler: the divider and multiplier run once per object, at most every
#  few hundred clocks. They are the widest arithmetic in the core.
set_multicycle_path -from [get_registers {*u_rle|u_scaler|*}] -to [get_registers {*u_rle|u_scaler|*}] -setup -end 2
set_multicycle_path -from [get_registers {*u_rle|u_scaler|*}] -to [get_registers {*u_rle|u_scaler|*}] -hold  -end 1

# ---------------------------------------------------------------------------
#  False paths
# ---------------------------------------------------------------------------
#  SDRAM capture setting: rd_phase/rd_half come from clk_sys (the self-test
#  sweep or the OSD) and change only between accesses. sdram.sv registers
#  them on clk_ram as rd_phase_q/rd_half_q.
set_false_path -to [get_registers {*u_sdram|rd_phase_q*}]
set_false_path -to [get_registers {*u_sdram|rd_half_q*}]
#  MRA configuration: latched once during the ROM download, static after.
#  It fans out widely (Slapstic type, clip window, descriptor fields).
set_false_path -from [get_registers {*u_loader|cfg_bytes*}]

#  OSD status bits change only when the user opens the menu.
set_false_path -from [get_registers {*hps_io*|status*}]

# ---------------------------------------------------------------------------
#  Checking the SDRAM paths
# ---------------------------------------------------------------------------
#  After a fit, run these in the TimeQuest console:
#
#     report_timing -hold -npaths 50 -detail full_path \
#         -to [get_ports {SDRAM_DQ[*]}]
#     report_timing -hold -npaths 50 -detail full_path \
#         -from [get_ports {SDRAM_DQ[*]}]
# ---------------------------------------------------------------------------
