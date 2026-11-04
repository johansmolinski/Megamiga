# Rubber banding: chip RAM in HyperRAM by pausing the Amiga

Status: experiments (2026-11-03/04); `CORE/vhdl/chip_hr.vhd` exists but is in no build yet. Goal: an R3/R3A Megamiga with
2 MB of chip RAM in HyperRAM (the R3 has no SDRAM; doc/developers/r3.md shows why chip RAM in
HyperRAM fails when the Amiga runs in real time: Minimig wants read data ~70 ns after the
address, HyperRAM needs 120-200 ns and doubles its latency without warning when it refreshes).

The idea (from an outside expert, 2026-11-03): run the Amiga faster than real time and pause
it whenever memory is late; FIFOs on everything that leaves the Amiga let it run ahead of real
time, so only the AVERAGE memory speed matters. His order of work:

1. make the Amiga pausable at no more than two FPGA clocks' notice;
2. move the HyperRAM outside the pausable domain;
3. the HyperRAM side keeps working and lets the Amiga continue once the data is there;
4. a cache in between, so the Amiga runs at 2x as often as possible and on average never
   falls behind.

## Experiment 1: is the Amiga pausable? (`~/aexp-work/pause`, `cmp.sh`)

The Apidya full-system bench (Minimig, fx68k, the real amiga_config + adf_track_engine, a
chip RAM model) with the Amiga domain on a gated clock: `gclk` gets an edge only while
`gate_en`, which is decided before the edge from registers of the free-running clock domain -
a BUFGCE. In the Amiga domain: amiga_clk, fx68k, minimig, the floppy engine, the ADF model,
the trace logic (stamped in Amiga clocks, `acyc`). Outside: the chip RAM timing model and the
gate controller. The read data register of the original model loads junk unless the outside
memory has the word of the current address, so a read let through too early shows up.

The gate controller is registered: it sees a new chipset address one clock after the Amiga
edge that produced it (k), lets edge k+1 happen and stops edge k+2 until the word is there.
That is enough because the measured deadline is two Amiga clocks (r3.md): the pause has one
clock of notice.

Variants against the run without pauses (`-DDIRECT`): `lat` (half the reads hit at once, the
rest wait 1..12 clocks, sometimes +40), `latrp` (+ random pauses of 1..16 clocks), `slow` (no
hits, waits up to 130 clocks, random pauses every ~16 clocks). Observables, all in Amiga time:
the bench's log (register writes, Paula states, sector frames, PC samples) and per video frame
a hash of every pixel (ce_pix, RGB, syncs), of every chip RAM write and of every word the CPU
took.

| Load | Run | Free clocks / Amiga clocks | Result |
|---|---|---|---|
| Apidya loader, 2 s, 100 frames | lat / latrp / slow | 1.23 / 1.30 / 2.10 | identical |
| DMA load (`dma.S`), 1.2 s, 60 frames | lat / latrp / slow | 1.40 / 1.48 / 2.72 | identical |

`dma.S` is a ROM program for this: hires 4 bitplanes over the widest fetch window, a copper
colour change on every line, 8 sprites, 4 audio channels, the blitter in nasty mode doing
A+B+C->D blits back to back, the CPU doing read-modify-write passes over chip RAM.

So with the whole Amiga on one gated clock, pausing is invisible to it by construction; what
has to be designed is the boundary (below).

## Experiment 2: does 2x keep up? (`main_rb.cpp`, `rbsweep.sh`)

The same bench, but a C++ driver decides every Amiga edge from a timing model (the data path
stays direct - experiment 1 covers pause safety): the free clock is K x the Amiga's real
rate, a pacer keeps the Amiga at most AHEAD (2048) Amiga clocks (72 us) ahead of real time,
chip RAM sits behind a set-associative cache (16-word lines, critical word first) and two
write-combining buffers in front of one HyperRAM server (fill: first word after 8 free
clocks = ~140 ns, the server busy 18 clocks = 310 ns; scaler bursts of 790 ns take 40 % of
the HyperRAM). Result over 1.2 s of the DMA load (~3.5 million chip accesses):

| Configuration | Hits | HyperRAM busy (Amiga + scaler) | Lag behind real time |
|---|---|---|---|
| 2x, 16 KB 4-way, scaler 40 % | 94.5 % | 25.5 % + 40 % | none (always ahead) |
| 2x, same, scaler 50 % | 94.5 % | 25.2 % + 50 % | none |
| 1.5x, 16 KB 4-way | 94.5 % | 32.7 % + 40 % | none |
| 2x, 8-word lines | 88.9 % | 16.5 % + 40 % | none |
| 2x, 8 KB 2-way | 13.9 % | 52.6 % + 40 % | 624 ms, growing |
| 2x, 16 KB direct-mapped | 14.0 % | 52.6 % + 40 % | 623 ms, growing |
| 1x | 94.5 % | 42.1 % + 40 % | 119 ms, growing |

The associativity matters (bitplanes 20 KB and blitter buffers 16 KB apart alias in a
direct-mapped or 2-way cache); with 4 ways the heaviest load we could make runs ahead of real
time all the time, with HyperRAM to spare. Earlier statistical model: `~/aexp-work/hyperr3/rubber.py`.

## Experiment 3: does the Amiga close timing at 2x? (build `r3-x2`)

The R3 build with the core clock doubled (clk.vhd dividers 20/22: 56.75/57.27 MHz;
`~/aexp-work/r3x2/src`): WNS -2.098 ns, 306 of 51,556 endpoints. Groups: the audio filter IIR
(141, -2.1 ns; audio needs no such speed), Minimig -> the 1 MB chip block RAM (~120, -1.06 ns;
gone when chip RAM leaves block RAM), TG68K internal (24, -0.79 ns), TG68K -> cache tags
(-0.13 ns). Nothing in Agnus, Denise, Paula, the CIAs or fx68k.

## Experiment 4: the real data path (`CORE/vhdl/chip_hr.vhd`, `chk.sh`)

`chip_hr` is the first RTL for steps 2-4: the chipset port's memory behind a 16 KB 4-way cache
(16-word lines, four 16-bit lanes so chip48 works) and two write-combining buffers, an Avalon
master to the HyperRAM, and the gate (`go_o`) for the Amiga's next edge. It sees an access one
clock after the Amiga edge that made it (k); edge k+1 always happens, k+2 only once the word is
in the cache (a hit costs nothing: the tags are compared in the clock the address is seen and
the cache RAM reads the current address in every clock). A miss fetches the whole line; the
write buffers are flushed before a fill, so the fill sees every earlier write; a write to a
cached line updates it.

In the bench (`-DCHIPHR`) chip RAM is ONLY reached through `chip_hr` (the bench's memory array is
the HyperRAM model: a read burst's first word after 8 clocks, then one per clock, a write burst
after 6, 3 clocks of recovery; the scaler takes it for 45 clocks every 112), Minimig's read data
comes straight from the cache, and the pacer runs the free clock at 2x. Against the run with
direct memory:
- Apidya loader, 1.2 s: identical (60 frames of pixel/write/read hashes), 2.000x clocks, lag 0.
- DMA load, 1.2 s: identical (60 frames), 2.000x clocks, lag 0; 94.4 % cache hits, HyperRAM
  busy 9.5 % for the Amiga next to 40 % for the scaler. (The first run deadlocked at frame 14:
  two bugs in the bench's HyperRAM model - the first beat of an Avalon write burst comes with
  the command; a command taken while waitrequest is low must win against a scaler burst.)
- `dma.S` got a CPU phase between blits that reads a word right after writing it (32 fresh
  lines), writes a cached word and reads it back, and writes four lines in a row before reading
  them back - checked by the program and in the CPU-read hash.
- Mutants (`mut.py`): k+2 not held for a miss, no flush before a fill, no cache update on a write
  hit, a line valid one clock early, the high byte enable lost when merging: all differ; a write
  that found no buffer not held: only reachable when a flush takes longer than a 68000 write
  cycle - with a slow HyperRAM write (`slowwr.sh`, HR_WLAT 40) the real chip_hr stays identical
  and that mutant differs. 6/6.
- Vivado out of context (`~/aexp-work/pause/ooc`), 57.27 MHz: WNS +9.55 ns, 567 LUTs (246 as
  LUT RAM), 4 block RAM tiles.
- AGA (`dma_aga.S`, the bench's chipset set to AGA): lores 8 bitplanes, FMODE $F (64-bit
  bitplane and sprite fetches), all planes filled, 8 x 32 palette colours: identical to the
  reference, 94.9 % hits, lag 0. (In Minimig only the sprite DMA takes chip48; the test
  programs' sprites never arm, so the video cannot see wrong chip48 words - hence the check below.)
- Direct check: a shadow memory written like the direct model; at every Amiga edge from a
  read's k+2 on, chip_hr's read word and its three chip48 words must equal it (about two
  checks per read). It catches a chip48 word-order mutant at its first read.
- `regress.sh` runs all of it (OCS and AGA against the references, the mutants, slow writes).

## Experiment 6: real-time video out (`rtv.sh`)

Every Amiga clock writes the video state (pixel enable, RGB, syncs) into a 4096-entry FIFO; the
free-running clock reads one entry every second clock - exactly 28.375 MHz real time - once 1024
are in. With chip_hr at 2x on the DMA loads (OCS and AGA, 1.2 s): no underflow, no overflow,
fill 1025..2597 entries, and the real-time stream's 60 per-frame hashes equal the Amiga-time
ones. (In hardware only pixel clocks need storing: a few hundred entries.)

## Experiment 5: the gated clock in the FPGA (build `r3-gate`)

A copy of the r3 tree (`~/aexp-work/r3gate/src`) with a BUFGCE in parallel to the core clock's
BUFG, fed from the same PAL/NTSC BUFGMUX_CTRL output, its CE a register (always 1 here);
amiga_clk, the CPU phase process, cpu_wrapper (fx68k, TG68K) and Minimig run on it, everything
else on the ungated clock, so every path between Minimig/CPU and main.vhd, the memory and the
boards is a gated <-> ungated crossing. R3 build (REF r3-d): OK, WNS +0.035 ns (unchanged),
WHS +0.000 ns; the worst hold path is in the framework's reset debouncer, not at the gate.

## The boundary (to design)

Inventory of `main.vhd`'s ports (the Amiga = everything inside it):

| Kind | Examples | Under pausing |
|---|---|---|
| Settings, static levels | profile, chipset, chip size, filters, mounted disks, board enables | safe as they are |
| Real-time levels the Amiga samples | joystick, pots, keyboard scan (key_num/pressed), RTC | mostly safe; the keyboard scan visits each key briefly - check that a pause cannot hide a key |
| Handshakes / pulses into the Amiga | the floppy engine's SD reads (adf_avm_*), IDE/network/shared-folder ready + data, the IDE data stream (ids_*), the CPU's ram* ready (TG68K: one-clock pulse) | adapters that count Amiga edges (a pulse lasts until the Amiga took an edge); toggle handshakes (fp_*, dm_*) are already safe |
| Real-time outputs | video (ce, RGB, syncs, blanks, field), audio | FIFOs read in real time (video: ~1 line, cheap) |
| Real-time serial/drive timing | UART RX/TX bit timing, the real floppy drive (step pulses, index, flux FIFO) | stay real-time: a UART that samples in real time and hands bytes over; the Hardware Floppy either pins the Amiga to 1x while active or gets its own re-timing |
| Memory | chipset port (chip_hr), the CPU's ram* port (Fast RAM / Kickstart) | outside, in the free-running domain |

## Next steps

1. (done as a timing experiment, see above) the gated clock: a BUFGCE next to the core
   clock's BUFG.
2. The domain split in main.vhd/mega65.vhd along the inventory above: edge-counting adapters for
   the handshakes, video and audio FIFOs read in real time, the real-time UART and floppy.
3. chip_hr on the real HyperRAM path (avm_fifo CDC, arbiter priority against the scaler), the
   pacer, the core at 2x (audio filter and TG68K paths to fix, chip RAM leaves block RAM).
4. AGA load in the bench (fetch modes, chip48) and a 68020 variant.
