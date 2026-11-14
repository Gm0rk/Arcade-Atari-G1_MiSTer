//============================================================================
//  Atari G1 for MiSTer
//  g1_audio_fade.sv -- fade the audio out and in around a pause
//
//  FPGA-side only, no counterpart on the board.
//
//  While the game is held (g1_pause) the YM2151 and OKI6295 stop clocking and
//  their last samples stay on the output, a steady offset that would click
//  as it began and again as it ended. The gain here runs 256 -> 0 when mute
//  rises and back when it falls, one step every 4096 clk_sys (71.5 us), so
//  18.3 ms each way.
//
//  The gain powers up at 256 and is not reset. At 256 the output is the input
//  exactly (x * 256 >> 8), one clock late, so with the option off the audio
//  is unchanged. mute falls on the request, before the game is held, and the
//  fade back up starts as the sound board is released, so it is silent while
//  the OSD is open and returns smoothly.
//
//  Clock domain: clk_sys
//============================================================================

`default_nettype none

module g1_audio_fade (
    input  wire               clk,
    input  wire               mute,
    input  wire signed [15:0] in_l,
    input  wire signed [15:0] in_r,
    output logic signed [15:0] out_l,
    output logic signed [15:0] out_r
);

    logic [11:0] div  = 12'd0;
    logic [8:0]  gain = 9'd256;      // 0 = silent, 256 = unity

    always_ff @(posedge clk) begin
        div <= div + 1'b1;
        if (div == 12'd0) begin
            if (mute  && gain != 9'd0)   gain <= gain - 1'b1;
            if (!mute && gain != 9'd256) gain <= gain + 1'b1;
        end
    end

    // |in| <= 2^15 and gain <= 2^8, so the product fits 25 bits signed and
    // bits [23:8] are in * gain / 256 exactly (floor).
    wire signed [9:0]  g   = {1'b0, gain};
    wire signed [25:0] p_l = in_l * g;
    wire signed [25:0] p_r = in_r * g;

    always_ff @(posedge clk) begin
        out_l <= p_l[23:8];
        out_r <= p_r[23:8];
    end

endmodule

`default_nettype wire
