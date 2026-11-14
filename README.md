# Atari G1 for [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

> **AI disclosure:** this core was developed using AI and MAME as a reference.
> (Claude, by Anthropic - Opus 5.5 & Sonnet 5.5).

A FPGA implementation of Atari Games' G1 arcade board
(A047896, 1990), the 68000-based platform behind Pit Fighter and Hydra.

## Table of Contents

- [Hardware](#hardware)
- [Games](#games)
- [Timing and resources](#timing-and-resources)
- [Features](#features)
- [ROMs](#roms)
- [Credits and references](#credits-and-references)
- [License](#license)

## Hardware

| | |
|---|---|
| Main CPU | Motorola 68000 @ 14.318181 MHz |
| Protection | Atari Slapstic II: 137412-111 to -114 (Pit Fighter revisions), -116 (Hydra) |
| Video | Scrolling playfield, fixed alpha (text) layer, scaled RLE motion objects |
| Palette | 1,280 entries, IRGB-1555 |
| Display | 336 x 240 visible in a 456 x 262 raster, 59.9227 Hz |
| Sound (JSA II) | 6502 @ 1.79 MHz, YM2151 @ 3.58 MHz, OKI6295 @ 1.19 MHz |
| Settings | 2 KB EEPROM; there are no DIP switches |

## Games

| Game | Main set | Title Screen | Gameplay |
|---|---|---|---|
| Pit Fighter (1990)| pitfight (rev 9) | <img src="https://github.com/Gm0rk/Arcade-Atari-G1_MiSTer/blob/main/images/Pit_Fighter.png" width="300" alt="Pit Fighter title screen"> | <img src="https://github.com/Gm0rk/Arcade-Atari-G1_MiSTer/blob/main/images/Pit_Fighter2.png" width="300" alt="Pit Fighter gameplay"> |
| Hydra (1990)| hydra | <img src="https://github.com/Gm0rk/Arcade-Atari-G1_MiSTer/blob/main/images/Hydra.png" width="300" alt="Hydra title screen"> | <img src="https://github.com/Gm0rk/Arcade-Atari-G1_MiSTer/blob/main/images/Hydra2.png" width="300" alt="Hydra gameplay"> |

Other sets are in `_alternatives`: Pit Fighter rev 7, 6, 5, 4, 3, 2, rev 1 and
Japan rev 3 (2 players) and the bootleg; Hydra prototypes 5-25-90 and 5-14-90.

## Timing and resources

Built with Quartus Prime 17.0.2 Lite for the DE10-Nano (Cyclone V
5CSEBA6U23I7), timing model Slow 1100 mV 100 C.

Setup, hold, recovery, removal and minimum pulse width slacks are positive on
every clock the report checks; the smallest is a hold slack of 0.149 ns, on the
SDRAM clock pin. The margins move a little with every compilation. The SDRAM
pin delays are applied, so SDRAM input/output timing is in these figures. The
SDRAM read capture is timed as the core samples it (the falling edge as a
two-cycle path, the rising edge not at all), and the boot self-test picks the
sample point.

| Clock | Frequency | Setup slack |
|---|---|---|
| System (core PLL) | 57.27 MHz | 1.707 ns |
| RAM (core PLL) | 114.55 MHz | 1.074 ns |
| SDRAM clock pin | 114.55 MHz | 1.480 ns |
| HDMI PLL | 148.54 MHz | 0.630 ns |

Every other clock has at least 3.7 ns of setup slack.

| Resource | Used |
|---|---|
| Logic (ALMs) | 15,654 / 41,910 (37 %) |
| Block RAM (M10K blocks) | 509 / 553 (92 %) |
| DSP blocks | 49 / 112 (44 %) |

## Features

- CRT Adjust by rmonic79: the picture's size and position on a 15 kHz CRT.
- Color Palette: **Original** (default) is the colour of the game
  board, fitted to footage of a real board: darker overall. **MAME** is MAME's linear palette.
  HDMI and analog alike; it switches at once

## ROMs

ROMs are **not** included in this repository; you need your own dumps of the
games. Use **merged** ROM sets: put `pitfight.zip` and `hydra.zip` in
`games/mame`, the `.mra` files from `mra/` in `_Arcade` with the `_alternatives`
folder beside them, and the core in `_Arcade/cores`.

## Credits and references

- MAME Atari G1 driver and video (`atarig1.cpp`, `atarig1_v.cpp`), RLE engine
  (`atarirle.cpp`), `slapstic.cpp`, `atarijsa.cpp` and `eeprom.cpp`: Aaron
  Giles. The reference for this core's behaviour; no MAME code is compiled into
  it
- Atari Games: game PCB, JSA Audio II and wiring schematics
- [fx68k](https://github.com/ijor/fx68k) (68000): Jorge Cwik
- T65 (6502): Daniel Wallner, Mike Johnson, Wolfgang Scherr and Morten Leikvoll
- [JT51 and JT6295](https://github.com/jotego) (YM2151 and OKI6295): Jose
  Tejada (jotego)
- [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer) framework and
  `Template_MiSTer`: Alexey Melnikov (Sorgelig) and the MiSTer-devel team.
  `sys/` is unmodified apart from CRT Adjust
- [CRT Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust): Umberto Parisi
  (rmonic79), with Andrea Bogazzi (@asturur)
- ppriest: [MiSTer-CoreSkill](https://github.com/ppriest/MiSTer-CoreSkill), the
  arcade core guidance the core's clocks were checked against
- rcoltrane: direct capture footage of Pit Fighter PCB gameplay

## License

GPL-3.0-or-later (see `LICENSE`). `sys/`, fx68k, T65, JT51, JT6295 and CRT
Adjust retain their original licences and authorship. No ROM data is included
or distributed.
