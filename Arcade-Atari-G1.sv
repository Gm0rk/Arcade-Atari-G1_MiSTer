//============================================================================
//  Atari G1 for MiSTer
//  Arcade-Atari-G1.sv -- top level: MiSTer framework glue for the core
//
//  Instantiates the board (g1_top), video (g1_video), motion-object renderer
//  (g1_rle), JSA II sound board (g1_jsa2), ROM loader, SDRAM arbiter and
//  controller with a boot-time self-test and Hydra analog controls. The
//  module must be named "emu" and use
//  sys/emu_ports.vh; the framework binds to those names.
//
//  Coins are not on the 68000's input ports: COIN1/2/3 are on the JSA II's
//  RDIO port (6502 $2804, active high) and reach the 68000 only through the
//  sound command latch (MAME port definitions). Only coins 1 and 2 are
//  credited; see Inputs.
//
//  Clock domain: clk_sys; the SDRAM controller runs on clk_ram.
//============================================================================

module emu
(
    `include "sys/emu_ports.vh"
);

    import g1_pkg::*;

    //========================================================================
    //  Unused framework ports
    //========================================================================
    assign ADC_BUS  = 'Z;
    assign USER_OUT = '1;
    assign {UART_RTS, UART_TXD, UART_DTR} = 0;
    assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
    assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR,
            DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

    assign VGA_F1         = 0;
    assign VGA_SCALER     = 0;
    assign VGA_DISABLE    = 0;
    assign HDMI_FREEZE    = 0;
    assign HDMI_BLACKOUT  = 0;
    assign HDMI_BOB_DEINT = 0;

    assign LED_DISK  = 0;
    assign LED_POWER = 0;
    assign BUTTONS   = 0;

    //========================================================================
    //  Aspect ratio
    //========================================================================
    wire [1:0] ar = status[122:121];
    assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
    assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

    //========================================================================
    //  OSD
    //========================================================================
    // build_id.v provides `BUILD_DATE for the OSD version line. It is generated
    // before every compile by sys/build_id.tcl (pre-flow script, sys/sys.tcl).
    `include "build_id.v"
    //
    // "h0" hides a line unless status_menumask bit 0 is set, which it is only while
    // Hydra is loaded (osd_hydra below), so the Controls page appears for Hydra alone.
    //
    // CRT Adjust (analog output geometry) exists only when sys/ carries
    // rmonic79's CRT Adjust stage: the modified sys/emu_ports.vh defines
    // MISTER_CRT_ADJUST. "H1" hides its amounts while CRT Adjust is Off.
    localparam CONF_STR = {
        "Atari-G1;;",
        "-;",
        "O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
        "O[4:2],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
`ifdef MISTER_CRT_ADJUST
        "P3,CRT Adjust;",
        "P3-;",
        "P3O[26],CRT Adjust,Off,On;",
        "H1P3O[49],CRT Auto-Width,Off,On;",
        "H1P3O[31:27],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
        "H1P3O[38:32],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
        "H1P3O[43:39],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-5,-4,-3,-2,-1;",
        "H1P3O[47:44],CRT V-Size,0,+1,+2,+3,+4,+5,+6,+7,-7,-6,-5,-4,-3,-2,-1;",
        "H1P3O[48],CRT V-Size Mode,PVM,Cabinet;",
`endif
        "-;",
        // The game's own service (test) menu: turn on, then reset.
        "O[23],Service Menu,Off,On;",
        // Original: the game board's bus wait states. MAME: none, as fast as
        // memory allows.
        "O[50],CPU timing,Original,MAME;",
        "-;",
        // Every Controls line carries h0, so the page stays hidden for Pit
        // Fighter in MiSTer's flat (single-page) OSD mode too.
        "h0P2,Controls;",
        "h0P2-;",
        // Hydra yoke scaling. Medium (100%) is listed first so it is the
        // default; Low is 50%.
        "h0P2O[14:13],Analog sensitivity,Medium,High,Low;",
        "h0-;",
        "T[0],Reset;",
        "R[0],Reset and close OSD;",
        // Overridden by each MRA's <buttons>; matches Pit Fighter's list so a
        // bare .rbf maps the same way (see Inputs).
        "J1,Punch,Kick,Jump,Start,Coin;",
        "jn,A,B,X,Start,R;",
        "v,0;",
        "V,v",`BUILD_DATE
    };

    wire         forced_scandoubler;
    wire  [1:0]  buttons;
    wire [127:0] status;             // as saved by MiSTer
    wire         osd_hydra;          // status_menumask bit 0: show Controls
    wire [21:0]  gamma_bus;
    wire         direct_video;

    wire         ioctl_download, ioctl_upload, ioctl_wr, ioctl_rd;
    wire [26:0]  ioctl_addr;
    wire  [7:0]  ioctl_dout;
    wire [15:0]  ioctl_index;
    wire         ioctl_wait;
    logic [7:0]  ioctl_din;

    wire [31:0]  joystick_0, joystick_1, joystick_2;
    wire [15:0]  joystick_l_analog_0;
    wire [15:0]  joystick_r_analog_0;
    wire [7:0]   paddle_0;

    hps_io #(.CONF_STR(CONF_STR)) hps_io
    (
        .clk_sys(clk_sys),
        .HPS_BUS(HPS_BUS),
        .EXT_BUS(),
        .gamma_bus(gamma_bus),

        .forced_scandoubler(forced_scandoubler),
        .direct_video(direct_video),
        .video_rotated(1'b0),
        .new_vmode(1'b0),

        .buttons(buttons),
        .status(status),
        .status_menumask({14'd0, ~status[26], osd_hydra}),

        .ioctl_download(ioctl_download),
        .ioctl_upload(ioctl_upload),
        .ioctl_upload_req(nv_dirty),
        .ioctl_upload_index(8'd2),
        .ioctl_wr(ioctl_wr),
        .ioctl_rd(ioctl_rd),
        .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout),
        .ioctl_din(ioctl_din),
        .ioctl_index(ioctl_index),
        .ioctl_wait(ioctl_wait),

        .joystick_0(joystick_0),
        .joystick_1(joystick_1),
        .joystick_2(joystick_2),
        .joystick_l_analog_0(joystick_l_analog_0),
        .joystick_r_analog_0(joystick_r_analog_0),
        .paddle_0(paddle_0)
    );

    //========================================================================
    //  Clocks
    //========================================================================
    wire clk_sys, clk_ram, clk_ram_ps, pll_locked;

    pll pll
    (
        .refclk(CLK_50M),
        .rst(1'b0),
        .outclk_0(clk_sys),     //  57.272724 MHz
        .outclk_1(clk_ram),     // 114.545448 MHz
        .outclk_2(clk_ram_ps),  // 114.545448 MHz, phase shifted
        .locked(pll_locked)
    );

    assign SDRAM_CLK = clk_ram_ps;

    // ---- Reset domains ----------------------------------------------------
    //   rst_n      game logic (CPUs, video, RLE engine, sound). Held during the
    //              ROM download and the SDRAM self-test: there is no valid ROM
    //              yet, and the self-test borrows the CPU memory channel.
    //   rst_n_mem  loader, arbiter and SDRAM path. Must run during the
    //              download, which writes through them: an arbiter in reset
    //              never acks the loader, ioctl_wait stays high and the HPS
    //              stalls at "Sending ROM #0".
    // ------------------------------------------------------------------------
    wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~pll_locked
               | st_busy;
    wire rst_n = ~reset;

    // Everything the download needs: excludes ioctl_download and st_busy but
    // still clears on a real reset or PLL unlock. The `| ioctl_download` term
    // is required: the framework asserts RESET during a ROM download, and
    // without it the loader never asserts ioctl_wait, so the download reports
    // success at full speed while nothing reaches SDRAM.
    wire rst_n_mem = ~(RESET | status[0] | buttons[1] | ~pll_locked)
                   | ioctl_download;

    // Accumulator clear: PLL unlock only. An MRA performs several
    // downloads (index 0 the 3.7 MB ROM, index 1 a 9-byte config blob), so
    // clearing at each download start would keep only the last, tiny one.
    // Anything that must accumulate across the download uses this rather than
    // rst_n_mem, which the framework's post-download RESET pulls low.
    wire load_clear = ~pll_locked;

    // The ROM image is download index 0, the same test g1_rom_loader uses.
    wire rom_loading = ioctl_download && (ioctl_index[5:0] == 6'd0);

    wire ce_pix, ce_cpu_p1, ce_cpu_p2, ce_14m, ce_ym, ce_6502, ce_oki;

    g1_ce u_ce
    (
        .clk       (clk_sys),
        .rst_n     (rst_n),
        .cpu_div2  (1'b0),
        .ce_pix    (ce_pix),
        .ce_cpu_p1 (ce_cpu_p1),
        .ce_cpu_p2 (ce_cpu_p2),
        .ce_14m    (ce_14m),
        .ce_ym     (ce_ym),
        .ce_6502   (ce_6502),
        .ce_oki    (ce_oki)
    );

    //========================================================================
    //  ROM loading
    //========================================================================
    g1_cfg_t cfg;
    wire     cfg_valid, rom_loaded, loading;

    wire [24:0] ldr_addr;
    wire [15:0] ldr_din;
    wire        ldr_we, ldr_ack;

    g1_rom_loader u_loader
    (
        .clk            (clk_sys),
        .rst_n          (rst_n_mem),
        .ioctl_download (ioctl_download),
        .ioctl_index    (ioctl_index),
        .ioctl_wr       (ioctl_wr),
        .ioctl_addr     (ioctl_addr),
        .ioctl_dout     (ioctl_dout),
        .ioctl_wait     (ioctl_wait),
        .sdr_addr       (ldr_addr),
        .sdr_din        (ldr_din),
        .sdr_we         (ldr_we),
        .sdr_ack        (ldr_ack),
        .cfg            (cfg),
        .cfg_valid      (cfg_valid),
        .rom_loaded     (rom_loaded),
        .loading        (loading)
    );

    // One-shot when the ROM download completes: kicks off the RLE prescan
    // and the SDRAM self-test.
    logic rom_loaded_d;
    always_ff @(posedge clk_sys) rom_loaded_d <= rom_loaded;
    wire load_complete = rom_loaded && !rom_loaded_d;

    //------------------------------------------------------------------------
    // Latched start requests (self-test, RLE prescan). load_complete is a
    // one-clock pulse in the cycle ioctl_download drops, when the consumers
    // can still be held in reset. The latches have no reset, so a request
    // holds until its consumer raises its busy flag.
    //------------------------------------------------------------------------
    logic st_pending, pf_pending;
    always_ff @(posedge clk_sys) begin
        if (load_complete) st_pending <= 1'b1;
        else if (st_busy)  st_pending <= 1'b0;

        if (load_complete)     pf_pending <= 1'b1;
        else if (prescan_busy) pf_pending <= 1'b0;
    end

    // Convenience decodes of the config blob.
    wire        is_pitfight = (cfg.game_id == 8'd1);
    assign      osd_hydra   = cfg_valid & (cfg.game_id == 8'd0);
    wire        has_adc     = cfg.flags[0];
    wire [10:0] obj_count   = is_pitfight ? RLE_OBJCOUNT_PITFIGHT[10:0]
                                          : RLE_OBJCOUNT_HYDRA[10:0];

    //========================================================================
    //  SDRAM
    //========================================================================
    wire [24:0] cpu_rom_addr, tile_rom_addr, rle_rom_addr, oki_rom_addr;
    wire        cpu_rom_req,  tile_rom_req,  rle_rom_req,  oki_rom_req;
    wire [15:0] cpu_rom_dout, tile_rom_dout, rle_rom_dout, oki_rom_dout;
    wire        cpu_rom_ack,  tile_rom_ack,  rle_rom_ack,  oki_rom_ack;
    // Tile channel grant: the arbiter took g1_video's presented request this
    // clock. See the handshake note in g1_video.sv.
    wire        tile_rom_gnt;

    // The JSA II 6502 fetches its program from SDRAM over the CPU channel,
    // shared with the 68000; at 1.79 MHz it has a full bus cycle of slack.
    wire [24:0] jsa_prog_addr;
    wire        jsa_prog_req;
    wire        jsa_prog_ack;

    wire [24:0] sdr_addr;

    wire [15:0] sdr_din;
    wire        sdr_we, sdr_rd;
    wire [15:0] sdr_dout;
    wire        sdr_ready;

    // ---- CPU channel: 68000 and 6502 --------------------------------------
    // The 68000 wins any tie. Owner and address latch together at grant (as
    // at the tile port in g1_video.sv): an owner flag that tracks the live mux
    // can hand a completed read to the wrong CPU.
    wire [24:0] m68k_addr = cpu_rom_addr;
    wire        m68k_req  = cpu_rom_req;

    logic       cpu_owner_68k;
    logic       cpu_arb_req;
    logic [24:0] cpujsa_addr_held;

    //------------------------------------------------------------------------
    // Registered request. Owner and address latch before the request becomes
    // visible, and the request drops for one cycle at handover, so the arbiter
    // cannot re-grant while the previous owner's address is still presented.
    // The 68000 is DTACK-gated on rom_have, so the extra clk_sys per fetch is
    // absorbed.
    //
    // The self-test bypasses the hold: it owns the channel while it runs, with
    // both CPUs in reset, so no request is pending across the transition.
    //------------------------------------------------------------------------
    always_ff @(posedge clk_sys) begin
        if (!rst_n_mem) begin
            cpu_arb_req      <= 1'b0;
            cpu_owner_68k    <= 1'b0;
            cpujsa_addr_held <= '0;
        end
        else if (!cpu_arb_req) begin
            if (!st_busy) begin
                if (m68k_req) begin
                    cpu_owner_68k    <= 1'b1;
                    cpujsa_addr_held <= m68k_addr;
                    cpu_arb_req      <= 1'b1;
                end
                else if (jsa_prog_req) begin
                    cpu_owner_68k    <= 1'b0;
                    cpujsa_addr_held <= jsa_prog_addr;
                    cpu_arb_req      <= 1'b1;
                end
            end
        end
        else if (cpu_rom_ack) begin
            cpu_arb_req <= 1'b0;
        end
    end

    wire cpu_rom_ack_68k = cpu_rom_ack &&  cpu_owner_68k && !st_busy;

    // The address compare drops an ack for a fetch the 6502 no longer wants:
    // a sound reset ($F98000) resets the 6502 but cannot withdraw a fetch this
    // mux has already latched. While the 6502 waits for a byte its address
    // cannot change, so a real ack always matches.
    assign jsa_prog_ack  = cpu_rom_ack && !cpu_owner_68k && !st_busy
                        && (cpujsa_addr_held == jsa_prog_addr);

    g1_sdram_arb u_arb
    (
        .clk       (clk_sys),
        // rst_n_mem: must run during the ROM download (see Reset domains).
        .rst_n     (rst_n_mem),
        .ld_addr   (ldr_addr),   .ld_din   (ldr_din),   .ld_we   (ldr_we),
        .ld_ack    (ldr_ack),
        // Held address and request (see cpu_owner_68k). The self-test owns the
        // channel outright while it runs and bypasses the hold.
        .cpu_addr  (st_busy ? st_addr : cpujsa_addr_held),
        .cpu_req   (st_busy ? st_req  : cpu_arb_req),
        .cpu_dout  (cpu_rom_dout),  .cpu_ack  (cpu_rom_ack),
        .tile_addr (tile_rom_addr), .tile_req (tile_rom_req), .tile_gnt (tile_rom_gnt),
        .tile_dout (tile_rom_dout), .tile_ack (tile_rom_ack),
        .rle_addr  (rle_rom_addr),  .rle_req  (rle_rom_req),
        .rle_dout  (rle_rom_dout),  .rle_ack  (rle_rom_ack),
        .oki_addr  (oki_rom_addr),  .oki_req  (oki_rom_req),
        .oki_dout  (oki_rom_dout),  .oki_ack  (oki_rom_ack),
        .sdr_addr  (sdr_addr),
        .dbg_cpu_done_addr (),
        // No other master on the bus while the self-test runs (its second pass).
        .solo_cpu  (st_busy & st_solo),
        .sdr_din   (sdr_din),
        .sdr_we    (sdr_we),
        .sdr_rd    (sdr_rd),
        .sdr_dout  (sdr_dout),
        .sdr_ready (sdr_ready)
    );

    //------------------------------------------------------------------------
    // SDRAM capture setting {rd_half, rd_phase}, numbered as the S rows:
    //
    //     S0 t8 Rise  S1 t9 Rise  S2 t10 Rise  S3 t7 Rise
    //     S4 t8 Fall  S5 t9 Fall  S6 t10 Fall  S7 t7 Fall
    //
    // The working sample point depends on where the fitter places the capture
    // registers, so it can move between compiles. The
    // self-test measures all eight settings at boot and the best is used.
    // Until the self-test has measured, S4 (t8 Fall) is used.
    //------------------------------------------------------------------------
    localparam [2:0] CAP_DEFAULT = 3'd4;
    // Selected in an always_comb after the self-test instance, where the
    // st_best_* nets are declared.
    logic [2:0] cap_sel;

    wire which_controller;

    g1_sdram_iface u_sdram
    (
        // During the self-test sweep, the sweep's setting; afterwards the best
        // measured. See cap_sel.
        .rd_phase   (cap_sel[1:0]),
        .rd_half    (cap_sel[2]),
        .dbg_refresh_count (),
        .dbg_dq7    (), .dbg_dq8  (),
        .dbg_dq9    (), .dbg_dq10 (),
        .SDRAM_DQ   (SDRAM_DQ),
        .SDRAM_A    (SDRAM_A),
        .SDRAM_BA   (SDRAM_BA),
        .SDRAM_DQML (SDRAM_DQML),
        .SDRAM_DQMH (SDRAM_DQMH),
        .SDRAM_nCS  (SDRAM_nCS),
        .SDRAM_nRAS (SDRAM_nRAS),
        .SDRAM_nCAS (SDRAM_nCAS),
        .SDRAM_nWE  (SDRAM_nWE),
        .SDRAM_CKE  (SDRAM_CKE),

        .init       (~pll_locked),
        .clk        (clk_ram),

        .addr       (sdr_addr),
        .din        (sdr_din),
        .dout       (sdr_dout),
        .rd         (sdr_rd),
        .we         (sdr_we),
        .ready      (sdr_ready),
        .which_controller (which_controller)
    );

    //========================================================================
    //  SDRAM self-test
    //========================================================================
    // Checks that every word read back from SDRAM equals the word written
    // (write-side and read-side checksums), and measures the error count of
    // each capture setting. It borrows the CPU read channel and finishes
    // before the 68000 is released from reset. See g1_sdram_selftest.sv for
    // what a pass does and does not prove.
    wire [24:0] st_addr;
    wire        st_req, st_busy, st_done, st_pass;
    wire        st_solo;   // self-test pass 2 wants the bus to itself
    wire [2:0]  st_sw_sel;   // capture setting the sweep is measuring
    wire        st_sw_on;    // sweep is driving the setting, not the OSD
    wire [2:0]  st_best_sel;    // setting the sweep measured best
    wire        st_best_valid;  // ... and it has finished measuring

    //------------------------------------------------------------------------
    // Reset from ~load_clear, not rst_n_mem: the write-side checksum is
    // accumulated during the download, and rst_n_mem includes the framework
    // RESET that pulses when the download ends, which would clear it before
    // the comparison. Any accumulator spanning the download needs this.
    //------------------------------------------------------------------------
    g1_sdram_selftest u_selftest
    (
        .clk           (clk_sys),
        .rst_n         (~load_clear),
        .load_active   (loading),
        .load_addr     (ldr_addr),
        .load_data     (ldr_din),
        .load_we       (ldr_we),
        .load_complete (st_pending),
        .rd_addr       (st_addr),
        .rd_req        (st_req),
        .rd_dout       (cpu_rom_dout),
        .rd_ack        (cpu_rom_ack),
        .busy          (st_busy),
        .done          (st_done),
        .pass          (st_pass),
        .sum_written   (),
        .sum_read      (),
        .sum_read_1    (),
        .solo_pass     (st_solo),
        .rep_err       (),
        .rep_ref       (),
        .sweep_sel     (st_sw_sel),
        .sweep_on      (st_sw_on),
        .sweep_err     (),
        .best_sel      (st_best_sel),
        .best_valid    (st_best_valid),
        .best_clean    (),
        .mix_written   (),
        .mix_read      (),
        .first_bad_addr(),
        .had_bad_addr  ()
    );

    always_comb begin
        if (st_sw_on)                       cap_sel = st_sw_sel;
        else if (st_best_valid)             cap_sel = st_best_sel;
        else                                cap_sel = CAP_DEFAULT;
    end

    // Latch the result so it survives past the one-clock done pulse.
    logic st_ran, st_result;
    always_ff @(posedge clk_sys) begin
        if (!rst_n) begin
            st_ran    <= 1'b0;
            st_result <= 1'b0;
        end else if (st_done) begin
            st_ran    <= 1'b1;
            st_result <= st_pass;
        end
    end

    //========================================================================
    //  Inputs
    //========================================================================
    // Bit assignments follow MAME's INPUT_PORTS. Game buttons are active low;
    // the VBLANK and ADC-EOC status bits are active high.
    //
    // MiSTer joystick bits: [0] right, [1] left, [2] down, [3] up, then one
    // bit per button in the order of the MRA's <buttons names="...">, from
    // bit 4. The MRA list overrides the CONF_STR J1 line, so the games differ:
    //
    //   Pit Fighter  [4] Punch  [5] Kick  [6] Jump  [7] Start  [8] Coin
    //   Hydra        [4] Left Trigger  [5] Right Trigger  [6] Left Thumb
    //                [7] Right Thumb   [8] Boost  [9] Pedal  [10] Coin
    //                (Hydra has no start button: the pedal starts a game)
    //------------------------------------------------------------------------
    // Service/test switch (IN0 bit 14, active low), from the OSD. MAME's
    // PORT_SERVICE; both games check it at boot to enter the test menu.
    wire        service = ~status[23];
    wire        vblank_status;
    wire [7:0]  adc_data;
    wire        adc_eoc;
    // snd_ready is declared with the sound board signals below.

    // Pit Fighter player port, MAME order: down, up, right, left, Punch,
    // Kick, Jump/Start. The cabinet's Jump button is also Start, so the MRA's
    // separate Start button drives the same bit.
    function automatic [15:0] pf_in0(input [31:0] j);
        pf_in0 = 16'hFFFF;
        pf_in0[0] = ~j[2];            // down
        pf_in0[1] = ~j[3];            // up
        pf_in0[2] = ~j[0];            // right
        pf_in0[3] = ~j[1];            // left
        pf_in0[4] = ~j[4];            // punch
        pf_in0[5] = ~j[5];            // kick
        pf_in0[6] = ~(j[6] | j[7]);   // jump / start
    endfunction

    // Hydra: five buttons, no directions (steering is analog). MAME order:
    // Left Trigger, Right Trigger, Left Thumb, Right Thumb, Boost -- the
    // same order as the MRA's buttons, so bit n is joystick bit n+4.
    wire [15:0] hydra_in0 = {
        vblank_status,          // 15  VBLANK, active high
        service,                // 14  service, active low
        adc_eoc,                // 13  ADC end of conversion, active high
        ~snd_ready,             // 12  main-to-sound latch full, active low
        7'h7F,                  // 11:5 unused
        ~joystick_0[8],         //  4  Boost
        ~joystick_0[7],         //  3  Right Thumb
        ~joystick_0[6],         //  2  Left Thumb
        ~joystick_0[5],         //  1  Right Trigger
        ~joystick_0[4]          //  0  Left Trigger
    };

    // Coin buttons (MRA order above). Both cabinets have two coin mechs (Pit
    // Fighter manual fig. 5-3: COIN 1 on JAMMA pin 16, COIN 2 on pin T). The
    // JSA II's third coin input is counted by the 6502 but credited by
    // neither game (MAME), so player 3's coin drops into the right mech and
    // coin 3 reads 0: no switch is wired to it.
    wire coin_p1 = is_pitfight ? joystick_0[8] : joystick_0[10];
    wire coin_p2 = is_pitfight ? joystick_1[8] : joystick_1[10];
    wire coin_p3 = is_pitfight ? joystick_2[8] : joystick_2[10];
    wire coin_left  = coin_p1;
    wire coin_right = coin_p2 | coin_p3;

    // Pit Fighter IN1: player 3 in the low byte, player 2 in the high byte.
    wire [15:0] p3 = pf_in0(joystick_2);
    wire [15:0] p2 = pf_in0(joystick_1);
    wire [15:0] in1 = {1'b1, p2[6:0], 1'b1, p3[6:0]};

    // IN0 bits 11:8: unused in MAME, but on the PCB (manual fig. 5-1, buffer
    // 35A) they repeat player 2's JAMMA lines through R15/R16/R13/R14: bit 8
    // JAM-Z (Punch 2), 9 JAM-a (Kick 2), 10 JAM-b (Jump 2), 11 JAM-c (spare,
    // pulled up). The game reads player 2 from IN1; these show only in the
    // Switch Test's raw FC0000 word.
    wire [15:0] pf_in0_bits = pf_in0(joystick_0);
    wire [15:0] pitfight_in0 = {
        vblank_status,          // 15
        service,                // 14
        1'b1,                   // 13  ADC EOC -- no ADC on Pit Fighter, pulled up
        ~snd_ready,             // 12
        1'b1,                   // 11  JAM-c, spare
        p2[6:4],                // 10:8 Jump 2, Kick 2, Punch 2 (active low)
        1'b1,                   //  7  JAM-25, spare
        pf_in0_bits[6:0]
    };

    wire [15:0] in0 = is_pitfight ? pitfight_in0 : hydra_in0;

    wire [1:0] adc_chan_sel;
    wire       adc_start;

    // Hydra yoke and pedal from a MiSTer pad (g1_hydra_controls.sv). The
    // pedal, which starts a game, is button 6 "Pedal" (joystick bit 9), the
    // right stick pushed up, or the paddle. The d-pad steers while the left
    // stick is centred. frame_tick marks the start of VBLANK.
    logic vbl_d;
    always_ff @(posedge clk_sys) vbl_d <= vblank_status;
    wire  frame_tick = vblank_status & ~vbl_d;

    wire [15:0] hydra_stick;
    wire  [7:0] hydra_pedal;

    g1_hydra_controls u_hydra_ctl
    (
        .clk        (clk_sys),
        .rst_n      (rst_n),
        .frame_tick (frame_tick),
        .dpad       (joystick_0[3:0]),
        .pedal_btn  (joystick_0[9]),
        .l_analog   (joystick_l_analog_0),
        .r_analog   (joystick_r_analog_0),
        .paddle     (paddle_0),
        .stick      (hydra_stick),
        .pedal      (hydra_pedal)
    );

    g1_adc0809 u_adc
    (
        .clk         (clk_sys),
        .rst_n       (rst_n),
        .stick       (hydra_stick),
        .pedal       (hydra_pedal),
        .sensitivity (status[14:13]),
        .chan_sel    (adc_chan_sel),
        .start       (adc_start && has_adc),
        .data        (adc_data),
        .eoc         (adc_eoc)
    );

    //========================================================================
    //  The board
    //========================================================================
    wire [10:0] pal_addr;
    wire [15:0] pal_din, pal_dout;
    wire        pal_wr_hi, pal_wr_lo;

    wire [14:0] vram_addr, vram_din_addr;
    wire [15:0] vram_din, vram_dout;
    wire        vram_we;

    wire [2:0]  rle_ctrl;
    wire        rle_ctrl_wr;
    wire [15:0] rle_cmd, rle_objram_w0;
    wire        rle_cmd_wr;

    wire [7:0]  nv_dout;
    wire        nv_dirty;
    wire        vblank_rise;

    g1_top u_board
    (
        .clk             (clk_sys),
        .rst_n           (rst_n),
        .ce_cpu_p1       (ce_cpu_p1),
        .ce_cpu_p2       (ce_cpu_p2),
        .ce_pix          (ce_pix),

        .cfg             (cfg),
        .disable_wd      (1'b0),
        .dbg_clr         (1'b0),
        // The ROM cache also flushes while the PLL is unlocked.
        .rd_probe_rearm  (load_clear),
        .force_bootleg   (1'b0),
        .cpu_fast        (status[50]),

        .vblank_rise     (vblank_rise),

        .in0             (in0),
        .in1             (in1),
        .adc_data        (adc_data),
        .adc_eoc         (adc_eoc),
        .adc_chan_sel    (adc_chan_sel),
        .adc_start       (adc_start),

        .rom_addr        (cpu_rom_addr),
        .rom_req         (cpu_rom_req),
        .rom_dout        (cpu_rom_dout),
        .rom_ack         (cpu_rom_ack_68k),

        .pal_addr        (pal_addr),
        .pal_din         (pal_din),
        .pal_wr_hi       (pal_wr_hi),
        .pal_wr_lo       (pal_wr_lo),
        .pal_dout        (pal_dout),

        .vram_snoop_addr     (vram_addr),
        .vram_snoop_din_addr (vram_din_addr),
        .vram_snoop_din      (vram_din),
        .vram_snoop_we       (vram_we),
        .vram_snoop_dout (vram_dout),

        .snd_cmd         (snd_cmd),
        .snd_cmd_wr      (snd_cmd_wr),
        .snd_reset       (snd_reset),
        .snd_resp_rd     (snd_resp_rd),
        .snd_resp        (snd_resp),
        .snd_int         (snd_int),
        .snd_ready       (snd_ready),

        .rle_ctrl        (rle_ctrl),
        .rle_ctrl_wr     (rle_ctrl_wr),
        .rle_cmd         (rle_cmd),
        .rle_cmd_wr      (rle_cmd_wr),
        .rle_objram_w0   (rle_objram_w0),

        .nv_active       (nv_access),
        .nv_addr         (ioctl_addr[10:0]),
        .nv_din          (ioctl_dout),
        .nv_wr           (nv_access && ioctl_wr),
        .nv_dout         (nv_dout),
        .nv_dirty        (nv_dirty),

        .dbg_cpu_addr    (),
        .dbg_cpu_as_n    (),
        .dbg_unmapped    (),
        .dbg_hit         (),
        .dbg_wd_count    (),
        .dbg_wd_addr     (),
        .dbg_wd_sel      (),
        .dbg_iack_cnt    (),
        .dbg_ipl_seen    (),
        .dbg_trace       (),
        .dbg_rv_pk       (),
        .dbg_ra_pk       (),
        .dbg_ack_count   (),
        .dbg_cyc_count   ()
    );

    // NVRAM transfers use ioctl index 2 in both directions.
    wire nv_access = (ioctl_index[7:0] == 8'd2) && (ioctl_download | ioctl_upload);
    always_comb ioctl_din = nv_dout;

    //========================================================================
    //  JSA II sound board
    //========================================================================
    wire [7:0] snd_cmd, snd_resp;
    wire       snd_cmd_wr, snd_reset, snd_int, snd_ready;
    wire signed [15:0] audio_l, audio_r;

    // $FD0000 read strobe, a g1_top port: Quartus will not resolve a
    // hierarchical read of an internal net.
    wire snd_resp_rd;

    g1_jsa2 u_jsa2
    (
        .clk                 (clk_sys),
        .rst_n               (rst_n),
        .board_reset         (snd_reset),
        .ce_6502             (ce_6502),
        .ce_ym               (ce_ym),
        .ce_oki              (ce_oki),

        .main_din            (snd_cmd),
        .main_wr             (snd_cmd_wr),
        .main_rd             (snd_resp_rd),
        .main_dout           (snd_resp),
        .main_irq            (snd_int),
        .main_to_sound_ready (snd_ready),

        // Coin and service come from the pad. Coins are active high on this
        // port, unlike the 68000-side buttons.
        //
        // self_test is the same switch as IN0 bit 14: one /SELFTEST net joins
        // JAMMA pin 15, the game PCB (AUD-29) and the JSA II's SW1 (J1-29),
        // and the 6502 reads it through inverting buffer 2F (74LS240), so it
        // is active high here. MAME reads 0 (it inverts the line twice). See
        // g1_jsa2.sv for its use.
        .coin1               (coin_left),
        .coin2               (coin_right),
        .coin3               (1'b0),
        .self_test           (~service),

        .prog_addr           (jsa_prog_addr),
        .prog_req            (jsa_prog_req),
        .prog_dout           (cpu_rom_dout),
        .prog_ack            (jsa_prog_ack),

        .oki_addr            (oki_rom_addr),
        .oki_req             (oki_rom_req),
        .oki_dout            (oki_rom_dout),
        .oki_ack             (oki_rom_ack),

        .audio_l             (audio_l),
        .audio_r             (audio_r)
    );

    //========================================================================
    //  Video
    //========================================================================
    wire [PAL_AW-1:0] pal_index;
    // Declared here, ahead of the palette instance.
    wire [7:0] pal_r, pal_g, pal_b;
    wire hblank, vblank, hsync, vsync, de;
    wire [8:0] vis_x, mo_x;
    wire [7:0] vis_y, mo_y;
    wire [9:0] mo_index;

    wire [14:0] rle_vaddr;
    wire        rle_vreq, rle_vack;
    wire [15:0] rle_vdin;
    wire        rle_vwe;

    g1_video u_video
    (
        .clk            (clk_sys),
        .rst_n          (rst_n),
        .ce_pix         (ce_pix),
        .pf_xoffset     (cfg.pf_xoffset),
        .mo_enable      (1'b1),

        .vram_addr      (vram_addr),
        .vram_dout      (vram_dout),
        .vram_din_addr  (vram_din_addr),
        .vram_din       (vram_din),
        .vram_we        (vram_we),
        .ext_vram_addr  (rle_vaddr),
        .ext_vram_req   (rle_vreq),
        .ext_vram_ack   (rle_vack),
        .ext_vram_din   (rle_vdin),
        .ext_vram_we    (rle_vwe),

        .tile_rom_addr  (tile_rom_addr),
        .tile_rom_req   (tile_rom_req),
        .tile_rom_gnt   (tile_rom_gnt),
        .dbg_fetch_overruns (),
        .dbg_fetch_max  (),
        .tile_rom_dout  (tile_rom_dout),
        .tile_rom_ack   (tile_rom_ack),

        .mo_x           (mo_x),
        .mo_y           (mo_y),
        .mo_index       (mo_index),

        .pal_index      (pal_index),
        .dbg_al_ack     (),
        .dbg_pf_ack     (),
        .dbg_al_busy    (),
        .dbg_pf_busy    (),
        .dbg_map_nz     (),
        .dbg_map_word   (),

        .hblank         (hblank),
        .vblank         (vblank),
        .hsync          (hsync),
        .vsync          (vsync),
        .de             (de),
        .vblank_rise    (vblank_rise),
        .vis_x          (vis_x),
        .vis_y          (vis_y)
    );

    assign vblank_status = vblank;

    //========================================================================
    //  Motion objects
    //========================================================================
    wire prescan_busy, render_busy;

    g1_rle u_rle
    (
        .clk           (clk_sys),
        .rst_n         (rst_n),
        .is_pitfight   (is_pitfight),
        .obj_count     (obj_count),
        .clip_left     ({1'b0, cfg.mo_left}),
        // 9-bit clip: config byte 4 plus flags bit 2. Pit Fighter's right
        // edge (295) does not fit in a byte.
        .clip_right    ({cfg.flags[2], cfg.mo_right}),

        .ctrl          (rle_ctrl),
        .ctrl_wr       (rle_ctrl_wr),
        .cmd           (rle_cmd),
        .cmd_wr        (rle_cmd_wr),
        .objram_word0  (rle_objram_w0),

        // MAME uses vpos only through min(239, vpos) and partial = vpos, so
        // any value >= 240 is exact for all of VBLANK (vis_y reads 0 there).
        .vpos          (vblank ? 9'd240 : {1'b0, vis_y}),
        .vblank_rise   (vblank_rise),

        .vram_addr     (rle_vaddr),
        .vram_req      (rle_vreq),
        .vram_dout     (vram_dout),
        .vram_ack      (rle_vack),
        .vram_din      (rle_vdin),
        .vram_we       (rle_vwe),

        .rom_addr      (rle_rom_addr),
        .rom_req       (rle_rom_req),
        .rom_dout      (rle_rom_dout),
        .rom_ack       (rle_rom_ack),

        // The checksum accumulator spans the download: not rst_n (held for
        // the whole transfer), and only the ROM download may restart it, not
        // the config download that follows.
        .load_active   (rom_loading),
        .load_rst_n    (~load_clear),
        .load_addr     (ldr_addr),
        .load_data     (ldr_din),
        .load_we       (ldr_we),
        .load_complete (pf_pending),

        .disp_x        (mo_x),
        .disp_y        (mo_y),
        .disp_index    (mo_index),

        .prescan_busy  (prescan_busy),
        .render_busy   (render_busy),
        .stat_valid    (),
        .stat_null     (),
        .stat_max_w    (),
        .stat_max_h    ()
    );

    //========================================================================
    //  Palette and video output
    //========================================================================

    g1_palette u_palette
    (
        .clk       (clk_sys),
        .cpu_addr  (pal_addr),
        .cpu_din   (pal_din),
        .cpu_wr_hi (pal_wr_hi),
        .cpu_wr_lo (pal_wr_lo),
        .cpu_dout  (pal_dout),
        .vid_index (pal_index),
        .vid_r     (pal_r),
        .vid_g     (pal_g),
        .vid_b     (pal_b),
        .vid_raw   ()
    );

    // The mixer registers its output and the palette adds two clocks, so
    // blanking and sync are delayed three pixels to match; otherwise the
    // picture shifts right and loses pixels at the end of each line.
    localparam int VID_DELAY = 3;
    logic [VID_DELAY-1:0] hb_dly, vb_dly, hs_dly, vs_dly;

    always_ff @(posedge clk_sys) begin
        if (ce_pix) begin
            hb_dly <= {hb_dly[VID_DELAY-2:0], hblank};
            vb_dly <= {vb_dly[VID_DELAY-2:0], vblank};
            hs_dly <= {hs_dly[VID_DELAY-2:0], hsync};
            vs_dly <= {vs_dly[VID_DELAY-2:0], vsync};
        end
    end

`ifdef MISTER_CRT_ADJUST
    //------------------------------------------------------------------------
    // CRT Adjust: OSD values for the CRT stage in sys_top.v (analog output
    // only; HDMI is untouched). Decoding and G1's limits: g1_crt_osd.sv.
    //------------------------------------------------------------------------
    g1_crt_osd u_crt_osd
    (
        .clk         (clk_sys),
        .ce_pix      (ce_pix),
        .enable      (status[26]),
        .autowidth   (status[49]),
        .scandoubler (|status[4:2] | forced_scandoubler),
        .hsize_idx   (status[31:27]),
        .hpos_idx    (status[38:32]),
        .vshift_idx  (status[43:39]),
        .vsize_idx   (status[47:44]),
        .cabinet     (status[48]),
        .crt_on      (CRT_ON),
        .crt_hsize   (CRT_HSIZE),
        .crt_hpos    (CRT_HPOS),
        .crt_vshift  (CRT_VSHIFT),
        .crt_vsize   (CRT_VSIZE),
        .crt_vsmode  (CRT_VSMODE)
    );
    assign CRT_VBL = vb_dly[VID_DELAY-1];   // the VBlank arcade_video receives
`endif

    arcade_video #(.WIDTH(H_VISIBLE), .DW(24)) u_arcade_video
    (
        .clk_video (clk_sys),
        .ce_pix    (ce_pix),
        .RGB_in    ({pal_r, pal_g, pal_b}),
        .HBlank    (hb_dly[VID_DELAY-1]),
        .VBlank    (vb_dly[VID_DELAY-1]),
        .HSync     (hs_dly[VID_DELAY-1]),
        .VSync     (vs_dly[VID_DELAY-1]),
        .CLK_VIDEO (CLK_VIDEO),
        .CE_PIXEL  (CE_PIXEL),
        .VGA_R     (VGA_R),
        .VGA_G     (VGA_G),
        .VGA_B     (VGA_B),
        .VGA_HS    (VGA_HS),
        .VGA_VS    (VGA_VS),
        .VGA_DE    (VGA_DE),
        .VGA_SL    (VGA_SL),
        .fx                 (status[4:2]),
        .forced_scandoubler (forced_scandoubler),
        .gamma_bus          (gamma_bus)
    );

    //========================================================================
    //  Audio
    //========================================================================
    assign AUDIO_L   = audio_l;
    assign AUDIO_R   = audio_r;
    assign AUDIO_S   = 1'b1;   // JSA II output is signed
    assign AUDIO_MIX = 2'd0;   // the board is mono; no stereo mix to apply

    //========================================================================
    //  Activity LED
    //========================================================================
    // On during the download, the SDRAM self-test and the RLE prescan; then
    // off if the self-test passed, fast blink if it failed. Stuck on means one
    // of those three never finished.
    logic [24:0] blink;
    always_ff @(posedge clk_sys) blink <= blink + 1'b1;

    assign LED_USER = loading | st_busy | prescan_busy
                    | (st_ran & ~st_result & blink[22]);

endmodule
