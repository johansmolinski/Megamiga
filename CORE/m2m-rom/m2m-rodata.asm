; ****************************************************************************
; Megamiga: read-only data of the core firmware
;
; The QNICE ROM ends at 0x7000 - from there on the RAMROM device window lies
; over it (M2M$RAMROM_DATA), so anything the assembler places at or above
; 0x7000 reads back as device data. Constant data that does not need to be in
; the ROM lives here instead: make_rom.sh assembles this file on its own into
; m2m-rodata.rom, which preloads the block RAM of the QNICE device
; C_DEV_AMIGA_RODATA (mega65.vhd), and exports every label as an .EQU of its
; WINDOW address (0x7000 + offset) to rodata_sym.asm. With that device and
; window 0 selected, a label reads exactly as if it were in memory.
;
; Use: RODATA_STR / RODATA_PUTS (strings, copied to RAM first) and
; M2M$LOAD_POLYPHASE (filter tables, any pointer >= 0x7000), all in
; m2m-rom.asm. Nothing here may be referenced directly as a memory pointer.
; Plain data only: no code, no .EQU (the export takes every symbol).
; ****************************************************************************

                .ORG    0x0000

; Warning: file size out of the valid ADF range
WRN_ADF_SIZE    .ASCII_P "\n\nThis is not a valid ADF disk image:\n"
                .ASCII_P "the file size must be 901,120 bytes\n"
                .ASCII_P "(880 KB standard ADF; 81..83-track over-\n"
                .ASCII_W "dumps up to 934,912 bytes are accepted).\n"

; Warning: could not write back the current disk before mounting a new one
WRN_ADF_BUSY    .ASCII_P "\n\nUnsaved changes on the current disk\n"
                .ASCII_P "could not be written back because the\n"
                .ASCII_P "Amiga keeps writing to the drive.\n"
                .ASCII_W "Stop the disk activity, then try again.\n"

; Warning: the same image file is already mounted in another drive
WRN_ADF_DUP     .ASCII_P "\n\nThis disk image is already in another\n"
                .ASCII_P "drive. One file cannot serve two drives\n"
                .ASCII_P "at once: each drive collects its own\n"
                .ASCII_P "changes and would save them over the\n"
                .ASCII_W "changes of the other one.\n"

; Warning: the image could not be read from the SD card (FAST_LOAD)
WRN_ADF_FAT     .ASCII_P "\n\nThe ADF file cannot be read from\n"
                .ASCII_W "the SD card (FAT32 error).\n"

; Warnings of the Kickstart selector
WRN_KICK_SIZE   .ASCII_P "\n\nThis is not a Kickstart ROM image:\n"
                .ASCII_P "the file size must be 256 KB or 512 KB\n"
                .ASCII_W "(a raw, unencrypted ROM dump).\n"
WRN_KICK_FAT    .ASCII_P "\n\nThe Kickstart file cannot be read from\n"
                .ASCII_P "the SD card (FAT32 error). The ROM is\n"
                .ASCII_W "incomplete: load another one.\n"

; Megamiga 0.3 machine profiles: Kickstart ROM and hard disk image per profile
; (PROFILE_APPLY in m2m-rom.asm; the name after "/amiga/" is what the menu shows)
PN_KICK         .ASCII_W "/amiga/kick.rom"
PN_K500         .ASCII_W "/amiga/a500.rom"
PN_K600         .ASCII_W "/amiga/a600.rom"
PN_K1200        .ASCII_W "/amiga/a1200.rom"
PN_H500         .ASCII_W "/amiga/a500.hdf"
PN_H600         .ASCII_W "/amiga/a600.hdf"
PN_H1200        .ASCII_W "/amiga/a1200.hdf"
PN_S500         .ASCII_W "/amiga/a500-1.hdf"
PN_S600         .ASCII_W "/amiga/a600-1.hdf"
PN_S1200        .ASCII_W "/amiga/a1200-1.hdf"

; Fatal: SD card write failed during the ADF write-back
WRN_HDF_NOROM   .ASCII_P "\n\nThe hard disk needs its boot ROM:\n"
                .ASCII_P "put lide.rom (lide.device for RIPPLE)\n"
                .ASCII_W "into /amiga on the SD card and restart.\n"
WRN_HDF_SIZE    .ASCII_P "\n\nThis is not a valid HDF image:\n"
                .ASCII_P "the file size must be a multiple of\n"
                .ASCII_W "512 bytes and at least 64 KB.\n"
WRN_HDF_FAT     .ASCII_P "\n\nThe HDF file cannot be read from\n"
                .ASCII_W "the SD card (FAT32 error).\n"
; IDE board: the IDENTIFY strings (IDE_IDENTIFY, one character per word)
IDE_ID_SERIAL   .ASCII_W "AEXP-HDF"
IDE_ID_FWREV    .ASCII_W "JS01"
IDE_ID_MODEL    .ASCII_W "Megamiga HDF image"
; live Hardware Floppy status line templates (HWF_STATUS_STEP; the drive digit is patched in)
HWF_OSM_IDLE    .ASCII_W "df0:Hardware Floppy   "
HWF_OSM_MOTOR   .ASCII_W "df0:HW Floppy: Motor  "
HWF_OSM_READ    .ASCII_W "df0:HW Floppy: Reading"
; screen adjustment (LOAD_SCREEN_OFFSETS)
SCR_FILE_NAME   .ASCII_W "/amiga/aexp_screen.cfg"
SCR_LOADING_STR .ASCII_W "<Loading Screen Config>"
ERR_ADF_FLUSH   .ASCII_W "ADF write-back: writing to the SD card failed.\n"

; serial-terminal (UART) log strings, MiSTer-style "new mode detected" trace
MSG_SCR_PFX       .ASCII_W "Screen: Amiga mode "
MSG_SCR_LORES     .ASCII_W "LORES"
MSG_SCR_HIRES     .ASCII_W "HIRES"
MSG_SCR_PROG      .ASCII_W " PROGRESSIVE"
MSG_SCR_LACE      .ASCII_W " INTERLACED"
MSG_SCR_GEO1      .ASCII_W "  (hdmax="
MSG_SCR_GEO2      .ASCII_W " vdmax="
MSG_SCR_GEO3      .ASCII_W ")"
MSG_SCR_HDMI      .ASCII_W "  HDMI: himin="
MSG_SCR_OFF2      .ASCII_W " himax="
MSG_SCR_OFF3      .ASCII_W " vimin="
MSG_SCR_OFF4      .ASCII_W " vimax="
MSG_SCR_VGA       .ASCII_W "  Analog: os_l="
MSG_SCR_VOF2      .ASCII_W " os_r="
MSG_SCR_VOF3      .ASCII_W " os_t="
MSG_SCR_VOF4      .ASCII_W " os_b="
MSG_SCR_VOF5      .ASCII_W " pan_x="
MSG_SCR_VOF6      .ASCII_W " pan_y="
MSG_SCR_UNSUP     .ASCII_W "screen: unsupported mode, adjustments disabled"

; Filter coefficient blobs for the polyphase-based options that the M2M
; framework does not already link: LANCZOS2_12 and SCAN_BR_110_80 come in
; via M2M/rom/filters.asm (included from M2M/rom/shell.asm); the three blobs
; below are core-local copies from C64MEGA65 V6 (see video_filters/README.md).
#include "video_filters/GS_Sharpness_050.asm"
#include "video_filters/CRT_Sim_Composite_H.asm"
#include "video_filters/CRT_Sim_SVideo_H.asm"
