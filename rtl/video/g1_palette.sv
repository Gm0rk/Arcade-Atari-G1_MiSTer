//============================================================================
//  Atari G1 for MiSTer
//  g1_palette.sv -- 1280-entry palette RAM, IRGB-1555 to RGB888
//
//  The conversion is g1_pal_decode.sv: the Original colour (the game board,
//  fitted to footage) or MAME's linear decode (curve_mame).
//
//  CPU $FE8000-$FE89FF: 1280 16-bit entries in MAME palette format IRGB_1555.
//  Dual-port BRAM: port A is the 68000 (read/write, byte lanes), port B the
//  video scan-out (read only). A CPU write and a video read of the same entry
//  in one cycle return the old value to the video port.
//
//  Clock domain: clk_sys (both ports).
//============================================================================

`default_nettype none

module g1_palette
    import g1_pkg::*;
(
    input  wire                  clk,

    // OSD "Color Palette": 0 = Original (the board, fitted to footage), 1 = MAME's
    // linear decode (g1_pal_decode.sv). Switches live; it only selects the table.
    input  wire                  curve_mame,

    // ---- Port A: 68000 -----------------------------------------------------
    input  wire [PAL_AW-1:0]     cpu_addr,    // entry index 0..1279 (word address)
    input  wire [15:0]           cpu_din,
    input  wire                  cpu_wr_hi,   // write D[15:8]  (68000 /UDS)
    input  wire                  cpu_wr_lo,   // write D[7:0]   (68000 /LDS)
    output logic [15:0]          cpu_dout,

    // ---- Port B: video scan-out -------------------------------------------
    // vid_r/g/b and vid_raw follow vid_index by two clocks (BRAM, conversion).
    input  wire [PAL_AW-1:0]     vid_index,
    output logic [7:0]           vid_r,
    output logic [7:0]           vid_g,
    output logic [7:0]           vid_b,
    output logic [15:0]          vid_raw      // raw entry (unused)
);

    // Clocks from vid_index to vid_r/g/b.
    localparam int VID_LATENCY = 2;

    //------------------------------------------------------------------------
    // Storage: two byte-wide arrays, so Quartus infers the CPU byte enables
    // reliably.
    //------------------------------------------------------------------------
    logic [7:0] ram_hi [PAL_ENTRIES];
    logic [7:0] ram_lo [PAL_ENTRIES];

    logic [7:0] cpu_q_hi, cpu_q_lo;
    logic [7:0] vid_q_hi, vid_q_lo;

    // Port A: CPU read/write.
    always_ff @(posedge clk) begin
        if (cpu_wr_hi) ram_hi[cpu_addr] <= cpu_din[15:8];
        if (cpu_wr_lo) ram_lo[cpu_addr] <= cpu_din[7:0];
        cpu_q_hi <= ram_hi[cpu_addr];
        cpu_q_lo <= ram_lo[cpu_addr];
    end

    assign cpu_dout = {cpu_q_hi, cpu_q_lo};

    // Port B: video read.
    always_ff @(posedge clk) begin
        vid_q_hi <= ram_hi[vid_index];
        vid_q_lo <= ram_lo[vid_index];
    end

    wire [15:0] entry = {vid_q_hi, vid_q_lo};

    //------------------------------------------------------------------------
    // IRGB-1555 to RGB888 (g1_pal_decode.sv)
    //------------------------------------------------------------------------
    wire [7:0] dec_r, dec_g, dec_b;

    g1_pal_decode u_dec
    (
        .entry (entry),
        .mame  (curve_mame),
        .r     (dec_r),
        .g     (dec_g),
        .b     (dec_b)
    );

    always_ff @(posedge clk) begin
        vid_r   <= dec_r;
        vid_g   <= dec_g;
        vid_b   <= dec_b;
        vid_raw <= entry;
    end

`ifdef SIMULATION
    // Reference values from MAME's decoder: $7C00 -> R = $FB (r6 = 62),
    // $FC00 -> R = $FF (r6 = 63). sim/pal_curve_check.py checks every entry.
    initial begin
        $display("g1_palette: decode is g1_pal_decode; "
                 "verify $7C00 -> R=0xFB and $FC00 -> R=0xFF in the testbench");
    end
`endif

endmodule

`default_nettype wire
