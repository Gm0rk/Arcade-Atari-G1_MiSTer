# Atari G1 for MiSTer FPGA

A work-in-progress FPGA implementation of Atari Games' **G1** arcade hardware:
board **A047896**, the platform under **Pit Fighter** and **Hydra**, written 
for the [MiSTer](https://github.com/MiSTer-devel) platform.

> **This core was made with AI.** The RTL, testbenches, reference models and
> documentation were written in collaboration with an AI assistant (Claude, by
> Anthropic). It worked from MAME's source, from the operator's
> manual and its schematics. Every change was verified in simulation
> against a reference and then on a DE10-Nano before being accepted.
> This is disclosed here so you can make your decision to use this core accordingly.

---

## Games

| Game | Year | Players | ROM sets | Status |
|---|---|---|---|---|
| Pit Fighter | 1990 | 3 (2 in some sets) | rev 9; rev 7, 6, 5, 4, 3, 2; rev 1 and Japan rev 3 (2 players); bootleg | **Runs on hardware** (rev 9): attract mode, all three layers, sound, coins and controls. The other sets are not yet tested on hardware. |
| Hydra | 1990 | 1 | Hydra; prototypes 5-25-90 and 5-14-90 | **Plays on hardware** (Hydra): attract mode, gameplay and sound, which matches MAME. The analog yoke and pedal work on an Xbox 360 controller, and the service-menu tests pass. The prototypes are not yet tested on hardware. |

All 13 sets are named as in MAME 0.264 and load from merged, split or
non-merged ROM sets.

## Progress

```
MiSTer integration     ████████████████████  100%
ROM loading (.mra)     ████████████████████  100%
CPU  (68000 + Slapstic)████████████████████  100%
Memory subsystem       ████████████████████  100%
Video                  ██████████████████░░   90%
Sound (JSA II)         ███████████████████░   95%
I/O and controls       ███████████████████░   95%
                       ────────────────────
Project                ███████████████████░   94%
```

## The hardware

Atari G1 was a short-lived board: a 68000 behind Atari's Slapstic bank
controller, Atari's RLE "growth renderer" motion-object engine, and the
separate JSA II sound board. Only two games shipped on it. Board photographs
and chip listings are at
[System 16 — Atari G1 Hardware](https://www.system16.com/hardware.php?id=773).

| | |
|---|---|
| Main CPU | Motorola 68000 @ 14.318181 MHz |
| Protection | Atari Slapstic II: 137412-111 to -114 (Pit Fighter revisions), -116 (Hydra) |
| Sound | JSA II: 6502 @ 1.79 MHz, YM2151 @ 3.58 MHz, OKI6295 @ 1.19 MHz |
| Video | 336×240 visible in a 456×262 raster, 59.9227 Hz |
| Layers | scrolling playfield, fixed alpha (text) layer, scaled RLE motion objects |
| Palette | 1,280 entries, IRGB-1555 |
| Settings | 2 KB EEPROM; there are no DIP switches |

Where the core deliberately differs from MAME, it follows the board
schematics: the sound CPU sees the test switch, player 3's coin drops into the
right coin mech, and Pit Fighter's `IN0` bits 8–10 carry player 2's buttons.

---

## Using the core

ROMs are not distributed with this core. Put the `.mra` files from `mra/` in
`_Arcade`, the core (`Arcade-Atari-G1_<date>.rbf` from `releases/`) in
`_Arcade/cores`, and the MAME ROM sets where your MRAs look for them. Merged
sets of `pitfight.zip` and `hydra.zip` go into `/games/mame/`. Keep only the
newest core in `_Arcade/cores`. Any MiSTer SDRAM module is enough.

### Controls

**Pit Fighter**: stick, **Punch** A, **Kick** B, **Jump** X (also Start),
**Coin** R. Punch + Kick + Jump together is the Super Move.

**Hydra**: the **left analog stick** is the flight yoke; the d-pad also
steers. There is no start button: **the pedal starts a game** and is the
throttle. Hold **Pedal** (R), or push the **right stick** up.

| Pad | Hydra control |
|---|---|
| A, B | Left and Right Trigger: laser cannons |
| X | Left Thumb: select a special weapon |
| Y | Right Thumb: fire the special weapon |
| L | Boost: launch into the air |
| R | Pedal: start, and accelerate |
| Select | Coin |

If Hydra's steering or pedal feels off-centre, recalibrate in the service
menu's Switch Test (see [`docs/HYDRA_MANUAL_NOTES.md`](docs/HYDRA_MANUAL_NOTES.md)).

### Settings

Coinage, difficulty and the other operator settings are in each game's own
service menu: turn on **OSD → Service Menu** and reset, save with Punch (Pit
Fighter) or Boost (Hydra), then turn it off and reset to play. They are kept
in the game's EEPROM, which the core saves to the SD card. The service menus
are described in [`docs/PITFIGHTER_MANUAL_NOTES.md`](docs/PITFIGHTER_MANUAL_NOTES.md)
and [`docs/HYDRA_MANUAL_NOTES.md`](docs/HYDRA_MANUAL_NOTES.md).

The OSD has:

* **Aspect ratio** and **Scandoubler Fx**: MiSTer's standard options.
* **[CRT Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust)**: the
  picture's size and position on a 15 kHz CRT (H-Size, H-Position, V-Shift,
  V-Size, PVM or Cabinet mode). Analog output only; HDMI is never affected,
  and it is bypassed while the scandoubler is on.
* **Service Menu**: the game's own test menu, from the next reset.
* **Controls** (Hydra only): analog sensitivity for the yoke.

---

## Credits and references

This core is a reimplementation. It would not have been possible without:

**[MAME](https://www.mamedev.org/)**, the reference for essentially all
hardware behaviour. Specifically:

| File | Author | Used for |
|---|---|---|
| `atarig1.cpp`, `atarig1.h` | Aaron Giles | memory map, machine configuration, interrupt levels, MO command register, input ports |
| `atarig1_v.cpp` | Aaron Giles | video registers, tilemap layout, per-scanline scroll, colour mixing |
| `atarirle.cpp`, `atarirle.h` | Aaron Giles | the RLE object engine: list scan, object table, decode, scaling, flip |
| `slapstic.cpp` | Aaron Giles | the Slapstic bank controller state machine |
| `atarijsa.cpp` | Aaron Giles | JSA II sound board configuration, comm registers and mixing |
| `eeprom.cpp` | Aaron Giles | EEPROM behaviour and the unlock sequence |

MAME is a reference for *behaviour*; no MAME code is compiled into this core.

**The *Pit Fighter* operator's manual** (Atari Games), with its game PCB,
JSA Audio II and wiring schematics. It is the source for everything in
`docs/PITFIGHTER_MANUAL_NOTES.md`.

**The *Hydra* Universal Kit installation instructions** (Atari Games,
TM-354): control wiring, game play, self-test and schematics. It is the source
for `docs/HYDRA_MANUAL_NOTES.md`.

**[fx68k](https://github.com/ijor/fx68k)** by Jorge Cwik: the 68000 core, a
cycle-accurate implementation derived from the original microcode. Its source
and accompanying notes settled the interrupt acknowledge timing when nothing
else could.

**T65** by Daniel Wallner, Mike Johnson, Wolfgang Scherr and Morten Leikvoll:
the 6502 core on the JSA II board.

**[JT51 and JT6295](https://github.com/jotego)** by Jose Tejada (**jotego**):
the YM2151 and OKI6295 implementations used on the JSA II board.

**[MiSTer](https://github.com/MiSTer-devel/Main_MiSTer)**: the framework, and
`Template_MiSTer` by Alexey Melnikov (**Sorgelig**), whose `sys/` directory
provides the HPS interface, video scaler and SDRAM pin handling this core builds
on. `sys/` is unmodified apart from the CRT Adjust stage below. MiSTer's MRA
loader (`mra_loader.cpp`) is the reference for the MRA layout checks.

**[CRT Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust)** by Umberto
Parisi (**rmonic79**), with help from Andrea Bogazzi: the analog picture
size and position controls, integrated sys-side.

The MiSTer community's existing arcade cores were a useful model for project
structure and MRA conventions. The Atari GT core's debug overlay is the direct
model for this one's.

## License

The core RTL is released under the GNU General Public License v2.0 or later,
consistent with the MiSTer framework it builds on. See `LICENSE`.

`sys/`, fx68k, T65, JT51, JT6295 and CRT Adjust (GPL v3) retain their original
licences and authorship.

No ROM data is included or distributed.
