//============================================================================
//  Atari G1 for MiSTer
//  g1_crt_osd.sv -- CRT Adjust OSD values -> the CRT stage in sys_top.v
//
//  The OSD stores each option as the INDEX into its list, so the signed
//  amounts are decoded from where each list wraps:
//      H-Size      0..+15,-16..-1  (32)   two's complement
//      H-Position  0..+48,-48..-1  (97)
//      V-Shift     0..+15, -5..-1  (21)   + = up; down stops at -5, where
//                                         VSync would reach the picture (G1's
//                                         front porch is 6 lines, plus 1 for
//                                         the stage's line buffer)
//      V-Size      0..+7,  -7..-1  (15)   + = taller; 3 lines per step
//
//  V-Size in PVM mode is limited on G1's 456 x 262 raster: taller by at most
//  2 steps (6 lines: the spare lines below the picture; at 2 steps the
//  picture also moves up 1 line to clear VSync), shorter by at most PVM_SHORT
//  steps (15 lines clean in simulation, 18 not). Beyond those, picture lines
//  are lost or wrap. Cabinet mode keeps the native timing and uses the full
//  range.
//
//  The stage assumes the native 8-clocks-per-pixel ratio, so it is held off
//  while the scandoubler runs.
//
//  Clock domain: clk_sys, sampled on ce_pix.
//============================================================================

`default_nettype none

module g1_crt_osd #(
    parameter int PVM_SHORT = 5              // PVM: shorter by at most this many steps (15 lines)
)(
    input  wire              clk,
    input  wire              ce_pix,
    input  wire              enable,        // OSD CRT Adjust On
    input  wire              scandoubler,   // Scandoubler Fx not None, or forced
    input  wire        [4:0] hsize_idx,
    input  wire        [6:0] hpos_idx,
    input  wire        [4:0] vshift_idx,
    input  wire        [3:0] vsize_idx,
    input  wire              cabinet,       // V-Size Mode: 0 PVM, 1 Cabinet

    output logic              crt_on,
    output logic signed [4:0] crt_hsize,    // + wider
    output logic signed [8:0] crt_hpos,     // + right, pixels
    output logic signed [5:0] crt_vshift,   // + up, lines
    output logic signed [5:0] crt_vsize,    // lines added per frame: - = taller
    output logic              crt_vsmode
);

    localparam logic signed [5:0] PVM_TALL  = 6'sd2;
    localparam logic signed [5:0] PVM_SHORT_S = 6'(PVM_SHORT);

    wire signed [8:0] hpos  = (hpos_idx <= 7'd48) ? $signed({2'b00, hpos_idx})
                                                  : $signed({2'b00, hpos_idx}) - 9'sd97;
    wire signed [5:0] vsh   = (vshift_idx <= 5'd15) ? $signed({1'b0, vshift_idx})
                                                    : $signed({1'b0, vshift_idx}) - 6'sd21;
    wire signed [5:0] vstep = (vsize_idx <= 4'd7) ? $signed({2'b00, vsize_idx})
                                                  : $signed({2'b00, vsize_idx}) - 6'sd15;

    wire signed [5:0] vstep_pvm = (vstep > PVM_TALL)      ? PVM_TALL
                                : (vstep < -PVM_SHORT_S)  ? -PVM_SHORT_S
                                :                           vstep;
    wire signed [5:0] vstep_use = cabinet ? vstep : vstep_pvm;
    wire              pvm_up    = ~cabinet & (vstep_use == PVM_TALL);

    always_ff @(posedge clk) begin
        if (ce_pix) begin
            crt_on     <= enable & ~scandoubler;
            crt_hsize  <= $signed(hsize_idx);
            crt_hpos   <= hpos;
            crt_vshift <= (pvm_up && vsh < 6'sd1) ? 6'sd1 : vsh;
            // The stage adds lines per frame (+ = shorter); OSD + means taller.
            crt_vsize  <= -(vstep_use + (vstep_use <<< 1));
            crt_vsmode <= cabinet;
        end
    end

endmodule
