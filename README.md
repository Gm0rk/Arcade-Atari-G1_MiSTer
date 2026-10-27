# Atari G1 for MiSTer FPGA

A FPGA implementation of Atari Games' **G1** arcade hardware:
board **A047896**, the platform under **Pit Fighter** and **Hydra**, written 
for the [MiSTer](https://github.com/MiSTer-devel) platform.

> **AI disclosure:** this core was developed using AI and MAME as a reference.
> (Claude, by Anthropic - Opus 5.5 & Sonnet 5.5).

---

Add to your downloader.ini
```
[Gm0rk/Gm0rkCores]
db_url = https://raw.githubusercontent.com/Gm0rk/Gm0rkCores/db/db.json.zip
```

## Games

| Game | Year | Players | ROM sets | Status |
|---|---|---|---|---|
| Pit Fighter | 1990 | 3 (2 in some sets) | rev 9; rev 7, 6, 5, 4, 3, 2; rev 1 and Japan rev 3 (2 players); bootleg | **Runs on hardware.** Every set loads its own version. Attract mode, all three layers, sound, coins and controls; the service-menu tests pass, including the Sound Test. Player 3's coin is not yet tested. |
| Hydra | 1990 | 1 | Hydra; prototypes 5-25-90 and 5-14-90 | **Plays on hardware.** Every set loads its own version. Gameplay and sound, which matches MAME; the analog yoke and pedal work on an Xbox 360 controller, and the service-menu tests pass. |

<img src="https://github.com/Gm0rk/Arcade-Atari-G1_MiSTer/blob/main/images/Pit_Fighter.png" width="400"><img src="https://github.com/Gm0rk/Arcade-Atari-G1_MiSTer/blob/main/images/Pit_Fighter2.png" width="400">
<img src="https://github.com/Gm0rk/Arcade-Atari-G1_MiSTer/blob/main/images/Hydra.png" width="400"><img src="https://github.com/Gm0rk/Arcade-Atari-G1_MiSTer/blob/main/images/Hydra2.png" width="400">

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

---

## Using the core

ROMs are not distributed with this core. Put the `.mra` files from `mra/` in
`_Arcade`, with its `_alternatives` folder (the other revisions, the bootleg
and the prototypes) as `_Arcade/_alternatives`. Put the core
(`Arcade-Atari-G1_<date>.rbf` from `releases/`) in `_Arcade/cores`, and the
MAME ROM sets where your MRAs look for them. Merged sets of `pitfight.zip`
and `hydra.zip` go into `/games/mame/`. Keep only the
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
  V-Size, PVM or Cabinet mode). At 0 the picture is centred, as with CRT
  Adjust off, and H-Size grows or shrinks it about the middle of the screen.
  **CRT Auto-Width** widens it to a standard width, about 93% of a broadcast
  line, and H-Size trims from there. Analog output only; HDMI is never
  affected, and it is bypassed while the scandoubler is on.
* **Service Menu**: the game's own test menu, from the next reset.
* **CPU timing**: **Original** (default) runs the 68000 at the game board's
  speed, with its bus wait states; **MAME** leaves them out, as MAME does, so
  busy scenes run faster.
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

**[MiSTer-CoreSkill](https://github.com/ppriest/MiSTer-CoreSkill)** by
**ppriest**: its guide to choosing an arcade core's clocks
([`clocks.md`](https://github.com/ppriest/MiSTer-CoreSkill/blob/main/mister-arcade-core/references/clocks.md)).
The core's clocks were checked against it, which led to measuring how fast
the 68000 really runs and giving it the game board's wait states.

The MiSTer community's existing arcade cores were a useful model for project
structure and MRA conventions. The Atari GT core's debug overlay is the direct
model for this one's.

## License

The core RTL is released under the GNU General Public License v2.0 or later,
consistent with the MiSTer framework it builds on. See `LICENSE`.

`sys/`, fx68k, T65, JT51, JT6295 and CRT Adjust (GPL v3) retain their original
licences and authorship.

No ROM data is included or distributed.
