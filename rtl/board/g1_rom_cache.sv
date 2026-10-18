//============================================================================
//  Atari G1 for MiSTer
//  g1_rom_cache.sv -- direct-mapped cache of 68000 program ROM words
//
//  The board answers a program ROM read with one wait state; an SDRAM read
//  through the shared arbiter takes two to seven. Holding recently read words
//  in block RAM lets most reads finish in the board's time. 4096 one-word
//  lines hit on about 88% of the games' reads outside their idle loops.
//
//  Keyed by the program-region word address after Slapstic banking, so each
//  bank's words are separate entries. The ROM never changes while the CPU
//  runs; every entry is cleared while reset is held (a download holds it) and
//  on flush, and no lookup hits until the clear has finished.
//
//  Lookup: lookup = 1 with the address; in the next clock hit and hit_data
//  are valid for that address, provided addr still holds it.
//
//  Clock domain: clk_sys
//============================================================================

`default_nettype none

module g1_rom_cache #(
    parameter int AW    = 18,          // word address width (512 KB)
    parameter int IDX_W = 12           // 2^IDX_W lines
)(
    input  wire           clk,
    input  wire           rst_n,
    input  wire           flush,         // start a clear (one clock is enough)

    input  wire           lookup,
    input  wire  [AW-1:0] addr,
    output logic          hit,
    output logic   [15:0] hit_data,

    input  wire           fill,
    input  wire  [AW-1:0] fill_addr,
    input  wire    [15:0] fill_data
);

    localparam int TAG_W = AW - IDX_W;
    localparam int ENT_W = 1 + TAG_W + 16;     // {valid, tag, data}
    localparam int LINES = 1 << IDX_W;

    // ramstyle: never built from registers, even when synthesis thinks block
    // RAM is short.
    (* ramstyle = "M10K" *) logic [ENT_W-1:0] mem [LINES];

    // Clear sweep: runs while reset is held and finishes afterwards if the
    // reset was shorter than a sweep. A flush restarts it.
    logic             clearing = 1'b0;
    logic [IDX_W-1:0] clr_idx  = '0;

    always_ff @(posedge clk) begin
        if (flush) begin
            clearing <= 1'b1;
            clr_idx  <= '0;
        end
        else if (!rst_n) begin
            clearing <= 1'b1;
            if (!clearing) clr_idx <= '0;
            else           clr_idx <= clr_idx + 1'b1;
        end
        else if (clearing) begin
            clr_idx <= clr_idx + 1'b1;
            if (&clr_idx) clearing <= 1'b0;
        end
    end

    wire             we    = clearing || fill;
    wire [IDX_W-1:0] waddr = clearing ? clr_idx : fill_addr[IDX_W-1:0];
    wire [ENT_W-1:0] wdata = clearing ? '0
                                      : {1'b1, fill_addr[AW-1:IDX_W], fill_data};

    logic [ENT_W-1:0] q;
    always_ff @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        q <= mem[addr[IDX_W-1:0]];
    end

    // The entry read last clock answers for addr only if addr has not moved.
    logic [AW-1:0] addr_l;
    logic          looked;
    always_ff @(posedge clk) begin
        addr_l <= addr;
        looked <= lookup && !clearing;
    end

    assign hit      = looked && !clearing && (addr == addr_l)
                   && q[ENT_W-1] && (q[16 +: TAG_W] == addr[AW-1:IDX_W]);
    assign hit_data = q[15:0];

endmodule

`default_nettype wire
