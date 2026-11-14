//============================================================================
//  Atari G1 for MiSTer
//  g1_pause.sv -- Pause: when to hold the game
//
//  FPGA-side only, no counterpart on the board.
//
//  Two things ask for a pause, and either is enough: the OSD menu being open
//  (when the OSD's "Pause when OSD open" is On), and the Pause button, which
//  toggles. The button is for capturing a clean picture: pressing it holds the
//  game with no OSD on the screen, pressing it again carries on. A press is a
//  rising edge of `btn`; the toggle is cleared by reset (rst_n low: a core
//  reset, an OSD Reset, a ROM download), so a reset never leaves the game
//  held with nothing on the screen to say why. Opening the OSD does not touch
//  it: a game paused with the button stays paused when the OSD closes.
//
//  freeze is what g1_ce uses to stop the 68000 and the JSA II enables, and
//  what the top level uses to hold back the VBLANK that sets IRQ1, ticks the
//  watchdog and lets the motion-object framebuffer erase. Video timing and
//  everything on the SDRAM side keep running, so the picture holds and the
//  OSD stays on a steady raster.
//
//  freeze rises only between bus cycles: on a clock where AS is negated AND
//  the 68000 is not being enabled, so AS cannot fall on that same edge (it
//  changes only on an enable). A cycle held half-way would leave write
//  strobes and the ROM/SDRAM request handshake asserted for as long as the
//  OSD is open (the palette, RAM and EEPROM writes are level strobes). The
//  wait is at most the length of one bus cycle plus any wait states.
//
//  It falls the clock the request drops, and it is forced low while rst_n is
//  low: the OSD's Reset buttons, a ROM download and the SDRAM self-test all
//  need the CPU enables to run (the 68000 only takes a reset on an enable).
//  If the OSD is still open when reset ends, freeze rises again at the next
//  gap between bus cycles, so a reset from the OSD stays paused at the start
//  of the game until the OSD closes.
//
//  osd_open is the framework's OSD_STATUS, which is already in the clk_sys
//  domain (sys_top's osd module runs on the core's clk_sys, exported through
//  HPS_BUS[36]); it is registered here once.
//
//  Clock domain: clk_sys
//============================================================================

`default_nettype none

module g1_pause (
    input  wire  clk,
    input  wire  rst_n,

    input  wire  enable,       // OSD: Pause when OSD open = On
    input  wire  osd_open,     // OSD_STATUS: the OSD menu is showing
    input  wire  btn,          // Pause button, level (any pad); a rising edge toggles
    input  wire  cpu_as_n,     // 68000 AS: high between bus cycles
    input  wire  cpu_ce,       // ce_cpu_p1 | ce_cpu_p2: the CPU steps on this edge

    output logic request,      // the pause is wanted (audio fades on this)
    output logic freeze        // the game is held (gates enables and frame events)
);

    logic btn_d, held;
    always_ff @(posedge clk) begin
        btn_d <= btn;
        if (!rst_n)              held <= 1'b0;
        else if (btn && !btn_d)  held <= ~held;
    end

    always_ff @(posedge clk) begin
        request <= (enable && osd_open) || held;

        if (!rst_n || !request) freeze <= 1'b0;
        else if (cpu_as_n && !cpu_ce) freeze <= 1'b1;
    end

endmodule

`default_nettype wire
