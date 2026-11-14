//============================================================================
//  Atari G1 for MiSTer
//  g1_pal_decode.sv -- one palette entry (IRGB-1555) to RGB888
//
//  Combinational. Two decodes, chosen by `mame` (the OSD's Color Palette):
//
//  Original (mame = 0): the game board's colour, fitted to footage of a real
//  board (tools/pcb_footage_fit.py; docs/PCB_COLOUR_FIT_NOTES.md). On the board
//  each channel is a 6-bit R2R DAC (D5-D1 the channel's five bits, D0 the shared
//  intensity bit) driving an emitter follower; a 5-input NOR of the five bits
//  clamps the base only when all five are zero (Pit Fighter manual, fig. 5-1,
//  docs/PITFIGHTER_MANUAL_NOTES.md). So a channel whose five bits are zero is
//  black whatever the intensity bit says, and everything else sits on a
//  pedestal. The fit takes L, the level the schematic's 14 % pedestal would
//  give the code,
//      L = round(255 * (0.14 + 0.86 * v6 / 63))   for v6 >= 2, else 0
//  (v6 = {the channel's five bits, intensity}), and maps it to what the footage
//  shows:
//      R = aR*L_R + bR + k*L_R^2
//      G = aG*L_G + bG + k*L_G^2 + mGR*L_R + mGB*L_B
//      B = aB*L_B + bB + k*L_B^2 + mBG*L_G
//  clamped to 0..255; a channel whose five bits are zero stays black, cross
//  terms or not. The cross terms are there because the footage's green and
//  blue are not a function of themselves alone: without them the neutral grey
//  pillars come out about 5 levels too green. In tables: each term is a
//  64-entry lookup of the channel's 6-bit value, so there are no multipliers,
//  and the output is the clamped sum of three (G), two (B) or one (R) of them.
//  Against MAME this is darker (white is about R 190, G 188, B 195), has a
//  lower pedestal (the first step is R 20, G 27, B 19) and a softer top end.
//  It is a fit to one compressed frame, so it holds the capture chain as well
//  as the board.
//
//  MAME (mame = 1): MAME's raw_to_rgb_converter::IRRRRRGGGGGBBBBB_decoder.
//  The intensity bit is the shared LSB of three 6-bit channels, not a
//  brightness flag:
//      r6 = { entry[14:10], i }   g6 = { entry[9:5], i }   b6 = { entry[4:0], i }
//  pal6bit then expands 6 bits to 8 by repeating the top two: { x, x[5:4] }.
//  $7C00 -> R = $FB (r6 = 62), $FC00 -> R = $FF (r6 = 63).
//
//  The tables are generated, not hand-typed: sim/pal_curve_check.py computes
//  them from the formulas and coefficients above, compares this module against
//  them for all 65,536 entries in every mode, and fails if any table below
//  differs from its formula.
//============================================================================

`default_nettype none

module g1_pal_decode (
    input  wire [15:0] entry,     // palette entry, IRGB-1555
    input  wire        mame,      // 0 = Original (fitted to footage), 1 = MAME's linear decode
    output logic [7:0] r,
    output logic [7:0] g,
    output logic [7:0] b
);

    // Original: 12-bit two's-complement entries, T[12*v6 +: 12], entry 63 the
    // top 12 bits, with L = round(255 * (0.14 + 0.86 * v6 / 63)) (v6 >= 2):
    //   O_c = round(a_c * L + b_c + k * L^2)    the channel's own term
    //   X_cd = round(m_cd * L)                  channel d's term into channel c
    // All are 0 for v6 = 0 and 1.
    localparam logic [767:0] T_OR =
        768'h0BE0BB0B80B60B30B10AE0AB0A80A60A30A109E09B09809609309108D08B08808608208007D07B07707507306F06D06A06706406205F05C05905705305104E04B04804504204003C03A03703403102E02C02802602202001D01A017014000000;
    localparam logic [767:0] T_OG =
        768'h08B08A08808608408308007F07D07B07907707507407207006E06C06A06806606406206105E05D05B05905705505305104F04D04B04904704504304103F03D03B03903703503303002F02C02A02802602402202001E01C01A018015013000000;
    localparam logic [767:0] T_OB =
        768'h0DE0DB0D80D50D20CF0CB0C90C50C20BF0BC0B90B60B20AF0AC0A90A50A309F09C09909609208F08C08908608208007C07907507306F06C06806506205F05B05805405104E04B04704404003D03903603403002D02902602201F01B018000000;
    localparam logic [767:0] T_XGR =
        768'h02602502502402402302302202202102102002001F01F01E01E01D01D01C01C01B01A01A01901901801801701701601601501501401401301301201201101101001000F00F00E00E00D00C00C00B00B00B00A00A009008008007007006000000;
    localparam logic [767:0] T_XGB =
        768'h00B00A00A00A00A00A00A00A009009009009009009009008008008008008008008007007007007007007007006006006006006006006005005005005005005005004004004004004004003003003003003003003002002002002002002000000;
    localparam logic [767:0] T_XBG =
        768'hFE5FE6FE6FE6FE7FE7FE7FE8FE8FE9FE9FE9FEAFEAFEAFEBFEBFEBFECFECFEDFEDFEDFEEFEEFEEFEFFEFFEFFF0FF0FF1FF1FF1FF2FF2FF2FF3FF3FF4FF4FF4FF5FF5FF5FF6FF6FF6FF7FF7FF8FF8FF8FF9FF9FF9FFAFFAFFAFFBFFBFFB000000;

    wire       i_bit = entry[15];
    wire [4:0] r5    = entry[14:10];
    wire [4:0] g5    = entry[9:5];
    wire [4:0] b5    = entry[4:0];
    wire [5:0] r6    = {r5, i_bit};
    wire [5:0] g6    = {g5, i_bit};
    wire [5:0] b6    = {b5, i_bit};

    // Original: the clamped sums. A channel with all five bits zero (v6 < 2)
    // is black; the table entries for those codes are 0, so they add nothing to
    // the other channels either.
    wire signed [11:0] o_r  = T_OR [12*r6 +: 12];
    wire signed [11:0] o_g  = T_OG [12*g6 +: 12];
    wire signed [11:0] o_b  = T_OB [12*b6 +: 12];
    wire signed [11:0] x_gr = T_XGR[12*r6 +: 12];
    wire signed [11:0] x_gb = T_XGB[12*b6 +: 12];
    wire signed [11:0] x_bg = T_XBG[12*g6 +: 12];

    wire signed [12:0] sum_r = {o_r[11], o_r};
    wire signed [12:0] sum_g = o_g + x_gr + x_gb;
    wire signed [12:0] sum_b = o_b + x_bg;

    wire [7:0] foot_r = (r6[5:1] == 5'd0) ? 8'd0 : sum_r[12] ? 8'd0 : (sum_r > 13'sd255) ? 8'd255 : sum_r[7:0];
    wire [7:0] foot_g = (g6[5:1] == 5'd0) ? 8'd0 : sum_g[12] ? 8'd0 : (sum_g > 13'sd255) ? 8'd255 : sum_g[7:0];
    wire [7:0] foot_b = (b6[5:1] == 5'd0) ? 8'd0 : sum_b[12] ? 8'd0 : (sum_b > 13'sd255) ? 8'd255 : sum_b[7:0];

    always_comb begin
        if (mame) begin
            r = {r6, r6[5:4]};
            g = {g6, g6[5:4]};
            b = {b6, b6[5:4]};
        end else begin
            r = foot_r;
            g = foot_g;
            b = foot_b;
        end
    end

endmodule

`default_nettype wire
