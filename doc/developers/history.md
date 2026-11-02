# Engineering history (moved verbatim from AGENTS.md, 2026-10-10)

The dated log of every AExp and Megamiga increment. `AGENTS.md` keeps only a
one-line index; the full record is here. Append new increments at the end of
the first section.

## Increment log

**Status: VERSION 1 IS RELEASED (tag `V1` = commit `46ef60c`, 2026-07-23;
`VERSIONS.md` dates the release 2026-07-26).** Read the
"Released and working" box below before assuming anything in this file is
still pending - much of the prose here was written while a feature was in
flight and was never re-worded after it shipped. Development continues on
Version 2 (audio improvements, Hardware Floppy, more drives).

### Released and working - do not re-litigate these

- **ADF floppy df0:, READ AND WRITE** - shipped in Version 1, in daily use.
- Video (HDMI + analog, interlace flicker fixer, screen adjustment),
  keyboard (both modes), mouse/joystick, battery RTC, Slow RAM toggle.
- See `VERSIONS.md` for the authoritative Version 1 feature list and
  `doc/inofficial.md` for the alpha/beta history.
- **The AExp release tag is `V1`** (commit `46ef60c`), and the alphas/betas
  are `WIP-V1-*` / `WIP-V2-*`. There is no `V1.0.0` tag in this project.
  Version numbers like "V2.0.1" in this file refer to the **MiSTer2MEGA65
  framework**, never to an AExp release - do not read a framework version
  as a core release. (This repo was forked from the M2M template, so M2M's
  own tags `V0.9.0`, `V0.9.1`, `V1.0.0`, `V2.0.0`, `V2.0.1`,
  `Vivado-2019.2` used to be present locally; they were removed on
  2026-08-02 and `remote.upstream.tagOpt=--no-tags` keeps them from coming
  back. GitHub `origin` never had them. If you ever see them again,
  someone fetched upstream tags - they are framework releases.)

**Work in progress (Version 2):**

- `WIP-V2-A1` — audio filters (A500 + LED), Stereo Mix, master volume.
- `WIP-V2-A2` — Hardware Floppy read: works "OK-ish", real disks mount and
  browse, but old/marginal media still produce errors.
- **`WIP-V2-A3` — MULTIPLE SIMULATED DRIVES. The HDL, the menu and the
  framework were R3-built (`5f2869d`: BRAM 364/365, WNS +0.120 ns) and
  HARDWARE-VERIFIED on 2026-08-03 (boot from df0, Workbench Tools in df1,
  a program reading both drives, the Hardware Floppy, and live drive-
  configuration switching all work). The per-drive firmware write-back
  followed on top and is statically verified but NOT yet synthesized or
  hardware-tested.** Three Amiga units `df0`/`df1`/`df2`, each either a
  read/write ADF disk image or the Hardware Floppy (at most one). The
  drive index IS the Amiga unit: per-drive twin lines in the main menu (a
  mount line and a hardware-status TEXT line) whose visibility comes from
  the backported M2M menu-dependency feature, a `Drive Settings` submenu
  with a `Drives 1/2/3` radio plus one mode radio per drive, three
  `adf_mount_wrapper` instances with their own guarded HyperRAM pools
  behind a 4-way `avm_arbit_general`, and a unit-tagged
  `adf_track_engine` whose write drain aborts the moment Paula selects a
  different unit. **All three drives are writable**: the eight write-back
  variables are arrays indexed by the drive, each drive owns its own
  FAT32 handle snapshot (`ADF_FDH0/1/2`), `FLUSH_ADF_STEP` takes a drive
  index, and `HANDLE_CORE_IO` runs per-drive SD guards, per-drive mount
  tracking and ONE round-robin flush slice per poll, so three armed
  drives cost the main loop what one used to. Three rules keep it safe
  and are load-bearing: a drive may only ever be flushed through ITS OWN
  handle; the same image file may not be mounted into two drives at once
  (`ADF_DUP_CHECK` rejects the second mount, because each drive holds its
  own HyperRAM copy and the later flush would overwrite the earlier one);
  and no handle may be left FAT32-DIRTY across a return to the main loop,
  because the machine has exactly ONE sector buffer whose owner the
  device handle tracks by ADDRESS, and the file browser steals it without
  flushing.
  **The authoritative working document is
  `.research/HANDOVER-multi-drive.md`** - read it before touching the
  floppy stack; it carries the design rationale, what is already in the
  tree, the defect classes to avoid (above all the untagged write drain,
  which would write one drive into another drive's image), the ordered
  remaining work and the verification recipes.
  Note that `CORE_VERSION` drives `CFG_FILE`, so the OSM settings file on
  the SD card becomes `/amiga/aexp-WIP-V2-A3.cfg` - regenerate it with
  `M2M/tools/make_config.sh` (see hard rule 10; `OPTM_SIZE` is now 146).
  The `doc/inofficial.md` row for A3 is added at packaging time, because
  `make_release.py check_inofficial_md` requires a real commit hash.
- **`WIP-V2-A4` — HARDWARE FLOPPY MARGIN INSTRUMENTATION (diag map v7).
  Field testing falsified the old-media verdicts (2026-08-07): a
  tester's original disk, verified on a real Amiga before AND after,
  read-errors in our core - the front-end decode margin is the suspect,
  and the A2-era dumps had no freshness marker (seven field "dumps"
  turned out to be two observations).** A4 adds, all in the 50 MHz
  domain with zero firmware/menu/BRAM impact: millisecond uptime + dump
  nonce (dumps can never silently duplicate again), step counter +
  /TRK0-referenced cylinder tracker, per-class SIGNED-error margin
  histograms of the adaptive quantiser (serve-gated; optional
  armed-sector window spanning exactly the approach to a chosen
  sector), minimum-margin capture with est/length/class context,
  estimate-excursion min/max, and a per-sector miss profile over
  qualified read revolutions ("always sector 4 or roving?" - the
  field signature is a deterministic sector-4 header miss on track 81
  with zero LOL/fmt_bad). Device decodes addr[6:0] now; dump =
  `M 7000 705F`; version reg 0x01 = 0x0007. Statically verified
  (nvc clean, all three existing TBs pass unchanged, new
  `tb_fdd_margin` checked against an independent integer model - which
  is how the "gaps stage counts intervals exclusive of the edge cycle"
  fact was found), NOT yet synthesized. The working doc is the Part-4
  section of `.research/HANDOVER-hardware-floppy-round2.md` (decoded
  field dumps, test.adf flux analysis, build + tester recipe incl. the
  German dump instructions, and the phase-3/4 separator plan). The SD
  settings file just needs a rename/copy to `/amiga/aexp-WIP-V2-A4.cfg`
  (`OPTM_SIZE` unchanged at 146). The A4 R6 build closed timing only in
  the post-route phys-opt pass (routed WNS -0.028 on the kick-ROM
  half-period path through the shared device-data cone, final +0.192).
- **`WIP-V2-A5` — REGISTERED DIAG READOUT (qnice_clk pressure relief,
  not shipped - a prerequisite for the next iteration).** The diag bank
  0x0104 latches the addressed word on the FALLING clock edge into one
  local 16-FF register; the CPU-facing `qnice_dev_data_o` cone sees a
  plain flip-flop instead of the 96-word mux cloud that helped an R6
  build graze the kick-ROM half-period path. ZERO wait states - the
  data source is register-fast, so this is the mount wrapper's
  WBC-CSR pattern ("plain FFs, no wait states"), NOT its
  HyperRAM-window wait pattern; bus timing is kick-ROM-identical
  (address stable at the falling edge, data consumed at the ending
  rising edge), so the firmware and monitor are untouched. Version reg
  0x01 reads **0x0008** (map CONTENT identical to v7 - the bump only
  identifies the build in field dumps); settings file
  `/amiga/aexp-WIP-V2-A5.cfg` (content identical, `OPTM_SIZE` 146).
  Verified: nvc clean, all four existing TBs unchanged-green, new
  `.research/tb_fdd_diag_ro.vhd` (pipelined 128-address sweep against
  an independent literal expectation table, latch-instant proof, alias
  folding). NOT synthesized.
  **A5 second increment - THE DPLL DATA SEPARATOR (map v9, reg 0x01 =
  0x0009).** Deft's A4 dumps (log03, 2026-08-08) measured the real
  failure: misses ROVE across all 11 sectors (~0.5/rev; "deterministic
  sector 4" was a frozen-snapshot artifact), the armed-sector windows
  are clean, and the killers are RARE extreme interval events (accepted
  gaps at -19%/+12%, margins to 0.19 cycles, ~40 rejects/session, est
  drag to 96.0 at exactly 300.0 RPM) that the interval classifier
  AMPLIFIES: one displaced edge hits two intervals, a class flip is a
  bit SLIP (rest of sector garbage), an out-of-span gap is a loud
  resync. The fix: a counter-based digital PLL bit source in
  `physical_fdd_bits.vhd` (per-edge phase pull err/2, period err/64
  clamped +/-10%, one bit per cell boundary, +/-1 us phase tolerance,
  errors stay local, droughts free-run) - the legacy quantiser path is
  BIT-IDENTICAL, runtime-selectable (diag 0x35 bit 6 = 1 -> legacy,
  default DPLL) and keeps running as passive observer, so the A4
  margin instrumentation measures identically in both modes (field
  A/B). New diag 0x5F = DPLL cell. Verified: tb_fdd_dpll RED/GREEN
  (the measured dropout event corrupts the tail via legacy resync,
  stays ONE bit flip under DPLL), S1..S5 pass in BOTH modes
  (G_LEGACY generic), margin/diag_ro/engine/multidrive TBs + full nvc
  chain + decoder v9 green. Plus two instrument fixes: /TRK0
  assert-edge cylinder zeroing (integral read one low in the field),
  min_est/min_gap cleared on reset/clear. NOT synthesized.
- **`WIP-V2-A6` - THE SYNC-SEAM FIX (map v10, reg 0x01 = 0x000A;
  R6-BUILT GOOD 2026-08-15: postroute-physopted WNS +0.172, 0 failing,
  BRAM 364/365 unchanged, both fx68k .mem read - delivered to deft for
  the field A/B). Settings file renames to `/amiga/aexp-WIP-V2-A6.cfg`
  (content identical, OPTM_SIZE 146). KNOWN LIMITATION in this build,
  fixed in WIP-V2-A7: while the framing hold is
  active (default) and a serve has crossed the splice, the CAPTURE-based
  diag instruments read misframed words - rev mask 0x1C/0x1D, fmt_bad
  0x1E, header captures 0x11..0x1A, the 0x58..0x5E miss profile and the
  armed-sector window are NOT trustworthy for post-splice sectors of
  hold-mode serves (they look bad on healthy disks); the BOOT outcome,
  the A/B switch, and the seam instruments 0x60..0x6C stay fully valid
  (the serve-start latch 0x6A fires pre-splice). WIP-V2-A7 fixes this
  limitation - it applies to 0x000A dumps only.** E2 of the
  2026-08-15 audit ran RED as pre-registered: `.research/tb_fdd_splice.vhd`
  (full AmigaDOS track through the REAL front-end at trackdisk's exact
  cadence into a LITERAL KS1.3 trackdisk decoder; independent Python
  twin `.research/td_check.py` agreed 7/7 on dumped captures) proved
  that the aligner's realign-at-every-4489 turns the once-per-rev
  write-splice slip into a seam ([gap run][hybrid][aligned 4489], e.g.
  run-end long $22444489) that matches NO trackdisk hunt-table entry:
  every spliced attempt dies `$1A` (written gap > ~560 B) or `$17` (second
  post-gap boundary inside the `$67C` window -> mis-anchor, `failslot ==
  SG`) in BOTH separator modes, except the SG=11 escape (serve start =
  first-written sector, 11-start sweep = exactly one escape), while a
  constant-framing capture of the SAME flux decodes GREEN (chunk-2
  shift absorbs the splice - real-Paula behavior, ROM-designed). THE
  FIX: `frame_hold` in physical_fdd_bits - word framing FREE-RUNS (no
  mid-stream realign) while the engine streams past its serve-start
  sync (new engine output `phys_data_o = phys_stream and not
  phys_hunt`, threaded main->mega65->top) AND live WORDSYNC=0 (Paula
  fdd_dws); pre-serve hunt and WORDSYNC=1 (X-Copy) keep realigning.
  Runtime A/B: 0x35 bit 7 = realign-ALWAYS (pre-fix framing; default 0
  = fix). E3 seam instruments at 0x60..0x6E (mid-serve realign counter
  + bit-phase context, pre-seam 8-word tap, per-session serve-start
  sector, LOL streaming/idle twins, chain-broken-window counter; the
  0x58 miss profile is now chain-gated - deselect-hole windows no
  longer count as misses). Dump = `M 7000 706F`. Verified: tb_fdd_splice
  matrix (unfixed RED / fixed GREEN x DPLL/legacy incl. seam-counter
  asserts), all six existing TBs green (tb_fdd_margin updated to the
  chain-gated window semantics, tb_fdd_diag_ro table extended to v10),
  decode_fdd_dump.py v10 + 52 selftests, full nvc chain. Zero firmware/
  menu/BRAM/.xpr impact; cfg unchanged. E1 (`.research/e1_census/`):
  KS1.3 census tool `tdcensus` + ADF + German recipe, built + vamos-
  smoke-tested, ready for deft.
- **`WIP-V2-A7` - THE HYGIENE BUILD toward the write milestone (reg
  0x01 = 0x000B, register CONTENT identical to v10; released to NO ONE -
  the A7->A8->V2 staging is in
  `.research/HANDOVER-hardware-floppy-write.md`). Statically verified +
  full TB gate green 2026-08-21, NOT yet synthesized.** Four queued
  items, nothing else: (1) the sync-anchored DIAGNOSTIC word stream -
  physical_fdd_bits carries a second framing counter over the same
  shifter that ALWAYS realigns on a sync match (`dword_valid_o/dword_o`);
  cap_proc consumes THIS stream, so the capture instruments (0x11..0x1A,
  0x1C..0x1E, 0x58..0x5E, armed-sector window) are trustworthy during
  framing-hold serves too - the A6 caveat is closed, and with the hold
  off the two streams are bit-identical by construction (both counters
  reset on the same events), so the realign-always A/B arm and the
  SERVED stream into Paula are untouched in every mode. (2) WORDSYNC=1
  coverage in tb_fdd_splice: one spliced serve under live WORDSYNC=1
  asserts the hold stays OFF (frame status) and X-Copy-style-decodes the
  capture (aligned [4489][4489] pair + word-aligned checksum decode for
  every boundary incl. >= 3 post-splice sectors) - a hold-ignores-
  WORDSYNC mutant top now goes RED (proven), where the old matrix was
  blind. (3) `phys_data_o` in adf_track_engine is registered (the level
  crosses to the 50 MHz domain through an async 2-FF; phys_stream and
  phys_hunt toggle together at dispatch - decode-glitch hygiene).
  (4) tdcensus `send_pkt1` repaired (sets mn_ReplyPort, loops
  GetMsg/WaitPort until ITS OWN packet returns before freeing - the
  stale-port-signal in-flight-free hazard; also: `inhibited` only set
  when ACTION_INHIBIT actually succeeded; rebuilt, vamos smoke PASS).
  Plus, from the increment's adversarial review (12 findings, all
  minor, all folded): cap_proc ABANDONS a torn capture on chain reset
  (a deselect mid-capture could otherwise complete the stale buffer
  with the next selection's free-running hunt words = a mixed-session
  garbage publish - pre-existing, now impossible), the splice TB's
  instrument asserts got a still-selected 300 us tail-settle window +
  a whole-run fmt_bad=0 backstop, and tb_engine_paula now checks the
  registered phys_data_o against the REAL engine (low through the
  hunt, high per stored word, low after DMA end).
  Red/green, all proven: the extended TB against the A6 HDL fails
  exactly at the new fmt_bad assertion (5 misframed post-splice headers
  = the caveat reproduced); a hold-ignores-WORDSYNC mutant top dies at
  the frame-status assert; two engine mutants (dropped hunt term /
  stuck-0 phys_data_r) die at the new tb_engine_paula asserts; against
  the real A7 HDL the full matrix passes (4 cells x DPLL/legacy x
  fixed/unfixed + G_SWEEP, WORDSYNC=1 coverage 14 pairs/13 clean/4
  post-splice in all of them). Gate: all eight TBs green, full nvc
  chain, decode_fdd_dump.py 0x000B + selftests (the A6 hold-mode dump
  caveat now scoped to 0x000A), check_osm_menu + check_firmware clean.
  Settings file renames to `/amiga/aexp-WIP-V2-A7.cfg` (content
  identical, OPTM_SIZE 146). Zero firmware/menu/BRAM/.xpr impact. The
  write-datapath spec is at
  `.research/INTEGRATION-SPEC-hardware-floppy-write.md` (now at revision
  3.6; the increment is **WIP-V2-A9, diag map 0x000D**, implemented and
  field-proven - see its entry below; write research ground truth in
  `.research/RESEARCH-write-mega65-core.md` +
  `RESEARCH-write-paula-engine.md`; working doc
  `.research/HANDOVER-hardware-floppy-write.md`). A8 went to the Copylock
  read fix, which is why the write milestone is A9.
- **`WIP-V2-A8` - THE COPYLOCK READ FIX (reg 0x01 = 0x000C; register
  CONTENT identical to v10; BUILT AND FIELD-CONFIRMED 2026-08-28, zero
  regressions - sy2002 calls it "very stable", and A9 is built on it).**
  Field round (dejavu4u2, from `40263eb` + submodule `cf934cb`): all
  three target titles - Cannon Fodder disk 2, The Chaos Engine,
  Terminator 2 - load and play normally, and the CAUSAL A/B held exactly
  as pre-registered: `M C 7035 8100` (surface off = the A7 stub) brings
  the hang back on all three, `M C 7035 8000` restores them, on the same
  disks in the same session. That pins the failure to this one register
  rather than to anything else the build changed. The regression sweep
  covered the only two theoretical exposures the review named, X-Copy and
  trackdisk/old originals, and both are clean: X-Copy full-disk copies of
  Alfred Chicken and Workbench 1.3 still 100%, and Giana Sisters, Alfred
  Chicken, R-Type II, X-Copy Pro, Workbench 1.3, Arkanoid, Arkanoid
  Revenge of Doh, Superfrog, Addams Family, New Zealand Story, Ruff'N
  Tumble, Apidya and Benefactor all boot flawlessly. New Zealand Story is
  itself a Copylock title - the very loader keirf disassembled - so it
  doubles as a second positive control. The one open thread is Tier 2
  (the seven dirk9880 titles), still UNCLASSIFIED for want of data: if
  they are Copylock they are covered now, and if any fails on A8 it is a
  different class and the classification-before-theory rule applies
  again. Details + the shelf list behind `0x35` bit 8:
  `.research/HANDOVER-protected-disks.md` (FIELD RESULT).
  THE ORIGINAL DEFECT: Rob Northen COPYLOCK protected
  originals (Cannon Fodder disk 2, Terminator 2, The Chaos Engine) hung
  reading their protection track (Amiga track 1 = cyl 0 head 1) on the
  Hardware Floppy while booting fine on the tester's real A500+.
  ROOT CAUSE (established from keirf's Copylock disassemblies + flux +
  the A7 dumps, three independent lines converging): Copylock times the
  disk by CPU-polling Paula's **DSKBYTR** (`$DFF01A`) - poll bit 12
  WORDEQUAL for the sync, then count poll iterations while bit 15
  BYTEREADY toggles as raw MFM bytes arrive - comparing a 5%-short
  sector (sync 0x8912) against a 5%-long one (0x8914); it needs
  `(t_long-t_short)/t_short >= 2..4%`. Minimig's DSKBYTR was a CONSTANT
  STUB (`paula_floppy.v`: BYTEREADY=1, WORDEQUAL=1, data 0x00), so the
  ratio was always 0, the check failed and the loader spun then parked
  the machine (black screen, motor on, no stepping - the video-forensics
  verdict). The read chain itself was PROVEN innocent: the SCP flux of
  all three disks decodes bit-identically under legacy/DPLL/fixed
  separators on the loader-relevant sectors, the A7 captures equal the
  real flux, and the est excursion (93.1..106.3 cyc) stays inside the
  +/-10% clamp - which is why EVERY 0x35 A/B arm failed identically
  (none touch DSKBYTR). **THE FIX - a gated DSKBYTR observation surface
  in `paula_floppy.v`** (a 9th... no, still a minimig change under the
  existing "physical-drive support" seam): main.vhd taps the engine's
  physical-FIFO pop (`s_hwf_rd_en` + `hwf_rd_data_i`, QUALIFIED with
  `hwf_rd_empty_i = '0'` so it mirrors the FIFO's real pops - the review's
  OBS-SRC-1 fix: without the guard the engine's ST_IDLE last-word re-pop
  publishes a phantom stale word over each real one) into a 1-clk pulse
  `obs_word/obs_stb` (clk_main; the reconstructed real-disk word stream
  at true flux pace), threaded main -> minimig_m65 -> minimig -> paula ->
  paula_floppy as `fdd_obs_word/stb/legacy`. paula_floppy synthesises a
  faithful DSKBYTR from it (2 raw MFM bytes per word hi-then-lo,
  BYTEREADY set-per-byte + clear-on-read, WORDEQUAL live) ONLY while
  `obs_gate = |(phys_mask & ~_sel & motor_on) & ~obs_legacy` - i.e. the
  physical unit is the selected, motor-on drive and the A/B bit is clear;
  otherwise the expression is the ORIGINAL constant stub, byte-for-byte.
  The DMA FSM, the DSKSYN interrupt, the FIFO, the ENGINE and the FRONT
  END are UNTOUCHED (the observation stream is independent of the DMA -
  DSKBYTR delivers bytes whenever selected+motor-on, no DMA needed - so
  the zero-length arm and syncint did not need changing). Runtime A/B:
  **0x35 bit 8 = 1 disables the surface** (`M C 7035 8100` reverts to the
  A7 stub and reproduces the hang; `M C 7035 8000` or reset = fix on).
  qnice_fdd_ctrl widened 8->9 bits, crossed qnice->main via a new
  cdc_stable. **Verified: a GOLDEN-DIFF iverilog TB (the new paula_floppy
  vs the frozen pristine A7 module, identical stimulus) proves
  BYTE-IDENTICAL outputs in every gate-off regime = the no-regression
  proof; a Copylock CPU-model TB shows fix-ON 5% timing ratio /
  fix-OFF 0% (hang); nvc clean on main/mega65/diag; tb_engine_paula +
  tb_fdd_diag_ro (bumped to 0x000C) + check_osm_menu + check_firmware +
  decode selftest all pass.** Zero firmware/menu/OPTM/BRAM impact;
  settings file `/amiga/aexp-WIP-V2-A8.cfg` (content identical,
  OPTM_SIZE 146). Working doc: `.research/INTEGRATION-SPEC-copylock-
  dskbytr.md`; campaign: `.research/HANDOVER-protected-disks.md`; the
  local regression TB is `.research/tb_paula_obs.v` (+
  `tb_paula_floppy_a7ref.v` + `build_tb_paula_obs.sh`). Field A/B recipe
  for dejavu4u2 in the handover.
- **`WIP-V2-A9` - THE HARDWARE FLOPPY WRITE DATAPATH (reg 0x01 = 0x000D;
  the first time any M2M core writes a real floppy). BUILT, FIELD-PROVEN AND
  RELEASED AS A PUBLIC ALPHA (tag `WIP-V2-A9` = `b5da87a`): real Amigas read
  the disks this core writes, and sy2002 called it good to go on
  2026-09-20 - see FIELD RESULT at the end of this block.** A dumb, format-agnostic bit pipe from Paula's write DMA to the
  WDATA pin - we never parse what we write, so AmigaDOS tracks, X-Copy
  images and trackloader formats pass through identically. The contract is
  `.research/INTEGRATION-SPEC-hardware-floppy-write.md` **revision 3.6**
  (five adversarial audit rounds: 36 -> 45 -> 22 -> 10 -> 11 findings, all
  folded; round 5 was the implementation session's own fold-check).
  THE STRUCTURE: Paula's 2048-word FIFO + the dmal backpressure loop IS the
  elastic buffer (supply 21.3 us/word beats demand 32 us/word, so a paced
  drain can never starve mid-track), the engine pops ONE word per frame and
  only when the writer is nearly dry, and a deliberately SHALLOW 4-deep CDC
  FIFO feeds `physical_fdd_writer.vhd` (50 MHz: 100-cycle cells, MSB-first,
  FWFT reload, 500 ns active-low WDATA pulses, ROM-faithful precomp, WGATE
  hard-gated). Shallowness is the whole safety mechanism: Paula fires DSKBLK
  when the HOST empties its FIFO, so every word still in our pipe then is
  flux the Amiga already believes written - the in-flight residue is 2 to 3
  word times (~72-104 us). That is about THREE TIMES a real Paula's, which
  owes exactly one word because it fires DSKBLK when its own FIFO empties
  into its own shifter. Shallow is necessary and NOT sufficient: a host that
  touches a pin inside that window still cuts the tail, which is what the
  drain hold in FIELD RESULT below exists for.
  THE EPISODE MODEL (the structural critical of audit round 2): Paula's
  write DMA survives every engine-side drain abort - trackwr stays high
  until the host drains the FIFO - so the unit of write-session state is the
  trackwr EPISODE, not the engine drain. Ownership binds ONCE at the first
  drain (`epi_bound`/`epi_phys`); every later drain INHERITS it
  (drain_unit = the physical unit, drain_commit = '0', wr_track_lat kept),
  which is what stops a foreign-sel sample from re-latching the physical
  DMA's remainder as an ADF-owned COMMITTING drain that would decode and
  write the flux into a mounted .adf image. The abort is a LEVEL held for
  the episode; an aborted episode is DEAD (the writer discards, Paula's DMA
  still completes, DSKBLK fires) - exactly what a real Amiga leaves after a
  mid-write fault, and trackdisk has no write verify, so the loss is silent
  until the next read. While an episode is open the engine NEVER enters
  ST_IDLE, so the 0x1nnn announce and the physical read-FIFO discard-pop are
  both suspended - load-bearing beyond pacing, because each such pop would
  fire the A8 obs tap into Paula's DSKBYTR surface in the middle of a write.
  SAFETY: WGATE opens only while enable AND selected AND motor AND
  STREAMing AND `wr_ok`, the tab qualifier - wprot_n read writable for 10 ms
  of CUMULATIVE SELECTED time (the PC mechanism drives its outputs only
  while selected), 50 us select-settle blanking, an 80 ns-filtered revoke,
  and the disk-change latch as a filtered EVENT rather than a level (a level
  would block X-Copy single-drive writes, which swap disks and rewrite the
  same track WITHOUT stepping). Any gate term lost mid-stream, the engine's
  abort level, or an underrun cuts WGATE in the SAME cycle and LATCHES the
  abort for the rest of the episode - a returning term, a re-opened drain or
  a re-select cannot re-open the gate. The read decode chain is held in
  reset for the WHOLE episode (`chain_rst` gains `or wr_epi`, NOT merely
  `or wgate`: a tab-blocked or aborted episode keeps the gate shut while the
  disk still spins, and a decoding chain would refill the read FIFO behind
  the write and feed the Copylock surface).
  PRECOMP is ROM-faithful: a 7-channel-bit window whose middle bit is the
  one written, gap-before shorter than gap-after -> EARLY and the mirror ->
  LATE (the mega65-core `f_write_buf` table), ONE magnitude of 140 ns =
  Paula's PRECOMP0, boundary bits explicitly unshifted. KS1.3 trackdisk
  programs exactly this for every track >= 81 (FEA2DA..FEA306, the ROM's
  track-80 exclusion honored); the decision is made ENGINE-side at the
  episode bind so no multi-bit track value crosses a clock domain, and
  arrives at the writer as one level. Diag 0x7C selects OFF/ON/AUTO.
  Files: NEW `CORE/vhdl/physical_fdd/physical_fdd_writer.vhd`; the engine
  gains the episode/tap/pacing/abort/interlock/announce; `physical_fdd_top`
  instantiates the writer + a second `physical_fdd_wfifo` (G_AW=2) whose
  write side is the CORE clock; the FIFO gains an ADDITIVE `rd_level_o`
  (the read instance leaves it open and stays bit-identical); diag map
  0x000D adds 0x70..0x7D; mega65/main thread it and add the 0x7C register
  plus two cdc_stable crossings; **the four board tops now ROUTE
  f_wdata/f_wgate instead of tying them '1' - an extension of M2M exception
  7 (`floppy-pins`) that sy2002 owns and signs off**; CORE_VERSION becomes
  WIP-V2-A9 (settings file `/amiga/aexp-WIP-V2-A9.cfg`, content identical,
  OPTM_SIZE 146); all four .xpr list the new file. Zero firmware, zero menu,
  zero BRAM impact (4x16 LUTRAM + registers).
  VERIFIED IN SIM: the new `.research/tb_fdd_write.vhd`
  closes the loop Paula-write-model -> REAL engine -> REAL write FIFO ->
  REAL writer -> a LIVE ROTATING FLUX MODEL in 50 MHz cycle timestamps ->
  REAL read chain -> REAL engine read service -> verdicts. The model is
  pre-seeded with a DIFFERENT track and every writing scenario asserts
  POSITIVELY that the gate opened and the old flux is gone, so a no-op
  writer cannot pass by re-reading the seed. S1 (trackdisk cadence, full
  6815-word track): WGATE window = 10,904,000 cycles = 6815 x 16 x 100
  EXACTLY pin-to-pin; the ROM-exact KS1.3 trackdisk checker decodes our
  own re-read (err=$00, SG=11); the constant-framing real-Paula referee
  decodes; all 11 sectors byte-compare; 0x7D overflow 0, underrun 0,
  in-flight <= 3; and the INDEPENDENT Python twin `td_write_check.py`
  agrees EDGE FOR EDGE (38536 = 38536, +/-1 cycle, incl. the 109 %-of-a-
  revolution self-overlap). S3 (tab open / pre-qualifier / qualified),
  S4 (short+long engine abort), S5 (all seven gate terms), S9 (both click
  classes + persisting foreign sel), S10 (df0 sel ambiguity), S11 (all
  three reset classes + the sub-threshold DMA) pass in BOTH separator arms.
  The whole pre-existing TB matrix stays green against the modified HDL.
  A 12-mutant matrix (`.research/run_write_mutants.sh`) enforces the spec
  rule that every mutant must turn a verdict RED.
  **S7 and S8 are the two proofs to trust most.** S7 (T8 in
  tb_adf_multidrive): a physical write carrying valid AmigaDOS sectors, a
  mounted and write-ARMED ADF drive at the same track, and a PERSISTING
  foreign selection injected mid-stream - RED against git HEAD ("Avalon
  write to the wrong image offset": the pre-A9 engine really does commit
  real-floppy data into a user's .adf) and GREEN against A9. That is the
  episode model's whole reason to exist, demonstrated rather than argued.
  S8 (`run_s8_golden.sh`): the engine's io-channel word stream over an
  ADF-only workload is **19,481 words BYTE-IDENTICAL** between the pre-A9
  and A9 engines - the bit-identity proof for every shipped ADF and read
  behaviour.
  **THE INCREMENT WAS ADVERSARIALLY REVIEWED (6 lenses + refuting
  skeptics, 30 findings, all folded)** because the implementation session
  was fragmented by repeated safeguard false positives and model switches.
  It found two REAL HDL bugs that would have reached a disk: an episode
  ending in ST_ARM left 1-2 words in the CDC FIFO to be written ahead of
  the NEXT episode's first word, and the underrun abort was gated on the
  whole precomp window emptying, so a 1-6 cell dry spell deasserted and
  then RE-ASSERTED WGATE mid-track - an erased hole with no abort, no
  reason code and no 0x75 tick, which is the path every real underrun
  would have taken. It also found that the WGATE expression relied on a
  monitor that is blind during the 50 us select-settle (so a stale wr_ok
  from a PREVIOUS disk could open the gate on a just-swapped protected
  one), that the read chain was released at DSKBLK while the writer still
  had ~104 us of tail to write, and eight defects in the TESTBENCH itself
  including one assert that could not fail. The mutant matrix then caught
  five more checker gaps on its first run - each fixed rather than
  excused, per the spec's rule.
  **THE FULL-TRACK BLOCK THEN RAN FOR THE FIRST TIME (2026-08-28) AND PAID
  FOR ITSELF.** The RPM x separator x framing sweep, S1p, S2, S6 and S12
  are now all executed. They exposed no HDL defect but seven CHECKER
  defects, every one of the same shape - a test that reported success
  without exercising what it claimed: a mutant kill criterion that scored
  TIMEOUTS as kills; nvc's "analysed unit older than its source" warning
  ignored, so an edit mid-run left 26 of 27 cells testing stale code; a
  mutant paired with the wrong cell, which was concealing that NEITHER
  interlock gate had a working detector (hence the new mutant xiii, read
  side, and x re-paired to S12/1); S12 grading a 600-word fragment with a
  ROM-exact decoder, which no design could pass; the S2 X-Copy capture
  modelled at the full DMA length instead of the spec's 6496 words, which
  made the residue branch dead code and the tail cut destroy real sector
  data; the twin's precomp tolerance applied per EDGE to a per-INTERVAL
  quantity, guaranteeing a false RED on every precomp-active dump; and all
  five S1p dumps colliding on one filename with the precomp-OFF one
  surviving, so spec 3.4 had never actually been machine-checked. It has
  now: the twin agrees EDGE-FOR-EDGE on a precomp-active cyl-90 track
  (38546/38546, 10061 early + 10017 late), red-controlled against the old
  tolerance. All runners now fail loudly on stale analysis, and a mutant
  kill is credited only if the cell is GREEN on the unmutated design.
  **THE 88-AGENT REGRESSION AUDIT THEN FOUND A REAL ONE (see spec 9a):**
  the episode bound `epi_phys` from ONE sample of Paula's priority-encoded
  sel field, whose "nothing selected" default is `2'd0` = "df0 selected",
  so with the mechanism at df0 an ordinary deselect gap bound an ordinary
  .adf write as physical - irreversibly, since that suspends the ownership
  guard and pins `drain_commit` at '0' - and the whole track write was
  discarded in silence (0 Avalon writes vs 256 pre-A9) while DSKBLK fired
  and trackdisk, which has no write verify, believed it. FIXED by
  qualifying the bind with the REAL per-drive select line
  (`main_hwf_selected`, already in the engine's clock domain, no new CDC) -
  a deliberate deviation from the original spec 2.1, **signed off by sy2002
  on 2026-08-28 and folded into the contract as revision 3.6**, where the
  qualifier is now the rule and 9a records why.
  Control: `tb_adf_multidrive` T9, RED unfixed / GREEN fixed; T8 now drives
  the select line, and without it caught a physical write committing into
  an ADF image. The A8 read-path guards (`tb_hwf_obs_tap` and the
  `paula_obs` golden diff) were MISSING from the regression suite and are
  now permanent cells; a forked `tb_engine_paula` additionally proved the
  physical read-FIFO pop stream - which IS the A8 DSKBYTR observation
  stream - cycle-timestamp identical to git HEAD over 17061 pops.
  **THE SIM GATE IS COMPLETE AND GREEN (2026-08-28, device fingerprint
  46ee06de):** write matrix FULL 0 failures, all 5 twin cross-checks OK,
  mutants i..xiii all KILLED on real assertions under a baseline-green
  guard, regression 15/15 (now including the two A8 read-path guards that
  were MISSING - `tb_hwf_obs_tap` and the `paula_obs` golden diff - plus a
  new `run_pop_identity.sh` that runs the PRE-A9 engine on a physical read
  workload and proves the read-FIFO pop stream, which IS the A8 DSKBYTR
  observation stream, cycle-exact at 17061 pops), S7 red control RED
  against git HEAD / GREEN against A9, and S8 in BOTH arms: byte-identical
  with no physical unit, and with one CONFIGURED exactly 1525 announce
  words differing in that unit's writable nibble and nothing else - the
  second half of spec 6.2 S8, pre-registered and never run until now.
  Late coverage added after the regression audit named the gaps: T10
  (combo B, the mechanism at df0, where "nothing selected" and "df0" are
  the same encoding), T11 (an ADF write against a BUSY writer with a full
  CDC FIFO - every earlier ADF result had the writer stubbed at 0/0/0),
  and T12 (a reset inside an open episode, which also settles the audit's
  one latent finding by measurement: `epi_bound` does NOT survive a
  reset). Results are recorded with per-scope fingerprints in the
  session ledger, so no result can be quoted against a tree it did not
  describe.
  FIELD RESULT. Three bench fixes landed on top of the datapath `cb1823d`.
  `c3a20dc`: the ADF encoder emits real MFM clock cells - it was a bit-exact
  port of minimig_fdd.cpp, which omits them, harmless while the words only
  reached Paula and fatal once X-Copy could raw-copy them onto media.
  `c9e8538`: the write pulse launches at the cell midpoint. `3edf736`: **HOLD
  SELECT AND SIDE THROUGH THE POST-DSKBLK DRAIN.** X-Copy's DOS engine writes
  `[500 x $AAAA][11 x 544-word sectors][1 x $AAAA]`, DSKLEN 6485, so its
  whole post-DSKBLK margin is ONE pad word, sized for a real Paula; it then
  toggles /SIDE1 about 30 us after DSKBLK, the writer treated that as a gate
  term, and the last word of sector 10 was lost on every upper-side track
  (85 bytes of 901,120, all sector 10, all head 1, all offset 510/511). The
  fix is a PAIR that must never ship apart: `mega65.vhd` holds `f_selecta_o`
  and `f_side1_o` at their episode values while the writer is busy AND the
  session has already fallen (the drain only - keying on busy alone would
  freeze the pins for a whole track and across a reset), and only if the
  held select is the ASSERTED one; `physical_fdd_writer.vhd` stops aborting
  on SELECT/SIDE once the session has fallen. STEP and DIR are deliberately
  NOT held - STEP is a pulse, freezing it would destroy it and leave the head
  behind the host's cylinder counter, and the STEP abort term stays live.
  This extends M2M exception 7 and the writer's abort contract; sy2002
  approved both. Builds: R3 WNS +0.198, R6 +0.088 postroute-physopted (judge
  R6 from THAT report, never `_routed`), BRAM 364/365, LUTRAM 8550, both
  unchanged. Gate: write matrix 77/77, mutants 15/15 killed.
  On real media: Workbench `format`, copy, REBOOT, run; X-Copy whole disk,
  160 tracks, VERIFY ON, read-back byte-identical to a proven reference.
  **The referee (dejavu4u2, 2026-09-02..20): an A500 (OCS, KS1.3) and an
  A500+ (ECS, KS2.0) read all four core-written disks**, a repaired A1200
  (KS3.2) reads the core-cloned Extras disk, a bootable Workbench clone was
  written end to end by the core, Giana Sisters' high score survived a power
  cycle (a custom trackloader format writing and re-reading its own data),
  and the read regression against A8 is clean over 18 titles including the
  Copylock originals.
  **Flux analysis of his Greaseweazle dumps (2026-09-20), no core defect:**
  the 140 ns precompensation REACHES THE MEDIUM - neighbour-conditioned
  interval means step exactly at the track 80/81 boundary on both heads, by
  +220/+248 ns on the core-formatted disk against +217/+248 ns on a disk a
  real A500 formatted; every X-Copy write ends 15 cells after sector 10's
  last data bit, i.e. at the end of the pad word, on BOTH heads; structure
  matches the A500's apart from spindle speed. The tester's "intermittent
  RAM-route boot failure" was three unrelated things: a voided test (X-Copy
  RAM mode holds 73 cylinders in 1 MB and the second pass was missed), a disk
  that was NEVER WRITTEN (statistically identical to its own never-written
  tracks 160-163; X-Copy's pass was aimed elsewhere or - unproven, and the
  writer has no state that blocks a whole pass - the core discarded 160
  episodes), and a disk with PHYSICAL MEDIA DEFECTS (13 of 16 analog patches
  at one rotational angle across five cylinders and both heads, which logic
  that does not know where the index is cannot produce). He can no longer
  reproduce either. His own theory, not waiting for the yellow ADF-flush LED,
  explains neither disk: a simulated drive is served from HyperRAM, the flush
  only copies it to the SD file.
  **If a write problem is ever reported again, do not theorise - run the
  protocol** at the top of `.research/HANDOVER-hardware-floppy-write.md`
  (START HERE): untouched disk as source `.adf` + X-Copy read-back + raw
  `.scp`, then `adf_compare.py` and the flux instruments in
  `.research/scp_flux/`; for a disk that comes back virgin, `M 7000 707D`
  before any reset (`0x70` episodes bound, `0x7A` episodes that opened
  WGATE, `0x76` tab-blocked). Advise users to copy with VERIFY ON.
  `doc/hardware_floppy.md` describes the write feature. Note that the four
  board tops no longer tie `f_wdata`/`f_wgate` inactive, so the Hardware
  Floppy is not PHYSICALLY read-only: the guards are the writer's conjunction
  and the disk's own tab, with no runtime disable.
- **`WIP-V2-A10` - ONE DRIVE BY DEFAULT (issue #29). Statically verified
  2026-09-20, NOT yet synthesized.** The shipped configuration is now a
  single Amiga unit, `df0:` as a Disk Image drive; `df1:`/`df2:` default to
  `Off` and NO drive is the Hardware Floppy. Reason (issue #27 comment):
  several games and demos misbehave when the Amiga sees more than one drive
  - Riverraid Reloaded is the reported case. Everything beyond one drive is
  opt-in through `Drive Settings`; nothing is removed, and for THIS part of
  A10 no menu line moves and the firmware ROM is untouched - the DVI item
  described at the end of this entry is what grows `OPTM_SIZE` to 148.
  MECHANICALLY this is three `OPTM_G_STDSEL` flags moving in
  `config.vhd` OPTM_GROUPS (Drives 15 -> 13, df1 24 -> 26, df2 31 -> 32)
  plus the decoders that MIRROR them. The load-bearing rule is that a
  STDSEL line must be VISIBLE under the other groups' defaults - df1/df2
  `Off` carry `OPTM_DEP(OPTM_G_DRIVES,0)` / `OPTM_DEP2(...,0,1)` and are
  exactly the variants the one-drive count swaps in, so the new triple is
  self-consistent, which matters because NOTHING reconciles the drive
  radios at boot (`DRV_ENFORCE_COUNT` runs only after the user changes
  something). Three HDL sites had to follow, all of which encoded the old
  default as a FALL-THROUGH: `drv_decode` in `mega65.vhd` (count chain now
  tests `C_MENU_DRIVES_3` and falls through to 1; the df1/df2 chains now
  test IMG/HW positively and fall through to `C_DRV_OFF` - the df2
  fall-through used to be `C_DRV_HW`, the one value that can assert
  `main_hwf_en`), its QNICE-domain twin `qnice_hwf_map3_decode` (same count
  chain; its df2 test became the positive `C_MENU_DF2_HW = '1'` instead of
  "neither IMG nor OFF", which would have marked df2 physical for an
  all-zeros vector and made field dumps claim a mechanism that is not
  there), and `amiga_cold_boot.vhd`, whose `drv_map_applied` power-on value
  IS the encoded default and became `"00" & "10" & "10" & "00"` - left at
  the old value it fires a spurious cold boot at t=0.
  Verified: `check_osm_menu.py` GAINED the boot-state checks the change
  turned out to need - exactly one OPTM_G_STDSEL per radio, every STDSEL
  line VISIBLE under the other groups' defaults, and at most one drive
  defaulting to `Hardware Floppy` (DRV_STEAL_HW does not run at boot
  either). NOTE what the control actually is: the OLD complete triple is
  self-consistent and passes, so it is NOT the red control; the check fires
  on a PARTIALLY migrated triple, which is the regression this edit could
  have shipped (mutant: Drives STDSEL at line 13 with df2 left at line 31
  -> `line 31 carries OPTM_G_STDSEL for group 21 but is HIDDEN at boot`).
  Three mutants kill on real assertions (missing OPTM_G_START, two drives
  defaulting to Hardware Floppy, partial migration). Also fixed in the
  checker while there: an UnboundLocalError that aborted every later check
  when the OPTM_G_START count was wrong, a one-member radio taking the
  single-select ordinal branch (wrong ordinal, then IndexError), and a
  height sweep that gave a single-select mother only ONE state and could
  therefore under-report the tallest view.
  `check_firmware.py` + the full nvc chain clean.
  `.research/tb_cold_boot_init.vhd` proves no power-on cold boot with the
  new map (G_MAP default), one with the old (`-gG_MAP="10010000"
  -gG_EXPECT_BOOT=true`), and that the assertion can fail
  (`-gG_EXPECT_BOOT=true` alone). Settings file
  becomes `/amiga/aexp-WIP-V2-A10.cfg`, **148 x 0xFF** because of the DVI
  item below - generate a FRESH one, never copy the A9 file forward: a used
  A9 file holds the old three-drive selections and, since the firmware
  accepts a settings file on LENGTH alone, would silently restore them. Here
  the length change happens to make that impossible, but do not rely on it.
  The one-drive change itself has zero firmware/menu-size/BRAM/.xpr impact;
  the diag map stays 0x000D (no floppy behaviour changed).
  A10 ALSO CARRIES THE HARDWARE-FLOPPY DOCUMENTATION PASS (issue #27): the
  user-facing docs still said the Hardware Floppy was read-only and that old
  media produce read errors - both falsified long ago and fixed in the core
  (A6 sync seam, A8 Copylock/DSKBYTR, A9 write). README, `doc/drives.md`,
  `doc/hardware_floppy.md`, VERSIONS.md, `doc/developers/floppy-adf.md` and
  `doc/developers.md` now say read AND write, carry the A9 field evidence
  (A500 OCS + A500+ ECS + A1200 read core-written disks, bootable Workbench
  clone, X-Copy 160 tracks VERIFY ON byte-identical, Giana Sisters high
  score across a power cycle), gain a new "Copy-protected originals" section
  (Rob Northen Copylock; Cannon Fodder, The Chaos Engine, Terminator 2, The
  New Zealand Story = the A8 field-confirmed list) and replace the retracted
  "blame the media" section. The docs deliberately state that a copier
  cannot REPRODUCE Copylock (true on a real Amiga too), so "we read
  protected originals" can never be read as "we clone them". The
  write-protect tab stays documented as the only write guard. HELP_1 states
  the one-drive default and no longer claims read-only; no other in-core
  help page makes a Hardware Floppy claim.
  HELP-PAGE GEOMETRY, found by the A10 review and FIXED here: the welcome
  and help screens print into a FULL-SCREEN frame (shell.asm FRAME_FULLSCR
  over the whole canvas; SCR$PRINTFRAME leaves the cursor at (x+1,y+1) and
  whs.asm prints from there with no GOTOXY), so rendered row i lands on
  SCREEN row i+1 and the usable area is rows 1..34 x columns 1..43 of the
  45x36 canvas. ONE row too many overwrites the bottom border; TWO and the
  last line is written past CHAR_MEM_SIZE (45*36 = 1620) and never appears.
  HELP_3 had been at 36 rows since before A9 - its `Space or Run/Stop:
  Close` footer was invisible on hardware and nobody noticed - and the A10
  edit pushed HELP_1 to 35. Both fixed by rewording (HELP_3 -> 34, HELP_1
  -> 33, the budget every other page keeps), and `check_osm_menu.py` now
  CHECKS all eight pages against the geometry it derives from globals.vhd.
  Note the trap in that checker, which cost one silent false pass before it
  was caught: the page text must be scanned to the terminating semicolon
  with a string-aware scanner, NOT split on the first `;`, because HELP_3
  prose contained one (`Writes are saved in the background;`) - splitting
  truncated the measurement and the too-long page passed. Mutants: an
  over-long page, an over-wide line, and a semicolon-bearing over-long page
  all go red on a green baseline.
  A10 ALSO CARRIES THE DVI ITEM, ported from C64MEGA65. `DVI (no sound)` is
  a single-select toggle, **default OFF**, inside the HDMI Settings submenu:
  it lands at line 45 (after the separator that follows `576p 50 Hz 5:4`),
  followed by a new separator at 46, so `Back to main menu` moves 45 -> 47
  and EVERY line from the old 45 onwards shifts by +2. It drives the
  framework's `qnice_dvi` input - `qnice_dvi_o <= qnice_osm_control_i(
  C_MENU_HDMI_DVI)` replaces the `'0'` tie-off - and `vga_to_hdmi.vhd` then
  forces `ENC_DVI` on every non-video period, so the audio packets and ALL
  HDMI data islands vanish while the pixels, the timing and the resolution
  stay identical. That is the cure for displays which reject an HDMI stream
  and show nothing, and the cost is that sound is only on the 3.5 mm jack.
  The signal is consumed in the qnice domain and `vga_to_hdmi.vhd` does its
  own CDC, so the core needs none.
  THE BLAST RADIUS IS THE RENUMBERING, and it is mechanical but wide: 20
  `C_MENU_*` constants and the three subtypes (`C_MENU_OSM_SCALING`,
  `_VOLUME`, `_STEREO`) in `mega65.vhd`, every `-- NN:` comment in BOTH
  `OPTM_ITEMS` and `OPTM_GROUPS`, the "OSM bit positions" comment block and
  the `OPTM_DY` view-height list (HDMI Settings submenu 7 -> 9 lines;
  `OPTM_DY` itself STAYS 34, because the new lines live in a submenu).
  `OPTM_DEP`/`OPTM_DEP2` encode GROUP ids, not line numbers, so no
  dependency changes; the firmware has no hard-coded menu index at all
  (`osm_const.asm` is scraped from `C_MENU_*` and `OPTM_G_*`), so keep the
  new `C_MENU_HDMI_DVI : natural := 45;` and `OPTM_G_HDMIDVI : integer :=
  22;` SINGLE-LINE for awk (`$6`). Group ids must stay monotonic increasing,
  which is why the DVI group is 22, after the floppy block.
  THE HEAP HAD TO BE REBUDGETED (hard rule 11): demand 2298 -> 2325, so
  `MENU_HEAP_SIZE` 2304 -> 2336 and both `HEAP_SIZE` constants drop by the
  same 32 (debug 4736 -> 4704, release 27776 -> 27744) to keep the combined
  total at 7040 / 30080 - `HEAP`, `VAR$STACK_START` and `STACK_SIZE` do not
  move. THE ROUNDING RULE ITSELF CHANGED HERE, on sy2002's challenge: it said
  "next 128-word boundary", which cost 6 words at 146 items but would have
  left 107 dead words at 148 - and since `FB_HEAP` starts at `HEAP +
  MENU_HEAP_SIZE`, those words come straight out of the file browser. It now
  says 32, and `check_osm_menu.py` enforces the new quantum. Tight is safe
  because both budget checks are FATAL (`ERR_FATAL_HEAP1` at boot,
  `ERR_FATAL_HEAP2` on every menu open) and the checker is exact, so a
  shortfall can never be a silent regression. HELP_5 gained a three-line DVI note paid for out of its own footer
  padding, so the page stays at 33 of 34 rows.
  Verified: `check_osm_menu.py` all checks passed (148 lines, 41 singles + 3
  ranges cross-checked against the item TEXT, demand 2325, 8 help pages),
  `check_firmware.py` clean, `nvc --std=2008` clean on config.vhd (which
  also ELABORATES) and on mega65.vhd in the full M2M + CORE chain. Two red
  controls, run rather than assumed: `C_MENU_HDMI_DVI := 46` fails with
  "points at '', expected 'DVI (no sound)'" (the checker's `expected` table
  gained that entry - without it the loop, which iterates `expected` and not
  the HDL, would silently lose coverage for the new constant), and an extra
  `OPTM_GROUPS` entry fails nvc with "expected at most 148 positional
  associations". Zero `.xpr`/XDC/board-top impact: `qnice_dvi` is already
  routed in all four tops. README.md documents the feature and, because the
  symptom it cures is a black screen, the exact BLIND key sequence: `Help`,
  2 x Down, Return, 3 x Down, Return - derived from `OPTM_G_START` on line 2
  plus `_OPTM_RUN_SM_2` (a submenu opens on its first selectable line, 41),
  and valid only on the FIRST menu open after a core start (`OPTM_SELECTED`
  is sticky). The count rule is ONE DOWN PER DRIVE SET TO DISK IMAGE PLUS ONE
  for `Drive Settings` - NOT one per drive, which is what the first README
  draft said and what the review caught: a Hardware-Floppy drive contributes
  only a non-selectable `OPTM_G_TEXT` twin, and df0 as Hardware Floppy
  REMOVES a Down because `_OPTM_RUN_INI` normalises the hidden start cursor
  forward to `Drive Settings`. Verified over all nine reachable drive
  configurations. Getting it wrong is not harmless: one Down too many opens
  the SECOND `HDMI:` line (the filter submenu), where the same three Downs
  and Return select and SAVE the `Smooth` scaling filter while the screen
  stays black. Working doc: `.research/HANDOVER-dvi-osm.md`.

- **`WIP-V2-A11-JS-01` - 8 MB ZORRO II FAST RAM (R4/R5/R6). Fork
  increment (not by sy2002; version suffix `-JS-01` on purpose, and
  `make_release.py` will reject it - its regex only knows `WIP-V<n>-A<m>[X<k>]`).
  Implemented + simulated 2026-10-06, NOT yet synthesized/hardware-tested.**
  The Amiga gets MiSTer's 68000 Zorro II Fast RAM board back: 8 MB at
  `$200000-$9FFFFF`, autoconfig'd by Kickstart, served from the board SDRAM
  (IS42S16320F) that R4+ have and R3 lacks. Pieces:
  (1) `cpu_wrapper.v` (submodule, develop): the four June-2026 tie-offs
  undone with provenance comments - `ramsel` = original minus `sel_dd` (keeps
  the $DD4000 always-ack defence), `ramlds/ramuds/ramdin`, `ramaddr`, and
  `DTACKn = ramsel ? ~ramready : chip_dtack`. Zorro II maps 1:1 onto
  `ramaddr[22:1]` (`$800000-$9FFFFF` wraps onto the first 2 MB, distinct
  storage). `fastramcfg` 3 = 8 MB (1/2 = 2/4 MB), latched at every CPU reset.
  (2) NEW `CORE/vhdl/fastram_sdram.vhd`: SDRAM controller SYNCHRONOUS to the
  core clock (no CDC; follows the flicker-free BUFGMUX switch, SDR SDRAM has
  no DLL), CL2/BL1, ACT-RD/WR-NOP-PRE per access, refresh every 192 clocks
  from IDLE or DONE. Pin timing without I/O constraints by construction:
  IOB registers, SDRAM clock = inverted core clock via ODDR (~17 ns
  setup/hold), read data captured on the FALLING edge 2.5 clocks after READ
  (~20 ns setup / ~8 ns hold; a rising-edge capture fails for slow clock-out
  delay). Load-bearing CPU-protocol rules: a write starts only once UDS/LDS
  are asserted (data valid), `ready_o` is gated by `sel_i` AND the bus
  direction, and a transaction also ends on a direction change - 68000 TAS
  keeps AS asserted across its read and write halves. Reset only by the
  clock generator, so Fast RAM survives Amiga resets. 4 clocks to DTACK
  after the request (141 ns vs a 564 ns bus cycle; +<=3 wait states when a
  refresh collides).
  (3) `mega65.vhd`/`main.vhd`: `C_HAS_SDRAM = G_BOARD /= "MEGA65_R3"` gates
  the menu bit (`main_fastram_en`), which drives `fastramcfg` and
  `amiga_cold_boot` (new `fast_ram_i`, power-on applied value '0' = the
  menu default, so no spurious t=0 cold boot). (4) **M2M exception 10
  `sdram-pins`**: the R4/R5/R6 board tops route the 11 SDRAM pin groups into
  `MEGA65_Core` (floppy-pins pattern; R3 top untouched, its core ports stay
  open). Needs the maintainer's sign-off before any upstreaming.
  (5) MENU: the main view was full (OPTM_DY 34 = 36 rows), so line 143
  `Slow RAM (A501)` became a `Memory` submenu (143..149) holding `Slow RAM
  (A501)` (146, `C_MENU_SLOWRAM`, default ON) and `Fast RAM (8 MB)` (147,
  `C_MENU_FASTRAM`, `OPTM_G_FASTRAM` = 23, default OFF); OPTM_SIZE 148 ->
  154, OPTM_DY unchanged, demand 2325 -> 2434, `MENU_HEAP_SIZE` 2336 -> 2464,
  both `HEAP_SIZE` -128 (totals and `HEAP`=0x8280 unchanged). HELP_1 row
  count unchanged. Settings file `/amiga/aexp-WIP-V2-A11-JS-01.cfg` = 154 x
  0xFF. All four .xpr list the new file.
  VERIFIED (scratch tooling, ghdl 5.0.1 / Verilator 5.032 / iverilog 12):
  a ghdl TB with a timing-checking SDRAM model (init, tRCD/tRP/tRAS/tRC/
  tRFC/tWR/tMRD, refresh interval, setup/hold, CL2 tAC/tOH window, DQ
  contention) and a 68000 bus model (byte/word writes with S3/S4 timing, TAS,
  wait-state bound 3) over 23k transactions at four pin-delay corners, eight
  seeds and native/fast/stretched clocks - 0 errors; boundary sweep matches the hand
  budget (reads fail at clock-out + input delay ~29.5 ns); 7 of 8 mutants
  killed, the survivor (no tRFC NOPs) is equivalent (3 inherent idle clocks
  > tRFC). END-TO-END in Verilator: REAL fx68k + modified cpu_wrapper.v +
  the ghdl-converted controller run a 68000 program (autoconfig ID +
  configure, long/word/byte writes, two TAS, window corners, MOVEM, code
  executing from Fast RAM, 256-word pattern) - PASS; red controls (original
  cpu_wrapper.v, fastramcfg=000) fail. ghdl analyzes/elaborates the R3 and
  R6 hierarchies (framework stubbed) and config.vhd; QNICE firmware
  assembles natively, ROM differs from the A10 baseline only in the 14 words
  using the two heap constants.

- **`WIP-V2-A11-JS-01` (cont.) - IDE BOARD FOR HDF IMAGES, HDL PART. Fork
  increment, 2026-10-06/07: R6-built (WNS +0.309, BRAM 362.5/365), NOT
  hardware-tested; the firmware ATA server is the next step.** A Zorro II
  IDE controller register-compatible with RIPPLE (manufacturer 5194,
  product 7) so that the GPL lide.device boot ROM autoboots Kickstart 1.3
  from an HDF on the SD card. `cpu_wrapper.v` (submodule develop) puts the
  board into the autoconfig chain after the Fast RAM board (`ide_ena`,
  latched at CPU reset; the RESET instruction un-configures it) and routes
  its cycles off the chip bus through a new `ext_*` port. NEW
  `CORE/vhdl/ide_board.vhd`: RIPPLE ROM mapping (whole board before the
  first write, then +64K and A13 = A12), task file at +0x1000 (register n
  at n x 0x200, A11..A9, so lide's MOVEM bursts stay on the data
  register), control block at A14; BSY on a command write and DRQ off with
  the 256th word in hardware, everything else by the firmware through QNICE
  device 0x0107 (`C_DEV_AMIGA_IDE`; register map in the file header).
  `/amiga/lide.rom` (32 KB) is an OPTIONAL auto-load ROM streamed into
  device 0x0108 (`C_DEV_AMIGA_IDEROM`, a fourth `adf_mount_wrapper` used as
  a plain byte bridge) at HyperRAM `C_HMAP_IDE_ROM` 0x0380; the board reads
  it through an avm_fifo, so the HyperRAM arbiter now has 6 masters. The
  board joins the chain only when the firmware sets control bit 1 (0x118).
  No new XDC: the qnice<->main clock-pair max_delay covers the two LUTRAM
  buffers. Note for test writers: lide reads with MOVEM from data+460 so the
  68000's extra MOVEM read hits the error register.
  **Firmware + menu = `WIP-V2-A11-JS-02` (2026-10-07), emulator-tested, NOT
  yet hardware-tested.** OSM: ` HDF:%s` at line 34 of the Drive Settings
  submenu (the 4th OPTM_G_LOAD_ROM = manual ROM 3 into C_DEV_AMIGA_IDE,
  `OPTM_G_HDF` = 24, `C_MENU_HDF_MOUNT_LN`); every line from 33 on moved +2
  (OPTM_SIZE 154 -> 156, all C_MENU_* >= 33 renumbered, demand 2478,
  MENU_HEAP_SIZE 2496). ide_board answers the M2M CSR in window 0xFFFF
  (READY on STATUS=OK) and decodes its own registers in window 0 only.
  Firmware (m2m-rom.asm, "IDE board" section): `HDF_PREP` from
  PREP_LOAD_IMAGE (needs lide.rom = auto-load ROM 1 loaded, size a multiple of
  512 and >= 64 KB; own FDH copy, extent map `HDF_MAP` of 64 extents via
  `FAT32$FILE_MAP` - called directly, M2M's qmon_m2m.asm syscall table has no
  f32_fmap -, Shell handle seeked to EOF so nothing streams, control = present
  + board, then an M2M$CSR_RESET pulse so Kickstart autoconfigs the board);
  `IDE_STEP` in HANDLE_CORE_IO = the ATA server, one sector per slice:
  IDENTIFY (16 heads / 63 sectors, LBA, no multiple, words byte-swapped),
  READ/WRITE SECTORS LBA28 (CHS -> ABRT, out of range -> IDNF, SD error ->
  UNC), a list of no-data commands -> OK, everything else ABRT; every written
  sector is fflushed (one shared SD sector buffer); reset event = abandon;
  SD change / slot switch = drive vanishes. The board is in the autoconfig
  chain only while an HDF is mounted. 280 new variable words, so the release
  heap total went 30080 -> 29696 (HEAP 0x83AB, 1845 words left for the
  1536-word stack). No unmount gesture yet (mount another image instead).
  Out-of-repo tests: `~/aexp-work/fw-ide` runs the real IDE section of
  m2m-rom.asm in the QNICE emulator against a FAT32 image (40 MB HDF in 20
  extents + 1 MB HDF in 404 extents = map fallback; harness plays board and
  Amiga, another handle steals the sector buffer after every write; host
  check of every sector + fsck); 16 of 16 firmware mutants killed.
  **First hardware round (2026-10-07, R6 via JTAG): boots, `DH0:` appears,
  `FORMAT ... QUICK` works.** Found on hardware: (1) `avm_arbit_general`
  implements 2..4 slaves ONLY - with G_NUM_SLAVES = 6 slaves 4/5 were silently
  unconnected (a Synth 8-7129 "unconnected" warning was the only hint), so the
  board's first ROM read never got an answer and Kickstart hung on the grey
  screen. Fix: the general arbiter stays at 4 (`C_ARB_SLAVES`, guarded by an
  assert) and slave 3 is a tree of 2-input `avm_arbit`s: df2 | (ROM loader |
  ROM reads). (2) A full (non-QUICK) Workbench 1.3 `Format` fails with "Error
  during format": a lide.device bug (40.12 and current source), not the core -
  `device.c` clears `io_Actual` (the TD64 high offset) for CMD_READ/WRITE and
  ETD_READ/WRITE but not for TD_FORMAT/ETD_FORMAT, and Format reuses the
  request after a 1-block READ (io_Actual = 512), so the TD_FORMAT block
  address lands past the end and lide never sends the write. (3) Workbench
  1.3 Format allocates one buffer per CYLINDER: an RDB with 16 x 63 needs 516
  KB ("Out of memory" on a 1 MB A500); use small cylinders for 1.3-era images
  (test images: `~/aexp-work/hdf/mkrdb.py out.hdf cyls heads sectors`).
  The release bundles a PATCHED lide.rom: fork johansmolinski/lide.device,
  branch `aexp-td-format-fix` (Release-40.12 + fe2246d: TD_FORMAT/ETD_FORMAT
  clear io_Actual), built in upstream's CI image `liv2/amiga-gcc`
  (`make all`); a full Format then works on hardware (~1 s per 32 KB
  cylinder - the per-byte FAT32 API is the bottleneck).
  Debugging recipe: Run/Stop + Cursor Up + Help = QNICE monitor on the JTAG
  UART (115200); `~/aexp-work/qmon.py` types into it; device 0x0107 window 0
  at 0x7100.. = events, task-file snapshot, last commit, control.

- **MEGAMIGA 0.1.1 (2026-10-07) - THE FORK IS RENAMED.** At sy2002's request
  the fork (repo johansmolinski/Megamiga, formerly johansmolinski/AExp) no
  longer presents itself as AExp: `CORE_VERSION` = `0.1.1` (no longer a
  `WIP-V2-A11-JS-NN` string - `make_release.py` does not accept it, package
  by hand), CORENAME / welcome / HELP_1 = "Megamiga 0.1.1 - Amiga 500 for
  MEGA65, based on AExp by sy2002", settings file
  `/amiga/megamiga-0.1.1.cfg` (156 bytes), IDENTIFY model "Megamiga HDF
  image", README title + intro. Unchanged on purpose: the `/amiga` SD folder,
  `kick.rom`/`lide.rom`/`aexp_screen.cfg` names, all AExp provenance comments
  and the docs in `doc/`, which describe the AExp base.

- **Megamiga 0.1.2 (development, 2026-10-08): direct SD block I/O + HD LED,
  hardware-confirmed by the user ("works fine").** With `HDF_MAPOK` the ATA
  server no longer uses the FAT32 byte API: `IDE_LBA2BLK` maps LBA -> SD block
  through the extent map (`HDF_SPC_SHIFT`, cached extent `HDF_EXT_*`), and
  `IDE_READ_FAST`/`IDE_WRITE_FAST` do ONE block read/write per sector via
  `FAT32$CALL_DEV`, copying the 512 bytes between `IO$SD_DATA` and the IDE
  buffer. The shared SD sector buffer is borrowed with `_F32_RELEASE_BUF`
  (flush a dirty owner, owner := nobody) - load-bearing, the emulator test's
  dirty-steal check fails without it. More than 64 extents -> the old byte
  path. About 26,800 fewer QNICE instructions per sector. Drive LED: red while
  the IDE board is busy (`activity_o` = BSY or DRQ, stretched to 50 ms in
  mega65.vhd), priority red > yellow (ADF dirty) > green (floppy).
  `CORE_VERSION` 0.1.2, settings file `megamiga-0.1.2.cfg`.

- **BRANCH `a500plus` (Megamiga 0.2.0-dev, 2026-10-08, local only): A500+
  MODE - ECS chipset, 2 MB Chip RAM, 512 KB Kickstart, everything in SDRAM.
  R4/R5/R6 only (R3 support dropped on the user's request; CORE-R3.xpr no
  longer builds). Simulated, R6-built (WNS +0.013, WHS +0.024, BRAM 61/365,
  all SDRAM pin registers in the IOBs except the one data-OE register, whose
  5.75 ns to the pads leaves ~6 ns of write setup), NOT hardware-tested.**
  Timing needs the chipset -> sdram_ctrl multicycle constraints in CORE.xdc
  (minimig, amiga_clk cck and the static qnice2main OSM bits as sources, as in
  MiSTer's Minimig.sdc); the build_bitstream/reroll sign-off gates now check the
  native-pinned main_clk (35.242 ns) and the i_sdram_ctrl instance instead of
  the flicker-free fast leg.
  **HARDWARE-TESTED by the user on R6 (2026-10-08): "seems to work fine" -
  Kickstart 3.1 (512 KB) boots, Workbench 3.1 from ADF, an HDF made with
  `dd if=/dev/zero` (200 x 516096 bytes) partitioned with HDToolBox on
  `lide.device` unit 0.** Minimig's own
  `rtl/sdram_ctrl.v` (+ `cpu_cache_new.v`, both SFType SVerilog) is back, as on
  MiSTer: 113.5 MHz = 4 x main_clk from the NATIVE MMCM (clk.vhd CLKOUT1), 16
  states per 7 MHz cycle re-synced to c1 (`main.vhd` exports `c7m_o`), one
  access per slot (chipset > CPU write > cache fill > refresh), the SDRAM clock
  a register output (56.75 MHz), all pin registers IOB-packed (CORE.xdc).
  NEW `CORE/vhdl/amiga_sdram.vhd` wraps it: chipset port = the banked
  minimig_sram_bridge address (chip $000000.., slow $400000.., kick $780000 =
  512 KB) in SDRAM bank 0; Zorro II Fast RAM in bank 1 (`"01" & ramaddr`), so
  it cannot alias the chipset banks. A maintenance writer owns the chipset port
  while it has work: the Kickstart loader (QNICE device 0x0100 is now
  write-only; byte pairs cross through an xpm_fifo_async; words in the first
  256 KB are also written to the second, so 1.3 is mirrored and a 512 KB ROM
  overwrites the mirror) and the cold-boot scrub (amiga_cold_boot holds each
  SysBase word for 64 clocks). Each word: 8 clocks presented, 8 idle (refresh).
  fastram_sdram.vhd and the Chip/Slow/Kick BRAMs are gone (320 tiles free).
  amiga_config: 0xF3 = 0x08 (ECS), 0xF5 = 0x07 (2 MB chip + slow toggle).
  The core clock is pinned to native (`core_speed_i => "00"`, CORE.xdc times
  i_clk_main, case analysis on the BUFGMUX select) because the 4x clock has no
  fast twin: HDMI flicker-free does nothing in this mode. ECS SuperHires (28 MHz
  pixel CE) does not fit the M2M video path. Fixes to the MiSTer file
  (submodule branch `a500plus`): standard tri-state data bus instead of an
  `inout reg`, and registers declared before use (Vivado made implicit 1-bit
  nets otherwise - "already implicitly declared" is a must-fix warning).
  Timing basis (from minimig_m68k_bridge.v): the chipset address is valid from
  c1 rising, the controller takes it 2 fast clocks later and has the word at
  clock 11; the 68000 bridge latches at the end of Q2 = clock 12 (MiSTer's
  margin). Out-of-repo test: `~/aexp-work/a500p/sim` (Icarus: amiga_sdram via
  ghdl + real sdram_ctrl/cpu_cache_new + an SDRAM model with protocol checks;
  `fix_inout.py` patches ghdl's one-way inout; 5/5 mutants killed).

- **Megamiga 0.2 increment 2 (branch `a500plus`, 2026-10-08, R6-built WNS +0.243 WHS +0.030, NOT hardware-tested): LED colours,
  Kickstart selector, fast ADF I/O.** (1) Drive LED in `mega65.vhd`: GREEN =
  unflushed ADF writes (SD write-back pending) and wins over everything, RED =
  hard disk (IDE BSY/DRQ, stretched 50 ms), YELLOW = floppy (Paula disk DMA),
  ORANGE (`FF8000`) = hard disk and floppy together. HELP_3 and README follow.
  (2) KICKSTART SELECTOR: ` Kickstart:%s` at line 151 of the Memory submenu
  (`OPTM_G_KICK` = 25, manual CRT/ROM 4 into `C_DEV_AMIGA_KICK`; OPTM_SIZE
  156 -> 158, demand 2528, MENU_HEAP_SIZE 2528 with zero headroom - both heap
  checks fail only on demand > size - both HEAP_SIZE -32; HEAP 0x83BE, 1826
  words for the 1536-word stack). The kick device got the M2M CSR in window
  0xFFFF (`qnice_csr` in mega65.vhd; loader writes are gated off that window).
  CSR status LOADING crosses to the core clock (cdc_stable) and, ORed with the
  new `amiga_sdram.kick_busy_o` (FIFO not empty / writer active), holds
  `amiga_cold_boot` in reset; it scrubs SysBase, waits until the hold has been
  low for 64 clocks and releases = a cold boot into the new ROM. Firmware
  `KICK_PREP` (from PREP_LOAD_IMAGE): 256 or 512 KB only, then FAST_LOAD; on
  any error it writes CSR STATUS=IDLE itself, because the Shell leaves LOADING
  set and the Amiga would stay in reset for good. Not saved: power-on loads
  `/amiga/kick.rom` again. (3) FAST ADF I/O: `FAST_LOAD` (ADF mount and
  Kickstart) seeks the file to every 512-byte boundary - which reads that
  sector into the SD buffer - and copies it straight from `IO$SD_DATA` into
  the device window, then leaves the handle at EOF so the Shell streams
  nothing; `FLUSH_ADF_STEP` writes each chunk with seek + direct buffer fill +
  DIRTY flag + `f32_fflush` instead of 512 `f32_fwrite` calls. No extent maps
  (no RAM to spare). Out-of-repo test `~/aexp-work/fw-adf` (QNICE emulator,
  real FAST_LOAD/FLUSH_ADF_STEP extracted from m2m-rom.asm, FAT32 images with
  1- and 8-sector clusters and fragmented files, every stored byte checked for
  window/offset/value, flushed tracks checked on the image by the host, the
  sector buffer stolen after every step): PASS; mutants (no DIRTY flag, lost
  carry in the offset) fail. `~/aexp-work/a500p/coldboot/tb_cold.vhd`: hold,
  quiet period, single release - PASS, red control fails.

- **Megamiga 0.2 increment 3 (branch `a500plus`, 2026-10-08): fix + spin-up
  delay + load progress bar.** FIX (`8ed64c9`): FAST_LOAD clobbered R12, which
  the Shell's LOAD_IMAGE keeps the CRT/ROM id in across PREP_LOAD_IMAGE - every
  ADF mount died with fatal 0x0005 (ERR_FATAL_INST5, HANDLE_CRTROM_M); FAST_LOAD
  and KICK_PREP now preserve R10..R12, and the fw-adf harness checks it (red on
  the old code). SPIN-UP DELAY: ` Drive spin-up delay` at line 36 (end of Drive
  Settings, `OPTM_G_SPINUP` = 26, `C_MENU_DRV_SPINUP`, default OFF); every line
  from the old 36 on moved +2 (OPTM_SIZE 160, demand 2560 = MENU_HEAP_SIZE,
  both HEAP_SIZE -32, settings file 160 bytes). main.vhd counts CORE_CLK_SPEED/2
  clocks per unit from its motor latch (`hwf_motor_on_o`) and drives the new
  `fdd_vspin_n[3:0]` (minimig_m65 -> minimig -> paula -> paula_floppy
  `vspin_n`, ORed into the simulated units' /RDY source; 0000 = bit-identical,
  physical unit unaffected). Motor off = ready as before (drive-ID protocol).
  Reason: Amiga Test Kit reports "Drive READY too fast (207us): Gotek or
  modified PC drive?" on the instantly-ready Minimig drives. PROGRESS BAR:
  FAST_LOAD draws the Shell's bar itself (FL_BAR_INIT/STEP, Bresenham over the
  sectors, frame SCR$OSM_M_DX-4 at x=2 on the last line of the browser window,
  3 RAM words). Harness: exactly 44 progress + 46 frame characters per load.
  Lesson (twice in one session): a callee that does INCRB cannot see the
  caller's R0..R7 - pass values in R8..R12.

- **MEGAMIGA 0.2.0 RELEASED (2026-10-08, tag `V0.2.0` on branch `a500plus`,
  GitHub release asset `Megamiga-0.2.0-R6.zip`, R6 only).** A500+ (ECS, 2 MB
  Chip, 512 KB Kickstart, memory in SDRAM), Kickstart selector, fast ADF I/O
  with progress bar, new LED colours, drive spin-up option, read-only data
  device, upstream WIP-V2-B1/B2 merged. Release build WNS +0.287, firmware
  28211/28672 words. User-confirmed on hardware: KS 1.3/3.1 boot, WB 3.1 from
  ADF, HDToolBox HDF, fast ADF mount (~1.5 s, -e build). On 2026-10-08
  `a500plus` was fast-forwarded into `develop`, and `develop` was renamed to
  **`main`, now the default branch** of johansmolinski/Megamiga. The R3-capable
  0.1.x line lives on as tag `V0.1.1` (and the 0.1.2 work at `225ec4c`).

- **Megamiga 0.3.0-dev (main, 2026-10-08, local commits 440cf04/f6a87e2 +
  Minimig 1ea4fe6, NOT pushed): 68020 + 16 MB Zorro III Fast RAM.** Memory
  menu: `CPU: 68000` (default, fx68k) / `CPU: 68020` (C_MENU_CPU_020 = 155,
  OPTM_G_CPU 28) and `Zorro III RAM (16 MB)` (C_MENU_Z3RAM = 152, OPTM_G_Z3RAM
  27, effective only with the 68020); both cold-boot (amiga_cold_boot). OPTM_SIZE
  164, MENU_HEAP_SIZE 2656, both HEAP_SIZE -96, settings file 164 bytes.
  cpu_wrapper.v: TG68KdotC_Kernel instantiated again (MiSTer runs it on clk_sys
  = 28 MHz too; only the SDRAM controller is 4x), cpucfg 11 from the menu (also
  sent to Minimig via userio 0xF4 TT in amiga_config). MiSTer's 128/256 MB Z3
  boards (DDR3) replaced by ONE 16 MB Z3 board (ac_z3/z3_base A31..A24 from the
  0x44 word write, size code 000 extended) after the Z2 board; sel_rtg dropped
  from ramsel. ramaddr[28:27]: 11 = Z2 -> SDRAM bank 1, 10 = Z3 -> banks 2/3, 00
  = bank 0 (main.vhd builds the 24-bit fram_addr). amiga_sdram: MiSTer's
  Minimig.sv ram_cs gating in clk4x (div synced to c1, cyc, cs drops after
  ready&cyc for the 020; for the 68000 cs = sel, now registered). IDE board on
  the 020: ext_sel drops one clock after each completed access (ext_done) and
  the chip FSM ignores IDE cycles - the board ends a cycle only when sel goes
  away and TG68K has no AS gap (MOVEM). TG68K files in R4/R5/R6 .xpr (no
  SFType; TG68K_ALU infers a latch on msb - ghdl needs --latches).
  SIM: `~/aexp-work/a500p/e2e020` (TG68K + real cpu_wrapper + amiga_sdram +
  sdram_ctrl/cpu_cache_new via ghdl/Icarus, chip bus model, 68020 program
  prog.S): 020 instructions, autoconfig Z2/Z3/IDE, memory tests incl. window
  ends and aliasing, byte/word in Z3, code from Z2/Z3 with caches off/on, MOVEM
  bursts to an IDE handshake model - PASS; mutants (no ext_done, no ram_cs
  gating, wrong Z3 base byte, Z3 on the Z2 bank) all fail; the 68000 memory TB
  passes. R6: WNS +0.021 (framework hr_clk->hr_rwds), main_clk +4.9, LUTs 41.6k.
  HARDWARE (user, 2026-10-08): "It works as it seems" - more testing pending.

- **Megamiga 0.3.0-dev, AGA step 1 (branch a1200, 2026-10-08, 8d686b7 +
  Minimig 400e265): HARDWARE-CONFIRMED by the user ("AGA works", with the
  68020 and the A1200 Kickstart 3.1 kick31_a1200.rom).** amiga_sdram exports
  sdram_ctrl's chip48 (the 3 burst words after the addressed one), threaded
  mega65 -> main -> minimig_m65 (the 48'h0 tie-off is gone) -> Minimig, which
  uses it for the AGA fetch modes (denise_bitplanes.v latches {data16, chip48}
  at clk7n_en after the slot - after sdram_ctrl's state-15 latch; sampling at
  the slot edge itself reads the PREVIOUS burst's third word, which the memory
  TB in ~/aexp-work/a500p/sim now checks at the Denise point: 8 chip48 checks
  PASS). Memory menu chipset radio OCS 157 / ECS 158 (default) / AGA 159
  (C_MENU_CHIPSET_OCS/_AGA, OPTM_G_CHIPSET 29) -> amiga_config 0xF3 bits 4:3
  (minimig derives ecs = |chipset_config[4:3]); cold boot on change. OPTM_SIZE
  168, MENU_HEAP_SIZE 2720, both HEAP_SIZE -64, settings file 168 bytes. R6:
  WNS +0.116 (main_clk -> clk4x, the multicycled chipset path), main_clk +6.0,
  LUTs 43.0k. Next (step 3): SuperHires - the M2M video path takes 14 MHz
  pixels at most (hard rule 6); 31 kHz AGA modes are out of scope for now.

- **Megamiga 0.3.0-dev, SuperHires (branch a1200, 2026-10-08, 19447ae):
  R6-built (WNS +0.052), archived as `~/aexp-builds/Megamiga-0.3.0-dev-c`,
  HARDWARE-CONFIRMED by the user ("SuperHires works", 2026-10-08).** `frame_hires` includes
  `fs_res(1)` (the 14 MHz pixel enable for SuperHires frames) and main.vhd
  averages each SuperHires pixel pair (`f_avg` of the registered previous
  pixel) when `vid_res(1)`, so the M2M video path never sees a 28 MHz pixel
  (hard rule 6).

- **Megamiga 0.3.0-dev, MACHINE PROFILES + NESTED SUBMENUS (branch a1200,
  2026-10-08, M2M 1e6ccff + the profile commit). R6 build WNS +0.069
  (`~/aexp-builds/Megamiga-0.3.0-dev-d`); HARDWARE-CONFIRMED by the user with
  per-profile ROMs/HDFs on the card ("everything works great"). RELEASED as
  Megamiga 0.3.0 (tag `V0.3.0`, branch a1200 merged into main).**
  (1) **M2M exception 11 `nested-submenus`** (`M2M/rom/menu.asm`,
  `menu_vars.asm`): a submenu opener may sit inside another submenu.
  `_OPTM_STRUCT` pass 1 numbers the openers in order with a stack
  (`OPTM_SSTACK`, depth `OPTM_MAXNEST` 8) and records `OPTM_PARENTS[id]`
  (`OPTM_MAXSUB` 32 submenus); an opener is visible on its parent's level,
  every other line on its own submenu's level. A closer (`OPTM_G_CLOSE +
  OPTM_G_SUBMENU`) returns to the PARENT level with the cursor on the opener of
  the level being left. Flat menus behave exactly as before. The `%s`
  summaries (options.asm `_OPTM_CBS_I`) count openers in order, which is
  nesting-agnostic. Tests: `~/aexp-work/menu-nest/run.sh` (13-step nested test
  menu; the original menu.asm fails from step 4) and
  `~/aexp-work/menu-nest/real/` (`gen.py config.vhd data.asm` builds the REAL
  menu - items, masked groups, STDSEL, LINES, raw DEPS, HELP flags exactly as
  config.vhd serves them - then OPTM_DEPS_VAL + OPTM_DEPS_RESOLVE + a 45-step
  walk through profiles, Profile Settings, Settings and the nested HDMI menu;
  a dependency mutant fails). Rerun `gen.py` after every menu change. Note:
  the resolved dependency word holds the mother's flat index in 8 bits, so a
  mother group must start below line 256.
  (2) **Menu layout** (`config.vhd` OPTM_SIZE 206, generated by
  `~/aexp-work/menu-gen/gen.py` from the 168-line menu, which also renumbered
  the C_MENU_* constants): main page = headline, the df0..df2 twin lines, the
  profile radio `A500 (OCS)` 9 / `A600 (ECS)` 10 / `A1200 (AGA)` 11
  (`OPTM_G_PROFILE` 30, A500 default), `Profile Settings` (12..61), `Drive
  Settings` (62..90), `Settings` (91..201: Display / Audio / Keyboard with the
  HDMI, filter, VGA, OSM-scaling, volume, stereo and OSM-key submenus NESTED
  inside, their closers say `Back to Settings`), About, Close. Profile
  Settings: `HDF:%s` 15 and `Kickstart:%s` 16 (manual ROMs 3 and 4, LOAD_ROM
  order unchanged), then one 14-line block per profile (base 18 + 14 x
  profile: CPU 68000/68020 +0/+1, line, chipset OCS/ECS/AGA +3..+5, line,
  chip RAM 512K/1M/2M +7..+9, line, Slow RAM +11, Fast RAM +12, Zorro III
  +13), each line `OPTM_DEP(OPTM_G_PROFILE, p)`, groups `OPTM_G_P{1,2,3}{CPU,
  CS,CHIP,SLOW,FAST,Z3}` 31..48. Defaults: A500 68000/OCS/512K/Slow on, A600
  68000/ECS/1M, A1200 68020/AGA/2M. The old Memory submenu and its groups
  (SLOWRAM 11, FASTRAM 23, Z3RAM 27, CPU 28, CHIPSET 29) are gone (ids 11/23/
  27..29 unused). Heap: demand 3403 (10 submenus, 5 ROMs), MENU_HEAP_SIZE
  3424, both HEAP_SIZE -704 (debug 3360, release 26016). Settings file 206
  bytes. README blind DVI sequence: Help, 6 x Down (one per Disk Image drive
  + 5), Return (Settings), Return (HDMI), 3 x Down, Return.
  (3) **HDL**: mega65.vhd `prof_decode` picks the active block
  (`C_MENU_PROF_*`, `C_PROF_*` offsets) and drives main_cpu_020 / z3 (only
  with the 020) / slow / fast (C_HAS_SDRAM) / chipset / the new
  `main_chip_size` ("00" 512K, "01" 1M, "11" 2M = userio 0xF5 CC) into
  amiga_config (new `chip_size_i`) and amiga_cold_boot (new `chip_size_i`;
  power-on applied values now OCS + 512K = the A500 defaults, so no t=0 cold
  boot). `~/aexp-work/a500p/coldboot/tb_cold.vhd` checks the chip-size cold
  boot.
  (4) **Firmware** `PROFILE_APPLY` (m2m-rom.asm, + PROF_OPEN / PROF_NAME):
  from OSM_SEL_POST (group PROFILE, R9 = 0..2) and PREP_START (saved
  profile, boot mode). Opens `/amiga/a500.rom|a600.rom|a1200.rom` (names in
  the rodata device, `PN_*`) through the SHELL's device handle HANDLE_DEV
  (mounted/re-mounted like the file browser on SD_CHANGED - the sector buffer
  is tracked per device handle, so mixing CONFIG_DEVH with the browser's
  handle risks stale cached sectors), falls back to `kick.rom` on a switch
  (at boot kick.rom is already loaded), loads it via CSR LDNG -> KICK_PREP
  (FAST_LOAD, no progress bar: `FL_NOBAR`) -> CSR OK, then mounts
  `a500.hdf|...` via HDF_PREP or, on a switch without one, drops the HDF and
  takes the board out of the chain. The menu lines show the loaded names
  (heap slot + CRTROM_MAN_LDF, exactly as the Shell does). Firmware 28479 of
  28672 words. Test: `~/aexp-work/fw-prof/run.sh case` (real FAST_LOAD /
  KICK_PREP / PROFILE_APPLY against a FAT32 image with /amiga, 5 boot/switch
  scenarios incl. fallback, decoy ROM in the root, card change, register
  preservation, no bar) PASS; 9 firmware mutants all killed (`mut/`). The
  fw-adf harness gained the `FL_NOBAR` symbol and still passes.

- **Megamiga 0.3.1-dev, FLOPPY BUFFERS IN SDRAM (branch `rtg`, 2026-10-08,
  Minimig branch `rtg`): preparation for RTG - frees the HyperRAM for a
  framebuffer. R6 build `-b` WNS +0.036 (`~/aexp-builds/Megamiga-0.3.1-dev-b`),
  HARDWARE-CONFIRMED by the user ("Everything works": ADF boot + write-back
  across a power cycle, three drives, HDF boot, CPU load during floppy
  loads). RELEASED in Megamiga 0.3.1 (via `hdf2`).** The three ADF pools and lide.rom
  moved from HyperRAM into the board SDRAM. `sdram_ctrl.v` (submodule) gained
  a third port (`flpReq/flpAck` toggle handshake, one word per request) that
  addresses bank 0 with column bit 9 = 1 - the Amiga ports only produce
  columns 0..511 (24-bit address = 2 bank + 13 row + 9 column), so the 8 MB
  "floppy area" is disjoint from Chip/Slow/Kick/Fast RAM by construction, and
  every Amiga slot now clears `casaddr[9]` explicitly. Slot priority: chipset,
  then the floppy port (never twice in a row while the CPU waits, never while
  a refresh is due), then CPU write, cache fill, refresh. `amiga_sdram.vhd`
  turns the core-clock Avalon bus into those requests (bursts split into
  words; a reset goes through F_DRAIN so a word already in the controller
  finishes before a new one is taken - otherwise the toggles cross and the
  controller replays a stale or phantom access). `mega65.vhd`: the wrappers'
  "hr" side, the 2-input arbiters and `avm_arbit_general` now run on
  main_clk / `main_reset_m2m_i`; the two main->hr avm_fifos are gone (direct
  wiring); `hr_core_*` is tied off. The `C_HMAP_*` constants keep their values
  and now address the SDRAM floppy area (globals.vhd note). Signal prefix
  `hr_*_avm_` -> `mem_*_avm_`. **RESET TRAP (found on hardware with an ILA, build -a hung at
  `LOADING ROM #0001`):** the floppy path is reset by `main_rst` (clock
  generator), NEVER by `main_reset_m2m_i` - the board tops pass
  `main_reset_m2m or main_qnice_reset or main_rst` into that port, so it is
  HIGH for as long as the Shell holds the core in reset, i.e. during every
  ROM/ADF load; the adapter sat in F_DRAIN with waitrequest high. Debug flow
  for such cases: `~/aexp-work/rtg/ila/ila_build.tcl` (ILA inserted into the
  synth checkpoint, non-project, reads the three XDCs) + `capture.tcl`
  (programs over the MEGA65 JTAG via hw_server, CSV export). Test: `~/aexp-work/rtg/flpsim/run.sh` (the
  A500+ memory TB extended: 10-column SDRAM model, floppy bursts/byte lanes
  concurrently with chip + Fast RAM traffic, Amiga-memory snapshot unchanged,
  alias check against chip $1A5, one-clock reset at 8 slot phases) PASS;
  `mut.sh` 8/8 mutants killed, `rd_stage` is equivalent. `CORE_VERSION`
  0.3.1 (settings file `megamiga-0.3.1.cfg`, content identical to 0.3.0's).

- **Megamiga 0.3.1-dev, MASTER + SLAVE HDF (branch `hdf2` on top of `rtg`,
  2026-10-09, Minimig `hdf2` = `rtg`). HARDWARE-CONFIRMED by the user
  ("It works", then "Works now" after the menu fixes below); build -b
  (`~/aexp-builds/Megamiga-0.3.1-dev-hdf2b`, WNS +0.104). RELEASED as Megamiga
  0.3.1 (tag `V0.3.1`, `hdf2` merged into main).** Two IDE drives on the one RIPPLE channel, as on a real
  A600/A1200. HDL (`ide_board.vhd`): control register 0x118 bit 2 = slave
  present; `present` follows DEV (device/head bit 4) per drive; both drives
  share the task file, status and data buffer (a real ATA channel does too),
  so the firmware serves whichever drive the command was written to.
  FIRMWARE: the disk state of ONE drive is a contiguous block (`HDF_FDH` up to
  `HDF_SAVE`: handle copy, size, MAPOK, the extent cache and the 257-word
  extent map, `HDF_BLK_WORDS` = 276) which `HDF_SELECT` swaps with `HDF_SAVE`
  (the other drive) - so every sector routine stays untouched. ROM: 28572 /
  28672 after moving the IDENTIFY strings, the screen-config strings and the
  Hardware Floppy status templates into m2m-rodata.asm (RODATA_STR). `HDF_ACTIVE` = drive in the block,
  `HDF_UNITS` = mounted drives (bit 0 master, bit 1 slave; replaces
  `HDF_VALID`), `HDF_SD_SLOT` is global (a mount from the other slot drops the
  other drive). `IDE_CMD_START` selects the drive from DEV; `HDF_PREP` takes
  the drive in R9 (it validates BEFORE touching the drive: a bad file leaves
  the old disk mounted); `HDF_DROP` takes a drive mask; `HDF_CTRL` writes the
  present bits + board bit. The swap releases the SD sector buffer first: its
  owner is tracked by handle ADDRESS and both drives use `HDF_FDH` - today
  every data access releases it anyway (fast path `IDE_SD_TAKE`, slow path
  `_F32_SEEK`), so that release is insurance. MENU: ` HDF 0:%s` (master,
  manual ROM 3), new ` HDF 1:%s` (slave, manual ROM 4, `OPTM_G_HDF1` = 49),
  Kickstart is manual ROM 5 now (`PROF_KICK_ID`); every line from 16 on moved
  +1 (OPTM_SIZE 207, `C_MENU_PROF_BASE` 19), `C_CRTROMS_MAN_NUM` 6, demand
  3445 -> `MENU_HEAP_SIZE` 3456; both heap totals -288 for the 278 new
  variable words (release 29152, debug 6496; HEAP 0x85E4, stack margin 284).
  Profiles: `PROFILE_APPLY` loops over master/slave: `/amiga/a500.hdf` +
  `a500-1.hdf` (a600, a1200 alike); a profile with neither takes the board out
  of the autoconfig chain.
  ONE CSR PER HDF LINE (found on hardware: the A600 menu showed the A1200
  slave's name): the Shell derives the "loaded" state of a manual-ROM line
  from the CSR STATUS of its DEVICE (`CRTROM_MLST_GET`, polled while the menu
  is open), so two lines on one device share one state. The slave line loads
  into `C_DEV_AMIGA_IDE1` = 0x010A, a bare `qnice_csr` in mega65.vhd
  (`i_ide1_csr`, READY on OK like the master's CSR in ide_board.vhd).
  `HDF_DROP` writes STATUS IDLE on the device of every dropped drive (the line
  reverts to <Load>), `PROFILE_APPLY` writes OK after a profile mount (else
  the poll would clear the flag `PROF_NAME` set). EJECT: SPACE on a mounted
  ` HDF 0:` / ` HDF 1:` line (`HANDLE_UNMOUNT_KEY`, gate 3 = the `HDF_UNITS`
  bit, lines `AEXP_OSM_HDF_MOUNT_LN` / `AEXP_OSM_HDF1_MOUNT_LN`) calls
  `HDF_EJECT`: drop, board out of the chain if no drive is left, Amiga reset
  (lide only scans at reset); on an empty line SPACE still opens the browser.
  Settings file 207 bytes (a 206-byte 0.3.1 file
  gets a 0 inserted at offset 16). Tests: `~/aexp-work/fw-ide2` (records carry
  drive/DEV and a per-file XOR key so wrong-drive data is caught; HDF1 has
  exactly 64 extents = a full map, HDF2/HDF3 are slow-path; interleaved and
  same-LBA commands, a read across every extent boundary of the 64-extent
  file, a rejected slave remount, master remount, ejects of either drive and
  of the last one, card change; CSR stub per device and a counted reset pulse;
  cases spc 1/2/8/64 PASS; all mutants killed except `no_flush` and
  `sel_no_release`, equivalent under the fork's FAT32 library), `~/aexp-work/fw-prof2`
  (PROFILE_APPLY: A500 master+slave, A600 none = board out, A1200 slave only,
  CSR OK per mounted line; 9/9 mutants killed - its runner now refuses to
  count a harness that did not assemble as a kill), `~/aexp-work/ide/tb_ide_board.vhd` section 10 (slave
  present/absent, DEV seen by the firmware, a command to an absent slave never
  reaches it; 12/12 HDL mutants killed), `~/aexp-work/menu-nest/real` (207-line
  walk) PASS.

- **Megamiga 0.4.0-dev, RTG GRAPHICS CARD (branch `rtg`, 2026-10-09, Minimig
  `rtg`). Simulated, R6-built (build -c, WNS +0.288,
  `~/aexp-builds/Megamiga-0.4.0-dev-rtg-c`, CORE_VERSION still "0.3.1" so the
  207-byte settings file on the card fits). HARDWARE-CONFIRMED by the user
  (2026-10-09, Picasso96 2.0 on WB 3.1, A1200 profile): "RTG works", 8 bit
  snappy, 16/24/32 bit progressively slower, the PAL picture comes back.** MiSTer's Minimig RTG
  card: Picasso96 with MiSTer's driver, the picture shown by ascal's
  framebuffer mode on HDMI. Pieces:
  (1) `cpu_wrapper.v`: `sel_rtg` ($02xxxxxx, 68020 only) back in `ramsel`,
  tagged `ramaddr[26]` (the MiSTer byte swap of RTG accesses was still in
  place). (2) `main.vhd`: MiSTer's `rtl/rtg.v` on cpu_wrapper's fastchip
  port (as `fastchip.v` wires it: $B80xxx, registers at $B80100, CLUT at
  $B80400; 68020 path only), reset by CPU reset / RESET instruction
  (= Amiga picture back); outputs `rtg_*`, plus `fram_rtg_o`. (3) NEW
  `CORE/vhdl/rtg_vram.vhd`: the 68020's RTG fram cycles -> single-word
  Avalon at HyperRAM word $200000 (= byte $400000, 4 MB - the space the
  floppy buffers left); ready is ONE core clock per access and the next
  clock is skipped (TG68K has no AS gap; MOVEM), writes posted, reads
  waited, 8192-clock watchdog returns $FFFF. mega65.vhd: `amiga_sdram`
  only gets non-RTG fram cycles, read data/ready muxed, `avm_fifo` main ->
  hr_clk onto `hr_core_*` (reset `main_reset_core_i or main_rst` /
  `hr_rst_i`). (4) **M2M exception 12 `rtg-framebuffer`**:
  `fb_ena/hsize/vsize/format/base/stride` + the 8bpp palette (ascal `pal2`,
  `PALETTE2 => true`) threaded core -> top_mega65-r4/5/6 -> framework ->
  av_pipeline -> digital_pipeline -> ascal o_fb_* (all defaults keep other
  cores unchanged; R3 top untouched). ascal builds the core palette only with
  BOTH generics: `GenPal2 = PALETTE and PALETTE2` (build -a had PALETTE2 alone
  = no 8bpp palette, caught in the netlist); so `PALETTE => true` (the unused
  pal1 memory is trimmed) and `pal_n => '1'` (= use pal2). Byte layout = MiSTer's DDR3: the even
  Amiga byte in Avalon lane 0. CORE.xdc: false path from `CORE/i_main/i_rtg`
  to hr_clk/hdmi_clk (ascal samples them asynchronously; the palette RAM is
  written on the core clock and stays timed). (5) DRIVER: `CORE/rtg/`
  (MiSTer.card.asm + includes, LGPL) with MEMORY_SIZE $400000 and FB_BASE
  $00400000 (the HyperRAM byte address goes into the base register, as on
  MiSTer with its DDR3 address); `build.sh` uses vasm (`-Fhunkexe -nosym`
  reproduces MiSTer's shipped MiSTer.card BYTE FOR BYTE with the original
  constants); `make_adf.sh` (amitools xdftool) makes `Megamiga_RTG.adf` with
  the card and MiSTer's monitor + Picasso96Settings (from MiSTer_RTG.lha,
  extracted to `CORE/rtg/mister/`). Test: `~/aexp-work/rtg/e2e` (TG68K + real
  cpu_wrapper + amiga_sdram + rtg.v + rtg_vram + avm_fifo -> HyperRAM model at
  100 MHz with random waits; 68020 program: version reg $5001, register and
  palette round trips, long/word/byte + MOVEM to VRAM, patterns at both ends
  of the 4 MB, Chip/Z2/Z3 untouched; TB checks the HyperRAM byte layout and
  the register outputs) PASS; mutants (no skipped clock, byte lanes swapped,
  base 0, early read ready, unposted write, no cpu_wrapper swap) all killed.
  Not covered by simulation: ascal's framebuffer mode itself (MiSTer code).
  TIMING: CORE.xdc now also carries the CPU half of MiSTer's Minimig.sdc -
  `cpu_inst_p`/`cpu_inst_o` -> `i_sdram_ctrl` setup 2 / hold 1 (the select
  reaches the controller through amiga_sdram's ram_cs register, which stays
  single-cycle). The TG68K register file -> sd_ba path had fallen to +0.001;
  with the constraint the build closes at +0.288 (path slack 6.7 ns).
  SPEED-UP (build -e, 2026-10-09, simulated, NOT hardware-tested): (a)
  digital_pipeline gates ascal's `i_ce` with `fb_ena_i` (exception 12; needs
  fb_ena synchronous to video_clk - here both are the core clock), so ascal no
  longer writes the Amiga picture into HyperRAM while it shows the
  framebuffer; (b) NEW `CORE/vhdl/rtg_wcomb.vhd` on hr_clk between the
  avm_fifo and hr_core_*: gathers consecutive words of one aligned 16-word
  block (and merges byte writes into gathered words) and sends them as ONE
  burst from its own buffer, so the controller never sees a gap; flushes on a
  write elsewhere, a full block, 128 idle clocks, or a read of a gathered word
  (other reads pass, one access is ever outstanding). Before it, every word
  was one HyperRAM transaction (~15-20 clocks overhead) - the avm_fifo already
  posted writes 16 deep, so queueing was never the limit. Tests:
  `~/aexp-work/rtg/wcomb` (random runs/bytes/merges/reads against a burst
  HyperRAM model with 0/30/80 % waits, reference memory, burst protocol
  checks; 5 seeds PASS; `mut.py` 9 mutants, 8 killed, `no_full_limit` is
  equivalent - the aligned-block check already stops at 16) and the e2e TB
  with the combiner and a burst model (PASS). The first TB run found a real
  bug: a read issued while words were gathered carried burstcount = the
  gathered count.
  Process lesson: after a build, `git checkout CORE-R6.xpr` also throws away
  uncommitted INTENDED .xpr edits (build -b first failed with "no such design
  unit rtg_vram") - restore a saved copy instead.
  HARDWARE BLITTER (2026-10-09, 0.4.1-dev, build blit-a WNS +0.143; HARDWARE-
  CONFIRMED by the user: "The blitter works ... much faster now"):
  NEW `CORE/vhdl/rtg_blitter.vhd` - registers at `$B80800` (68020 fastchip
  port; rtg.v decodes nothing there and completes the cycle, main.vhd only
  muxes the read data: `blt_*` ports), engine on hr_clk sharing hr_core_*
  with rtg_wcomb through an `avm_arbit`. FILL (pattern of 1/2/4 bytes in
  memory order) and COPY (byte-generic, any source/destination alignment):
  each source line is read whole into a 4096-word BRAM line buffer, so
  overlap within a line needs no care; for overlap between lines the DRIVER
  passes the last line and negative strides when dst > src. Writes go out as
  aligned <=16-word bursts with edge byte enables. ORDERING with the CPU's
  own writes (rtg_vram -> avm_fifo -> rtg_wcomb): a start waits until the
  FIFO output is empty and the combiner holds nothing for 16 clocks
  (`h_quiet_i`), and meanwhile asks the combiner to send what it holds
  (`h_flush_o` -> rtg_wcomb `flush_i`); the driver waits for busy before it
  rewrites the registers, and Picasso96 calls WaitBlitter before CPU access.
  CORE.xdc: max_delay for the m_par_* registers and the two toggles.
  DRIVER (`CORE/rtg/MiSTer.card.asm`, `HasBlitter` now defined): FillRect,
  BlitRect, BlitRectNoMaskComplete (minterm $0C only), WaitBlitter, flag
  BIF_BLITTER (1<<15); anything else (plane mask /= $FF in CLUT, 24-bit fill,
  other minterms, a bitmap outside the board memory, lines > 8190 bytes)
  goes to the ...Default routine with all registers as they came in (push the
  address, rts). The pen goes into the pattern as a move.w/move.l would write
  it (8 bit: <<24, 16 bit: <<16) - UNVERIFIED for the PC (little-endian)
  16-bit format: if 16-bit fills have swapped colours, swap there.
  TESTS: `~/aexp-work/rtg/blit` (engine vs a burst HyperRAM model and a
  byte-exact reference, whole-memory compare after each command, 6 seeds x 0/
  30/85 % waits; 16 mutants all killed), `~/aexp-work/rtg/wcomb` (flush_i
  regression), `~/aexp-work/rtg/e2e` (68020 program: CPU writes the source
  last-line-first so the newest word is still in the combiner, then starts the
  copy at once; odd->even copy, overlapping copy, odd-address 32-bit fill;
  the combiner's idle timeout is 60000 there so ordering cannot lean on it -
  the start-without-wait mutant is caught; lesson: the TG68K model needs
  ~4.6 us per byte write, so with the real G_IDLE 128 the window never opened
  and three ordering mutants survived until the test was rebuilt), and
  `~/aexp-work/rtg/drvtest` (the driver's routines extracted VERBATIM from
  MiSTer.card.asm, called like Picasso96 with a fake BoardInfo whose Default
  stubs count calls, on the 68020 + hardware model via `e2e/tbdrv.sv`:
  fills 8/16/32 bit, default paths, overlapping BlitRect, two-bitmap copy,
  register preservation, a 24000-byte fill read back after WaitBlitter -
  PASS; 9 driver mutants killed). Lesson: the e2e HyperRAM model must start
  ZEROED - 68k CLR reads before it writes, an unwritten word returns x, and x
  in TG68K turned two mutant runs into timeouts that looked like hangs.
  ALSO IN THIS COMMIT - PROFILE NAMES AT CORE START: the first menu open
  showed `HDF 0:%s` / `HDF 1:%s` / `Kickstart:%s`, because PROFILE_APPLY runs
  from PREP_START before the menu exists (`OPTM_HEAP` = 0 until the first
  HELP_MENU) and PROF_NAME set CRTROM_MAN_LDF without a name in its buffer.
  Now PROF_NAME keeps the path label in `PROF_PEND` (+ flag `PROF_PENDF`) while
  `OPTM_HEAP` is 0 and leaves the loaded flag alone; `PROF_PEND_APPLY` (in
  HANDLE_CORE_IO, which the menu key loop runs BEFORE CRTROM_MLST_GET) shows
  the names and sets the flags once the menu exists. PROFILE_APPLY clears flag
  + table first (uninitialised RAM would otherwise be taken as labels - the
  harness's 0xDEAD case caught exactly that). Test `~/aexp-work/fw-prof2`
  (boot with no menu, then the replay): PASS; 15 of 16 mutants killed, the
  survivor (no heap check in the replay) is equivalent, PROF_NAME defers
  again. ROM 28650/28672. HARDWARE-CONFIRMED by the user (build -d,
  2026-10-09): the names show on the first menu open.
  TEXT, PLANE MASKS, READ-AHEAD (0.4.2-dev, 2026-10-09, build tmpl-b WNS
  +0.054; HARDWARE-CONFIRMED by the user: "Scrolling is much faster now"). Field report on 0.4.1: Shell scrolling slow, slower in 8
  bit than in 16 - the AmigaOS console draws with a PLANE MASK on CLUT
  screens, and the 0.4.1 driver gave every masked call back to the CPU.
  (1) TEMPLATE command (CMD 3, `BlitTemplate` = text): registers TBYTES $18,
  TCTRL $1A (bit offset, JAM2, INVERSVID), BGPAT $20/$22. The driver copies
  the 1-bit template by longwords into one of two 64 KB scratch areas at
  board offset $3C0000 (behind MemorySpaceSize, below the mouse save buffer;
  alternating, so the copy overlaps the engine drawing the previous one -
  the driver waits for busy only before it writes the registers); the engine
  reads each template line into the line buffer and expands it through a
  32-bit bit window (`tcur` + the BRAM output = the next word), lane 1 is the
  next pixel when its byte starts one. JAM1 = byte enables off (empty beats
  are legal: the HyperRAM errata path sends them too). COMPLEMENT, 24 bit and
  templates over 64 KB go to the default routine. (2) PLANE MASK, register
  $24 (bits 7:0, $FF = none, driver writes $FF outside CLUT; mask 0 = the
  driver does nothing): the engine reads each 16-word destination block
  before writing it (E_DRD_*) and merges (old and not m) or (new and m) -
  fills, copies and templates. (3) READ-AHEAD in rtg_vram: a miss fetches
  the aligned 16-word block (one burst) into one of two lines (LRU), the CPU
  gets its word as it arrives, hits answer in one clock; CPU writes update a
  line that holds their word; `inval_i` = the blitter's new `m_busy_o`
  clears the lines and spoils a running fill. rtg_wcomb passes read bursts
  (burstcount from avm_fifo, reads of the gathered block flush first);
  avm_fifo read depth 16 -> 32. Lesson: ghdl --synth drops initial values
  and a 2-write-site array came out as X - the lines are now one write port
  per byte lane and `victim` has a reset (the e2e caught both; the plain
  VHDL TB did not). NOT fixed: the mouse pointer blinks during Shell
  scrolling - Picasso96's software pointer is taken off around every blit
  touching it; a hardware pointer would need an overlay after ascal.
  TESTS: `~/aexp-work/rtg/vram` (NEW: rtg_vram + FIFO + combiner, TG68K-like
  CPU model without gaps, read-modify-read, fake blitter busy + memory
  changes; 9/9 mutants killed), `rtg/wcomb` (16-word read bursts with beat
  gaps, timeouts on every wait; 12/13 killed, `no_full_limit` equivalent),
  `rtg/blit` (templates with random xoff/JAM/INV/alignment, random masks;
  new template + mask mutants killed, `t_tbytes_width` (reads more) is
  equivalent), `rtg/e2e` prog.S (read-ahead coherence incl. misaligned longs
  over 3 blocks, lines cached before a copy/fill), `rtg/drvtest` tests 10-18
  (templates 8/16/32 bit, registers kept, defaults, three templates back to
  back with a 400-line one, masked template/fill/copy over a background).

- **Megamiga 0.4.2, SERIAL PORT ON PMOD1 (2026-10-09, R4/R5/R6). Built
  without a PMOD module here, released for outside testers; HARDWARE-CONFIRMED
  by a tester with an RS-232 module on 2026-10-12.** Paula's UART (Minimig `rxd/txd`) and CIA-B /CTS /RTS reach the
  PMOD1 header through the new M2M exception 13 `pmod-pins`; MegaST pin
  layout (lo: CTS in, TXD out, RXD in, RTS out; hi: MIDI OUT = TXD, MIDI IN
  ANDed into RXD), inputs through a 2-FF ASYNC_REG synchronizer, pull-ups in
  CORE.xdc. `Settings > Ports > Serial port on PMOD` (`C_MENU_SERIAL` 204,
  `OPTM_G_SERIAL` 50, default OFF = every PMOD pin high-Z and both headers
  unpowered); OPTM_SIZE 207 -> 211, MENU_HEAP_SIZE 3520 (both HEAP_SIZE
  -64). DTR/DSR/CD/RI stay tied inactive. Settings file 211 bytes. Built in a
  separate session (worktree `.claude/worktrees/serial-pmod`) and merged as
  a patch; the menu walk (`~/aexp-work/menu-nest/real`, 211 lines) passes.

- **Megamiga 0.5.0-dev, NETWORK CARD (2026-10-09, R4/R5/R6). R6 build eth-b
  (WNS +0.125, `~/aexp-builds/Megamiga-0.5.0-dev-eth-b`), HARDWARE-CONFIRMED by
  the user: `ethtest` ARP probe answered, Roadshow 1.15 pings the gateway.**
  Design and register map: `doc/developers/ethernet.md`. A Zorro II board of our
  own (manufacturer 2011, product 101, 64 KB, INT2), not an emulated card:
  `CORE/vhdl/eth_card.vhd` (registers, 16-slot RX ring and TX buffer in
  dual-clock BRAM, Gray/toggle CDC, MDIO: advertise 100BASE-TX only, poll link
  + $1E mode; PHY reset 10 ms), `eth_mac.vhd` (RMII 100 Mbit/s: RX latched at
  200 MHz at a selectable phase and TX through a 200 MHz delay line, the
  MEGA65 core's scheme; default PHASE $05 = the MEGA65 etherload values, which
  worked first time; CRC-32, end of frame after 3 low CRS_DV samples),
  `eth_clk.vhd` (own MMCM: 50 MHz to the PHY + 200 MHz), `eth_dna.vhd` (MAC =
  02 + DNA folded to 40 bits). cpu_wrapper: `ac_eth` after the IDE board,
  `ext_eth` selects which board `ext_*` serves (main.vhd splits); minimig.v:
  `eth_irq` ORed into int2. New M2M exception 14 `eth-pins` (R4/R5/R6 tops
  route the PHY pins). CORE.xdc: eth clocks, main<->eth50 max_delay, false
  paths on the RMII/MDIO pins. Driver `CORE/eth/` (`megamiga-eth.device`,
  from a314eth.device, CC0; asm INT2 server masks the level RX interrupt until
  the device process drained the ring) + `ethtest` (no stack: card, link,
  ARP probe, `PHASES` sweep) + `Megamiga_Net.adf` (make_adf.sh, Roadshow
  templates, DHCP by default); built with vbcc 0.9h + NDK 3.2
  (`~/aexp-work/eth/tc`, build.sh needs VBCC and NDK). TESTS:
  `~/aexp-work/eth/card` (tb_eth: PHY model with CRS_DV toggling, filters,
  runts/giants/partial bytes with good FCS, overflow, TX decode, MDIO;
  19/19 mutants killed), `~/aexp-work/rtg/e2e` (eth_chain = card + looped
  PHY: autoconfig nibbles, registers, a frame out and back, MOVEM/byte reads),
  `~/aexp-work/ide/e2e` (68000 IDE with the changed cpu_wrapper; needs
  tg68_stub.v now). Lesson: in the e2e TBs `cw.wr` is HIGH for a read.

- **Megamiga 0.5.1, AMIGAVISION BOOT FIX (2026-10-10, Minimig `rtg` aa1f75c).**
  Field report: AmigaVision (the TheA500 Mini build, two HDFs: system with
  DH0 Amiga: + DH1 Data:, PFS3, and Saves.hdf as slave) went black after
  loading for a while on 0.5.0; a user said it booted on 0.3.0. NOT the HDF
  path (both files one extent each on the card, direct-block path, the
  arithmetic checked) and NOT the screen mode. Cause, from the HDF's scripts
  and disassembled tools: `ags-uname` reads the long at `$B8010E` (the RTG
  ID register) - `$5001` = "mister", `$6001` = "pocket", else an expansion
  board by manufacturer 2011 = "uae", else "amiga". Since 0.4.0 rtg.v
  answers `$5001`, so `S:mount-misterfs` runs `mount MR0:` with
  `L:MiSTerFileSystem`, which writes a command to `$DD4002` and spins until
  MiSTer's HPS echoes it (`cmp.w (a1),d2 / bne`) - never, here (the
  `$DD4000-$DD5FFF` range goes to the chip bus). `bblank` has already
  blanked the screen. The user confirmed with the workaround (`EQ "nomister"`
  in `S:mount-misterfs`). FIX: rtg.v ID register reads `$4D01`; our driver
  never reads it (`REG_ID` unused in MiSTer.card.asm), and MiSTer's stock
  MiSTer.card cannot work with this board anyway (FB_BASE `$27000000`, 8 MB).
  AmigaVision now says "uae" (the network card is manufacturer 2011); a
  search of both HDFs found `ags-uname` only in the startup-sequence (uae:
  a `Picasso96:` assign) and mount-misterfs. A MiSTer shared folder
  (answering the `$DD4000` mailbox from the firmware) would be a feature of
  its own. Settings file unchanged (211 bytes).

- **Megamiga 0.5.2, 32K ROM + HARD DISKS ON SD CARD PARTITIONS
  (2026-10-10).** (1) M2M exception 15 `rom-32k` (see AGENTS.md): the QNICE
  device window moved to `0x8000`-`0x8FFF`, so the firmware has the whole
  32,768-word ROM (it was at 28650/28672). R6 build rom32k-a (WNS +0.012; the
  thin paths are the known hr_rwds input and TG68K -> sdram `ram_cs`, not
  QNICE) HARDWARE-CONFIRMED by the user: menu, ADF boot, HDF boot, an HDMI
  filter (= `_PP_COPY` from the moved rodata window), settings saved.
  Firmware side: core window constants `0x8xxx`, variables `.ORG 0x9000`,
  `_PP_COPY` tests `> 0x7FFF`, release heap total 29152 -> 25056 (`HEAP_SIZE`
  21536; HEAP 0x95E8 + 25056 = 0xF7C8, 1816 words for the 1536-word stack -
  the margin is unchanged because variables and heap moved together), the
  develop-mode heap is 0 (that mode has not fit for ages); `make_rom.sh`
  exports rodata labels as 0x8000 + offset, ROM_MAX_WORDS 32768, variables
  expected >= 0x9000. The QNICE RAM BRAM outputs 0 when not enabled (it shares
  the ORed bus with the window). Test harnesses that relocate windows
  (`~/aexp-work/fw-ide2/extract.py`: `0x81..`/`0x8000` -> `0xC1..`/`0xC000`)
  must follow. (2) HDF LINK FILES (`HDF_LINK` in m2m-rom.asm): an .hdf file
  under 512 bytes starting with `MEGAMIGA-PARTITION n` (n 1..4, any case)
  makes the drive MBR partition n of that card - only type `0x7F` (the "local
  / experimental use" type of the MBR list; no OS claims it), >= 64 KB, start
  block > 0, signature 55 AA; anything else is refused (`WRN_HDF_PART`); the
  other drive holding the same partition start -> `WRN_HDF_PDUP`. The FAT32
  library reports ABSOLUTE card blocks (its mount stores the MBR start), so
  the partition uses the same device handle and block calls as the HDF fast
  path. Per-drive state block gained `HDF_PART`/`HDF_PST_LO/HI`
  (`HDF_BLK_WORDS` 279); file mounts clear `HDF_PART`; `IDE_LBA2BLK` returns
  start + LBA for a partition (`HDF_MAPOK` = 1); size capped at LBA28. The
  QNICE FAT32 library has NO file creation, which is why the per-profile
  choice is a link FILE (`a1200.hdf` = link) and not something the firmware
  writes. Firmware 28971/32768. TEST: `~/aexp-work/fw-ide2` case `case_p`
  (gen.py: MBR entry 2 = 0x7F 2 MB with the keyed pattern, 3 = 0x7F too
  small, 4 = FAT16; link files P2 / P2L (lower case) / P1 / P3 / P4 / P5 / PX;
  mount, the full block of commands, interleaving with a file slave, the
  same partition on the slave refused, refusals, remount, a fast-path FILE
  after a partition on the same drive; hostcheck checks the raw partition
  blocks) PASS + the old cases; 9/9 `lnk_*` mutants killed (the runner now
  counts `FAIL record` output as a run - with many failures run.sh's head cut
  the RESULT line).
  HARDWARE ROUND (2026-10-10, R6 builds part-a WNS +0.137, part-b same):
  through the profile a link file mounts and HDToolBox wrote a valid RDB into
  partition 3 (MDH0 100 MB + MDH1 900 MB, FFS in the RDB), both formatted and
  work; a menu-picked link file and master + slave on two partitions pass
  too. Found on the way: (a) FATAL 0x0005 when a link file was picked in the
  menu: the link path of `HDF_PREP` returned with R10..R12 changed (HDF_LINK
  answers in R9..R12), and the Shell keeps the CRT/ROM id in R12 across
  PREP_LOAD_IMAGE (the KICK_PREP lesson of 0.2.0 again; the profile path does
  not care, so the first test passed). FIX: `HDF_PREP` saves and restores
  R10..R12 at its one exit; the harness now seeds R10..R12 before every
  `HDF_PREP` and checks them (code 0x010F) - RED on the old code at exactly
  the 10 link mounts, GREEN fixed. (b) "MDH1: No disk present" / Format "no
  disk in drive" was NOT a core bug: the monitor (`M C FFF4 0107`, `M D 8100
  811F`) showed MDH1's boot-block READ (LBA 201600) answered OK; the block
  was never written and that card reads such blocks as 0xFF, and FFS takes a
  first long of 0xFFFFFFFF (= -1) as ID_NO_DISK_PRESENT. Zeroing the block
  fixed it; README now says to zero a new 0x7F partition. (c) The emulator
  test's partition had 4096 sectors, so the LBA high word was never used on
  the partition path: case_p now has 140000 sectors (0x10000 and 0x20000
  boundaries, the end) and a mutant that drops the high word (`ADDC` ->
  `MOVE` in `IDE_LBA2BLK`) fails 40 records where the old case PASSED.
  A full (non-QUICK) Format is slow (one SD block write per sector + the
  verify pass): use QUICK. Released as 0.5.2. Firmware 28977/32768.
- **68040 EXPERIMENT, step 1 (branch `cpu040`, worktree `../AExp-cpu040`,
  2026-10-10, Minimig `cpu040` 34ffc65, NOT merged).** Goal (user): a fast
  CPU, ideally an 060 at 50 MHz. Survey (`~/aexp-work/cpu060/FINDINGS.md`):
  no open 060 exists; open 040s do - apolkosnik/AP68040 (sequential, MMU,
  FPU, caches, GPLv2 WITHOUT "or later" - must be cleared with the author
  before any release next to GPLv3 code) and ranzbak/AP68040-pipelined (6
  stages, GPLv3, in MinimigAGA_TC64 on an XC7A100T at clk_114/3 = 37.8 MHz,
  Kickstart 3.1.4 to Workbench, 47k Dhrystones = 1.44x A4000/040). OOC on our
  -2 part at 17.62 ns: TG68K +0.039 (about 57 MHz), the pipelined core about
  21.1 ns (about 47 MHz, 28 logic levels; the LUT count of that run was
  inflated by the core's simulation dpram). STEP 1 integrates the pipelined
  core at TC64's commit 8ead239 as `rtl/ap040` ON THE 28 MHz CORE CLOCK:
  main.vhd `C_CPU040 = 1` makes cpu_wrapper instantiate it instead of TG68K
  when the menu says 68020 (no menu change). TG68K's 16-bit bus via the
  core's own `ap040_bus16_adapter` (BUS16 = 1), so the whole 68020 path
  downstream is unchanged. NEW in cpu_wrapper: (a) a walker bridge - the
  MMU's 32-bit table-walk port runs as two 16-bit cycles on the same bus,
  only while the adapter is idle, with the core's clock enable held low
  for the length of those cycles; ack held until the MMU drops its request;
  (b) chipset writes to Chip RAM (main.vhd: `ram_we_n_o` and a strobe,
  banked `ram_addr_o[22:21] = 00`) into the data cache's snoop port - the
  core's D cache caches Chip RAM; (c) CACR bit 15 -> cpu_cache_new enable,
  CINV/CPUSH -> its clear. dpram renamed `ap040_dpram` and replaced by
  TC64's two-process block-RAM version (the core's own model costs ~43k LUTs
  in Vivado). Conservative configuration: synchronous stores, none of the
  speed-up parameters, no fill channel. PITFALL found: names used inside a
  generate block before their module-level declaration become new undriven
  nets in the block's scope (iverilog: the core's clock enable was X and it
  never ran) - cpu_req, cpu_ipl, chipready, z2ram_ena, z3_* are now declared
  above the block. SIM: `~/aexp-work/cpu060/e2e040` (the RTG e2e with
  CPU040, `build.sh`, `bt.sh`): the whole 68020 program (autoconfig, IDE
  MOVEM, network card, memory tests with caches, RTG, blitter) plus an
  040 section - FPU arithmetic, MOVE16, a 3-level page table in Zorro II
  (logical `$50000000` -> `$00500000`, TTRs for the rest), U then M set by
  the walker, an access error on an unmapped page resumed by the handler,
  and Chip RAM coherency against a testbench DMA write with its snoop -
  PASS; the TG68K build of the same program (CPU040 = 0) PASS. Mutants:
  walker halves swapped -> hang; snoop off -> $BAA9 (stale $11112222).
  BUILD b (after two fixes, `~/aexp-builds/Megamiga-cpu040-b`): WNS +0.014,
  WHS +0.030, main_clk +1.587, 75.8k LUTs, 93.5 BRAM. Fix 1: build a missed
  by -0.41 ns on clk4x -> main_clk, sdram_ctrl's cpu_ack through the core's
  clock enable (19 levels): cpu_wrapper registers the RAM answer (ram_rdy_r /
  ram_dat_r, one CPU clock per RAM access) and drops the ramsel PORT in that
  clock (ram_hold) so amiga_sdram's cs, which pulses low on ready&cyc for the
  020, does not come back for a second access (the SDRAM model's read/write
  counts are identical before and after). Fix 2: CORE.xdc's CPU->SDRAM
  multicycle named `i_cpu_wrapper/cpu_inst_p/*`; inside the generate block
  the instance is `g_tg68k.cpu_inst_p`/`g_ap040.cpu_inst_p` - now
  `*cpu_inst_p/*`. HARDWARE (user, 2026-10-10): boots, SysInfo "68040" with
  FPU and a big speed-up; RTG gave a black screen.
  RTG ON THE 68040: Commodore's 68040.library 37.30 (OS 3.1 Install disk,
  disassembled) switches the MMU on whenever TC is writable: at 0x9f4a it
  builds tables for the first 4 KB, $BC0000 (256 KB), $D80000 and $F00000
  (512 KB each), the ROM, PCMCIA/$E00000 when present, the memory list and
  every FindConfigDev board without ERTF_MEMLIST, then at 0x646 loads
  URP/SRP/TC and CLEARS ALL FOUR TTRs. MiSTer's RTG card sits at fixed
  addresses ($B80100, $02000000) that are neither, so Picasso96's first
  access faults. FIX: the card is also an autoconfig Zorro III I/O board
  (8 MB, 2011/102, after the Z3 RAM board in the chain, so $41000000 with
  the RAM board): +0 = the board memory (sel_rtg), +$400000 = the $B80000
  register page repeated every 4 KB (chip_addr remapped to $B80xxx and
  fastchip_sel, so main.vhd's RTG/blitter decode is unchanged). The fixed
  addresses stay. ap040 compat patch: cache_z3_base0 is A31..A24 (exactly
  the 16 MB RAM board) - the 128 MB window held the RTG board too and would
  have cached it with the MMU off. MiSTer.card: FindCard takes the
  addresses from the board (FindConfigDev, clears CDB_CONFIGME), else the
  fixed ones; the blitter routines read MemBase/MemEnd/BltBase through an
  address register (never PC-relative: a program-space read could come from
  the 040's I-cache); BlitRect/BlitRectNoMaskComplete also save a1 (CopyRect
  uses it). SIM: e2e040 configures the board and checks both halves against
  the fixed addresses (ID, palette, blitter ID, page repeat, long/byte
  memory) on the 040 and TG68K - PASS; `~/aexp-work/cpu060/drvtest` = the
  0.4 driver test (BOARD variant: the RIs and bases at $41000000) on both
  CPUs. The driver test needs about 41 minutes and more than 2M clocks
  (MAXCYC 20M).
  RESULT: all four driver runs PASS (tests 1..$18); build cpu040-c WNS
  +0.129 WHS +0.036 (`~/aexp-builds/Megamiga-cpu040-c`, with the new
  `Megamiga_RTG.adf`); not hardware-tested yet.
- **68040 EXPERIMENT, step 2: the core on its own clock (branch `cpu040`,
  2026-10-11, C_CPU040 = 2, NOT hardware-tested).** `rtl/ap040_island.v`:
  the core free-running on clk_cpu (clk.vhd CLKOUT2 of the main MMCM, own
  BUFG) with its 32-bit master port (BUS16 = 0); the master port and the
  MMU walker share ONE request channel (fields in registers + a toggle,
  2-FF synchronized; answer toggle + held data back; walker first when
  both ask; no new request in the clock of an answer, whose requester only
  drops its request at the consuming edge). The bus side runs
  ap040_bus16_adapter on the 28 MHz clock, completed by the same clock
  enable as before, so everything downstream (registered RAM answer,
  ram_hold, chip FSM, IDE/network, fastchip) is unchanged; the walker
  bridge is gone. Snoop: one toggle per chipset write (the strobe is a
  level for the whole write; an even number of toggles is invisible) -
  writes are 4 bus clocks apart, the CPU takes a toggle within 3 of its
  clocks (the e2e DMA model now writes 4 clocks apart like the chipset).
  ipl, reset, windows, CACR/VBR/nresetout/CINV: 2-FF levels. CORE.xdc:
  `create_generated_clock -name cpu_clk` on CLKOUT2 and a datapath-only
  20 ns max delay both ways. cpu_wrapper CPU040_FAST passes the TC64 speed-
  up set (POST_STORES, STORE_BUF, FWD, RAS, PRECISE, SB_MMU, BTFN, LDX; no
  COPYBACK). SIM: e2e040 at 47.29 MHz, speed-ups off and on - PASS; snoop
  mutant -> $BAA9; driver test at the board addresses, off and on - PASS.
  BENCH (`~/aexp-work/cpu060/bench`, 500 iterations of a load/mul/store loop
  in Zorro II RAM, caches on, 28 MHz clocks): TG68K 14,764; 040 on the bus
  clock 17,788; island 47 MHz 17,432; island + speed-ups 12,184 (47 MHz) /
  12,460 (42 MHz) = 1.18x TG68K. The 040's caches work (fetches 1003 -> 38,
  reads = the 64 line fills); every long store is still two 16-bit bus
  writes of about 12 bus clocks each, so this loop is bus-bound - the next
  big step is a faster memory path (32-bit, fewer handshake clocks), not a
  faster CPU clock. Build cpu040-d at 47.29 MHz: cpu_clk WNS about -1.5 ns
  post-route (the core's bus unit, ~22.7 ns), stopped; build e at 42.04 MHz
  (1135/27) with the speed-ups: cpu_clk about -1.8 ns post-place (the
  speed-ups lengthen the paths to ~25.5 ns), stopped. Build f: 37.83 MHz
  (1135/30 = 113.5/3, TC64's rate).
  WRITE BUFFER (ap040_island WRITE_BUF, on with CPU040_FAST): the request
  channel became an asynchronous FIFO (8 entries, Gray pointers, entry
  written before the pointer moves); a write is acknowledged to the core
  when queued, the bus side runs the queue back to back, reads wait behind
  earlier writes (order kept; this bus never answers with an error). The
  trace showed 8-10 idle bus clocks per access before (the toggle round
  trip). e2e040 and the driver test (board addresses) PASS with it.
  BENCH at 37.83 MHz, speed-ups + write buffer, 28 MHz clocks: store loop
  11,396 (TG68K 14,764: 1.30x); register-only loop (2000 x 8 instructions,
  all from cache) 17,032 (TG68K 22,240: 1.31x - per CPU clock the 040 is
  about as fast as TG68K here, the gain is the clock). NOTE the bench's
  bus-cycle counter counts state changes, so TG68K's back-to-back fetches
  read as a handful.
  THE SPEED-UPS DO NOT CLOSE: build f (37.83 MHz, speed-ups + write buffer)
  still missed cpu_clk by ~2.7 ns post-place in the branch-redirect paths
  (u_if/u_id/u_eac -> u_bcu mem_addr), stopped. Bench with the write buffer
  ONLY at 42.04 MHz: register loop 15,440 (1.44x TG68K), store loop 11,948
  (1.24x) - as good as the speed-up build overall, so CPU040_FAST became
  1 = write buffer, 2 = also the speed-ups, and main.vhd uses 1.
  BUILD g (`~/aexp-builds/Megamiga-cpu040-g`, with Megamiga_RTG.adf):
  island at 42.04 MHz (1135/27), write buffer, no core speed-ups: WNS
  +0.020 (cpu_clk +0.020 after post-route phys_opt; the `_routed` report
  before it says -0.157 - judge by `_postroute_physopted` / STATS.WNS),
  WHS +0.036, main<->cpu_clk crossings +15.2 ns inside their 20 ns bound,
  76.4k LUTs, 93.5 BRAM. e2e040 and the driver test PASS in exactly this
  configuration (CPU clock 42.04 MHz in the TB). NOT hardware-tested.
  HARDWARE (user, 2026-10-11): build g boots the user's OS3.1 HDF; RTG works
  with the new MiSTer.card; SysInfo 19,446 Dhrystones = 1.06x A4000/040 with
  Zorro II or Zorro III RAM (the same: Zorro III is cached), but 580
  Dhrystones (1.06x A600) with Chip + Slow RAM only - the core cached neither
  Slow RAM nor the ROM, and never code from Chip RAM.
  STEP 3, FAST RAM PORT + MOTHERBOARD CACHING (build h, CPU040_FASTRAM = 1).
  (a) compat: `cache_rom_ena` / `cache_slow_ena` make $F80000-$FFFFFF and the
  512 KB Slow RAM ($C00000, main.vhd slow_ram_i) cacheable for both banks
  (nothing but the CPU writes them; code from Chip RAM stays uncached, the
  core's DMA rule); the fill channel keeps to the Zorro windows
  (`cache_zwin`). (b) the core's fill channel (AP040_FILL_CHANNEL, off until
  now) and every island entry for Zorro II/III RAM that fits one aligned long
  go to a new sdram_ctrl port (fp_*, toggle handshake, 128-bit line answer)
  instead of the 16-bit adapter: a line = two burst-4 read slots, a long write
  = ONE slot (two WRITE commands into the open row, the first without auto
  precharge; no mode-register change). Fills ride the island queue, so they
  never overtake a buffered write; misaligned Fast RAM accesses keep the
  adapter path, and cpu_wrapper switches cpu_cache_new off (the port bypasses
  it). Priority in the controller: chipset, floppy, CPU write, the 040 port
  (never while a refresh is due), CPU read. Bug found on the way: the port's
  first-slot flag had no reset, so the first write after power-up lost its
  high half (fixed: cleared during the SDRAM init).
  BENCH (28 MHz clocks, Zorro II RAM, 42.04 MHz CPU): 16 KB copy TG68K
  57,584 / build g 105,952 / port 49,556; 16 KB read TG68K 33,000 / g 75,444
  / port 33,168 - build g streamed memory at half TG68K's speed, the port
  more than doubles it. Load/mul/store loop 11,948 -> 9,168, register loop
  unchanged (15,272): in-cache code is bound by the core without its
  speed-ups. A line fill now costs ~32 bus clocks end to end (2 slots + the
  island's queue and answer crossings), was ~75.
  HARDWARE (user, 2026-10-11): build h boots; SysInfo 20,040 (Zorro III) /
  20,032 (Zorro II) Dhrystones, up from 19,446; Slow-RAM-only 2,022 after a
  boot without startup-sequence (610 before: SysInfo had landed in Chip RAM).
  The user's direction: Slow RAM stays as slow as a trapdoor board; the target
  is the 68040 with Zorro III RAM.
  CORRECTION: TC64's release (doc/release-0.1.md) gets xSysInfo 1.10x an
  A4000/040 with copyback OFF; the 47,413 / 1.44x of FINDINGS.md was not a
  release figure. Against the A4000 we are level with TC64 already.
  DHRYSTONE IN SIMULATION (`~/aexp-work/cpu060/dhry`: xSysInfo's Dhrystone,
  as AP68040-pipelined's tb/perf/dhry, loaded into Zorro II RAM with the stack
  there, DTT0 copyback like 68040.library's Fast RAM; bench/tb020.sv, 50
  runs, 28 MHz clocks): TG68K 75,320; build h 67,872 (~20,900/s - matches the
  board's 20,040); all speed-ups 33.4 MHz 50,944; all + copyback 33.4 MHz
  47,008; store path (POST_STORES, STORE_BUF, FWD, PRECISE, SB_MMU) at 42 MHz
  53,328; store path + copyback at 42 MHz 47,180 (1.44x build h). Dhrystone
  is store-bound: write-through stores drain one per SDRAM slot.
  cpu_wrapper `CPU040_OPTS` (bit per speed-up, bit 8 COPYBACK), main.vhd
  `C_CPU040_OPTS`; the compat's copyback window `cb_win` now includes the
  Zorro RAM windows (`cache_zwin`). This core's copyback is conservative: CINV
  pushes dirty lines too, and an access that bypasses the cache pushes its
  set first. TC64 shipped COPYBACK=0 ("unstable under disk load", unsolved,
  doc/backlog.md); Commodore's 68040.library maps all Fast RAM copyback, so
  a copyback build runs the whole system in copyback.
  e2e040: a copyback section (TTRs CM = 01, 4 KB of Zorro lines read, written
  dirty, read back, CPUSHA, CINVA, memory checked; code copied, CPUSHA, run).
  PASS with OPTS 311 at 42 MHz, OPTS 256 + FAST 2, and OPTS 55. Mutant: pushed
  data corrupted -> $BAC1. (Removing the CPUSHA is NOT a mutant here: CINV and
  the cache-off reads push as well.)
  BUILD i (`~/aexp-builds/Megamiga-cpu040-i`): OPTS 311 (store path +
  copyback), 42.04 MHz, WNS +0.048. BUILD j (`Megamiga-cpu040-j`): OPTS 55
  (store path, no copyback), WNS +0.018.
  HARDWARE (user, 2026-10-11): SysInfo (Zorro III) build i 25,777, build j
  25,779 - the same, 1.29x build h. A 15 MB partition copy on build i boots.
  Simulation with the MMU on and 68040.library-style tables (4K pages,
  `~/aexp-work/cpu060/dhry` loader MMU=1): copyback 45,964 vs write-through
  52,300 clocks - so copyback works through the ATC path. On the board,
  `mmuinfo` (`~/aexp-work/cpu060/mmuinfo`, ADF Megamiga_040.adf: TC/URP/SRP,
  TTRs, CACR, PTESTR + MMUSR of a Fast RAM buffer, code, stack, ROM): TC
  $8000, TTRs 0, CACR $80008000, Fast RAM/code/stack MMUSR CM = 01
  (copyback), ROM CM = 00. `cbtest` (5.12 M long loads / stores on 1 KB of
  Fast RAM): build i loads 17 / stores 32 ticks, build j 17 / 42 - copyback
  works on the board (write-through = one SDRAM slot per store, ~164 ns).
  SysInfo's Dhrystone simply gains nothing from it (no write-allocate: a
  store miss writes through). The OS's CopyBack flag (CPU, SysInfo) cannot be
  switched off on a 68040 (no CACR bit); 68040.library sets it per page.
  The user's HDF copy seemed slow (a rough, untimed impression of about
  25 KB/s); the user thinks that is not new - to measure properly later. The
  figure was taken out of the 0.6.0 release notes on 2026-10-12.
  MERGE + CPU MENU (2026-10-11, the user: "call the 040 done for now", merge
  to main with 0.5.2, a 68040 option in the CPU menu, the 68020 back). main
  (0.5.2) merged into cpu040 (history.md conflict: both entries kept). The
  profile's CPU radio is 68000 / 68020 / 68040: the BLANK LINE after the radio
  (lines 21/35/49) became " CPU: 68040" in the same OPTM group, so no line
  moved, OPTM_SIZE stays 211 and settings files stay compatible (the old
  separator byte reads as "68040 off"); C_PROF_CPU_040 = 2. Menu heap: +33
  characters, demand 3495 -> 3528 (formula of hard rule 11, reproduced
  without check_osm_menu.py, which is not on this machine; it gives the
  recorded 3495 for main), MENU_HEAP_SIZE 3520 -> 3552, release HEAP_SIZE
  -32 (combined total unchanged); help page text reworded within its lines.
  mega65.vhd: main_cpu_020 = 68020 OR 68040 (the 32-bit bus: cpucfg "11",
  Zorro III, RTG, the sdram ram_cs rule), main_cpu_040 = the 68040 bit, into
  main.vhd cpu_040_i -> cpu_wrapper cpu040_sel and into amiga_cold_boot (a
  68020 <-> 68040 change cold-boots). cpu_wrapper with CPU040 != 0 now holds
  BOTH cores: the 040 block's outputs became f_*, a TG68K instance t_*, and
  the *_p wires are multiplexed by cpu040_sel; the unselected core is held in
  reset; ram_hold only with the 040 (TG68K takes ramready unregistered).
  cpu_cache_new is on with TG68K (its CACR) and off with the 040 (Fast RAM
  port). SIM: e2e040 and the board-address driver test with SEL040 = 0
  (TG68K, the CPU040=0 program) and 1 (the 68040, OPTS 311). Build k.
  LICENCE (2026-10-11): apolkosnik confirmed to the user that AP68040 is
  GPL-2.0-or-later (he will update the terms in his repository) - the open
  question from step 1 is closed.

- **Megamiga 0.6.0 (2026-10-11): the 68040.** CORE_VERSION 0.6.0. Contents:
  the 68040 entries above (island at 42.04 MHz, Fast RAM port, store-path
  speed-ups + copyback, CPU radio 68000 / 68020 / 68040, TG68K and the
  AP68040 side by side) plus the RTG driver rename: `MiSTer.card` ->
  `Megamiga.card` (CORE/rtg/Megamiga.card.asm: board name, library name and
  version string only), monitor `Devs/Monitors/Megamiga` with tool type
  `BOARDTYPE=Megamiga`, screen modes `Megamiga:...` - CORE/rtg/rename_board.py
  rewrites MiSTer_RTG.lha's monitor icon (tool type length field) and the
  fixed-size name fields of Picasso96Settings (STHD from byte 8, BDNM, RSHD
  from byte 14), so make_adf.sh stays reproducible. Reasons: the driver is no
  longer MiSTer's (board search, ID $4D01) and a MiSTer package's MiSTer.card
  can no longer overwrite it. Manufacturer ID 2011 kept for now (registry:
  "Reserved", Commodore's "hackers" number, also UAE's; a free ID can be
  requested from Hyperion, support@hyperion-entertainment.com). scsi.device
  as lide.device's name was discussed and rejected (Kickstart 3.x and the
  3.1.4/3.2 updates have their own scsi.device); the clean way is Gayle IDE
  for the A600/A1200 profiles, a later feature. README: 68040 section,
  credits (Adam Polkosnik, Renee Cousins, Paul Honig), upgrade steps for the
  driver rename, HDToolBox tool type SCSI_DEVICE_NAME=lide.device. Settings
  file unchanged (211 bytes).
- **FREEZER CARTRIDGES: HRTmon + Action Replay III (2026-10-13, worktree
  `.claude/worktrees/cart-ar3-hrtmon`, branch `worktree-cart-ar3-hrtmon` from
  0.6.0 `d7cafdc`, Minimig submodule branch `cart`). NOT built yet.** The user
  wants both: HRTmon (built in, technically the better freezer) and the Action
  Replay Mk III (history preservation, bring your own ROM), selectable per
  profile. Decisions (user, 2026-10-13): freeze = CTRL+MEGA+HELP plus a
  "Freeze cartridge" menu line; a "Cart: None / HRTmon / Action Replay 3" radio
  in each profile block; with the AR3 the Zorro II board shrinks to 2 MB.
  - HRTmon: `CORE/hrtmon/` holds the unmodified 2.38 archive (GPL-2.0-or-later,
    source headers), `build.sh` rebuilds the cartridge image byte-identically
    (`UAE = 1`, `CARTRIDGE = 1`, vasm, NDK 3.2), README.md. The image
    (99,370 words) lives in a block RAM in `amiga_sdram.vhd`, which copies it to
    the HRTmon bank (A22..A19 = 0100, where `$A00000` lands) at every cold boot
    with MiSTer's `UploadActionReplay` configuration patch (AGA flag, chip size).
    `amiga_cold_boot.vhd` gained a CART_INIT state: the Amiga stays in reset
    until `cart_busy` drops. Minimig's `cart.v` is the cartridge.
  - AR3: `rtl/ar3.v`, a port of Jakub Bednarski's Minimig 1.x
    `ActionReplay3.v` to Minimig-AGA's clocking (clk + clk7_en; ROM loaded by
    the core instead of the CPU; registers, map and freeze sequence unchanged).
    Bank A22..A19 = 0101 (`$400000` = Slow RAM's slot in the bridge, so
    minimig.v steers `ar3_selmem` there; also for the overlay at `$000000`).
    QNICE device 0x010C (0x010B is the shared folder on `share`): window 0..63
    = ROM bytes through the Kickstart loader FIFO (tag bit 34), 0xFFFE = the
    menu's freeze, 0xFFFF = CSR of the " AR3 ROM:%s" line (manual ROM 6); the
    optional `/amiga/ar3.rom` auto-load. Counts as loaded only after byte
    $3FFFF of a stream that started at 0. cpu_wrapper: with `cart_ar3` the
    Zorro II decode is the 2 MB board only (`addr[23:21]` = 1), which keeps
    `$400000-$47FFFF` off the fast path; `fastramcfg` 2 MB.
  - AR3 = 68000 only (mega65.vhd `main_cart_req`): the ROM expects the 68000
    frame and IACK cycle, and the AP68040 would not even reach it - it caches
    the whole Zorro II window and its island sends that window straight to the
    Fast RAM port (`e_fp`, `cache_zwin`).
  - cart.v on the 68040: the AP68040 autovectors without an IACK cycle, and its
    chip bus cycles are so short that `~_cpu_as & rd` (3 clocks) can fall
    between two 7 MHz enables. New `vec_ack`: the vector read of a pending
    request (`l_int7`), caught on every clock, does at the next enable what the
    IACK path does (int7 off, request done, active + stealth on); `ovr` is also
    on while `l_int7`, so that very read already gets `$00A1000C`. A 68000 is
    unchanged (its IACK clears `l_int7` before the vector read). Limitation: a
    VBR in Zorro II/III RAM is served by the island's Fast RAM port on the
    68040, so the cartridge never sees the vector read there.
  - Freeze key: keyboard.vhd `freeze_o` = CTRL+MEGA+HELP (HELP mirrored but not
    sent; the MEGA hold counts as used), `osm_block_o` = CTRL+MEGA held. M2M
    exception 4 (`osm-hotkey`) grew `osm_block_i` (m2m_keyb, framework, four
    board tops; default '0'): the menu key does nothing while it is set.
    ciaa.v's Help-key freeze is tied off. The menu's freeze is a momentary item
    like "Reload Screen Config" (OSM_SEL_POST writes window 0xFFFE; ~4.6 ms
    press); the framework cannot close the menu from a callback.
  - Menu: 226 items (+15), demand 3809, MENU_HEAP_SIZE 3840 (headroom 31),
    release HEAP_SIZE 21504 -> 21216; HEAP 0x9602 + 25056 leaves 1790 stack
    words. Firmware 29063/32768 words, rodata 2863/4096. Settings file 226
    bytes (dev SD cards need `make_config.sh`).
  - Tests: `~/aexp-work/cart/sdram` (amiga_sdram + sdram_ctrl + SDRAM model:
    AR3 ROM loader, HRTmon copy + patch, AR3 RAM clear, busy). `~/aexp-work/
    cart/frz` (Verilator: real fx68k / TG68K netlist / AP68040 + cpu_wrapper +
    minimig_m68k_bridge + cart.v + ar3.v + RAM models; two freezes each, entry,
    resume, override off afterwards): fx68k+HRTmon, TG68K+HRTmon,
    AP68040+HRTmon, fx68k+AR3 (with the 2 MB board configured, status 0,
    overlay read of `$7C`) all PASS; the 68040 run with the original cart.v
    FAILS (INT7 never acknowledged); mutants `mut/m2..m4` (ovr without
    `l_int7`, no `vec_ack` for active / for int7) all killed. Static: iverilog
    over the whole Verilog set, ghdl analysis of every changed VHDL file and
    elaboration of `mega65_r6` (only the known av_pipeline bound noise).
  - The SDRAM TB found two init bugs (2026-10-14), both fixed, TB PASS
    (HRTmon copy 1,689,292 core clocks for 99,370 words, 428 words checked):
    `c_prime` was only set outside `M_IDLE`, so the first word never started
    and `cart_busy` stayed high forever (red: still busy after 19M clocks);
    now every clock that takes no word primes. And `cart_busy` dropped when
    the last word was ISSUED, while its write still owned the port for
    2 x `C_HOLD` clocks (red: first chip read after the init = `zzzz`); now
    `c_tail` holds it to the end of that write's `M_GAP`.
  - Synthesis: Vivado's file loader stops at 65536 lines (Synth 8-403), so the
    image is four 32K-word parts `hrtmon_0..3.hex` (`HRTMON_ROM_PREFIX`).
    R6 build b (before the init fix): BRAM 94/365, post-route WNS -0.37
    (AP68040 island paths and main_clk -> sdram_ctrl address; the latter
    routes at -0.2..-0.35 in earlier builds too).
  - Timing (build c, with the init fix): first pass WNS -0.352, re-roll best
    -0.153 after 11 of 16 attempts. All 73 failing native_clk4x paths run
    TG68K -> cpu_wrapper RAM decode -> sdram_ctrl CPU port, and none touches the
    cartridge init mux. The first AR3 decode (`sel_ar3win`, a 5-bit compare
    carving `$400000-$47FFFF` out of the 8 MB window) added three LUT inputs to
    `sel_z2ram`; now `cart_ar3` selects the 2 MB decode of `addr[23:21]`, one
    input more than upstream. Freeze TB check added: with AR3 `$200000` takes the
    fast path and `$480000` does not (red with `sel_ar3win`: 28 clocks beyond
    2 MB).
  - Field test of build c (2026-10-14, A500, Kickstart 1.3, HRTmon,
    CTRL+MEGA+HELP): nothing visible, then Guru 00000004 - the CPU took the
    $A1000C override into an EMPTY cartridge bank and ran zeros (`ori.b
    #0,d0`) until something illegal. Cause: `amiga_cold_boot` drove
    `cart_type_o` from `cart_applied`, which CART_INIT updates only at its END,
    so `amiga_sdram` latched the PREVIOUS cartridge at the init clock (None ->
    HRTmon copied nothing). Fix: `cart_q` during CART_INIT. ghdl TB
    `~/aexp-work/cart/coldboot/run.sh` (latches the type at `cart_init_o` like
    amiga_sdram; 4 changes None/HRTmon/AR3/None/HRTmon): PASS; red with the old
    line (`init with cart_type 00, want 01`). Neither existing TB could see it
    (the SDRAM TB drives type + init itself, the freeze TB preloads memory).
    Build d (decode fix only, first pass WNS -0.018) was stopped for build e.
  - Field test 2 (after a forced cold boot): HRTmon works with the 68020 (A1200
    and A500 profiles), the 68000 still crashes (Guru 00000004 after a few
    seconds), the 68040 hangs. The 68000 crash is the IMAGE: the source selects
    MC68030 for its 030/040 routines, and vasm's default absolute -> PC-relative
    optimisation then also rewrites destinations, e.g. `cmp.b #1,config_screen`
    in mon_setscreen -> `cmpi.b #1,(d16,PC)` (68020+ only), executed at every
    entry before HRTmon has its own illegal-instruction handler. The prebuilt
    HRTmon.data of the 2.38 archive has the same flaw. build.sh now passes
    `-opt-a-`: 199,540 bytes, 99,770 words (`C_HRTMON_WORDS`), same header
    layout, no PC-relative cmp/tst destinations left (the 60ff/61ff words are
    disassembler table data). Freeze TB with the REAL image (`-DREALHRT
    -DTRACE=..`, `HRTDIR=`): old image on fx68k -> vector $10 read with no
    handler installed (red); new image: 68000, 68020 and 68040 all install
    their vector, probe and settle in the same main loop ($A18Dxx/$A215xx).
    The 68040 also reached that loop with the OLD image, so its hang on the
    board is environmental (VBR in Fast RAM? caches?), still open.
    Builds d/e stopped with the user's OK; build f has all three fixes.
  - Build f (image + cold-boot + decode fix): first pass OK, WNS +0.017,
    WHS +0.050, BRAM 94/365 - the decode fix took the -0.35 away.
  - 68040 hang after Workbench (field test 3: KS 3.1, OS 3.1, Z3 RAM; the
    freeze works at the Kickstart screen, after Workbench the machine hangs).
    The level 7 vector read never reached cart.v: with the data cache on, the
    line with $78/$7C (the level 6 vector, read by every CIA-B interrupt) is
    resident and the read is answered from the cache - chip RAM is D-cacheable
    on this core (snooped) - and with the VBR moved into Fast RAM it also goes
    to the Fast RAM port. Nothing then ends the request (no IACK cycle on the
    68040), IPL stays at 7, every lower interrupt is shut out: the hang.
    Fix, active only while IPL = 7 and only for the exact long VBR + $7C:
    `ap040_pipe_tg68k_compat.v` adds it to `c_nocache` (`nmi_vec_rd`) and keeps
    it off the data fast path (`dfp_nmi`, the compare registered with the fast
    path's address latch); `ap040_island.v` keeps it off the Fast RAM port
    (`e_nmi`). cpu_wrapper's existing `sel_nmi_vector` then puts it on the chip
    bus, where cart.v overrides it. Exact address on purpose: an uncached read
    must never bypass a dirty copyback line it does not override.
    Freeze TB (real image, AP68040, Fast RAM port model added): Kickstart state,
    caches on (A), VBR in Fast RAM (B), B with the vector line kept resident
    (C), VBR 0 with the line resident (D): all enter HRTmon's main loop. Red:
    B, C, D take the OS NMI handler without the fix; C also with only
    `c_nocache` (the data fast path answers it) and without the island part.
  - Field test of build f (2026-10-15): HRTmon freezes on the A500 with the
    68000 (the image fix confirmed on the board).
  - 68020 confirmed on the board as well (user, 2026-10-15).
  - Build g (68040 fix, 2026-10-15): TIMING-FAILED, WNS -0.547 ns after four
    placement passes (-0.743/-0.509/-0.878/-0.270), not re-rolled (> 0.5 ns);
    the identical sources on the new Fedora build host gave the identical
    result. The failing paths do not contain the fix's cells: all inside the
    AP68040 (ALU flags -> branch condition -> stall/redirect -> fetch PC
    adder, 43 levels, 74 % route) - the added logic moved the placement.
    DECISION (user): no freezer with the 68040. The fix is removed from the
    RTL and parked as `doc/developers/freezer-68040.patch`, the analysis,
    TB table and resume plan in `doc/developers/freezer-68040.md`;
    `main_cart_req` plugs in no cartridge with a 68040 profile (HRTmon now
    like the AR3), README says 68000/68020. Build h = that state (Fedora),
    WNS +0.020 / WHS +0.036.
  - Rebased onto main = 0.6.1 (2026-10-15), to become 0.6.2: the Minimig
    `cart` commit sits on 39b2d9c (ext_shr); the menu was merged entry by
    entry (main's "Mount SDCard" + line + status line, the cart's AR3 ROM
    line, cart radios and Freeze: 229 items), the cart's OPTM groups moved to
    52..56 (main took 51 for OPTM_G_SHARE), every C_MENU_* recomputed from the
    merged menu (profile block stride 18, base 22), MENU_HEAP_SIZE 3872
    (demand 3867), release HEAP_SIZE 14656 (combined total 18528 unchanged);
    AR3 stays QNICE device 0x010C next to the shared folder's 0x010B.
    Firmware: Shell ROM 31331/32768 words, code banks 3/8. CORE_VERSION
    0.6.2 (the menu grew in the middle: own settings file). Build i (Fedora).
  - Build i (Fedora, WNS +0.014 / WHS +0.036, BRAM 116/365) loaded
    2026-10-15. Field: with an RTG screen up, a freeze looks like a hang on
    HDMI (ascal keeps showing the framebuffer while the driver has RTG on;
    HRTmon only programs the chipset), but HRTmon runs - `x` + Return
    resumes; the VGA output shows HRTmon meanwhile (user-confirmed).
    Accepted as authentic (user): README note, no auto-switch.
  - AR3 confirmed on the board with a real AR3 ROM (A500 profile, 68000,
    build i, user 2026-10-15).
  - HRTmon on the 68000 and the 68020 confirmed on build i (user,
    2026-10-15).
  - 68040 profile with "Cart: HRTmon" runs normally (no cartridge plugged
    in), build i (user, 2026-10-15).
  - Open: the 0.6.1 features after the merge (field), the AR3
    breakpoint/trainer paths (not simulated).

- **Megamiga 0.6.1-dev, SHARED FOLDER (branch `share` from main, 2026-10-12;
  Minimig `share` 39b2d9c).** The user: mount `/amiga` as a removable AmigaOS
  volume without a reboot; steps 1-3 (read-only first) for a 0.6.1 release
  without Gayle. Design: MiSTer's shared-folder protocol (MiSTerFileSystem in
  the Minimig repo `extra/`, host side Main_MiSTer
  `support/minimig/minimig_share.cpp`): request flag `$DD4000` ((n+77)<<8 | n,
  then `$DD4002` = 0xA55A until answered), request/response from `$DD4004`
  (MiSTer's `miminig_fs_messages.h` layouts), data `$DD5000` (4 KB). HDL:
  `share_buf.vhd` (4K x 16 dual-clock byte-enable BRAM, CPU port = ext_* of
  cpu_wrapper with the new `ext_shr`, DTACK 2 clocks after the strobe; QNICE
  device 0x010B falling edge, window 1 word 0 = gray-coded Amiga reset
  counter); cpu_wrapper's `sel_shr` replaces the chip-bus always-ack of the
  range. Firmware `SHARE_*`/`SHR_*` (2.3K words, ROM 31280/32768; 966 words of
  variables, release HEAP_SIZE 21504 -> 20512, stack margin 300): own device
  handle SHARE_DEV, root = `/amiga` via FAT32$CD; `SHR_TAKE_BUF` flushes and
  releases HANDLE_DEV's and CONFIG_DEVH's sector-buffer ownership before a
  request, `SHR_GIVE_BUF` its own after it; locks = (type, cluster, index) in
  64 slots, key = generation:slot (stale generation -> 218); 8 open files;
  directory cursor (ExNext continues, O(n)); parent via the `..` entry; READ
  seeks per sector and copies from IO$SD_DATA (76k instructions per 4 KB, the
  byte API took 487k); everything that writes -> 214. Media: card-detect
  edges of the active slot (CSR bits 9/10), slot switch and SD_CHANGED rising
  take the volume down, a remount follows after ~1 s (IO$CYC_MID); edges, not
  levels, so a slot without card-detect still mounts at start. QNICE gotcha
  found: RET is a MOVE and rewrites Z/N - results across RET only in C.
  Amiga side `CORE/share/MegamigaFS.c` (vbcc, BCPL module like a314fs, linked
  with `-Rstd` so 1.3's LoadSeg reads it - MiSTer's binary has RELOC32SHORT):
  volume `SDCard:` only while the firmware status (`$DD4FF8` 'MS', bit 15 up,
  generation) says so, checked per packet and every second (timer.device),
  retired volumes kept while locked, IECLASS_DISKINSERTED/REMOVED, fixes
  (failed READ replies, FH_FROM_LOCK, IS_FILESYSTEM, CURRENT_VOLUME); DOSDriver
  `SD`, 1.3 MountList, `dummy.device` (= MiSTer's), `Megamiga_Share.adf`.
  Tests: `~/aexp-work/share/fw` (real SHARE section in the QNICE emulator on
  generated FAT32 images, spc 1/8/64, 520 records incl. 64 KB crossings,
  leap/2104 dates, events reset/card out/in/SD_CHANGED/slot, buffer ownership
  checked after every request; `mut.py` 49 mutants, 46 killed, 3 equivalent:
  seek_neg/seek_past (the library refuses), dotdot_name). `~/aexp-work/share/
  e2e` (tb020 0.6.0 + ghdl-synth share_buf + firmware model: TG68K PASS) and
  `e2e68k` (fx68k Verilator: PASS; `mut.sh` 7 HDL mutants, 6 killed,
  sb_rstcnt equivalent); the e2e TB also PASSES with the AP68040 (run_s1).
  R6 build share-a (commit 90dbd3c): WNS +0.006, WHS +0.012, BRAM 95.5/365,
  LUTs 64%; saved with `patch_firmware.sh save` in
  `~/aexp-builds/Megamiga-share-a`. Hardware test pending. Also on this branch: patch_firmware.* from `gayle`
  with the rodata RAM in block RAM; CORE_VERSION 0.6.1 (settings file
  megamiga-0.6.1.cfg, layout unchanged).
- **Megamiga 0.6.1-dev, step 2: code banks, FAT32 write layer, SDCard:
  read/write, profile files in the settings file (branch `share`,
  2026-10-13).** (a) `a638be1`: menu toggle "SDCard: inserted"
  (`C_MENU_SHARE` 8, line after the profile radio, default on), card-detect
  debounce (~100 ms), event counters at `$DD4FEC`, MegamigaFS edits the DOS
  list under LockDosList, `C:ShareInfo`. (b) `966c0c1` = M2M exception 16
  `code-banks` (see AGENTS): 8 x 4K banks behind the window `0x9000`, RAM
  from `0xA000`, `FAR_CALL` stubs, `make_banks.py`; ghdl TB `~/aexp-work/banks`
  (3 HDL mutants killed). R6 build share-d: WNS +0.022, WHS +0.036, BRAM
  111.5/365, saved in `~/aexp-builds/Megamiga-share-d`. (c) FAT32 write layer
  in the QNICE submodule (`6162e43`): `fat32_write.asm` (bank 1: sessions,
  both FATs + FSInfo, alloc/free, directory walker with entry addresses,
  scan by name/LFN/alias, create (LFN + numeric tail), delete, set entry,
  mkdir, rename) and `fat32_wfile.asm` (bank 2: write handle, put, advance,
  sync, set size); errors EE24..EE29. Tests
  `M2M/QNICE/test_programs/fat32_write` (phases A-E, spc 1/8/64; `mutants.py`
  27 mutants: 25 killed in the last full run, the other two had stale
  patterns after the bank split and were refreshed). (d) `a2e829e`: SDCard:
  read/write, protocol 2 (FINDOUTPUT/FINDUPDATE, WRITE, SETSIZE, DELETE,
  RENAME, CREATEDIR, SETPROTECT, SETCOMMENT (accepted, ignored), SETDATE;
  time from the handler's DateStamp at `$DD4FE0`; HARDWARE-CONFIRMED by the
  user 2026-10-13 with `mega65_r6_rw1.bit`); share fw harness 1216
  records + fsck/mtools image check PASS at spc 1/8/64. (e) M2M exception
  17 `cfg-strings` (see AGENTS): `key=value` text behind the menu bytes of
  the settings file; `ROSM_SAVE` resizes it (entry date kept: W_SYNC leaves
  the date alone when PB_DATE = 0); FAT32$FILE_OPEN now records the entry
  address (`FDH_EA_*`, FDH 15 words). A manual Kickstart/HDF load makes the
  selected profile remember the file by path (`B2_PROF_REMEMBER`: the path is
  rebuilt from the entry address and `..` walks, at most 127 characters, or
  the key is dropped); `PROFILE_APPLY` loads the remembered file first
  (`B2_PROF_SAVED`, name in the menu line cut to 20 characters) and falls back
  to `aNNN.rom`/`aNNN.hdf`/`aNNN-1.hdf`. HDF link files keep working (the link
  file is what is remembered). Variables +705 words: release HEAP_SIZE 15008
  (combined 18592, stack margin 287). ROM 29529/32768, banks 3932/3621/1276.
  TB `~/aexp-work/cfgstr` (cfgstr.asm + the bank code in the emulator, spc
  1/8/64, 168 records + final content, date and fsck; `mut.py` 14 mutants, 13
  killed, `no_dotdot_check` equivalent: `..` is always slot 1). Firmware
  patched onto share-d: `mega65_r6_cfg1.bit`. Hardware test pending.
  (f) The user (2026-10-13): no fallback paths, everything explicit,
  default nothing loaded; `kick.rom` the one exception (optional now, the
  Kickstart of a profile without a choice; none at all, or a chosen one that
  fails = the Amiga held in reset through the Kickstart CSR at LOADING, black
  screen). `globals.vhd`: kick.rom `C_CRTROMTYPE_OPTIONAL`; boot check via
  `CRTROM_AUT_LDF` (the auto-load sets no CSR). SPACE on a mounted HDF line
  also makes the profile forget it (`B2_PROF_FORGET`). FILTER_FILES filters
  HDF1 like HDF0 (it showed every file). The HDF browser lists the 0x7F
  partitions with number and size ("Partition 3: 1024 MB", GB from 10000 MB)
  through the new M2M `BROWSE_EXTRA` hook (part of exception 17), mounted with
  `HDF_VPART` through the link-file path (`HDF_PART_GET` split out of
  `HDF_LINK`), remembered as `partition:N`. Variables +45 words: HEAP_SIZE
  14976 (stack margin 274). cfgstr TB 176 records incl. browser listings
  (order, flags, PREV links, root without `<..>`, a non-HDF group); mutants
  22/23 (+9 new, all killed after a 64 GB partition was added for the
  16-bit overflow of the MB count). Build share-e (`~/aexp-builds/Megamiga-share-e`): R6 WNS +0.008, WHS +0.046, fully routed; NOT hardware-tested.

- **Megamiga 0.6.1-dev, FAST HARD DISKS (branch `fastdisk` from `share`,
  2026-10-14; `1724499`).** The user: HDFs run at 100-250 KB/s, a real Amiga
  hard disk does 1-10 MB/s; do all three steps (sector engine in hardware, SPI
  at 25 MHz, 4-bit SD bus). Cause of the old speed: every sector went through
  the firmware ATA server (one time slice per QNICE main-loop pass, two passes
  per sector, a byte-wise copy) behind QNICE's SPI controller at 12.5 MHz with
  one block per command. (a) M2M exception 18 `sd-host` (see AGENTS):
  `M2M/vhdl/QNICE/sdhost.vhd` replaces `sdcard.vhd` with the same six QNICE
  registers (plus register 6: native / slow / ready / retry count). It tries
  the native SD bus first (CMD0 with DAT3 high, CMD8, ACMD41, CMD2, CMD3,
  CMD7, ACMD6 = 4 bits, CMD16 for SDSC, then a test read of block 0 with the
  CRC16 of all four lines checked), 400 kHz during the identification, 25 MHz
  after it; if the card does not answer in SD mode - a card that was used in
  SPI mode since its power-up (the MEGA65 boot ROM, the previous core) STAYS in
  SPI mode until it loses power - or the test read fails, it initialises SPI
  (CMD0 with CS low, CMD8, ACMD41, CMD58, CMD59 = CRC on, CMD16) and runs it at
  25 MHz. A failed transfer re-initialises one step down (native -> SPI 25
  MHz -> SPI 12.5 MHz) and resumes at the first unfinished block; the third
  failure is an error. Timing: outputs change with the falling SD clock edge,
  inputs are sampled just before the next falling edge (a full SD clock after
  the card launched them); the clock stops high for flow control. Engine
  port: multi-block CMD18/CMD25 streams with a per-block limit (flow
  control), QNICE commands end an engine transfer at the next block boundary.
  The lines CMD and DAT3..0 now have output, output enable and input through
  sdmux, qnice, qnice_wrapper and framework; the R4/R5/R6 tops make the pins
  bidirectional (names unchanged: mosi = CMD, miso = DAT0, reset = DAT3) and
  CORE.xdc adds pull-ups; the engine port is packed into two vectors
  (`sdhost_pkg` in sdhost.vhd) top -> core. common.xdc: the generated clock of
  sdcard.vhd's divider is commented out. R3's top was not adapted (R3 does
  not build since 0.2.0). (b) `CORE/vhdl/ide_engine.vhd` (QNICE clock) serves
  READ SECTORS / WRITE SECTORS (0x20/0x21/0x30/0x31, LBA28) of a unit whose
  engine mode is not 0: it takes the command from the task-file snapshot,
  checks LBA mode and the size, translates the sectors with the extent map
  (FAT32$FILE_MAP format: cluster runs; block = base + (cluster << shift) +
  sector, base = DEV_CLUSTER - (2 << shift)) or the partition start, and
  streams through the engine port into rings of 8 sectors per direction in
  block RAM (`tdp_ram`, one RAMB36 each, + the 4K-word map RAM). Every other
  command, and every one it cannot serve, is forwarded: the firmware sees the
  command event only then (event bit 0 of 0x100 is now the engine's toggle).
  ide_board keeps DRQ across sector boundaries while the ring has data (read)
  or room (write); a write ends (BSY -> READY/ERR) when the last sector is on
  the card; errors end with ERR + UNC. Handshake: single-bit toggles (acc, rdy,
  fin, free) through 2-FF synchronisers, the direction/error bits set 4 clocks
  before their toggle. Registers 0x120-0x12D (unit 0/1: mode, sectors, base,
  shift), 0x130-0x133 (status, statistics), window 1 = the maps. (c)
  Firmware: `HDF_ENG_SETUP` after a successful mount (partition: base = its
  first block; file: FAT32$FILE_MAP straight into window 1, up to 511
  extents, more = the firmware path as before), engine off in `HDF_DROP` and
  `IDE_INIT`. ROM 30029/32768, no new variables. Tests: `~/aexp-work/sdhost`
  (ghdl; `sdcard_model.vhd` = native 4-bit + SPI card with CRC checks,
  multi-block, CMD12, busy and fault injection; `tb_sdhost.vhd` scenarios 0
  native SDHC, 1 card stuck in SPI, 2 SDSC V2, 3 SDSC V1, 4 DAT1..3 not
  connected, 5 no card: QNICE reads/writes, engine reads/writes with slow
  consumers/producers and QNICE preemption, read CRC error -> SPI -> slow SPI,
  rejected write, reset recovery: ALL PASS) and `~/aexp-work/ideng` (ghdl
  end to end: lide-style ATA master -> ide_board + ide_engine -> sdhost ->
  card model, firmware stand-in for forwarded commands (IDENTIFY, out of
  range) and random firmware SD reads; file map with 5 extents and a
  partition; reads/writes of 1..256 sectors with fast and slow CPU, Amiga
  reset and SRST in the middle, a failing card: PASS in native (~11 MB/s at
  the card with a fast bus master) and SPI (~2.5 MB/s)); the 0.6.0
  firmware-path board TB still passes. `~/aexp-work/ideng/mut.py`: 16 mutants
  over sdhost/ide_engine/ide_board, 16 killed (the first round left 4: the
  controller TB never filled the ring, the model corrupted only the CRC bytes
  of a bad read, and two skip counts were equivalent - TB, model and mutants
  were strengthened). Found in review after the first build: the inputs went
  through two registers, which put the sample point on the RISING SD clock
  edge (20 ns after the card's launch at 25 MHz, minus its up to 14 ns output
  delay); now one register samples just before the next falling edge (`2098dcf`;
  the card model's output delay is 14 ns now). Register 6 bit 0 = SPI only.
  Firmware switches (`#define` at START_FIRMWARE, for patch_firmware.sh
  variants): `SD_SPI_ONLY` (0) and `IDE_ENGINE` (1). Builds: fastdisk-a (`1724499`, before the
  sampling fix) R6 WNS +0.021 / WHS +0.036, fully routed, LUTs 87.6k (65.5%),
  BRAM 115.5 tiles; NOT for hardware (the sampling bug). fastdisk-b (`2098dcf`)
  missed hold by 0.054 ns on the known framework HyperRAM input
  (`hr_d_io[4]` -> IDDR, clock hr_rwds); re-roll 2/15 (place ExtraTimingOpt,
  route Explore) WNS +0.005 / WHS +0.036, LUTs 87.8k. Saved to
  `~/aexp-builds/Megamiga-fastdisk-b` with the RE-ROLLED checkpoint copied over
  `routed.dcp` by hand (`patch_firmware.sh save` takes the postroute one).
  Patched variants of b: `mega65_r6_fastdisk_b_fw.bit` (`ab77986` firmware,
  default), `_spionly.bit` (SD_SPI_ONLY 1), `_noengine.bit` (IDE_ENGINE 0).
  Awaiting hardware tests.
  SD STATUS LINE (user, the next morning: no menu choice of the SD mode - the
  setting lives on the card it would configure - but show the mode): the main
  menu ends `About & Help`, `Close Menu`, Line, and a TEXT line (group 0, the
  cursor skips it) that `SD_STATUS_STEP` (m2m-rom.asm, called from
  HANDLE_CORE_IO next to HWF_STATUS_STEP, same gates and throttle) fills via
  OPTM_LIVE_TEXT from sdhost register 6: `SD: 4-bit 25 MHz` / `SPI 25 MHz` /
  `SPI 12.5 MHz` / `no card`. The line is dimmed with `M2M$SA_DARK` (0x4F); the
  OSM renderer halves foreground AND background with that bit, so it shows as a
  darker bar - real grey on the normal blue would need `vga_osm.vhd`. The
  attributes are rewritten every poll (a full OPTM_SHOW repaints the line in
  the standard colours). OPTM_SIZE 213 -> 214 (`C_MENU_SD_STATUS` 213),
  MENU_HEAP_SIZE 3616 (demand 3586), release HEAP_SIZE 14944. So that the
  existing 0.6.1-dev settings file (menu bytes + profile text) survives the
  longer menu, HELP_MENU_INIT accepts a file from a menu that grew at its END
  (M2M exception 17): before, the first text character landed in the new menu
  byte and stopped the core with ERR_FATAL_ROSMC. Emulator TB
  `~/aexp-work/cfgold` (the real loader block, 9 file layouts incl. bank
  seams, 0xFF default, invalid byte, empty file): PASS; the HEAD loader fails
  5 of them (FATAL 0E03 / no settings). Firmware 30347/32768 words.
  Build fastdisk-c (`ca48dcd`): R6 WNS +0.061 / WHS +0.013 first pass, fully
  routed, LUTs 87.7k, BRAM 115.5; saved to `~/aexp-builds/Megamiga-fastdisk-c`
  (`mega65_r6_fastdisk_c.bit`). Awaiting hardware tests.
  HARDWARE (fastdisk-c, 2026-10-14): 4-bit only after re-inserting the card
  (the MEGA65 boot firmware leaves the card it read in SPI mode); with cards in
  both slots, F1 (the tray card) gave 4-bit at once - the boot firmware reads
  only the back card. A firmware rule "both slots -> the tray card" (`068ea69`)
  was then replaced by the user's request to use BOTH CARDS AT ONCE:
  BOTH SD SLOTS (M2M exception 18 extended; user decisions: paths carry the
  card, `SD0:` = tray / `SD1:` = back, a path without it is invalid; no F1/F3,
  "<..>" above a card's root lists the cards; the settings file back card
  first, then the tray; `SDCard:` = the back card only - "the purpose of the
  shared folder is easy file sharing with other computers"; partitions in the
  card list). HDL: `M2M/vhdl/QNICE/sdslots.vhd` (new, replaces `sdmux.vhd`,
  which is deleted and replaced in all four .xpr): two sdhost, register 0xFF27
  selects the QNICE slot, C2Q bit 75 the engine's (latched while either
  controller is busy), a controller is held in reset while its slot has had no
  card for G_ABSENT clocks; ide_board mode registers bit 2 = the unit's slot,
  ide_engine `sd_slot_o` (the new command's unit in E_DECIDE). Firmware:
  `M2M/rom/sdcards.asm` (SDC$INIT/POLL/MOUNT/DEV/SLOT/SEL/SELDEV/PRESENT/GEN/
  HOMEDEV; one device handle per slot whose functions select the slot first,
  so the FAT32 library is unchanged and tracks each controller's buffer owner
  correctly; card generations bumped on a ~100 ms debounced card-detect edge),
  browser (`FB_PREPARE`, `FB_CHANGED`, `FB_ENTER`, `FB_TOCARDS`, `FB_ATROOT`,
  `DIRBROWSE_CARDS`, the synthetic "<..>" at a root, three initial cursor
  stack words), settings file on both cards (`SDC_HOME`/`SDC_HGEN`,
  ROSM_INTEGRITY by generation), auto-load ROMs from the settings card.
  Megamiga: per-drive card + generation for ADF (`ADF_SD_GEN`) and HDF
  (`HDF_DSLOT`/`HDF_DGEN`, the global `HDF_SD_SLOT` rule "both drives on one
  slot" is gone), `SDC$SELDEV` before every direct IO$SD_DATA use (FAST_LOAD,
  FLUSH_ADF_STEP, IDE_SD_TAKE), share on the back card only (SHARE_DEV = a copy
  of SDC_DEV1, follows SDC_GEN[1]; SHR_COREUSE counts core files on the back
  card only), partitions per card in the card list (`SDx: Partition n: size`,
  id = slot << 8 | n), profile paths `SDx:/...` / `SDx:partition:N`
  (`_PR_CARD`, `_PR_PUTCARD`, `_PR_PATHOF` on the file's own device), the
  status line shows both cards (`SD0:4-bit  SD1:SPI 25 `). QNICE emulator:
  two slots (`-a`, `-a1`, register 7). Firmware 31221/32768 words, combined
  heap total 18528 (stack margin 287). TBs: `~/aexp-work/sdslots` (HDL: two
  card models, the back one in SPI mode; QNICE on both, engine on one while
  QNICE uses the other, removal/re-insertion), `~/aexp-work/sdcards`
  (emulator: the real sdcards.asm, browser helpers and dirbrowse.asm on two
  images; 19 mutants, all killed). The HDL TB found that sdhost raises
  e_busy only some clocks after the start pulse, so the engine's slot is
  latched from the start pulse to the done pulse (9/9 mutants killed, incl. a
  start to both controllers, caught by an engine write on the back card that
  must not touch the tray card); `~/aexp-work/ideng/run2.sh` (tb_ide2: the IDE
  engine through sdslots, card in the back slot, native + SPI): PASS.
  Firmware TBs updated for two cards (two images, `-a1`): cfgstr (227
  records, 37/37 mutants), cfgold (16 cases, 7/7), fw-prof2 (rewritten for the
  explicit profiles: 7 steps across both cards, 14/15 - the survivor removes a
  redundant SDC$SELDEV in FAST_LOAD), share/fw (PASS, all 12 new mutants
  killed), fw-ide3 (new, from fw-ide2-old - fw-ide2 targets 0.7/Gayle: master
  on card 0, slave on card 1, per-card drops, partitions by slot, the engine
  slot bit; all new mutants killed), fw-adf (drives on both cards, per-card
  teardown; 7/9 - the two SDC$SELDEV removals are redundant with this FAT32
  library, kept as a guard). The cfgstr update found that `_PR_PUTCARD`'s
  terminator emptied a path of exactly the maximum length (fixed).
  Build fastdisk-d (`3729c9a`): first pass WNS -0.376 (the 68040 island's
  eaf -> bcu mem_addr path, 46 logic levels, 74 % route; nothing of the SD
  change is on it), too much for the automatic re-roll; re-rolled by hand: the
  routing-only attempts stayed at -0.38..-0.55, so the re-roll was restarted
  placements first (WHS argument -0.001 selects that order): 3/15
  ExtraNetDelay_high + route Explore PASS WNS +0.003 / WHS +0.011. LUTs 89.4k
  (66.8 %, +1.7k for the second SD controller), BRAM 115.5. Saved to
  `~/aexp-builds/Megamiga-fastdisk-d` with the re-rolled checkpoint as
  `routed.dcp`; `mega65_r6_fastdisk_d.bit`. Hardware (2026-10-15, build d
  by JTAG): both cards show up, the card list lists the partitions.
  Menu tweaks (`5cc4e5a`, build fastdisk-e): " Mount SDCard" (was "SDCard:
  inserted"), default off and off at every start - PREP_START clears the
  setting whatever the settings file says, and SHARE_STEP ignores it until
  then (`SHR_INSW` = `SHR_INSW_BOOT`; share/fw checks that nothing mounts
  before PREP_START, the mutant without the guard fails). Turning it on still
  makes the menu save the file (ROSM_CHANGES); the next start clears it again.
  The SD status line is painted straight into the bottom row of the main menu
  frame by SD_STATUS_STEP (every poll, ~95 Hz) instead of being the last menu
  item, which floated under "Close Menu" whenever the main menu was shorter
  than its frame; item 213 is an empty text line now (OPTM_SIZE unchanged).
  Cards without FAT32: a card whose four MBR entries are all 0x7F partitions
  (the internal card next to an external card with the core's files). Before,
  the partitions of a card were only listed and opened after FAT32 mounted
  on its partition 1. Now SDC$MOUNT tries once per card generation and keeps
  the result (`SDC_MERR`): FAT32$MOUNT resets the card (DEV_RESET), so
  retrying it while a partition of the card is the Amiga's hard disk would
  reset the card under the engine. A failed mount leaves word 0 = 0 (not
  mounted, as before), the block functions in place and no buffer owner;
  `SDC$BLKDEV` returns such a handle for block access (only "no card" is an
  error). BROWSE_EXTRA, HDF_PREP (HDF_VPART) and B2_PROF_SAVED (partition
  paths; file paths still need SDC$MOUNT) use it; FB_PREPARE shows the list
  of the cards for a card that does not mount instead of the mount-error
  retry loop. Trade-off: a card whose mount failed for a transient reason is
  tried again only after it is re-inserted. TBs: sdcards `RAW=1` (tray image
  `genraw.py`: four 0x7F partitions, no FAT32: mount error cached, block
  reads of the MBR and of partition 2, card list, FB_PREPARE/FB_ENTER, new
  generation remounts, no card; 5/5 mutants killed), fw-prof2 `RAW=1`
  (`SD0:partition:2` loads, a file path on that card does not; 1/2 - the
  survivor drops the FAT32 check before a file open, which fails on the
  unmounted handle anyway), all other firmware TBs PASS unchanged.
  Build fastdisk-e (`5cc4e5a`): first pass WNS +0.038 / WHS +0.036 (the
  router reported congestion but closed), no re-roll. LUTs 89.3k (66.7 %),
  BRAM 115.5. Saved to `~/aexp-builds/Megamiga-fastdisk-e`. The firmware of
  `29db7a2` was patched in (`patch_firmware.sh`, 16 + 16 block RAMs verified
  and patched): `mega65_r6_fastdisk_e2.bit`. The tree's images were already
  newer than the synthesis when `save` ran, so the reference images in the
  saved folder were rebuilt from `5cc4e5a`'s sources (the patch verifies them
  against the checkpoint). Awaiting hardware tests.
  Hardware (2026-10-15, fastdisk-e2): the user installed AmigaOS 3.2 from
  ADF images on SDCard: onto a hard disk with the 68040 + AGA + Z3 RAM: "It
  all seems to work fine". One screen corruption during that install (chip RAM
  overwritten after DAControl CHANGE WRITEPROTECTED=NO on GlowIcons3.2) was not
  reproduced; the share firmware bench got an `ADF=1` mode (trackfile.device's
  seek/read/write pattern on a 901120-byte file, 1505 records, PASS) and the
  $DD4000 buffers are outside every AP68040 cache window.
  0.6.1 release preparation (docs, 2026-10-15): README rewritten for the
  explicit profiles (no automatic aNNN.rom/.hdf names, kick.rom optional, a
  missing Kickstart = Amiga stopped), the Kickstart ROM section, the hard disk
  steps (profile keeps the disk, SPACE forgets it), the sector engine (files up
  to 511 extents and partitions; more fragmented files through the firmware),
  partition prep with fatresize/sfdisk, the DAControl syntax verified on
  hardware (`DAControl DEVICE=DA0: CHANGE WRITEPROTECTED=NO`), features/intro.
  Settings file from 0.6.0: NOT compatible - "Mount SDCard" and a line were
  inserted at items 8/9 (OPTM_SIZE 211 -> 214), so a renamed 0.6.0 file loads
  through `_HLP_CA_OLD` (shorter file) with every item from 8 on shifted by
  two; the release notes say to start with the new file. Package README.txt
  and notes061.md in `~/aexp-builds/release/`.

- **MEGAMIGA 0.6.1 RELEASED (2026-10-15, tag `V0.6.1` = `6c0ce23` on main,
  GitHub release asset `Megamiga-0.6.1-R6.zip`, R6 only).** Fast hard disks
  (sd-host + ide_engine), both SD slots, shared folder SDCard: read/write,
  explicit profiles, partitions in the browser, cards without FAT32. The user
  on fastdisk-e2 (68040, AGA, Z3 RAM, AmigaOS 3.2 installed from SDCard:): "It
  all seems to work fine!". Release build on the Fedora host (rel061): route
  WNS -0.378 (68040 RDindex_A -> sdram_ctrl sd_ba, 17 levels), post-route
  phys_opt +0.038 / WHS +0.036, no re-roll - the same placement as build e
  (firmware is BRAM contents only), and the bitstream body is byte-identical
  to the hardware-tested `mega65_r6_fastdisk_e2.bit`. Before the push the
  fastdisk history was rebased onto main (its five early rebrand commits with
  the first logo images dropped; main already had the clean rebrand), old tip
  kept locally as `fastdisk-backup`. Submodules pushed: QNICE
  `fat32-fastseek` 75873a2, Minimig branch `share` 39b2d9c. A 0.6.0 settings
  file must not be renamed (items 8/9 inserted). Follow-up: a multicycle or
  register stage for the 68040 -> sdram_ctrl address path, which every build
  closes only by a few tens of ps.

- **Hard disk speed, 0.6.1 (user, 2026-10-15, SysInfo):** ~4.8 MB/s with the
  card on the native 4-bit bus, ~2.8 MB/s with SPI at 25 MHz (was 0.1-0.25
  MB/s through the firmware ATA server). SPI 25 MHz carries 3.125 MB/s raw, so
  2.8 is ~90 % of the wire; 4-bit carries 12.5 MB/s raw, so at 4.8 the limit
  is no longer the card but the Amiga side: lide.device moves every word by
  CPU through the Zorro II IDE data port (Amiga bus cycles). More would need
  a wider/faster host path (e.g. long-word reads of the data port, a Zorro III
  or local-bus window for the 68020/68040, or DMA into Fast RAM).

- **MEGAMIGA 0.6.2 RELEASED (2026-10-15, tag `V0.6.2` = `6cfe46b` on main,
  GitHub release asset `Megamiga-0.6.2-R6.zip`, R6 only).** Freezer
  cartridges: HRTmon built in (68000 + 68020), the Action Replay III with the
  user's ROM (68000), no cartridge with the 68040 (parked:
  `doc/developers/freezer-68040.md`). All field-confirmed on build i (cart
  rebased onto 0.6.1): HRTmon 000/020, AR3 with a real ROM, 68040 with HRTmon
  chosen runs normally, the 0.6.1 features after the merge, HRTmon on VGA
  while an RTG screen holds HDMI. Release build on the Fedora host (rel062):
  WNS +0.014 / WHS +0.036, bitstream body byte-identical to build i (only
  docs changed in between). Submodules: Minimig branch `cart` ec7b7f0 pushed,
  QNICE unchanged (75873a2). Settings file 229 bytes; a 0.6.1 file must not
  be renamed (items inserted mid-menu). Package README.txt and notes062.md in
  `~/aexp-builds/release/`.
- **Megamiga 0.7.0-dev, GAYLE IDE (branch `gayle`, Minimig branch `gayle`,
  2026-10-12).** The HDF drives can sit on the A600/A1200 Gayle instead of the
  RIPPLE board, per profile: "Gayle IDE controller" toggle on lines 25 / 39 /
  53 (the blank line after the chipset radio, again no renumbering, OPTM_SIZE
  211, `C_PROF_GAYLE` 6, groups `OPTM_G_P1..3GAYLE` 51..53), default ON for
  A600 and A1200, OFF for A500 (Kickstart 1.3/2.04 have no scsi.device). Old
  0.6 settings files have 0 in those bytes = Gayle off everywhere.
  Design: the SAME drive backend (ide_board.vhd + the firmware ATA server),
  only a second register decode in front of it - not Minimig's gayle.v/ide.v,
  whose HPS protocol the firmware does not speak.
  - cpu_wrapper.v: `gayle_ena` input; at reset `gayle_on <= ide_ena &
    gayle_ena`, `ac_ide <= ide_ena & ~gayle_ena` (the board is either
    autoconfig'd or the Gayle); `sel_gayle` = $DA0000-$DAFFFF and
    $DE1000-$DE1FFF -> ext_sel (and the chipreq/ext_done exclusion), so Gayle
    cycles never touch the chip bus (Minimig's own gayle stays disabled,
    hdc_ena = 0). Without a mounted disk (board_ena 0) there is no Gayle at
    all, as there was no RIPPLE board.
  - ide_board.vhd: `gayle_i` (static), `addr_i` widened to 18:1 (bit 18 tells
    $DE from $DA), `irq_o`. Decode as the real Gayle / gayle.v: CS1 at
    $DA0000 and $DA2000 (register = A4..A2, A1 ignored: a long access is two
    data words), CS2 at $DA1000/$DA3000 (+$18 = device control / alternate
    status, other CS2 registers float), $DA8000 card status (bit 15 = IDE irq
    | cs_mask 5, the written cs_mask/cs), $DA9000 bit 15 = INTRQ (writes
    ignored, as gayle.v), $DAA000 enable bit 15, $DAB000 config 15..12, Gayle
    ID 1,1,0,1 on bit 15 (a write restarts). ATA INTRQ: set by a commit with
    flag bit 2 unless nIEN (control bit 1), cleared by a status read or a
    command write, by SRST and reset; irq_o = gayle_i & INTRQ & enable,
    OR'ed into minimig's eth_irq input in main.vhd (INT2). New commit flag
    bit 3 (END): the 256th word of the last buffer->CPU block ends the
    command (DRDY|DSC instead of BSY, MiSTer ide.cpp's ATA_STATUS_END); 0x119
    reads the mode for the firmware.
  - Firmware: commit flags follow MiSTer ide.cpp (the drive the A600/A1200
    scsi.device is proven against): IRQ on every commit that ends BSY except
    the first DRQ of a WRITE; the last READ sector and IDENTIFY carry END and
    finish WITHOUT a commit (a late READY commit could land on the host's next
    command - the race END would otherwise open); at a command event a
    pending buffer event of the previous command is consumed. IDE_LIDE_OK is
    true in Gayle mode (no lide.rom needed). RIPPLE mode also gets END (lide
    polls; ready slightly earlier); irq_o stays 0 there.
    MENU_HEAP_SIZE 3552 -> 3616 (demand 3591), release HEAP_SIZE 21440;
    ROM 29012/32768 words.
  - amiga_cold_boot: a Gayle toggle change cold-boots like the CPU radio.
  - Tests (all out of repo):
    - `~/aexp-work/ide/tb_ide_board.vhd` (`run_tb.sh`): RIPPLE PASS (and
      irq_o never set) + `-gG_GAYLE=true` PASS (ID sequence, registers, irq
      per ide.cpp rules, alt status does not clear, nIEN, enable, END,
      command-write clear, reset). `mut.py`: 30 mutants (12 old + 18 Gayle)
      all killed.
    - `~/aexp-work/fw-ide2` (real firmware in the QNICE emulator): harness
      checks the flags of every commit (T_DRQFL: read 04 / last 0C, write
      01 then 05; final 04), no commit after END (stepped on even records,
      left pending into the next command on odd ones), Gayle PREP without
      lide.rom (lide field 2). 5 cases PASS (case_s64 regenerated without
      the partition part: the emulator seeks with 32-bit byte offsets and
      the 64-sectors-per-cluster image puts it past 4 GiB - an emulator
      limit, old firmware fails it the same way). Mutants: 12 new all
      killed; old `sel_swap_short` survives as before (all4.log).
    - `~/aexp-work/gayle/e2e` (Verilator: real fx68k + cpu_wrapper + the
      ghdl-converted ide_board + firmware model): RIPPLE prog PASS (0 irqs),
      `prog_gayle.S` PASS (Gayle ID through $DE1000, no IDE board in the
      autoconfig chain, IDENTIFY by MOVE.L, READ via $DA0000/$DA2000, WRITE
      without irq on the first DRQ, nIEN, ABRT, RESET instruction; 6 irqs,
      no Gayle cycle on the chip bus). Its TG68K variant fails at the first
      autoconfig step in RIPPLE mode too (the old bench's bus models), so
      the 32-bit CPUs are covered by e2e040 instead.
    - `~/aexp-work/cpu060/e2e040/run_gayle.sh`: the release configuration
      (C_CPU040 2, OPTS 311, both cores) with GAYLE 0/1 x TG68K/AP68040
      (prog.S `.if GAYLE`: no IDE board in the chain, MOVEM bursts on
      $DA2000, $DE1010 and a long on $DA9010 go to the board).
      All four PASS (32 / 38 board accesses). Mutants (`mut_gayle.sh`):
      `sel_gayle` without $DE1 -> $BA17, the IDE board still autoconfig'd
      as the Gayle -> $BA90, both killed on both CPUs.
  - R6 build `~/aexp-builds/Megamiga-gayle-a`: WNS +0.017, WHS +0.017,
    85.9k LUTs (0.6.0 85.8k). NOT hardware-tested yet.
  - HW round 1 (2026-10-12): HDToolBox found the Gayle drive but called it
    "Unknown", existing RDBs were not seen, "Save Changes to Drive" gave
    error -3. Cause: the scsi.device of Kickstart 3.1 (and older) addresses
    CHS (DEVH bit 6 clear), which the firmware aborted (lide.device always
    sends LBA). FIX (firmware only): IDE_TF_LBA converts CHS with the drive's
    geometry like MiSTer ide.cpp, LBA = (C x heads + H) x spt + S - 1 (head <
    heads, 1 <= S <= spt, else IDNF); per-drive HDF_HEADS/HDF_SPT in the
    swapped drive block (HDF_BLK_WORDS 281), default 16/63 at mount; INITIALIZE
    DEVICE PARAMETERS (0x91) sets them (count 0 = 256 sectors, heads = DEVH
    3..0 + 1); IDENTIFY words 54..58 report the current geometry and capacity.
    fw-ide2: CHS reads at the default geometry, after 0x91 15/32 and 1/256
    (cylinder > 255, LBA > 65535), a CHS write read back by LBA, three IDNF
    cases; 13 CHS mutants killed; case_p's old "CHS -> ABRT" records became
    0x91 16/63. Firmware 29148 words. Delivered as a patched bitstream
    (`Megamiga-gayle-b`, see below).
  - HW round 2 (2026-10-12, gayle-b, tested on the 68040 only):
    HARDWARE-CONFIRMED - with Gayle on, the existing drives are recognized,
    and a new HDF was partitioned in HDToolBox (Save Changes to Drive works)
    and its partitions formatted; with Gayle off, the Zorro board with
    lide.device still works. Not yet tested: 68000/68020, A600 + KS 2.05.
  - Rebased onto main 0.6.2 (2026-10-15, branch `dev-0.7.0`, old tip kept as
    `dev-0.7.0-backup` 8c5bbe1) and again onto 0.6.3 (2026-10-16, the 0.6.2
    state kept as `dev-0.7.0-pre063`; Minimig branch `dev-0.7.0` = the Gayle
    cpu_wrapper commit on ec7b7f0). Merges: `ext_sel`/`chipreq` with
    `sel_ide | sel_gayle | sel_eth | sel_shr`; the Gayle toggles on lines
    28 / 46 / 64 (the blank line after each chipset radio, main's menu),
    groups `OPTM_G_P1/P2/P3GAYLE` (57/58/59, 58/59/60 since 0.6.3 took 57
    for RTG native resolution); main.vhd `eth_irq_i or ide_irq_i` next to the
    cart ports; MENU_HEAP_SIZE 3936 (demand 3930), release HEAP_SIZE 14592
    (on 0.6.3: demand 3889 + 63 = 3952, MENU_HEAP_SIZE 3968, HEAP_SIZE 14560); HDF_BLK_WORDS 284 (main's FDH 15 + 12 + the
    CHS geometry); the CHS default geometry is set after HDF_DSLOT/HDF_DGEN,
    so partitions get it too. Firmware: ROM 31502/32768, banks 3850/3621/1477.
  - NEW with the rebase: the sector engine (0.6.1) serves READ/WRITE SECTORS
    in hardware, but only the firmware raised INTRQ, so in Gayle mode
    scsi.device waited for an interrupt that never came. ide_board.vhd now
    raises INTRQ for engine transfers (Gayle mode, unless nIEN) like a real
    drive: per READ block (DRQ set), per WRITE block after the first, at the
    WRITE end and on errors; none after the last READ block. RIPPLE mode is
    unchanged (lide.device polls). CHS commands still go to the firmware
    (the engine only takes LBA, DEVH bit 6). Tests: `~/aexp-work/ideng/run_g.sh`
    (`tb_ide_g.vhd`, scsi.device-style: wait for INTRQ, read status, move
    the block) PASS for both scenarios x GAYLE true/false; red check (engine
    without INTRQ) fails; mutants "no per-block IRQ" and "no write-end IRQ"
    killed. `~/aexp-work/ide/run_tb.sh R=<checkout>` IDE BOARD TB + GAYLE PASS.
    `~/aexp-work/fw-ide4` (fw-ide3 + Gayle: CHS, GAYLE records, END/IRQ flags,
    0x91, IDENTIFY 54..58): 6 cases PASS, 84/84 mutants killed.
    e2e040 `run_gayle.sh` (W=worktree): all four PASS (32 / 38 board
    accesses). tb020.sv had to tie the 0.6.2 inputs `cart_ar3`/`cart_ovl` to
    0: left open, `cart_ar3` made the Zorro II RAM decode X and the TG68K
    stalled in the Fast RAM fill (the AP68040 uses the fp_* port, so it passed).
  - R6 build `dev070-a` (on 0.6.2, no reference): WNS -0.335 (68040 core and
    TG68K -> sdram_ctrl paths, none in the Gayle logic); 11 re-roll attempts
    reached -0.155 at best, stopped after the 0.6.3 rebase. Build `dev070-b`
    (on 0.6.3, incremental from `rel063`, IMPL_MARGIN flow): met timing on the
    first pass, WNS +0.066, WHS +0.007, 115.0k LUTs, 116 BRAM tiles;
    `~/aexp-builds/Megamiga-dev070-b`. HW (2026-10-16, 68040 + Z3 Fast RAM,
    OS/Kickstart 3.2, both on the 4-bit bus): Gayle boots (KS 3.1 too), but
    2.4 MB/s against 4.8 MB/s with lide.device. Not the hardware: the engine
    reads 8 sectors ahead, Gayle and RIPPLE cycles cost the same; scsi.device
    waits for one INTRQ per 512-byte sector (INT2 server, Signal, task switch:
    ~100 us each), lide.device polls.
  - READ/WRITE MULTIPLE (2026-10-16, for scsi.device and Linux's libata, which
    uses it when IDENTIFY word 59 has a valid count): one INTRQ per block of N
    sectors. Board: per-unit count registers 0x126/0x12E (-> engine: takes
    0xC4/0xC5 for a unit with a count; -> core side through the CDC: block
    size), `blk_more`: between two sectors of a block a data-register access
    is HELD (no DTACK) while BSY - a host moves a block without status reads;
    the engine path sets it itself, the firmware path by commit flag bit 4
    (IDE_FL_MORE); INTRQ only at block starts. Firmware: SET MULTIPLE (0, 1,
    2, 4, 8, 16, else ABRT; writes the board register before the commit),
    per-drive HDF_MULT in the swapped block (HDF_BLK_WORDS 285), default 16 at
    mount, READ/WRITE MULTIPLE on the firmware path (CHS, engine off; no count
    -> ABRT) via IDE_MBLOCK/IDE_MFLAGS/IDE_NEXT's block position, IDENTIFY
    word 47 0x8010, word 59 0x0100 | count. lide.device also switches to
    MULTIPLE (it sends SET MULTIPLE with word 47's count). The held access is
    at most a firmware sector (the 68040 bus watchdog is 37 ms). ROM
    31669/32768, HEAP 0xAF72.
    Tests: tb_ide_g (+ SET MULTIPLE, READ/WRITE MULTIPLE on file/partition,
    counts not a multiple of N, slow CPU, firmware path with a held access
    > 5 us, no count -> ABRT, a card error within a block releases the held
    access): 4/4 PASS; `~/aexp-work/ideng/mut_mult.sh`: 11/11 killed
    (no hold, hold also during DRQ, INTRQ per sector / on resume, flag bit 4
    ignored, block size 1 or of the other unit, C5 as a read, engine without
    MULTIPLE or with the other unit's count), `last_more` equivalent (a stale
    blk_more after the last sector holds nothing). fw-ide4
    (agent-extended: 10-word records, MULTIPLE flags per sector, per-drive
    counts, remount -> 16, CHS, word 47/59, board register): 6 cases PASS,
    110/110 mutants killed, no firmware bug.
    Build `dev070-c` (incremental from dev070-b): WNS +0.013, WHS +0.007;
    `~/aexp-builds/Megamiga-dev070-c`. HW (2026-10-16, same setup: 68040,
    Z3 Fast RAM, KS/OS 3.2, 4-bit card): Gayle 2.4 -> 2.9 MB/s, so the 3.2
    scsi.device uses MULTIPLE; the rest is its own per-block Wait()/copy
    overhead. The user accepts it ("If that's a limitation of how Gayle works,
    then it's fine. Lide is still an option for most use cases"): lide.device
    (Gayle off) stays the fast choice for AmigaOS, Gayle is for the Kickstart's
    own scsi.device and Linux. lide.device with MULTIPLE not measured yet.
  - HW (2026-10-16, dev070-c): 68020 + Z3 Fast RAM: Gayle 1 MB/s, lide.device
    4.5 MB/s. 8 KB at 1 MB/s = ~8 ms per block: lost interrupts, recovered by
    a timeout. Cause: `$DA9000` bit 15 followed INTRQ (as gayle.v), which a
    status read clears; the engine raises the next block's INTRQ the moment a
    block ends when the ring already holds it (the slower 68020 copy keeps the
    ring full, the 68040 mostly empties it), and a status read before the
    INT2 server ran lost it (the server then saw $DA9000 = 0: not mine). On
    MiSTer the ARM side is slow enough that this never shows. FIX (as a real
    Gayle, UAE, and what Linux's pata_gayle expects: it acknowledges with
    0x7C): bit 15 of $DA9000 is a LATCH, set when INTRQ rises, cleared by
    writing 0 to it (a 1 changes nothing) or a reset; INT2 = latch and
    $DAA000. RED/GREEN: tb_ide_g's Gayle host now reads the status right after
    every block and serves interrupts like pata_gayle (latch bit, status,
    0x7C) - before the fix "file read 21+30 slow CPU" hangs (INTRQ timeout) in
    both Gayle scenarios, after it 4/4 PASS. tb_ide_board's Gayle part moved to
    the latch semantics (status read clears INTRQ = $DA8000 bit 15, not the
    latch; 1 written to bit 15 changes nothing): PASS. mut_mult.sh + 3 latch
    mutants (INT2 from INTRQ, acknowledge ignored, latch = level): killed (14/14).
    Build `dev070-d` (incremental from dev070-c): WNS +0.030, WHS +0.007;
    `~/aexp-builds/Megamiga-dev070-d`. HW: no change (68020 + Gayle still
    1 MB/s, 68040 2.9 MB/s) - kept because it is what a real Gayle does.
  - Diagnostics (2026-10-16, commit 74009c5, build `dev070-e` WNS +0.008):
    free-running counters in ide_board.vhd (commands, data words, interrupts
    latched/acknowledged, clocks latched/held/BSY/interrupt->next access, core
    clocks, status/alternate status reads, last command), snapshot on a
    request (0x134) through cdc_stable, read at 0x140..0x157; `IDE_DIAG`
    firmware (m2m-rom.asm, firmware-only switch) prints them as one line on
    the debug UART (115200) about every 1.34 s while data moves;
    `~/aexp-work/remote/idediag.py` (this machine: /dev/ttyUSB1) decodes them.
    tb_ide_g reads the snapshot and checks it. HW (SysInfo, 68020 / 68040,
    Z3 Fast RAM, KS/OS 3.2): 020+Gayle 1.09 MB/s: 16 commands/s x 128
    sectors, 133 interrupts/s (MULTIPLE 16 works), interrupt -> first data
    read 230 us, BSY 2 %, held 0 %: the card is never the limit; the copy
    itself takes ~460 us per sector (~1.8 us per data word; 0.1 us in
    simulation). 040+Gayle 2.90 MB/s: interrupt -> access 86 us. lide.device
    polls (~100 status reads per sector). CAUSE: `cachecfg` is "000" in
    main.vhd and cpu_wrapper's turbo chip/kick paths are off ("self-disable
    with cpucfg[1]=0 (68000)" - an AExp-era comment nobody revisited for the
    TG68K in 0.3.0), so the TG68K fetches every Kickstart instruction over the
    16-bit chip bus: scsi.device's word copy loop (in ROM) crawls, lide.device
    (RAM, MOVEM) does not, the 68040's caches hide it.
  - TURBO KICKSTART for the TG68K (2026-10-16, the user: "Yes, implement turbo kick
    for the 68020"): main.vhd cachecfg "110" (bit 1 turbo kick, bit 2 also data
    reads); cpu_wrapper (Minimig dev-0.7.0 360284d): sel_kickram only for
    $F80000-$FFFFFF (the $E00000 1 MB-ROM half stays on the chip bus),
    turbokick_d also requires ~cpu040_sel (the AP68040 keeps its tested path).
    The fetch goes through ramsel -> main.vhd fram_addr "00" & [22:1] -> bank 0
    of sdram_ctrl, the same {bank,row,column} the chipset port uses for the
    kick bank ([22:19] = 1111) - i.e. the words the Kickstart loader wrote;
    sdram_ctrl's CPU cache snoops every chipset-port write (snoop_act =
    chipWE), so a Kickstart reload leaves no stale lines. Turbo chip stays off.
    Test `~/aexp-work/cpu060/e2e040/run_kick.sh` (prog_kick.S + kick.S at
    $F80000; the ROM in the SDRAM model with one signature, on the chip bus
    with another): TG68K + 110 -> SDRAM path, TG68K + 000 and AP68040 + 110 ->
    chip bus, the loop checksum equal on all paths; 2000-iteration ROM loop:
    290,668 cycles over the chip bus vs 20,572 with turbo kick and the
    instruction cache on (CACR, as Kickstart sets it) = 14x; uncached 146,556.
    Build `dev070-f` (incremental from dev070-e): WNS +0.029, WHS +0.007;
    `~/aexp-builds/Megamiga-dev070-f`. e2e040 `run_gayle.sh` with cachecfg
    110 (now its default): all four PASS (32 / 38 board accesses). HW
    (dev070-f, SysInfo): 68020 + Gayle + KS 3.2 1.09 -> 1.9 MB/s (interrupt ->
    first data read 230 -> ~150 us); KS 3.1 0.5 MB/s (first measurement):
    READ MULTIPLE 128 sectors too, but BSY 79 % and ~220 status reads per
    sector - its scsi.device addresses CHS, which the engine forwarded, so the
    firmware fetched every sector (~870 us each).
  - CHS IN THE ENGINE (2026-10-16, the user: "Yes, implement CHS in the
    engine"): per-unit geometry register 0x127/0x12F ((heads - 1) << 12 |
    sectors per track, 0 = none), written by the firmware (IDE_GEOM_REG) at
    mount (16/63) and by INITIALIZE DEVICE PARAMETERS before its commit;
    ide_engine.vhd E_CHS1..3: (cylinder x heads + head) x spt + sector - 1,
    then the LBA range check; CHS invalid for the geometry (sector 0 or > spt,
    head >= heads), past the end or without a geometry still goes to the
    firmware (IDNF). The LBA path is unchanged (accept/forward became the
    procedures take/forward). tb_ide_g: a CHS host mode (the LBA tests' data
    checks, sent as CHS) - READ/WRITE MULTIPLE and SECTORS at 4/17, cylinder
    300 at 1/1, served by the engine (the firmware sees nothing); sector 0
    (also at C1/H1), head 4 of 4, sector 18 of 17, past the end, unit
    without geometry -> firmware: 4/4 PASS. mut_mult.sh: 9 CHS mutants
    killed (sector 0 at C0/H0 alone did not kill "no sector-0 check": LBA -1
    wraps and fails the range check - hence the C1/H1 case). Firmware ROM
    31784/32768. fw-ide4 (agent): the geometry register after every mount
    (0xF03F), after 0x91 (the commanded drive, observed AT the commit, the
    other drive unchanged), untouched by other commands, and with IDENTIFY;
    geometries incl. 16/256 and 2/255; 6 cases PASS, 118/118 mutants killed
    (8 new), no firmware bug. Build `dev070-g` (incremental from dev070-f):
    WNS +0.056, WHS +0.007; `~/aexp-builds/Megamiga-dev070-g`.
    HW (2026-10-16, SysInfo, 68020 + Z3 Fast RAM + Gayle): KS 3.1 0.5 -> 3.0
    MB/s, KS 3.2 1.9 MB/s. Board side identical for both (READ MULTIPLE 128,
    interrupt -> first data read ~150 us, BSY 1-1.5 %); 3.2's scsi.device
    takes ~270 us per sector against 3.1's ~170 us - its own copy, nothing
    the board can change.
  - HW (2026-10-16): an INTERMITTENT HANG with turbo Kickstart when SysInfo
    starts from the hard disk (frozen screen, pointer gone, drive LED off):
    dev070-g hung with lide.device and worked with Gayle (KS 3.1); dev070-f
    hung with Gayle and worked with lide.device (4.7 MB/s). Never seen before
    turbo Kickstart. lide.device on 3.2 measured 2.1 MB/s once (4.5 before).
    Ruled out in simulation: CACR handling (the TG68K keeps CACR bit 3, so
    cpu_cache_new clears only once after reset - a ROM stress routine with
    CACR on/off/clear, ROM table reads and Chip RAM writes gives the same
    checksum with and without turbo kick, kick2.S), SDRAM refresh (longest gap
    2.3 us either way; tb020 now prints it), bank-0 conflicts (one access per
    slot), stray writes into the Kickstart (rom_readonly). Diagnostics builds
    (commit 1203113, Minimig ad7438b): cpu_wrapper dbg_addr/dbg_state/
    dbg_stall into the IDE snapshot (entries 12/13), IDE_DIAG prints every
    1.34 s: `dev070-h` (cachecfg 110, WNS +0.040) and `dev070-h2` (010 =
    turbo kick for instruction fetches only, built from a copy,
    ~/aexp-work/build-src/dev070-h2, WNS 0.000).
    dev070-h on HW (KS 3.1 + Gayle, SysInfo from the hard disk): hung again;
    NOT a bus stall (waits <= 0.3 us, the CPU keeps running), the IDE board
    idle and every interrupt acknowledged (the last command, WRITE SECTORS 1,
    completed). The CPU loops in graphics.library 40.24 ($F98828-$F9889C of
    KS 3.1 40.68: walk a list via (12,a2) until (54,sp), nodes in Z3 Fast RAM
    $4009E44C): a list in Fast RAM became circular = Fast RAM data corrupted
    earlier. Next: dev070-h2 (ROM data reads on the chip bus).
    dev070-h2 hung too (same loop, the list walked into address 0): not the
    data-read path. CAUSE (found in simulation, 2026-10-16): the CPU cache's
    SNOOP in sdram_ctrl (cpu_cache_new: chipset writes update cached lines),
    never exercised before turbo Kickstart because the cache only held Fast
    RAM. sdram_ctrl set chipWE (= snoop_act) at every chip slot and cleared it
    only on reset, so after a chipset write it stayed 1 through the following
    non-chip slots, and the snoop used the LIVE chip bus (chipAddr, chipWR) -
    whose address lines carry the CPU's current address when there is no DMA,
    i.e. exactly the Kickstart address the CPU was fetching through the cache:
    the snoop "updated" that cached code with bus junk (blitter-heavy
    Workbench launches = many chipset writes). Upstream MiSTer has the same
    code. tb020 `CHIPLOAD` drives the chip port like minimig_sram_bridge (a
    chipset write every 5th 7 MHz cycle, a DMA read, else the CPU's banked
    address with junk on the data bus): RED - the turbo ROM loop (I-cache on)
    ran off the rails (result never written in 3M cycles), the chip-bus
    reference passed. FIX (Minimig d7d29e2): chipWE is cleared at every slot
    start and set only in a chipset write slot, and the snoop gets the
    write's own address/data/byte selects captured with it (snoopAddr/WR/BS)
    - each alone closes this path. GREEN: k1c 3dd07332 in 20,576 cycles
    under load, k1 (uncached), k0c reference pass.
    Also under load: the ROM stress routine (kick2.S) gives a142f3a0 with
    and without turbo Kickstart; run_gayle.sh (no chip load) 4/4 PASS. Build
    `dev070-i` (the fix + diagnostics, cachecfg 110; incremental from
    dev070-h): WNS +0.039, WHS +0.007; `~/aexp-builds/Megamiga-dev070-i`.
    HW (dev070-i): KS 3.1 Gayle 3.0 MB/s, lide.device 4.6 MB/s. It still hung
    once, in the same graphics.library list walk ($F98828-$F9889E, a
    linked list (next at +12) that never reaches its end pointer), and the
    user then saw that the hangs came with the experimental PrismRTG driver
    on an RTG screen: with Picasso96 restored everything works. So the
    remaining hang is PrismRTG's (see "PrismRTG driver"), not the core; the
    snoop bug above was real regardless (red/green in simulation).
    KS 3.2 (dev070-i): 020 Gayle 1.9 / lide 4.6, 040 Gayle 2.8 / lide 4.6;
    KS 3.1: 040 Gayle 2.2, lide 4.6. One 020+3.2+lide run gave 1.4 (the next
    4.6, like the earlier one-off 2.1): the diagnostics show irq->access 93
    instead of 31 us and the CPU sampled at Z3 $403DB0xx instead of the
    board - something else ran on the CPU during that test.
  - **Merged into main (2026-10-16, 011e767)** on top of 0.6.4 (A4000
    profile, PrismRTG). Only the menu collided: main's A4000 layout keeps
    the blank line after each profile's chipset radio, dev-0.7.0 had made
    it the Gayle toggle; merged = main's layout with the toggle on lines
    29/47/65/83 (C_PROF_GAYLE = 6 unchanged), the A4000 one off by default
    (its Kickstart drives the A4000 IDE at $DD2000, not the Gayle), groups
    OPTM_G_P1..P4GAYLE = 65..68 (main's A4000 groups keep 58..64). OPTM_SIZE
    stays 248; +84 characters: demand 4320 (= 135 x 32), MENU_HEAP_SIZE
    4320, release HEAP_SIZE 14208. Firmware 31788/32768 words. The IDE
    diagnostics (IDE_DIAG, UART) are still on.
    Build `main-merge-b` (incremental from dev070-i): WNS +0.101, WHS +0.007;
    `~/aexp-builds/Megamiga-main-merge-b`.
  - **Where lide.device's time goes (2026-10-16, simulation).** The user asked
    about DMA from the board into Z3 RAM. `~/aexp-work/cpu060/e2e040/meas_lide.sh`
    runs lide 40.12's read copy (`$1BF6`: MOVEM.L 13 longs from the data
    window, MOVEM.L into the buffer, 9 x 13 + 11 longs) for 8 sectors per
    destination, board model with ide_board.vhd's latency, stack in Z2.
    Sector into Z2/Z3: TG68K 96 us (5.3 MB/s), AP68040 with 68040.library's
    copyback 99-100 us (5.1 MB/s), uncached 119 us; into Chip RAM 2.0-2.5 MB/s.
    It matches the hardware's 4.6 MB/s on both CPUs (the rest is command and
    IRQ overhead). Per sector (core clocks): TG68K 2732 = board reads 768
    (3 clocks per word) + stores ~1450 (a 13-long MOVEM.L store ~145 clocks,
    5.6 per word) + call overhead ~680; 68040 2800 = board reads ~1920 (a long
    = 3 + 12 clocks, the 12 between longs) + stores ~700 (copyback) + ~400.
    So the TG68K is bound by its Fast RAM stores, the 68040 by the board read
    path. The SD bus (4-bit, 25 MHz) would allow ~10 MB/s.
    Traced (tb020.sv `ISLTRACE`/`TGTRACE` probes): the TG68K run above had
    its instruction cache off; with CACR = 1, as exec sets it (`s0cb`), a
    sector into Z2/Z3 takes 75-76 us (6.8 MB/s, 2140 clocks), so instruction
    fetches from Fast RAM (8-9 clocks per word uncached) were a quarter of it.
    What is left on the TG68K: board reads 3 clocks per word, Fast RAM writes
    4 clocks per word - sdram_ctrl serves one access per 7 MHz slot (16
    states at 113.5 MHz = 4 core clocks), a 16-bit write takes a whole slot
    and the write buffer holds one word. On the AP68040 one board long is 16
    core clocks: the adapter's two 16-bit cycles 6 (3 per word, one of them
    the idle between the words), the answer toggle 1, the CDC back to the
    CPU ~1.3, the core from m_ack to its next m_req 4 CPU clocks (~2.7), the
    queue write ~0.7, the CDC to the bus side ~2.3, entry load + adapter
    start 2. No single wait; the island's own registers and the idle word
    are ~3 of the 16, the two crossings ~3.6, the core ~2.7.
    **IDE data stream (branch `ide-stream`, 2026-10-17):** the board pushes
    the sector's next words ahead into a 32-word FIFO in the island's CPU
    clock domain (`ids_*` ports: `ide_board.vhd` -> mega65/main ->
    cpu_wrapper -> `ap040_island.v`; `pf_off` = words sent beyond `ptr`, reset
    by every other bus access to the board), and the 68040 takes data-register
    reads (RIPPLE $1000-$11FF, Gayle $DA0000) from it as longs without a bus
    cycle; a hit queues a consume entry so the board's `ptr` advances in
    order with status reads and commands, words are tagged with a count of
    board entries so stale ones are dropped. TG68K/fx68k: ports tied off.
    Measured (meas_lide.sh `IDS=1`, sector into Fast RAM, routine in Z2):
    68040 copyback 5.1 -> 11.9 MB/s (Z3) / 12.3 MB/s (Z2), uncached 7.7 MB/s;
    TG68K unchanged 6.8 MB/s. TBs: `~/aexp-work/ideng` `STREAM=true` (real
    `ide_board` + engine, scenarios 0/1 x Gayle, all PASS),
    `~/aexp-work/cpu060/e2e040/run_ids.sh` (every word checked, 6 PASS).
    Build `ide-stream-a` (R6, REF main-merge-b): WNS +0.119 ns, WHS +0.007 ns,
    0 routing errors. Hardware (2026-10-17, 3.1, lide, 68040, Z3): SysInfo
    **10.5 MB/s** from the tray card in native 4-bit mode (before: ~4.8);
    2.84 MB/s from a card in SPI mode, where the board diagnostics show BSY
    72% / held 64% = the 68040 waits for the card.
    Gayle (same build, 68040): 3.1's scsi.device 2.7 MB/s on 4-bit and SPI alike
    (move.w loop, ~113 status polls per sector inside READ MULTIPLE blocks, BSY
    39%), 3.2's scsi.device 6 MB/s on 4-bit - left as a driver limit. The slave
    on the Gayle: 3.1's scsi.device probes only the master at init (no master =
    no device, as on a real A1200) and stops the unit scan when the master's RDB
    has rdb_Flags bit 0 (RDBFF_LAST, HDToolBox "Last disk"; amitools rdbtool
    writes 7); lide.device ignores it. Clearing it on the master HDF made the
    slave mount (user, 2026-10-17).
    Merged into main (with floppy-direct); build `main-ids-a` (R6, REF main-merge-b):
    WNS +0.021 ns, WHS +0.016 ns, 0 routing errors; ideng STREAM=true all PASS on
    the merged tree.
    Later on main-ids-a: lide 9.5 MB/s, scsi.device (3.2) 5.6 MB/s on 68040/Z3 - a few
    hundred KB/s below ide-stream-a; not investigated (no floppy inserted).
  - **IDE DMA (branch `ide-dma`, 2026-10-17; plan `doc/developers/ide-dma-plan.md`).**
    sdram_ctrl: a second client of the 68040's fp_* slots (`dm*`, a one-sysclk front end
    picks the client; the switch rule looks at the selected client's LIVE request, else a
    slot can start while p_* change over), fp_* writes snoop cpu_cache_new (high half at the
    slot start, low half at state 4 - one line). ide_board: the DMA unit (RIPPLE only,
    registers at $A000 which lide never touches: ID $444D, address, control/status, words
    left) runs the board's own data-register code (`data_read`/`data_write`), reads spaced
    two clocks (ring output register), waits for DRQ by itself, refuses non-Fast-RAM ranges
    (Z2/Z3 decode from cpu_wrapper's new fmap_* outputs), pauses the IDE data stream. An
    early command end stops it but still writes the long it holds (found by the TB: the
    unit went idle with it queued, the next DMA wrote it first). lide.device fork branch
    `megamiga-dma` (51862e4): mm_dma in ata_read/ata_write after the first DRQ, one DMA per
    command, CachePreDMA/CachePostDMA, PIO for unaligned/refused buffers; ata_read/ata_write
    built -Os (the ROM was 304 bytes over with -O3; now 27268 of 28668). Name stays
    lide.device, ID string "(Megamiga DMA 1)". TBs: `~/aexp-work/idedma/mem` (dm/fp random
    traffic + snoop, 5 sdram_ctrl mutants, 4 killed + 1 that found the switch race),
    `~/aexp-work/ideng` DMA=true (both scenarios PASS), mutants `mut_dma.py`; e2e040
    run_ids.sh still PASS (default MAXCYC now 1500000). Build `ide-dma-a` (REF main-ids-a):
    WNS +0.006, WHS +0.016. Hardware (KS 3.1, lide, Z3, 4-bit): SysInfo 68040 9.1 MB/s,
    68020 9.8 MB/s (was ~5; the CPU no longer copies) - the card is the limit now.
    **DMATest and two watchdogs (2026-10-18).** `CORE/ide/DMATest` (vbcc, `build.sh`)
    writes and reads back an 8 MB pattern file from four buffers: Fast RAM long-aligned
    (DMA), +2 and +1 (CPU copy) and Chip RAM (refused by the DMA, CPU copy); the CPU fills
    the buffer just before each Write() and fills it with garbage just before each Read(),
    so a missing cache push or invalidate shows up as wrong data. First run (68040,
    ide-dma-a): write error at block 47940 - the board holds a data-register access while
    the SD card is busy inside READ/WRITE MULTIPLE (up to 250 ms by the SD spec) and
    cpu_wrapper's bus watchdog (`ap040_bus_timeout`, 2^20 core clocks = 37 ms, shared by
    TG68K and the 68040) ended the cycle. Now 2^24 = 591 ms (`ae26e0c`, build ide-dma-b):
    the 68020 passes all rounds. The 68040 then froze (mouse dead, even with the official
    lide): the AP68040's own core stall watchdog (`ap040_pipe_tg68k_compat.v`, 2^21 clk_cpu
    = 50 ms) fired under the bus watchdog and injected an access error. Now 2^25 = 0.8 s,
    above the bus watchdog (`cf736eb`, build ide-dma-c, WNS +0.006, WHS +0.016). Hardware
    (68040, KS 3.1, Z3, 4-bit), all rounds OK with both drivers (write / read MB/s):

    | Buffer | official lide 40.12 | DMA lide (Megamiga DMA 1) |
    |---|---|---|
    | Fast, long-aligned | 4.34 / 7.01 | 5.88 / 6.25 |
    | Fast, +2 | 2.33 / 4.59 | 2.50 / 4.65 |
    | Fast, +1 | 1.74 / 1.10 | 1.33 / 0.87 |
    | Chip | 1.36 / 1.51 | 1.39 / 1.48 |

    The DMA round writes 35% faster but READS about 10% slower than the CPU copy (128 KB
    Read()s through the filesystem; SysInfo still 9.1 MB/s) - under investigation. TB
    results: `mut_dma.py` 9 of 12 killed; `no_settle`, `stream_on`, `keep_nv` survive and
    are equivalent or defensive (the settle wait, the stream switch and the queued-long
    flag are covered by the drain on every exit). e2e040 with `DMTRAFFIC` (random dm*
    traffic next to the 68040 running code): no errors, longest CPU fp_* wait 23 clocks
    with DMA, no starvation. `CORE/ide/CacheTime` (68040): CachePreDMA+CachePostDMA on 128 KB
    cost 491 us when the board writes memory, 238 us when it reads it, CacheClearU x2 the
    same (about 120 us per call: the whole cache) - not the reason for the slower DMA read;
    three DMA runs read 5.96-6.25 MB/s (one official-lide run 7.01). Not pursued: the SD
    card is the limit (next entry).
  - **SD card at 50 MHz (branch `sd50` from `ide-dma`, 2026-10-18; plan
    `doc/developers/sd50-plan.md`).** `sdhost.vhd` (M2M exception 18): the controller
    process runs on 100 MHz (`hr_clk`, same MMCM as the QNICE clock, phase 0; new port
    `clk2x_i` through framework -> qnice_wrapper -> QNICE -> sdslots), all half periods and
    G_MS doubled, so every state behaves as before in controller clocks. Between the
    domains: QNICE reads clk_i copies, buffer writes and engine strobes last two controller
    clocks, the engine port is clk_i registers (inputs e_limit/e_abort/e_wr_data too).
    After the native init: CMD6 high speed (64-byte status block, group 1 result), 50 MHz,
    a calibration of four sample points (10/20/25/30 ns after the edge that raises SD_CLK;
    20..30 one step later, latched at the clock after each step so a paused clock skips no
    bit) by four CRC-checked reads of block 0 each, the middle of the passing points
    (`C_SAMP_PICK`); not switched / nothing passed / a failure at 50 MHz later -> native
    25 MHz. Engine write data at 50 MHz: the address runs two bytes ahead (the clients'
    block RAM + our registers: 6-7 clocks of latency, a byte every 4). Pin registers in
    the IOBs (Vivado packs the input pair into an IDDR). Register 6: bit 4 high speed,
    bits 6..5 the point. Found by the TBs: a retry into native ran the init's test read over
    the resumed operation; a failed native multi-block transfer left the card sending while
    the re-init drove DAT3 (now CMD12 first - also possible before 50 MHz); e_blk and e_done
    in the same clk_i clock (ide_engine relies on them being apart; S_DISPATCH waits); the
    calibration drain must outlast a block. TBs: `~/aexp-work/sd50` (12 scenarios, card
    model with CMD6, high speed output delay/hold ('W' window), board delays, `rd_gap`,
    strict data state; `mut.py` 17 mutants, 13 killed, survivors: lag_every_clock (needs a
    block gap below the spec minimum), idx1_late (the other clk_i phase, not reachable in
    the TB; the design has a clock of margin in both), hs_retry_loop (equivalent: a retry
    skips the high speed steps), no_blk_guard (killed by ideng)); `~/aexp-work/ideng`
    run_g50.sh (DMA, HS=true/false: all PASS), `sdslots` run50.sh PASS, `adfsd` run50.sh
    (scenario 0 PASS; scenario 1 is hours long with the old controller as well, running).
    Builds: `sd50-a` WNS -1.36 (the falling sample into the state machine had half a clock;
    the engine's limit adders + the compare in one 100 MHz clock), `sd50-c` (cbb1561) WNS
    +0.013, WHS +0.016. Hardware (68040, **Kickstart 3.2**, DMA lide, Z3, 4-bit): SysInfo
    **14.8 MB/s** (3.2 on main-ids-a without DMA: 9.5; 3.1 with DMA at 25 MHz: 9.1);
    DMATest Fast aligned write 6.89-7.54, read 8.16-8.50 MB/s; copying from an ADF on SD,
    from SDCard: and to the hard disk at the same time works. DMATest is now bound by the
    card's access time per 128 KB command (next: keep CMD18 running for sequential
    commands).
  - **Zorro III RAM 48 MB (branch `z3-48` from main 8a99a9c, Minimig branch `z3-48`,
    2026-10-18; survey `doc/developers/z3-48mb-plan.md`).** A second Zorro III board, 32 MB,
    with its own toggle per profile: the separator line after "Zorro III RAM (16 MB)" became
    "Zorro III RAM (32 MB)" (lines 37/55/73/91, `C_PROF_Z3B` = 14, groups
    `OPTM_G_P1Z3B`..`P4Z3B` = 69..72, default off, no line moved; MENU_HEAP_SIZE 4416 for a
    demand of 4408, release HEAP_SIZE 14112). Both Zorro III toggles now need the SDRAM (R4+)
    as well as a 68020/68040; a change cold-boots the Amiga. The board is the upper halves of
    the SDRAM rows of all four banks (column bit 9 - free since floppy-direct; the unused
    floppy slot of `sdram_ctrl.v` is gone): fram/fp/dm addresses and the TG68K cache snoop got
    bit 25, `main.vhd` maps ramaddr[25] = 1 to `'1' & [24:1]`. `cpu_wrapper.v`: `ac_z3b`
    (size code 001, serial 3) first among the Zorro III boards, so Kickstart puts it at
    $40000000, the 16 MB board at $42000000 and the RTG board at $43000000 (32 MB alone: RTG
    at $42000000; nothing hard-codes the RTG base); `ap040_island.v` + the compat wrapper:
    window 1 = the 32 MB board (A31..A25), its line fills and aligned accesses to the fp_*
    port at `'1' & A24..A2`; `ide_board.vhd`: the DMA decodes both boards (a range across
    them is refused like any other, lide falls back to PIO). TBs: `~/aexp-work/z3b` (e2e040
    copy: SDRAM model with all 1024 columns - the old one dropped column bit 9 and would have
    hidden every alias; prog.S `Z3B` 0/1/2 with regions in every half bank of both boards and
    twins that differ only in column bit 9; release configuration, TG68K and AP68040: all six
    PASS; `mut.py` 12 mutants, 11 killed, `cw_snoop_b25` survives: no IDE DMA write meets a
    TG68K-cached line of the board in the bench) and `~/aexp-work/z3b/ide` (ideng tb_ide_g50
    with both boards: DMA at the start, the end and across the bank boundary at $40800000 of
    the 32 MB board, refused ranges; scenarios 0/1 PASS; `mut.sh` 3 mutants killed - its
    first run was void: parallel `ghdl -e` overwrote one ./tb_ide_g, each mutant now has its
    own directory). Build `z3-48-a` (ea36094): WNS +0.025, WHS +0.016, 117.7k LUTs (88%).
    Hardware-confirmed by the user on 2026-10-18 (z3-48-a on the MEGA65 R6).
  - **Menu rows (branch `hmenu` from main 50b43ce, 2026-10-18; M2M exception 21
    `menu-rows`).** The user wanted radio options side by side: CPU (68000 68020
    68040), Chip RAM (512 kB 1 MB 2 MB), Slow RAM (None 512 kB), Monitor Cartridge
    (None HRTmon AR3) in every profile and Drive Settings > Drives (1 2 3); a fourth
    drive was offered by the user "if not too much" and left for later (new menu lines,
    a fourth entry in every per-drive table, a fourth image channel). A row: label line
    (the text before ": " of the group's first item), then the options, each behind its
    marker; the cursor highlights one option, left/right move inside the row, up/down
    skip the rest of it and land on the selected option of the next row, Return/Space
    select. Design: every option stays its own menu item (line numbers, settings file,
    OPTM_SIZE, prof_decode unchanged); only screen positions change, so menu.asm keeps
    computing the classic position (ordinal = position among the visible items) and the
    screen callbacks translate it through the layout `OPTR_PRINT` recorded while drawing
    (`M2M/rom/menu_rows.asm`). Slow RAM was a toggle: the separator in front of it
    (offset 10 of each profile block: lines 33/51/69/87) became "Slow RAM: None" and the
    toggle (offset 11, `C_PROF_SLOW`) its second item, so the HDL still reads the same
    bit; an old settings file has neither set, and `_HLP_RADIOFIX` gives any radio group
    without a selection its first item (no single-item radio group exists, checked by
    `cfg/check.py`). The Profile Settings page went from 27 to 24 rows. Firmware: ROM
    31694 -> 32296/32768 words, 84 variable words (stack margin 252 -> 168),
    MENU_HEAP_SIZE 4416 -> 4288 (demand 4260, 148 characters fewer), release HEAP_SIZE
    14240. Tests `~/aexp-work/menu-rows`: `run.sh` (real OPTM_SHOW/OPTM_RUN + menu_rows
    into a RAM screen: 25 scripted keys over three rows, a submenu row without a label,
    a classic radio and a single-select; screen and attributes checked at each step,
    callbacks checked), `radiofix/run.sh` (_HLP_RADIOFIX extracted from options.asm,
    16 settings banks in RAM, a group across a bank boundary), `cfg/run.sh` (ghdl dump
    of config.vhd as the firmware reads it: row rules, widths, defaults; `render.py`
    draws a level), `mut.py` 20/20 mutants killed; `~/aexp-work/menu-nest` still PASS.
    Build `hmenu-a` (6c0871f, REF z3-48-a): WNS +0.116, WHS +0.016; the user on the MEGA65:
    "Looks great!".

    Round 2 (afde733, 9cfc099; a NEW settings file is required, the user: "It's ok to
    require a new config file. No fallbacks." - so `_HLP_RADIOFIX` went again):
    - Profile blocks of 23 lines (stride 18 -> 23): rows CPU, Chipset, Hard Disk
      Controller (None / Gayle / RIPPLE - the RIPPLE-compatible Zorro II board,
      lide.device is its driver), Chip RAM, Slow RAM, Monitor Cartridge (no Zorro board:
      it stays outside the section), then the headline "Zorro Boards": Zorro II RAM 8 MB,
      Zorro III RAM 16 MB / 32 MB, Graphics Card, Network Card. The two cards had no switch
      before (always in); now per profile, default on: `cpu_wrapper` input `rtgena` gates
      `ac_rtgb`, `eth_ena` comes from the profile, None gates the IDE board's
      `ide_ena`; all three cold-boot through `amiga_cold_boot` `boards_i`.
    - Greyed out (the user: "grey out options that are not available"): config.vhd
      `OPTM_AVAIL` rules (group, item mask, mother group, mother item mask) mirror
      prof_decode - the Zorro III boards and the graphics card need a 68020/68040, HRTmon
      not the 68040, the Action Replay the 68000. The layout word carries them (bit 1 +
      mother/mask); `_OPTM_AVAIL` decides, OPTM_SHOW draws such items with
      `M2M$SA_COL_DIM` (0x4F), up/down/left/right and the entry position skip them, a
      change of a mother redraws the level (`_OPTM_GAFF`). The setting is kept.
    - The menu limit: the settings register has 256 bits and HELP_MENU_INIT allows 254
      items; the menu had 248 and needed 20 more. The 19 separators directly below a
      headline (all of them unconditional) are no items any more: config.vhd's
      `OPTM_HEADLINE_LINE` sets layout bit 14 for every headline and OPTR_PRINT draws the
      line itself (`OPT_LINE_AT`). 248 - 19 + 20 + 3 (drive sound) = 252 items, 2 left;
      more growth needs a wider settings register (an M2M change).
    - Virtual Drive Sound (Drive Settings row "On / Noclick / Off", default On): while no
      unit is the Hardware Floppy, `hwf_pins_proc` lets the real drive run its motor for
      the lowest disk image unit whose motor is on (df0 > df1 > df2) and passes on that
      unit's steps; without a motor the steps of the lowest selected disk image unit
      still reach it - the click of an empty drive - unless Noclick. `main_snd_cyl` keeps
      the head inside cylinders 0..79 (TRK0 resyncs it); write gate, side and density
      stay inactive.
    - Disk guard (user, 2026-10-19: a disk in the drive would wear): `main_snd_disk` =
      /DSKCHG read after the drive has been selected C_SND_SETTLE (1023) clocks - an
      unselected drive releases the line, which then reads "disk". The drive clears the
      latch on a step with a disk in, so the first click or seek after an insertion
      finds it (the motor may run until then). With a disk: no motor, no steps, only a
      probe select of 2^13 clocks (289 us) every 2^24 (0.59 s); a low /DSKCHG there
      (disk out) brings the sound back. Not with Off. drvsound TB cases h..k, 18/18
      mutants.
    - The settings file is created when no card has one (`_HLP_CREATE`, M2M-UPSTREAM
      cfg-create): on the first card that mounts, in the directory of CFG_FILE,
      OPTM_SIZE bytes with byte 0 = 0xFF (the standard selectors), then the lookup runs
      again; the user: "if config file is missing, create one".
    - Firmware: ROM 32576/32768 words, MENU_HEAP_SIZE 4480 (demand 4476). Tests:
      `~/aexp-work/menu-rows` (now also greying, the CPU redraw, a greyed selected option,
      headline lines; 25/25 mutants), `cfg/run.sh` (rows, rules, defaults, no single-item
      radio), `~/aexp-work/drvsound` (ghdl on the code block of mega65.vhd: priority,
      Noclick, Off, the 0..79 limits, TRK0, pulse width, the disk guard; 18/18 mutants),
      `~/aexp-work/cfgcreate` (cfgold + creation: 18 cases, the images checked; 4/5
      mutants, no_flush equivalent). Builds `hmenu-b` (afde733) and `hmenu-c` (9cfc099), REF hmenu-a: both
      WNS -0.774 (QNICE/sdhost, identical: firmware does not change P&R); `hmenu-d`
      (a184938, fresh) 16 re-rolls, best -0.042; `hmenu-e` (a184938, IMPL_MARGIN
      "cpu_clk:0.5 native_clk4x_mmcm:0.3 hr_clk:0.3 qnice_clk:0.2") PASS 0.000 after
      re-roll 2, on HW. HW found: the three C_MENU_* RANGE subtypes (OSM Scaling,
      Volume, Stereo Mix) had not been renumbered (the OSM came up small) - fixed in
      cfb466a; `~/aexp-work/menu-rows/cfg/xcheck.py` now checks every C_MENU_* constant,
      ranges too, against the item texts of 50b43ce.
    - Timing root cause (2026-10-19, 7e2c601): the CPU -> SDRAM multicycle in CORE.xdc
      matched `*cpu_inst_p/*`, but with CPU040 = 2 the 68020 is `g_ap040.tg68k_inst`, so
      since 0.6.0 its register file -> `sd_ba` paths were timed single-cycle (8.8 ns
      instead of 17.6) - the main_clk -> native_clk4x_mmcm misses of hmenu-b..g. Measured
      on hmenu-g's routed design: -0.177 ns before, +0.225 ns with `*tg68k_inst/*` added
      (WHS +0.036). New sign-off gate: every TG68KdotC_Kernel instance must be
      cpu_inst_p or tg68k_inst. Incremental synthesis from the REF build was added
      (80809f2) but Vivado declined it for hmenu-h ("Change is too high", an edit of
      mega65.vhd) - kept, it applies where the change is small.
    - `hmenu-g` (90f1e9b, REF hmenu-e): first pass -0.177 under the old constraint =
      +0.225 under the corrected one (same routed design, so its bitstream was used).
      HW-confirmed by the user 2026-10-19 (menu size, drive sound disk guard). Merged
      into main (4b13425 and the follow-ups up to 7e2c601), pushed.
    - Round 3 (2026-10-19, firmware only): (1) `_OPTM_DESEL` (menu.asm): a greyed-out
      item is deselected - a radio hands its selection to its first available option
      (AR3 -> None) - in OPTM_SHOW (a state loaded from a file) and before the selection
      callback copies OPTM_IR_STDSEL to M2M$CFM_DATA. Visual only before: prof_decode and
      cpu_wrapper already ignore a greyed-out option. (2) OPTR_PRINT: a headline right
      behind a row gets a separator line above it too (only "Zorro Boards"; no config
      bit: the 15-bit layout word is full; Profile Settings now 29 of 29 rows).
      (3) Settings file signature: `menu=XXXX` in the text, a 16-bit hash (rotate left,
      XOR) of OPTM_SIZE and the group words read from the config window - the structure
      of the menu, not its settings. HELP_MENU_INIT: after CFGS_LOAD `CFG_SIGCHECK`; no or
      another signature -> the file is reset in place (CFGS_SIZE to OPTM_SIZE, byte 0 =
      0xFF, no text) and treated as new; a new file gets the signature (`CFG_SIGSET`,
      CFGS_DIRTY: written at the next save); PREP_START shows "Settings reset" until a
      key is pressed (`CFGS_RESET`). Code in bank 2 (B2_CFG_*, FAR_CALL stubs; the fixed
      ROM has 60 words left: 32708/32768). Not caught: options of one radio swapped.
      Tests: menu-rows (+ a headline behind a row and behind a headline, OCS greyed with
      68020 -> AGA, Fast RAM selected under 68000 at the start, the selection array the
      callback copies; 33/34 mutants, snap_grey now unreachable = equivalent),
      cfgcreate (20 cases: signature ok / missing / other / short file, new and created
      files get it, the reset file on disk, SD0 untouched when SD1's is reset;
      `mut_sig.py` 13/13). Bitstream `hmenu-p1`: the firmware patched into linux040-d
      (CORE/patch_firmware.sh; its hardware sources are identical to main cddf519).
      HW-confirmed by the user 2026-10-19: the old file was reset ("made for another
      menu"), the saved new one loads without a warning at the next start.
  - **Linux boots to a busybox shell on the 68040 (2026-10-17..19, branch `linux040` from
    main 50b43ce, Minimig branch `linux040` from ea6144a).** Kernel: Linux 6.18.57 LTS built
    on fedora (`~/linux68k/build.sh`: `amiga_defconfig` for the 68040 only, -Os, busybox-static
    initramfs built in; the command line needs `video=amifb:pal`, amifb's AGA default is
    31 kHz), started with amiboot 5.6 from AmigaDOS (`execute boot`, kits
    `~/aexp-builds/linux-*`; the test kernel `linux-f` prints every access error as
    AEin/AEnn/AEout). Four AP68040 bugs stood in the way, all in the submodule's `rtl/ap040`
    (all four are in upstream ranzbak/AP68040-pipelined as checked out on 2026-10-10,
    `~/aexp-work/cpu060/ref/ranzbak_AP68040-pipelined`):
    1. MUL.L 64 (Dh) and DIV.L (Dr): EX computes the second result register, but EA-calc and
       EA-fetch only saw the micro-op's (An)+ update on u1, so the next instruction read the
       old Dh (put_dec_trunc8: `MULU.L #,D1:D0` / `MOVE.W D1,D0` - garbled printk numbers).
       EX exports its u1 port (`fw_u1_*`), EA-calc waits for it (`ex_w1_pend`).
    2. A completed store's access fault reported its pending write in WB1; the 68040 (WinUAE,
       NetBSD trap.c) reports it in WB3, and Linux's `access_error040()` completes only
       WB2/WB3, so every first write to a user page was lost (bss, exec).
    3. The early operand read (`use_early`) went out during exception entry: after a store
       fault (`wf_go`) EA-fetch is empty, the next, abandoned instruction's read gets FC 5 in
       P_EXC, Linux's supervisor table has no user mapping, the read faults, and a fault in
       exception entry halts the core (`aerr_dbl`). Found with an ILA capture on the MEGA65
       (`~/aexp-work/linux/ila`: probes added to linux-b's synthesized checkpoint in a
       non-project flow, trigger `ph == P_HALT`; busybox stopped right after its 13th access
       error). Fix: no early read in P_EXC/P_RTE/P_RESET/P_HALT, and one issued in the
       `wf_go` clock itself is dropped. Build `linux-d` (WNS +0.027): busybox ran to its
       162nd access error, then the CPU stopped again (diag UART: CPU address frozen,
       cursor frozen).
    4. An instruction-fetch fault (ID's `ifault`, not serialising) or a read fault enters
       P_EXC and waits in step 5 for the older instructions; a store fault from one of them
       counted as a double fault (`wf_dbl`). Nothing of the frame has gone out in step 5, so
       the store's access error now replaces the entry (`wf_go`), as on the 68040, and the
       abandoned instruction faults again after the RTE; a frame store (`wb_stf.exc`) is
       still a double fault.
    Benches in `~/aexp-work/linux/sim` (the e2e040 harness in the release configuration,
    OPTS 311, FRAM, copyback; `runbb.sh`, `regress.sh`; `mktb.py` monitors EXCTRACE/XWIN):
    `exctest.S` (store fault + the next load, 8 alignments x 0..3 fillers; without fix 3
    halts after 4 faults; mutants: only the `wf_go` drop PASSES, only the phase gate FAILS -
    the gate half, EA-fetch empty after `wf_go`, does not happen in the bench and rests on
    the ILA trace), `exctest2.S` (store fault + TRAP/line A: PASS before and after, both
    serialise), `exctest3.S` (a store at the end of a code page, the next page not present:
    without fix 4 halts after 1 fault, with it C0DE and all 96 faults), `bbtest.S` (busybox's
    start, separate empty SRP table) - all PASS with the four fixes. Build `linux-e`
    (floppy-direct + the four fixes, WNS +0.001, WHS +0.010): **hardware-confirmed
    2026-10-19, the user: "We're in buzybox and can execute commands."** Note: linux-e was
    built on the floppy-direct base (Minimig d7d29e2); the branch carries the same four
    commits on top of main's Minimig (ea6144a, IDE DMA + Z3 48 MB), not yet built as such.
    Reported upstream 2026-10-19: ranzbak/AP68040-pipelined issue #1 (all four, with the
    patch; it applies to upstream `0a07062` with offsets only).
    - Gayle ATA under Linux, "ata1: found unknown device (class 0)" (2026-10-19): libata
      classifies the drive after SRST by the ATA signature (LBA mid/high 00/00), but
      `ide_board.vhd`'s `device_reset` kept the taskfile, so the cylinder scsi.device had
      left there was read back. `device_reset` (SRST release and the hardware reset) now
      loads sector count 01, LBA low 01, LBA mid/high 00/00. Bench `~/aexp-work/ide`
      (`tb_ide_board.vhd` step 11, `add_sig.py`: SRST through pata_gayle's addresses
      $DA0002 + 4n / $DA101A): without the fix 4 errors (05/56/34/12 read back), with it
      both modes PASS; `~/aexp-work/z3b/ide` (DMA) scenarios 0/1 PASS. (`ideng/run_g50.sh`
      no longer elaborates against main's sdhost: stale bench.) HW: see linux040-d below.
    - Clean kernel kit `~/aexp-builds/linux-g` (pristine traps.c, /init = the busybox
      script; fedora `build.sh` takes OUT/VMOUT/INITT; the bring-up traps.c is kept as
      `traps.c.debug`); qemu virt reaches the shell.
    - Fedora: the build disk's btrfs ran out of metadata space (all chunks allocated to
      data, 41 GB "free"): `sudo btrfs balance start -dusage=5 /home` after deleting two
      disposable build directories gave 37 GiB unallocated.
    - Build `linux040-b` (main 50b43ce + the four fixes + the Gayle signature): WNS +0.002,
      WHS +0.036. On the MEGA65 the OSD menu did not come up; likely cause: main had
      moved on to the menu rows (OPTM_SIZE 248 -> 252, same file name), so the card's
      settings file did not fit the older menu. Rebased onto main
      4b13425 (hmenu), Minimig `linux040` onto 95069c1 (`rtgena`), no code conflicts.
    - Build `linux040-c` (REF hmenu-e): first pass WNS -0.077, the re-rolls worse (-0.545);
      the failing paths `g_ap040.tg68k_inst` -> `sd_ba` were the ones main's 7e2c601 then
      put under the CPU -> SDRAM multicycle (found by the hmenu session). Stopped, rebased
      onto main 7e2c601. Build `linux040-d` (REF hmenu-e): WNS +0.002, WHS +0.010 at the
      first pass. **Hardware-confirmed by the user on 2026-10-19** (linux040-d, kernel kit
      linux-g, A1200 profile with the 68040 and Gayle IDE): the OSD is back, Linux boots
      to the busybox shell, libata finds the ATA disk and lists its partitions.
  - **HDF images without an RDB (branch `vrdb` from main 33fdb93, 2026-10-19).** The
    user asked for UAE's simplified hardfiles (one file system from block 0 on, no
    RDB). Like MiSTer's `ide.cpp` (`guess_geometry`, `fill_fake_rdb`), the drive gets a
    virtual cylinder in front of the image: block 0 an RDSK, block 1 one PART over the
    whole image, the rest zeros; the image starts at block `HDF_VRDB`.
    - Detection (`B3_VRDB_DET`, at every mount of a file or an SD partition, after the
      extent map): block 0 starts with `DOS\0`..`DOS\7`, `PFS\x`, `PDS\x` or `SFS\0`, and
      blocks 1..15 hold no `RDSK`. Blank images stay as they are (HDToolBox). MiSTer takes
      any image whose first 16 blocks are not all zero.
    - Geometry: OFS/FFS put the root block at (blocks - 1 + reserved) / 2 of the
      partition, so the partition must have exactly the formatted size. UAE's default
      (32 sectors x 1 surface, 2 reserved, whole cylinders: root = (n & ~31) / 2) is
      taken unless only MiSTer's cylinder (the smallest of 32..2048 blocks with fewer
      than 65535 cylinders - it differs from UAE's above ~1 GB) finds an OFS/FFS root
      (type 2, secondary type 1) there. amitools' `xdftool` images are UAE-shaped
      (checked at 2, 10, 50, 300 MB: whole 32-block cylinders, root in the middle).
      Differences to MiSTer: the DosType comes from the image (MiSTer always DOS\1),
      MaxTransfer 0x1FE00 (MiSTer 0xFFFFFF), vendor/product "MEGAMIGA" / "DONT
      REPARTITION" / "VRDB", no cylinder clamp at 65535 (RDB fields are 32 bits).
    - Writes to the virtual blocks are ignored (as MiSTer). No FSHD: PFS/SFS images need
      the file system on the booting system.
    - Firmware: code bank 3 `BANK_IDE` (889 words) with the detection, the blocks
      (`B3_VRDB_RD` builds them in the board buffer; the buffer cannot be read back, so
      `_VR_PUTL` sums the checksum while writing) and HDF_LINK/HDF_PART_GET moved out of
      the fixed ROM: 32708 -> 32566 words (142 free). Hooks in the fixed ROM:
      `IDE_LBA2BLK`/`IDE_SEEK` subtract `HDF_VRDB`, `IDE_READ_SECT`/`IDE_WRITE_SECT` ask
      `HDF_VRDB_RD`/`_WR` first, `HDF_PREP` calls `HDF_VRDB_DET`. Per drive (inside
      HDF_FDH..HDF_SAVE): `HDF_VRDB`, `HDF_VDOS_HI/LO`; `HDF_BLK_WORDS` 285 -> 288.
      HEAP 0xAFCF + 18528 = 0xF82F, 1697 words below VAR$STACK_START for 1536.
    - Sector engine: per-unit skip register (ide_board 0x38/0x39, `IDE_ENG_SKIP0/1`):
      a command that starts below it (LBA or CHS) goes to the firmware, the others
      address LBA - skip; `sects` counts the virtual blocks too. HDF_ENG_SETUP writes it
      and reads it back: a board without it (a firmware patch into an older build) reads
      0, then such a drive stays with the firmware (correct, only slower).
    - Tests: `~/aexp-work/vrdb/fw` (fw-ide4 + vrdb: 14 images - UAE fast path, a
      fragmented one on the slow path, one over 64K sectors on the slow path, no root,
      PFS/PDS/SFS, refused ids, RDSK in block 5/15/16, a sparse 1 GB SD partition in
      MiSTer's geometry with a decoy header at UAE's root, a small DOS\7 partition; the
      reference RDSK/PART from `vrdb_ref.py` (written from the NDK layouts, checked with
      amitools: `rdbtool` parses it, `xdftool` mounts the partition through it and reads a
      file back); the whole fw-ide4 block() suite runs behind the virtual cylinder;
      `H_OLDHW=1` = a board without the skip register), `~/aexp-work/vrdb/eng`
      (tb_ide_z3b + SKIP: every LBA command shifted, commands below the skip must reach
      the firmware; skip 0 and 32, Gayle and RIPPLE with DMA).
    - Geometry fix after the first hardware test (vrdb-a, the user's SWOS WHDLoad image, 4 MB
      = 8192 blocks, A1200 profile on the Gayle): it booted, then "read error on disk block
      8045". Kickstart 3.1's scsi.device addresses by CHS with the IDENTIFY geometry and
      stops at its capacity: 16 x 63 gave 8 cylinders = 8064 of the 8224 blocks. Like
      MiSTer, a drive with a virtual RDB now reports the partition's geometry (IDENTIFY
      words 1/3/6 via `B3_VRDB_ID`: min(spc, 128) sectors, spc / that heads, cylinders =
      blocks / spc up to 65535) and gets it as the default CHS geometry at the mount
      (`HDF_HEADS/SPT`, so also the engine's geometry register); `HDF_VRDB_DET` moved
      behind the 16/63 defaults in HDF_PREP. (Plain RDB images can hit the same limit on
      the Gayle when their RDB cylinders reach past 16 x 63 ones; MiSTer reports the RDB's
      geometry for those too - not done here.)
    - Builds: `vrdb-a` (REF linux040-d, incremental synthesis + implementation; WNS +0.047
      after post-route phys_opt, WHS +0.010), firmware patch `vrdb-p1` (68a31d8) =
      **hardware-confirmed by the user 2026-10-19: SWOS loads without errors.** Fixed ROM
      32572/32768, bank 3 951 words.
    - Test results: fw - six image cases + the H_OLDHW variant pass (2154 records in
      case1), 198/198 mutants killed (81 v_* + the fw-ide4 set; the root-check mutants
      needed per-case PART3B variants - MiSTer root only / both / neither / a T_DATA decoy
      - and the direct `_VR_LONG` records 13 incl. one right after a WRITE's dirty steal;
      forged states (record 14) cover 256/2048-block cylinders beyond the emulator's 4 GB;
      v_is_noff equivalent); eng - skip 0/32 x Gayle/RIPPLE pass, 9/9 HDL mutants killed.
  - **Profiles as files (branch `profiles` from main, Minimig branch `profiles`, QNICE
    branch `map-progress`, 2026-10-19; design `doc/developers/profiles.md`).** One file per
    machine profile, `/amiga/profiles/NN_<name>.prof` (text `key=value`: cpu, chipset, hdc,
    chip, slow, cart, the Zorro boards, kick, hdf0, hdf1); the four defaults (01_A500..
    04_A4000) only when the folder is missing or holds no profile. The main menu has one
    "Profile:" line (name painted live) that opens the firmware's selector (Up/Down,
    Return, Run/Stop; Left/Right move the highlighted profile and renumber the files;
    "Add New Profile" behind a separator) and "Rename Profile"; Profile Settings shows ONE
    block for the active profile. Name editor: real typing through the ungated key status
    (`m2m_keyb.vhd` `key_raw_n_o`, an addition to M2M exception 4), FAT32-legal characters
    only. The settings file keeps `profile=<name>` (no number). Also: the Graphics Card
    switch removes the RTG board completely (Minimig `rtg: present input`), the HDF mount
    shows a progress bar (`FAT32$FILE_MAP_CB` in QNICE, `HDF_MAPBAR`) and the cluster chain
    is walked once (HDF_ENG_SETUP copies HDF_MAP when it fits), the selector's frame
    junctions. Firmware: `CORE/m2m-rom/profiles.asm`, code bank `BANK_PROF`. Tests:
    `~/aexp-work/profiles` (emulator + FAT32 images, 16 scenarios incl. sort order and
    rename, 35 mutants). Builds: `prof-c` (full) + firmware patches up to `prof-p6`,
    **hardware-confirmed by the user 2026-10-19** ("they work great").
    - Merged into main after vrdb (2026-10-19): both branches had added code bank 3, so
      BANK_IDE stays 3 and BANK_PROF became 4 (marker 0x4B04, labels B3_* -> B4_*); the
      temporary PRF debug output was removed first (128bfee, profiles TB 16/16). Submodules
      fast-forwarded: Minimig `develop` -> `profiles` (eebc314), QNICE `fat32-fastseek` ->
      `map-progress` (78aeaac). Merged firmware: fixed ROM 32631/32768, banks 3: 951 and
      4: 3286 words, HEAP 0xB4A8 + 17248 leaves 1736 stack words (1536 needed); the
      profiles TB (B3_/B4_ picked from the source) 16/16 and the vrdb fw TB case1 (HDF_MAPBAR
      stubbed with a plain FAT32$FILE_MAP) pass on the merged tree. The help page text of
      profiles (config.vhd) needs the next full build.
  - **Quick HDF (branch `quickhdf` from main e558567, 2026-10-19).** The user: a quick
    "hdf: <Load>" on the main page like df0:, which takes the profile's HDFs out until Space
    ejects it or the core restarts - for the WHDLoad libraries of one HDF per game. Their
    choice on the eject: the profile's disks come back.
    - Menu: " hdf:%s" at line 7 (below the drive lines; `~/aexp-work/quickhdf/insert.py` moved
      every line >= 7 and the C_MENU_* constants, xcheck 57/57), OPTM_G_QHDF 83, manual
      CRT/ROM load 3 (HDF 0/1, Kickstart, AR3 -> 4..7: PROF_HDF_ID 4, PROF_KICK_ID 6), its
      own CSR device C_DEV_AMIGA_IDEQ 0x010E (mega65.vhd i_ideq_csr, as the slave line's).
      OPTM_SIZE 182: the settings signature resets the settings file once. MENU_HEAP_SIZE
      3264 -> 3296 (demand 3242 + 9 + 4 + 25 = 3280), release HEAP_SIZE -32.
    - Firmware: QHDF_ON (zeroed by IDE_INIT); PREP_LOAD_IMAGE -> QHDF_PREP (bank 3: the
      slave out, HDF_PREP as the master, the profile lines keep STATUS OK where they show a
      name; refused while the profile's disks were in: PROF_HDFS mounts them again); the
      HDF lines while QHDF_ON only note the file (QHDF_HREM: EOF for the Shell, then
      PROF_REMEMBER). PROFILE_APPLY's disk part is `PROF_HDFS` (R8 profile, R9 switch) with
      two guards: no mount over the quick disk (the name only) and no drop (the line goes
      IDLE instead). Space: HANDLE_UNMOUNT_KEY asks HDF_SPACE_OK / HDF_SPACE (bank 3) for
      lines HDF 0, HDF 1 and hdf: - quick on, an HDF line forgets its file; on hdf: the
      quick disk is dropped, PROF_HDFS(0, switch) mounts the profile's, no drive left = the
      board leaves the chain and the Amiga restarts. The browser offers .hdf files and 0x7F
      partitions on the line too. Fixed ROM 32707/32768, bank 3 1182 words.
    - Tests: `~/aexp-work/quickhdf/fw` (the vrdb fw harness + the real PROF_HDFS against
      PROF_SAVED/NAME/FORGET stubs, records 15..19: profile files, quick load, Space per line,
      profile switch, a profile-line load while quick) - 2198 records, all seven cases pass;
      222/222 mutants killed (24 q_*: the drop before PROF_HDFS is needed when the profile's
      HDF 0 cannot be mounted; the line-IDLE guard was a real bug the switch record found).
      Not in the harness: the dispatch in PREP_LOAD_IMAGE and HANDLE_UNMOUNT_KEY's line test.
    - Builds: `quickhdf-a` - Vivado 2022.2 segfaulted in the incremental synthesis cache dump
      (HARTNDb::dumpUnoptimizedCache): build_all.sh `NO_REF_SYNTH=1` (fresh synthesis, the
      implementation still from REF); `quickhdf-b` (REF main-a): WNS +0.088, WHS +0.036,
      **hardware-confirmed by the user 2026-10-19** ("It works").
  - **The AR3 ROM remembered per profile (on main after 0.6.4, 2026-10-20).** A user reported
    that the AR3 ROM setting was not saved: the " AR3 ROM:%s" line was a session load (only
    /amiga/ar3.rom came back after a restart; the `cart` radio itself was always saved).
    Now the fourth file key `ar3rom` (`_P_FKEYS` key 3, ROM id `PROF_AR3_ID` 7,
    `PROF_PEND_NUM` 4, PROF_PNAME 84 words): PREP_LOAD_IMAGE remembers it like the
    Kickstart (`_PREP_LI_REM`), PROFILE_APPLY calls `PROF_AR3_APPLY` (bank 2 `B2_PROF_AR3`:
    the fixed ROM had no room - 32785 words with the code inline): a remembered ROM is
    loaded (CSR LOADING holds the Amiga, OK cold-boots it; a broken one: the line shows
    <Load>); without one the loaded ROM stays, and at boot the line shows ar3.rom if it was
    auto-loaded. B2_PROF_SAVED refuses a partition for it, as for the Kickstart. Fixed ROM
    32720/32768, bank 2 1977 words, HEAP 0xB4D1 + 17248 leaves 1695 stack words. Profiles
    TB scenario 17 (key 3 written and read back, the file has `ar3rom=`): red on the old
    table, green now; 17/17. PROFILE_APPLY's AR3 step is not in a harness. Firmware only
    (patch_firmware.sh); not yet on hardware.
  - **1 MB Kickstart for AROS (branch `aros` from main 33fdb93, 2026-10-19).** The user
    wants AROS as a Megamiga target; its ROM is 1 MB: a 512 KB extension at $E00000 and
    the main half at $F80000 (MiSTer's minimig_config.cpp UploadKickstart: file
    0..512K -> $E00000, 512K..1M -> $F80000). Minimig already decodes $E00000-$E7FFFF
    (gary `sel_kick1mb`, bankmapper bank 4, sram bridge A22..A19 = 1100 = SDRAM bank 0
    $600000-$67FFFF, free: chip 0000-0011, HRTmon 0100, AR3 0101, slow 1000-1010, kick
    1111), and every CPU reaches it over the chip bus (cpu_wrapper decodes nothing
    there; the TG68K turbo Kickstart is $F80000 only). Firmware: `KICK_PREP` (the only
    Kickstart load path: selector, profile Kickstart, kick.rom fallback) accepts 1 MB
    (`KICK_1M_HI`) and writes the file size into the CSR (FS_LO/FS_HI) before
    FAST_LOAD; WRN_KICK_SIZE names 1 MB. ROM 32724/32768. mega65.vhd: the CSR length
    (`qnice_req_length_o`, was open) = $100000 -> `qnice_kick_1mb`. amiga_sdram.vhd: the
    loader FIFO word grows to 37 bits (E0 = the word goes to $E00000, CLR = a 256/512 KB
    load); the mirror works per half unchanged (later words overwrite it); word 0 of a
    256/512 KB load waits until the writer has cleared the $E00000 half (256K words,
    ~0.15 s), so no AROS extension stays visible to Kickstart 3.x (MiSTer copies the
    512 KB ROM there instead; a real A1200 has nothing at $E00000). TB
    `~/aexp-work/aros` (run.sh, ghdl; sdram_ctrl stub recording the chipset-port writes,
    real loader + FIFO stub; runs on fedora with ghdl-llvm in a few minutes): 1 MB, then
    512 KB (cleared), then 256 KB (cleared + mirror), then AR3 64 bytes, no write
    outside the three banks: PASS; `mut.sh` 7/7 killed (no_e0, wrong_half, no_clear,
    no_redone, short_clear, no_mirror, no_gate).
    Build `aros-a` (154f721): with REF=linux040-d Vivado segfaulted in synthesis right
    after `read_checkpoint -incremental` of linux040-d's synth_1 checkpoint (hs_err,
    signal 11); again with an implementation-only reference (`~/builds/linux040-d-impl`:
    just the impl_1 link, so build_all finds no synthesis reference): WNS +0.086,
    WHS +0.010 at the first pass. Not on the hardware yet (aros-a ran Linux with
    Kickstart 3.1 there on 2026-10-19, so the 512 KB path with the clearing works).
    Merged into main 2026-10-20 (after 0.6.4 and the AR3 ROM per profile). One gap
    fixed on the way: the framework's boot-time auto-load of /amiga/kick.rom
    (CRTROM_AUTOLOAD) writes no file size into the CSR, so a 1 MB kick.rom came out
    wrong at power-on (second half over the first, $E00000 cleared); PROFILE_APPLY now
    opens kick.rom at boot and, if it is 1 MB, loads it again through KICK_PREP
    (`_PA_KNM`). Fixed ROM 32751/32768 - 17 words left: move code into a bank next.
    Build `main-b` (fc07dca, REF quickhdf-b, incremental synthesis + implementation):
    WNS +0.006, WHS +0.035, saved fedora:~/saved/main-b. Not on the hardware yet.
  - **68040 FPU hang: a released FP operation's answer in a flush clock (branch `fpbg` from
    main 4dac552, Minimig branch `fpbg`, 2026-10-26/27).** Reported with a patch by a user
    porting the AP68040 to a Mac core ("MegaMac", not public yet; MacBench's FP test and a
    plain FDIV loop hung). A register-destination FP operation (FDIV/FSQRT/FMUL...) is
    RELEASED at `accepted` and runs on in the background; `fp_bg` holds the next FP
    instruction at P_START until the unit's one-clock `done` (or enabled exception,
    `fp_exc_req`) clears it. Both clauses sat in EA-fetch's normal branch, below
    `if (wf_go)` / `else if (flush)`: an answer in an EX-redirect clock (every interrupt
    entry ends with one) or a store-fault clock was lost, `fp_bg` stayed set, and the next
    FP instruction waited for ever while interrupts were still served. The same branches
    also left `fp_pcap` (the FPU's "prepare the deferred exception's frame") standing
    through such clocks, so the unit captured the frame two or more times. Fix = the
    reporter's patch unchanged: both branches clear `fp_bg` on `done`, defer an exception
    (`fp_pend`/`fp_pvec`/`fp_pcap`) and drop `fp_pcap` as the normal branch does. Same
    code in upstream ranzbak/AP68040-pipelined.
    Bench `~/aexp-work/fpbg` (their `tb_fdiv_irq.sv` needs the 1-clock L1 stand-in and
    covers only `done` in a flush): `ap040_pipe_core` alone with BUS = 1, the real FPU, a
    memory answering the next clock (+LAT) that faults stores to $F000, a level-1
    interrupt every N clocks held until the handler acknowledges ($E100; +PULSE=1 their
    6-clock pulse). `prog.S`: 200 x FMOVE.X FP2,FP0 / FDIV.X FP1,FP0 (1000/3: a full
    28-clock divide - 1000/8 takes 5 and never overlaps an interrupt entry) / FILL integer
    instructions; variants d (plain), e (INEX2 enabled: every FDIV excepts in the
    background), w/we (+ a faulting store after the fillers), sb (the store before the
    FDIV). Checks iterations, interrupts, faults, FP exceptions = 200, FP0 = 333 and one
    frame capture per exception. `campaign.sh` (lists A-E, 6960 runs, fedora 16 jobs
    ~70 min): without the fix 1029 runs do not pass, 915 of them pass with it (A 337,
    C 290, D 12 - w hangs at 15/16 fillers and we - E 276): 714 hangs, each with an
    answer lost in a flush/wf_go clock, and 201 FAILs, each a repeated frame capture
    (captures != exceptions). With the fix A, C, D all PASS. Left over, the same on both
    RTLs: E 103 and B 10 hangs are
    interrupt starvation (a period at the handler's length: with 10x the clocks the
    worst one finishes), and B's one FAIL is the next bug.
    A late store fault (list D2, +SLAT delays only the faulting store's answer up to 6
    clocks): without the fix 17 hangs and 10 FAILs, with it all 468 runs pass.
    Mutants (`mkmut.py`, 16, on the 87-run red sample R.txt): 14 killed; the two
    survivors drop the `fp_bg &&` guard on the `done` clause (`flush-nobgterm`,
    `wf-nobgterm`), equivalent in these programs (no `done` arrives with `fp_bg` clear).
    Controls: the fixed RTL passes 87/87, the old one fails 87/87. Regression: ranzbak's
    `tb/run_pipe_tests.sh` 285 pass / 6 FAIL before and after (the same six bus tests
    berr_trace/berr_write that expect WB1, we report WB3 since 2887b7e); the Linux
    full-system benches exctest3/exctest2/exctest/bbtest reach C0DE. Amiga test
    `fdivtest` (in the build directory; vasm hunk exe, PASS under vamos): 10 rounds of
    1M FDIV.X and 1M FSQRT.X with AmigaOS's interrupts running, 333 and 32 expected.
    **Found on the way, fixed in a second commit (upstream too): the interrupt mask came
    from the wrong clock.** Exception entry took `x_lvl <= irq_lvl` (the live level), but
    the vector from `irq_take_lvl` (the previous clock's); an IPL change in exactly the
    take clock gave the handler a different mask. With the 6-clock pulse (B, d_1 at
    period 50) the level-1 handler ran with mask 0, nested at every pulse and grew the
    stack into the vectors (the bench's "access outside memory" at $20000000). On an
    Amiga: a level rising in that clock (CIA level 6 during a level-3 take) only delays
    levels 4/5 until the RTE; one dropping lets a handler re-enter itself. Fix:
    `x_lvl <= irq_take_lvl`. Bench: `prog.S` MASKCHK (variant m): each handler checks
    SR's mask = its level, a second level-2 source at $E102 (+PER2/+PH2).
    Lists M1 (6-clock pulse, periods 40..250) and M2 (level 2 every 397/531/663 clocks over
    level 1 every 110..200): before the mask fix 725 of 1477 and 256 of 855 runs report
    a wrong mask; after it none - M1's 24 remaining hangs are starvation (6-clock pulse
    at about the handler's length) and also fail before it, M2 passes 855/855. Mutants
    on M1+M2: back to `irq_lvl` killed (983 runs), mask 7 killed (2298), the larger of
    the two levels killed only by M2 (256 runs: the same runs as before the fix).
    Build `fpbg-b` (both fixes, REF main-b, NO_REF_SYNTH=1 - incremental synthesis
    segfaulted in fpbg-a): WNS +0.003, WHS +0.035, all constraints met; synthesis read
    both microcode files, 0 critical warnings. On the hardware (2026-10-27): `fdivtest`
    on a 68040 profile finishes all 10 rounds, PASS.
  - **Apidya ADF hang: the track engine skipped the sector after a short DMA (branch
    `apidya` from main e0ac508, 2026-10-27).** Reported on AExp too: Apidya (Quartex
    crack and other versions) hangs right after the bootblock, drive LED on. The
    bootblock loads a loader to $7E800. It reads stage 2 with whole-track DMAs
    (DSKLEN $1930); stage 2 ($7A666, loaded to $7A400) reads one sector per DMA with
    DSKLEN $821E, which is the sector after its first sync word plus ONE word. As soon
    as DSKBLK fires it re-arms the next DMA and decodes the previous sector. An
    unwanted sector restarts the DMA after its header. That extra word is word 0 of
    sector n+1's frame; Paula stores nothing beyond the length (`fifo_wr` gated by
    `~lenzero`), so the rest of n+1 is lost, but the engine still advanced
    `sector_next` past n+1. Paula arms the re-armed DMA only at word 1 of a later
    poll frame (1-2 ms: two 1 ms parks in ST_IDLE), so it got n+2. Sector 10's frame
    carries the track gap, so the engine served 0, 2, 4, ... 10, 0, 2 ... forever and
    the loader waited for the odd sectors of track 53. A real disk keeps rotating:
    the unwanted-sector restarts land mid-sector and catch the odd sectors on the next
    pass. Fix (`adf_track_engine.vhd`): keep Paula's DMA length from w2 of each sector
    frame (`frame_len`). When a frame continues a running session (`strm_cont`, cleared
    when a poll starts a session) and that DMA had at most 2 words left at w2, it ended
    in the preamble before this sector's sync, so `sector_next` stays on the same sector.
    The Hardware Floppy path (`ST_PHYS_*`) has no sector counter and is unchanged.
    Bench `~/aexp-work/apidya` (fedora, `rtest.sh`): minimig_m65 as an OCS A500 (fx68k,
    512K chip + 512K slow), the engine and amiga_config ghdl-synthesized
    (`flp_sim.vhd`), the ADF as the Avalon read model, a stub Kickstart that recreates
    the state after the bootblock and jumps to $7E800; tracers for the disk registers,
    Paula's DMA state and the engine's frames. 10 s of Amiga time takes about 8 min.
    Without the fix the loader is still cycling on track 53 at 10 s; with it, it leaves
    track 53 at about 4.1 s, depacks file 0 and the game code keeps loading
    (tracks 59..143) until the 10 s limit. `ENG=<vhd> ./build.sh <suffix>` swaps the engine.
    The ~2 ms re-arm after DSKBLK (ST_IDLE's 1 ms park, twice) remains: slower than a
    real Amiga, no hang. Build `apidya-a` (REF fpbg-b, incremental synthesis +
    implementation): WNS +0.020, WHS +0.035. On the hardware (2026-10-27): Apidya loads
    from the ADF.
  - **A damaged long file name crashed the file browser (branch `lfnfix` from main
    85fd76f, 2026-10-27).** A user got "FATAL ERROR: SD Card: Unknown error while trying
    to browse. Error code: 273F" and had to delete and recreate `/amiga` (no card image).
    The code is R11 of `DIRBROWSE_READ`, but every SD/FAT32 error is `0xEExx`: 273F is
    no error code. `FAT32$DIR_LIST` (QNICE library, also upstream) collects a long name
    on the stack, 13 words per record. When a later record of the run had a wrong
    sequence number or checksum, it skipped to the next entry without giving those words
    back, so its RET took a character of the name as the return address and the CPU ran
    into the firmware at random. A first record claiming more than 20 records (up to
    63) with a consistent run would also have copied up to 819 words into the 257-word
    name of the directory entry and onto the browser's 768-word stack. The same function
    looks up names for `FAT32$CD`/`FILE_OPEN` and lists `SDCard:`, so any of those could
    crash on that directory. Fix (QNICE fork `fat32-fastseek`): a broken run gives the
    stack back before skipping, then the entry shows its short name (as on Windows); a
    run of more than 20 records is skipped. What damaged the user's directory is
    unknown (interrupted write by any system, or the fork's write layer). Tests
    `M2M/QNICE/test_programs/fat32_lfn` (`run.sh`: 9 image cases with the stack pointer
    checked after every call; the old library fails all 7 damaged cases with the CPU in
    garbage; `mutants.py` 6/6 killed). Fixed ROM 32764/32768 words. Firmware patch
    `lfnfix-p1` into `apidya-a` (saved as fedora `~/builds/apidya-a-save`).
  - **AROS finds its hard disk on the Gayle (branch `arosdiag` from lfnfix 6dc43f3,
    2026-11-02).** AROS m68k (nightly 20261101: `aros-ext.bin` + `aros-rom.bin` from the
    boot ISO as one 1 MB Kickstart, ext first) booted, but its boot menu showed no DH0 and
    `Assign` only RAM Disk and the Kickstart. AROS's ata.device (`rom/devs/ata/lowlevel.c`,
    `ata_ReadSignature`) sends EXECUTE DEVICE DIAGNOSTIC (0x90) after the software reset
    when the signature is 00/00 and wants `(Error & 0x7f) == 1`; the firmware aborted
    0x90 (error 0x04), so AROS dropped the drive. Fix: the firmware answers 0x90 with
    READY, error 01, INTRQ and the ATA signature (count 01, LBA 01 00 00, device 00) in
    the task file (commit flags TF + IRQ, `IDE_NSIG`). Room: `IDE_IDENTIFY` moved into
    code bank 3 (`B3_IDE_IDENT` behind a FAR_CALL stub); fixed ROM 32629/32768 words.
    Bench `~/aexp-work/arosdiag/fw` (the quickhdf firmware bench + 0x90 checks,
    `fedora_arosdiag.sh`): all cases PASS, 27 mutants killed. Firmware patch
    `arosdiag-p1` into `apidya-a`. On the hardware (A1200 profile, Gayle, 68020 and 68040,
    with and without Zorro III RAM): DH0 is found and AROS boots into Wanderer from a 512
    MB RDB HDF (`~/aexp-work/aros-hdf/mkaroshdf.sh`). AROS itself is very slow (minutes
    to open a window; the UART diagnostics show the disk mostly idle and the CPU in AROS's
    ROM code on the chip bus) - the user does not pursue it further. Earlier runs gave
    "AFFS Write error 45" requesters and a bitmap block 0x444F5303 ("DOS\3") after a
    first boot (a full validation) had been reset midway; a diagnostics build
    (`arosdiag-p2`, not committed: firmware-path commands, firmware errors and the
    engine's taken/forwarded/failed counters on the UART) then showed a clean boot from a
    fresh image: 7300 commands, all READ MULTIPLE through the sector engine, none failed,
    only 0x90 x2, IDENTIFY and SET MULTIPLE 16 on the firmware path. Open: the AROS boot
    animation is garbled on HDMI only (VGA is fine).
- **Firmware patching without synthesis (2026-10-12).** `CORE/patch_firmware.sh
  save <dir>` keeps a build's routed checkpoint, bitstream and firmware images;
  `patch <dir> [out.bit]` assembles the current firmware, opens the checkpoint,
  verifies that the 16 QNICE ROM block RAMs (32K x 1 each, `ram_slice_begin` =
  bit) hold exactly the saved image, sets the new INIT_xx (computed by
  `patch_firmware.py`) and runs write_bitstream: about 2.5 minutes. An
  identity patch reproduced the build's .bit byte for byte except the header
  date. The read-only data (m2m-rodata) was a 700-cell LUT ROM; `i_rodata` now
  has RAM_STYLE_SELECT "block" so builds from now on can patch it too (older
  builds refuse a rodata change). Menu/help texts are in config.vhd = HDL.

- **RTG native resolution (branch `rtg-native` from fastdisk `a627e12`,
  2026-10-15, M2M exception 19 `rtg-native-modes`).** The user: RTG screens
  were scaled into the OSD's HDMI mode; the panel should get the screenmode's
  own resolution. Before: `qnice_video_mode_o` came from the HDMI radio only,
  ascal scaled the framebuffer (fb_* ports, exception 12) into it. Now
  `mega65.vhd` decodes the RTG registers (`fb_ena/hsize/vsize`, core clock,
  `p_rtgv`) into a mode code: 640x480 / 800x600 / 1024x768 @ 60 Hz, 1280x720
  @ 60 Hz, 1920x1080 @ 30 Hz, each also for its exact half (320x240 ...
  960x540); anything else stays scaled. `cdc_stable` into the QNICE domain,
  then the code must stay unchanged for 100 ms (`C_RTGV_SETTLE`; the driver
  writes width, height, enable one after the other and every mode change makes
  the display resync) before `qnice_video_mode_o` follows; `qnice_zoom_crop_o`
  = native, so ascal's output window is the whole picture (not the 4:3
  window of the 16:9 modes). ascal's accumulator starts at hsize + ihsize, so
  1:1 lands on phase 0 for every pixel (interpolating filters pass it
  through). Menu: `Settings > HDMI > RTG native resolution`, item 107 (was a
  Line: no renumbering, OPTM_SIZE 214 unchanged, +22 characters, demand 3608
  of MENU_HEAP_SIZE 3616). Framework (exception 19): VESA 1024x768@60 and
  1080p30 (VIC 34, 74.25 MHz like 720p) in `video_modes_pkg.vhd`, entries 7/8
  in framework.vhd + digital_pipeline.vhd; `video_out_clock.vhd` slot 011 =
  65 MHz (was 148.5 MHz, unused): M=39 D=4 CLKOUT0=3 CLKOUT1=15, values from
  Xilinx clk_wiz_v6_0 `mmcm_pll_drp_func_7s_mmcm.vh` (its lock/OPTIMIZED
  filter lookup reproduces every proven table entry: M=10/17/21/22/31/37/47)
  and the unisim MMCME2_ADV DRP readback; xsim of the real video_out_clock
  (scratch TB `tb_voc.vhd`, `~/drp/voc` on fedora): 74.25 -> 65.00 (x5 325)
  -> 40.00 -> 25.20 MHz, all lock. 1080p50/60 not possible: 148.5 MHz = 1485
  Mbit/s per TMDS lane (> the -2 OSERDES), the HDMI domain closes only at
  74.25 MHz, and 1920x1080x60 at 16 bit is ~250 MB/s of HyperRAM reads (the
  HyperRAM peaks at ~200 MB/s). Known: in 640x480 the 720x576 OSM is clipped
  (as in every M2M core's 640x480 mode). Build `rtgnative-a` (Fedora, R6):
  route WNS -0.496, phys_opt -0.092, failing paths only inside the 68040
  (`cpu_clk`, eaf_o -> fpc, 43 logic levels, 76 % route); HDMI domain met.
  Re-roll 8/16 (place ExtraTimingOpt, route Explore, phys_opt
  AggressiveExplore) passed: WNS +0.007, WHS +0.025, bitstream md5
  `fa790b74`, in `~/aexp-builds/Megamiga-rtgnative-a/`. Hardware (2026-10-15,
  the user): the RTG modes come out natively on the monitor, 1024x768 included;
  the OSM keeps its size in every mode (hardware-scaled overlay).
  1080p30 field report: now and then the picture is pushed down a bit, then
  restored. Cause: a 1:1 line at 1080p30 is 3840 bytes = 30 ascal bursts of 128
  bytes per 29.6 us line (~130 MB/s, ~85 % of the HyperRAM with its latency per
  burst); the framework arbiter alternated fairly between ascal and the core
  (RTG write combiner/blitter, 1..16-word bursts each paying the full latency),
  so under RTG traffic a fetch ran past the next line sync; ascal's `o_hsp` is a
  flag, the second sync was lost, `o_vacpt` fell one line behind and the rest of
  the frame showed row y-1 until the next frame re-initialised it. Fix (the user
  chose priority + catch-up, exception 19 extended): `avm_arbit` `G_PRIORITY_S1`
  / `avm_arbit_general` `G_PRIORITY_HIGH` (ascal first; only the RTG masters and
  QNICE share `hr_core`, both just wait) and ascal's `o_hspn` (up to 3 pending
  syncs, worked off in `sDISP`). TB `~/aexp-work/arbprio` (3 random masters +
  a pipelined scaler like ascal's `o_readlev<2`, shadow-checked data, ghdl): no
  data errors either way; worst scaler line 2420 -> 2100 cycles with priority
  (= the bus held for the whole line). TB `~/aexp-work/ascalcatch` (ascal
  framebuffer 256x64 16bpp 1:1, memory stall of ~2 lines in frame 3): original
  ascal 43 wrong lines (21..63 show the row above = the field symptom), patched
  4, other frames 0; stall sweep (avalon cycles, orig/new wrong lines): 0: 0/0,
  300: 0/0, 2500: 43/11, 5000 (~9 lines, more than the 3 pending syncs): 43/43.
  Noticed on the way: ascal's `o_hburst`/`o_hbcpt` are
  `0 TO 31`, i.e. at most 31 x 128 bytes per line - a 32bpp line wider than 992
  pixels does not fit (pre-existing, not touched).
  Build `rtgnative-b`: incremental from `rtgnative-a`'s re-roll checkpoint,
  met timing on the first pass (WNS +0.007, WHS +0.025, no re-roll); pushed to
  the MEGA65 for the 1080p30 field test.
  Field (2026-10-15): the 1080p30 jitter is gone, blitting feels fine. Seen
  once after much screen-mode switching: two faint one-pixel dotted rows near
  the bottom of the 1080p Workbench backdrop (a window hides them, they are
  back after it moves away). Not chased (user: probably the mode switching);
  if they come back: A/B against `rtgnative-a`, or a screenshot from the Amiga
  (in it = memory/picture, not the scaler).

- **32bpp wide lines (2026-10-15):** the user confirmed 1024x768x32 broken,
  24 bit fine. Cause 1: ascal's `o_hburst`/`o_hbcpt` are `0 TO 31` (1024 x 4
  bytes = 32 bursts of 128 does not fit). Cause 2, the real limit: the
  HyperRAM controller (16 bit DDR at 100 MHz, latency 4, ~13 clocks overhead
  per 64-word burst) gives ascal ~160 MB/s; 1024x768x32@60 needs ~198 MB/s
  (4096 B x 48.4 kHz), 1280x720x24 ~173, 1080p30x24 ~194, while 1024x768x24
  needs ~149 (works) and 1080p30x16 ~130 (works). So a wider counter would
  enable no mode that the bandwidth can feed. User decision: not fixed for
  0.6.3, documented (README table: 24 bit up to 1024x768, 32 bit up to
  800x600). Possible later: Megamiga.card MaxHor/VerResolution per RGB class,
  so P96 does not offer those modes.

- **Rebased onto main = 0.6.2 (2026-10-15)** for 0.6.3: config.vhd conflict
  (the cartridges renumbered the menu): the RTG toggle is now line 120 (the
  Line before "Back to Settings" in the HDMI submenu), `OPTM_G_RTGNATIVE` 57
  (the cart took 52..56), `C_MENU_RTG_NATIVE` 120. Menu heap: the cart left
  headroom 5, the toggle text needs +22: demand 3889, MENU_HEAP_SIZE 3904,
  release HEAP_SIZE 14624 (combined total 18528 unchanged). CORE_VERSION
  0.6.3, help page 5 got two lines about RTG native resolution (in place of
  the footer padding). Old tip kept as local branch `rtg-native-prerebase`.

- **MEGAMIGA 0.6.4 RELEASED (2026-10-19, tag `V0.6.4` on main, GitHub release asset
  `Megamiga-0.6.4-R6.zip`, R6 only).** Everything on main since 0.6.3: the A4000
  profile, dev-0.7.0 (Gayle IDE, READ/WRITE MULTIPLE, CHS in the engine, turbo
  Kickstart), ADFs straight from the SD card, the IDE data stream, IDE DMA + SD at
  50 MHz, the plain line doubler, 48 MB Zorro III, the menu rows (drive sound,
  settings signature), the 68040 fixes for Linux, RDB-less HDFs (vrdb), profiles as
  files and the quick HDF. Not in it: AROS's 1 MB Kickstart (branch `aros`, not yet on
  the hardware; the user: skip it). Release bitstream = `quickhdf-b` (REF main-a,
  WNS +0.088, WHS +0.036), hardware-confirmed by the user before the release; its
  sources equal the release commit except docs. Package: the DMA lide.rom ("Megamiga
  DMA 1", lide.device fork branch `megamiga-dma` 51862e4, pushed for the release),
  Megamiga_RTG.adf rebuilt (the Megamiga.card that reports no card with the Graphics
  Card off - not tested on hardware), Net/Share ADFs unchanged, settings file 182 bytes
  of 0xFF (a new file: no signature warning), README.txt and notes064.md in
  `~/aexp-builds/release/`. The 0.6.3 settings file is reset by the signature, the
  per-profile files of 0.6.3 are not carried over (release notes say so).

- **MEGAMIGA 0.6.3 RELEASED (2026-10-16, tag `V0.6.3` on main, GitHub
  release asset `Megamiga-0.6.3-R6.zip`, R6 only).** RTG native resolution
  (M2M exception 19) with the 1080p30 fix (ascal first at the HyperRAM, line
  sync catch-up). Release build on the Fedora host (rel063), incremental from
  rel062 (`REF=rel062`): first pass WNS +0.011 / WHS +0.007, no re-roll,
  Shell ROM 31331/32768. The user on the release build: "It all works"
  (freezer cartridges, RTG native modes incl. 1080p30, the menu switch, help
  page). Settings file 229 bytes, same layout as 0.6.2: a 0.6.2 file may be
  renamed (RTG native then OFF: line 120 was a Line). Submodules unchanged
  (Minimig `cart` ec7b7f0, QNICE 75873a2). Package README.txt and notes063.md
  in `~/aexp-builds/release/`.

- **A4000 profile, A600 with 2 MB Chip RAM (2026-10-16, branch `a4000` from
  main = 0.6.3, CORE_VERSION 0.6.4).** User request: a fourth machine profile
  A4000 (68040, AGA, 2 MB Chip, Zorro III RAM on; Slow RAM, Zorro II Fast RAM
  off; cartridge None) and the A600 default Chip RAM 1 MB -> 2 MB (A500 and
  A1200 unchanged). Menu: " A4000 (AGA)" is line 13 (`C_MENU_PROF_A4000`),
  the separator under the radio moved to 14 (build a4000-a had the A4000 in
  the separator's place because the OPTM_DY comment claims the main view is
  at its 34-line ceiling; that is stale since the Settings submenu - the main
  view is ~21 lines, the tallest view is Profile Settings with 27; the user
  missed the separator), the A4000 block is lines 77..94 in Profile Settings
  (`C_MENU_PROF_BASE` 23 + 3 x 18, groups `OPTM_G_P4*` 58..64, `OPTM_DEP`
  item 3 - the last item a dependency mask can name); everything behind moved
  by 19, OPTM_SIZE 229 -> 248 (the 256-bit osm_control leaves 8). The
  settings-file layout changed in the middle, so CORE_VERSION 0.6.4 (a new
  file name: an old file would load with the lines behind 76 shifted - the
  `_HLP_CA_OLD` path only handles growth at the end). Firmware: the profile
  index (boot in PREP_START, `_PR_CUR`) adds 3 x A4000, keys `a4000.hdf0`/
  `.hdf1`/`.kick` (PROF_KEYTAB row 3). Menu heap: +271 characters, +4 x 19
  array words: demand 4236, MENU_HEAP_SIZE 4256, headroom 20, release
  HEAP_SIZE 14272 (combined total 18528 unchanged); Shell ROM 31338/32768.
  The settings text (CFGS_MAXC 511) now holds 12 profile paths: ~29
  characters per path on average, enough for the usual `SDx:/amiga/...`
  paths; when full, a choice is not remembered (CFGS_SET C=0), as before.
  The A4000 is the A1200 chipset with the 68040: no Ramsey/Fat Gary/A4000 IDE,
  so the README recommends an A1200 3.x Kickstart (A4000 ROM untested).
  **Found on the way (since 0.6.1):** `C_MENU_OSM_SCALING`, `C_MENU_VOLUME`
  and `C_MENU_STEREO` were 2 lines too low - a638be1 (the "SDCard: inserted"
  toggle and its line) shifted the menu but not these three subtypes (later
  edits kept the offset). Each range started at the submenu headline: Volume
  100% (the default) played at 90%, 5% and 0% did nothing; OSM Scaling and
  Stereo Mix were two steps off. Fixed (+2 on top of the +19). The README's
  blind DVI steps (Mount SDCard was not counted either) now say 8 x down.
  Checks: a menu script (every `C_MENU_*` against the text of its line, the
  four blocks' defaults and OPTM_DEP items), ghdl analysis of config.vhd /
  mega65.vhd, make_rom.sh; firmware TB `~/aexp-work/fw-a4000` (fw-prof2 +
  A4000 steps 3b/3c: the A4000 loads its own Kickstart and master, none of
  the A1200's files, and the A1200 gets its own back): PASS; mutant
  "A4000 row = A1200 keys" fails 3 checks.
  Build `a4000-a` (Fedora, `REF=rel063`): first pass WNS +0.038 / WHS +0.007,
  no re-roll, Shell ROM 31338/32768. On the MEGA65 (user): the separator
  under the profiles was missing, and "lots of empty space between Close Menu
  and the status bar" - OPTM_DY was still 34 while the main view has 20..22
  lines and the SD status is painted on the frame's bottom row. Fixed: the
  separator is back (line 14) and OPTM_DY 34 -> 29 = the tallest view
  (Settings, counted by hand: headlines/lines/submenu labels of Display,
  Audio, Keyboard, Ports + Back = 29).
  Build `a4000-b` (`REF=rel063`): first pass WNS +0.002 / WHS +0.007, Shell
  ROM 31338/32768; pushed with the 248-byte megamiga-0.6.4.cfg.
- **PrismRTG driver (2026-10-16, branch `prism-rtg` from main, no HDL/firmware
  change).** User: "an open source RTG host would serve us well" - PrismRTG
  (github.com/lainejones/PrismRTG, GPL-3.0-only, 1.1 beta 9) replaces
  Picasso96 with its own cybergraphics/Picasso96API libraries and loads board
  drivers as modules (`LIBS:Prism/NAME.driver`, board ABI 3 / protocol 4,
  frozen since beta 8). `CORE/prism/drv_megamiga.c` = `MEGAMIGA.driver`: found
  by `driver_find(2011, 102)` (the Z3 RTG board, so 020/040 profiles only) +
  ID `$4D01`; regs at board+$400100, palette +$400400, blitter +$400800 (ID
  `$B11B` gates the ops); VRAM = board offset 0, 4 MB minus 128 KB (two 64 KB
  template scratch halves at the top, as Megamiga.card does). Formats = the
  four Megamiga.card has shown since 0.4 (CLUT8 3, RGB565LE 4+16, BGR24 5+16,
  RGBA32 6; rtg.v keeps FORMAT[4:0], so Megamiga.card's +32 is dropped
  anyway); STRIDE is its own register, so autoscroll (`pitchPixels`) works;
  checkMode refuses modes bigger than VRAM. Ops fill/copy/expand (no 24-bit
  fills/text: no 3-byte pattern), asynchronous with `waitBlit`, every wait
  bounded (2M polls -> PR_FAILED / PBF_ACCEL_BROKEN). No sprite, vblank or
  DPMS (the card has none). Built with bebbo gcc 6.5 in podman on fedora
  (`sacredbanana/amiga-compiler:m68k-amigaos`, `CORE/prism/build.sh
  CONTAINER=podman`), 9892 bytes (13688 with the probe diagnostics). Host fixture `CORE/prism/test_megamiga.c`
  (`test.sh`, vamos from amitools git master in fedora:~/amitools-venv,
  `-m 10240` - more RAM refuses with hw access): mode/palette/display-start
  registers + a C model of rtg_blitter.vhd, 3000 random fills/copies/texts
  byte-compared with the CPU: PASS; mutants (no bottom-up copy, 16-bit
  pattern unshifted, JAM2 inverted, 565 swap bit, template stride, overlap
  accepted) 6/6 killed. Test disk `CORE/prism/Megamiga_PrismRTG.adf`
  (`make_adf.sh`: release drawer + our driver in its Drivers, PrismCheck kit
  built from source). **Hardware, first try:** after install + reboot no RTG
  screen and Prefs/ScreenMode quit silently (OS 3.1 and 3.2; P96 monitor was
  parked correctly). The probe got diagnostics (board address, ID, blitter ID
  printed once the ConfigDev is found). Then, after the user reloaded the
  core, it worked - cause unknown (stale core/board state?). Watch for a
  repeat; the probe line and `C:PrismD BOARD=MEGAMIGA LOG` are the first data
  to get. Narrowed by the user: works on the 68020, NOT on the 68040 (where
  Picasso96 + Megamiga.card works). Also explained: PrismRTG's boot failsafe
  (`ENVARC:Prism.booting`, cleared after 3600 VBLs = 72 s) skips every boot
  after one that was rebooted early or where PrismD quit. Ruled out in
  simulation: MOVE16 to/from the RTG board (PrismD CopyMems VRAM a lot) -
  `~/aexp-work/cpu060/e2e040m16` (e2e040 + MOVE16 Z2->board, board->Z2,
  board->board, Z2->$02000000; RTL of dev-0.7.0, GAYLE=0): CPU40 PASS.
  Last data (68040, `C:PrismD BOARD=MEGAMIGA LOG` from a LMB boot): PrismD
  reaches "running" (driver found, modes built), but Prefs/ScreenMode still
  quits silently and the log shows only five `ChangeExtSprite` lines (the
  Intuition pointer) - no `FindDisplayInfo`/`GetDisplayInfoData` for any
  Prism ID, so ScreenMode gives up BEFORE it asks PrismD about a Prism mode.
  PrismD has no 68040-specific code (its trampolines are static `stubs.S`
  code installed with SetFunction; only the ZZ9000/Z3660 drivers call
  CacheClearU). **PAUSED here 2026-10-16 (user: "I don't feel like hunting
  right now").** Next steps, in this order: (1) on the 68040, ScreenMode
  with NO PrismD (LMB boot) - if it quits too, the fault is the 68040 setup,
  not PrismRTG; (2) the trace build `PrismD.trace` (PrismRTG
  `tools/mktrace.sh ALL`, whose source list is stale: add `src/cgxvideo.c`,
  `src/arexx.c` and `-lm`; built on fedora with PATH
  `/opt/m68k-amigaos/bin`) logs every graphics.library call as `g-<LVO>`:
  `Run >RAM:trace.txt RAM:PrismD.trace BOARD=MEGAMIGA LOG`, start
  ScreenMode, the last `g-` lines say where it stops; (3) only then the
  unverified ideas: the 5 s monitor timeout / probe order, the driver's
  CopyMem in expand (Megamiga.card uses a move.l loop), the board's MMU
  mapping under 68040.library on real hardware (the sim used TTRs). Also
  still to do: the PrismCheck tests (tmpltest, p96test, vramcheck,
  PrismBench) and a "Use blitter" off check on the 68020; then perhaps an
  upstream PR to PrismRTG (prismsetup.c/prismprobe.c board tables, build.sh,
  mkpkg.sh, README). The working copy of PrismRTG is
  fedora:~/prismbuild/PrismRTG (1.1 beta 9, `f44c4cc`). Status: works on
  the 68020, NOT on the 68040; not for release.

- **ADF images straight from the SD card (2026-10-17, branch `floppy-direct` from main
  `4dc1fdd`, night pass).** User: "with better SD card speed, would it be possible to use
  unbuffered diskdrive emulation?"; reasons: the AExp upstream (no SDRAM) could one day
  drop its HyperRAM pools, and the floppy half of SDRAM bank 0 (column bit 9 = 1, 8 MB)
  becomes free for more Zorro III RAM. No upstreaming effort now ("something to keep in
  mind"). Design (one-track buffer, not strictly unbuffered: trackdisk reads a track,
  re-reads are common, and an SD card can stall for 100+ ms):
  - `CORE/vhdl/adf_sd.vhd` answers the track engine's UNCHANGED Avalon port
    (`pool base + track x 2816 + sector x 256 + word`; the drive from address bits
    21:19, the sector = bits 18:8) from a 4K x 16 dual-clock block RAM holding the
    eleven sectors of one track of one drive (tag drive/track, valid + dirty per sector).
    The engine side (core clock) asks the QNICE side per sector with a toggle request
    (PREP_RD / PREP_WR / COMMIT; payload stable while the toggle crosses, CORE.xdc's
    qnice<->main max_delay covers it). PREP_RD of an invalid sector loads every invalid
    sector of the track, usually one CMD18; PREP_WR of a dirty sector writes the dirty
    sectors back first (an engine that aborts mid-sector must not lose a committed
    sector - found while planning the TB), then invalidates the sector; COMMIT marks it
    valid + dirty. Write-back: before the buffer changes tags, 20 ms after the last
    commit (a trackdisk track write leaves as one CMD25), or on the firmware's FLUSH.
    Translation: the FAT32$FILE_MAP extent map (firmware, up to 511 extents per drive,
    8K x 16 block RAM for three drives) + base/shift/sectors/slot registers, the lookup
    copied from ide_engine (E_LOOK..C3). Preemption by QNICE commands: the rest of a run
    is looked up and started again. Errors: G_RETRIES = 2 retries 1 ms apart; a
    controller that is not ready (sdhost re-initialises the card after a failed transfer
    in the other bus mode, or no card) is waited for up to 500 ms of WALL time from the
    first "not ready", the port released meanwhile, without using a retry - the long TB
    found loads that failed three times in a row while the controller recovered from an
    injected CRC error, and then (seed 777, no tray card) a FLUSH that never ended because
    the first version counted the wait in retries, each of which also waited for the busy
    IDE client. A sector that cannot be
    read is served with `avm_rderr` -> `adf_track_engine` sends it with a wrong data
    checksum (new input `avm_rderr_i`, default '0'; the only engine change), so the
    Amiga gets a read error, never silently wrong data; a write that fails for good is
    dropped and sets the drive's FAULT bit. QNICE registers in windows 0xFFFD (MODE,
    SECTS, BASE, SHIFT, STATUS, FLUSH, statistics 0x10..0x15) and 0xFFFC (map) of each
    ADF device (C_DEV_AMIGA_ADF0/1/2); the mount wrapper keeps 0xFFFF (CSR, size
    validator -> mounted/tracks) and 0xFFFE (WR_EN; its dirty bitmaps are unused).
  - `CORE/vhdl/sd_eng_arb.vhd`: the SD host controller's single engine port shared by
    the IDE sector engine (owner by default) and adf_sd (asks with req, holds it per
    operation). Lock from a start pulse to done; hand-over to adf_sd in two steps (one
    clock with the IDE side frozen) because a client decides on busy in one clock and
    pulses start in the next - the first TB run showed the lost start. `ide_engine.vhd`
    got `sd_gnt_i` (default '1'): E_DECIDE waits for the port, because sd_ready_i
    belongs to the owner's slot.
  - main.vhd: no avm_cache (and no cache flush) any more - adf_sd checks drive and
    sector on every access. mega65.vhd: adf_sd + arbiter, the ADF devices' windows
    0xFFFC/0xFFFD decoded to adf_sd, the drive LED's "unsaved" (green) = adf_sd dirty.
  - Firmware: `ADF_TB_SETUP` (map via FAT32$FILE_MAP into window 0xFFFC, base =
    DEV_CLUSTER - (2 << shift), sectors = size >> 9, slot, mode last, handle to EOF so
    the Shell reads EOF at once - mounting is instant now), `ADF_TB_SYNC` (FLUSH + wait,
    ~1 s bound), `ADF_TB_OFF`. PREP_LOAD_IMAGE: SYNC + OFF of the old file instead of the
    FLUSH_ADF_STEP loop, ADF_TB_SETUP instead of FAST_LOAD (FAST_LOAD stays for the
    Kickstart); new text WRN_ADF_FRAG (> 511 extents); WRN_ADF_DUP shortened.
    ADF_UNMOUNT: SYNC (or drop on a card change) + OFF. HANDLE_CORE_IO: a new generation
    of a drive's card now also switches the drive off and EJECTS it (the image is gone
    with the card); the background flush (step 3) and FLUSH_ADF_STEP are gone,
    ERR_ADF_FLUSH removed. Shell ROM 31694/32768 words.
  - IDE boot ROM: `CORE/vhdl/flp_bram.vhd`, the old arbiter tree now ends in a block
    RAM slave (16K words at C_HMAP_IDE_ROM, byte enables, bursts; other addresses read
    0) instead of amiga_sdram's floppy port, which is tied off. Nothing uses the SDRAM
    floppy half any more. BRAM: was 116/365 tiles.
  - Tests: `~/aexp-work/adfsd` (tb_adfsd: engine BFM with the engine's exact access
    pattern -> adf_sd -> sd_eng_arb -> sdslots with two real sdhost -> two card models;
    an IDE-engine stand-in on the shared port; a firmware stand-in preempting with
    QNICE reads, mounting, FLUSH/STATUS; three drives: 160 tracks fragmented on the back
    card (4 KB clusters), 40 tracks with ~100 extents on the tray card (512-byte
    clusters), 30 tracks + 5 sectors; every read compared with a reference, every card
    block compared at the end; SCEN 0 with injected read/write CRC errors, SCEN 1 no
    tray card; ops: track reads in rotation order, aborted reads/commits, track writes,
    write + aborted rewrite + read back, timed write-back, FLUSH, eject/remount, another
    file into a drive, Amiga reset, the same sector through two drives; `run.sh`,
    `multi.sh` seeds, `mut.py`); `~/aexp-work/fw-adfsd` (QNICE emulator: ADF_TB_SETUP on
    generated FAT32 images, 1/8 and 64/4 sectors per cluster, contiguous, 7 and 150
    extents, 600 extents refused; hostcheck translates every sector through the
    map/registers the firmware wrote and compares the image block; SYNC/OFF;
    `mut.py` 9/9 killed); `~/aexp-work/flpbram` (20000 random ops, mutants 3/4 - the
    survivor, waitrequest never raised, needs a master that pipelines into a burst).
    tb_adfsd mutants (`mut.py`, 14): killed - no write-back before a tag change, PREP_WR
    keeps the sector valid, no write-back of a dirty sector before PREP_WR, COMMIT not
    dirty, byte swap, no read error flag, run past the extent end, preemption restarts
    the whole run (hangs), no backoff, no arbiter lock, no invalidation on a
    configuration write (needed the "another file into a drive" op), arbiter without
    the freeze (needed a hostile IDE stand-in that decides in exactly the clock adf_sd
    raises its request, plus an end-of-test check that the stand-in is not stuck in a
    transfer). Equivalent, survive: the byte select of the SD write data unregistered
    (sdhost holds each write address two clocks, so it reads the same byte), word 0 of a
    sector always asking again (only protects against configuration changes, which the
    generation toggle already covers). Regressions 600 ops x 2 scenarios: 3 seeds pass
    before the hostile TB; on the final TB seeds 44/55 pass scenario 0, seed 66 failed:
    after enough injected CRC errors sdhost has used up its fallbacks (native -> SPI 25 ->
    SPI 12.5 MHz, one per error) and stays in error until QNICE resets it - documented
    sdhost behaviour (`~/aexp-work/sdhost` SCEN 0), and the firmware resets a controller
    only when it mounts a card, so on hardware three SD errors since power-up leave the
    card dead for the IDE engine and the floppy alike until it is re-inserted (an open
    firmware item, not new here). The TB now injects at most two errors per run: seeds
    66 and 77 then PASS scenario 0 (600 ops); seeds 44/55 PASS both scenarios.
    **Open firmware item:** reset a controller whose error bit (register 5 bit 14) is set
    while its card is present.
  - Builds (fedora, R6, REF = main-merge-b): **fd-a** = the floppy part (with the first,
    retry-counted ready wait), first pass WNS -0.073 (the known TG68K -> sdram_ctrl
    paths), re-roll 1/16 PASS WNS +0.011 WHS +0.007, BRAM 122/365 (+6). **fd-b** = final
    (time-bounded ready wait + IDE ROM in flp_bram), REF = fd-a, WNS +0.009 WHS +0.007
    first pass, BRAM 130/365. Bit + .cor (coretool, version "0.6.4-fd-x") in
    `~/aexp-builds/Megamiga-fd-{a,b}`. HW-confirmed by the user 2026-10-17 (fd-b over JTAG; "Everything tested and seems to
    be working fine"), merged into main.
  - Next: Zorro III RAM 16 -> 48 MB from the four free upper column halves, survey in
    `doc/developers/z3-48mb-plan.md`.

- **Analog Standard VGA: every hires pixel (2026-10-16, branch
  `eval-linedoubler` from main, upstream AExp `f4b5fdb` = WIP-V2-B2, AExp
  issues #35/#36).** Upstream found that hires screens lose every second pixel
  column on the analog output in the Standard VGA mode: the framework's
  scandoubler doubles lines with MiSTer's Hq2x, which spends four clock enables
  per input pixel, and the core enables hires pixels at 14.19 MHz on the
  28.375 MHz video clock - two. Megamiga is affected identically (same
  `video_clk_o <= main_clk`, same `video_ce_o`, scandoubler.v/video_mixer.sv/
  hq2x.sv byte-identical to upstream's before the fix), and additionally its
  SuperHires lines, whose averaged pixel pairs ride the same 14 MHz enable.
  HDMI and both 15 kHz modes bypass the scandoubler (not affected, which is
  why nobody noticed). Taken over: the framework part (M2M exception 20
  `line-doubler`: `scandoubler.v` `LINEDOUBLER` + the plain line doubler,
  `video_mixer.sv`, analog_pipeline/av_pipeline/framework generics),
  `VGA_LINEDOUBLER true` in globals.vhd, the comments in main.vhd (merged by
  hand with the SuperHires note) and upstream's bench `CORE/sim/video/`
  (`run_scandoubler.sh`, `check_scandoubler.py`, two TBs); not taken: AExp's
  docs, CORE_VERSION, `run_all.sh`/`run_long.sh` (Megamiga has no CORE/sim
  gate). Quick bench on Megamiga's sources (incl. the AGA Minimig raster,
  `q_minimig` 574/574 lines complete): all 9 line-doubler checks PASS; the two
  Hq2x red controls (`q_hires_red`, `q_lores_same`) do not elaborate on Icarus
  12.0 (`hq2x.sv:40`: whole-array assignment not supported), so the red half
  is unproven here - upstream ran it on a newer Icarus.
  Build `linedbl-b` (Fedora, `REF=a4000-b`) failed in place_design: "Could not
  place all LUTRAM shapes" - upstream forces the two 1K x 24 halves to
  distributed RAM (AExp's BRAM is full), 256 RAM64M that the reused placement
  had no room for (LUT as memory 2867 -> 4162). A fresh build (`linedbl-c`)
  placed but missed timing in the 68040 (WNS -0.410, re-rolls). So the halves
  are block RAM in Megamiga (`ram_style = "block"`, original kept as a
  comment), which keeps the LUTRAM layout of the reference builds. Collision
  safety: both halves are read every clock, pix_out shows only rbuf_d's half,
  and the write half we_b is never that half in the same clock (also not in
  the swap clock). Proof: the quick bench on a copy whose read returns X when
  it hits the address written in the same clock (worst-case BRAM collision):
  9/9 PASS; mutant "write half = read half" on that copy: 9/9 FAIL.
  Build `linedbl-d` (Fedora, `REF=a4000-b`): first pass missed, re-roll 2/16
  (placement kept, route_design NoTimingRelaxation) WNS +0.050 / WHS +0.007,
  0 routing errors, BRAM 110.5 (a4000-b 116), LUT as memory 2854 (2867),
  Shell ROM 31338/32768. `linedbl-c` (LUTRAM, fresh placement) stopped after
  2 failed re-rolls (best WNS -0.410). Loaded onto the MEGA65 over JTAG;
  awaiting the field check (hires/SuperHires on analog VGA Standard).

**ADF floppy milestone history (2026-07-03).** Read-only ADF
support verified on real R3 hardware: Workbench 1.3.2 boots to the
desktop, demoscene trackloaders run (State of the Art, Batman, TBL Eon).
Mount via OSM " ADF:" → Shell streams to HyperRAM (QNICE device 0x0103,
`adf_mount_wrapper.vhd`) → `adf_track_engine.vhd` serves Paula over the
IO_FPGA host channel with bit-exact minimig_fdd.cpp MFM encoding. Design
spec: `.research/INTEGRATION-SPEC-floppy-adf.md` (supersedes the vdrives
advice). Milestone 1
(Kickstart hand, 2026-06-10/11) preceded it. Timing closed (run 3: all
AExp-owned groups ≥ +0.24 ns; global WNS +0.017 ns sits on the framework
HyperRAM PHY path). **Interlace weave deinterlacing shipped 2026-07-04**
(minimig `field1` → `video_fl` chain → ascal `i_fl`, `INTER => true`;
verified on R3 hardware — Batman Rises' laced intro is stable; commit
29c1aa2, WNS +0.108 ns). **VGA analog modes +
OSM restructure implemented 2026-07-04** (VGA: Standard / 15 kHz HS+VS /
15 kHz CSYNC radio, C64MEGA65-style decode + retro15kHz OSM-CE in
main.vhd; filter submenu now directly under the HDMI resolution submenu;
Audio-improvements item removed, `qnice_audio_filter_o` tied '0';
OPTM_SIZE 35→44) — synthesized (WNS +0.165 ns, BRAM unchanged) and
verified on R3 hardware 2026-07-04. Firmware OSM
constants are now autogenerated like in C64MEGA65 (`make_rom.sh` →
`osm_const.asm`; refactor proven ROM-byte-identical); the settings file
is generated by `make_release.py` at packaging — the tracked `aexpcfg`
master was removed. **Screen adjustment (issue #5): HDMI crop is
hardware-verified (2026-07-09, both outputs of the old increment). The old
"VGA centering" was an RCA-confirmed false positive — the soft blank only
crops, it never pans. Replaced 2026-07-13 (A9) by a TRUE analog
positioner — implemented + sim-proven (5-scenario nvc TB), NOT yet
synthesized/hardware-tested.** New generic
`M2M/vhdl/av_pipeline/analog_positioner.vhd` (M2M-UPSTREAM screen-center, in
all four .xpr): post-OSM, pre-CSYNC edge rescheduler that shifts HS/VS phase
vs. final RGB (delay = predicted period − pan; two-back VS predictor keeps
interlace half-line phase + parity; width-exact per-pulse delays; seamless
engage/bypass; porch-measured H clamps from post-crop DE + structural
line/8, V ±64 lines; pan=0 = combinational bypass → other cores
bit-identical). Units mode-normalized via `doubled_i` ← scandoubler: pan_x =
1 hires px, pan_y = 1 line in ALL three VGA modes. Data path: v4
`aexp_screen.cfg` (84 B, per-mode rows [4 HDMI][4 overscan][2 pan]; firmware
still accepts v3, pan=0) → `LOAD_SCREEN_OFFSETS`/`DETECT_SCREEN_MODE` → CFD
gp_reg words 8-9 → `i_qnice2video` CDC (142→166). The soft blank stays as
honest analog OVERSCAN (crop/reveal borders) and was hardened: reset +
geometry-acquisition gate, clamped edge targets (no more
permanent-blank/12-bit wrap). Tool v4 (grouped UI, --pan-x/-y, --reset,
--copy-from, direction echo, v3 migration, `test_aexp_screen_cfg.py` = 25
tests); presets regenerated v4; `doc/screen_adjust.md` rewritten around
position/overscan/no-true-scale. Interactive OSD adjust still pending. **HDMI flicker-free (issue #12)
— Increment 1 implemented 2026-07-09, statically verified (nvc analyze +
elaborate against the real `clk`/`cdc_stable`; adversarial swarm) but NOT
yet synthesized/hardware-tested.** CORE-only (clk.vhd + mega65.vhd +
config.vhd + CORE.xdc; zero M2M/.xpr/firmware edits). A second MMCM
`i_clk_fast` = 28.437500 MHz (313-line = 50.030 Hz, above 50) + a
glitch-free `BUFGMUX_CTRL` are dithered native↔fast by a 2-state FSM in
the `hr_clk` domain driven by the already-plumbed ascal over/underflow
loop (`hr_high_i`/`hr_low_i`, mega65.vhd:97-98) → the core's time-average
frame rate is exactly 50.000 Hz; interlace already averages 50.000 and
settles on native (zero dither). **Direction inverted vs C64MEGA65:
native 49.92 is BELOW 50 → the twin is FASTER.** HDL-read OSM toggle
"HDMI: Flicker-free" (top-level between the HDMI Filter and VGA submenus,
single-select default ON; `C_MENU_HDMI_FF`=25, OPTM_SIZE 41→42, OPTM_DY
12→13, VGA `C_MENU_*`/lines +1; ships in the unreleased `WIP-V1-A6`, no
version bump). CORE.xdc times
the fast leg (`set_case_analysis 1` on `hr_core_speed_reg[0]/Q`,
`create_generated_clock` on `i_clk_fast/CLKOUT0`) — the leaf names
`i_clk_fast`/`hr_core_speed` are load-bearing (a "no pins matched" warning
silently no-ops STA). Recommend FF OFF for VGA/15 kHz (H-sync frequency
step). Real synthesis risk = the R6 global HyperRAM-PHY WNS (+0.058 ns
baseline), NOT core timing (~+7 ns). Increment 2 (3-clock, adds
`i_clk_slow`=28.3125 for the rare >50 content) deferred. Spec:
`.research/INTEGRATION-SPEC-hdmi-flicker-free.md`. Everything below is the
distilled project knowledge —
the deep material lives in `doc/` (see "Key documents").


## Former "The emulated machine" section (AExp A500 era, verbatim)


- Amiga 500, **OCS only** (no ECS/AGA), **PAL only**, 68000 (fx68k,
  cycle-exact)
- 512 KB Chip RAM (`$000000`–`$07FFFF`) + 512 KB Slow RAM (`$C00000`–`$C7FFFF`,
  the "trapdoor" expansion) + 256 KB Kickstart 1.3 — **all in FPGA BRAM**.
  Optional 8 MB Zorro II Fast RAM ($200000-$9FFFFF) in the R4+ board SDRAM
  (`fastram_sdram.vhd`, OSM Memory submenu, default off; R3 has no SDRAM,
  see WIP-V2-A11-JS-01). The Slow RAM is
  OSM-switchable: "Slow RAM (A501)" toggle, default on (issue #20, for
  programs like Rogue that break with expansion RAM; **implemented
  2026-07-16, NOT yet synthesized/HW-tested**). The toggle drives
  `slow_ram_i` → `amiga_config.vhd`, which sets userio 0xF5 payload bit 2
  (SS[0]); the firmware auto-soft-resets on toggle (`RESET_CORE` in
  `OSM_SEL_POST`) so the replayed config takes effect at once. With slow
  RAM off, minimig decodes $C00000+ as the custom-register mirror
  (authentic chip-only A500); the RTC at $DC0000 stays mapped (deliberate,
  matches MiSTer). The slow BRAM stays instantiated either way (no BRAM
  delta).
- Kickstart is loaded from SD card at boot: `/amiga/kick.rom` (raw 256 KB
  dump, big-endian, no byte swapping), **mandatory** — missing file =
  fatal error screen, core never starts (`C_CRTROMTYPE_MANDATORY` in
  `CORE/vhdl/globals.vhd`)
- One core clock: **28.375 MHz** (PAL ideal 28.37516, −5.6 ppm), MMCM in
  `CORE/vhdl/clk.vhd` (100 MHz × 56.750 / 5 / 40). No 113.5 MHz clock —
  everything SDRAM/turbo/AGA that needed it is out of scope.
- Floppy: up to THREE drive units `df0`/`df1`/`df2` (WIP-V2-A3; Version 1
  shipped one). Each unit is either a simulated ADF drive (read/write ADF
  mount from the OSM, image staged in its own HyperRAM pool
  `C_HMAP_ADF_DF0/1/2` at words 0x200000/0x280000/0x300000) or the
  Hardware Floppy = the MEGA65's internal mechanism reading real Amiga DD
  disks (read-only milestone, at most one unit). The OSM "Drive Settings"
  submenu holds a `Drives 1/2/3` radio and one Disk Image / Hardware
  Floppy / Off radio per drive; the main menu shows one line per drive,
  swapped between the mount item and a hardware-status text by the M2M
  menu-dependency layer. **ADF read AND write are
  RELEASED and work: they shipped in Version 1 (tag `V1`, 2026-07-23) and
  have been in daily use since. Do not treat the ADF drive as unproven** -
  `VERSIONS.md` lists "One floppy drive (df0:): read/write standard 880 KB
  *.adf disk images" as a Version 1 feature. What was never formally
  recorded is the write test MATRIX of the write spec §8 (rename persists
  across power cycle, format, write+verify, swap-while-dirty, wprot
  regression); the feature itself is fine.
  The write path is a
  hardware MFM write decoder (bit-exact minimig_fdd.cpp
  FindSync/GetHeader/GetData) commits verified sectors to HyperRAM;
  per-track dirty bitmap + vdrives-style anti-thrash (2 s, config.vhd
  word 13) in `adf_mount_wrapper` window 0xFFFE ("WBC"); firmware
  flushes dirty tracks to the SD file in the background via the new
  `HANDLE_CORE_IO` hook (512 B + fflush per slice, one FDH snapshot PER
  DRIVE — the Shell re-opens `HNDL_RM_FILES[n]` before `PREP_LOAD_IMAGE`!);
  drive LED yellow while any drive is dirty. Design + review findings:
  `.research/INTEGRATION-SPEC-floppy-adf-write.md` (the arm-state
  invariant in §5a is load-bearing and now has to hold PER DRIVE). A unit
  is announced write-protected until the firmware arms its WR_EN, on SD
  change, and while remounting.
  IDE: one RIPPLE-compatible board for an HDF image (fork, WIP-V2-A11-JS-02).
  Keyboard + joysticks + mouse work.
- Audio (**implemented + sim-verified 2026-07-24, NOT yet synthesized/
  HW-tested; ships in the unreleased WIP-V2-A1, no version bump**): Paula →
  `CORE/vhdl/audio_filters.vhd` (bit-faithful Minimig.sv port reusing M2M's
  `iir_filter.v`: A500 fixed 4400 Hz low-pass = OSM "A500 Filter", CIA-A-PA1
  LED filter 3000+3400 Hz following `pwr_led` live = OSM "LED Filter", both
  single-select default ON; MiSTer `aud_mix` crossfeed = OSM "Stereo: %s"
  radio Full/Wide/Narrow/Mono, default Full) → master volume (Q15,
  monitor-knob = last) → HDMI + analog alike. All HDL-read OSM bits
  (`C_MENU_STEREO` 96..99, `C_MENU_A500FILT` 102, `C_MENU_LEDFILT` 103 since
  the Configure Drives block shifted lines ≥3 by +10), zero
  firmware logic, zero BRAM; both filters have intrinsic DC gain (+0.53 /
  +1.11 dB, MiSTer-faithful incl. the IIR's 16-bit clamp). Everything-off =
  bit-transparent raw Paula (the V1 sound). OPTM_SIZE 103→114, OPTM_DY
  28→31, MENU_HEAP 1536→1664. The generic M2M "audio improvements" filter
  stays tied off. End-user doc: `doc/audio.md`; details:
  `doc/developers/audio.md`; TBs in `.research/` (tb_iir_amiga.v +
  tb_audio_filters.vhd, all green).
- **Hardware Floppy (read milestone) — implemented 2026-07-26; first R3
  build closed timing after the CDC fix, OSM reworked after hardware round
  1; read path partially proven on hardware (real flux decoded, boot
  attempt started), ships in WIP-V2-A2.** The MEGA65's internal 3.5" drive
  as a real Amiga unit: OSM "Configure Drives" submenu with four combos
  (`C_MENU_HWFC_*` 7..10) A: df0:ADF+df1:HW (default) / B: df0:HW+df1:ADF
  / C: df0:ADF only / D: df0:HW only (no ADF drive - the engine gates its
  ADF service, announcements and commits with `adf_en_i`); a combo change
  cold-boots only the Amiga via `amiga_cold_boot`, drive count via userio
  0xF7 bits [3:2] (two drives only in A/B). Research:
  `.research/RESEARCH-physical-floppy-drive.md`. Minimig has NO flux layer,
  so three surfaces: (1) 50 MHz read front-end `CORE/vhdl/physical_fdd/`
  (C64MEGA65 physical-1581 codec: input conditioner + index qualification,
  runt-filtered gap stage, ADAPTIVE quantiser — constants hardware-proven at
  exactly 50 MHz on this mechanism — plus the new gap→raw-channel-bit
  rebuild with drought filler and a bit-level DSKSYNC aligner/deserializer
  into a Gray dual-clock word FIFO; BOTH FIFO resets derive from the QNICE
  reset, load-bearing); (2) `adf_track_engine` per-unit backend mux (status
  sel bits dispatch ADF vs physical; physical words stream at real disk
  pace; raw dsksync exported to the aligner — no Copy Lock substitution;
  physical writes drain-DISCARD, `drain_commit` gates the MFM decoder so
  they can never commit into the ADF image; per-unit 0x1nnn announce,
  physical always announced write-protected); (3) CIA-line muxes inside
  `paula_floppy.v` (per-unit substitution into the open-collector status
  AND-terms, real /TRK0 for recalibration, real INDEX edge into CIA-B FLAG,
  `motor_on` export; `phys_mask=0` = bit-identical) + connector driving in
  mega65.vhd (`f_side1 <= side` straight wire — HARDWARE-CONFIRMED correct
  2026-07-26 by the diag sector-header capture, the C64 side-select lesson
  laid to rest). /RDY is synthesized (motor off
  = ready → drive-ID 0xFFFFFFFF for df1:; motor on = 505 ms + 2 qualified
  index edges + index freshness = eject detection). Diag device 0x0104
  (`physical_fdd_diag`, QNICE domain, CDC-free — the bring-up instrument).
  The A2 menu had a static two-line structure whose LABELS a firmware
  routine (`HWF_LABEL_SYNC`) rewrote in the menu heap to follow the
  selected combo. **That routine is GONE in WIP-V2-A3**: the M2M
  menu-dependency layer swaps whole lines now, which is what the twin
  pairs are. A positional REORDER of the lines is
  impossible within the framework invariants and was HARDWARE-REFUTED on
  R3 (fatal 0x001F on submenu exit): submenu blocks are contiguity-defined
  (head..closer) and CFM bit i is positionally bound to line i.
  OPTM_SIZE 114→124, OPTM_DY 31→33,
  MENU_HEAP 1664→1920. f_wgate/f_wdata stay tied '1' (write = a later
  milestone; DD media only, PC HD mechanisms cannot do Amiga HD). TB
  `.research/tb_physical_fdd_top.vhd`: 5 closed-loop scenarios (nominal /
  ±3% speed / jitter / runts / drought re-lock) ALL PASS; firmware
  qasm-clean; nvc + iverilog clean. Dev SD card: regenerate the settings
  file (`M2M/tools/make_config.sh aexp-WIP-V2-A2.cfg auto`). First R3
  synthesis (2026-07-26) FAILED timing exactly like the C64 precedent: WNS
  -6.331, all 47 failing endpoints = the new RAW qnice<->main crossings
  (word-FIFO Gray syncs + LUTRAM read into the engine's io_din register,
  control/dsksync 2-FF metas) - the first unconstrained fabric paths
  between these MMCM-unrelated clocks. FIXED in `CORE/CORE.xdc`:
  clock-pair `set_max_delay -datapath_only 20.000` qnice<->main in BOTH
  directions (deliberately NOT the C64 blanket false path: a clock-pair
  false path would override common.xdc's object-scoped cdc_stable bounds,
  while max_delay yields to them). Round 2 on R3 (2026-07-26, rebuilt
  core WNS +0.131): the flux front-end PROVEN healthy on real media (284
  sync hits = exactly 22/rev over ~13 revs, 300.5 RPM, 0 runts, 0 drops)
  yet `DF1:BAD` → suspected side inversion → sector-header CAPTURE
  (diag regs 0x11..0x1A: SIDE//TRK0-tagged 8 words after the double
  0x4489) + runtime side-invert (writable diag reg 0x1F → XOR on
  f_side1) added = map v2. **Round 3 (2026-07-26): SIDE INVERSION
  REFUTED — polarity CORRECT as wired** (capture at cylinder 0/head 0
  returned info long 0xFF000207 = track 0 sector 2, hand-verified
  bit-exact MFM incl. clock bits; keep 0x1F at 0; mega65.vhd comment
  updated). Full delivery-chain audit (engine ST_PHYS, wfifo FWFT,
  paula_floppy receiver/WORDSYNC/DMA FSM): loss-free by construction,
  everything after Paula rx shared with the WORKING ADF path — but NO
  existing counter separates "read 6400 words and rejected them" from
  "DMA never armed" (both end `DF1:BAD`). Response = **diag map v3**
  (reg 0x01 = 0x0003; R3 build closed WNS +0.182, BRAM 365): 0x1B =
  words SERVED into Paula (engine ST_PHYS_DATA count, Gray-crossed —
  the go/no-go observable; 1 track read = 6400), 0x1C =
  last-revolution sector-seen mask (0x07FF = all 11), 0x1D =
  {captures,LOL} last rev, 0x1E = bad-format-capture count. The
  DiskDoctor whole-disk sweep (v2 build) then PROVED: disk HEALTHY
  (18254 captures = 11.00 headers/rev over 1659 streamed revs, LOL
  0.60/rev = splice only), side mapping correct on BOTH heads (track
  74 @ cyl37/h0 + track 105 @ cyl52/h1, `cylinder == DiskDoctor
  display` → stepping 1:1), index edges 1:1 with streamed revs — yet
  hard errors on ~every track at ~10 fast retries × 2 surfaces per
  cylinder. Open findings: (a) /RDY WART — the PC mechanism gates
  INDEX on /SEL, so idx_fresh starves across deselect gaps and the
  synthesized /RDY flickers at operation STARTS (fix: drop the
  idx_fresh term from steady-state media_ready, keep the spin-up
  gate, eject via the proven /DSKCHG); (b) co-selection hole (Paula
  sel = priority encoder: a df0: change-poll click during a df1: read
  makes the engine abort/discard ~1 ms or dispatch the ADF service
  into the phys DMA — refuted as root cause by round-1 combo D, MUST
  still be fixed). THE FORK = v3 reg 0x1B served delta over one read
  workload: ≈N×6400 → served-and-rejected → next instrument = a
  Paula-side capture tap (first fifo_wr words after trackrdok rise);
  ≈0 → never armed → the ready-model fix is the prime candidate.
  Round 4 DECIDED the fork: **served-and-rejected** (0x1B ticking at the
  full word rate live, media_ready/idx_fresh = 1 during reads, scoreboard
  0x07FF/11/2 = complete revolutions into Paula — trackdisk rejects
  anyway). The engine→Paula-receiver segment was then exonerated in sim
  (`.research/tb_engine_paula.vhd`: REAL engine vs a line-by-line VHDL
  model of paula_floppy.v's receiver at real-flux cadence — 2 attempts ×
  6400 stored words, all ring-exact) and the same TB caught the
  co-selection hole red-handed (foreign-sel pulse mid-read → 6242 shifted
  words = poisoned buffer). **v4 = diag map 0x0004 (implemented + TB/nvc
  verified 2026-07-27, NOT synthesized):** (a) store-signature pair — XOR
  over the first 1024 post-sync words per attempt, engine-side
  (`phys_sig_*`) AND inside the real paula_floppy.v (`fdd_dsig`, threaded
  paula.v → minimig.v → minimig_m65.v → main.vhd), diag regs 0x20..0x23
  (decode widened to addr[5:0]) — equal-on-hardware exonerates the real
  channel, different = corruption caught; (b) co-selection FIX
  (`phys_stream` session latch: no abort/discard/ADF-dispatch on
  transient foreign sel while trackrd=1; red→green in the TB); (c) /RDY
  HOLD fix (media_ready latches once qualified, holds while motor on —
  INDEX is /SEL-gated so freshness starves across deselect gaps; eject =
  /DSKCHG). Round 5 (v4 build) showed the signatures differing — round 6
  (v5 instruments: checkpoint sigs 0x24..0x27, 8-word Paula tap
  0x28..0x2F, WORDSYNC bit 0x23.8) revealed WHY and found the ROOT
  CAUSE: **ADKCON WORDSYNC is 0 in this system** (measured live; the sig
  windows were differently anchored — the "corruption" verdict is
  retracted, the channel is clean), Paula therefore stores from the VERY
  FIRST served word, and after the deselect-induced chain reset between
  attempts the engine served up to ~570 free-running PRE-LOCK words (the
  taps showed them: legal MFM at wrong bit phase, `A4A5 12A9...`) at the
  buffer start — which trackdisk rejects (the WORKING ADF path's tap
  shows its first aligned 0x4489 at offset 2 = the tolerance
  calibration). Explains the ~100% failure incl. round 1's boot. **v6 =
  THE FIX (implemented + red/green verified 2026-07-27, NOT synthesized;
  version reg = 0x0006, map unchanged): serve-from-sync gate** in
  `adf_track_engine` (`phys_hunt`: discard FIFO words until head equals
  the live DSKSYNC, serve from the sync word; correct under either
  wordsync setting; engine sig window now sync-inclusive = Paula's exact
  window → 0x20 and 0x22 must read EQUAL on an intact channel). TB
  reworked to measured reality (wordsync=0 model, hardware-taken junk
  prefix per selection, strict sync-at-start check, phys_sel vs sel_stat
  separation): old engine RED with the exact hardware junk signature,
  fixed engine ALL PASS. Also: the two m2m-rom.asm genitive apostrophes
  reworded (0 cpp warnings, 26261 ROM lines). **Round 7 (2026-07-27, v6
  build): READ MILESTONE REACHED — the real disk MOUNTS with its volume
  name and browses; signature pairs EQUAL on every dump (channel proven
  word-exact end to end); one-time validate popup (authentic old-media
  retry or the dirty-bitmap-needs-write case = correct wprot behavior)
  and one Guru 00000025 while loading (suspect: 1994 disk content, not
  the core) under observation. Round-8 checklist (eject/re-insert,
  browse+Type, combo-D boot, wprot regression, DiskDoctor re-run) +
  commit decision + R4/R5/R6 + docs pass pending.** Full playbook:
  `.research/HANDOVER-hardware-floppy-round2.md`.

