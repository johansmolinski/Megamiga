# Rubber banding: chip RAM in HyperRAM by pausing the Amiga

Status: experiments (2026-11-03/04), then the FPGA design for R3 (2026-11-04, see "The FPGA design"). Goal: an R3/R3A Megamiga with
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

## Experiment 7: a handshake across the boundary (`adfout.sh`)

The rule for every synchronous interface between the gated Amiga and the free-running side: the
free side samples the Amiga's outputs, and changes the Amiga's inputs, only at clock edges the
Amiga takes (gate_en); between those edges it works on its own. Test: the floppy engine's ADF
reads (Avalon, one outstanding read, the engine waits for readdatavalid) go to a model outside
the Amiga that answers after a random 1..64 free clocks, like an SD card, with random Amiga
pauses on top (`-DADFOUT -DRPAUSE=64`). Apidya loader, 3 s: the same 12 sector frames in the
same order as the reference, no exception. (The answer arrives at a different Amiga time than in
the reference, as it would from a real card - the engine paces Paula itself.)

## Experiment 8: the 68020, and the A1200 with 2 MB chip RAM (`chk020.sh`, `chk2m.sh`)

`-DCPU020`: cpu_wrapper with TG68K (ghdl netlist) on Minimig's CPU pins as main.vhd wires it,
68020 mode, no turbo modes, the 68020 config in amiga_config. The same programs (68000 code):

| Load | Variant | Result |
|---|---|---|
| OCS DMA load | random latency + pauses | identical, 60 frames, 1.48x clocks |
| OCS DMA load | chip_hr at 2x | identical, 94.4 % hits, lag 0, 5.5 M words checked, 0 bad |
| AGA DMA load | random latency + pauses | identical, 60 frames, 1.46x clocks |
| AGA DMA load | chip_hr at 2x | identical, 94.9 % hits, lag 0, 5.2 M words checked, 0 bad |
| A1200: 68020 + AGA + 2 MB chip RAM, the load above 1 MB (`dma_aga2m.S`) | chip_hr at 2x | identical, lag 0, 0 bad; real-time video FIFO: no underflow |

In the 2 MB run the chipset port is above 1 MB in 1.8 M Amiga clocks of reads and 0.9 M of
writes (the cache counts equal the 512 KB run: the load moved by a multiple of the cache size).

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

## The FPGA design (R3, `C_R3_RUBBER` in globals.vhd, November 2026)

The boundary turned out simpler than the inventory above suggested: instead of adapters per
handshake, the boundary sits at the framework. Everything in mega65.vhd that talks to the
Amiga moves into the Amiga's clock domain with it - the memory (amiga_mem_r3 for the Kickstart and
the Fast RAM), the IDE board and its sector engine, the network card, the shared folder, the
floppy engine's SD buffer, the Hardware Floppy's core side, the cold-boot logic - so their
handshakes with the Amiga stay synchronous. Their other sides (QNICE, HyperRAM, the SD
controllers, the Ethernet MAC, the floppy's 50 MHz front-end) already crossed clock domains with
synchronizers, Gray-coded FIFOs or cdc_stable, and those work with a gated clock as long as it
keeps ticking - it does, it averages real time. Only the framework's real-time interface needs
the bridge.

- Clocks (clk.vhd, `G_RB`): CLKOUT3 of the PAL MMCM, 1135 MHz / 23 = 49.35 MHz, through a BUFG
  (`rb_clk`, free running: chip_hr, the gate) and a BUFGCE (`amiga_clk`, the Amiga and its
  peripherals). That is 1.74 x PAL and 1.72 x NTSC - not 2x: TG68K's register file -> ALU path
  (41 logic levels) needs ~20 ns; build rb-a at 1135 / 22 = 51.59 MHz met timing only after
  the post-route phys_opt, by 3 ps. 1.5x already kept up in experiment 2. The rate need not
  be a multiple of anything, because both FIFOs below are dual-clock. CORE.xdc names the clock
  `amiga_clk` and bounds its crossings like main_clk's.
- `rb_bridge.vhd`: the in-FIFO (main_clk -> rb_clk) carries a word of real-time inputs per
  main_clk (keyboard scan, joysticks, pots, serial RXD/CTS); the Amiga takes one word per edge,
  and the gate only opens when the word for the next edge exists - that is the pacer, and the
  Amiga at Amiga time a sees the inputs of real time a. The out-FIFO (rb_clk -> main_clk)
  carries a word of real-time outputs per Amiga edge (video incl. its clock enables, Paula's
  raw audio and the filters' enable, the LEDs, osm_block, serial TXD/RTS), read one per
  main_clk once 2048 are in. So every output - pixel timing, audio samples, UART bit cells -
  is replayed exactly, 2048 clocks (72 us) after the Amiga made it, and the Amiga may fall up
  to 2048 clocks behind before anything shows. An underflow stops the reader until 2048 words
  are in again and throws the in-FIFO's backlog away, so the latency returns to 2048.
- `rb_audio.vhd`: main.vhd's audio filters and volume, in real time on the replayed Paula output
  (the IIR fails timing at the fast clock, experiment 3).
- The framework's settings, the RTC and the resets reach the Amiga's domain through cdc_stable
  (whole words) and two-flop synchronizers.
- chip_hr on rb_clk. Its Avalon master crosses to hr_clk through its own avm_fifo and takes the
  RTG blitter's arbiter port (no blitter on R3). The cold-boot scrub (two words) goes through
  chip_hr.
- The 8 MB of HyperRAM (16-bit words), all of it in use:

  | Words | Contents |
  |---|---|
  | 000000-0FFFFF | the scaler's framebuffer (2 MB: ascal masks its addresses to 2 MB) |
  | 100000-2FFFFF | Zorro II Fast RAM, 4 MB (amiga_mem_r3, the same 1:1 map as without rubber banding) |
  | 300000-3FFFFF | chip RAM, 2 MB (banks 0000-0011) |
  | 380000-3BFFFF | slow RAM, 512 KB (bank 1000): the upper half of the chip RAM's words |

  The Kickstart moved into 512 KB of block RAM in amiga_mem_r3 (`G_KICK_BRAM`, 128 tiles, free
  since the chip RAM left the block RAM; the 1 MB design keeps it in HyperRAM). A Kickstart
  read bypasses the Fast RAM cache and takes two clocks more than a cache hit, but never misses.
  Slow RAM shares the chip RAM's 2 MB, so prof_decode allows it only with 512 KB or 1 MB chip
  RAM (Minimig's bank mapper keeps 1 MB chip RAM in the lower 1 MB). Any other bank on the
  chipset port reads 0 and writes nothing (mega65.vhd masks the strobes before chip_hr), as the
  block RAM design did.
- Menu (config.vhd): 2 MB chip RAM is available again on R3, Slow RAM next to 512 KB or 1 MB
  chip RAM; the Fast RAM line reads 4 MB.

Bench `~/aexp-work/rbbridge` (`run.sh`, `mut.py`): rb_bridge with a dual-clock FIFO model, a fake
Amiga on the gated clock that checks every input word arrives in order, random chip_go pauses.
No pauses / 30 % / 42 % busy (bursts up to 400 clocks) / 10 % in bursts of up to 2000: every
input word once and in order, every output word once and in order, input-to-output latency
constant (2056-2057 main_clk), no underflow (lowest out-FIFO level 654 at 42 %). An overload (70 %
busy for 400 us): one underflow, input words skipped, no output word lost or repeated, latency
back to 2057 afterwards. Mutants: 7/7 killed.

Builds:
- `rb-a` (R3, 1135 / 22 = 51.59 MHz): only TG68K's register file -> ALU path (41 logic levels)
  failed after routing (-0.580 ns, 17 endpoints); the post-route phys_opt made it +0.003.
- `rb-b` (R3, 49.35 MHz, REF rb-a): OK, WNS +0.065 (amiga_clk +0.183 before the post-route
  phys_opt), WHS +0.002; 54.2K LUTs, 121/365 block RAM tiles. Checkpoint `rb-b-save`.
- `r6rb-a` (`~/aexp-work/r6rb/mk.sh`: this tree on the R6 with C_HAS_SDRAM false, the SDRAM
  pins idle, the R3 menu and sign-off gates): OK, WNS +0.077 (amiga_clk -0.040 on 3 TG68K
  endpoints before the post-route phys_opt), WHS +0.051. Checkpoint `r6rb-a-save`;
  `~/aexp-builds/Megamiga-r6rb-a-diag` = the same with the IDE_DIAG firmware: once a second a
  line `IDE` + 14 words on the debug UART (115200, `~/aexp-work/uartlog.py`); word 12 =
  underflows (bits 31:16) and the lowest out-FIFO level since reset (12:0), word 13 = chip_hr's
  line fills.
- 4 MB Fast RAM (the Kickstart in block RAM, the new HyperRAM map above): `rb-c` (R3, REF rb-b)
  crashed Vivado in the incremental synthesis (segfault reading rb-b's synth checkpoint); `rb-d`
  (the same with `NO_REF_SYNTH=1`, implementation still from rb-b): OK, WNS +0.089 (amiga_clk
  +0.114), WHS +0.002; 54.0K LUTs, 249/365 block RAM tiles (+128 for the Kickstart). Checkpoint
  `rb-d-save`. `r6rb-b` (R6 test, REF r6rb-a): OK, WNS +0.073, WHS +0.040, 249 tiles; checkpoint
  `r6rb-b-save`, IDE_DIAG variant `~/aexp-builds/Megamiga-r6rb-b-diag`. They replace rb-b and
  r6rb-a.

## Hardware test on the R6 (2026-11-04)

The user ran the R6 test builds (A1200 profile, 68020, AGA, 2 MB chip RAM, 4 MB Fast RAM, HDMI
1280x720 50 Hz and VGA; an LCD, then an analog CRT).

- Boot, Kickstart 3.x, the early boot menu, a Shell without startup-sequence: fine. `avail`:
  2,096,128 bytes chip, 4,194,304 fast. AmigaTestKit: four full memory passes over 2 MB chip and
  4 MB fast without an error. SysInfo: lide.device 6.7 MB/s (main with SDRAM: ~14.8 MB/s).
- **Workbench after SetPatch showed only every fourth 16-pixel column, plus snow** (r6rb-b): SetPatch
  switches AGA to 64-bit fetches (FMODE 3); the first word of a group comes with the ram data,
  the other three on `chip48`. Two faults: (1) chip_hr drove chip48 straight from the cache's read
  port, which follows the current address - but Denise takes chip48 half a 7 MHz cycle after the
  ram data (`bplNdat <= {data16, chip48}` at clk7n_en), when the bus already shows the next slot
  (the CPU between the 64-bit fetches); sdram_ctrl.v holds it until the next chip slot. chip_hr
  now holds it the same way (`c48_q`, loaded at the read's edge k+2). The pause bench had the same
  flaw in its reference model, so frames matched; it now models the hold and checks it at every
  Amiga edge (old chip_hr: 6.2 M violations in 0.6 s, new: 0). (2) mega65.vhd masked chip48 with
  `ch_valid` of the CURRENT address (the unused banks read 0) - zero whenever the CPU ran from
  Kickstart or Fast RAM by then. chip48 is no longer masked (only Denise reads it, after its own
  chip RAM fetches). r6rb-d: Workbench and all screen modes fine, the snow gone.
- **VGA went black for ~1 s / the CRT's upper picture shook** whenever Workbench drew (selecting a
  window, typing, dragging, some clicks), HDMI fine. Out-FIFO underflows: the Amiga fell more than
  G_DELAY behind real time, the reader re-primed, the video stream lost ~0.1-0.2 ms (one long line
  per underflow, measured with a stream checker: lines of 3000-6500 instead of 1816 clocks, nearly
  all at lines 16-32 of the field - the vertical blank, where Intuition draws). The scaler hides
  that on HDMI. A direct check of the gated clock (a flop toggled by amiga_clk against the edges
  rb_bridge books) found no mismatch: the BUFGCE does exactly what the bookkeeping assumes.
  G_DELAY 8192 (16K FIFOs, 283 tiles) did not help: the lag reached the in-FIFO's 16K limit
  (in hindsight most likely the re-prime bug found later, see below).
  Measured (r6rb-i/j, wait = rb_clk clocks with chip_hr's go low): a miss cost 1.1-1.2 us with
  the scaler first in the framework arbiter, 0.83 us round-robin; ~65,000 misses/s from the
  display alone, 200,000-240,000/s while Workbench drew; on average only 7-25 % waiting, but in
  bursts (blits) far beyond the 42 % the Amiga can afford at 1.74 x. Hence the prefetch below.
- Not a rubber-band issue but found on the way: the chipset backport's opposite-direction joystick
  filter broke the DB9 mouse's vertical axis (fixed on main, Minimig 63f1c27).

Note on the diagnostics firmware: the UART line's 14 words are dcnt(0)..dcnt(13); the debug word is
dcnt(12) (bits 63:32) and dcnt(13) (31:0) - the LAST two words. (Reading one word too early made
the first underflow readings look like zero.)

### Prefetch and fill-before-write-back (chip_hr, 2026-11-04)

Tagged next-line prefetch and demand fills that no longer wait for unrelated write-backs; the
rules are in chip_hr's header. chip48 is now loaded exactly once per read, at its edge k+2 (a
background fill may take the line as its victim right after and overwrite it).

- Pause bench (`chkaga.sh`, `chk.sh`; on fedora via `rtest.sh`): AGA FMODE 3 load identical to the
  reference, chip48 hold 0 violations, 1.74 M words checked, 0 bad, misses 33,682 -> 4,436 (hits
  96.1 % -> 99.5 %); OCS Apidya and DMA loads identical, 0 bad.
- With a HyperRAM model as slow as the R6 measured (`pfperf.sh`: first word after 40 clocks,
  writes after 30, the scaler 40 %): misses AGA 33,682 -> 7,063, OCS DMA 148,513 -> 31,366
  (-79 %), write-backs 27,445 -> 17,032 and 103,696 -> 57,767.
- Unit bench `~/aexp-work/chiphr` (`tb_chip_hr.vhd`, `run.sh`, `mut.sh`): chip_hr alone with a
  4-set cache (16 lines: constant evictions), sequential read streams, writes just ahead of and
  behind them, random reads and writes, random Amiga pauses, an Avalon model with random
  waitrequest, latency and readdatavalid gaps; strobes high in the last quarter of every slot as
  minimig_sram_bridge.v does (without that two writes to one word look like one access). Checks
  every read word at k+2 against a shadow and chip48 at every edge; STUCK after 20000 clocks
  without an edge. 6 seeds x 200,000 slots pass. Mutants (`~/aexp-work/pause/pfmut/mk.py`): 7/10
  killed - no stale mark on a write to the line in flight, validating a stale fill, prefetching a
  cached line, prefetching a line in a write buffer, a demand fill past a write buffer of its
  line, no wait for the cache port, issuing before the last tag is written. Not killed: a
  duplicate demand request for the line in flight (equivalent: the issue drops a request whose
  line is cached by then), chip48 reloaded after k+2 (needs a fill word within one Amiga edge of
  the victim's invalidation; the strobes are gone by then), and a write to the prefetch line in
  the very clock the prefetch is issued (a real race, guarded in the code, not reached by 3 stress
  settings x 8 seeds x 60,000 slots).

### The prefetch in the FPGA: tags back in LUT RAM (2026-11-04)

The first prefetch builds failed: r6rb-k could not be routed (9,873 nets with route conflicts),
r6rb-l missed timing by 2.4 ns on amiga_clk (7,105 failing endpoints, 6,144 of them `tags`).
Vivado had built the tag array from 6,144 flip-flops and ~20K LUTs instead of LUT RAM (+23K LUTs
for the whole design), because it got a second write address (the issue invalidated the victim
at `rr(set)`, the validation wrote `f_way/f_set`). And three tag/pfb writes depended on the
current access, whose address comes late from Agnus' address generator: the validation checked
for a write to the line in the same clock (and that write's `v_wpost` used the tag lookup), the
demand issue dropped a request whose line the current read hit, and a read hit cleared its
prefetch bit at once (worst path 31 levels: beamcon0 -> Agnus -> Gary -> tag compare -> tags).

The fix (same behaviour, other structure):
- one LUT RAM per way, written only at `(f_way, f_set)` from registers: the victim's tag is
  invalidated one clock after the issue (its data stays intact until the first fill word, many
  clocks later);
- a write in the validation clock goes into the cache (write-through) instead of blocking the
  validation;
- `v_wpost` uses the last clock's hit (and holds every new write access that meets a fill word);
- a demand request is not made for a line issued in the same clock (with "not while that line is
  being filled" a demand line is never cached when issued - a simulation-only assertion checks
  every issue);
- the prefetch bit of a read hit is cleared one clock later, addressed by registers.

Out-of-context synthesis of chip_hr (`~/aexp-work/chiphr/ooc.tcl`, 12 ns input delay at 49.35 MHz):
pre-prefetch 630 LUTs / 296 LUT RAM / 344 FFs, slack +4.17 ns; first prefetch 25,464 / 68 / 7,278,
+0.88 ns (15 levels); now 2,710 / 324 / 1,082, +3.93 ns (6 levels). Benches: unit bench 6 seeds x
200,000 slots pass; AGA FMODE 3 and OCS identical, 0 bad, the same miss counts as before. Unit-bench
mutants (`pause/pfmut2/mk.py`, 14 + 1 performance-only): 11/14 killed - the new ones (demand
request without the busy or the issue exclusion, no write-through, no victim invalidation,
`v_wpost` off) included. Not killed: m3 and m9 as before, and `v_wpost` by `hit_d` alone (the
bench changes the address a clock before the strobes, so `hit_d` is already the new access's hit;
the `new_acc` term covers a bus that changes both at once). The same mutants in the system bench
(`pfmut2/run1.sh`, AGA DMA load 0.6 s): 2/14 killed (a demand fill past a write buffer of its
line, no wait for the cache port), as with the first set - its HyperRAM model rarely makes the
races, and `ghdl --synth` drops the simulation-only assertion; the unit bench is the one for them.
Builds (incremental from r6rb-i/j): r6rb-m (scaler first) WNS +0.073 / WHS +0.026, r6rb-n
(round-robin) +0.054 / +0.036 (both limited by qnice_clk; amiga_clk +0.197 / +0.244), 56.2K LUTs
(r6rb-j 54.1K), 283 BRAM tiles.

### Hardware test of the prefetch (r6rb-m, r6rb-n, 2026-11-04)

The user dragged windows and selection rectangles in Workbench on the CRT; both builds shook "as
bad" as before, though the counters improved a lot:

| | r6rb-i (no prefetch, scaler first) | r6rb-j (no prefetch, round-robin) | r6rb-m (prefetch, scaler first) | r6rb-n (prefetch, round-robin) |
|---|---|---|---|---|
| idle Workbench: misses/s, wait | 65K, 7.4 % | 65K, 5.4 % | 16K, 3.1 % | 13K, 1.4 % |
| while drawing: misses/s, wait | 217K, 30 % | 200-240K, 17-25 % | 13-34K, 1-5 % | 17-27K, 2-3 % |
| cost of a miss while drawing | 1.1-1.4 us | 0.9-1.05 us | 1.3-1.9 us | 1.0-1.25 us |
| underflows in the test | 456 | 789 | 74 | 175 |

(Each miss of r6rb-m/n may wait for a prefetch in flight first.) So the picture needs NO underflow,
not fewer: every underflow re-primes the reader, a jump of the sync timing. A drag redraws a few
hundred lines at the top of the field, and its misses come in bursts longer than the 289 us lead.

### The lead, and a bug in the bridge's re-prime (r6rb-o, 2026-11-04)

r6rb-o (lead 12288 of 16K, round-robin, the largest lag of every 1.36 s window on the diag line):
still shaking ("maybe it moved a bit higher up on screen"), +24..+138 underflows per window while
dragging - and after the test, in an idle Workbench, the Amiga stayed 165 us behind for good (12 %
wait, 87K misses/s), the lag readings often exactly 577 us = the in-FIFO full.

The rb_bridge bench (`~/aexp-work/rbbridge`, generic DELAY, longer overloads: 1.5 ms at 50-60 %
pause) reproduced it at every ratio, 2048 of 4096 included: after an underflow the latency stayed
156..626 clocks above G_DELAY. Traced (`tb_trace.vhd`, VHDL-2008 external names): while the reader
re-primed, the discard threw the in-FIFO's backlog away at ~21 words/us, but the unblocked Amiga
refilled the out-FIFO at up to 49 words/us, so the reader restarted with G_DELAY words out AND
part of the backlog still in; nothing removed that rest - in-level + out-level stayed above
G_DELAY, more with every underflow, until the out-FIFO was full, the in-FIFO overflowed and input
words were lost. Fix: while the reader waits, the Amiga fills the out-FIFO only up to G_DELAY + 8,
and the reader restarts only when the in-FIFO's backlog is gone (its write-side count <= 16). Now
every overload returns to G_DELAY + 8..23, at 50 % and at 94 % of the depth alike. The bench also
checks now that the reader still reads at the end (a re-prime that never ends passed before), and
starts its latency and input checks after the first priming (which takes DELAY clocks). Mutants
(`mut.py`, 4 scenarios): 9/9 killed, including the two halves of the fix.

So G_DELAY = depth - 512 (`C_RB_DELAY`). Builds with the fix (round-robin, lag diag): r6rb-q (16K,
15872 = 559 us) WNS +0.009 / WHS +0.037, 283 tiles; r6rb-r (32K, 32256 = 1.14 ms) WNS +0.182 /
WHS +0.040, 327 tiles.

### A Workbench-like load in the pause bench (`dma_wb.S`, `wbperf.sh`)

The DMA loads never made the bench's Amiga fall behind, even at 1.74 x (`KNUM`/`KDEN` defines
now; `kperf.sh`). `dma_wb.S`: hires 8 planes in FMODE 3, and once per frame from line $20, on every
plane, 4 vertical XOR lines (line mode, 120 rows), 2 columns complemented (C->D, 2 words x 180
rows) and a window copy (A->D, 20 words x 120 rows, modulo 40); not nasty. `wbperf.sh`: 1.74 x,
AHEAD 4 (the Amiga never ahead of real time, as with the in-FIFO: the bench's lag is then the
FPGA's), the slow HyperRAM model; the CHIPHR line counts how often the lag rose above the three
leads 8192 / 15872 / 32256 (r6rb-n / -q / -r). 0.8 s, frames identical to the DIRECT reference:

| chip_hr | misses | max lag | lag over 8192 / 15872 / 32256 |
|---|---|---|---|
| before the prefetch | 47,031 | 5.9 ms (runs away) | 14 / 13 / 39 times |
| with the prefetch (r6rb-m..r) | 21,804 | 1.04 ms | 136 / 128 / 0 |
| + early restart (a read of the line being filled goes on once its 4-word group is in) | 21,822 | 1.03 ms | 166 / 126 / 0 |

The bench matches the hardware (the prefetch builds still underflow with leads up to 559 us) and
says a lead of 1.14 ms (r6rb-r) would be enough for this load. Early restart gains nothing here
(the 16-word transfer is not the cost, the ~1 us latency of each serialized fill is): not kept
(`~/aexp-work/pause/chip_hr.vhd.early-restart`; unit bench 6 seeds passed).

What would shrink the lag (`wbsweep.sh`, `wbsweep2.sh`; the same load and chip_hr, max lag):

| variant | scaler's HyperRAM share | max lag |
|---|---|---|
| as now (first word after 40 clocks, the scaler 45 of every 112) | 40 % | 1.04 ms |
| miss latency -10 clocks | 40 % | 0.79 ms |
| miss latency -20 clocks | 40 % | 0.63 ms |
| scaler 25 % | 25 % | 0.62 ms |
| no scaler | 0 | 0.32 ms |
| ascal N_BURST 64 instead of 128 (bursts of 27 every 56: the per-burst overhead stays) | 48 % | 3.4 ms |
| ascal at 16 bpp (565) instead of 24 (45 every 168) | 27 % | 0.65 ms |
| both | 32 % | 0.76 ms |

The HDMI scaler's share of the HyperRAM costs as much as the misses themselves. Shorter scaler
bursts are worse (more overhead); a 16-bpp framebuffer (lossless for OCS/ECS's 12-bit colours, AGA
loses depth on HDMI only) helps like a 20-clock shorter miss. Test build r6rb-s = r6rb-r with
ascal's scaler format "00" (an M2M change, TEST BUILD only, not in the worktree): WNS +0.182 /
WHS +0.040, 56.3K LUTs, 327 tiles.

### Hardware test of r6rb-r and r6rb-s (2026-11-05)

Window drags and selection rectangles on Workbench, diag line every 1.36 s (`rb_r.log`, `rb_s.log`):

| build | underflows in the test | wait | misses/s | per miss | CRT |
|---|---|---|---|---|---|
| r6rb-r (lead 1.14 ms) | ~45 | 2.3..3.3 % | 17..24K | 1250..1390 ns | still shakes |
| r6rb-s (+ scaler 16 bpp) | 22 | 1.3..2.0 % (16 % in one heavy stretch) | 14..21K | 740..970 ns | "a little less shaky" |

- The lag statistic cannot show the margin: an underflow leaves exactly G_DELAY of backlog, so a
  window with an underflow reads the lead itself (1137 us). r6rb-s windows without an underflow
  still reach 1.01..1.13 ms.
- The 16-bpp scaler cuts the cost of a miss by 40 % (the scaler's HyperRAM share), but not enough.
  HDMI showed no picture in r6rb-s (ascal's `format` "00" alone is not enough; not looked into).
- Both builds had one underflow about 12 s after loading, with a lag of 2 us: not the Amiga falling
  behind - probably the Amiga's reset after the Kickstart load (open).

### The virtual lag (r6rb-t)

`rb_bridge`'s lag statistic now adds, while the reader waits after an underflow, the words
discarded while chip_go holds the Amiga (not those discarded while only the pace holds it: the
Amiga would have taken them): the lead the Amiga would have needed. Saturates at 24 bits; the diag
word carries it in units of 16 clocks (`LAG=16 rbstat.py`). The bridge bench checks it against its
own count (real time minus the Amiga's input word plus the words it skipped): 346 / 347 without and
2081 / 2083 with an overload; mutants 11/11 (`mut.py` now runs the unmutated bridge first: an
external name the fedora ghdl cannot resolve had made every run fail). Test build r6rb-t = r6rb-r +
this: WNS +0.014 / WHS +0.040, 327 tiles.

### Why Workbench outruns any lead: the cache is too small (2026-11-05)

Intuition draws window outlines and selection rectangles with the blitter in line mode, one plane
after the other: on a vertical line every pixel is a read and a write of a word in another row, so
every pixel misses (a 32-byte line holds 256 pixels of one row of one plane). The display's
bitplanes stream ~160 KB a frame through the 16 KB cache and push those rows out before the next
frame draws the line again. The pause bench with `dma_wb.S` (whose vertical lines stay at the same
x, as a slowly dragged outline mostly does), the largest lag of every 20 ms (`LAGW` lines in
`tb_top.sv`; `csweep*.sh`):

| chip_hr cache | misses (0.8 s) | first two frames | then, every frame |
|---|---|---|---|
| 16 KB (now) | 21,804 | 1.01 / 1.03 ms | ~1.0 ms |
| 64 KB | 20,145 | 0.93 ms (the largest of the run) | (not measured) |
| 128 KB | 3,948 | 0.92 / 0.93 ms | 0.13..0.14 ms |
| 256 KB | 1,540 | 0.92 ms (the largest of the run) | (not measured) |
| 16 KB, prefetched lines into way 0 only | 35,985 | 2.3 / 3.2 ms | 2.3..3.3 ms |
| 128 KB, prefetched lines into way 0 only | 4,216 | 0.92 ms | 0.06 ms |
| 128 KB, one victim pointer for all sets | 4,754 | 0.92 ms | 0.02..0.05 ms |
| 16 KB, one victim pointer for all sets | 33,380 | 2.2 / 3.2 ms | 2.0..3.5 ms |

From 128 KB the rows of the lines stay cached: only the cold start costs ~0.9 ms (below the 1.14 ms
lead). Keeping streams in one way, or one victim pointer for all sets, makes small caches lose
prefetched lines before their use.

A 128 KB chip_hr as it was cost 16.1K LUTs and 4.8K flip-flops (out-of-context synthesis,
`~/aexp-work/chiphr/oocsz.sh`): the prefetch bits (4 x 1024) and the round-robin pointers
(1024 x 2) were flip-flop arrays. Now the prefetch bit is part of the tag word (the tag RAM's one
write port also clears it, one clock after the first read, when no fill tag is written then; never
deferred, the line may be the victim of that fill), and the pointers are a LUT RAM written in the
clock after an issue. Same behaviour (the bench gives the same misses and lag at 16 and 128 KB to
the clock), and:

| out of context | LUTs | LUT RAM | flip-flops | BRAM tiles | slack at 49.35 MHz |
|---|---|---|---|---|---|
| 16 KB before | 2,710 | 324 | 1,082 | 4 | +3.93 ns |
| 128 KB before | 16,127 | 1,632 | 4,801 | 32 | +3.38 ns |
| 16 KB now | 987 | 368 | 507 | 4 | +3.77 ns |
| 128 KB now | 3,029 | 1,984 | 555 | 32 | +2.95 ns |

A bug in the first version: a read can hit a line in the very clock its tag is invalidated as a
fill's victim (the tag RAM still reads valid then); if the line was prefetched and unread, the clear
one clock later wrote its tag back VALID while the fill overwrote its data. The unit bench's usual
setups never met it; a new sim assertion ("the slot being filled is valid": from the clock after
the issue until f_done the slot is invalid) with 2 sets, a 256-word window and no pauses
(`TBARGS="-gG_SETBITS=1 -gG_WINDOW=256 -gG_PAUSE=0"`) failed seeds 1 and 3; fixed (no clear when
the slot was invalidated in the clock of the read), 6/6 seeds pass. `~/aexp-work/chiphr/mut.sh` runs
that setup too; the mutant set is `~/aexp-work/pause/pfmut3` (m15 the fill's tag write displaced
by the clear, m16 the clear in the wrong way, m20 without the new guard; p17..p19 performance only).

The worktree's mega65.vhd now asks for 128 KB (`G_SET_BITS => 10`, +28 BRAM tiles). Test build
r6rb-u = r6rb-t (32K FIFOs, the virtual lag) + the 128 KB cache (with that bug) FAILED timing:
WNS -0.501 on amiga_clk (WNS -1.547 by the intra-clock table): TG68K's 39-level path at -1.55 ns
(+0.20 in r6rb-t) and chip_hr's read path at -1.47 ns - the late chipset address through the
1024-deep tag LUT RAM and the hit way into the address of 32 block RAMs (17.9 ns of 21.2 ns
routing).

So the data RAM is now one block RAM per lane AND way: all four ways of the set are read at once,
the address (set and word) straight from the chipset address, and the way is picked after the RAM
by the registered hit way (`hway_r`). The tag lookup ends at flip-flops. Same 32 tiles at 128 KB
(at 16 KB it would cost 16 tiles instead of 4: 32 RAMB18s); same behaviour (unit bench counts and
the pause bench's misses and lag identical); out of context at 128 KB: 3,059 LUTs, slack +3.32 ns
(+2.78 before). Test build r6rb-v = r6rb-t + the 128 KB cache with the fix and the way-parallel
read: FAILED timing too, WNS -0.520 (amiga_clk -1.358): now the tag lookup itself - the chipset
address (fanout 684) through the 1024-deep tag LUT RAM into the miss request (`dq_line` CE -1.36)
and `go` (-0.88); in r6rb-t (16 KB) the same paths had +0.73 / +1.31. Logic about the same, routing
+2.2 ns: one tag RAM was placed at the far right (SLICE_X154, 3.5 ns there, 2.5 ns back).

So the prefetch's lookup (is the next line cached?) no longer uses a second read port of the tag
LUT RAM (which doubled it) but a block RAM copy of the valid bits and tags, written with the fill
tags (t_we) and read every clock at pq_set: its answer is a clock late, so a prefetch is issued only
when neither pq_line nor a tag was written in the clock before the last edge (`pq_age`). Out of
context at 128 KB: 1,958 LUTs (1,088 LUT RAM instead of 1,984), 34 tiles, +2.90 ns. The pause
bench: 21,798 misses / 1.04 ms at 16 KB, 3,948 / 0.93 ms at 128 KB (the prefetch a clock later
costs nothing visible). Mutants m22 (the copy used while stale) and m23 (the copy without the fill
tags) killed. Test build r6rb-w = r6rb-v + this.

r6rb-w: WNS -0.157 in the first pass, and its automatic re-rolls landed around -2 ns: the 128 KB
first level stays at the mercy of placement. Two answers, built in parallel:

- r6rb-x = r6rb-w with the Amiga clock at 1135/24 = 47.29 MHz (1.67 x instead of 1.74 x, +0.88 ns on
  every path; TEST BUILD, `RBDIV=24 rbstat.py`), to see on the hardware whether the cache size cures
  the shaking. Built: WNS +0.005 / WHS +0.015, 67.2K LUTs, 334 tiles. (The fetched
  `timing_summary_routed.rpt` is from before post-route phys_opt: it said -0.446; the build's
  RESULT line is the final state. The per-path numbers above are from those routed reports.)
- A second level (`G_L2_BITS`, r6rb-y), the design for the R3 - see below.

### A second level instead of a big first level (2026-11-05, r6rb-y)

The first level stays the 16 KB of r6rb-m..t (pf-v2: its tag lookup in the clock the chipset
address arrives has closed timing on every build); behind it a second level of 128 KB (4 ways,
1024 sets, 16-word lines) whose tags are LUT RAM read only at registered addresses (the fill's line,
the flushed line) and whose data is block RAM:

- a fill (demand or prefetch) first looks its line up there (M_L2, one clock): a hit copies the line
  in four 64-bit groups (M_L2C; the first level's eight byte lanes are written at once, its write
  data is now 64 bits) - about 6 clocks instead of ~1 us of HyperRAM; a miss invalidates the second
  level's victim (one rotating pointer for all sets: at 128 KB that was the better choice) and reads
  HyperRAM into both levels, the second level's tag written valid with f_done unless the fill was
  made stale;
- a write-back (flush) looks its line up at its start and writes every word it sends (with its byte
  enables) into the second level's copy, if there is one. Fills never read a line a write buffer
  holds (it is flushed first), so the second level is never older than HyperRAM plus the buffers;
  for the same reason validating a stale fill would also be harmless (mutant l3 survives), the
  check stays anyway.
- The write-through's data now loads whether the write hits or not (only the enables wait for the
  tag lookup): with 64-bit write data the old form cost 1 ns out of context (+2.75 instead of +3.72).

Out of context: 4,279 LUTs (1,476 LUT RAM), 1,346 flip-flops, 36 BRAM tiles, slack +3.72 ns (pf-v2
alone: +3.93). Pause bench with the Workbench-like load: 21,172 first-level misses, the first two
frames 0.93 ms (cold), then 0.12..0.15 ms a frame - as the 128 KB single level. Unit bench
`~/aexp-work/chiphr/tb_chip_hr2.vhd` (`run2.sh`, generic G_L2BITS: with 1..3 bits the second level
evicts constantly; up to 102K second-level hits a run): 10/10 setups pass; mutants
`~/aexp-work/pause/pfmut4` (`chiphr/mut2.sh`: pfmut2's set + l1..l9 for the second level): all
killed but m3 and m9 (as before) and l3 (equivalent, above); m8b, which used to survive, is now
killed. Pause regression PASS. Test build r6rb-y = r6rb-t + this: FAILED - not routable (1,150 nets
with partial route conflicts, WNS -0.99 after phys_opt): with the 32K FIFOs the block RAM is nearly
full (~360 of 365 tiles). r6rb-z = the same with 16K FIFOs (lead 559 us, -44 tiles; the worktree's
R3 setting): whether that lead is enough is what r6rb-t (the virtual lag) measures on the hardware.
r6rb-z built: WNS +0.042 / WHS +0.033.

**Hardware test of r6rb-z (2026-11-05, `rb_z.log`): no shaking.** The user's earlier tests (window
drags, selection rectangles) no longer shake the CRT. ~80 s of log: 0 underflows (also none at
boot), a first-level miss costs the Amiga ~200..250 ns on average (second-level hits; r6rb-r: ~1.2
us), wait 0.2..3.2 %, the largest virtual lag 342 us against the 559 us lead (1.6 x margin).
Also (user): an AGA demo with one part that slowed down severely in every earlier build (the Amiga
waiting on misses more than the 1.74 x clock could make up) runs that part at full speed on r6rb-z.

The pause bench's `regress.sh` had reported FAIL since the real-time video lines (RTFRAME, 2026-11-04
night) and the lag counters on the CHIPHR line: its compare did not filter them (`chk.sh` did), and
its OCS mutants (`mut.py`) were therefore "killed" by every run, three of them no longer even
matching the code. Fixed (the filter of `chk.sh`, "0 bad" anywhere in the line, the mutants
updated to the current code; "no flush before a fill" dropped, pfmut3's m6 covers it): PASS, 5/5
killed.

### Who writes the chip RAM's HyperRAM words (checked 2026-11-05)

Both cache levels assume every write to the chip RAM (and slow RAM) words, HyperRAM 300000-3FFFFF,
goes through chip_hr. On R3 with C_RB that holds:

- the core's HyperRAM port has two masters (`i_avm_arbit_rtg`): chip_hr (s1, in the RTG blitter's
  slot) and amiga_mem_r3 (s0, through the RTG write combiner): Fast RAM at words 100000-2FFFFF
  (`hr_word` = the Zorro II address) and, only without G_KICK_BRAM, the Kickstart at G_KICK_WORD =
  300000 - the chip RAM's words. G_KICK_BRAM => C_RB ties the two together; a build with C_RB and
  without G_KICK_BRAM would load the Kickstart over the chip RAM behind chip_hr's back;
- the cold-boot scrub writes through chip_hr's own port (ch_ram_* mux in front of it);
- the CPU's fast path to chip RAM (cpu_wrapper `sel_chipram`, turbo chip) is off: main.vhd
  `cachecfg` "110" (bit 0 = 0); `sel_kick_hr` only reads;
- ADF images (adf_sd: SD card), the IDE boot ROM (flp_bram: block RAM), the ADF/IDE-ROM arbiter tree
  (ends in flp_bram) and the AR3 loader (amiga_sdram, no SDRAM on R3) never reach HyperRAM;
- the framework's other masters: ascal writes only its framebuffer - RAMBASE 0, one buffer of
  2**ceil(log2(720 x 576 x 3)) = 2 MB = words 000000-0FFFFF (writes wrap inside it); triple buffering
  (M2M$ASCAL_TRIPLEBUF) would need 6 MB and run into the Fast RAM, but the firmware only ever writes
  the filter modes 0..4; QNICE's HyperRAM device (M2M$HYPERRAM 0x0004) is used only for ROMs of type
  C_CRTROMTYPE_HYPERRAM, and Megamiga has none (all ROM entries are QNICE devices).

## Next steps

1. DONE for r6rb-z (no shaking, 342 us of 559 us). Optional: r6rb-t (the needed lead with the 16 KB cache):
   CRT stability while Workbench draws, `LAG=16 rbstat.py` (the virtual lag per 1.36 s window).
   Then the FIFO depth for the R3 (14 or 15) and whether the 16-bpp scaler is still wanted.
2. Round-robin for the R3 (no RTG there): the framework arbiter's G_PRIORITY_HIGH per board.
3. TG68K's 41-level path is the only one near the edge at 49.35 MHz.
