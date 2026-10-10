# AExp / Megamiga — Amiga for MEGA65

Port of the MiSTer Minimig-AGA core to the MEGA65, built on the
MiSTer2MEGA65 (M2M) framework V2.0.1. Upstream is **AExp** by sy2002 (Amiga
500 OCS). This repo is the fork **Megamiga** (johansmolinski/Megamiga,
default branch `main`), which grew A500+/A600/A1200 profiles on top.

**This file is the always-loaded summary. The full dated engineering log of
every increment (design rationale, review findings, red/green proofs,
field results, build numbers) is `doc/developers/history.md` - read the
relevant entry there before touching a subsystem.** Keep this file short:
new increments get ONE entry in the index below and their long write-up in
the history file.

### Released and working - do not re-litigate these

- **AExp `V1`** (commit `46ef60c`, 2026-07-23; `VERSIONS.md` says
  2026-07-26): ADF df0: READ AND WRITE (daily use), video (HDMI + analog,
  interlace weave, screen adjustment), keyboard (both modes), mouse/
  joystick, battery RTC, Slow RAM toggle. Authoritative list: `VERSIONS.md`;
  alpha/beta history: `doc/inofficial.md`.
- AExp tags are `V1` and `WIP-V1-*`/`WIP-V2-*`. Version numbers like
  "V2.0.1" mean the **M2M framework**, never an AExp release. M2M's own tags
  (`V0.9.0`..`V2.0.1`, `Vivado-2019.2`) were removed 2026-08-02 and
  `remote.upstream.tagOpt=--no-tags` keeps them out; if they reappear,
  someone fetched upstream tags.
- **Megamiga releases** (tags on this fork): `V0.1.1` (R3-capable line;
  0.1.2 work at `225ec4c`), `V0.2.0` (A500+ mode, everything in SDRAM),
  `V0.3.0` (68020, Z3 RAM, AGA, SuperHires, machine profiles, nested
  submenus), `V0.3.1` (floppy buffers in SDRAM, master+slave HDF), 0.4.x
  (RTG card + blitter, text/plane masks/read-ahead, PMOD serial), 0.5.0
  (network card). All hardware-confirmed by the user except the PMOD
  serial port (no tester hardware).

### Increment index (details: `doc/developers/history.md`)

AExp Version 2 work (sy2002):

- `WIP-V2-A1` audio filters (A500 + LED), Stereo Mix, master volume.
- `WIP-V2-A2` Hardware Floppy read (the MEGA65's internal drive as an
  Amiga unit; 50 MHz flux front-end in `CORE/vhdl/physical_fdd/`).
- `WIP-V2-A3` three simulated drives df0..df2, all writable; per-drive
  FAT32 handles; `ADF_DUP_CHECK`. HW-verified. Working doc
  `.research/HANDOVER-multi-drive.md`. Three load-bearing rules: a drive is
  flushed only through ITS OWN handle; one image file never in two drives;
  no handle left FAT32-dirty across a return to the main loop (ONE shared
  sector buffer, owner tracked by ADDRESS).
- `WIP-V2-A4` HWF margin instrumentation (diag map v7).
- `WIP-V2-A5` registered diag readout + DPLL data separator (map v9).
- `WIP-V2-A6` sync-seam fix `frame_hold` (map v10; R6-built, field A/B).
- `WIP-V2-A7` hygiene: sync-anchored diagnostic word stream (map 0x000B).
- `WIP-V2-A8` Copylock read fix: real DSKBYTR observation surface in
  `paula_floppy.v`, A/B via diag 0x35 bit 8. Field-confirmed.
- `WIP-V2-A9` Hardware Floppy WRITE datapath (map 0x000D;
  `physical_fdd_writer.vhd`, trackwr EPISODE model, WGATE conjunction,
  ROM-faithful precomp, select/side hold through the post-DSKBLK drain).
  Field-proven on real Amigas; public alpha. If a write problem is ever
  reported: do not theorise - run the protocol at the top of
  `.research/HANDOVER-hardware-floppy-write.md`.
- `WIP-V2-A10` one drive by default (df0 = Disk Image), HWF docs pass,
  help-page geometry checks, `DVI (no sound)` toggle.

Megamiga fork (johansmolinski):

- 0.1.x: 8 MB Zorro II Fast RAM (`WIP-V2-A11-JS-01`), RIPPLE-compatible
  IDE board + firmware ATA server for HDF (`-JS-02`, patched lide.rom),
  rename to Megamiga 0.1.1, direct SD block I/O + HD LED (0.1.2).
- 0.2.0 (`a500plus`): A500+ mode, Minimig `sdram_ctrl.v` at 113.5 MHz,
  ALL Amiga memory in SDRAM (R3 dropped), Kickstart selector, fast ADF I/O
  + progress bar, LED colours, drive spin-up delay.
- 0.3.0: 68020 (TG68K) + 16 MB Z3 RAM, AGA (chip48), SuperHires (pixel-pair
  averaging), machine profiles A500/A600/A1200 with per-profile ROM/HDF,
  M2M exception 11 nested submenus.
- 0.3.1: floppy buffers moved from HyperRAM to SDRAM (third
  `sdram_ctrl` port; floppy path reset by `main_rst`, NEVER
  `main_reset_m2m_i`), master + slave HDF, eject with SPACE.
- 0.4.x: RTG card (Picasso96, ascal framebuffer, VRAM in HyperRAM,
  `rtg_vram`/`rtg_wcomb`/`rtg_blitter`, driver in `CORE/rtg/`), profile
  names at core start, PMOD serial port (0.4.2).
- 0.5.0: network card (own Zorro II board, RMII MAC, SANA-II driver in
  `CORE/eth/`; design in `doc/developers/ethernet.md`).

Out-of-repo testbenches for all fork increments live under `~/aexp-work/`
(see the "Local test setup" memory); every history entry names its TB and
mutant set.

## The emulated machine (current, Megamiga 0.5)

- **Profiles** A500 (OCS) / A600 (ECS) / A1200 (AGA), each with CPU
  (fx68k 68000 or TG68K 68020), chipset, Chip RAM 512K/1M/2M, Slow RAM,
  Z2 Fast RAM (8 MB), Z3 RAM (16 MB, 020 only). `prof_decode` in
  `mega65.vhd`; firmware `PROFILE_APPLY` loads `/amiga/a500.rom|a600.rom|
  a1200.rom` (fallback `kick.rom`, which is mandatory at boot) and
  `aNNN.hdf` / `aNNN-1.hdf`. Changes cold-boot via `amiga_cold_boot`.
- **Memory**: all Amiga memory in the board SDRAM (R4/R5/R6 only), Minimig's
  `sdram_ctrl.v` at 113.5 MHz = 4x the 28.375 MHz core clock (native MMCM;
  the HDMI flicker-free fast twin is disabled in this mode). Bank 0 chip/
  slow/kick + the 8 MB floppy area (column bit 9 = 1), bank 1 Z2, banks 2/3
  Z3. HyperRAM: ascal framebuffer + RTG VRAM (byte `$400000`, 4 MB).
- **PAL only.** Video CE never 28 MHz (SuperHires pixel pairs averaged).
- **Floppy**: df0..df2, each Disk Image (ADF r/w, buffered in SDRAM,
  written back to SD in the background via `HANDLE_CORE_IO`) or the
  Hardware Floppy (read + write, at most one unit). Default: one drive.
- **IDE**: RIPPLE-compatible Zorro II board, master + slave HDF,
  `/amiga/lide.rom` boot ROM.
- **RTG**, **network card**, **PMOD serial**, audio filters/stereo/volume,
  battery RTC.

Note: parts of the sections below (hard rules 3-5, the architecture cheat
sheet, the roadmap) were written for the AExp A500/BRAM design and are
marked where the fork superseded them; when in doubt, the history file has
the dated facts.

## Repository map

- `M2M/` — the framework. **NEVER modify**, with FOURTEEN sanctioned
  exceptions (all testbeds for a later M2M upstream merge, tagged
  `M2M-UPSTREAM <name>` in-code, greppable): (1) `interlace` — new
  `video_fl_i` input through framework → av_pipeline → digital_pipeline
  → ascal `i_fl`, `INTER => true`; new inputs default to '0'
  (progressive cores unaffected). (2) `core-io-hook` — `HANDLE_CORE_IO`,
  an 8th mandatory core callback called from `HANDLE_IO` (shell.asm,
  at the `_HANDLE_IO_0` label): a per-iteration time slice in the main
  loop AND all blocking wait loops (OSM/browser/help), for background
  tasks like non-vdrives write-back caches; contract: preserve all regs,
  return fast, may change RAMROM selection. (3) `screen-center` — the
  screen-adjustment plumbing (issue #5): (a) four signed per-edge offsets
  threaded framework → av_pipeline (`i_qnice2video` CDC) → digital_pipeline
  driving ascal's INPUT crop (`iauto=0`, `himin/himax/vimin/vimax`) for HDMI
  (hardware-verified 2026-07-09); (b) four signed analog OVERSCAN soft-blank
  edges (hardened `p_vga_softblank`, feeds only the analog pipeline); (c) two
  signed analog PAN inputs (gp_reg words 8-9) into the new
  `analog_positioner.vhd`, a post-OSM/pre-CSYNC sync-phase shifter (2026-07-13,
  awaiting synthesis). All new inputs default to 0 = bit-identical for other
  cores.
  (4) `osm-hotkey` — three core-driven inputs (`osm_key_a_i`/`osm_key_b_i`
  default 67=Help, `osm_combo_i` default '0') threaded core →
  `framework.vhd` → `m2m_keyb.vhd` so the core picks which key(s) drive the
  menu-open bit (`qnice_keys` bit 7, the *ungated* scan); the defaults
  reproduce the classic Help-only behaviour and leave the firmware ROM
  byte-identical, so every existing M2M core is unchanged. Issue #8,
  2026-07-11 — implemented, awaiting synthesis; **the 4th exception still
  needs sy2002's explicit sign-off** (spec §8).
  (5) `osm-scale` — a RAM-inference override: `tdp_ram.vhd` gains a
  `RAM_STYLE_SELECT` generic (default `"auto"` = every existing caller
  unchanged) driving the block RAM's `ram_style`; `ascal.vhd` uses it to pin its
  shallow async ping-pong buffers (`i_dpram`) to `"distributed"` LUTRAM.
  Otherwise Vivado maps them to BRAM, burning 4 RAMB36s AND absorbing `avl_dr`
  into the BRAM output, invalidating the ascal-FIFO CDC max-delay endpoints
  (`CORE/CORE.xdc`) that MEGA65 cores depend on.
  (6) `raw-joyports` — `M2M/vhdl/debouncer.vhd`: the ten `work.debounce`
  instances (1 ms stable-time) replaced by plain 2-FF synchronizers, so the DB9
  direction/fire (and mouse quadrature) lines reach the core raw — authentic (a
  real Amiga has no DB9 debouncing) and mandatory for quadrature mice, whose fast
  pulse trains the 1 ms filter swallowed (frozen-then-jumping pointer). Port-flip
  + joy on/off gating kept; `CLK_FREQ`/`reset_n` now unused. sy2002-approved
  2026-07-22, to become a framework option when upstreamed.
  (7) `floppy-pins` — the four board tops route the 11 read-path floppy pins
  (f_motora/f_selecta/f_side1/f_stepdir/f_step/f_density + the 5 inputs)
  into `MEGA65_Core` for the Hardware Floppy feature (the C64MEGA65
  issue-#90 pattern: board top → core direct, `framework.vhd` untouched);
  f_motorb/f_selectb/f_wdata/f_wgate stay tied '1'. sy2002-approved
  2026-07-26.
  (8) `osm-deps` — SMART MENU DEPENDENCIES, backported from C64MEGA65 issue
  #229 (dependency format 2): a menu line can be tagged in config.vhd with
  `OPTM_DEP`/`OPTM_DEP2` so that it is only visible while one of the items
  of a "mother" group is selected. New `M2M/rom/optm_deps.asm`, plus
  `M2M$CFG_OPTM_DEPS`, `OPTM_IR_DEPS`, the third visibility pass in
  `_OPTM_STRUCT`, the live redraw and cursor normalisation in `_OPTM_RUN`,
  the `OPTM_SELECT` carry guard, the boot validator call and the five
  `ERR_F_DEP*` strings. Every line is unconditionally visible when
  config.vhd does not serve the feature probe, so other cores are
  unaffected. AExp needs it for the per-drive twin lines: this instance
  additionally allows dependent `OPTM_G_LOAD_ROM` lines, PARTIALLY VISIBLE
  radio groups and two-level chains, which is why `OPTM_DEPS_VAL` classes
  2 and 3 are weaker here than in the C64 original (reasons in its header).
  (9) `live-text` — `OPTM_LIVE_TEXT` (+ its `_OPTM_LT_ISEND` helper) in
  `M2M/rom/menu.asm`, backported from C64MEGA65, where it drives the live
  status field of the `8:Internal 1581` line. It replaces a fixed-width slice
  of one menu item in the writable `OPTM_IR_ITEMS` heap copy and repaints just
  those characters when that line is visible; it never triggers the fatal menu
  callback. AExp uses it for the live Hardware Floppy status in the three
  `dfN:Hardware Floppy` twin lines. **Purely ADDITIVE** — nothing else in the
  framework calls it, so every other core is byte-identical. One deliberate
  difference to the C64 original: M2M V2.0.1 has no `OPTM_FOREGROUND` flag and
  introducing one would mean touching `OPTM_RUN` and the selection-callback
  path, so the "does the menu own the screen right now" question is left to the
  caller (AExp answers it with `M2M$CSR_OSM` + its own `OSM_SUB_ACTIVE` +
  `OPTM_MENULEVEL`). Getting that wrong is cosmetic, never fatal.
  sy2002-approved 2026-08-04. When this goes upstream it should grow the
  `OPTM_FOREGROUND` flag of the C64 original, so the "does the menu own the
  screen" test lives in the framework instead of in each caller.
  (10) `sdram-pins` — the R4/R5/R6 board tops route the SDRAM pins into
  `MEGA65_Core` for the 8 MB Zorro II Fast RAM (`fastram_sdram.vhd`), the
  floppy-pins pattern (board top -> core direct, `framework.vhd` untouched,
  original tie-offs kept as comments). Added in the JS fork 2026-10-06,
  NOT maintainer-approved yet.
  (11) `nested-submenus` — `M2M/rom/menu.asm` + `menu_vars.asm`: submenu
  openers inside submenus (parent table + level stack in `_OPTM_STRUCT`,
  closers return to the parent level). Flat menus are unchanged. Added in the
  JS fork 2026-10-08 for the Megamiga 0.3 Settings page, NOT
  maintainer-approved yet.
  (12) `rtg-framebuffer` — ascal's framebuffer mode driven by the core:
  `fb_*` ports (enable, size, format, base, stride, 8bpp palette) through
  top_mega65-r4/5/6 -> framework -> av_pipeline -> digital_pipeline, and
  `PALETTE2 => true`. Defaults keep every other core unchanged. Added in the
  JS fork 2026-10-09 for the RTG card, NOT maintainer-approved yet.
  (13) `pmod-pins` — the R4/R5/R6 board tops route the PMOD headers
  (`p1lo/p1hi/p2lo/p2hi_io`, `pmod1_en_o`/`pmod2_en_o`) into `MEGA65_Core`
  for the Amiga serial port (floppy-pins pattern, original tie-offs kept as
  comments). mega65.vhd keeps every pin high-Z and both headers unpowered
  unless `Settings > Ports > Serial port on PMOD` (`C_MENU_SERIAL` 204) is on;
  pin layout = MegaST's (PMOD1 lo CTS/TXD/RXD/RTS, hi MIDI OUT/IN mirroring
  the same Paula UART). Pull-ups on the three inputs in CORE.xdc. Added in
  the JS fork 2026-10-09, NOT maintainer-approved yet.
  (14) `eth-pins` — the R4/R5/R6 board tops route the Ethernet PHY pins
  (`eth_clock_o`, `eth_led2_o`, `eth_mdc_o`, `eth_mdio_io`, `eth_reset_o`,
  `eth_rxd_i`, `eth_rxdv_i`, `eth_rxer_i`, `eth_txd_o`, `eth_txen_o`) into
  `MEGA65_Core` for the network card (floppy-pins pattern, original tie-offs
  kept as comments). Added in the JS fork 2026-10-09, NOT maintainer-approved
  yet.
  All other framework fixes
  go into `CORE/CORE.xdc` (constraints) or get documented for upstreaming.
  Git remote `upstream` = sy2002/MiSTer2MEGA65 (master = V2.0.1).
- `CORE/vhdl/` — the port (all files ours):
  - `mega65.vhd` — BRAM lanes (2×256K×8 chip, 2×256K×8 slow, 2×128K×8
    kick), banked-address decode, QNICE devices 0x0100 (kick) + 0x0103
    (ADF), HyperRAM plumbing (avm_fifo CDC + 2-master arbiter →
    hr_core_*), OSM wiring
  - `main.vhd` — wraps minimig_m65 + cpu_wrapper + amiga_clk; fx68k phase
    enables, frame-locked video CE, sync inversion, interlace field
    export (`video_fl_o` ← minimig `field1`), reset mapping, host
    bus mux (amiga_config ↔ adf_track_engine) + avm_cache
  - `amiga_config.vhd` — FSM replaying MiSTer's HPS config via the userio
    protocol after every reset (0xF1=0x07 halt+reset, 0xF3=OCS,
    0xF4=68000, **0xF5=0x04** = 512K+512K, 0xF6/0xF7/0xF8/0xF9/0xF2=0,
    0xF1=0x00 release)
  - `adf_mount_wrapper.vhd` — QNICE device 0x0103: byte-window bridge
    into HyperRAM + M2M CSR (window 0xFFFF) + ADF size validator
    (160–166 tracks × 5632 bytes; "mounted"+track count → cdc_stable)
    + write-back CSR "WBC" (window 0xFFFE: WR_EN, 166-bit dirty bitmap
    W1C, anti-thrash ms countdown, dirty-event receiver)
  - `adf_track_engine.vhd` — Paula floppy host service (MiSTer HandleFDD
    in hardware): 1 ms poll + drive-status re-announce, per-sector MFM
    streaming with status-bit-8 flow control, MFM write decoder
    (drain-and-commit: verified sectors → HyperRAM via avm writes,
    dirty-track events → wrapper via two-phase cdc_stable toggle
    handshake); since WIP-V2-A2 also the Hardware Floppy backend (per-unit
    dispatch on the status sel bits, real-flux word streaming, dsksync
    export, drain-discard for physical writes); the protocol contract is
    documented in its header
  - `physical_fdd/` — the Hardware Floppy 50 MHz read front-end (pkg,
    input conditioner, runt-filtered gap stage, adaptive quantiser,
    raw-bit rebuild + DSKSYNC aligner, dual-clock word FIFO, top, QNICE
    diag device 0x0104); codec stages adapted from the C64MEGA65
    physical-1581 bring-up (hardware-proven at exactly this clock)
  - `keyboard.vhd` — MEGA65 keys → raw Amiga scancodes (kms_level toggle)
  - `clk.vhd`, `globals.vhd`, `config.vhd` (OSM menu — bit = line number,
    must match `C_MENU_*` constants in mega65.vhd; exception: the HDMI
    Filter radio, lines 19–26, is read by the firmware (`OSM_FLT_*` in
    m2m-rom.asm must mirror them), not mega65.vhd; VGA radio lines
    32/36/37)
- `CORE/m2m-rom/` — core QNICE firmware (`m2m-rom.asm`): ADF size guard
  + ADF write-back (`HANDLE_CORE_IO` + `FLUSH_ADF_STEP`: FDH snapshot,
  SD-change + SD-slot guards, per-chunk fflush, force-flush + disarm in
  `PREP_LOAD_IMAGE` — the §5a arm-state invariant of the write spec)
  + HDMI Filter dispatcher `LOAD_HDMI_FILTER` (C64MEGA65-V6 port;
  `ASCAL_USAGE=1`, includes a backported `M2M$LOAD_POLYPHASE` — delete it
  when M2M is upgraded to V2.1+; coefficient blobs in `video_filters/`).
  OSM menu constants are autogenerated: `make_rom.sh` scrapes `C_MENU_*`
  (mega65.vhd) and the core `OPTM_G_*` (config.vhd) into `osm_const.asm`
  (`AEXP_OSM_*` / `AEXP_OPTM_G_*`, gitignored) — no hardcoded menu
  indexes in the firmware. The OSM settings file (72 bytes = OPTM_SIZE;
  SD name `/amiga/aexp-<CORE_VERSION>.cfg`) is generated by
  `make_release.py` at packaging — no tracked master. `CORE_VERSION` in
  config.vhd is the single version source (welcome/help
  screens, CORENAME, CFG_FILE all derive from it; `make_release.py`
  validates it and packages releases, alpha rows live in
  `doc/inofficial.md`).
- `CORE/Minimig_MiSTerMEGA65/` — git submodule, upstream
  MiSTer-devel/Minimig-AGA_MiSTer. Branch **develop** carries all
  Xilinx/MEGA65 changes; **MiSTer** mirrors upstream; **master** is the
  released state (= `develop` at each AExp release). Every change to
  original files has a dated provenance comment with original code kept
  commented out. `rtl/minimig_m65.v` is our VHDL-friendly rename shim
  (minimig.v has leading-underscore ports = illegal VHDL identifiers).
- `M2M/QNICE/` — git submodule, the QNICE-FPGA fork
  johansmolinski/QNICE-FPGA, branch **fat32-fastseek** (based on the commit
  M2M V2.0.1 pins, `2eb27dd`). It adds a fast `FAT32$FILE_SEEK` (cluster
  stepping, FAT sector cache, forward from the current position, exact EOF,
  `FAT32$ERR_CHAIN` on damaged chains), extent maps (`FAT32$FILE_MAP` +
  `FAT32$FILE_SEEK_MAP`, syscalls `f32_fmap`/`f32_fseekm`) and fixes
  `FAT32$FLUSH` returning a stale R9 for R8 = 0. Tests:
  `M2M/QNICE/test_programs/fat32_seek/run.sh` (emulator + generated FAT32
  images, `--compare REV`, `--mutants`). The firmware assembles this library
  from source but takes constants from the generated `dist_kit/sysdef.asm`,
  which `CORE/m2m-rom/make_rom.sh` therefore refreshes on every build.
- `CORE/CORE-R{3,4,5,6}.xpr` — one Vivado project per board.
- `doc/` — the knowledge base. `.research/` — untracked local research
  notes (integration specs, review reports); never committed.

## Hard rules (each learned the expensive way)

1. **Keep all four .xpr files in sync** — every file-list or file-type
   change goes to R3+R4+R5+R6 in the same commit. Expected per-board
   deltas (do NOT "fix"): board top, board XDC, R3 `max10.vhdl` +
   `pcm_to_pdm.vhdl` vs R4+ `audio.vhd`.
2. **.xpr SFType tokens**: only `VHDL2008`, `SVerilog`, or *no attribute*
  (extension-inferred). Anything else (e.g. "Verilog", "SystemVerilog")
  makes Vivado **segfault on project open** (hs_err with
  `HDDASrcFileType::getId`).
3. *[AExp era - since Megamiga 0.2.0 the Amiga memory is in SDRAM and BRAM
   is ~61/365; the rule still holds for the AExp upstream.]*
   **BRAM is at 363.5/365 tiles — full.** All future buffers (ADF images,
   sector buffers, monitor ROMs) MUST live in HyperRAM. Re-enabling
   IDE (+8 tiles) does not fit. The 320 Amiga tiles are an exact mapping,
   nothing left to squeeze.
4. **No QNICE ports on die-spread BRAMs.** QNICE reads/writes RAMs on the
   falling clock edge = half-period (10 ns) budget; the address bus
   cannot reach 256 spread tiles in time (cost us WNS −0.757). Only the
   kick ROM (64 tiles) has a QNICE port.
5. *[Number is AExp-era; the Megamiga builds close at +0.02..+0.3 ns, so
   the rule matters even more.]* **Timing margin is thin (+0.387 ns).** Check the timing summary after
   every build. The ascal FIFO CDC constraints in `CORE/CORE.xdc`
   (set_max_delay -datapath_only) are load-bearing — they cut phantom
   ps-requirement inter-clock paths AND the hold-fix router detours.
6. **Video into the framework**: active-HIGH syncs (minimig outputs are
   active-low — inverted in main.vhd), blanks must cover syncs, video CE
   is frame-locked 7.09/14.19 MHz and **never** 28 MHz (M2M line buffers:
   video_mixer LINE_LENGTH=768, ascal IHRES=1024),
   `qnice_scandoubler_o='1'` (15.625 kHz core!).
7. **OPTM_PAUSE stays false** — pause_i is not implemented in the core.
8. Commit as **sy2002 <code@sy2002.de>** (repo-local git config is set).
   Do NOT add a `Co-Authored-By: Claude` trailer — Claude is credited in
   the `AUTHORS` file instead.
9. Do not delete `/tmp/claude-501` task outputs (deny rules in
   `.claude/settings.local.json`); tell workflow subagents not to run
   cleanup commands.
10. `CORE/m2m-rom/make_rom.sh` scrapes globals.vhd (`C_VDNUM`/
    `C_CRTROMS_*_NUM`), mega65.vhd (`C_MENU_*` → `AEXP_OSM_*`) and
    config.vhd (core `OPTM_G_*` → `AEXP_OPTM_G_*`) via awk into generated
    .asm files — keep all those constants single-line; the Vivado
    pre-synth hook rebuilds the firmware, so menu changes need a
    synthesis (or VM-side make_rom.sh) to reach the ROM. Changing
    `OPTM_SIZE` ⇒ `make_release.py` generates the matching settings file
    at packaging (no tracked master; manual for dev SD cards:
    `M2M/tools/make_config.sh <name> auto` from inside `M2M/tools`).
11. **Every OSM growth needs a QNICE heap rebudget.** `OPTM_SIZE` is not
    only the settings-file length: `HELP_MENU` copies the item string plus
    three `OPTM_SIZE` arrays into `MENU_HEAP_SIZE`, then uses the remainder
    as `OPTM_HEAP` for one `SCR$OSM_O_DX`-wide (`OPTM_DX + 2` frame
    characters) buffer per vdrive, submenu and manual ROM, plus one scratch
    buffer. After changing `OPTM_SIZE`,
    `OPTM_ITEMS`, `OPTM_DX`, or any of those counts, verify both
    `LOG_HEAP1`/`LOG_HEAP2` budgets (a fatal naming `MENU_HEAP_SIZE` or
    `OPTM_HEAP_SIZE` is the corresponding failed check). If
    `MENU_HEAP_SIZE` changes, normally subtract the identical delta from both
    debug and release `HEAP_SIZE` constants so the combined heap totals stay
    unchanged. Only raise a combined total after the assembled `HEAP`/stack
    addresses prove that `STACK_SIZE` still fits. Keep `MENU_HEAP_SIZE` tight:
    every extra word directly reduces
    file-browser capacity (a file entry costs three list words plus its name,
    terminator and directory flag) - `FB_HEAP` literally starts at
    `HEAP + MENU_HEAP_SIZE` (`M2M/rom/shell.asm`). **Round the calculated
    demand up to the next 32-word boundary and no further.** This rule used to
    say 128, which was harmless while it happened to cost 6 words at 146 items
    but would have left 107 dead words at 148. Allocating tight is safe
    because a shortfall is LOUD rather than silent: `HELP_MENU` checks the
    permanent structure against `MENU_HEAP_SIZE` (`ERR_FATAL_HEAP1`) and the
    `OPTM_HEAP` demand against the remainder (`ERR_FATAL_HEAP2`), so the core
    stops with a fatal screen at boot and on every menu open, and
    `check_osm_menu.py` recomputes the demand statically long before that.
    The demand is fully static: every term comes from config.vhd constants,
    and `SCR$OSM_O_DX` is latched once at screen init from `M2M$CFG_OPTM_DIM`
    (OSM Scaling scales the overlay in hardware, not the character grid).
    The exact demand
    formula (from `HELP_MENU` in `M2M/rom/options.asm`): 20 (menu struct) +
    `OPTM_ITEMS` string chars (`\n` = 2 chars) + 1 (terminator) + 4 ×
    `OPTM_SIZE` + 1, plus (vdrives + submenus + manual ROMs + 1) ×
    (`OPTM_DX` + 2) for `OPTM_HEAP`. The struct is 20 words and there are FOUR
    per-item arrays since the menu-dependency backport (M2M exception 8); the
    boot-time dependency validator transiently needs 20 + 3 × `OPTM_SIZE`,
    which is always far below the permanent demand. Since the A10 DVI item,
    the 148-item menu needs exactly 2325 words and uses `MENU_HEAP_SIZE` 2336,
    headroom 11 (it was 146 items / 2298 / 2304 / headroom 6 from WIP-V2-A3 up
    to that point, so the A10 edit moved both `HEAP_SIZE` constants down by 32,
    not by the 128 the old rounding rule would have cost) —
    `.research/check_osm_menu.py` recomputes all of this from
    `config.vhd`. WIP-V2-A11-JS-01 (Memory submenu with the Fast RAM toggle)
    grew the menu to 154 items: demand 2434, `MENU_HEAP_SIZE` 2464 (headroom
    30), both `HEAP_SIZE` constants -128 (debug 4576, release 27616).
    **Firmware VARIABLES count too**, even though this rule is about the menu:
    they sit below the heap, so every word added there pushes `HEAP` up and
    comes straight out of the stack. The per-drive write-back and the live
    Hardware Floppy status line added 66 variable words, so the combined total
    was lowered from the C64 figure of 30208 to **30080** to buy the margin
    back: `HEAP=0x8280` + 30080 = `0xF800` against `VAR$STACK_START 0xFEE0`
    leaves 1760 words for a `STACK_SIZE` of 1536. Recheck both live heap
    budgets and the `HEAP`/`VAR$STACK_START` symbols in `m2m-rom.lis` manually
    whenever the menu or the firmware variables grow.

## Build & verification workflow

- **No Vivado on this Mac.** It runs in the user's Parallels Ubuntu VM on
  a shared folder. Prepare everything, then ask the user to synthesize
  and return: `CORE/CORE-R3.runs/synth_1/runme.log`,
  `impl_1/*_utilization_placed.rpt`, `impl_1/*_timing_summary_routed.rpt`,
  `impl_1/*_route_status.rpt`. Per-module BRAM: ask for
  `report_utilization -hierarchical`.
- **QNICE firmware**: the Vivado pre-synth hook rebuilds it inside the
  VM on every build — the VM works directly in this (mounted) folder,
  which is why `M2M/QNICE/assembler/qasm`/`qasm2rom` are Linux ELF
  binaries. Never overwrite them, and NEVER run
  `CORE/m2m-rom/make_rom.sh` on the Mac: the `asm` wrapper deletes
  `m2m-rom.out`/`m2m-rom.rom` BEFORE assembling, then dies on the Linux
  binaries. For Mac-side sanity checks compile temporary native tools
  into a temp dir (`cc -O2 -o "$TMP"/qasm M2M/QNICE/assembler/qasm.c`,
  same for `qasm2rom`), then from `CORE/m2m-rom`: `cc -xc -E
  m2m-rom.asm | sed '/^#.*/d' > __t.asm && "$TMP"/qasm __t.asm
  m2m-rom.out && "$TMP"/qasm2rom m2m-rom.out m2m-rom.rom` (verified to
  produce a `.def`-identical ROM vs the VM build).
  **The firmware ROM must end below `0x7000`**: M2M maps the 4K RAMROM/device
  window at `0x7000`-`0x7FFF`, so only 28672 words of the 32K-word QNICE ROM
  are usable; `make_rom.sh` enforces this (ported from the C64 core): it
  derives the image size from the serialized addresses rather than from
  the `.rom` line count, which qasm2rom inflates with the zero words of the
  RAM variables, cross-checks it against the `END_OF_ROM` label (which must
  stay the last ROM item before `.ORG 0x8000`), trims the variable words
  off the image and fails the Vivado build loudly on overflow or on a
  layout qasm2rom cannot serialize. `WIP-V2-B1` uses 27533 words, 1139
  free; the VM log line to look for is `Shell ROM: N/28672 words.`
  **Megamiga (fork):** the fork's firmware had grown past `0x7000` before this
  guard arrived (0x75D5 - ADF tables in the window silently broke ADF
  filtering, SPACE eject and the fast load), so the long texts and the core's
  three filter tables live in `m2m-rodata.asm`, a read-only QNICE device
  (`C_DEV_AMIGA_RODATA` 0x0109, 4K-word preloaded block RAM in mega65.vhd);
  `make_rom.sh` assembles it first and exports its labels as window addresses
  (`rodata_sym.asm`). Texts are used through `RODATA_STR`/`RODATA_PUTS` (RAM
  copy), filter tables through `M2M$LOAD_POLYPHASE` (any table >= 0x7000).
  After the upstream merge: 28211/28672 words. Move more constant data there
  when the ROM fills up again - never reference a rodata label directly.
- **The QNICE submodule tracks `dev-V1.61`** (upstream AExp; in the Megamiga
  fork it is the branch `fat32-fastseek` of johansmolinski/QNICE-FPGA, which
  merged `dev-V1.61`/`2541cce` on 2026-10-08 on top of the fast seek;
  `.gitmodules` `branch`, update with `git submodule update --remote
  M2M/QNICE`, the pre-synth hook reassembles the firmware against the new
  monitor). That branch carries two FAT32 library fixes under the ADF
  write-back: the sector buffer is written back before `DIR_OPEN`/`FILE_OPEN`
  re-fill it (`a937af2`, the single-buffer-owner hazard the firmware also
  guards against itself, see hard rule 11 and the write spec) and the 32-bit
  sector-address overflow check (`2541cce`). The M2M V2.0.1 template pins the
  2024 commit `2eb27dd`, 13 commits behind; a template sync must never drag
  the pointer back there.
- **Headless QNICE menu regression**: `M2M/rom/menu_percent_test.asm` runs
  the real `OPTM_SHOW` scanner and guards the C64 `%`-at-end-of-label fix.
  The pinned QNICE (`dev-V1.61`) ships the emulator's headless batch mode
  (`-b`, one or more `.out` images), so build the POSIX terminal flavour
  from `M2M/QNICE/emulator` and use it as `$QNICE_HEADLESS`. Assemble the
  test with the native/VM assembler, then run `$QNICE_HEADLESS -b 0x8000
  M2M/QNICE/monitor/monitor.out M2M/rom/menu_percent_test.out`. Expected:
  `PASS: percentage labels preserve later %s indices`. Run this after every
  change to `M2M/rom/menu.asm` or percentage-bearing `OPTM_ITEMS` labels.
- **Local static checks before any Vivado round-trip** (installed:
  nvc 1.21, ghdl 5.1, iverilog). Two Python checkers live in `.research/`
  (untracked, like the rest of it): `check_osm_menu.py` recomputes
  `OPTM_SIZE`, the submenu balance, the `OPTM_DEP` rules, the worst-case
  visible height per menu view and the `MENU_HEAP_SIZE` demand from
  `config.vhd`, and cross-checks every `C_MENU_*` constant in `mega65.vhd`
  against the TEXT of the line it addresses - run it after ANY menu change.
  `check_firmware.py` checks the per-drive tables and arrays against
  `ADF_DRIVES` and requires every `ADDC`/`SUBC` in `m2m-rom.asm` to take its
  carry from a producer that writes the same storage class; on QNICE only
  `ADD`/`ADDC`/`SUB`/`SUBC`/`SHL`/`SHR` write Carry and `MOVE` does not, so
  inserting address arithmetic between a 32-bit `ADD` and its `ADDC` silently
  eats the carry (this exact slip once made the ADF write-back address every
  chunk past a 64 KB boundary 64 KB too low). Then analyze all CORE VHDL with
  `nvc --std=2008` in dependency order (M2M packages first: tools.vhd,
  types_pkg, video_modes_pkg, tdp_ram, 2port2clk_ram); clk.vhd/mega65.vhd
  need stub `unisim`/`xpm` vcomponents packages (recipe in memory).
  iverilog `-g2012 -t null` over the kept
  Verilog set with stubs for `dpram` and `fx68k`. Known noise to ignore:
  forward references, fx68k unpacked structs, zero-width-concat
  follow-ons.
- Synthesis log checks: `microrom.mem`/`nanorom.mem` "read successfully"
  (silent failure = dead CPU with no error), Amiga RAMs as block RAM,
  `Synth 8-5835` (BRAM over-utilized, "Will try to implement using LUT-RAM")
  now fires routinely — BRAM sits at 365/365, so Vivado spills the excess to
  LUT-RAM and the build still fits; it is a real failure only if implementation
  then cannot place/route. Vivado OOM in the VM: close the implemented design in
  the GUI before relaunching a run.

## Architecture cheat sheet

- **Fast RAM bus** (R4+, when enabled): Zorro II cycles leave the chip bus in
  `cpu_wrapper.v` (`ramsel`, DTACK from `ramready`) and go to
  `fastram_sdram.vhd` on the core clock; everything else is unchanged.
- *[AExp era: the BRAM memory bus below; Megamiga serves it from SDRAM via
  `amiga_sdram.vhd` + `sdram_ctrl.v`, HyperRAM `hr_core_*` now carries RTG
  VRAM.]*
- **Memory bus**: with 68000 + no fast RAM, ALL memory traffic (CPU +
  chipset DMA) flows through minimig's single SRAM-style port
  (`ram_addr[22:1]` word address + `_bhe/_ble/_we/_oe`). The address is
  BANKED by `minimig_sram_bridge.v`: chip at `[22:19]="0000"`, slow at
  `[22:19]="1000"`, kick at `[22:19]="1111"` (bit 18 ignored = F8/FC
  mirror). 1-cycle BRAM latency meets the 7.09 MHz bus easily; read-mux
  select is registered to match.
- **QNICE device bus**: `qnice_dev_id_i` ≥ 0x0100, 4k windows, byte
  addresses; kick = 0x0100 (lane U = even byte = bits 15:8, so raw ROM
  dumps load unmodified); 0x0101/0x0102 reserved (chip/slow, unwired).
- **Host/userio channel**: `IO_UIO` carries config commands (driven by
  amiga_config.vhd); `IO_FPGA` is Paula's floppy channel (tied 0 —
  the future floppy service and the RamDump upload engine plug in here /
  via cmd 0xF0 mem_write through the halted m68k_bridge).
- **HyperRAM**: 8 MB, Avalon-MM via `hr_core_*` ports (currently tied
  off), 100 MHz, ~9 cycles latency after CDC, arbiter shared with the
  ascal framebuffer. Core address space from `C_HMAP_DEMO` (0x0200, 4kW
  units). Pattern for core→HyperRAM: avm_cache + avm_fifo CDC (reference:
  C64MEGA65 REU chain).
- **Reference port**: /Users/mirko/.dev/MEGA65/C64MEGA65 — consult it for
  every M2M integration pattern (vdrives, CRT/PRG loaders, OSM, LEDs).

## Roadmap

*[AExp roadmap as of 2026-07; the fork's work is in the increment index.]*

1. **Floppy: ADF read/write DONE and RELEASED in Version 1 (tag `V1`).**
   Read-only landed 2026-07-03, write 2026-07-05 (`WIP-V1-A4`), and both
   rode through A5..A11 and the release candidates B2/B3 into the Version 1
   release. This is a working, shipped, daily-driven feature - do NOT
   re-open it as "unverified". The only thing still unrecorded is the
   formal write test matrix
   (`.research/INTEGRATION-SPEC-floppy-adf-write.md` §8: WB rename
   persists across power cycle, format, write+verify, swap-while-dirty,
   wprot regression). Before touching floppy code, read BOTH specs in
   `.research/` — the read spec is authoritative on three verified points
   (DEVICE-type mount, bit-8 flow control not
   IO_WAIT, disk_present re-announce per poll); the write spec's §5a
   arm-state invariant closed three review-confirmed critical bugs
   (stale FDH across re-mounts, stale-READY re-arm, F1/F3 slot switch).
   Future increments: df1 (HyperRAM window `C_HMAP_ADF_DF1` reserved),
   mount-status OSM feedback (`<Saving>` needs an M2M options.asm
   generalization, noted in the write spec §7).
2. **DiagROM test round** — zero code: 256 KB DiagROM as /amiga/kick.rom
   exercises slow RAM, keyboard, audio, CIAs (diagrom.com).
3. **RamDump loader** — run deft's demo without floppy (possibly obsolete
   now that ADFs boot — confirm with deft whether .A5R is still wanted):
   the `.A5R` format (192-byte header with full CPU context
   D0-D7/A0-A6/USP/SSP/SR/PC, segment table, RTE-based launcher entry) plus the
   German delivery contract for deft. Loader = OSM manual-load → QNICE→main CDC FIFO
   → upload engine drives userio 0xF0 → launcher ROM replaces kick.
   Hardware state deliberately NOT restored (V1); brief color flicker OK.
4. Pending decision: publish to GitHub as sy2002/AExp (plan exists:
   fork Minimig upstream → sy2002/Minimig_MiSTerMEGA65, fix .gitmodules
   URL, add origin, push master+develop).

## Key documents (read before working)

User-facing docs (also the source for the a500.mega65.org website, built by
`doc/make_doc.py`; see `doc/make_doc.md`):

- `doc/keyboard.md` — full keyboard mapping guide, both modes, per-key tables.
- `doc/retrotubes.md` — connecting real 15 kHz CRTs (BNC / SCART / DB9 RGB) to
  the analog output, including the wiring-safety cautions.
- `doc/audio.md` — end-user guide to volume, stereo mix and the A500/LED
  filters (including the power-LED/filter story).
- `doc/screen_adjust.md` — HDMI crop + analog position/overscan, the
  `aexp_screen.cfg` format and the `aexp_screen_cfg.py` tool.
- `doc/RTC.md` — real-time clock setup and the Kickstart 1.3 quirks.
- `doc/developers.md` — build the core from source (clone → `*.cor`).

Internal engineering notes:

- `doc/developers/floppy-adf.md` — ADF floppy (read/write) design.
- `doc/developers/audio.md` — audio path.
- `doc/developers/hdmi_latency.md` — HDMI latency analysis.
- `doc/developers/research_df1.md` — second-drive (df1) research.
- `doc/inofficial.md` — alpha/beta build history (shipped only in WIP releases).
- `.research/` (local only, untracked) — integration specs and agent review
  reports from the porting sessions.

## People & communication

- The user IS sy2002 — author of the M2M framework and co-author of
  C64MEGA65. Expert level; framework questions can be asked directly.
- deft — MEGA65 project lead and Amiga demo author; provides test
  content (RamDump deliveries). Communication with deft is in German;
  documents intended for him: German, PDF via pandoc + xelatex
  (both installed; strip the English context header first).
