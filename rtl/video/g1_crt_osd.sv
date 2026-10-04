//============================================================================
//  Atari G1 for MiSTer
//  g1_crt_osd.sv -- CRT Adjust OSD values -> the CRT stage in sys_top.v
//
//  The OSD stores each option as the INDEX into its list, so the signed
//  amounts are decoded from where each list wraps:
//      H-Size      0..+15,-16..-1  (32)   two's complement
//      H-Position  0..+48,-48..-1  (97)
//      V-Shift     0..+15, -5..-1  (21)   + = up; down stops at -5, where
//                                         VSync would reach the picture
//      V-Size      0..+7,  -7..-1  (15)   + = taller; 3 lines per step
//
//  The stage reads one source dot every (BASE + H-Size) eighths of a clk_sys
//  cycle; BASE = 64 is G1's native 8 clocks per dot. Three things are added
//  to the OSD amounts so that the stage works outward from the centred
//  picture (H_FRONT in g1_pkg.sv puts its middle where a standard 15 kHz
//  source's is):
//    - Auto-Width: H-Size AW_HSIZE more, the step that makes the 336-dot
//      picture closest to AW_E8 / 458.18 us wide (48.75 us, about 93% of a
//      52.66 us broadcast line). The OSD H-Size trims from there.
//    - H-Size about the middle: the stage stretches each line from HSync, so
//      the picture's middle, MID dots after the HSync edge, would move right.
//      H-Position gets round(-MID x H / (BASE + H)) read dots to hold it.
//    - On at 0 = Off: the stage's read pipeline adds a dot (H-Position -1)
//      and its line buffer a line (V-Shift +1).
//
//  V-Size in PVM mode is limited on G1's 456 x 262 raster: taller by at most
//  2 steps (6 lines: the spare lines below the picture; at 2 steps the
//  picture must sit at least a line up to clear VSync), shorter by at most
//  PVM_SHORT steps (15 lines clean in simulation, 18 not). Beyond those,
//  picture lines are lost or wrap. Cabinet mode keeps the native timing and
//  uses the full range.
//
//  The stage assumes the native 8-clocks-per-pixel ratio, so it is held off
//  while the scandoubler runs.
//
//  Clock domain: clk_sys, sampled on ce_pix.
//============================================================================

`default_nettype none

module g1_crt_osd
    import g1_pkg::*;
#(
    parameter int PVM_SHORT = 5              // PVM: shorter by at most this many steps (15 lines)
)(
    input  wire              clk,
    input  wire              ce_pix,
    input  wire              enable,        // OSD CRT Adjust On
    input  wire              autowidth,     // OSD CRT Auto-Width On
    input  wire              scandoubler,   // Scandoubler Fx not None, or forced
    input  wire        [4:0] hsize_idx,
    input  wire        [6:0] hpos_idx,
    input  wire        [4:0] vshift_idx,
    input  wire        [3:0] vsize_idx,
    input  wire              cabinet,       // V-Size Mode: 0 PVM, 1 Cabinet

    output logic              crt_on,
    output logic signed [4:0] crt_hsize,    // + wider
    output logic signed [8:0] crt_hpos,     // + right, read dots
    output logic signed [5:0] crt_vshift,   // + up, lines
    output logic signed [5:0] crt_vsize,    // lines added per frame: - = taller
    output logic              crt_vsmode
);

    localparam int BASE = 64;

    // Auto-Width target in eighth-clocks: 48.75 us x 8 x 57.272724 MHz.
    localparam int AW_E8    = 22336;
    localparam int AW_HSIZE = (AW_E8 + H_VISIBLE / 2) / H_VISIBLE - BASE;

    // Middle of the picture after the HSync leading edge, in dots.
    localparam int MID = H_TOTAL - (H_VISIBLE + H_FRONT) + H_VISIBLE / 2;

    // HMID[h + 16] = round(-MID x h / (BASE + h)) for H-Size h = -16..+15.
    function automatic logic [32*9-1:0] hmid_table();
        logic [32*9-1:0] t;
        int h, num, den, q;
        t = '0;
        for (int i = 0; i < 32; i++) begin
            h   = i - 16;
            num = MID * h;
            den = BASE + h;
            q   = (num >= 0) ? (num + den / 2) / den : -((-num + den / 2) / den);
            t[i*9 +: 9] = 9'(-q);
        end
        return t;
    endfunction
    localparam logic [32*9-1:0] HMID = hmid_table();

    localparam logic signed [5:0] PVM_TALL    = 6'sd2;
    localparam logic signed [5:0] PVM_SHORT_S = 6'(PVM_SHORT);

    wire signed [8:0] hpos  = (hpos_idx <= 7'd48) ? $signed({2'b00, hpos_idx})
                                                  : $signed({2'b00, hpos_idx}) - 9'sd97;
    wire signed [5:0] vsh   = (vshift_idx <= 5'd15) ? $signed({1'b0, vshift_idx})
                                                    : $signed({1'b0, vshift_idx}) - 6'sd21;
    wire signed [5:0] vstep = (vsize_idx <= 4'd7) ? $signed({2'b00, vsize_idx})
                                                  : $signed({2'b00, vsize_idx}) - 6'sd15;

    // H-Size: the OSD amount plus Auto-Width, within the stage's -16..+15.
    wire signed [6:0] h_sum = $signed({{2{hsize_idx[4]}}, hsize_idx})
                            + (autowidth ? 7'(AW_HSIZE) : 7'sd0);
    wire signed [4:0] h_eff = (h_sum > 7'sd15)  ? 5'sd15
                            : (h_sum < -7'sd16) ? -5'sd16
                            :                     h_sum[4:0];
    wire        [4:0] h_i   = {~h_eff[4], h_eff[3:0]};           // h_eff + 16
    wire signed [8:0] hmid  = $signed(HMID[h_i*9 +: 9]);

    wire signed [5:0] vstep_pvm = (vstep > PVM_TALL)      ? PVM_TALL
                                : (vstep < -PVM_SHORT_S)  ? -PVM_SHORT_S
                                :                           vstep;
    wire signed [5:0] vstep_use = cabinet ? vstep : vstep_pvm;
    wire              pvm_up    = ~cabinet & (vstep_use == PVM_TALL);
    wire signed [5:0] vsh_line  = vsh + 6'sd1;                   // the buffer's line

    always_ff @(posedge clk) begin
        if (ce_pix) begin
            crt_on     <= enable & ~scandoubler;
            crt_hsize  <= h_eff;
            crt_hpos   <= hpos + hmid - 9'sd1;                    // the pipeline's dot
            crt_vshift <= (pvm_up && vsh_line < 6'sd1) ? 6'sd1 : vsh_line;
            // The stage adds lines per frame (+ = shorter); OSD + means taller.
            crt_vsize  <= -(vstep_use + (vstep_use <<< 1));
            crt_vsmode <= cabinet;
        end
    end

endmodule
