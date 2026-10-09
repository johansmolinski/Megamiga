Megamiga - Amiga 500, 600 and 1200 for MEGA65
=============================================

Megamiga is a fork of [AExp](https://github.com/sy2002/AExp), sy2002's Amiga
500 core for the MEGA65, by Johan Smolinski. It adds an 8 MB Zorro II Fast RAM
expansion and an IDE hard disk (HDF images on the SD card) that Kickstart
boots from; version 0.2 turned the machine into an Amiga 500+ (ECS, 2 MB Chip
RAM, 512 KB Kickstart ROMs, all Amiga memory in the board SDRAM), and version
0.3 adds the 68020, 16 MB Zorro III Fast RAM, the AGA chipset with SuperHires,
and three machine profiles - A500, A600 and A1200 - on the main page of the
menu. Megamiga needs a MEGA65 R4 or newer; the R3 has no SDRAM. Everything
else - and most of this README - is AExp; where the text says "AExp", it
describes the core Megamiga is built on.

Experience the [Commodore Amiga 500](https://en.wikipedia.org/wiki/Amiga_500)
on your [MEGA65](https://mega65.org/)!

This core turns the MEGA65 into an Amiga 500 with the original OCS chipset
(PAL), a cycle accurate 68000 CPU, 512 KB of Chip RAM and a 512 KB memory
expansion in the trapdoor slot (known as Slow RAM, this is what the classic
Commodore A501 expansion did). The Amiga therefore has 1 MB of RAM in total.

This is Version 1, the first official release. The core is feature complete
and, as far as we can assess, rock solid: it runs 99.9% of all games and demos.

![Amiga500](doc/assets/a500_ocs.jpg)

Credits
-------

* This core is based on the
  [Minimig-AGA core of the MiSTer project](https://github.com/MiSTer-devel/Minimig-AGA_MiSTer).
  Minimig was originally created by Dennis van Weeren and has been improved
  by many others over the years.
* The CPU is [fx68k](https://github.com/ijor/fx68k) by Jorge Cwik, a cycle
  accurate implementation of the 68000.
* [sy2002](http://www.sy2002.de) ported the core to the MEGA65 in 2026.
* The core uses the [MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65)
  framework and [QNICE-FPGA](https://github.com/sy2002/QNICE-FPGA) for
  FAT32 support (loading the Kickstart ROM, mounting disks) and for the
  on-screen-menu.

Features
--------

* Three machine profiles on the main page of the menu (Megamiga 0.3):
  **A500** (68000, OCS, 512 KB Chip + 512 KB Slow RAM), **A600** (68000, ECS,
  1 MB Chip RAM) and **A1200** (68020, AGA, 2 MB Chip RAM), each with its own
  Kickstart and hard disk, and each editable (see Machine profiles below)
* OCS, ECS or AGA, PAL - AGA with the 68020 and an A1200 Kickstart 3.x makes
  an A1200-class machine (256 colours, HAM8, the AGA fetch modes,
  SuperHires; the 31 kHz modes are not displayed yet)
* Cycle accurate 68000 CPU, or a 68020 (the TG68K core that MiSTer's
  Minimig uses for its 68020 mode; no FPU, no MMU)
* 512 KB, 1 MB or 2 MB Chip RAM, optional 512 KB Slow RAM (trapdoor
  expansion)
* Optional 8 MB Zorro II Fast RAM, switched off by default
* Optional 16 MB Zorro III Fast RAM with the 68020 (off by default; needs
  Kickstart 2.0 or newer - Kickstart 1.3 does not know Zorro III boards, so
  leave it off there)
* MEGA65 R4, R5 and R6 only: all Amiga memory lives in the board SDRAM
* Up to three floppy drives (`df0:`, `df1:`, `df2:`), one of them — `df0:`
  as a disk image — switched on by default: mount standard 880 KB `*.adf`
  disk images via the on-screen-menu, read and write — and hand one of the
  drives to the MEGA65's own internal 3.5" drive to read and write genuine
  Amiga disks, copy-protected originals included
* A Picasso96 graphics card (RTG) for the 68020, on HDMI: 8/16/24/32-bit
  screens in 4 MB of board memory
* Two IDE hard disks (master and slave): `*.hdf` images on the SD card, read
  and write, that Kickstart boots from (needs the free lide.device boot ROM)
* Kickstart 1.3 (256 KB) or 2.04 / 3.x (512 KB), one per profile, and
  switchable in the menu
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

The main page of the menu (<kbd>Help</kbd>) offers three machines:

| Profile       | CPU   | Chipset | Chip RAM | Slow RAM | Kickstart file       | Hard disks (master, slave)               |
|---------------|-------|---------|----------|----------|----------------------|------------------------------------------|
| A500 (OCS)    | 68000 | OCS     | 512 KB   | 512 KB   | `/amiga/a500.rom`    | `/amiga/a500.hdf`, `/amiga/a500-1.hdf`   |
| A600 (ECS)    | 68000 | ECS     | 1 MB     | -        | `/amiga/a600.rom`    | `/amiga/a600.hdf`, `/amiga/a600-1.hdf`   |
| A1200 (AGA)   | 68020 | AGA     | 2 MB     | -        | `/amiga/a1200.rom`   | `/amiga/a1200.hdf`, `/amiga/a1200-1.hdf` |

Selecting a profile reconfigures the Amiga and restarts it (a cold boot): it
loads the profile's Kickstart - `/amiga/kick.rom` if the profile's own file is
missing - and mounts the profile's hard disk images that exist (with none, the
profile has no hard disk). The profile is remembered, and at power-on the
core starts with it.

**Profile Settings** shows the details of the selected profile, and you can
change each of them: CPU, chipset, Chip RAM, Slow RAM, 8 MB Zorro II Fast RAM
and 16 MB Zorro III Fast RAM (68020 only). Every profile keeps its own
settings. The hard disk lines (**HDF 0** = master, **HDF 1** = slave) and the
**Kickstart** line there load any other file for the running session.

The floppy drives stay on the main page; the display, audio and keyboard
options are in **Settings**.

#### Setting up the profiles

1. **Kickstart ROMs.** Copy one ROM per profile into `/amiga` on the SD card,
   under the profile's name. The ROMs are raw dumps of 256 KB (1.3) or 512 KB
   (2.04, 3.x), no byte swapping and no encryption (for example from Cloanto's
   Amiga Forever):

   | File                | A good choice                                   |
   |---------------------|-------------------------------------------------|
   | `/amiga/a500.rom`   | Kickstart 1.3 (34.5, A500/A2000)                |
   | `/amiga/a600.rom`   | Kickstart 2.05 or 3.1 for the A600/A500         |
   | `/amiga/a1200.rom`  | Kickstart 3.1 for the A1200 (40.68) - an A500/A600 3.1 ROM does not drive AGA |

   Keep `/amiga/kick.rom` as well: the core needs it at power-on, and every
   profile without its own ROM uses it. Kickstart 1.3 knows neither Zorro III
   RAM nor the AGA chipset, so give the A1200 profile an A1200 3.x ROM.
2. **Hard disks (optional).** Copy an HDF image per profile to
   `/amiga/a500.hdf`, `/amiga/a600.hdf` or `/amiga/a1200.hdf` (the master,
   unit 0), optionally a second one to `/amiga/a500-1.hdf`, `a600-1.hdf` or
   `a1200-1.hdf` (the slave, unit 1), and the `lide.rom` of the release to
   `/amiga/lide.rom` (see Hard disks below). A profile without its own images
   starts without a hard disk; leave the files out to get a floppy-only
   machine.
3. **The settings file.** Copy `megamiga-<version>.cfg` from the release to
   `/amiga`, so that the core remembers the selected profile and every change
   in Profile Settings.
4. **Pick a profile.** Press <kbd>Help</kbd>, move to **A500 (OCS)**,
   **A600 (ECS)** or **A1200 (AGA)** and press <kbd>Return</kbd>. The Amiga
   restarts with that machine; the **Kickstart**, **HDF 0** and **HDF 1**
   lines in **Profile Settings** show which files it loaded.
5. **Adjust it (optional).** Open **Profile Settings** to change the CPU,
   chipset, Chip RAM or the RAM expansions of the selected profile - for
   example 8 MB Fast RAM for the A500 with a hard disk, or a 68000 for
   A1200 games that dislike the 68020. Each change restarts the Amiga and
   is stored for that profile only.

A typical card:

    /amiga/kick.rom          (required, e.g. a copy of a500.rom)
    /amiga/a500.rom          Kickstart 1.3
    /amiga/a600.rom          Kickstart 3.1 (A600)
    /amiga/a1200.rom         Kickstart 3.1 (A1200)
    /amiga/a1200.hdf         Workbench 3.1 hard disk for the A1200
    /amiga/a1200-1.hdf       a second disk for the A1200 (games, data)
    /amiga/lide.rom          hard disk boot ROM (from the release)
    /amiga/megamiga-<version>.cfg

### Kickstart ROM

The core needs a Kickstart ROM: 1.3 (the 256 KB version that shipped with the
Amiga 500) or a 512 KB A500/A600 ROM such as 2.04 or 3.1. Put it on your SD
card as

    /amiga/kick.rom

as a raw dump of exactly 256 KB or 512 KB, no byte swapping and no
encryption. Without this file the core stops with an error message.
Kickstart is copyrighted software, so it is not part of this repository or
of any release; you need to obtain a legal copy yourself, for example from
Cloanto's Amiga Forever.

Each machine profile loads its own Kickstart (see Machine profiles above) and
falls back to `/amiga/kick.rom`, which must always be there. To switch to
another Kickstart without touching the SD card, open **Profile Settings** in
the menu and pick a ROM file at **Kickstart**: the core loads it and restarts
the Amiga with it (a cold boot, the old memory contents are gone). That choice
is not saved - at the next power-on the profile's Kickstart is loaded again.

### Slow RAM (A501)

A small number of programs — typically early games — do not work correctly
on an Amiga that has expansion RAM: they place their graphics in the
expansion memory, which the Amiga's custom chips cannot display. **Rogue**
is a well-known example: with Slow RAM switched on it fails to draw the
dungeon and the player. On a real A500 the fix was to pull the trapdoor
card out of the machine; here it is a menu item. Open the menu with
<kbd>Help</kbd>, go to **Profile Settings** and deselect
**Slow RAM (512 KB)** (the A500 profile has it on): the Amiga automatically
reboots as a 512 KB chip-RAM-only A500, authentic down to the detail that
the expansion memory area behaves exactly like on a machine without the
trapdoor card. The setting is remembered, so switch it back on for
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

The Amiga can have two hard disks, master and slave on one IDE channel, as on
an A600 or A1200: `*.hdf` image files on your SD card, served
through an emulated Zorro II IDE controller that behaves exactly like LIV2's
open-source [RIPPLE](https://github.com/LIV2/RIPPLE-IDE) board. Its driver
and boot ROM is [lide.device](https://github.com/LIV2/lide.device) (GPL-2.0),
so Kickstart 1.3 finds the disk on its own and boots from it; Workbench sees
the partitions as `DH0:`, `DH1:` and so on. Reads and writes go straight to
the file on the SD card - there is no copy in memory and nothing to wait for
before a reset.

1. Copy the `lide.rom` from the core's release package to `/amiga/lide.rom`.
   Without it the core works as before, just without the hard disk. The
   release ships lide.device 40.12 with one fix for Workbench 1.3's Format
   (source: branch `aexp-td-format-fix` of
   [johansmolinski/lide.device](https://github.com/johansmolinski/lide.device/tree/aexp-td-format-fix));
   the official `lide.rom` of a
   [lide.device release](https://github.com/LIV2/lide.device/releases) works
   too, except for a full format (see below).
2. Copy your `*.hdf` images to the SD card. Named `/amiga/a500.hdf`,
   `a600.hdf` or `a1200.hdf`, an image is the master (unit 0) of that machine
   profile; named `a500-1.hdf`, `a600-1.hdf` or `a1200-1.hdf`, the slave
   (unit 1). They are mounted whenever the profile starts.
3. Any other image: open the menu with <kbd>Help</kbd>, go to **Profile
   Settings** and select **HDF 0:** (master) or **HDF 1:** (slave). Pick the
   image in the file browser. The Amiga restarts at once and boots from the
   hard disk (a floppy in `df0:` still has priority, as on a real Amiga).
4. To eject a disk, highlight its **HDF 0:** or **HDF 1:** line and press
   <kbd>Space</kbd> - on an empty line the same key opens the file browser.
   The Amiga restarts, because it only looks for its drives at a restart;
   with neither drive left, the IDE board leaves the Amiga's expansion list.

lide.device finds both drives on its own; HDToolBox lists them as units 0 and
1 of `lide.device`, and their partitions appear as `DH0:`, `DH1:` and so on
in the order of the drives. Never mount the same image as master and slave at
once: the two drives would write to one file without knowing of each other.

The image must be a whole hard disk with a partition table (a Rigid Disk
Block, RDB), not a single-partition "hardfile": WinUAE's "Create hardfile"
with RDB, or [amitools](https://github.com/cnvogelg/amitools)' `rdbtool`
make such images. Kickstart 1.3 has only the old file system (OFS) in ROM, so
either use OFS partitions, or put the FastFileSystem into the RDB (rdbtool
`fsadd`), which lide.device then loads at boot. The image size must be a
multiple of 512 bytes; FAT32 limits a file to 4 GB.

To format a partition on the Amiga, use `Format DRIVE DH0: NAME Work`, or
add `QUICK` to only write the empty file system (much faster, and just as
valid). With the official lide.device up to version 40.12 a full format fails
with "Error during format": it mixes up the block address of Workbench 1.3's
format command, which the patched `lide.rom` of the release fixes. Workbench
1.3's Format also needs one cylinder's worth of free memory, so partition
images for an unexpanded A500 with small cylinders (for example 2 heads x 32
sectors), or switch on the Fast RAM.

Hard disk access is a little slower than on a real IDE disk, because the
MEGA65's small control CPU serves every sector from the SD card. A disk stays
mounted until you eject it, mount another image on its line, select a machine
profile or swap the SD card; mounting an
image always restarts the Amiga, because Kickstart only looks for hard disks
when it starts.

### Graphics card (RTG, Picasso96)

Profiles with the 68020 (the A1200 profile, or any profile switched to the
68020 in **Profile Settings**) have a graphics card for Picasso96: Workbench
and RTG programs can open screens in 256 colours, 16 bit (65536 colours) or
24/32 bit, which the MEGA65 shows on its **HDMI** output. The 4 MB of board
memory hold for example 1024 x 768 in 32 bit or 1280 x 1024 in 16 bit.
It is MiSTer's Minimig RTG card: the same registers at `$B80100` and the same
Picasso96 driver, rebuilt for the 4 MB of board memory the MEGA65 has for it
(`$02000000`-`$023FFFFF`, in the HyperRAM).

You need Kickstart 3.x, Workbench 3.x and
[Picasso96 2.0](https://aminet.net/package/driver/video/Picasso96) from
Aminet. Install Picasso96 first, then copy the driver from the
`Megamiga_RTG.adf` disk of the release (or from `CORE/rtg/` of the source):

    Libs/Picasso96/MiSTer.card   to LIBS:Picasso96/
    Devs/Monitors/MiSTer         to DEVS:Monitors/  (with MiSTer.info)
    Devs/Picasso96Settings       to DEVS:           (the screen modes)

Reboot and pick one of the `MiSTer:` modes in Prefs/ScreenMode. The driver
keeps MiSTer's name, so MiSTer's settings files work unchanged.

The card has a blitter: Picasso96 hands rectangle fills and copies (window
moves, scrolling) to the FPGA instead of doing them with the 68020.

While an RTG screen is shown, the HDMI picture comes from the graphics card
and the analog VGA output keeps showing the normal Amiga picture. A reset
switches back to the Amiga picture. RTG needs the HDMI output.

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

HDMI outputs 720p at 50 Hz (16:9) by default. The first `HDMI:` menu
entry offers the other 50 Hz modes — 576p at 50 Hz in 4:3 or 5:4 — plus the
DVI switch that rescues displays which show nothing at all (see the end of
this section).

**An OCS PAL Amiga is a 50 Hz machine**, so only faithful 50 Hz modes are
offered. 

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
   disk-image line, or on **A500 (OCS)** if no drive is a disk image.
2. Six times <kbd>&darr;</kbd> — past the three machine profiles,
   **Profile Settings** and **Drive Settings**, onto **Settings**. That is
   **one <kbd>&darr;</kbd> per drive you have set to Disk Image, plus five**
   — six at the factory default. Moving the cursor over a profile does not
   select it; only <kbd>Return</kbd> does.
3. <kbd>Return</kbd> — opens Settings, cursor on the first `HDMI:` line.
4. <kbd>Return</kbd> — opens the HDMI menu, cursor on **720p 50 Hz 16:9**.
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

### Video: VGA port (analog RGB)

The VGA connector always carries the picture in parallel to HDMI. The
`VGA:` menu selects one of three modes:

* **Standard** (default): the Amiga's 15.6 kHz picture is line-doubled to
  31 kHz so that VGA monitors accept it. Note that it is still a 50 Hz
  signal, which not every flat panel likes.
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
* PAL only, no NTSC; the 68020 has no FPU and no MMU, and there is no 68030
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

1. Use a FAT32 formatted SD card with a maximum capacity of 32 GB. The card
   in the back slot has precedence over the card in the bottom slot.
2. Copy the Kickstart ROM to `/amiga/kick.rom` as described above.
3. Optional: copy the `megamiga-<version>.cfg` file that comes with the build
   into `/amiga` so that the core remembers your menu settings. Without the
   file nothing breaks, your settings are just not saved. The file name
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
