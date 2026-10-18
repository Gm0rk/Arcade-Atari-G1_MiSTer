//============================================================================
//  Atari G1 for MiSTer
//  g1_cpu_timing.sv -- 68000 DTACK with the game board's wait states
//
//  The board ends every 68000 bus cycle through a wait-state counter (game
//  PCB 045977, 95D 74F163 and 105C): it loads when AS is seen, counts CPU
//  clocks to its terminal count, and DTACK follows half a clock later. The
//  preset depends on the device, so each access gets a fixed number of wait
//  states (one wait state = one 14.318 MHz CPU clock):
//
//    $FE0000-$FE7FFF        0   DTACK straight from the daughter-card select
//    $FC8000, $FD8000       3   ADC / IN1 and EEPROM
//    work RAM ($F7, $FF)    1 + up to 7: the counter only loads in the CPU's
//                               RAM slot, one CPU clock in eight, shared with
//                               the video
//    everything else        1   program ROM, palette, I/O
//
//  MAME has no wait states, and neither does the Fast setting here: DTACK as
//  soon as the data is there.
//
//  fx68k samples DTACK on a PHI2 enable; DTACK asserted once PHASE0 phase
//  enables have passed since AS fell still gives a zero-wait cycle, and each
//  wait state is two more. A ROM word that is not yet back from the cache or
//  SDRAM holds DTACK off longer, so the CPU never sees fewer wait states than
//  the board, only more on a cache miss.
//
//  The interrupt acknowledge (VPA autovector on the board) ends at once.
//
//  Clock domain: clk_sys
//============================================================================

`default_nettype none

module g1_cpu_timing #(
    parameter int PHASE0   = 2,       // last zero-wait DTACK point, in phases
    parameter int RAM_SLOT = 0        // CPU clock (mod 8) of the RAM slot
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ce_cpu_p1,     // the 68000's phase enables
    input  wire        ce_cpu_p2,
    input  wire        fast,          // OSD: no board wait states (MAME)

    input  wire        as_n,
    input  wire [23:1] addr,
    input  wire        iack,
    input  wire        rom_sel,       // the data comes from the ROM path
    input  wire        rom_have,      // ... and is ready

    output logic       dtack_n
);

    // CPU clocks, modulo the RAM slot period.
    logic [2:0] clk8;
    always_ff @(posedge clk) begin
        if (!rst_n)         clk8 <= 3'd0;
        else if (ce_cpu_p1) clk8 <= clk8 + 3'd1;
    end

    logic as_n_d;
    always_ff @(posedge clk) as_n_d <= as_n;
    wire cyc_start = as_n_d && !as_n;

    //------------------------------------------------------------------------
    // Wait states by address, as the board decodes them (A19 is not decoded:
    // work RAM also answers at $F70000).
    //------------------------------------------------------------------------
    wire       io     = (addr[23:20] == 4'hF) && addr[18];
    wire [2:0] slot   = addr[17:15];
    wire       w_ram  = io && addr[17] && addr[16];
    wire       w_none = io && (slot == 3'b100);                     // $FE0000
    wire       w_slow = io && (slot == 3'b001 || slot == 3'b011);   // $FC8000, $FD8000

    // RAM: the counter loads at the first CPU clock edge in the slot, from the
    // clock after AS on; that edge is one wait state, each clock before it one
    // more.
    wire [2:0] ram_wait = 3'(RAM_SLOT) - clk8 - 3'd1;

    logic [3:0] waits;
    always_comb begin
        if (iack || w_none)  waits = 4'd0;
        else if (w_slow)     waits = 4'd3;
        else if (w_ram)      waits = 4'd1 + {1'b0, ram_wait};
        else                 waits = 4'd1;
    end

    // Phase enables since AS fell, and the count at which DTACK is due.
    logic [4:0] ph, due_at;
    always_ff @(posedge clk) begin
        if (cyc_start) begin
            ph     <= 5'd0;
            due_at <= 5'(PHASE0) + {waits, 1'b0};
        end
        else if (!as_n && (ce_cpu_p1 || ce_cpu_p2) && ph != 5'd31) begin
            ph <= ph + 5'd1;
        end
    end

    wire due   = !cyc_start && (ph >= due_at);
    wire ready = !rom_sel || rom_have;

    always_comb begin
        if (fast) dtack_n = rom_sel ? !rom_have : as_n;
        else      dtack_n = as_n || !(ready && due);
    end

endmodule

`default_nettype wire
