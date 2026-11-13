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
- [Controls](#controls)
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
every clock the report checks. The margins move a little with every
compilation. This compile did not yet apply the SDRAM pin delays, so SDRAM
input/output timing is not in these figures.

| Clock | Frequency | Setup slack |
|---|---|---|
| System (core PLL) | 57.27 MHz | 1.939 ns |
| RAM (core PLL) | 114.55 MHz | 1.563 ns |
| HDMI PLL | 148.54 MHz | 0.525 ns |

Every other clock has at least 4.0 ns of setup slack.

| Resource | Used |
|---|---|
| Logic (ALMs) | 15,531 / 41,910 (37 %) |
| Block RAM (M10K blocks) | 509 / 553 (92 %) |
| DSP blocks | 47 / 112 (42 %) |

## Features

- CRT Adjust by rmonic79: the picture's size and position on a 15 kHz CRT
  (H-Size, H-Position, V-Shift, V-Size in PVM or Cabinet mode).

## Controls

| Pad | Pit Fighter | Hydra |
|---|---|---|
| Stick | Move | Left analog stick: the flight yoke (the d-pad also steers) |
| A, B | Punch, Kick | Left and Right Trigger: laser cannons |
| X | Jump (also Start) | Left Thumb: select a special weapon |
| Y | | Right Thumb: fire the special weapon |
| L | | Boost: launch into the air |
| R | Coin | Pedal: starts a game, and accelerates |
| Select | | Coin |

Pit Fighter: Punch + Kick + Jump together is the Super Move. Hydra has no start
button: hold **Pedal** (R), or push the right stick up. If Hydra's steering or
pedal feels off-centre, recalibrate it in the service menu's Switch Test.

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
- Pit Fighter operator's manual and Hydra Universal Kit installation
  instructions (TM-354), Atari Games: game PCB, JSA Audio II and wiring
  schematics, and the service menus
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

## License

GPL-3.0-or-later (see `LICENSE`). `sys/`, fx68k, T65, JT51, JT6295 and CRT
Adjust retain their original licences and authorship. No ROM data is included
or distributed.
