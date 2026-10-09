Megamiga RTG - Picasso96 driver for the MEGA65
==============================================

This disk holds MiSTer's Picasso96 RTG driver, rebuilt for Megamiga: the
graphics card has 4 MB of board memory (in the MEGA65's HyperRAM) at
$02000000. Source: CORE/rtg/MiSTer.card.asm in the Megamiga repository
(LGPL 2.1, Replay/FPGAArcade and MiSTer contributors).

Requirements: a profile with the 68020 (e.g. A1200), Kickstart 3.x,
Workbench 3.x and Picasso96 2.0 (Aminet: driver/video/Picasso96.lha).
The RTG picture is on the HDMI output only.

Install (after Picasso96):
  Copy Libs/Picasso96/MiSTer.card   to LIBS:Picasso96/
  Copy Devs/Monitors/MiSTer(.info)  to DEVS:Monitors/
  Copy Devs/Picasso96Settings       to DEVS:  (screen modes; replaces yours)
Reboot, then pick a "MiSTer:" mode in Prefs/ScreenMode.
