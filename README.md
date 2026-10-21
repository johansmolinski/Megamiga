![Megamiga](doc/assets/megamiga-logo-2.png)

Megamiga - Amiga 500, 600 and 1200 for MEGA65
=============================================

Megamiga is a fork of [AExp](https://github.com/sy2002/AExp), sy2002's Amiga
500 core for the MEGA65, by Johan Smolinski. It adds an 8 MB Zorro II Fast RAM
expansion and an IDE hard disk (HDF images on the SD card) that Kickstart
boots from; version 0.2 turned the machine into an Amiga 500+ (ECS, 2 MB Chip
RAM, 512 KB Kickstart ROMs, all Amiga memory in the board SDRAM), and version
0.3 adds the 68020, 16 MB Zorro III Fast RAM, the AGA chipset with SuperHires,
and machine profiles (A500, A600 and A1200; files of your own since 0.7); version 0.6 adds a 68040 with MMU, FPU and caches at 42 MHz, and
0.6.1 a shared folder (`SDCard:`), both SD card slots at once and hard disks
served by the FPGA itself; 0.6.2 adds freezer cartridges (HRTmon built in, the
Action Replay III with your own ROM), and 0.6.3 shows Picasso96 screens on
HDMI in their own resolution; 0.6.4 adds an A4000 profile. Megamiga needs a MEGA65 R4 or newer; the R3 has no
SDRAM. Everything
else - and most of this README - is AExp; where the text says "AExp", it
describes the core Megamiga is built on.

Credits
-------

* This core is based on [AExp](https://github.com/sy2002/AExp) by sy2002,
  which in turn is based on the
  [Minimig-AGA core of the MiSTer project](https://github.com/MiSTer-devel/Minimig-AGA_MiSTer).
  Minimig was originally created by Dennis van Weeren and has been improved
  by many others over the years.
* The CPU is [fx68k](https://github.com/ijor/fx68k) by Jorge Cwik, a cycle
  accurate implementation of the 68000.
* The 68040 (Megamiga 0.6) is
  [AP68040-pipelined](https://github.com/ranzbak/AP68040-pipelined), a
  pipelined MC68040 with MMU, FPU and caches:
  * **Adam Polkosnik** wrote [AP68040](https://github.com/apolkosnik/AP68040),
    the original 68040 core with its MMU, FPU, caches and test benches, as part
    of his [Minimig-AGA_MiSTer](https://github.com/apolkosnik/Minimig-AGA_MiSTer)
    work (GPL-2.0-or-later).
  * **Renee Cousins (nonarkitten)** started the six-stage pipelined core
    ([nonarkitten/AP68040](https://github.com/nonarkitten/AP68040)).
  * **Paul Honig (ranzbak)** completed the pipelined core - the full integer
    instruction set, exceptions, MMU, FPU, the split read paths and timing
    closure - and brought it up on hardware in
    [MinimigAGA_TC64](https://github.com/ranzbak/MinimigAGA_TC64), whose
    integration Megamiga's follows.
  * Megamiga runs it on its own 42 MHz clock with a 32-bit path into the SDRAM
    for Fast RAM, next to TG68K.
* The built-in freezer cartridge (Megamiga 0.6.2) is
  [HRTmon](http://www.whdload.de/whdload/Tools/hrtmon238.lha) 2.38 by Alain
  Malek (Hornet of Alcatraz), later maintained by Bert Jahn and others
  (GPL-2.0-or-later); the cartridge logic is Minimig's `cart.v`.
* [sy2002](http://www.sy2002.de) ported the core to the MEGA65 in 2026.
* The core uses the [MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65)
  framework and [QNICE-FPGA](https://github.com/sy2002/QNICE-FPGA) for
  FAT32 support (loading the Kickstart ROM, mounting disks) and for the
  on-screen-menu.

Features
--------

* Machine profiles (Megamiga 0.3; files you can add, copy and name since
  0.7): **A500** (68000, OCS, 512 KB Chip + 512 KB Slow RAM), **A600** (68000,
  ECS, 2 MB Chip RAM), **A1200** (68020, AGA, 2 MB Chip RAM) and **A4000**
  (68040, AGA, 2 MB Chip RAM, 16 MB Zorro III RAM) to start with, each with
  its own Kickstart and hard disks, and as many of your own as you like (see
  Machine profiles below)
* OCS, ECS or AGA, PAL - AGA with the 68020 and an A1200 Kickstart 3.x makes
  an A1200-class machine (256 colours, HAM8, the AGA fetch modes,
  SuperHires; the 31 kHz modes are not displayed yet)
* Cycle accurate 68000 CPU, or a 68020 (the TG68K core that MiSTer's
  Minimig uses for its 68020 mode; no FPU, no MMU), or a 68040 with MMU,
  FPU and caches at 42 MHz (see 68040 below)
* 512 KB, 1 MB or 2 MB Chip RAM, optional 512 KB Slow RAM (trapdoor
  expansion)
* Optional 8 MB Zorro II Fast RAM, switched off by default
* Optional Zorro III Fast RAM with the 68020 or 68040: a 16 MB and a 32 MB
  board, each switched on by itself, 48 MB with both (off by default; needs
  Kickstart 2.0 or newer - Kickstart 1.3 does not know Zorro III boards, so
  leave them off there)
* MEGA65 R4, R5 and R6 only: all Amiga memory lives in the board SDRAM
* Up to three floppy drives (`df0:`, `df1:`, `df2:`), one of them — `df0:`
  as a disk image — switched on by default: mount standard 880 KB `*.adf`
  disk images via the on-screen-menu, read and write — and hand one of the
  drives to the MEGA65's own internal 3.5" drive to read and write genuine
  Amiga disks, copy-protected originals included
* A Picasso96 graphics card (RTG) for the 68020 and 68040, on HDMI: 8/16/24/32-bit
  screens in 4 MB of board memory; HDMI switches to the screen's own
  resolution (640x480 up to 1920x1080)
* Two IDE hard disks (master and slave): `*.hdf` images or whole Amiga
  partitions of an SD card, read and write, that Kickstart boots from - on
  the A600/A1200's own Gayle IDE port, or on a Zorro II IDE board with the
  free lide.device boot ROM; the FPGA reads and writes their sectors itself,
  on the SD card's native 4-bit bus where the card allows it
* A network card on the MEGA65's Ethernet port (R4/R5/R6, 100 Mbit/s) with a
  SANA-II driver: Roadshow, AmiTCP, Miami and the like
* A shared folder: the `/amiga` folder of the external SD card as the Amiga
  volume `SDCard:`, read and write, that comes and goes with the card like a
  disk in a drive - no reboot to mount it
* Both SD card slots at once: disk images, hard disks and Kickstarts can be
  on either card
* The Amiga serial port on the MEGA65's PMOD header (R4/R5/R6, off by
  default): a terminal, a null-modem link or MIDI
* Freezer cartridges, per profile: HRTmon built in (68000 and 68020), or the
  Action Replay III with your own ROM (68000); freeze with CTRL + MEGA + HELP
* Kickstart 1.3 (256 KB) or 2.04 / 3.x (512 KB), chosen per profile in the
  menu
* Real Amiga mouse in port 1, joystick in port 2, exactly like on a real
  Amiga — and either device works in either port, so dual-mouse and
  two-player (two-joystick) setups work too
* MEGA65 keyboard mapped to the Amiga keyboard and raw Amiga keyboard mode
* Interlace ("laced") modes with a built-in flicker fixer on HDMI
* Analog output in parallel to HDMI: scandoubled 31 kHz VGA or raw
  15 kHz RGB for CRTs (SCART), selectable in the menu
* Adjustable picture, per Amiga screen mode: HDMI crop plus analog
  position (pan) and analog overscan, via a config file and helper tool  
* Battery-backed real-time clock

### Machine profiles

A machine profile is a file in `/amiga/profiles` on the SD card (the card the
settings file is on): `03_A1200.prof` is the profile "A1200". The number and
the underscore in front of the name set the order of the list and are not
shown; files without a number (`Work.prof`) come after the numbered ones, in
alphabetical order. At the first start the core creates four profiles:

| Profile | CPU   | Chipset | Chip RAM | Slow RAM | Fast RAM            |
|---------|-------|---------|----------|----------|---------------------|
| A500    | 68000 | OCS     | 512 KB   | 512 KB   | -                   |
| A600    | 68000 | ECS     | 2 MB     | -        | -                   |
| A1200   | 68020 | AGA     | 2 MB     | -        | -                   |
| A4000   | 68040 | AGA     | 2 MB     | -        | 16 MB Zorro III     |

It does that only while `/amiga/profiles` is missing or holds no profile: a
directory with your own profiles stays as it is, also when you deleted the
four.

The A4000 profile is the A1200's chipset with the 68040 and Zorro III RAM;
the core has no A4000 mainboard chips (Ramsey, Fat Gary, the A4000 IDE port),
so give it an A1200 Kickstart 3.x (an A4000 ROM is untested) and use the IDE
board for hard disks as in the other profiles. The A600 profile has 2 MB Chip
RAM (a real A600 has 1 MB; pick that in Profile Settings if a program needs
it).

The main page of the menu (<kbd>Help</kbd>) shows the active profile:
**Profile: A1200**. Select it for the list of the profiles, a separator bar
and **Add New Profile** below it. Choosing a profile reconfigures the Amiga
and restarts it (a cold boot), loads the Kickstart you chose for that profile
- `kick.rom` if you chose none - and mounts its hard disks. The active profile
is remembered: at power-on the core starts with it.

In that list <kbd>Left</kbd> moves the highlighted profile up and
<kbd>Right</kbd> moves it down; the core then renames the files `01_...`,
`02_...` and so on in the new order.

**Add New Profile** asks for a name and makes a copy of the active profile
under it at the end of the list, which becomes the active one; <kbd>Return</kbd> on an empty name
takes "User 1", "User 2" and so on. **Rename Profile** on the main page
gives the active profile a new name (it keeps its place in the list). The name is typed on the MEGA65
keyboard (<kbd>Shift</kbd> for capitals and the shifted symbols,
<kbd>Left</kbd>/<kbd>Right</kbd>, <kbd>Inst/Del</kbd> deletes,
<kbd>Shift</kbd>+<kbd>Clr/Home</kbd> clears, <kbd>Return</kbd> accepts,
<kbd>Run/Stop</kbd> cancels); only characters a file name may have are
accepted (no `" * / : < > ? \ |`), at most 20. You can also copy, rename and
delete the `.prof` files on a computer or from the Amiga through `SDCard:`.

**Profile Settings** shows the details of the active profile, and you can
change each of them: CPU (68000, 68020 or 68040), chipset, the **Hard Disk
Controller** (None, **Gayle** = the A600/A1200's built-in IDE port, or
**RIPPLE** = a Zorro II IDE board, see Hard disks below), Chip RAM, Slow RAM
and the Monitor Cartridge. These show their choices side by side on one line
(like the number of drives in Drive Settings): <kbd>Left</kbd>/<kbd>Right</kbd>
move to a choice, <kbd>Return</kbd> or <kbd>Space</kbd> selects it.

Below them, **Zorro Boards** lists the expansion boards the profile has:
**Zorro II RAM 8 MB**, **Zorro III RAM 16 MB** and **Zorro III RAM 32 MB**
(two boards, switch on one or both for 48 MB), the **Graphics Card** (RTG)
and the **Network Card**, each on or off. What the profile's CPU cannot use
is greyed out, switched off and skipped by the cursor: the Zorro III boards
and the graphics card need a 68020 or 68040, HRTmon does not run on the 68040
and the Action Replay needs the 68000. The hard disk lines (**HDF 0** =
master, **HDF 1** = slave), the **Kickstart** and the **AR3 ROM** line there
pick the profile's files: the file is loaded at once (the Amiga restarts) and
the profile keeps it. <kbd>Space</kbd> on a mounted HDF line ejects the disk and
the profile forgets it. Every change is written to the profile's file when
you close the menu.

A profile file is text, one setting per line, for example:

```
cpu=68040
chipset=AGA
hdc=gayle
chip=2M
slow=none
cart=none
z2ram=off
z3ram16=on
z3ram32=off
gfx=on
net=on
kick=SD1:/amiga/kick31-a1200.rom
hdf0=SD1:/amiga/disks/work.hdf
ar3rom=SD1:/amiga/ar3.bin
```

(`cpu` 68000/68020/68040, `chipset` OCS/ECS/AGA, `hdc` none/gayle/ripple,
`chip` 512K/1M/2M, `slow` none/512K, `cart` none/hrtmon/ar3, the boards on/off;
upper or lower case, a missing line takes the A500 value.)

The floppy drives stay on the main page; the display, audio and keyboard
options are in **Settings**.

#### Setting up the profiles

1. **The files.** Copy into `/amiga` of the SD card (the external one, in the
   back slot, if you use both): `lide.rom` and `megamiga-<version>.cfg` from
   the release (without it the core creates the settings file itself at the
   first start), your Kickstart ROMs and your hard disk images. Kickstart ROMs
   are raw dumps of 256 KB (1.3) or 512 KB (2.04, 3.x), no byte swapping and
   no encryption (for example from Cloanto's Amiga Forever). Name them as you
   like, for example:

   | File                       | A good choice for                              |
   |----------------------------|------------------------------------------------|
   | `/amiga/kick13.rom`        | A500: Kickstart 1.3 (34.5, A500/A2000)         |
   | `/amiga/kick31-a600.rom`   | A600: Kickstart 2.05 or 3.1 for the A600/A500  |
   | `/amiga/kick31-a1200.rom`  | A1200 and A4000: Kickstart 3.1 for the A1200 (40.68) - an A500/A600 3.1 ROM does not drive AGA |

   `/amiga/kick.rom` is optional: it is the Kickstart of every profile you
   have not given one. Kickstart 1.3 knows neither Zorro III RAM nor the AGA
   chipset, so give the A1200 and A4000 profiles an A1200 3.x ROM.
2. **Pick a profile.** Press <kbd>Help</kbd>, select **Profile:** and choose
   one. The Amiga restarts with that machine.
3. **Give it its files.** Open **Profile Settings**, select **Kickstart** and
   pick the ROM in the file browser; then, if you want hard disks, **HDF 0**
   (the master, unit 0) and **HDF 1** (the slave, unit 1): an `.hdf` file or
   an Amiga partition of a card (see Hard disks below). Each choice restarts
   the Amiga and is stored in the profile, with the card it is on
   (`SD1:/amiga/kick13.rom`, `SD0:partition:2`). A profile without hard disks
   is a floppy-only machine.
4. **Adjust it (optional).** In **Profile Settings** change the CPU, chipset,
   Chip RAM or the RAM expansions - for example 8 MB Fast RAM for the A500
   with a hard disk, or a 68000 for A1200 games that dislike the 68020. Each
   change restarts the Amiga and is stored in that profile only. For a
   variant (a second A1200 with other disks), use **Add New Profile** first.

The profiles keep their files by path, so keep the files where they are. A
file that is gone (deleted, renamed, or on the other card) counts as not
chosen: pick it again.

A settings file belongs to the menu of the core that wrote it. When a core
with a different menu (a newer or older version) finds it, it resets the
file to the defaults and says so on the screen at the start; the profiles in
`/amiga/profiles` are not touched (since 0.7 the files a profile remembers
are in its own file).

### Kickstart ROM

The core needs a Kickstart ROM: 1.3 (the 256 KB version that shipped with the
Amiga 500) or a 512 KB ROM such as 2.04, 3.1 or 3.2, as a raw dump of exactly
256 KB or 512 KB, no byte swapping and no encryption. Kickstart is copyrighted
software, so it is not part of this repository or of any release; you need to
obtain a legal copy yourself, for example from Cloanto's Amiga Forever.

Each machine profile uses the Kickstart chosen for it in **Profile Settings >
Kickstart** (see Machine profiles above). A profile without a choice uses

    /amiga/kick.rom

of the card the settings file is on, if it is there. A profile with no
Kickstart at all - none chosen and no `kick.rom`, or a chosen file that
cannot be loaded - keeps the Amiga stopped (black screen) until you pick a
ROM in **Profile Settings**. Picking a ROM loads it and restarts the Amiga
(a cold boot, the old memory contents are gone).

### Slow RAM (A501)

A small number of programs — typically early games — do not work correctly
on an Amiga that has expansion RAM: they place their graphics in the
expansion memory, which the Amiga's custom chips cannot display. **Rogue**
is a well-known example: with Slow RAM switched on it fails to draw the
dungeon and the player. On a real A500 the fix was to pull the trapdoor
card out of the machine; here it is a menu item. Open the menu with
<kbd>Help</kbd>, go to **Profile Settings** and set **Slow RAM** to
**None** (the A500 profile has 512 kB): the Amiga automatically
reboots as a 512 KB chip-RAM-only A500, authentic down to the detail that
the expansion memory area behaves exactly like on a machine without the
trapdoor card. The setting is remembered, so set it back to 512 kB for
software that wants the full 1 MB. The battery-backed real-time clock —
on real hardware a part of the A501 — stays available either way.

### Fast RAM (8 MB)

On MEGA65 boards with SDRAM (revisions R4, R5 and R6) the Amiga can have an
8 MB Zorro II Fast RAM expansion, like the memory side-car boards that were
plugged into the expansion port of a real A500. Kickstart finds it on its own
(autoconfig) and places it at `$200000`, so the Amiga then has 9 MB of RAM
in total. The 68000 runs from Fast RAM without waiting for the custom
chips, so programs, Workbench and anything that loads into memory become
noticeably faster, and much larger programs fit.

Fast RAM is switched **off** by default, because a stock A500 had none and
a few old games and demos do not cope with it. To switch it on, open the
menu with <kbd>Help</kbd>, go to **Profile Settings** and select
**Fast RAM (8 MB)**: the Amiga automatically reboots with the new memory
configuration, and the setting is remembered. The MEGA65 R3 has no SDRAM;
there the menu item has no effect.

### 68040

Each profile can run a 68040 instead of the 68000 or 68020: select
**CPU: 68040** in **Profile Settings** (the Amiga restarts). It is the
pipelined AP68040 core with the 68040's MMU, its FPU (the 68040's own subset
of 68881/68882 instructions) and 4 KB instruction and data caches, clocked at
42 MHz - on its own clock, next to the 28 MHz Amiga bus. Zorro II and Zorro
III Fast RAM is read and written straight from the SDRAM controller, 32 bits
and whole cache lines at a time.

* **Software.** Like a real A4000/040, AmigaOS needs `68040.library` in
  `LIBS:` (Commodore's from the Workbench 3.1 Install disk, version 37.30, is
  tested). SetPatch loads it and switches the MMU on; Fast RAM then runs in
  copyback mode, Chip RAM uncached. SysInfo shows a 68040 with FPU.
* **Speed.** SysInfo: about 25,800 Dhrystones with Zorro III Fast RAM, about
  1.4x an A4000/040 at 25 MHz. Chip and Slow RAM
  stay as slow as on a real Amiga, and code in Chip RAM is never cached
  (chipset DMA can change it).
* **RTG** needs the `Megamiga.card` from `Megamiga_RTG.adf`: with the MMU on,
  only that driver finds the graphics card (see the RTG section).
* **Known limits.** Ctrl-Amiga-Amiga resets at once, so data the data cache
  has not written back yet is lost (the OS flushes before its own reboots);
  this matters only for things meant to survive a reset, such as `RAD:`.
  Some old games and demos do not run on any 68040, as on a real A4000/040.

### Floppy disks

AExp gives the Amiga up to three floppy drives: `df0:`, `df1:` and `df2:`.
Each one is either a **disk image** (an `*.adf` file on your SD card), the
**Hardware Floppy** (the MEGA65's own internal 3.5" drive, reading genuine
Amiga disks), or switched off. How many drives exist and what each of them
is, you choose in the **Drive Settings** submenu of the options menu; a
change there cold-boots the Amiga, because it has to re-detect its drives.
Out of the box you get exactly one: `df0:` as a disk image drive. `df1:` and
`df2:` are off, and no drive is the Hardware Floppy — a number of games and
demos misbehave when the Amiga sees more than one drive, so AExp starts with
the configuration those titles expect. Switch the others on when you need
them.

A disk image drive normally reports "ready" the moment the Amiga switches its
motor on, as in Minimig on the MiSTer. A real drive needs about half a second
to spin up, and test programs such as Amiga Test Kit notice the difference
("Drive READY too fast: Gotek or modified PC drive?"). **Drive spin-up delay**
at the bottom of **Drive Settings** makes the disk image drives behave like
real ones: ready 500 ms after motor on. It is off by default; Kickstart waits
for spin-up anyway, so disks do not load noticeably slower with it.

**Virtual Drive Sound** (**On**, **Noclick**, **Off**; On by default) lets
the MEGA65's internal drive play the sounds of the disk image drives: its
motor runs while a disk image drive's motor runs, and its head steps with
it. If several drives run at once, the lowest one is heard (`df0:` before
`df1:` before `df2:`). **Noclick** leaves out the "click" an empty Amiga
drive makes every few seconds while Workbench checks for a disk. Nothing is
written to a disk in the internal drive, and the sound is off while a drive
is set to Hardware Floppy.

A real disk in the internal drive silences it, so the disk does not wear:
the drive reports the disk at the first click or head step after it is
inserted (the motor may run until then), and the sound comes back within a
second of taking the disk out.

Press <kbd>Help</kbd> to open the menu, which shows one line per existing
drive: a disk image drive shows the mounted file name or `<Load>` when it is
empty, a Hardware Floppy drive shows that instead. Move the highlight to a
disk image drive and press <kbd>Space</kbd> to open the file browser and
**mount** a `*.adf` image; a disk in `df0:` boots after mounting. On a drive
that already holds a disk, that same <kbd>Space</kbd> **ejects** it, so one
key both mounts and ejects.

Disks are **read/write**: when the Amiga writes to a disk — saving a file,
formatting, storing a high score — the change is written back to the
`*.adf` file on your SD card. One rule surprises people: the same `*.adf`
file cannot sit in two drives at the same time, and the core refuses the
second mount. Each drive keeps its own copy of the disk and collects its
own changes, so whichever drive saved last would quietly overwrite what the
other one saved. If a program wants two disks, give it two files.

Saving happens in the background, so the Amiga never stalls. The MEGA65's
drive LED shows what the Amiga is doing: **yellow** during floppy access —
reading or writing — just like the drive light on a real Amiga, **red** while
the hard disk is busy, and **orange** when both are. After a floppy write it
turns **green** while the change is being written back to the `*.adf` file on
the SD card (green wins over the other colours), and goes **off** once
everything is safely saved. Please **wait until the LED has stayed off for a
few seconds** before you unmount a disk, swap disks, reset, or switch the
machine off — the green light can briefly come back on as more data is
flushed. Switching off while it is green loses the not-yet-saved changes,
exactly like ejecting a real floppy while its drive light is still on.

The **Hardware Floppy** makes the MEGA65's built-in drive behave like a real
Amiga drive: you put a genuine Amiga disk into the MEGA65 and the emulated
Amiga reads **and writes** it. Originals boot — including copy-protected
ones, such as the widespread Copylock scheme by Rob Northen Computing behind
titles like Cannon Fodder, The Chaos Engine and Terminator 2 — and so do
custom trackloader formats that never used AmigaDOS. Disks the core writes
are read by real Amigas: an A500, an A500+ and an A1200 have all read back
disks written here, including a bootable Workbench disk cloned end to end.

Two things to know. It needs double-density (DD) media, which is what Amiga
disks are; a PC-style mechanism physically cannot read Amiga HD disks. And
because writing is real, **the disk's own write-protect tab is the only thing
protecting it** — slide the tab open on anything irreplaceable before it goes
near the slot. Only one drive can have the Hardware Floppy, since there is
only one mechanism.

The complete guide to the drives is in [doc/drives.md](doc/drives.md), and
[doc/hardware_floppy.md](doc/hardware_floppy.md) explains reading and writing
real Amiga disks, copy protection, and what to expect from thirty-year-old
media.

### Hard disks (HDF images)

The Amiga can have two hard disks, master and slave on one IDE channel:
`*.hdf` image files on your SD card. Reads and writes go straight to the file
on the SD card - there is no copy in memory and nothing to wait for before a
reset. Each machine profile picks the controller the disks are on, with the
**Hard Disk Controller** row in **Profile Settings** (**None** = no
controller at all):

* **Gayle** (the default in the A600 and A1200 profiles): the IDE port
  built into the real A600 and A1200, at the same addresses. Their Kickstarts
  (2.05 and newer) bring its driver, `scsi.device`, and boot from it, so no
  boot ROM file is needed, HDToolBox and the AmigaOS installers find the
  drives without further settings, and the `scsi.device` updates of AmigaOS
  3.1.4 and 3.2 (disks over 4 GB, for example) apply. It needs an A600 or
  A1200 Kickstart: the A500 ones (1.3, 2.04) have no driver for it, and with
  such a ROM the Amiga simply finds no hard disk.
* **RIPPLE** (the default in the A500 and A4000 profiles): a Zorro II IDE
  board, emulated to behave exactly like LIV2's open-source
  [RIPPLE](https://github.com/LIV2/RIPPLE-IDE). Its driver and boot ROM is
  [lide.device](https://github.com/LIV2/lide.device) (GPL-2.0), which works
  with every Kickstart, 1.3 included.

The partition table is inside the image, so a disk works with either
controller; only things that name the driver need changing (a mount entry or
a tool type with `lide.device` instead of `scsi.device`, or the other way
round). Workbench sees the partitions as `DH0:`, `DH1:` and so on, in the
order of the drives, with either controller.

1. For the Zorro II board only: copy the `lide.rom` from the core's release
   package to `/amiga/lide.rom`. Without it that profile works as before,
   just without the hard disk. The release ships lide.device 40.12 with two
   Megamiga additions: the fix for Workbench 1.3's Format, and DMA - the board
   copies the sectors into Fast RAM itself instead of the CPU (version string
   "Megamiga DMA 1"; buffers in Chip RAM or not on a long-word boundary still
   go through the CPU). Source: branch `megamiga-dma` of
   [johansmolinski/lide.device](https://github.com/johansmolinski/lide.device/tree/megamiga-dma).
   The official `lide.rom` of a
   [lide.device release](https://github.com/LIV2/lide.device/releases) works
   too, without DMA and except for a full format (see below).
2. Copy your `*.hdf` images to either SD card.
3. Open the menu with <kbd>Help</kbd>, go to **Profile Settings** and select
   **HDF 0:** (master) or **HDF 1:** (slave). Pick the image in the file
   browser (or an Amiga partition, see below). The Amiga restarts at once and
   boots from the hard disk (a floppy in `df0:` still has priority, as on a
   real Amiga). The profile keeps the disk: it is mounted whenever the
   profile starts.
4. To eject a disk, highlight its **HDF 0:** or **HDF 1:** line and press
   <kbd>Space</kbd> - on an empty line the same key opens the file browser.
   The profile forgets the disk, and the Amiga restarts, because it only
   looks for its drives at a restart; with neither drive left, the controller
   disappears from the Amiga.

HDToolBox lists the drives as units 0 and 1 of `scsi.device` (Gayle) or
`lide.device` (Zorro II board). HDToolBox looks at `scsi.device` unless told
otherwise, so for the Zorro II board select its icon, choose **Icons >
Information** in Workbench, add the tool type
`SCSI_DEVICE_NAME=lide.device` and save: from then on it opens with the
Megamiga drives. From a Shell, `HDToolBox lide.device` does the same once.
Installers that ask for the hard disk's device (the AmigaOS 3.2 one, for
example) take `lide.device` too. Never mount the same image as master and slave at
once: the two drives would write to one file without knowing of each other.

An image is normally a whole hard disk with a partition table (a Rigid Disk
Block, RDB): WinUAE's "Create hardfile" with RDB, or
[amitools](https://github.com/cnvogelg/amitools)' `rdbtool` make such images.
Kickstart 1.3 has only the old file system (OFS) in ROM, so either use OFS
partitions, or put the FastFileSystem into the RDB (rdbtool `fsadd`), which
lide.device then loads at boot. The image size must be a multiple of 512
bytes; FAT32 limits a file to 4 GB (for bigger disks see the partitions
below).

Simplified hardfiles work too: an image of a single partition without an RDB,
as UAE makes them by default (WinUAE's "Add Hardfile" without RDB mode,
amitools' `xdftool`, and many images that were made for UAE). The core then
shows the drive with one extra cylinder in front of the image: a made-up RDB
with one bootable partition that covers the whole image, named `DH0` on the
master and `DH1` on the slave, with the image's own file system type. MiSTer
does the same. Such an image is recognised by its first block, which starts
with `DOS\0` to `DOS\7` (OFS/FFS), `PFS` or `SFS`, and by having no RDB in its
first 16 blocks; a blank image is left as it is, so HDToolBox can still
partition it. The partition has UAE's default geometry (32 blocks per track,
one surface, two reserved blocks); images over about 1 GB that were formatted
on MiSTer, which uses bigger cylinders there, are recognised by where their
root block is. Notes:

* The file system must be one the Amiga already has: FFS is in the ROM of
  Kickstart 2.0 and newer. A PFS3 or SFS image needs that file system
  installed on the system you boot (a made-up RDB carries no file system), so
  it can be a second drive but not the boot disk.
* The made-up blocks are read-only: writes to them are ignored, and HDToolBox
  shows the drive as "MEGAMIGA DONT REPARTITION". Do not repartition such a
  drive - its image has no room for a real RDB.
* An Amiga partition of the SD card (see below) without its own RDB is
  treated the same way.

To format a partition on the Amiga, use `Format DRIVE DH0: NAME Work`, or
add `QUICK` to only write the empty file system (much faster, and just as
valid). With the official lide.device up to version 40.12 a full format fails
with "Error during format": it mixes up the block address of Workbench 1.3's
format command, which the patched `lide.rom` of the release fixes. Workbench
1.3's Format also needs one cylinder's worth of free memory, so partition
images for an unexpanded A500 with small cylinders (for example 2 heads x 32
sectors), or switch on the Fast RAM.

#### A quick hard disk: hdf: on the main page

The line **hdf:** right below the floppy drives of the main menu takes one hard
disk image for a while, without touching the profile - meant for the WHDLoad
images that hold a single game and boot it (one HDF per game). Pick an `.hdf`
file (or an Amiga partition of the SD card) there and it becomes the master
drive, the only one: the profile's **HDF 0** and **HDF 1** step aside and the
Amiga restarts and boots the game. It stays like that until you highlight
**hdf:** and press <kbd>Space</kbd>, which ejects it, mounts the profile's hard
disks again and restarts the Amiga - or until the core is restarted, because
the quick disk is never saved.

Meanwhile the profile keeps its disks: the HDF lines in **Profile Settings**
still show them, switching to another profile changes them without touching the
quick disk, and a file you pick on those lines is only noted in the profile
(mounted when the quick disk goes); <kbd>Space</kbd> on such a line makes the
profile forget its file. Simplified (RDB-less) UAE images work here too, see
above. With the RIPPLE board the profile needs `lide.rom`, as for any hard disk.

#### Hard disks on an SD card partition (beyond 4 GB)

A hard disk can also be a partition of the SD card itself instead of a file,
which lifts FAT32's 4 GB limit (up to 128 GB per disk). Partitions of type
`7F` (hex) are Amiga disks; Megamiga only ever uses partitions of exactly
that type: the FAT32 partition, an empty entry or any other type is refused.
On the Gayle, the part of a disk beyond 4 GB needs the `scsi.device` of
AmigaOS 3.1.4 or 3.2: the one in the Kickstart 3.1 ROM only reaches the
first 4 GB.
The card with the core's files keeps its FAT32 partition first and has room
for up to three more. A card that only holds Amiga disks, for example the
internal one next to an external card with the core's files, needs no FAT32
partition at all: all four entries can be `7F` partitions. Such a card shows
its partitions in the list of the cards; it has no folders to browse.

1. Make room on a PC: back up the card, shrink its FAT32 partition (or, on a
   card for Amiga disks only, delete it) and add a primary partition of type
   `7F` after it. On Linux, `fatresize` shrinks FAT32 in place, files kept
   (`sudo fatresize -s 8G /dev/sdX1` with the partition unmounted and checked
   by `fsck.fat` first); `fdisk` (`n`, then `t` sets the type) or
   `echo ',2G,7f' | sudo sfdisk --append /dev/sdX` adds the partition; GParted
   does both. Partition numbers are the MBR entries, 1 to 4. Then zero the
   start of the new partition, for example
   `dd if=/dev/zero of=/dev/sdX2 bs=1M count=16` (`sdX2` = that partition -
   check the name twice). Many SD cards read never-written blocks as `FF`
   bytes, and an Amiga partition whose first block reads `FF FF FF FF` shows
   up as "No disk present" and cannot be formatted.
2. Pick the partition in the file browser: go to the top of a card with
   **<..>**, and in the list of the cards every Amiga partition shows up below
   its card (`SD0: Partition 2: 1024 MB`). Or put a link file on the FAT32
   side of the same card: an `.hdf` file with one line of text,
   `MEGAMIGA-PARTITION 2` for partition 2 (the release has `part2.hdf`,
   `part3.hdf` and `part4.hdf`), and pick that like any other HDF.
3. Partition the new disk on the Amiga with HDToolBox (`scsi.device` on
   the Gayle, `lide.device` on the Zorro II board), or
   copy an existing HDF image into the partition on a PC (`dd`); either way
   the partition holds a whole disk with its own RDB (or a single partition
   without one, see the simplified hardfiles above).

Format the Amiga partitions with `QUICK`: a full format writes and then
verifies every block, one SD card block at a time, which takes a long time
on a big partition and gains nothing on a hard disk.

One partition can only be the master or the slave at a time. File systems
beyond 4 GB need a 64-bit-capable file system on the Amiga (FFS of Kickstart
3.1.4 or 3.2, PFS3 or SFS); with Kickstart 1.3 keep the partitions small.

#### Installing AmigaOS 3.2 without a CD drive

The AmigaOS 3.2 CD's own readme allows copying the CD onto any FFS volume
named `AmigaOS3.2CD`. On a PC, make an HDF with one bootable FFS partition
(about 150 MB, boot priority 1), label it `AmigaOS3.2CD` and copy the CD's
contents into it, for example with amitools (`rdbtool ... create chs=300,16,63
+ init + add size=100% name=CD0 dostype=DOS3 bootable=1 pri=1`, then
`xdftool ... open part=CD0 + format AmigaOS3.2CD ffs+intl` and `write`); an
update such as 3.2.3 can go into the same volume. Mount it as `HDF 1:`, the
Amiga boots from it, and `AmigaOS3.2CD:Install/StartHere` starts the
installation onto the master. With the A1200 profile the 3.2.x Kickstart
from the update package (`A1200.47.115.rom`, chosen as its Kickstart) saves the
Modules disk and its double boot. StartHere mounts the `Install3.2` disk
image (and others, such as `GlowIcons3.2`) write-protected; if the installer
or a tool such as HDToolBox has to write to one, find its unit (`DA0:`,
`DA1:`, ... - `Info` lists them) and run
`DAControl DEVICE=DA0: CHANGE WRITEPROTECTED=NO` in a Shell, then retry. The
image file itself must be writable: on `SDCard:` it is, on a CD-ROM it is not
(copy it to a hard disk first).

Reading and writing sectors is done by the FPGA: it streams them straight
between the IDE board and the SD card, on the card's native 4-bit bus at
50 MHz where the card supports it, else 25 MHz (SPI at 25 MHz where the card
is in SPI mode, see [Two SD cards](#two-sd-cards)). An `.hdf` file in up to
511 pieces on the card - nearly every file - and every partition are served
this way; a very fragmented file still works, through the menu's control
CPU, but much more slowly (copy it once to defragment it). With the
release's `lide.rom` the RIPPLE board also copies the sectors into Fast RAM
by itself (DMA). Measured with SysInfo: 14.8 MB/s on the 68040 with
Kickstart 3.2, the RIPPLE board with DMA and the internal card at 50 MHz
(0.6.1, 4-bit at 25 MHz without DMA: about 4.8 MB/s; SPI at 25 MHz: about
2.8 MB/s). A disk stays
mounted until you eject it, mount another image on its line, select a machine
profile or swap the SD card; mounting an
image always restarts the Amiga, because Kickstart only looks for hard disks
when it starts.

### Graphics card (RTG, Picasso96)

Profiles with the 68020 or 68040 (the A1200 profile, or any profile switched
to one of them in **Profile Settings**) have a graphics card for Picasso96: Workbench
and RTG programs can open screens in 256 colours, 16 bit (65536 colours) or
24/32 bit, which the MEGA65 shows on its **HDMI** output. The 4 MB of board
memory hold for example 1024 x 768 in 32 bit or 1280 x 1024 in 16 bit.
It is MiSTer's Minimig RTG card: the same registers at `$B80100` and the same
Picasso96 driver, rebuilt for the 4 MB of board memory the MEGA65 has for it
(`$02000000`-`$023FFFFF`, in the HyperRAM). Only its ID register differs
(`$B8010E` reads `$4D01`, not MiSTer's `$5001`): software that looks for a
MiSTer there, such as AmigaVision, would otherwise wait for MiSTer-only
hardware such as the shared folder and hang. Its driver is `Megamiga.card`
from `Megamiga_RTG.adf` (it was called `MiSTer.card` until 0.5.2); MiSTer's
own `MiSTer.card` is not made for this card.

The card is also an autoconfig Zorro III board (8 MB, manufacturer 2011,
product 102): its board memory at the board's address and its registers
$400000 above it. A system that switches the MMU on - the 68040's
`68040.library`, MMULib, Linux - only maps memory and configured boards,
so the driver from `Megamiga_RTG.adf` uses the board's addresses when it
finds the board; the fixed addresses above remain for older drivers.

You need Kickstart 3.x, Workbench 3.x and
[Picasso96 2.0](https://aminet.net/package/driver/video/Picasso96) from
Aminet. Install Picasso96 first, then copy the driver from the
`Megamiga_RTG.adf` disk of the release (or from `CORE/rtg/` of the source):

    Libs/Picasso96/Megamiga.card   to LIBS:Picasso96/
    Devs/Monitors/Megamiga         to DEVS:Monitors/  (with Megamiga.info)
    Devs/Picasso96Settings         to DEVS:           (the screen modes)

Reboot and pick one of the `Megamiga:` modes in Prefs/ScreenMode.

**Coming from Megamiga 0.5.2 or older:** the card was called `MiSTer` there.
Delete `DEVS:Monitors/MiSTer`, `DEVS:Monitors/MiSTer.info` and
`LIBS:Picasso96/MiSTer.card`, then install the three files above. Copying the
new `Picasso96Settings` replaces your screen modes with the standard set, now
named `Megamiga:`; if you made your own modes, recreate them with
Picasso96Mode instead (they are stored under the board name). Programs set to
a `MiSTer:` mode need the new mode chosen once.

The card has a blitter: Picasso96 hands rectangle fills, copies (window
moves, scrolling) and text to the FPGA instead of doing them with the 68020.
When the 68020 reads the board memory itself, it gets 32 bytes at a time into
a small read-ahead buffer.

While an RTG screen is shown, the HDMI picture comes from the graphics card
and the analog VGA output keeps showing the normal Amiga picture. A reset
switches back to the Amiga picture. RTG needs the HDMI output.

**RTG native resolution** (Settings > HDMI, on by default): when the screen
mode is one that HDMI can show pixel for pixel, the HDMI output switches to that
resolution instead of scaling the picture into the HDMI mode chosen in the
menu. These are 640x480, 800x600 and 1024x768 at 60 Hz, 1280x720 at 60 Hz and
1920x1080 at 30 Hz, and also their exact halves (320x240, 400x300, 512x384,
640x360, 960x540), which are doubled. Other sizes are scaled as before. The
display needs a moment to resync at every switch between the Amiga picture and
an RTG screen. Switch the option off if your display does not take one of these
modes.

The graphics memory delivers about 160 MB/s to the HDMI picture. Depending on
the colour depth, that limits how large a screen can be shown with RTG native
resolution on (with it off, the screen is read at the menu's HDMI refresh rate,
which needs even more for the large modes):

| Colour depth | Largest screen |
|--------------|----------------|
| 8 and 16 bit | 1920x1080 (at 30 Hz) |
| 24 bit       | 1024x768 |
| 32 bit       | 800x600 |

Larger modes at 24 or 32 bit give a broken picture; use 16 bit for them.

### Mouse and joystick

Plug the mouse into **port 1** and the joystick into **port 2** — the usual
setup, exactly like on a real Amiga. Both ports accept either device, though,
so a mouse in each port, or a joystick in each port for two-player games, works
just as well. The **original Amiga "Tank Mouse"** is the directly
supported passive mouse; compatible active adapters are listed below.
Commodore C64 mice do **not** work: neither the 1350 ("joystick mouse") nor
the 1351 (proportional mouse) speaks the Amiga's protocol. We may add support
for them in a future version.

The Amiga Tank Mouse works out of the box: movement and the **left button**
behave just like on the original machine.

The **right mouse button** (in Workbench it pulls down the menu bar) is the
tricky one. On a real Amiga the mouse signals it on a special line that the
Amiga's Paula chip actively drives high. The MEGA65 can only *read* that
line, not drive it, so it cannot sense the right button of an original Tank
Mouse. This is a hardware property, identical on every MEGA65 model from R3
to R6. The built-in answer is always available: **hold the <kbd>Run/Stop</kbd>
key** as a right mouse button (hold it while moving the mouse to open the
Workbench menus). This works when your keyboard is in the MEGA65 mode.
In the positional Amiga keyboard mode this substitute moves to the
<kbd>&uarr;</kbd> symbol key (left of <kbd>RESTORE</kbd>), because
there <kbd>Run/Stop</kbd> is the Amiga's <kbd>Esc</kbd>. Both keyboard modes are
summarized in the Keyboard section below.

So what works depends on what you plug in:

| What you use                                                        | Move + left button | Right / middle buttons                    |
|---------------------------------------------------------------------|--------------------|-------------------------------------------|
| Original Amiga "Tank" Mouse                                         | Yes                | Right via <kbd>Run/Stop</kbd>; no middle  |
| Original Amiga "Tank" Mouse with DIY adapter (see below)            | Yes                | Yes                                       |
| Adapter that *actively drives* the line (e.g. Micro Tom, USBAMI)    | Yes                | Yes                                       |
| Faithful Tank Mouse replica that *actively drives* the line (e.g. Alfa Data MegaMouse 400, Amitech Amiga Mouse, Amigakit Mouse)      | Yes                | Yes                                       |
| mouSTer in Amiga-mouse mode                                         | Yes                | Yes(*)                                    |
| Commodore 1350 (C64 "joystick mouse")                               | No                 | No (maybe supported later)                |
| Commodore 1351 (C64 "proportional mouse")                           | No                 | No (maybe supported later)                |

(*) Note on the mouSTer: it emulates a real tank mouse so faithfully that it
inherits the exact same limitation. Therefore you need to
[download firmware version `3.23.5313`](https://github.com/willyvmm/mouSTer/releases/tag/3.23.5313)
or newer. With new firmware, mouSTer supports a new setting in the
`[mouse]` section: `activepotlines=true`. With that, you can use the right
button on your mouse, without it, you need to stick to <kbd>Run/Stop</kbd>.
Here is an example of a known-to-work [MOUSTER.INI](https://github.com/user-attachments/files/29939083/MOUSTER.INI.zip).

**A simple DIY adapter makes the right button work**, even with an original
Tank Mouse. The only missing piece is the pull-up that a real
Amiga's Paula chip provides, and you can add it externally: build a
straight-through DB9 male-to-female passthrough (all nine pins wired 1:1) and
solder two resistors inside the shell, roughly 2 kΩ from pin 7 (+5V) to
pin 9 (right button) and another 2 kΩ from pin 7 to pin 5 (middle button).
With that adapter in line, the right (and middle) button of any faithful
passive mouse works natively.

One heads-up for actively-driving adapters: if you unplug one while the Amiga
is running, the right button can stay "stuck" for up to half a minute
(Workbench shows its menu bar and stops redrawing) before it clears on its
own. Just give it a moment after swapping devices.

#### No mouse? Drive the pointer from the keyboard

Have no Amiga mouse or adapter at hand? You can still operate Workbench. The
Amiga's operating system can move the mouse pointer from the keyboard, and
that feature works on this core too. It is provided by Intuition (the Amiga's
windowing system), so it is available in Workbench and other OS-friendly
programs — but **not** in games or demos that take over the machine.

The MEGA65 keys map onto the Amiga's built-in combinations like this:

| Action                      | Keys                                                                   |
|-----------------------------|------------------------------------------------------------------------|
| Move the pointer            | <kbd>MEGA</kbd> + <kbd>&uarr;</kbd> <kbd>&darr;</kbd> <kbd>&larr;</kbd> <kbd>&rarr;</kbd> |
| Move the pointer **faster** | <kbd>MEGA</kbd> + <kbd>Shift</kbd> + <kbd>&uarr;</kbd> <kbd>&darr;</kbd> <kbd>&larr;</kbd> <kbd>&rarr;</kbd> |
| **Left** mouse button       | <kbd>MEGA</kbd> + <kbd>Alt</kbd> *(Amiga mode: <kbd>MEGA</kbd> + <kbd>F13</kbd>)* |
| **Right** mouse button      | <kbd>Run/Stop</kbd> *(Amiga mode: <kbd>&uarr;</kbd> key)*               |

<kbd>MEGA</kbd> is the Amiga's *left Amiga* key and <kbd>Alt</kbd> is its
*left Alt*, so <kbd>MEGA</kbd> + <kbd>Alt</kbd> is exactly the Amiga's
built-in "left click". (In the positional Amiga keyboard mode the *left Alt* key
moves to <kbd>F13</kbd>, so use <kbd>MEGA</kbd> + <kbd>F13</kbd> there.) The
pointer keeps accelerating the longer you hold an arrow, so tap the keys for fine
positioning and hold them to cross the screen.

### Keyboard

The MEGA65 keyboard drives the Amiga, and you choose **how**. Two mapping
modes are available in the menu's **Keyboard** section:

* **MEGA65 mode** (default) — *the cap is law*: you get exactly the character
  printed on the MEGA65 keycap, including the front-face symbols typed with
  <kbd>MEGA</kbd> (so `{` is <kbd>MEGA</kbd>+<kbd>:</kbd>, `~` is
  <kbd>MEGA</kbd>+<kbd>,</kbd>, and so on). Best if the MEGA65 is the keyboard
  you know.
* **Amiga mode** — *positional*: each key sends the Amiga key in the same
  place on a real Amiga keyboard, so the shifted number row and a few
  punctuation keys follow the Amiga's own labels. Best for Amiga muscle memory
  and for games such as Pinball Dreams that require the original Amiga
  mapping.

The most important keys (the meanings below are for the default MEGA65 mode;
where Amiga keyboard mode differs from the MEGA65 keyboard mode is noted in the right column):

| MEGA65 keyboard                                                       | Amiga                                         |
|-----------------------------------------------------------------------|-----------------------------------------------|
| <kbd>MEGA</kbd>                                                       | Left Amiga; in MEGA65 mode it also selects front-face symbols |
| <kbd>CTRL</kbd> + <kbd>MEGA</kbd> + <kbd>RESTORE</kbd>                | Ctrl + Left Amiga + Right Amiga (reset)       |
| <kbd>RESTORE</kbd>                                                    | Right Amiga · *Amiga mode:* Right Alt         |
| <kbd>Run/Stop</kbd>                                                   | Right mouse button, hold · *Amiga mode:* Esc  |
| <kbd>F1</kbd> <kbd>F3</kbd> <kbd>F5</kbd> <kbd>F7</kbd> <kbd>F9</kbd> | F1, F3, F5, F7, F9 *(MEGA65 mode)*            |
| <kbd>Shift</kbd> + <kbd>F1</kbd>/<kbd>F3</kbd>/<kbd>F5</kbd>/<kbd>F7</kbd>/<kbd>F9</kbd> | F2, F4, F6, F8, F10 *(MEGA65 mode)* |
| Top row from <kbd>Run/Stop</kbd> through <kbd>F11</kbd>               | Esc, F1–F10 *(Amiga mode)*                    |
| <kbd>Help</kbd>                                                       | Amiga Help; default menu key                   |

In the default **MEGA65 mode** <kbd>Esc</kbd>, <kbd>Tab</kbd> and
<kbd>Caps Lock</kbd> work as expected. In **Amiga mode** the entire top row is
positional — <kbd>Run/Stop</kbd> is Esc, <kbd>Esc</kbd> is F1, <kbd>Alt</kbd> is
F2, <kbd>Caps Lock</kbd> is F3 … <kbd>F11</kbd> is F10 — the right mouse button
moves to the <kbd>&uarr;</kbd> symbol key (left of <kbd>RESTORE</kbd>), and
<kbd>F13</kbd> becomes Left Alt. The full per-key breakdown is in the guide below.

By default <kbd>Help</kbd> opens the menu, but you can reassign it — to
<kbd>F11</kbd>, <kbd>F13</kbd> or <kbd>MEGA</kbd>+<kbd>Run/Stop</kbd> — in the
Keyboard menu, which reserves <kbd>Help</kbd> solely for the Amiga. In MEGA65
mode, <kbd>F11</kbd> and <kbd>F13</kbd> are clean menu keys that send nothing to
the Amiga. In Amiga mode they also send F10 and Left Alt respectively; see the
guide for the effect of every menu-key choice.

**The full keyboard guide — complete per-mode tables for typing, special keys,
menu keys, and steering the mouse from the keyboard — is in
[doc/keyboard.md](doc/keyboard.md).**

### Video: HDMI

HDMI outputs 720p (16:9) by default. The first `HDMI:` menu entry offers
576p in 4:3 or 5:4 instead, plus the DVI switch that rescues displays which
show nothing at all (see the end of this section).

**HDMI follows the Amiga's frame rate.** A PAL Amiga draws 50 pictures a
second, an NTSC Amiga 60, and the HDMI mode follows whatever the Amiga shows
at the moment: 720p at 50 or 60 Hz, and 576p at 50 Hz or 480p at 59.94 Hz (at
60 Hz both 576p choices give 480p in 4:3; there is no 5:4 variant of it). When
the rate changes, the display resyncs once. See
[PAL and NTSC](#pal-and-ntsc-60-hz) below.

The second `HDMI:` menu entry, directly below the display mode, selects
the scaling filter:

| Filter          | Look                                                      |
|-----------------|-----------------------------------------------------------|
| No Filter       | nearest neighbor: maximum sharpness, visible pixel stairs |
| Sharp Bilinear  | pixel sharp, but with softened stair edges                |
| Bicubic         | smooth all-round interpolation                            |
| Smooth          | soft polyphase scaling                                    |
| Lanczos         | crisp polyphase scaling; the default                      |
| Scanlines       | Lanczos plus visible scanlines                            |
| CRT (S-Video)   | scanlines plus a slightly softened picture, like S-Video  |
| CRT (Composite) | scanlines plus heavy horizontal blur, like an antenna or composite cable |

These two features both fight "flicker", but they cure two entirely
different things — one the shimmer of interlaced screens, the other a
periodic hitch in smooth motion:

#### Interlace flicker fixer (automatic)

Laced screens such as the 640x512 Workbench or the interlaced pictures that
demos love are woven into a stable, full-resolution HDMI picture — the same
job the A3000's "Amber" chip or an Indivision does on real hardware. This
runs automatically; there is no menu entry for it. Demos that flicker *on
purpose* (alternating two images at 50 Hz to fake extra colors, transparency
or glowing lights) keep flickering: that is the intended look, and only a CRT
softens it.

#### Flicker-free: smooth motion (menu entry)

The third `HDMI:` menu entry, **Flicker-free** (on by default), keeps the
HDMI picture perfectly smooth. An Amiga runs a hair below 50 Hz while HDMI
is locked to exactly 50 Hz, so without correction the picture drops or
repeats one frame roughly every twelve seconds — a small judder or tear,
most visible on horizontal scrollers. Flicker-free nudges the Amiga clock
by a fraction of a percent so its frame rate averages exactly 50 Hz and
the seam disappears. **Turn it off for the analog VGA / 15 kHz outputs**:
there it would make the sync frequency step, which analog monitors
dislike. (With it on, the machine also runs about 0.16 % fast, so software
clocks gain a few seconds per hour — turn it off if you need authentic
timing.)

(Megamiga: Flicker-free is not available, and the menu entry has no effect.
Since 0.2.0 the SDRAM's clock comes from the main clock generator only, so
the core clock cannot switch to the faster twin. Since 0.7 that second clock
generator makes the NTSC master clock instead.)

#### Latency on the Checkmate Retro Monitor

Because the Checkmate is a popular choice, it deserves a note of its own.
The monitor appears to use a native 60 Hz panel and introduces considerable
latency when displaying the 50 Hz output of our PAL AExp core, although
scrolling remains smooth with Flicker-free enabled. We suspect that the
latency comes from the internal conversion required to display a 50 Hz
signal on a 60 Hz panel. Deft recorded 
[several videos demonstrating the effect (click here)](https://github.com/sy2002/MiSTer2MEGA65/issues/72),
comparing the Checkmate with a 15 kHz analog monitor and a Samsung HDMI
monitor in Gaming Mode, which adds almost no HDMI latency.

#### DVI (no sound): when the screen stays black

An HDMI cable carries more than pixels. In the gaps between the visible
lines it also sends "data islands": the sound, and small packets that
describe the picture to the display. Not every display wants them. A DVI
monitor behind a passive HDMI-to-DVI adapter cannot decode them at all, and
some older monitors, cheap scalers and capture boxes reject the whole stream
instead of ignoring the parts they do not understand. The symptoms are a
black screen, a "no signal" or "unsupported format" message, or a picture
that keeps dropping out — while the very same core runs fine on a different
display.

**DVI (no sound)**, at the bottom of the first `HDMI:` menu (in
**Settings**) just above **Back to Settings**, is the cure. It strips the signal down to plain DVI:
the pixels, the timing and the resolution stay exactly what they were, and
only the sound and those extra packets disappear. As the name warns, that costs you the sound over the
cable — use the MEGA65's 3.5 mm audio jack instead, which carries the same
audio at the same time anyway.

Leave it off unless you need it. And if you do need it, your display is
showing nothing right now, so here is how to switch it on blind. Turn the
MEGA65 off and on first, so the menu starts from a known state, and then, as
soon as the core has started, press your menu key — <kbd>Help</kbd> unless
you reassigned it in the Keyboard menu:

1. <kbd>Help</kbd> — opens the menu, with the cursor on the topmost `dfN:`
   disk-image line, or on **hdf:** if no drive is a disk image.
2. Seven times <kbd>&darr;</kbd> — past **hdf:**, **Mount SDCard**,
   **Profile:**, **Rename Profile**, **Profile Settings** and **Drive
   Settings**, onto **Settings**. That is **one <kbd>&darr;</kbd> per drive you
   have set to Disk Image, plus six** — seven at the factory default. Moving the
   cursor over a line does not open it; only <kbd>Return</kbd> does.
3. <kbd>Return</kbd> — opens Settings, cursor on the first `HDMI:` line.
4. <kbd>Return</kbd> — opens the HDMI menu, cursor on **720p 16:9**.
5. <kbd>&darr;</kbd> <kbd>&darr;</kbd> <kbd>&darr;</kbd> — past the two 576p
   modes, onto **DVI (no sound)**, then <kbd>Return</kbd> — DVI is on, and
   the picture should appear.
6. <kbd>Help</kbd> — closes the menu and saves the setting.

If the `megamiga-<version>.cfg` file is on your SD card (step 3 of the
installation), you only have to do this once: the choice is stored there and
the core comes up in DVI mode from then on. Without that file the setting is
lost at every power-off, so it is worth copying in.

Two things decide whether those key counts are right. The menu remembers
where the cursor was, so the sequence only works the **first** time you open
it after switching the machine on — that is what the power cycle is for. And
step 2 follows your drive configuration: only a drive set to **Disk Image**
has a line the cursor can land on, so it adds one <kbd>&darr;</kbd>, while a
drive set to **Hardware Floppy** shows a status line that the cursor skips
and a drive set to **Off** shows nothing at all. Neither adds a
<kbd>&darr;</kbd>. If `df0:` itself is the Hardware Floppy, step 2 is five
<kbd>&darr;</kbd>.

### PAL and NTSC (60 Hz)

Megamiga is a PAL Amiga by default. **Settings > NTSC (60 Hz)** makes it an
NTSC Amiga, like the crystal and the Agnus of an American machine. The core
then runs at the NTSC master clock (28.636 MHz instead of 28.375 MHz), and
Agnus starts in NTSC. The Kickstart comes up at 60 Hz with 200- and 400-line
screens, and games and demos made for NTSC machines run at their intended
speed and music tempo. Switching the toggle cold-boots the Amiga. It is one
setting for all profiles.

As on a real ECS or AGA Amiga, software can still switch the picture between
PAL and NTSC on either machine: the Kickstart's Early Startup menu, the
ScreenMode preferences, or a program that writes BEAMCON0. HDMI follows
that too. Such a switch changes only the picture, not the master clock: on
the PAL machine an NTSC screen runs at 59.4 Hz and the CPU keeps its PAL
speed, exactly as on real hardware.

HDMI shows every NTSC field as 240 lines (the bottom one or two lines of the
lower border are cut) and every PAL field as 288. That is exactly ×2 on 480p
and 576p, and exactly ×3 on 720p at 60 Hz, so the
[`aexp_screen.cfg_576p`](doc/screen_adjust.md) preset is pixel-exact on 480p
too. The analog outputs carry the NTSC timing as it is: 15.7 kHz / 60 Hz in
the two 15 kHz modes (a Commodore 1084 handles both standards), 31.5 kHz /
60 Hz in Standard.

### Video: VGA port (analog RGB)

The VGA connector always carries the picture in parallel to HDMI. The
`VGA:` menu selects one of three modes:

* **Standard** (default): the Amiga's 15.6 kHz picture is line-doubled to
  31 kHz so that VGA monitors accept it. Note that a PAL Amiga's picture is
  still a 50 Hz signal, which not every flat panel likes (an NTSC one is
  60 Hz).
* **15 kHz with HS/VS**: the raw 15.6 kHz RGB signal with separate
  horizontal and vertical sync, for retro monitors with a VGA-style
  input.
* **15 kHz with CSYNC**: the raw 15.6 kHz RGB signal with composite sync,
  which is what RGB SCART cables and most CRT setups expect.

On a 15 kHz CRT you get the most authentic Amiga picture possible:
interlace is displayed natively by the tube (no flicker fixer needed) and
the intentional flicker effects of demos melt on the phosphor exactly as
their authors intended.

For how to connect real CRT monitors — BNC, SCART and DB9 RGB, including
important safety cautions — see [doc/retrotubes.md](doc/retrotubes.md).

The on-screen menu is oversized in both raw 15 kHz modes. Open the
**`OSM: 100%`** menu entry (the percentage changes with your selection) and
choose a smaller size, down to 50%, until the menu fits your display
comfortably. This changes only the menu, not the Amiga picture. The setting
is global, so it also changes the menu size on HDMI and in Standard VGA mode.

Careful: a regular VGA monitor shows **no picture at all** in the 15 kHz
modes — including the on-screen-menu. If you locked yourself out, connect
an HDMI display and switch back there; both outputs share the same menu.

### Screen adjustment

The Amiga's picture may not sit perfectly on your screen — an old quirk that
every faithful Amiga recreation shares. AExp fixes it: drop a small 
`aexp_screen.cfg` file into `/amiga` and the core adjusts the
picture, automatically per Amiga screen mode. Three independent controls are
available: **HDMI crop** re-frames the picture on HDMI; **analog position**
moves the complete analog picture (OSM included) left/right/up/down in all
three VGA modes; **analog overscan** hides or reveals the Amiga border edges,
which some demos fill with odd-looking material. Two ready-made files ship
with the core (one for 16:9 displays, one tuned like a 4:3 monitor); pick the
one that looks best, or fine-tune your own with the included
`aexp_screen_cfg.py` tool. The full guide is in
[doc/screen_adjust.md](doc/screen_adjust.md).

### Audio

Audio is available on HDMI and on the 3.5 mm jack simultaneously — unless
you switch on **DVI (no sound)**, which drops the HDMI audio and leaves the
jack. By default
AExp sounds like a real A500: the machine's fixed output filter and its
software-switchable "LED filter" are both emulated, and the options menu adds
a loudness-true master volume plus a stereo mix that makes hard-panned Amiga
music pleasant on headphones. The full story — including why a sound filter
is coupled to the power LED — is in [doc/audio.md](doc/audio.md).

### Network (Ethernet)

On R4, R5 and R6 boards Megamiga has a network card on the MEGA65's Ethernet
port (100 Mbit/s): a Zorro II board that Kickstart configures like any other
expansion card, present in every profile. Tested with the 68020 and Kickstart
3.1 (A1200 profile) and Roadshow 1.15.
Its SANA-II driver `megamiga-eth.device` and the test tool `ethtest` are on
the `Megamiga_Net.adf` disk of the release (or build them from `CORE/eth/`).

1. Mount the disk, open a Shell and run `ethtest` (Kickstart 2.04 or newer):
   it shows the card's station address, the link (it should say "up, 100
   Mbit/s") and its counters. `ethtest 192.168.1.1` (your router's address)
   sends an ARP probe and shows the reply - then the card sends and receives.
2. Copy `Devs/Networks/megamiga-eth.device` to `DEVS:Networks/` and set up
   your TCP/IP stack with that device, unit 0. For Roadshow copy
   `Roadshow/MegamigaEth` to `DEVS:NetInterfaces/`: it asks the network's
   DHCP server for an address; for a fixed address edit it and
   `DEVS:Internet/routes` and `name_resolution` (examples on the disk).

Each MEGA65 has its own station address (`02:...`), derived from the FPGA's
unique device ID. The card needs a 100 Mbit/s port: it does not do 10 Mbit/s
and has no collision handling for old hubs. The driver is based on Niklas
Ekström's a314eth.device; the design is described in
[doc/developers/ethernet.md](doc/developers/ethernet.md).

### Two SD cards

The MEGA65 has two SD card slots: one in the bottom tray under the trapdoor
(the internal card, **SD0**) and one at the back (the external card, **SD1**).
Megamiga uses both at the same time: a hard disk can be on one card and the
floppy images on the other, in any combination.

* **File browser.** It starts in `/amiga` of the card the settings file is
  on. **<..>** at the top of a card leads to the list of the cards,
  `<SD0: internal card>` and `<SD1: external card>`; for the HDF lines the
  Amiga partitions (type `7F`) of each card are listed below it.
* **Settings file.** `megamiga-<version>.cfg` is looked for on the external
  card first, then on the internal one, and the settings are saved back to
  the card it came from. If neither card has it, the core creates it in
  `/amiga` of the first card it can use (external first) with the default
  settings. `kick.rom` and `lide.rom` are read from that card
  too (without a settings file: from the external card, else the internal).
* **Profiles** remember their Kickstart and hard disks together with the
  card, for example `SD1:/amiga/kick31.rom` or `SD0:partition:2`. A file
  that moved to the other card has to be chosen again in the menu.
* **Shared folder.** `SDCard:` is always `/amiga` of the external card.
* **Pulling a card** affects only what is on that card: its drives become
  empty, and the other card keeps working.
* **Speed.** The internal card runs on the native 4-bit SD bus at 50 MHz
  (25 MHz if the card cannot do that).
  The external card normally runs in SPI mode at 25 MHz: the MEGA65 reads it
  in SPI mode before the core starts, and a card leaves SPI mode only when it
  loses power. Taking it out and putting it back in while the core runs gives
  4-bit there too. The last line of the main menu shows the mode of both
  cards, for example `SD0:4-bit  SD1:SPI 25`. For the fastest hard disk, put
  it on the internal card.

### Shared folder (SDCard:)

The folder `/amiga` of the SD card can be an Amiga volume, `SDCard:`, so that
files you copy onto the card on your computer reach the Amiga without disk
images, and from the Amiga back to the card. It can be read and written
(files and drawers: create, copy, rename, delete). It works in every profile
and with every CPU.

The handler `MegamigaFS` is on the `Megamiga_Share.adf` disk of the release
(or build it from `CORE/share/`). With Kickstart 2.0 or newer:

1. Copy `L/MegamigaFS` to `L:`, `Devs/dummy.device` to `DEVS:` and
   `Devs/DOSDrivers/SD` to `DEVS:DOSDrivers/`.
2. Run `Mount SD:` in a Shell - or just reboot: from then on, the handler is
   mounted at every start.

With Kickstart 1.3, add the entry from `Devs/MountList` to `DEVS:MountList`
instead and run `Mount SD:` (in `S:Startup-Sequence` for every start).

`SDCard:` shows the `/amiga` folder of the external SD card, the one in the
back slot: the card you can take out to copy files on a computer (see
[Two SD cards](#two-sd-cards)). The volume is there only while **Mount
SDCard** in the main menu (below the floppy drives) is on. It is off at every
start of the core and the setting is not saved, so switch it on when you want
to use the volume. Without a card in the back slot there is no volume either.
It behaves like a disk in a drive: pull the card and the volume goes
away; insert one and it comes back about a second later, and Workbench shows
its icon again. Long file names work (up to 106 characters, the limit of
AmigaOS); hidden files and anything outside `/amiga` are not shown.

FAT is not an Amiga file system: of the protection bits only "read-only" is
kept (set when a file must not be written or deleted), comments are not kept,
dates have a resolution of two seconds, and names cannot contain
`" * / : < > ? \ |`. Files the core uses itself (a mounted ADF or HDF, the
settings file) cannot be written, deleted or renamed through `SDCard:`. Pull
the card only while nothing is being written to it.

To eject the volume without touching the card, switch **Mount SDCard** off
again.
`C:ShareInfo` on the disk shows the state of the volume and counts the card
changes since the core started.

The volume speaks the protocol of the MiSTer's shared folder, so MiSTer's own
`MiSTerFileSystem` works too, without the disk-change part. `MegamigaFS` is
based on it (Alexey Melnikov) and on a314fs (Niklas Ekström).

### Serial port (PMOD)

On R4, R5 and R6 boards, Megamiga can put the Amiga's serial port on the
MEGA65's PMOD header. The port is Paula's UART with the /CTS and /RTS lines
of CIA-B, so `serial.device`, terminal programs, null-modem games and MIDI
software that drive the serial port all use it. Switch it on in **Settings >
Ports > Serial port on PMOD**. It is off by default: both PMOD headers then
stay unpowered and all of their pins stay inputs.

The pins are 3.3 V TTL and use the same layout as the MegaST (Atari ST) core,
so one adapter works with both:

| PMOD1 pin | Signal          | PMOD1 pin | Signal          |
|-----------|-----------------|-----------|-----------------|
| lo[0]     | CTS (in)        | hi[0]     | MIDI OUT (out)  |
| lo[1]     | TXD (out)       | hi[1]     | MIDI IN (in)    |
| lo[2]     | RXD (in)        | hi[2]     | -               |
| lo[3]     | RTS (out)       | hi[3]     | -               |

PMOD1 lo matches the Digilent PmodUSBUART pinout and MAX3232 RS-232
modules. Never connect real RS-232 levels (±12 V) directly to the header:
use a 3.3 V USB serial adapter or a MAX3232 module. The input pins have
pull-ups, so a pin with nothing connected reads as idle.

The Amiga sends MIDI through its serial port, so MIDI OUT carries the same
data as TXD, and MIDI IN is merged with RXD. Connect only one of the two
inputs at a time. MIDI needs the usual opto-coupler (IN) and driver (OUT)
circuit; an MT32-pi can take MIDI OUT directly on its RXD pin (GPIO 15). DTR,
DSR, CD and RI are not connected: the Amiga reads them as inactive.

### Freezer cartridges (HRTmon, Action Replay III)

A freezer cartridge stops the running program at the press of a button and
opens a monitor: look at and change memory, disassemble, rip graphics and
music, set breakpoints, then continue the program where it stopped. Megamiga
has two, chosen per machine profile in **Profile Settings > Cart**:

* **HRTmon** is built in (HRTmon 2.38 by Alain Malek, GPL). It works with the
  68000 and the 68020 and with Kickstart 1.3 to 3.x. With a 68040 profile no
  cartridge is plugged in.
* **Action Replay 3** is the Datel Action Replay Mk III for the Amiga 500.
  Bring your own ROM: put a raw 256 KB dump on the SD card as
  `/amiga/ar3.rom`, or load one at **Profile Settings > AR3 ROM** (the profile
  remembers it; a profile without its own uses `/amiga/ar3.rom`). The AR3 is
  a 68000 cartridge: it is only plugged in while the profile's CPU is the
  68000, and it wants Kickstart 1.3 or 2.04. It sits at `$400000`, so with
  the AR3 the Zorro II Fast RAM board shrinks to 2 MB, just like on a real
  A500 with this cartridge.

Changing the cartridge restarts the Amiga (a cold boot). To freeze, press
**CTRL + MEGA + HELP**, or select **Freeze cartridge** in the menu and then
close the menu. HELP alone still opens the menu, and the Amiga never sees the
HELP of the key combination.

While a Picasso96 (RTG) screen is shown, HDMI keeps showing it when you
freeze: the cartridge draws its screen with the Amiga's own chips, just like a
freezer next to a real graphics card. The cartridge is running all the same -
its screen is on the analog (VGA) output, and in HRTmon `x` and Return
continue the frozen program.

### Real-time clock

AExp can feed the Amiga the MEGA65's own battery-backed clock, so Workbench
shows the real date and time and your files get proper timestamps. It takes a
minute to set up, and Kickstart 1.3 has two quirks worth knowing about (the
year can come out as 1978, and the time can be an hour off — both with simple
fixes, neither a fault of AExp). The full walkthrough is in
[doc/RTC.md](doc/RTC.md).

Constraints and roadmap
-----------------------

Version 1 is feature complete, so — among other things — the following known
gaps remain in this release:

* One hard disk only, no CD-ROM
* NTSC lines are all 227 color clocks long (a real NTSC Agnus alternates 227
  and 228); the 68020 has no FPU and no MMU (the 68040 has both),
  and there is no 68030 or 68060
* AGA: no SuperHires (1280 pixels) and no 31 kHz modes (DblPAL, Multiscan,
  Productivity) yet
* No ECS SuperHires and Productivity modes (the video path takes at most a
  14 MHz pixel clock), no HDMI flicker-free mode
* Megamiga 0.2 runs on boards with SDRAM (R4, R5, R6) only, not on the R3

The development history — all the alpha and beta work-in-progress builds — is
documented in [doc/inofficial.md](doc/inofficial.md).

Installation
------------

To install the core you need its `*.cor` file (or a `*.bit` file if you flash
via JTAG). Then:

1. Use a FAT32 formatted SD card with a maximum capacity of 32 GB, or two:
   Megamiga uses both slots at the same time (see
   [Two SD cards](#two-sd-cards)); the settings file is looked for on the
   card in the back slot first.
2. Copy your Kickstart ROMs into `/amiga` (see Machine profiles and
   Kickstart ROM above), one of them as `/amiga/kick.rom` if you want a
   Kickstart for every profile without picking one.
3. Copy the `megamiga-<version>.cfg` file that comes with the build into
   `/amiga` so that the core remembers your menu settings and the files each
   profile uses. Without the file the core works, but forgets everything at
   power-off - including the Kickstart and hard disks you picked. The file name
   contains the core version, so after an upgrade you need the matching
   file and need to re-select your settings once.
4. Optional: copy the `aexp_screen.cfg` file into `/amiga` and the core
   adjusts the picture, automatically per Amiga screen mode.
5. Put your `*.adf` disk images into `/amiga`, the file browser starts
   there.
6. Optional, for the hard disk: copy `lide.rom` to `/amiga/lide.rom` and
   your `*.hdf` images onto the card (see "Hard disks" above).
7. Flash the `*.cor` file using the MEGA65's bitstream utility, or, if you
   have a JTAG adaptor, load the `*.bit` file directly with the
   [M65 tool](https://github.com/MEGA65/mega65-tools):
   `m65 -q yourbitstream.bit`.
8. Press <kbd>Help</kbd> as soon as the core is running to mount a disk
   and to configure the core.

Developers
----------

Want to build the core from source? In [doc/developers.md](doc/developers.md)
you will find the whole path from a fresh clone to a `*.cor` file. This core
is built on the [MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65) (M2M)
framework, whose [Wiki](https://github.com/sy2002/MiSTer2MEGA65/wiki) is the
authoritative reference for the build environment and its
operating-system specific details.
