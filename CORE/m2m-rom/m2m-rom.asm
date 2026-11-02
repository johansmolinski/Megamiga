; ****************************************************************************
; Amiga for Mega65 (AExp) QNICE ROM
;
; Main program that is used to build m2m-rom.rom by make-rom.sh.
;
; The execution starts at the label START_FIRMWARE.
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

; NOTE on comment style: this file is fed to the C preprocessor (see the asm
; wrapper in M2M/QNICE/assembler, which runs cc -xc -E), so an apostrophe or a
; double-quote is tokenized even inside a ; comment. So, in comments:
;   * avoid genitive apostrophes; use an of-construction instead (the
;     sub-activity of the menu selection, not the possessive apostrophe-s form);
;   * never split a double-quoted string across two lines (keep it on one line;
;     a balanced pair on ONE line is fine).
; Either slip only yields a harmless missing-terminating preprocessor warning.

; If the define RELEASE is defined, then the ROM will be a self-contained and
; self-starting ROM that includes the Monitor (QNICE "operating system") and
; jumps to START_FIRMWARE. In this case it is assumed, that the firmware is
; located in ROM and the variables are located in RAM.
;
; If RELEASE is not defined, then it is assumed that we are in the develop and
; debug mode so that the firmware runs in RAM and can be changed/loaded using
; the standard QNICE Monitor mechanisms such as "M/L" or QTransfer.

#define RELEASE

; ----------------------------------------------------------------------------
; Firmware: M2M system
; ----------------------------------------------------------------------------

; main.asm is the mandatory, so always include it
; It jumps to START_FIRMWARE (see below) after the QNICE "operating system"
; called "Monitor" has been included and initialized
#include "../../M2M/rom/main.asm"

; Only include the Shell, if you want to use the pre-build core automation
; and user experience. If you build your own, then remove this include and
; also remove the include "shell_vars.asm" in the variables section below.
#include "../../M2M/rom/shell.asm"

; ----------------------------------------------------------------------------
; Firmware: Main Code
; ----------------------------------------------------------------------------

                ; Run the Shell and before that, initialize:
                ; a) ADF write-back state. It cannot live in PREP_START, as
                ;    HANDLE_CORE_IO can already be reached during boot
                ;    (HANDLE_IO is polled from boot-time wait loops), and RAM
                ;    variables are undefined at power-on.
                ; b) Screen-centering feature
                ; c) Real-Time-Clock connector
                ; d) Live Hardware Floppy status line
                ; e) IDE board: no disk, out of the autoconfig chain
; SD_SPI_ONLY 1 keeps the SD host controller (M2M/vhdl/QNICE/sdhost.vhd) off the
; native 4-bit SD bus: SPI at 25 MHz only. IDE_ENGINE 0 leaves READ/WRITE SECTORS
; with the firmware ATA server (IDE_STEP) instead of the board's sector engine
; (ide_engine.vhd). Firmware-only variants (CORE/patch_firmware.sh, no synthesis).
#define SD_SPI_ONLY 0
#define IDE_ENGINE 1
; IDE_DIAG 1 (Megamiga 0.7, a diagnostics firmware): about once a second, while
; data moves, one line of the IDE board's diagnostics counters on the UART
; (115200 8N1, the MEGA65's debug UART): "IDE" and 14 x 8 hex digits, see
; ide_board.vhd (0x134/0x140). Firmware only: patch_firmware.sh switches it.
#define IDE_DIAG 1

START_FIRMWARE
#if SD_SPI_ONLY
                MOVE    1, R2                   ; both SD controllers (slot 1, 0)
_SF_SDS         MOVE    M2M$SD_SLOT, R0
                MOVE    R2, @R0
                MOVE    0xFF26, R0              ; sdhost register 6: SPI only,
                MOVE    1, @R0                  ; then re-initialise the card
                MOVE    IO$SD_CSR, R0           ; (busy ends after the init,
                MOVE    0, @R0                  ; also without a card)
_SF_SDW         MOVE    @R0, R1
                AND     0x8000, R1
                RBRA    _SF_SDW, !Z
                SUB     1, R2
                RBRA    _SF_SDS, !N
#endif
                RSUB    ADF_WB_INIT, 1
                RSUB    SCR_INIT, 1
                RSUB    RTC_INIT, 1
                RSUB    HWF_OSM_INIT, 1
                RSUB    SD_OSM_INIT, 1
                RSUB    IDE_INIT, 1
                RSUB    SHARE_INIT, 1           ; Megamiga 0.6.1: shared folder
                RBRA    START_SHELL, 1

; ----------------------------------------------------------------------------
; Core specific callback functions: Submenus
; ----------------------------------------------------------------------------

; SUBMENU_SUMMARY callback function:
;
; Called when displaying the main menu for every %s that is found in the
; "headline" / starting point of any submenu in config.vhd: You are able to
; change the standard semantics when it comes to summarizing the status of the
; very submenu that is meant by the "headline" / starting point.
;
; Input:
;   R8: pointer to the string that includes the "%s"
;   R9: pointer to the menu item within the M2M$CFG_OPTM_GROUPS structure
;  R10: end-of-menu-marker: if R9 == R10: we reached end of the menu structure
; Output:
;   R8: 0, if no custom SUBMENU_SUMMARY, else:
;       string pointer to completely new headline (do not modify/re-use R8)
;   R9, R10: unchanged

SUBMENU_SUMMARY XOR     R8, R8                  ; R8 = 0 = no custom string
                RET

; ----------------------------------------------------------------------------
; Core specific callback functions: File browsing and disk image mounting
; ----------------------------------------------------------------------------

; FILTER_FILES callback function:
;
; Called by the file- and directory browser. Used to make sure that the
; browser is only showing valid files and directories.
;
; Input:
;   R8: Name of the file in capital letters
;   R9: 0=file, 1=directory
;  R10: Context (see CTX_* in sysdef.asm)
;  R11: Menu group id (see config.vhd) of the menu item that is responsible
;       for triggering FILTER_FILES
; Output:
;   R8: 0=do not filter file, i.e. show file
FILTER_FILES    INCRB
                MOVE    R9, R0

                CMP     1, R9                   ; do not filter directories
                RBRA    _FFILES_RET_0, Z

                CMP     CTX_LOAD_ROM, R10       ; only filter in the ADF
                RBRA    _FFILES_RET_0, !Z       ; load context
                MOVE    HDF_FILE_EXT, R9        ; the HDF lines: .hdf files
                CMP     AEXP_OPTM_G_HDF, R11
                RBRA    _FFILES_EXT, Z
                CMP     AEXP_OPTM_G_HDF1, R11
                RBRA    _FFILES_EXT, Z
                CMP     AEXP_OPTM_G_QHDF, R11   ; (0.7: and the quick HDF)
                RBRA    _FFILES_EXT, Z
                MOVE    R8, R1                  ; R1: keep the directory entry
                MOVE    R11, R8                 ; one of the three mount items?
                RSUB    IS_ADF_GROUP, 1         ; (branch on C before anything
                RBRA    _FFILES_ADF, C          ; else can touch the flags)
                MOVE    R1, R8
                RBRA    _FFILES_RET_0, 1
_FFILES_ADF     MOVE    R1, R8                  ; restore the directory entry

                MOVE    ADF_FILE_EXT, R9        ; only show .adf files
_FFILES_EXT     RSUB    M2M$CHK_EXT, 1          ; preserves R8/R9/R10
                RBRA    _FFILES_RET_0, C        ; extension matched: show it

                MOVE    1, R8                   ; no match: filter it
                RBRA    _FFILES_RET, 1

_FFILES_RET_0   XOR     R8, R8                  ; R8 = 0 = do not filter file

_FFILES_RET     MOVE    R0, R9
                DECRB
                RET

; PREP_LOAD_IMAGE callback function:
;
; Some images need to be parsed, for example to extract configuration data or
; to move the file read pointer to the start position of the actual data.
; Sanity checks ("is this a valid file") can also be implemented here.
; Last but not least: The mount system supports the concept of a 2-bit
; "image type". In case this is used at the core of your choice, make sure
; you return the correct image type.
;
; The ADF is streamed into the C_DEV_AMIGA_ADF device, which bridges into a
; 4 MB HyperRAM region (see globals.vhd). We range-guard the file size to
; 160..166 tracks x 5632 bytes = 901,120..934,912 bytes BEFORE streaming, so
; an absurd (renamed) file can never stream past the region. The exact
; multiple-of-5632 validation happens in the core-side CSR responder
; (adf_mount_wrapper.vhd), which reports "Invalid ADF size" to the OSM.
;
; Input:
;   R8: File handle: You are allowed to modify the read pointer of the handle
;   R9: Context (see CTX_* in sysdef.asm)
;  R10: Menu group id (see config.vhd) of the menu item that is responsible
;       for triggering PREP_LOAD_IMAGE
; Output:
;   R8: 0=OK, error code otherwise
;   R9: image type if R8=0, otherwise 0 or optional ptr to  error msg string
PREP_LOAD_IMAGE INCRB

                CMP     CTX_LOAD_ROM, R9        ; only guard the ADF load
                RBRA    _PREP_LI_OK, !Z
                CMP     AEXP_OPTM_G_QHDF, R10   ; 0.7: the quick HDF of the
                RBRA    _PREP_LI_NQ, !Z         ; main page (never remembered)
                RSUB    QHDF_PREP, 1            ; R8/R9: result
                DECRB
                RET
_PREP_LI_NQ     CMP     AEXP_OPTM_G_HDF, R10    ; the HDF lines: own path,
                RBRA    _PREP_LI_H0, Z          ; R9 = the drive
                CMP     AEXP_OPTM_G_HDF1, R10
                RBRA    _PREP_LI_NHDF, !Z
                MOVE    1, R9                   ; slave
                RBRA    _PREP_LI_HDF, 1
_PREP_LI_H0     XOR     R9, R9                  ; master
_PREP_LI_HDF    MOVE    R8, R5                  ; R5: the file, R6: its ROM id
                MOVE    R9, R6
                ADD     PROF_HDF_ID, R6
                MOVE    SF_VIRTUAL, R4          ; a partition from the browser
                MOVE    @R4, R4                 ; (BROWSE_EXTRA: id = slot <<
                CMP     0, R4                   ; 8 | its number)
                RBRA    _PREP_LI_HP, Z
                SUB     1, R4
                MOVE    HDF_VPART, R7
                MOVE    R4, @R7
_PREP_LI_HP     MOVE    QHDF_ON, R4             ; 0.7: while the quick HDF is
                CMP     0, @R4                  ; on, the profile only notes
                RBRA    _PREP_LI_HQ, !Z         ; the file (mounted at its eject)
                RSUB    HDF_PREP, 1             ; R8/R9: result
                RBRA    _PREP_LI_REM, 1
_PREP_LI_HQ     RSUB    QHDF_HREM, 1            ; R8/R9: 0
                RBRA    _PREP_LI_REM, 1
_PREP_LI_NHDF   CMP     AEXP_OPTM_G_KICK, R10   ; the Kickstart selector: own path
                RBRA    _PREP_LI_NKCK, !Z
                MOVE    R8, R5
                MOVE    PROF_KICK_ID, R6
                RSUB    KICK_PREP, 1            ; R8/R9: result
_PREP_LI_REM    CMP     0, R8                   ; loaded: the profile remembers
                RBRA    _PREP_LI_RR, !Z         ; the file (cfg text)
                MOVE    R5, R8
                MOVE    R9, R4
                MOVE    R6, R9
                RSUB    PROF_REMEMBER, 1
                XOR     R8, R8
                MOVE    R4, R9
_PREP_LI_RR     DECRB
                RET
_PREP_LI_NKCK   CMP     AEXP_OPTM_G_AR3ROM, R10 ; Megamiga: the Action Replay III
                RBRA    _PREP_LI_NAR3, !Z       ; ROM: own path, remembered
                MOVE    R8, R5                  ; like the Kickstart
                MOVE    PROF_AR3_ID, R6
                RSUB    AR3_PREP, 1             ; R8/R9: result
                RBRA    _PREP_LI_REM, 1
_PREP_LI_NAR3   MOVE    R8, R5                  ; R5: keep the new file handle
                MOVE    R10, R8                 ; one of the three mount items?
                RSUB    IS_ADF_GROUP, 1         ; (branch on C before anything
                RBRA    _PREP_LI_ADF, C         ; else can touch the flags)
                MOVE    R5, R8
                RBRA    _PREP_LI_OK, 1
_PREP_LI_ADF    MOVE    R9, R6                  ; R6: the drive 0..2 behind the
                MOVE    R5, R8                  ; group id; restore the handle

                ; Every gate below is PER DRIVE. The write-back and the disarm
                ; act on the drive that is being (re)loaded, the size gate keeps
                ; a file out that is no ADF, and the duplicate gate keeps the
                ; same file out of two drives at once.
                ;
                ; Megamiga: the images are no longer copied anywhere - the track
                ; buffer (adf_sd.vhd) reads and writes the file on the SD card.
                ; BEFORE the drive gets its new file, every sector of the old
                ; disk that is still in the track buffer goes to the old file
                ; (ADF_TB_SYNC: the buffer still has the old extent map), then
                ; the drive is switched off in the buffer. The Shell has already
                ; unmounted the drive (ST_LDNG), so the Amiga cannot write to it
                ; any more and this ends within milliseconds; only a card that
                ; does not answer any more makes it time out.
                MOVE    R8, R3                  ; R3: handle of the new file
                MOVE    R6, R8
                RSUB    ADF_TB_SYNC, 1          ; R9: 0 = all written
                CMP     0, R9
                RBRA    _PREP_LI_FLD, Z
                MOVE    WRN_ADF_BUSY, R8        ; timed out: bail out
                RSUB    RODATA_STR, 1           ; (text in the read-only data
                MOVE    R8, R9                  ; device: copy it to RAM)
                MOVE    1, R8
                DECRB
                RET

                ; The mount flow OWNS the arm state: disarm the write-back of
                ; THIS drive here and let the PARSEST=READY of the NEW mount
                ; re-arm it with a fresh handle snapshot. HANDLE_CORE_IO alone
                ; cannot do that: the whole load runs without HANDLE_IO
                ; polling, so the READY -> LOADING -> READY transient of a
                ; re-mount is invisible to it.
_PREP_LI_FLD    MOVE    R6, R8
                RSUB    ADF_TB_OFF, 1           ; the old file is done with
                RSUB    ADF_DISARM, 1           ; WR_EN := 0 until the new
                MOVE    R3, R8                  ; mount is complete; restore
                                                ; the file handle

_PREP_LI_SIZE   MOVE    R8, R0                  ; R0: file size low word
                MOVE    R8, R1                  ; R1: file size high word
                ADD     FAT32$FDH_SIZE_LO, R0
                MOVE    @R0, R0
                ADD     FAT32$FDH_SIZE_HI, R1
                MOVE    @R1, R1

                ; Valid range: C_ADF_MIN_SIZE .. C_ADF_MAX_SIZE from
                ; globals.vhd, scraped into globals.asm by make_rom.sh so this
                ; gate can never drift from the HyperRAM map and the track
                ; engine geometry. A plain unsigned 32-bit range compare,
                ; high word first: QNICE CMP sets N for an unsigned src > dst
                ; (V is the signed one).
                CMP     ADF_MIN_SIZE_HI, R1     ; minimum > file: too small
                RBRA    _PREP_LI_BAD, N
                RBRA    _PREP_LI_MAX, !Z        ; minimum < file: minimum met
                CMP     ADF_MIN_SIZE_LO, R0     ; equal high word: compare low
                RBRA    _PREP_LI_BAD, N

_PREP_LI_MAX    CMP     R1, ADF_MAX_SIZE_HI     ; file > maximum: too big
                RBRA    _PREP_LI_BAD, N
                RBRA    _PREP_LI_DUP, !Z        ; file < maximum: maximum met
                CMP     R0, ADF_MAX_SIZE_LO     ; equal high word: compare low
                RBRA    _PREP_LI_BAD, N

                ; The same image file may not sit in two drives at once (the
                ; Amiga would see two disks with the same volume and could not
                ; tell them apart; before Megamiga 0.6.5 each drive also held
                ; its own copy, and the drive that flushed last overwrote the
                ; other's changes). The drive simply stays empty (the Shell has
                ; already unmounted it with ST_LDNG) and the user gets the file
                ; browser back.
_PREP_LI_DUP    MOVE    R6, R9
                RSUB    ADF_DUP_CHECK, 1        ; (branch on C before anything
                RBRA    _PREP_LI_DUPE, C        ; else can touch the flags)

                ; Megamiga: nothing is loaded. The track buffer gets the extent
                ; map of the file and reads its sectors from the SD card when
                ; the Amiga asks for them (ADF_TB_SETUP). The handle is left at
                ; the end of the file, so the Shell reads EOF at once and goes
                ; on with the CSR handshake (file size, STATUS=OK) as usual.
                MOVE    R6, R9                  ; R8: the handle, R9: the drive
                RSUB    ADF_TB_SETUP, 1         ; R8: 0, 1 = too fragmented,
                CMP     1, R8                   ; 2 = FAT32 error
                RBRA    _PREP_LI_FRAG, Z
                CMP     0, R8
                RBRA    _PREP_LI_FATE, !Z

_PREP_LI_OK     XOR     R8, R8                  ; no errors
                XOR     R9, R9                  ; image type hardcoded to 0
                DECRB
                RET

_PREP_LI_BAD    MOVE    1, R8                   ; error: invalid size
                MOVE    WRN_ADF_SIZE, R8
                RSUB    RODATA_STR, 1           ; (text in the read-only data
                MOVE    R8, R9                  ; device: copy it to RAM)
                MOVE    1, R8
                DECRB
                RET

_PREP_LI_DUPE   MOVE    1, R8                   ; error: already in a drive
                MOVE    WRN_ADF_DUP, R8
                RSUB    RODATA_STR, 1           ; (text in the read-only data
                MOVE    R8, R9                  ; device: copy it to RAM)
                MOVE    1, R8
                DECRB
                RET

_PREP_LI_FRAG   MOVE    WRN_ADF_FRAG, R8        ; error: more extents than the
                RSUB    RODATA_STR, 1           ; track buffer's map holds
                MOVE    R8, R9
                MOVE    1, R8
                DECRB
                RET

_PREP_LI_FATE   MOVE    1, R8                   ; error: SD card read failed
                MOVE    WRN_ADF_FAT, R8
                RSUB    RODATA_STR, 1           ; (text in the read-only data
                MOVE    R8, R9                  ; device: copy it to RAM)
                MOVE    1, R8
                DECRB
                RET

; ----------------------------------------------------------------------------
; Read-only data device (m2m-rodata.asm, mega65.vhd C_DEV_AMIGA_RODATA)
;
; The QNICE ROM ends at 0x8000 (the device window is at 0x8000-0x8FFF since the
; M2M-UPSTREAM rom-32k change; it used to be 0x7000-0x7FFF). Long texts and the
; filter tables of the core live in the read-only data device instead; their
; labels (rodata_sym.asm) are window addresses 0x8000-0x8FFF that are only valid
; while that device and window 0 are
; selected. Texts are therefore always copied into RODATA_BUF (RAM) before use,
; so the Shell, FATAL and puts see a plain RAM pointer.
;
; RODATA_STR: R8 = label of a zero-terminated text -> R8 = RODATA_BUF holding
; a copy (at most RODATA_BUF_SIZE - 1 characters). All other registers and the
; RAMROM selection are preserved. One buffer: a caller must use the text before
; the next RODATA_STR (the Shell copies a mount warning at once, FATAL halts).
RODATA_STR      INCRB
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    @R0, R1                 ; R1/R2: selection of the caller
                MOVE    M2M$RAMROM_4KWIN, R6
                MOVE    @R6, R2
                MOVE    AEXP_DEV_RODATA, @R0
                MOVE    0, @R6
                MOVE    RODATA_BUF, R3
                MOVE    RODATA_BUF_SIZE, R4
                SUB     1, R4
_RDS_L          MOVE    @R8++, R5
                MOVE    R5, @R3++
                CMP     0, R5
                RBRA    _RDS_E, Z
                SUB     1, R4
                RBRA    _RDS_L, !Z
                MOVE    0, @R3                  ; too long: truncated
_RDS_E          MOVE    R1, @R0
                MOVE    R2, @R6
                MOVE    RODATA_BUF, R8
                DECRB
                RET

; RODATA_PUTS: print the text R8 (label as above) to the serial terminal.
; All registers preserved.
RODATA_PUTS     MOVE    R8, @--SP
                RSUB    RODATA_STR, 1
                SYSCALL(puts, 1)
                MOVE    @SP++, R8
                RET

; ----------------------------------------------------------------------------
; FAST_LOAD: copy a whole file into a QNICE device, one SD sector at a time
;
; The Shell loads an image byte by byte through f32_fread, at several dozen
; instructions per byte. This is the fast path for the ADF drives and the
; Kickstart selector: FAT32$FILE_SEEK to each 512-byte boundary reads that
; sector into the one SD sector buffer (and makes the handle its owner), and
; the 512 bytes are then copied straight from IO$SD_DATA into the device
; window, one byte per window word, like the Shell writes them. Sequential
; seeks are cheap: the fast seek of the QNICE fork walks forward from the
; current cluster and reads a FAT sector only once per 128 clusters.
;
; The device sees exactly what the Shell would have written: byte offset n of
; the file goes to window n >> 12, word n & 0xFFF. Sector boundaries never
; cross a 4k window. A last partial sector is copied partially.
;
; It draws the same progress bar as the byte loader of the Shell, on the last line
; of the file browser window, which is still on screen while PREP_LOAD_IMAGE
; runs (the Shell redraws that line for its own, then empty, load).
;
; Input:  R8: file handle (any position), R9: QNICE device id
; Output: R8: unchanged; R9: 0 = OK, otherwise the FAT32 error code
;         The handle is at the end of the file. R10..R12 preserved - the
;         Shell keeps the CRT/ROM id in R12 across PREP_LOAD_IMAGE (LOAD_IMAGE
;         in M2M/rom/shell.asm), a clobbered R12 is fatal 0x0005 there. The
;         RAMROM selection is changed.
; ----------------------------------------------------------------------------
FAST_LOAD       MOVE    R10, @--SP
                MOVE    R11, @--SP
                MOVE    R12, @--SP
                INCRB
                MOVE    R8, R0                  ; R0: file handle
                MOVE    R9, R1                  ; R1: device
                MOVE    R0, R7                  ; R5:R4: file size
                ADD     FAT32$FDH_SIZE_LO, R7
                MOVE    @R7, R4
                MOVE    R0, R7
                ADD     FAT32$FDH_SIZE_HI, R7
                MOVE    @R7, R5
                XOR     R2, R2                  ; R3:R2: file offset
                XOR     R3, R3
                MOVE    R4, R8                  ; progress bar for this size
                MOVE    R5, R9
                RSUB    FL_BAR_INIT, 1

_FL_NEXT        MOVE    R4, R6                  ; R7:R6: bytes left
                MOVE    R5, R7
                SUB     R2, R6
                SUBC    R3, R7
                MOVE    R6, R10
                OR      R7, R10
                RBRA    _FL_DONE, Z
                MOVE    FAT32$SECTOR_SIZE, R12  ; R12: bytes from this sector
                CMP     0, R7
                RBRA    _FL_SEEK, !Z
                CMP     FAT32$SECTOR_SIZE, R6   ; sector size > bytes left?
                RBRA    _FL_SEEK, !N
                MOVE    R6, R12

_FL_SEEK        MOVE    R0, R8                  ; read the sector into the
                MOVE    R2, R9                  ; SD sector buffer
                MOVE    R3, R10
                SYSCALL(f32_fseek, 1)
                CMP     0, R9
                RBRA    _FL_RET, !Z

                MOVE    M2M$RAMROM_DEV, R8      ; the device and the 4k window:
                MOVE    R1, @R8                 ; window = offset >> 12
                MOVE    R3, R8
                AND     0xFFFD, SR              ; clear X: shift in zeros
                SHL     4, R8
                MOVE    R2, R9
                AND     0xFFFB, SR              ; clear C: shift in zeros
                SHR     12, R9
                OR      R9, R8
                MOVE    M2M$RAMROM_4KWIN, R9
                MOVE    R8, @R9
                MOVE    @R0, R8                 ; the SD controller of the file
                RSUB    SDC$SELDEV, 1           ; (M2M-UPSTREAM sd-host)
                MOVE    R2, R8                  ; R8: destination in the window
                AND     0x0FFF, R8
                ADD     M2M$RAMROM_DATA, R8

                MOVE    IO$SD_DATA_POS, R9
                MOVE    IO$SD_DATA, R10
                XOR     R11, R11                ; R11: byte in the sector
                MOVE    R12, R6                 ; R6: countdown
_FL_COPY        MOVE    R11, @R9
                MOVE    @R10, @R8++
                ADD     1, R11
                SUB     1, R6
                RBRA    _FL_COPY, !Z

                ADD     R12, R2                 ; next sector
                ADDC    0, R3
                RSUB    FL_BAR_STEP, 1
                RBRA    _FL_NEXT, 1

_FL_DONE        MOVE    R0, R8                  ; leave the handle at the end
                MOVE    R4, R9                  ; of the file: a later byte
                MOVE    R5, R10                 ; reader gets EOF at once
                SYSCALL(f32_fseek, 1)           ; R9: 0 or the error

_FL_RET         MOVE    R0, R8
                DECRB
                MOVE    @SP++, R12
                MOVE    @SP++, R11
                MOVE    @SP++, R10
                RET

; FL_BAR_INIT / FL_BAR_STEP: the progress bar of FAST_LOAD
;
; Same look and place as the bar of LOAD_IMAGE in M2M/rom/shell.asm: a frame
; of SCR$OSM_M_DX - 4 characters at x = 2 on the last line of the big window,
; filled with M2M$LD_PROGRESS characters from x = 3. FL_BAR_STEP is called once
; per sector and prints a character whenever the sectors done have crossed the
; next 1/width of the file (Bresenham: FL_BAR_ACC += width per sector, one
; character per FL_BAR_TOTAL). Files of 32 MB and more (more sectors than 16
; bits hold) get no bar. SCR$PRINTSTR saves and restores the RAMROM selection.
;
; FL_BAR_INIT input: R9:R8 = file size. All registers preserved.
FL_BAR_INIT     INCRB
                MOVE    R8, R4                  ; R5:R4: file size
                MOVE    R9, R5
                MOVE    R8, R6
                MOVE    R9, R7
                XOR     R2, R2                  ; R2: total sectors, 0 = no bar
                CMP     R5, 0x01FF              ; 32 MB or more (size high
                RBRA    _FBI_SET, N             ; word > 0x01FF)? no bar
                MOVE    R5, R2                  ; (size + 511) >> 9
                AND     0xFFFD, SR
                SHL     7, R2
                MOVE    R4, R3
                AND     0xFFFB, SR
                SHR     9, R3
                OR      R3, R2
                MOVE    R4, R3
                AND     0x01FF, R3
                RBRA    _FBI_SET, Z
                ADD     1, R2
_FBI_SET        MOVE    FL_NOBAR, R0            ; PROFILE_APPLY: no bar
                CMP     0, @R0
                RBRA    _FBI_SET2, Z
                XOR     R2, R2
_FBI_SET2       MOVE    FL_BAR_TOTAL, R0
                MOVE    R2, @R0
                MOVE    FL_BAR_ACC, R0
                MOVE    0, @R0
                CMP     0, R2
                RBRA    _FBI_RET, Z

                MOVE    SCR$OSM_M_DX, R0        ; R1: bar width
                MOVE    @R0, R1
                SUB     6, R1
                MOVE    FL_BAR_WIDTH, R0
                MOVE    R1, @R0
                MOVE    SCR$OSM_M_DY, R3        ; the frame: x = 2, last line
                MOVE    @R3, R3
                SUB     1, R3
                MOVE    2, R8
                MOVE    R3, R9
                RSUB    SCR$GOTOXY, 1
                MOVE    FL_BAR_LEFT, R8
                RSUB    SCR$PRINTSTR, 1
                MOVE    FL_BAR_SPACE, R8
_FBI_SP         RSUB    SCR$PRINTSTR, 1
                SUB     1, R1
                RBRA    _FBI_SP, !Z
                MOVE    FL_BAR_RIGHT, R8
                RSUB    SCR$PRINTSTR, 1
                MOVE    3, R8                   ; the progress starts at x = 3
                MOVE    R3, R9
                RSUB    SCR$GOTOXY, 1

_FBI_RET        MOVE    R6, R8
                MOVE    R7, R9
                DECRB
                RET

; FL_BAR_STEP: one sector done. All registers preserved.
FL_BAR_STEP     INCRB
                MOVE    R8, R6
                MOVE    FL_BAR_TOTAL, R0
                MOVE    @R0, R0                 ; R0: total sectors
                CMP     0, R0                   ; (MOVE leaves the flags alone)
                RBRA    _FBS_RET, Z             ; no bar
                MOVE    FL_BAR_ACC, R1
                MOVE    FL_BAR_WIDTH, R2
                ADD     @R2, @R1                ; acc += width
_FBS_L          CMP     R0, @R1                 ; total > acc: done
                RBRA    _FBS_RET, N
                SUB     R0, @R1
                MOVE    FL_BAR_PROG, R8
                RSUB    SCR$PRINTSTR, 1
                RBRA    _FBS_L, 1
_FBS_RET        MOVE    R6, R8
                DECRB
                RET

FL_BAR_LEFT     .DW     M2M$FC_HE_LEFT, 0
FL_BAR_RIGHT    .DW     M2M$FC_HE_RIGHT, 0
FL_BAR_SPACE    .DW     M2M$LD_SPACE, 0
FL_BAR_PROG     .DW     M2M$LD_PROGRESS, 0

; ----------------------------------------------------------------------------
; KICK_PREP: the PREP_LOAD_IMAGE part of the Kickstart selector (Memory menu)
;
; Accepts 256 KB (Kickstart 1.x, mirrored by the hardware) and 512 KB ROMs and
; loads them with FAST_LOAD into the Kickstart device. Megamiga 0.7: also 1 MB
; ROMs (AROS): the file's first half is the $E00000 half, the second the
; $F80000 half. The file size goes into the CSR (FS_LO/FS_HI) first, so that
; amiga_sdram.vhd knows where the first 512 KB belong (and clears the $E00000
; half for a smaller ROM). The Shell has already
; set the CSR of the device to LOADING, which holds the Amiga in reset
; (mega65.vhd, amiga_cold_boot.vhd); the STATUS=OK that follows this callback
; releases it with a cold boot. On an error the Shell leaves the CSR at
; LOADING, so we set it back to IDLE ourselves: the Amiga restarts and is not
; kept in reset for good. After a read error the ROM is incomplete, which the
; message says.
;
; Input:  R8: the file handle of the Shell (just opened)
; Output: R8: 0=OK, else error; R9: 0 or pointer to an error message;
;         R10..R12 preserved (see FAST_LOAD)
; ----------------------------------------------------------------------------
KICK_PREP       INCRB
                MOVE    R10, R4                 ; R4: R10 of the caller
                MOVE    R8, R0                  ; R0: the handle of the Shell
                MOVE    R0, R1                  ; R3:R2: file size
                ADD     FAT32$FDH_SIZE_LO, R1
                MOVE    @R1, R2
                MOVE    R0, R1
                ADD     FAT32$FDH_SIZE_HI, R1
                MOVE    @R1, R3
                CMP     0, R2                   ; 256 KB = 0x00040000,
                RBRA    _KP_BADSZ, !Z           ; 512 KB = 0x00080000 or
                CMP     KICK_256K_HI, R3        ; 1 MB = 0x00100000
                RBRA    _KP_LOAD, Z
                CMP     KICK_512K_HI, R3
                RBRA    _KP_LOAD, Z
                CMP     KICK_1M_HI, R3
                RBRA    _KP_BADSZ, !Z

_KP_LOAD        MOVE    AEXP_DEV_KICK, R8       ; the size for the HDL
                MOVE    CRTROM_CSR_FS_LO, R9
                MOVE    R2, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    CRTROM_CSR_FS_HI, R9
                MOVE    R3, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    R0, R8
                MOVE    AEXP_DEV_KICK, R9
                RSUB    FAST_LOAD, 1
                CMP     0, R9
                RBRA    _KP_FAT, !Z
                XOR     R8, R8
                XOR     R9, R9
                RBRA    _KP_RET, 1

_KP_BADSZ       MOVE    WRN_KICK_SIZE, R1
                RBRA    _KP_ERR, 1
_KP_FAT         MOVE    WRN_KICK_FAT, R1
_KP_ERR         MOVE    AEXP_DEV_KICK, R8       ; LOADING -> IDLE: let the
                MOVE    CRTROM_CSR_STATUS, R9   ; Amiga run again
                MOVE    CRTROM_CSR_ST_IDLE, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    R1, R8                  ; (text in the read-only data
                RSUB    RODATA_STR, 1           ; device: copy it to RAM)
                MOVE    R8, R9
                MOVE    1, R8
_KP_RET         MOVE    R4, R10
                DECRB
                RET

; ----------------------------------------------------------------------------
; AR3_PREP: the PREP_LOAD_IMAGE part of the " AR3 ROM:%s" line (Profile Settings)
;
; Megamiga: the Action Replay III cartridge ROM, bring your own. Like KICK_PREP,
; but only exactly 256 KB is accepted, and it goes into the AR3 device
; (C_DEV_AMIGA_AR3, mega65.vhd), which streams it into the cartridge bank of the
; SDRAM. The HDL counts the ROM as loaded once byte $3FFFF arrived; a profile with
; "Cart: Action Replay 3" then cold-boots with the cartridge plugged in.
;
; Input:  R8: the file handle of the Shell (just opened)
; Output: R8: 0=OK, else error; R9: 0 or pointer to an error message;
;         R10..R12 preserved (see FAST_LOAD)
; ----------------------------------------------------------------------------
AR3_PREP        INCRB
                MOVE    R10, R4                 ; R4: R10 of the caller
                MOVE    R8, R0                  ; R0: the handle of the Shell
                MOVE    R0, R1                  ; R3:R2: file size
                ADD     FAT32$FDH_SIZE_LO, R1
                MOVE    @R1, R2
                MOVE    R0, R1
                ADD     FAT32$FDH_SIZE_HI, R1
                MOVE    @R1, R3
                CMP     0, R2                   ; 256 KB = 0x00040000
                RBRA    _A3P_BADSZ, !Z
                CMP     KICK_256K_HI, R3
                RBRA    _A3P_BADSZ, !Z

                MOVE    R0, R8
                MOVE    AEXP_DEV_AR3, R9
                RSUB    FAST_LOAD, 1
                CMP     0, R9
                RBRA    _A3P_FAT, !Z
                XOR     R8, R8
                XOR     R9, R9
                RBRA    _A3P_RET, 1

_A3P_BADSZ      MOVE    WRN_AR3_SIZE, R1
                RBRA    _A3P_ERR, 1
_A3P_FAT        MOVE    WRN_AR3_FAT, R1
_A3P_ERR        MOVE    AEXP_DEV_AR3, R8        ; LOADING -> IDLE: let the
                MOVE    CRTROM_CSR_STATUS, R9   ; Amiga run again
                MOVE    CRTROM_CSR_ST_IDLE, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    R1, R8                  ; (text in the read-only data
                RSUB    RODATA_STR, 1           ; device: copy it to RAM)
                MOVE    R8, R9
                MOVE    1, R8
_A3P_RET        MOVE    R4, R10
                DECRB
                RET

; ----------------------------------------------------------------------------
; PROFILE_APPLY: the Kickstart and the hard disks of a machine profile
;
; Megamiga 0.3: the main menu selects a machine profile (A500 / A600 / A1200;
; A4000 since 0.6.4).
; The HDL applies its CPU, chipset and RAM settings (mega65.vhd prof_decode,
; a cold boot of the Amiga). Here the files of the profile are loaded.
;
; Megamiga 0.6.1: everything is explicit. A profile loads only the files the
; user chose for it through the menu (the settings file remembers them by
; path, B2_PROF_SAVED); nothing chosen = nothing loaded. The one exception is
; the Kickstart: a profile without a chosen Kickstart uses /amiga/kick.rom
; (an optional boot-time load since 0.6.1). Without either - or if the chosen
; Kickstart cannot be loaded - the Amiga is held in reset (Kickstart CSR at
; LOADING: black screen) until the user loads one.
; The menu lines Kickstart and HDF show the names, as after a manual load.
;
; The Action Replay III ROM (since 0.6.5): a profile loads the one it remembers;
; a profile without one keeps the ROM that is loaded (/amiga/ar3.rom from the
; boot, or the last profile's) - the profile's cartridge radio decides whether
; the cartridge is plugged in at all.
;
; At boot (PREP_START) /amiga/kick.rom is already loaded if it exists, and no
; HDF is mounted.
;
; The files are opened through the device handle of their card (M2M-UPSTREAM
; sd-host, two slots: a remembered path names its card, "SD0:" or "SD1:";
; kick.rom comes from the card of the settings file), the one the file browser
; uses too; the SD sector buffer of a card is tracked per device handle.
;
; Input:  R8: profile 0..3, R9: 0 = boot, 1 = the user selected the profile
; Output: none, all registers preserved
; ----------------------------------------------------------------------------
PROFILE_APPLY   SYSCALL(enter, 1)
                MOVE    R8, R0                  ; R0: profile
                MOVE    R9, R1                  ; R1: 1 = switch, 0 = boot
                MOVE    PROF_PENDF, R8          ; no menu names waiting yet
                MOVE    0, @R8++                ; (PROF_PEND follows)
                MOVE    0, @R8++
                MOVE    0, @R8++
                MOVE    0, @R8++
                MOVE    0, @R8

                ; the Kickstart: hold the Amiga while the ROM is replaced
_PA_KICK        MOVE    FL_NOBAR, R2            ; no progress bar: the menu
                MOVE    1, @R2                  ; is on screen
                MOVE    R0, R8                  ; one the profile remembers?
                MOVE    PROF_KICK_ID, R9        ; (C=1: open, R8: its name;
                RSUB    PROF_SAVED, 1           ; C=0: R8 = 0 none chosen, 1
                MOVE    R8, R3                  ; chosen but not there)
                RBRA    _PA_KLD, C
                CMP     0, R8
                RBRA    _PA_KHOLD, !Z           ; chosen, not there: hold
                CMP     0, R1                   ; boot: kick.rom is loaded if
                RBRA    _PA_KSW, !Z             ; it exists
                MOVE    CRTROM_AUT_LDF, R8      ; (auto-load ROM 0, see
                CMP     0, @R8                  ; C_CRTROMS_AUTO)
                RBRA    _PA_KHOLD, Z
                MOVE    PN_KICK, R8             ; 0.7: a 1 MB kick.rom (AROS)
                MOVE    R8, R3                  ; again through KICK_PREP: the
                RSUB    PROF_OPEN, 1            ; auto-load gives amiga_sdram
                RBRA    _PA_KNM, !C             ; no file size, so its first
                MOVE    PROF_FDH, R8            ; half is not at $E00000
                ADD     FAT32$FDH_SIZE_HI, R8
                CMP     KICK_1M_HI, @R8
                RBRA    _PA_KLD, Z
_PA_KNM         MOVE    PN_KICK, R8             ; its name in the menu
                MOVE    PROF_KICK_ID, R9
                RSUB    PROF_NAME, 1
                RBRA    _PA_HDF, 1
_PA_KSW         MOVE    PN_KICK, R8             ; switch: kick.rom
                MOVE    R8, R3
                RSUB    PROF_OPEN, 1
                RBRA    _PA_KHOLD, !C
_PA_KLD
                MOVE    AEXP_DEV_KICK, R8       ; LOADING holds the Amiga
                MOVE    CRTROM_CSR_STATUS, R9   ; in reset
                MOVE    CRTROM_CSR_ST_LDNG, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    PROF_FDH, R8
                RSUB    KICK_PREP, 1            ; error: CSR back to IDLE
                CMP     0, R8
                RBRA    _PA_KHOLD, !Z
                MOVE    AEXP_DEV_KICK, R8       ; OK: the cold boot
                MOVE    CRTROM_CSR_STATUS, R9
                MOVE    CRTROM_CSR_ST_OK, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    R3, R8
                MOVE    PROF_KICK_ID, R9
                RSUB    PROF_NAME, 1
                RBRA    _PA_HDF, 1

                ; no Kickstart: the Amiga stays in reset, the menu shows <Load>
_PA_KHOLD       MOVE    AEXP_DEV_KICK, R8
                MOVE    CRTROM_CSR_STATUS, R9
                MOVE    CRTROM_CSR_ST_LDNG, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    CRTROM_MAN_LDF, R8
                ADD     PROF_KICK_ID, R8
                MOVE    0, @R8
                MOVE    PROF_PEND, R8
                ADD     PROF_KICK_ID, R8
                SUB     PROF_HDF_ID, R8
                MOVE    0, @R8

_PA_HDF         MOVE    R0, R8                  ; the hard disks
                MOVE    R1, R9
                RSUB    PROF_HDFS, 1

                MOVE    R0, R8                  ; the Action Replay III ROM
                MOVE    R1, R9
                RSUB    PROF_AR3_APPLY, 1

_PA_RET         MOVE    FL_NOBAR, R2
                MOVE    0, @R2
                SYSCALL(leave, 1)
                RET

; PROF_HDFS: the hard disks of profile R8 (R9: 0 = boot, 1 = a switch: a drive
; the profile has none for is emptied). Megamiga 0.7: while the quick HDF is
; on (QHDF_ON), the drives keep it - the lines only show the profile's names.
; Also called when the quick HDF is ejected (B3_HDF_SPACE). Registers preserved.
PROF_HDFS       SYSCALL(enter, 1)
                MOVE    R8, R0                  ; R0: profile
                MOVE    R9, R1                  ; R1: 1 = switch, 0 = boot
                XOR     R4, R4                  ; R4: drive, 0 master, 1 slave
_PA_HL          MOVE    R0, R8                  ; one the profile remembers?
                MOVE    PROF_HDF_ID, R9
                ADD     R4, R9
                RSUB    PROF_SAVED, 1
                MOVE    R8, R3                  ; R3: its name
                RBRA    _PA_HNO, !C             ; none: no drive there
                MOVE    QHDF_ON, R8             ; (the quick HDF: the name only)
                CMP     0, @R8
                RBRA    _PA_HOK, !Z
                MOVE    PROF_FDH, R8
                MOVE    R4, R9
                RSUB    HDF_PREP, 1             ; mounts, restarts the Amiga
                CMP     0, R8
                RBRA    _PA_HNX, !Z
_PA_HOK         MOVE    HDF_DEV_TAB, R8         ; the menu line counts as
                ADD     R4, R8                  ; loaded: STATUS OK on its
                MOVE    @R8, R8                 ; device (CRTROM_MLST_GET)
                MOVE    CRTROM_CSR_STATUS, R9
                MOVE    CRTROM_CSR_ST_OK, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    R3, R8
                MOVE    PROF_HDF_ID, R9         ; manual ROM 4 or 5
                ADD     R4, R9
                RSUB    PROF_NAME, 1
                RBRA    _PA_HNX, 1
_PA_HNO         CMP     0, R1                   ; switch without this HDF in
                RBRA    _PA_HNX, Z              ; the profile: drive absent
                MOVE    QHDF_ON, R8             ; (unless the quick HDF holds
                CMP     0, @R8                  ; the drives: then only the
                RBRA    _PA_HNQ, !Z             ; line)
                MOVE    R4, R8
                ADD     1, R8                   ; drive mask: 1 or 2
                RSUB    HDF_DROP, 1
                RBRA    _PA_HNL, 1
_PA_HNQ         MOVE    HDF_DEV_TAB, R8         ; (what HDF_DROP does for the
                ADD     R4, R8                  ; line: STATUS IDLE)
                MOVE    @R8, R8
                MOVE    CRTROM_CSR_STATUS, R9
                MOVE    CRTROM_CSR_ST_IDLE, R10
                RSUB    CRTROM_CSR_W, 1
_PA_HNL         MOVE    CRTROM_MAN_LDF, R8      ; the menu shows <Load>
                ADD     PROF_HDF_ID, R8
                ADD     R4, R8
                MOVE    0, @R8
                MOVE    PROF_PEND, R8           ; and no name is waiting for it
                ADD     R4, R8
                MOVE    0, @R8
_PA_HNX         ADD     1, R4
                CMP     2, R4
                RBRA    _PA_HL, !Z
                CMP     0, R1                   ; switch to a profile without
                RBRA    _PH_RET, Z              ; any HDF: the board leaves the
                MOVE    HDF_UNITS, R8           ; autoconfig chain
                CMP     0, @R8
                RBRA    _PH_RET, !Z
                RSUB    IDE_SEL, 1
                MOVE    IDE_CTRL, R8
                MOVE    0, @R8
_PH_RET         SYSCALL(leave, 1)
                RET

; PROF_OPEN: open a file of the read-only data device (label in R8) into
; PROF_FDH, on the card of the settings file. Output: C=1 and R8 = the name
; after "/amiga/" (in RODATA_BUF) if it is open, C=0 if not. R9..R12
; preserved.
PROF_OPEN       INCRB
                MOVE    R9, R0
                MOVE    R10, R1
                MOVE    R11, R2
                RSUB    RODATA_STR, 1           ; the path in RAM
                MOVE    R8, R3
                MOVE    R8, R10
                RSUB    SDC$HOMEDEV, 1          ; R8: device, R9: 0 = mounted
                CMP     0, R9
                RBRA    _PO_NM, Z
                MOVE    R9, R10                 ; (an error code: not open)
                RBRA    _PO_ERR, 1
_PO_NM          MOVE    PROF_FDH, R9
                XOR     R11, R11                ; "/" separator
                SYSCALL(f32_fopen, 1)
_PO_ERR         MOVE    R3, R8
                ADD     PROF_DIR_LEN, R8        ; skip "/amiga/"
                MOVE    R10, R4                 ; R4: error code
                MOVE    R0, R9
                MOVE    R2, R11
                MOVE    R1, R10
                CMP     0, R4                   ; (the flags of the last MOVE
                RBRA    _PO_NO, !Z              ; must not decide this)
                OR      0x0004, SR              ; C=1
                DECRB
                RET
_PO_NO          AND     0xFFFB, SR              ; C=0
                DECRB
                RET

; PROF_NAME: show the file loaded from path R8 (a read-only data label) on the
; menu line of manual ROM R9 (PROF_HDF_ID..PROF_AR3_ID), like the Shell does
; after a load from the file browser. All registers preserved.
;
; The name buffers of the menu (OPTM_HEAP) only exist once the menu has been
; opened. At core start they do not, so the label is kept in PROF_PEND and
; PROF_PEND_APPLY (HANDLE_CORE_IO) shows it when the menu opens. That runs in
; the key loop of the menu BEFORE the Shell polls the loaded flags, and the
; flag is set only together with the name: a line never shows a name that is
; not there.
PROF_NAME       SYSCALL(enter, 1)
                MOVE    OPTM_HEAP, R0
                CMP     0, @R0
                RBRA    _PN_SHOW, !Z            ; the menu exists: show it now
                MOVE    PROF_PEND, R0           ; not yet: remember the label
                ADD     R9, R0
                SUB     PROF_HDF_ID, R0
                MOVE    R8, @R0
                MOVE    PROF_PENDF, R0
                MOVE    1, @R0
                RBRA    _PN_RET, 1
_PN_SHOW        MOVE    R8, R2                  ; a name in RAM (a file the
                AND     0xF000, R2              ; profile remembers, PROF_SAVED)
                CMP     0x8000, R2              ; or a read-only data label
                RBRA    _PN_RAM, !Z
                RSUB    RODATA_STR, 1           ; the path in RAM
                ADD     PROF_DIR_LEN, R8        ; skip "/amiga/"
_PN_RAM         MOVE    R8, R2                  ; R2: the name
                MOVE    CRTROM_MAN_LDF, R0      ; "loaded"
                ADD     R9, R0
                MOVE    1, @R0
                MOVE    R9, R8                  ; heap slot: (vdrives +
                MOVE    VDRIVES_NUM, R0         ; submenus + ROM id) x DX
                ADD     @R0, R8
                MOVE    OPTM_SCOUNT, R0
                ADD     @R0, R8
                MOVE    SCR$OSM_O_DX, R9
                MOVE    @R9, R9
                SYSCALL(mulu, 1)
                MOVE    OPTM_HEAP, R0
                MOVE    @R0, R0
                ADD     R10, R0
                MOVE    R2, R8                  ; (the names are short)
                MOVE    R0, R9
                SYSCALL(strcpy, 1)
                MOVE    SCR$OSM_O_DX, R8        ; "%s is replaced" = 0
                MOVE    @R8, R8
                SUB     1, R8
                ADD     R0, R8
                MOVE    0, @R8
_PN_RET         SYSCALL(leave, 1)
                RET

; PROF_PEND_APPLY: once the menu exists, show the names PROF_NAME had to keep
; back (see there). Cheap while nothing waits. All registers preserved.
PROF_PEND_APPLY SYSCALL(enter, 1)
                MOVE    PROF_PENDF, R0
                CMP     0, @R0
                RBRA    _PPA_RET, Z             ; nothing waiting
                MOVE    OPTM_HEAP, R1
                CMP     0, @R1
                RBRA    _PPA_RET, Z             ; no menu yet
                MOVE    0, @R0
                MOVE    PROF_PEND, R0
                MOVE    PROF_HDF_ID, R9         ; R9: ROM id
                MOVE    PROF_PEND_NUM, R2       ; R2: lines left
_PPA_LOOP       MOVE    @R0, R8
                MOVE    0, @R0++
                CMP     0, R8
                RBRA    _PPA_NEXT, Z
                RSUB    PROF_NAME, 1
_PPA_NEXT       ADD     1, R9
                SUB     1, R2
                RBRA    _PPA_LOOP, !Z
_PPA_RET        SYSCALL(leave, 1)
                RET

HDF_DEV_TAB     .DW     AEXP_DEV_IDE, AEXP_DEV_IDE1         ; the device of each HDF line

; ----------------------------------------------------------------------------
; Core specific callback functions: Custom tasks
; ----------------------------------------------------------------------------

; PREP_START callback function:
;
; Called right before the core is being started. At this point, the core
; is ready to run, settings are loaded (if the core uses settings) and the
; core is still held in reset (if RESET_KEEP is on). So at this point in time,
; you can execute tasks that change the run-state of the core.
;
; Input: None
; Output:
;   R8: 0=OK, else pointer to string with error message
;   R9: 0=OK, else error code
PREP_START      INCRB

                ; Apply the saved HDMI Filter selection. At this point the
                ; framework has already loaded its own default into the
                ; ascal polyphase RAM (LANCZOS2_12 + SCAN_BR_110_80 via
                ; M2M/rom/filters.asm:LOAD_ASCAL_FLT), and HELP_MENU_INIT has
                ; populated M2M$CFM_DATA from the saved SD config. We now
                ; overwrite the framework default with whatever the user
                ; chose -- before the core un-resets and the first frame
                ; reaches HDMI, so no glitch is visible. The default
                ; selection in config.vhd is "Lanczos" (LANCZOS2_12 on both
                ; axes), so for first-time users (or anyone with an empty
                ; config) this replaces the Scanlines-look preload of the
                ; framework before it ever reaches the screen.
                RSUB    LOAD_HDMI_FILTER, 1

                ; Apply the screen-centering offsets (HDMI ascal window) from
                ; /amiga/aexp_screen.cfg (zeros if absent) before the core
                ; un-resets so the first frame is already positioned.
                RSUB    LOAD_SCREEN_OFFSETS, 1

                RSUB    CFG_SIGWARN, 1          ; a settings file was reset

                ; Megamiga 0.3: the Kickstart and the hard disk of the saved
                ; machine profile (the HDL already runs its CPU/chipset/RAM)
                RSUB    PRF_BOOT, 1             ; 0.7: the active profile file
                XOR     R0, R0                  ; R0: profile (0.7: always 0)
                MOVE    R0, R8
                XOR     R9, R9                  ; 0 = boot
                RSUB    PROFILE_APPLY, 1

                ; the shared folder starts unmounted, whatever the settings
                ; file says ("Mount SDCard" is not a saved setting)
                MOVE    AEXP_OSM_SHARE, R8
                XOR     R9, R9
                RSUB    M2M$SET_SETTING, 1
                MOVE    SHR_INSW, R0
                MOVE    0, @R0

                XOR     R8, R8
                XOR     R9, R9
                DECRB
                RET

; OSM_SEL_POST callback function:
;
; Called each time the user selects something in the on-screen-menu (OSM),
; and while the OSM is still visible. This means, that this callback function
; is called on each press of one of the valid selection keys with the
; exception that pressing a selection key while hovering over a submenu entry
; or exit point does not call this function. All the functionality and
; semantics associated with a certain menu item is already handled by the
; framework when OSM_SELECTED is called, so you are not able to change the
; basic semantics but you are able to add core specific additional
; "intelligent" semantics and behaviors.
;
; Input:
;   R8: selected menu group (as defined in config.vhd)
;   R9: selected item within menu group
;       in case of single selected items: 0=not selected, 1=selected
;   R10: OPTM_KEY_SELECT (by default means "Return") or
;        OPTM_KEY_SELALT (by default means "Space")
; Output:
;   R8: 0=OK, else pointer to string with error message
;   R9: 0=OK, else error code
OSM_SEL_POST    INCRB

                ; issue #16: the sub-activity of the menu selection (file
                ; browser / help viewer) has returned - drop the gate-4 flag so
                ; SPACE-unmount works again. Reached on EVERY non-fatal path out
                ; of OPTM_CB_SEL (incl. the CLOSE early-out via _OPTMCB_RET), so
                ; the flag can never stick at 1. R8 (the selected group, used
                ; below) is untouched: R0 is bank-local after the INCRB.
                MOVE    OSM_SUB_ACTIVE, R0
                MOVE    0, @R0

                ; Megamiga 0.7: profiles as files. " Profile:" opens the
                ; profile selector, " Rename Profile" the name editor (both
                ; momentary); a setting of the block marks the profile dirty
                CMP     AEXP_OPTM_G_PROFILE, R8
                RBRA    _OSM_SP_PRN, !Z
                RSUB    PRF_SELECT, 1
                RBRA    _OSP_MOMENT, 1
_OSM_SP_PRN     CMP     AEXP_OPTM_G_PROFREN, R8
                RBRA    _OSM_SP_PCH, !Z
                RSUB    PRF_RENAME, 1
                RBRA    _OSP_MOMENT, 1
_OSM_SP_PCH     RSUB    PRF_CHANGED, 1

                ; HDMI Filter selection changed: re-push the matching (H, V)
                ; coefficient pair into the ascal polyphase RAM. NO core
                ; reset -- only the coefficient RAM content changes; the
                ; Amiga keeps running. The user sees the new filter from the
                ; next frame.
_OSM_SP_FLT     CMP     AEXP_OPTM_G_FILTER, R8
                RBRA    _OSM_SP_DRV, !Z
                RSUB    LOAD_HDMI_FILTER, 1
                RBRA    _OSM_SEL_POST_R, 1

                ; "Reload Screen Config" pressed. This is a MOMENTARY action,
                ; not an on/off toggle (issue #19): show <Loading Screen Config>
                ; on the line of the item for the ~1-2 s the SD re-mount +
                ; reload takes -- the OSM is frozen meanwhile because QNICE
                ; serves the menu synchronously -- then repaint the original
                ; label with no "=" checkmark left behind.
                ; Drive Settings: keep the "Drives" count radio and the three
                ; per-drive mode radios consistent. The HDL decode is defensive
                ; about an inconsistent combination, but the MENU must not show
                ; one: a drive beyond the count has to sit on its "Off" item,
                ; because that item is what the count radio swaps in (menu
                ; dependency), and it is also what hides the two lines of that drive
                ; in the main menu. And only one physical mechanism exists, so
                ; "Hardware Floppy" has to be stolen from the other drives.
                ; Everything else - the Amiga cold boot, the twin-line
                ; visibility, the live redraw - happens in the HDL and in the
                ; framework; this is purely about the model staying sane.
_OSM_SP_DRV     CMP     AEXP_OPTM_G_DRIVES, R8
                RBRA    _OSM_SP_DRVM, !Z
                RSUB    DRV_ENFORCE_COUNT, 1
                RSUB    DRV_EJECT_GONE, 1
                RBRA    _OSM_SEL_POST_R, 1

_OSM_SP_DRVM    CMP     AEXP_OPTM_G_DF0MODE, R8
                RBRA    _OSM_SP_DRVM1, !Z
                XOR     R8, R8                    ; R8: the drive that changed
                RBRA    _OSM_SP_DRVS, 1
_OSM_SP_DRVM1   CMP     AEXP_OPTM_G_DF1MODE, R8
                RBRA    _OSM_SP_DRVM2, !Z
                MOVE    1, R8
                RBRA    _OSM_SP_DRVS, 1
_OSM_SP_DRVM2   CMP     AEXP_OPTM_G_DF2MODE, R8
                RBRA    _OSM_SP_SCR, !Z
                MOVE    2, R8
_OSM_SP_DRVS    RSUB    DRV_STEAL_HW, 1
                RSUB    DRV_EJECT_GONE, 1
                RBRA    _OSM_SEL_POST_R, 1

                ; Megamiga: "Freeze cartridge" pressed - the cartridge's freeze
                ; button (mega65.vhd: a write to window 0xFFFE of the AR3 device
                ; presses it for ~4.6 ms, for HRTmon and the Action Replay III
                ; alike; without a cartridge nothing happens). MOMENTARY like
                ; "Reload Screen Config": no "=" mark stays behind. The Amiga is
                ; frozen right away; closing the menu shows the freezer.
_OSM_SP_SCR     CMP     AEXP_OPTM_G_FREEZE, R8
                RBRA    _OSM_SP_SCR2, !Z
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    @R0, R1                 ; R1/R2: the selection, kept
                MOVE    M2M$RAMROM_4KWIN, R6
                MOVE    @R6, R2
                MOVE    AEXP_DEV_AR3, @R0
                MOVE    0xFFFE, @R6
                MOVE    M2M$RAMROM_DATA, R7
                MOVE    1, @R7
                MOVE    R1, @R0
                MOVE    R2, @R6
                RBRA    _OSP_MOMENT, 1

_OSM_SP_SCR2    CMP     AEXP_OPTM_G_SCRRELOAD, R8
                RBRA    _OSM_SEL_POST_R, !Z

                ; Paint the "loading" label. OPTM_CUR_SEL is the flat index of
                ; the highlighted item; the menu is flat-indexed but on-screen
                ; rows collapse submenus, so translate to the visible row first
                ; (_OPTM_R_F2M_O is the same "from the outside" helper OPTM_SET
                ; / OPTM_SELECT use). Then print across the full content width
                ; at the left edge (x = OPTM_X+1, y = OPTM_Y+row+1).
                MOVE    OPTM_CUR_SEL, R8
                MOVE    @R8, R8
                MOVE    OPTM_F_MS_SLCT, R9      ; fatal-context (unused on OK)
                RSUB    _OPTM_R_F2M_O, 1        ; R8 = row; C=1 -> off this level
                RBRA    _OSP_SCR_RM, C          ; (defensive) skip paint if so
                MOVE    OPTM_Y, R10
                MOVE    @R10, R10
                ADD     R8, R10
                ADD     1, R10                  ; R10 = screen y (+1 for frame)
                MOVE    OPTM_X, R9
                MOVE    @R9, R9
                ADD     1, R9                   ; R9 = screen x (+1 for frame)
                MOVE    SCR_LOADING_STR, R8     ; (read-only data device:
                RSUB    RODATA_STR, 1           ;  copied to RAM)
                RSUB    OPTR_PRINTXY, 1         ; (M2M menu-rows: y = the row
                                                ;  of the classic layout)

                ; The user may have pulled the SD card to write a new file with
                ; the python tool. M2M-UPSTREAM sd-host (two slots): that is a
                ; new card generation, and SDC$HOMEDEV in LOAD_SCREEN_OFFSETS
                ; mounts the card again, so the reload reads the CURRENT card.
                ; Safe for config-save: write-back is gated on CONFIG_FILE and
                ; the generation the settings file was loaded at.
_OSP_SCR_RM     RSUB    LOAD_SCREEN_OFFSETS, 1

                ; Momentary reset: clear the single-select state everywhere so
                ; no "=" ever sticks. M2M$FORCE_MENU clears the QNICE setting
                ; register bit AND the in-memory selection of the menu (and
                ; erases the on-screen marker); OPTM_SHOW then repaints every
                ; label (ours reverts to "Reload Screen Config", markerless) and
                ; OPTM_SELECT restores the cursor highlight. OPTM_CUR_SEL is
                ; untouched by these calls, so it still points at our item.
_OSP_MOMENT     MOVE    OPTM_CUR_SEL, R8
                MOVE    @R8, R8
                XOR     R9, R9                  ; 0 = unselected
                RSUB    M2M$FORCE_MENU, 1
                RSUB    OPTM_SHOW, 1
                MOVE    OPTM_CUR_SEL, R8
                MOVE    @R8, R8
                MOVE    OPTM_SEL_SEL, R9
                RSUB    OPTM_SELECT, 1
                RBRA    _OSM_SEL_POST_R, 1

_OSM_SEL_POST_R XOR     R8, R8
                XOR     R9, R9
                DECRB
                RET

; OSM_SEL_PRE callback function:
;
; Identical to the OSM_SEL_POST callback function (see above) but it is being
; called before the functionality and semantics associated with a certain
; menu item has been handled by the framework.
OSM_SEL_PRE     INCRB

                ; issue #16: a sub-activity of a menu selection is about to run
                ; (the file browser, its SD-mount retry / "press Space"
                ; acknowledgments, or the WHS help viewer) and it polls
                ; HANDLE_IO. Raise the gate-4 flag so HANDLE_UNMOUNT_KEY does
                ; not mistake a SPACE inside one of those sub-screens - e.g.
                ; Return-to-replace on the still-mounted ' ADF:' line - for an
                ; unmount request. Cleared again in OSM_SEL_POST, which brackets
                ; the whole select-callback body (options.asm OPTM_CB_SEL).
                MOVE    OSM_SUB_ACTIVE, R0
                MOVE    1, @R0

                XOR     R8, R8
                XOR     R9, R9
                DECRB
                RET

; ----------------------------------------------------------------------------
; Core specific callback functions: Custom messages
; ----------------------------------------------------------------------------

; BROWSE_EXTRA callback function (M2M-UPSTREAM cfg-strings):
;
; Entries of the file browser that are no files. The browser lists them first
; (behind "<..>"); choosing one makes the Shell call PREP_LOAD_IMAGE with an
; empty file handle and SF_VIRTUAL = id + 1.
;
; Megamiga: for the two HDF lines (0.7: and the quick HDF), the partitions of an SD card with the MBR
; type 0x7F ("SD0: Partition 2: 1024 MB"), id = slot << 8 | the partition
; number: the drive is then that partition (HDF_PREP, HDF_VPART), like a link
; file names it. M2M-UPSTREAM sd-host (two slots): they are listed in the list
; of the cards, after their card (R11 = its slot); in a directory (R11 =
; 0xFFFF) there are none.
;
; Input:  R8: index of the entry (0, 1, ...), R9: context (CTX_*), R10: group,
;         R11: the slot or 0xFFFF
; Output: R8: its name (0 = no more entries), R9: its id (0..0x0FFF);
;         R10..R12 preserved
BROWSE_EXTRA    INCRB
                MOVE    R10, R0
                MOVE    R11, R1
                MOVE    R12, R2
                CMP     CTX_LOAD_ROM, R9
                RBRA    _BRX_NO, !Z
                CMP     AEXP_OPTM_G_HDF, R0
                RBRA    _BRX_GO, Z
                CMP     AEXP_OPTM_G_QHDF, R0    ; (0.7: the quick HDF too)
                RBRA    _BRX_GO, Z
                CMP     AEXP_OPTM_G_HDF1, R0
                RBRA    _BRX_NO, !Z
_BRX_GO         CMP     0xFFFF, R1              ; a directory: none
                RBRA    _BRX_NO, Z
                MOVE    R8, R3                  ; R3: usable ones to skip
                MOVE    R1, R8                  ; the card (FAT32 or not)
                RSUB    SDC$BLKDEV, 1
                CMP     0, R9
                RBRA    _BRX_NO, !Z
                MOVE    BRX_DEVREF, R9          ; a "file handle" for
                MOVE    R8, @R9                 ; HDF_PART_GET: only its
                MOVE    1, R4                   ; device word is read
_BRX_L          MOVE    BRX_DEVREF, R8          ; R4: partition number
                MOVE    R4, R9
                RSUB    HDF_PART_GET, 1         ; R8: n or 0xFF, R12:R11 size
                CMP     0x00FF, R8
                RBRA    _BRX_NX, Z
                CMP     0, R3
                RBRA    _BRX_FOUND, Z
                SUB     1, R3
_BRX_NX         ADD     1, R4
                CMP     5, R4
                RBRA    _BRX_L, !Z
_BRX_NO         XOR     R8, R8
                RBRA    _BRX_RET, 1

_BRX_FOUND      MOVE    BRX_NAME, R5            ; "SDx: Partition n: "
                MOVE    0x0053, @R5++
                MOVE    0x0044, @R5++
                MOVE    R1, R6
                ADD     0x0030, R6
                MOVE    R6, @R5++
                MOVE    0x003A, @R5++
                MOVE    0x0020, @R5++
                MOVE    BRX_S_PART, R8
                MOVE    R5, R9
                SYSCALL(strcpy, 1)
                ADD     BRX_S_PLEN, R5
                MOVE    R4, R6
                ADD     0x0030, R6
                MOVE    R6, @R5++
                MOVE    0x003A, @R5++
                MOVE    0x0020, @R5++
                MOVE    R11, R8                 ; the size: MB = blocks >> 11,
                MOVE    R12, R9                 ; GB from 10000 MB on
                MOVE    11, R10
                RSUB    _BRX_SHR, 1
                MOVE    BRX_S_MB, R7
                CMP     0, R9
                RBRA    _BRX_GB, !Z
                CMP     R8, 9999
                RBRA    _BRX_DEC, !N            ; (R8 <= 9999)
_BRX_GB         MOVE    10, R10
                RSUB    _BRX_SHR, 1
                MOVE    BRX_S_GB, R7
_BRX_DEC        MOVE    BRX_DEC, R10
                SYSCALL(h2dstr, 1)              ; R11: the decimal string
                MOVE    R11, R8
                MOVE    R5, R9
                SYSCALL(strcpy, 1)
                SYSCALL(strlen, 1)
                ADD     R9, R5
                MOVE    R7, R8
                MOVE    R5, R9
                SYSCALL(strcpy, 1)
                MOVE    BRX_NAME, R8
                MOVE    R1, R9                  ; the id: slot << 8 | number
                SWAP    R9, R9
                OR      R4, R9
_BRX_RET        MOVE    R0, R10
                MOVE    R1, R11
                MOVE    R2, R12
                DECRB
                RET

; _BRX_SHR: R9:R8 >> R10 (1..15). R11, R12 clobbered.
_BRX_SHR        MOVE    R9, R11
                MOVE    16, R12
                SUB     R10, R12
                AND     0xFFFD, SR              ; (X: shift in zeros)
                SHL     R12, R11
                AND     0xFFFB, SR              ; (C: shift in zeros)
                SHR     R10, R8
                OR      R11, R8
                AND     0xFFFB, SR
                SHR     R10, R9
                RET

BRX_S_PART      .ASCII_W "Partition "
BRX_S_PLEN      .EQU    10
BRX_S_MB        .ASCII_W " MB"
BRX_S_GB        .ASCII_W " GB"

; CUSTOM_MSG callback function:
;
; Called in various situations where the Shell needs to output a message
; to the end user. The situations and contexts are described in sysdef.asm
;
; Input:
;   R8: Situation (CMSG_* constants in sysdef.asm)
;   R9: Context   (CTX_* constants in sysdef.asm)
; Output:
;   R8: 0=no custom message available, otherwise pointer to string

CUSTOM_MSG      XOR     R8, R8
                RET

; ----------------------------------------------------------------------------
; ADF write-back: background flush of Amiga-written tracks to the SD card
;
; The track engine (CORE/vhdl/adf_track_engine.vhd) MFM-decodes Amiga writes
; and commits verified sectors into the ADF image in HyperRAM; the mount
; wrapper (CORE/vhdl/adf_mount_wrapper.vhd) collects the affected tracks in
; a dirty bitmap behind window ADF_WBC_4KWIN of device AEXP_DEV_ADF0 and runs
; the vdrives-style anti-thrashing countdown. The firmware side below mirrors
; the proven C64MEGA65 vdrives discipline (background flushing driven from
; HANDLE_IO, chunked to stay responsive, still-open FAT32 handle, errors are
; fatal) against our non-vdrives device. Full design:
; doc/developers/floppy-adf.md
;
; SCOPE: every one of the three simulated drives has its own write-back. The
; hardware is already per drive - each adf_mount_wrapper instance carries its
; own WBC (WR_EN, dirty bitmap, anti-thrash countdown) behind its own device id
; - so the firmware only has to address the right device and keep its own state
; per drive. All of it is therefore an array indexed by the Amiga drive unit
; 0..2, which is also the manual CRT/ROM id and thus the index into the
; HANDLE_RM_FILE handles of the Shell: drive n loads through HNDL_RM_FILES[n].
; The three tables ADF_DEV_TAB / ADF_FDH_TAB / ADF_GRP_TAB are the only place
; that knows how a drive maps to a device, a handle snapshot and a menu group.
;
; The three consequences that make this safe (see also the section 5a arm-state
; invariant of .research/INTEGRATION-SPEC-floppy-adf-write.md, which now has to
; hold PER DRIVE):
;
;   * Each drive keeps its OWN FDH snapshot. A flush of drive n can only ever
;     reach the file that was mounted into drive n - this is what stops the
;     cross-drive corruption of one drive being written into the file of
;     another, which a single shared handle would produce the moment a second
;     drive is armed.
;   * The arming is bound to the drive whose device CSR reported the mount, and
;     the disarm to the drive whose menu group triggered PREP_LOAD_IMAGE.
;   * The same image file may not be mounted into two drives at once: both
;     drives would hold their own HyperRAM copy and the later flush of one
;     would silently overwrite what the other wrote. PREP_LOAD_IMAGE rejects
;     the second mount (see ADF_DUP_CHECK).
;
; The background flush serves ONE drive per time slice, round-robin, so three
; armed drives cost exactly as much main-loop time as one did.
; ----------------------------------------------------------------------------

; ADF_SEL_WBC: point the RAMROM window at the write-back CSR of one drive.
;
; Input:  R8: drive 0..2
; Output: none; all registers preserved (the RAMROM selection is changed -
;         every caller either owns it or restores it, see HANDLE_CORE_IO)
ADF_SEL_WBC     INCRB
                MOVE    ADF_DEV_TAB, R0
                ADD     R8, R0
                MOVE    M2M$RAMROM_DEV, R1
                MOVE    @R0, @R1
                MOVE    M2M$RAMROM_4KWIN, R1
                MOVE    ADF_WBC_4KWIN, @R1
                DECRB
                RET

; ADF_WIPE_DIRTY: drop the whole dirty bitmap of one drive (write-1-to-clear).
;
; Used whenever the retained file handle of that drive became unusable: the
; tracks can no longer be written anywhere sensible, and leaving the bits set
; would make a LATER mount flush them into a different file.
;
; Input:  R8: drive 0..2
; Output: none; all registers preserved
ADF_WIPE_DIRTY  INCRB
                RSUB    ADF_SEL_WBC, 1
                MOVE    ADF_WBC_DIRTY0, R0
                MOVE    ADF_WBC_DIRTY_W, R1
_AWD_L          MOVE    0xFFFF, @R0++
                SUB     1, R1
                RBRA    _AWD_L, !Z
                DECRB
                RET

; ADF_DISARM: disarm the write-back of one drive.
;
; Invalidates the handle snapshot, aborts a running flush session, re-opens the
; arming edge for the next mount and takes WR_EN away so the track engine
; announces that unit write-protected again. Does NOT touch the dirty bitmap -
; the callers decide whether the pending tracks are still flushable (mount and
; eject flush first) or have to be dropped (ADF_WIPE_DIRTY).
;
; Input:  R8: drive 0..2
; Output: none; all registers preserved
ADF_DISARM      INCRB
                MOVE    ADF_FDH_VALID, R0
                ADD     R8, R0
                MOVE    0, @R0
                MOVE    ADF_MOUNT_SEEN, R0      ; 0: a fresh READY may arm
                ADD     R8, R0
                MOVE    0, @R0
                MOVE    ADF_FL_STATE, R0
                ADD     R8, R0
                MOVE    0, @R0
                RSUB    ADF_SEL_WBC, 1
                MOVE    ADF_WBC_CTRL, R0
                MOVE    0, @R0
                DECRB
                RET

; ADF_DUP_CHECK: is the file behind a fresh file handle already mounted into
; ANOTHER drive?
;
; Two drives holding the same image file is a silent data-loss trap: each drive
; streams its OWN copy into its OWN HyperRAM pool, both collect Amiga writes
; independently, and whichever drive flushes last overwrites what the other one
; saved. The file is identified by its device handle (M2M-UPSTREAM sd-host:
; one per card) and its FAT32 start cluster, which is unique per file on a
; card; the guards of HANDLE_CORE_IO keep every ARMED drive on the generation
; of its card it was armed on. A drive whose write-back is not armed cannot
; write and is therefore skipped - its file identity is not retained anywhere
; either.
;
; Input:  R8: the fresh file handle
;         R9: the drive that is being loaded (it is skipped)
; Output: C=1 and R9 = the other drive, if that drive holds the same file;
;         C=0 otherwise. R8 preserved.
ADF_DUP_CHECK   INCRB
                MOVE    R8, R0                  ; R0: the fresh handle
                MOVE    R9, R1                  ; R1: the drive being loaded
                MOVE    R0, R6
                ADD     FAT32$FDH_START_CLUS_LO, R6
                MOVE    @R6, R2                 ; R2/R3: its start cluster
                MOVE    R0, R6
                ADD     FAT32$FDH_START_CLUS_HI, R6
                MOVE    @R6, R3
                MOVE    @R0, R7                 ; R7: its device handle

                MOVE    R2, R6                  ; start cluster 0 means an
                OR      R3, R6                  ; empty file and is not a
                RBRA    _ADC_NO, Z              ; usable identity (an ADF never
                                                ; gets here - the size gate ran
                                                ; first - but 0 == 0 must not
                                                ; be read as "the same file")

                XOR     R4, R4                  ; R4: drive under inspection
_ADC_D          CMP     R4, R1
                RBRA    _ADC_N, Z               ; skip the drive being loaded
                MOVE    ADF_FDH_VALID, R5
                ADD     R4, R5
                CMP     0, @R5
                RBRA    _ADC_N, Z               ; not armed: cannot write, and
                                                ; no file identity is retained
                MOVE    ADF_FDH_TAB, R5
                ADD     R4, R5
                MOVE    @R5, R5                 ; R5: the own FDH of that drive
                CMP     @R5, R7                 ; same device handle?
                RBRA    _ADC_N, !Z
                MOVE    R5, R6
                ADD     FAT32$FDH_START_CLUS_LO, R6
                CMP     @R6, R2
                RBRA    _ADC_N, !Z
                MOVE    R5, R6
                ADD     FAT32$FDH_START_CLUS_HI, R6
                CMP     @R6, R3
                RBRA    _ADC_N, !Z
                MOVE    R4, R9                  ; the very same file
                MOVE    R0, R8                  ; (R8 unchanged for the caller)
                OR      0x0004, SR              ; set Carry
                DECRB
                RET

_ADC_N          ADD     1, R4
                CMP     ADF_DRIVES, R4
                RBRA    _ADC_D, !Z
_ADC_NO         MOVE    R0, R8                  ; (R8 unchanged for the caller)
                AND     0xFFFB, SR              ; clear Carry: not a duplicate
                DECRB
                RET

; ADF_WB_INIT: called once from START_FIRMWARE, before the Shell starts.
; Zero-initializes the write-back state of all three drives and loads
; VD_ANTI_THRASHING_DELAY from config.vhd into each WBC hardware countdown
; register (mirrors the vdrives VD_INIT pattern, M2M/rom/vdrives.asm).
ADF_WB_INIT     INCRB

                MOVE    M2M$RAMROM_DEV, R0      ; anti-thrashing delay (ms)
                MOVE    M2M$CONFIG, @R0         ; from config.vhd
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    M2M$CFG_GENERAL, @R0
                MOVE    M2M$CFG_VD_AT_DELAY, R0
                MOVE    @R0, R1                 ; R1: the delay, in ms

                XOR     R2, R2                  ; R2: drive 0..2
_AWBI_D         MOVE    ADF_FDH_VALID, R3
                ADD     R2, R3
                MOVE    0, @R3
                MOVE    ADF_MOUNT_SEEN, R3
                ADD     R2, R3
                MOVE    0, @R3
                MOVE    ADF_FL_STATE, R3
                ADD     R2, R3
                MOVE    0, @R3

                MOVE    R2, R8                  ; ... into the WBC register of
                RSUB    ADF_SEL_WBC, 1          ; this drive
                MOVE    ADF_WBC_ATDELAY, R3
                MOVE    R1, @R3

                ADD     1, R2
                CMP     ADF_DRIVES, R2
                RBRA    _AWBI_D, !Z

                MOVE    ADF_FL_RR, R0           ; round-robin flush pointer
                MOVE    0, @R0

                ; issue #16 unmount state: no SPACE seen yet and no menu
                ; sub-activity running. Seeded here (like the rest of the ADF
                ; state) because HANDLE_IO can poll HANDLE_UNMOUNT_KEY during
                ; boot wait loops, before RAM is otherwise written.
                MOVE    ADF_UNMNT_PREV, R0
                MOVE    0, @R0
                MOVE    OSM_SUB_ACTIVE, R0
                MOVE    0, @R0

                DECRB
                RET

; SCR_INIT: called once from START_FIRMWARE, before the Shell starts. Puts the
; screen-centering runtime state (issue #5) into a safe boot state, so a
; DETECT_SCREEN_MODE poll from a boot-time wait loop (HANDLE_IO is polled before
; PREP_START runs LOAD_SCREEN_OFFSETS, and RAM is undefined at power-on) can never
; act on undefined state: the debounce latch says "nothing applied", and the table
; is inert (0,0,0,0 = no centering) until LOAD_SCREEN_OFFSETS reads the SD file.
SCR_INIT        INCRB
                MOVE    SCR_APPLIED_MODE, R0
                MOVE    SCR_MODE_NONE, @R0
                MOVE    SCR_CAND_MODE, R0
                MOVE    SCR_MODE_NONE, @R0
                MOVE    SCR_CAND_CNT, R0
                MOVE    0, @R0
                MOVE    SCR_TICK, R0
                MOVE    0, @R0
                MOVE    SCR_TABLE, R0
                MOVE    SCR_TABLE_WORDS, R1
_SCR_INIT_L     MOVE    0, @R0++
                SUB     1, R1
                RBRA    _SCR_INIT_L, !Z
                DECRB
                RET

; RTC_INIT: called once from START_FIRMWARE, before the Shell starts (like
; ADF_WB_INIT - RAM variables are undefined at power-on). Primes the minute-edge
; detector with a sentinel so the first minute change reseeds the Amiga clock.
RTC_INIT        INCRB
                MOVE    RTC_LAST_MIN, R0
                MOVE    0xFFFF, @R0
                DECRB
                RET

; RTC_STEP: one non-blocking step of the battery-RTC reseed (issue #13).
;
; The Minimig $DC0000 clock (minimig.v) advances minutes/hours/date only when the
; framework flips the RTC "new value" toggle, which it does when an external I2C
; RTC read completes (M2M/vhdl/i2c/rtc_controller.vhd). The framework issues that
; read only at reset, so the Amiga clock would freeze ~1 minute after the boot
; seed (minimig free-runs its seconds field but never carries into minutes). This
; re-issues the read once per real minute - aligned to the :00 boundary by
; edge-detecting the free-running internal-minute register - which reseeds
; minimig with fresh time and restarts its in-FPGA seconds counter from 0. This
; is the MiSTer "HPS resend once per minute" cadence.
;
; The minute register is read WITHOUT flipping the toggle (only a command-byte
; write does), so the common path is just a couple of cheap device reads. The
; command byte is accepted only while I2C is idle, so a still-running read (e.g.
; the boot read) simply defers to the next call.
;
; Expects the caller to tolerate a changed RAMROM device selection (HANDLE_CORE_IO
; saves and restores it around this call). Input/Output: none.
RTC_STEP        INCRB
                MOVE    M2M$RAMROM_DEV, R0      ; select the framework RTC device
                MOVE    AEXP_DEV_RTC, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    RTC_4KWIN, @R0

                MOVE    RTC_COMMAND, R0         ; defer while an I2C read runs
                MOVE    @R0, R1
                AND     1, R1
                RBRA    _RTC_RET, !Z

                MOVE    RTC_MINUTES, R0         ; free-running internal minute
                MOVE    @R0, R0                 ; (BCD, high byte already 0)
                MOVE    RTC_LAST_MIN, R1
                CMP     @R1, R0
                RBRA    _RTC_RET, Z             ; same minute: nothing to do

                MOVE    R0, @R1                 ; remember this minute
                MOVE    RTC_COMMAND, R0         ; reseed: stop, then read+restart
                MOVE    RTC_CMD_STOP, @R0       ; b3=0: stop the internal timer
                MOVE    RTC_CMD_RESYNC, @R0     ; b1=read + b3=run: the external
                                                ; read flips the toggle and
                                                ; minimig reseeds $DC0000

_RTC_RET        DECRB
                RET

; HANDLE_CORE_IO callback function:
;
; Called from HANDLE_IO in every iteration of the main loop and of all
; blocking wait loops - see the M2M-UPSTREAM core-io-hook contract in
; M2M/rom/shell.asm. AExp uses the time slice to run the ADF write-back:
;
;   1. SD guards: a swapped card invalidates every retained file handle, and an
;      active-slot switch invalidates the handles snapshotted on the other slot
;      - disable those drives and discard their dirty state (the
;      ROSM_INTEGRITY precedent: never write to a card we did not open on).
;   2. Mount tracking: when a mount of drive n reaches PARSEST=READY, snapshot
;      the Shell handle HNDL_RM_FILES[n] into that drive OWN FDH (the Shell
;      re-opens that struct for the NEXT load before PREP_LOAD_IMAGE even
;      runs!) and arm the write-back of that drive: WBC WR_EN=1 makes the track
;      engine announce that unit as writable to the Amiga.
;   3. One background flush step (respects the anti-thrashing gate), handed to
;      ONE drive per poll in round-robin order.
;
; Input/Output: none; all registers are preserved
HANDLE_CORE_IO  SYSCALL(enter, 1)

                ; ADF unmount with SPACE (issue #16): must run FIRST and on
                ; EVERY poll. HANDLE_IO calls us at the top of every OSM
                ; key-wait iteration, before the KEYB$SCAN of that loop - the
                ; ordering that lets us both suppress the SPACE of the menu (so
                ; it never becomes a mount) and, on a fresh press over the
                ; highlighted ' ADF:' line, eject the disk. Cheap in the common
                ; path (OSM closed) and RAMROM-transparent.
                RSUB    HANDLE_UNMOUNT_KEY, 1

                ; profile file names that were loaded before the menu existed
                RSUB    PROF_PEND_APPLY, 1
                RSUB    PRF_STEP, 1             ; 0.7: the profile line, write-back

                ; screen centering (issue #5): throttle the mode detector. A mode
                ; change only needs to be reacted to within a few ms, so run
                ; DETECT_SCREEN_MODE once every SCR_TICK_MASK+1 poll-loop
                ; iterations instead of every one -- the detector is ~80 instr
                ; and this callback is polled in the tightest loops (incl. the
                ; ADF write-back below). Skipped iterations pay only this
                ; ~4-instruction counter. On a change the detector re-centers
                ; within (SCR_DEBOUNCE+2) detects, i.e. a few tens of ms.
                MOVE    SCR_TICK, R4
                ADD     1, @R4
                MOVE    @R4, R5
                AND     SCR_TICK_MASK, R5
                RBRA    _HCIO_NODET, !Z
                RSUB    DETECT_SCREEN_MODE, 1     ; detect + apply on a mode change

                ; be transparent about the active RAMROM device selection
_HCIO_NODET     MOVE    M2M$RAMROM_DEV, R0
                MOVE    @R0, R1
                MOVE    M2M$RAMROM_4KWIN, R2
                MOVE    @R2, R3

                ; --- 1. SD guards, per drive. M2M-UPSTREAM sd-host (two
                ;        slots): a drive was armed on one card (its handle
                ;        snapshot names the device handle of that card), and
                ;        a new generation of THAT card (sdcards.asm: it was
                ;        pulled or swapped) tears the drive down - a flush
                ;        through the handle would write into whatever file
                ;        happens to live at those clusters on the new card.
                ;        Drives on the other card survive.
                XOR     R5, R5                  ; R5: drive
_HCIO_SDD       MOVE    ADF_FDH_VALID, R7
                ADD     R5, R7
                CMP     0, @R7
                RBRA    _HCIO_SDN, Z            ; not armed: nothing to tear
                MOVE    ADF_SD_SLOT, R7
                ADD     R5, R7
                MOVE    @R7, R8
                RSUB    SDC$GEN, 1
                MOVE    ADF_SD_GEN, R7
                ADD     R5, R7
                CMP     @R7, R8                 ; the same card as at arm time?
                RBRA    _HCIO_SDN, Z            ; yes: this drive stays armed
_HCIO_SDK       MOVE    R5, R8                  ; the retained handle is dead:
                RSUB    ADF_TB_OFF, 1           ; Megamiga: the file is gone,
                MOVE    ADF_DEV_TAB, R8         ; so is the disk - switch the
                ADD     R5, R8                  ; drive off in the track buffer
                MOVE    @R8, R8                 ; (its dirty sectors cannot be
                MOVE    CRTROM_CSR_STATUS, R9   ; written anywhere) and eject
                MOVE    CRTROM_CSR_ST_IDLE, R10 ; it (STATUS := ST_IDLE, as
                RSUB    CRTROM_CSR_W, 1         ; ADF_UNMOUNT does)
                MOVE    R5, R8
                RSUB    ADF_WIPE_DIRTY, 1       ; the dirty tracks can no
                RSUB    ADF_DISARM, 1           ; longer be written anywhere
                MOVE    ADF_MOUNT_SEEN, R7      ; 1: BLOCK re-arming from the
                ADD     R5, R7                  ; STALE PARSEST=READY of the
                MOVE    1, @R7                  ; old mount - only the next
                                                ; real ADF load, through
                                                ; PREP_LOAD_IMAGE, opens the
                                                ; arming again
_HCIO_SDN       ADD     1, R5
                CMP     ADF_DRIVES, R5
                RBRA    _HCIO_SDD, !Z

                ; --- 2. mount tracking (PARSEST=READY rising edge), per drive
_HCIO_MOUNT     XOR     R5, R5                  ; R5: drive
_HCIO_MD        MOVE    ADF_DEV_TAB, R6
                ADD     R5, R6
                MOVE    @R6, R8
                MOVE    CRTROM_CSR_PARSEST, R9
                RSUB    CRTROM_CSR_R, 1         ; R10: parse status
                MOVE    ADF_MOUNT_SEEN, R7
                ADD     R5, R7
                CMP     CRTROM_CSR_PT_OK, R10
                RBRA    _HCIO_NOMNT, !Z
                CMP     1, @R7
                RBRA    _HCIO_MN, Z             ; this mount is already armed
                MOVE    1, @R7
                MOVE    HNDL_RM_FILES, R8       ; snapshot the Shell handle of
                ADD     R5, R8                  ; THIS drive: manual CRT/ROM id
                MOVE    @R8, R8                 ; n is drive n (the mount lines
                MOVE    ADF_FDH_TAB, R9         ; sit in that order in the
                ADD     R5, R9                  ; static config array)
                MOVE    @R9, R9
                MOVE    FAT32$FDH_STRUCT_SIZE, R10
                SYSCALL(memcpy, 1)
                ADD     FAT32$FDH_FLAGS, R9     ; the snapshot must never start
                MOVE    0, @R9                  ; out DIRTY: the ONE hardware
                                                ; sector buffer is tracked by
                                                ; the ADDRESS of the handle
                                                ; that filled it, so a copy
                                                ; that claims to be dirty while
                                                ; not owning the buffer would
                                                ; make the next FAT32$FLUSH
                                                ; write foreign bytes to the
                                                ; sector of this drive. The
                                                ; Shell only ever reads through
                                                ; that handle, so this is
                                                ; belt-and-braces
                MOVE    ADF_FDH_VALID, R6
                ADD     R5, R6
                MOVE    1, @R6
                MOVE    ADF_FL_STATE, R6
                ADD     R5, R6
                MOVE    0, @R6
                MOVE    ADF_FDH_TAB, R8         ; remember the card of the
                ADD     R5, R8                  ; snapshot and its generation
                MOVE    @R8, R8
                MOVE    @R8, R8                 ; (FAT32$FDH_DEVICE = 0)
                RSUB    SDC$SLOT, 1
                MOVE    ADF_SD_SLOT, R7         ; (see the SD guards above)
                ADD     R5, R7
                MOVE    R8, @R7
                RSUB    SDC$GEN, 1
                MOVE    ADF_SD_GEN, R7
                ADD     R5, R7
                MOVE    R8, @R7
                MOVE    R5, R8                  ; WR_EN := 1: the track engine
                RSUB    ADF_SEL_WBC, 1          ; announces THIS unit writable
                MOVE    ADF_WBC_CTRL, R6
                MOVE    1, @R6
                RBRA    _HCIO_MN, 1

_HCIO_NOMNT     MOVE    0, @R7                  ; re-arm the edge detection
                                                ; for the next mount
_HCIO_MN        ADD     1, R5
                CMP     ADF_DRIVES, R5
                RBRA    _HCIO_MD, !Z

                ; --- 3. Megamiga: no background flush any more. The track
                ;        buffer (adf_sd.vhd) writes dirty sectors to the SD card
                ;        itself, 20 ms after the last one; the dirty-track bitmaps
                ;        of the WBC are not used.

                ; keep the Amiga battery clock live (issue #13): re-issue the
                ; framework RTC read once per minute so the Minimig $DC0000 clock
                ; advances instead of freezing after the boot seed
_HCIO_RTC       RSUB    IDE_STEP, 1             ; the IDE board (HDF image)
#if IDE_DIAG
                RSUB    IDE_DIAG_STEP, 1
#endif
                RSUB    SHARE_STEP, 1           ; the shared folder
                RSUB    RTC_STEP, 1

                ; live Hardware Floppy status line in the main menu. Four RAM
                ; reads and out while the OSM is closed, which is the case in
                ; the tightest loops.
                RSUB    HWF_STATUS_STEP, 1
                RSUB    SD_STATUS_STEP, 1       ; and the SD card status line

_HCIO_RET       MOVE    R1, @R0                 ; restore RAMROM selection
                MOVE    R3, @R2
                SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; The ADF track buffer (Megamiga, CORE/vhdl/adf_sd.vhd)
;
; The disk images are no longer copied into memory. The track engine reads and
; writes them through a one-track buffer in block RAM that the hardware fills
; from the file on the SD card and writes back to it, on its own: it reads the
; sectors through the SD host controller's engine port (shared with the IDE
; sector engine) and writes dirty sectors back 20 ms after the last write or
; before it needs the buffer for another track. The firmware only hands it
; the file - the extent map (FAT32$FILE_MAP, up to 511 extents), the block of
; cluster 0, the cluster size, the number of sectors and the card - and makes
; it write everything back before a drive gets another file or is ejected.
; Registers: window ADF_TB_REGWIN of the drive's device, the map: window
; ADF_TB_MAPWIN (constants at the end of this file).
; ----------------------------------------------------------------------------

; ADF_TB_SEL: point the RAMROM window at the track buffer of one drive
; Input: R8: drive 0..2, R9: window (ADF_TB_REGWIN or ADF_TB_MAPWIN)
; Output: none; all registers preserved
ADF_TB_SEL      INCRB
                MOVE    ADF_DEV_TAB, R0
                ADD     R8, R0
                MOVE    M2M$RAMROM_DEV, R1
                MOVE    @R0, @R1
                MOVE    M2M$RAMROM_4KWIN, R1
                MOVE    R9, @R1
                DECRB
                RET

; ADF_TB_OFF: switch one drive off in the track buffer (sectors of it that are
; still in the buffer are dropped: call ADF_TB_SYNC first)
; Input: R8: drive 0..2
; Output: none; all registers preserved (the RAMROM selection is changed)
ADF_TB_OFF      INCRB
                MOVE    R9, R0
                MOVE    ADF_TB_REGWIN, R9
                RSUB    ADF_TB_SEL, 1
                MOVE    ADF_TB_MODE, R1
                MOVE    0, @R1
                MOVE    R0, R9
                DECRB
                RET

; ADF_TB_SYNC: write the sectors of one drive that are in the track buffer to
; the SD card now, and wait until they are (bounded: about a second)
; Input: R8: drive 0..2
; Output: R9: 0 = done, 1 = timed out; R8 preserved (the RAMROM selection is
;         changed)
ADF_TB_SYNC     INCRB
                MOVE    ADF_TB_REGWIN, R9
                RSUB    ADF_TB_SEL, 1
                MOVE    ADF_TB_FLUSH, R0
                MOVE    1, @R0
                MOVE    ADF_TB_STAT, R0
                MOVE    64, R2                  ; 64 x 65536 polls
_ATS_O          XOR     R1, R1
_ATS_L          MOVE    @R0, R3
                AND     ADF_TB_WAIT, R3         ; dirty or still pending?
                RBRA    _ATS_OK, Z
                SUB     1, R1
                RBRA    _ATS_L, !Z
                SUB     1, R2
                RBRA    _ATS_O, !Z
                MOVE    1, R9
                RBRA    _ATS_RET, 1
_ATS_OK         XOR     R9, R9
_ATS_RET        DECRB
                RET

; ADF_TB_SETUP: give one drive its file in the track buffer
;
; The extent map of the file goes into the drive's map window, then the block
; of cluster 0 (DEV_CLUSTER - (2 << shift), as for the IDE sector engine), the
; cluster size, the number of 512-byte sectors and the card; the mode goes
; last. Finally the handle is moved to the end of the file, so that the Shell
; reads EOF at once.
;
; Input:  R8: file handle, R9: drive 0..2
; Output: R8: 0 = OK, 1 = more extents than the map holds (the drive stays
;         off), 2 = FAT32 error; R9 clobbered, R10..R12 preserved (the RAMROM
;         selection is changed)
ADF_TB_SETUP    MOVE    R10, @--SP
                MOVE    R11, @--SP
                MOVE    R12, @--SP
                INCRB
                MOVE    R8, R0                  ; R0: handle
                MOVE    R9, R1                  ; R1: drive

                MOVE    R1, R8                  ; off while it changes
                RSUB    ADF_TB_OFF, 1

                MOVE    ADF_TB_MAPWIN, R9       ; the extent map
                RSUB    ADF_TB_SEL, 1
                MOVE    R0, R8
                MOVE    ADF_TB_MAP, R9
                MOVE    ADF_TB_MAPW, R10
                RSUB    FAT32$FILE_MAP, 1       ; (not in the M2M syscall table)
                MOVE    1, R7                   ; R7: the result
                CMP     FAT32$ERR_MAPSIZE, R9
                RBRA    _ATSU_RET, Z
                MOVE    2, R7
                CMP     0, R9
                RBRA    _ATSU_RET, !Z

                MOVE    R1, R8                  ; the registers
                MOVE    ADF_TB_REGWIN, R9
                RSUB    ADF_TB_SEL, 1

                MOVE    R0, R2                  ; sectors = size >> 9
                ADD     FAT32$FDH_SIZE_LO, R2
                MOVE    @R2, R2                 ; R2: size lo
                MOVE    R0, R3
                ADD     FAT32$FDH_SIZE_HI, R3
                MOVE    @R3, R3                 ; R3: size hi
                AND     0xFFFB, SR              ; (C = 0: shift in zeros)
                SHR     9, R2
                MOVE    R3, R4
                AND     0xFFFD, SR              ; (X = 0: shift in zeros)
                SHL     7, R4
                OR      R4, R2                  ; R2: sectors lo
                AND     0xFFFB, SR
                SHR     9, R3                   ; R3: sectors hi
                MOVE    ADF_TB_SECT, R4
                MOVE    R2, @R4++
                MOVE    R3, @R4++               ; R4: ADF_TB_BASE

                MOVE    @R0, R2                 ; R2: device handle
                MOVE    R2, R3                  ; (FAT32$FDH_DEVICE = 0)
                ADD     FAT32$DEV_SECT_PER_CLUS, R3
                MOVE    @R3, R3                 ; R3: sectors per cluster
                XOR     R5, R5                  ; R5: shift
_ATSU_SH        CMP     R3, 1
                RBRA    _ATSU_SHD, !N           ; R3 <= 1: done
                AND     0xFFFB, SR
                SHR     1, R3
                ADD     1, R5
                RBRA    _ATSU_SH, 1
_ATSU_SHD       MOVE    2, R6                   ; base = DEV_CLUSTER - (2 << shift)
                AND     0xFFFD, SR              ; (X = 0: shift in zeros)
                SHL     R5, R6
                MOVE    R2, R3
                ADD     FAT32$DEV_CLUSTER_LO, R3
                MOVE    @R3++, R11              ; R12:R11: DEV_CLUSTER
                MOVE    @R3, R12                ; (FAT32$DEV_CLUSTER_HI)
                SUB     R6, R11
                SUBC    0, R12
                MOVE    R11, @R4++              ; base lo, hi, shift
                MOVE    R12, @R4++
                MOVE    R5, @R4

                MOVE    R2, R8                  ; the card (M2M-UPSTREAM sd-host:
                RSUB    SDC$SLOT, 1             ; the engine port's controller)
                MOVE    ADF_TB_ON, R6
                CMP     0, R8
                RBRA    _ATSU_S0, Z
                OR      ADF_TB_SLOT1, R6
_ATSU_S0        MOVE    ADF_TB_MODE, R3         ; mode last
                MOVE    R6, @R3

                MOVE    R0, R8                  ; the handle to the end
                MOVE    R0, R9
                ADD     FAT32$FDH_SIZE_LO, R9
                MOVE    @R9, R9
                MOVE    R0, R10
                ADD     FAT32$FDH_SIZE_HI, R10
                MOVE    @R10, R10
                SYSCALL(f32_fseek, 1)           ; R9: 0 or the error
                MOVE    2, R7
                CMP     0, R9
                RBRA    _ATSU_RET, !Z
                XOR     R7, R7
_ATSU_RET       MOVE    R7, R8
                DECRB
                MOVE    @SP++, R12
                MOVE    @SP++, R11
                MOVE    @SP++, R10
                RET

; ----------------------------------------------------------------------------
; ADF unmount with SPACE (issue #16)
;
; Mirrors the C64 gesture: with the OSM open and the cursor on the ' ADF:'
; line, SPACE ejects the disk (df0 goes empty, the menu label reverts to
; "<Load>"). Megamiga 0.3.1: the same on the ' HDF 0:' / ' HDF 1:' lines
; (HDF_EJECT, which also restarts the Amiga). The framework has NO unmount path for CRT/ROM devices
; (HANDLE_MOUNTING always opens the browser for CRT/ROM mode, shell.asm) and
; M2M must not be modified, so we intercept the key core-side. HANDLE_IO calls
; HANDLE_CORE_IO - and thus HANDLE_UNMOUNT_KEY - at the TOP of every OSM
; key-wait iteration, BEFORE the KEYB$SCAN of that loop (options.asm). That
; ordering lets us both suppress the SPACE of the menu (so it never becomes a
; mount) and fire the eject ourselves. Full design + adversarial review:
; .research/INTEGRATION-SPEC-adf-unmount.md
;
; Five gates must all hold to act:
;   1  OSM open            M2M$CSR bit M2M$CSR_OSM (else SPACE is for the Amiga)
;   4  not a sub-activity  OSM_SUB_ACTIVE == 0 (the browser/help set it; this
;                          is what keeps a SPACE on a browser "press Space"
;                          screen reached via Return-to-replace from ejecting)
;   2  ' ADF:' highlighted OPTM_CUR_SEL == the flat menu index of the ADF item
;   3  ADF mounted         PARSEST == PT_OK (else let SPACE fall through and
;                          mount, matching the SPACE-on-empty-drive of the C64)
;   5  fresh SPACE edge    via the ADF_UNMNT_PREV latch (one act per press)
;
; Gates 1+4 read only absolute MMIO / RAM (no device window), so the common path
; (OSM closed) is cheap and leaves the RAMROM selection untouched. Only once we
; pass gate 4 do we snapshot RAMROM (R6/R7) and switch devices for gates 2/3 and
; the eject; _HUK_RET restores it so HANDLE_CORE_IO stays transparent to its
; caller. While gates 1-4 hold we suppress the SPACE of the menu EVERY iteration
; (race-free vs. the edge detector of KEYB$SCAN) and eject only on the gate-5
; rising edge.
;
; Input/Output: none. Bank-local R0-R7; clobbers global R8-R10 (HANDLE_CORE_IO
; has no live upper registers at its top and reloads them at first use).
; ----------------------------------------------------------------------------
HANDLE_UNMOUNT_KEY INCRB

                ; read current SPACE state (M2M$KEYBOARD is low-active) and
                ; update the edge latch UNCONDITIONALLY every call (OSM open or
                ; closed), so opening the OSM with SPACE held cannot fake an edge
                MOVE    M2M$KEYBOARD, R0
                MOVE    @R0, R0
                NOT     R0, R0                  ; low-active -> high-active
                AND     M2M$KEY_SPACE, R0
                MOVE    R0, R4                  ; R4 = 0x20 pressed / 0 released
                MOVE    ADF_UNMNT_PREV, R1
                MOVE    @R1, R5                 ; R5 = SPACE state last poll
                MOVE    R4, @R1                 ; latch := current

                ; --- gate 1: OSM open? (closed -> SPACE belongs to the Amiga)
                MOVE    M2M$CSR, R0
                MOVE    @R0, R0
                AND     M2M$CSR_OSM, R0
                RBRA    _HUK_RET_NS, Z

                ; --- gate 4: inside a menu-item sub-activity (browser/help)? ---
                MOVE    OSM_SUB_ACTIVE, R0
                CMP     0, @R0
                RBRA    _HUK_RET_NS, !Z

                ; from here on we switch the RAMROM device; snapshot it first
                ; so _HUK_RET can hand HANDLE_CORE_IO back the selection intact
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    @R0, R6
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    @R0, R7

                ; --- gate 2: is one of the three mount lines highlighted? ---
                ; The flat menu index of each mount line is a BUILD-TIME
                ; constant (AEXP_OSM_DF*_MOUNT_LN, scraped from mega65.vhd by
                ; make_rom.sh and cross-checked against the text of that line
                ; by .research/check_osm_menu.py), and OPTM_CUR_SEL is the live
                ; highlight in the same flat coordinate - so this gate is three
                ; compares. Asking CRTROM_M_GI once per drive instead would
                ; rescan the whole 148-line menu three times on EVERY key-wait
                ; poll. The scan needs no visibility test of its own: a mount
                ; line hidden by a menu dependency can never carry the cursor.
                MOVE    OPTM_CUR_SEL, R0
                MOVE    @R0, R0                 ; R0: highlighted flat index
                MOVE    ADF_MNT_LN_TAB, R1
                XOR     R2, R2                  ; R2: drive under inspection
_HUK_G2         CMP     @R1++, R0
                RBRA    _HUK_G3, Z
                ADD     1, R2
                CMP     ADF_DRIVES, R2
                RBRA    _HUK_G2, !Z

                ; Megamiga 0.3.1: the two HDF lines. Gate 3 there is the drive
                ; being mounted (HDF_UNITS: a profile mounts without the Shell)
                ; 0.7: and the quick HDF line ("drive" 2); while that one is on,
                ; Space on an HDF line forgets the profile's file (B3_HDF_SPACE)
                XOR     R2, R2                  ; R2: drive 0 / 1, 2 quick
                CMP     AEXP_OSM_HDF_MOUNT_LN, R0
                RBRA    _HUK_H, Z
                ADD     1, R2
                CMP     AEXP_OSM_HDF1_MOUNT_LN, R0
                RBRA    _HUK_H, Z
                ADD     1, R2
                CMP     AEXP_OSM_QHDF_MOUNT_LN, R0
                RBRA    _HUK_RET, !Z            ; some other line -> bail
_HUK_H          MOVE    R2, R8                  ; something to eject or forget?
                RSUB    HDF_SPACE_OK, 1
                RBRA    _HUK_RET, !C            ; no -> let SPACE mount
                MOVE    KEYB_PRESSED, R1        ; suppress the SPACE of the menu
                OR      M2M$KEY_SPACE, @R1      ; (see gate 3 below)
                CMP     0, R4                   ; gate 5: rising edge only
                RBRA    _HUK_RET, Z
                CMP     0, R5
                RBRA    _HUK_RET, !Z
                MOVE    R2, R8
                RSUB    HDF_SPACE, 1
                RBRA    _HUK_RET, 1

                ; --- gate 3: is a disk in THAT drive? PARSEST == PT_OK ---
_HUK_G3         MOVE    ADF_DEV_TAB, R8
                ADD     R2, R8
                MOVE    @R8, R8
                MOVE    CRTROM_CSR_PARSEST, R9
                RSUB    CRTROM_CSR_R, 1         ; R10 = parse status
                CMP     CRTROM_CSR_PT_OK, R10
                RBRA    _HUK_RET, !Z            ; empty drive -> let SPACE mount

                ; in context: suppress the SPACE of the menu this iteration,
                ; BEFORE KEYB$SCAN runs. The rising edge of KEYB$SCAN is
                ; (pressed AND NOT KEYB_PRESSED), so pre-setting the SPACE bit
                ; kills the edge -> KEYB$GETKEY never returns SPACE ->
                ; OPTM_CB_SEL / HANDLE_MOUNTING never fire for it. Done on every
                ; in-context poll (not only our own edge), so it is immune to
                ; the read skew between our M2M$KEYBOARD read and the menu read.
                MOVE    KEYB_PRESSED, R0
                OR      M2M$KEY_SPACE, @R0

                ; --- gate 5: act once per physical press (rising edge) ---
                CMP     0, R4                   ; SPACE pressed now?
                RBRA    _HUK_RET, Z
                CMP     0, R5                   ; ..released last poll?
                RBRA    _HUK_RET, !Z            ; still held -> already handled
                MOVE    R2, R8                  ; eject + flush + disarm THAT
                RSUB    ADF_UNMOUNT, 1          ; drive

_HUK_RET        MOVE    M2M$RAMROM_DEV, R0      ; restore the RAMROM selection
                MOVE    R6, @R0                 ; (keeps HANDLE_CORE_IO
                MOVE    M2M$RAMROM_4KWIN, R0    ;  transparent to its caller)
                MOVE    R7, @R0
_HUK_RET_NS     DECRB
                RET

; ADF_UNMOUNT: eject the ADF of ONE drive, then flush + disarm its write-back.
;
; Order matters: eject FIRST so the Amiga sees that unit vanish and stops
; writing to it, THEN flush the already-committed dirty tracks (the eject
; leaves the HyperRAM image intact), THEN disarm. This mirrors the flush +
; disarm of PREP_LOAD_IMAGE and now shares ADF_DISARM with it. Only the drive
; that is passed in is touched: a session or dirty bitmap of another drive
; keeps running untouched. Switches the RAMROM device; the caller
; (HANDLE_UNMOUNT_KEY) restores it.
;
; Input:  R8: drive 0..2
; Output: none. Bank-local R0-R2; clobbers global R8-R10.
ADF_UNMOUNT     INCRB
                MOVE    R8, R2                  ; R2: the drive, live to the end

                ; 1. eject: STATUS := ST_IDLE on the device of that drive. The
                ; validator (adf_mount_wrapper.vhd p_validate, VS_DONE) sees
                ; req_status /= REQ_OK and drops disk_mounted; the track engine
                ; announces that unit empty within ~1 ms. STATUS/PARSEST ->
                ; IDLE also makes the Shell revert the menu label of that drive
                ; for free via CRTROM_MLST_GET (same mechanism as ST_LDNG at
                ; the start of every load).
                MOVE    ADF_DEV_TAB, R8
                ADD     R2, R8
                MOVE    @R8, R8
                MOVE    CRTROM_CSR_STATUS, R9
                MOVE    CRTROM_CSR_ST_IDLE, R10
                RSUB    CRTROM_CSR_W, 1

                ; 2. write the sectors of this drive that are still in the
                ;    track buffer to the file (Megamiga: adf_sd.vhd; it still
                ;    has the extent map of the file), then switch the drive off
                ;    there. First apply the SAME card-change guard that the SD
                ;    guard of HANDLE_CORE_IO uses (a new generation of the
                ;    drive's card, M2M-UPSTREAM sd-host): on a swapped/pulled
                ;    card the map points into whatever lives at those blocks
                ;    now, so the buffer is dropped instead (we run BEFORE that
                ;    SD guard, RSUB-ed first in HANDLE_CORE_IO).
                MOVE    ADF_FDH_VALID, R0       ; card check only when armed
                ADD     R2, R0
                CMP     1, @R0
                RBRA    _ADF_UM_FLUSH, !Z       ; not armed: nothing was written
                MOVE    ADF_SD_SLOT, R1
                ADD     R2, R1
                MOVE    @R1, R8
                RSUB    SDC$GEN, 1
                MOVE    ADF_SD_GEN, R1
                ADD     R2, R1
                CMP     @R1, R8
                RBRA    _ADF_UM_FLUSH, Z        ; same card -> safe to write

_ADF_UM_DROP    MOVE    R2, R8                  ; card changed: drop the dirty
                RSUB    ADF_WIPE_DIRTY, 1       ; bitmap and the buffer
                RBRA    _ADF_UM_OFF, 1

_ADF_UM_FLUSH   MOVE    R2, R8                  ; (a time-out leaves the
                RSUB    ADF_TB_SYNC, 1          ; sectors unwritten - the card
                                                ; does not answer any more)
_ADF_UM_OFF     MOVE    R2, R8
                RSUB    ADF_TB_OFF, 1

                ; 3. disarm the write-back (mirrors PREP_LOAD_IMAGE): the
                ; PARSEST=READY of a later genuine mount re-arms it with a fresh
                ; handle snapshot. PARSEST is IDLE now, so _HCIO_MOUNT will not
                ; re-arm regardless; ADF_MOUNT_SEEN:=0 is the correct clean
                ; state for the next mount.
_ADF_UM_DIS     MOVE    R2, R8
                RSUB    ADF_DISARM, 1

                DECRB
                RET


; ----------------------------------------------------------------------------
; Live Hardware Floppy status in the main menu
;
; Every drive owns a twin pair of main-menu lines: the mount line, shown while
; that drive is a Disk Image, and a fixed-width TEXT line
; " dfN:Hardware Floppy   " shown while it is the Hardware Floppy (the menu
; dependency layer swaps them). That TEXT line is exactly OPTM_DX characters:
; one selection-marker column plus a HWF_LABEL_LEN-wide field, so the field can
; be patched in place while the menu is on screen. This is the C64MEGA65
; "8:Internal 1581" pattern, and it uses the same framework helper
; (OPTM_LIVE_TEXT, M2M-UPSTREAM live-text), which updates the writable menu-heap
; copy of the item string AND repaints just those characters.
;
; Three coarse states are shown. The idle label is byte-identical to the static
; config.vhd text, so painting it is a visual no-op:
;
;   idle    dfN:Hardware Floppy      the mechanism is not spinning
;   motor   dfN:HW Floppy: Motor     the motor runs, no data reaching Paula
;   read    dfN:HW Floppy: Reading   decoded words are streaming into Paula
;
; The classification needs no new hardware: bit 2 of the front-end status word
; is the motor line, and diag register 0x1B counts the data words the track
; engine served into Paula, so a moving counter IS a running read.
;
; Cost discipline, in the order the gates are applied: the whole routine is
; four RAM reads while the menu is closed - which is most of the time, and it
; is polled from every wait loop. Only once all four visibility gates pass does
; it look at the timer, and only once per about 10 ms does it touch the
; diagnostic device. The screen is written solely on an actual state change.
; ----------------------------------------------------------------------------

; HWF_OSM_INIT: called once from START_FIRMWARE, before the Shell starts (RAM
; is undefined at power-on and HANDLE_IO is polled from boot-time wait loops).
HWF_OSM_INIT    INCRB
                MOVE    HWF_OSM_LAST, R0
                MOVE    HWF_OS_INVALID, @R0
                MOVE    HWF_OSM_LDRV, R0
                MOVE    HWF_DRV_NONE, @R0
                MOVE    HWF_LAST_CNT, R0
                MOVE    0, @R0
                MOVE    PRF_DIRTY, R0           ; 0.7: nothing to write back
                MOVE    0, @R0                  ; before PRF_BOOT (PRF_STEP)
                MOVE    IO$CYC_MID, R0
                MOVE    HWF_OSM_TICK, R1
                MOVE    @R0, @R1
                DECRB
                RET

; HWF_STATUS_STEP: one poll of the live Hardware Floppy status line.
;
; Expects the caller to tolerate a changed RAMROM device selection
; (HANDLE_CORE_IO saves and restores it around this call). Input/Output: none.
HWF_STATUS_STEP INCRB

                ; --- gate 1: is the OSM on screen at all? ---
                MOVE    M2M$CSR, R0
                MOVE    @R0, R0
                AND     M2M$CSR_OSM, R0
                RBRA    _HWF_HIDE, Z

                ; --- gate 2: is a sub-activity showing instead? ---
                ; The file browser and the help viewer own the screen while
                ; they run, and they poll HANDLE_IO. OSM_SUB_ACTIVE is the flag
                ; that OSM_SEL_PRE/OSM_SEL_POST bracket them with (issue #16),
                ; and it is what stands in for the OPTM_FOREGROUND of the
                ; C64MEGA65 framework - see the contract of OPTM_LIVE_TEXT.
                MOVE    OSM_SUB_ACTIVE, R0
                CMP     0, @R0
                RBRA    _HWF_HIDE, !Z

                ; --- gate 3: the twin lines live in the MAIN menu ---
                MOVE    OPTM_MENULEVEL, R0
                CMP     0, @R0
                RBRA    _HWF_HIDE, !Z

                ; --- gate 4: which drive IS the Hardware Floppy? ---
                ; The selected-state array of the menu is plain QNICE RAM and
                ; therefore much cheaper than M2M$GET_SETTING, which would have
                ; to select the config device. Only one drive can claim the
                ; single mechanism (DRV_STEAL_HW enforces it), so the first hit
                ; wins; if nobody claims it, all three TEXT lines are hidden by
                ; their dependencies and there is nothing to show.
                MOVE    OPTM_DATA, R0
                MOVE    @R0, R0
                CMP     0, R0
                RBRA    _HWF_HIDE, Z
                ADD     OPTM_IR_STDSEL, R0
                MOVE    @R0, R0                 ; R0: selected-state array
                CMP     0, R0
                RBRA    _HWF_HIDE, Z
                MOVE    DRV_MODE_TAB, R1        ; R1: the Hardware Floppy item
                ADD     1, R1                   ; of drive 0
                XOR     R2, R2                  ; R2: drive
_HWF_D          MOVE    @R1, R3
                ADD     R0, R3
                CMP     0, @R3
                RBRA    _HWF_FOUND, !Z
                ADD     3, R1                   ; three words per drive
                ADD     1, R2
                CMP     ADF_DRIVES, R2
                RBRA    _HWF_D, !Z
                RBRA    _HWF_HIDE, 1            ; nobody claims the mechanism

                ; The drive that owns the mechanism changed: the cached state
                ; belongs to the line of the OTHER drive, so invalidate it and
                ; let the new line repaint at once.
_HWF_FOUND      MOVE    HWF_OSM_LDRV, R0
                CMP     @R0, R2
                RBRA    _HWF_TMR, Z
                MOVE    R2, @R0
                MOVE    HWF_OSM_LAST, R0
                MOVE    HWF_OS_INVALID, @R0

                ; --- throttle --- IO$CYC_MID advances at about 763 Hz, so
                ; polling once per eight changes is about 95 Hz. An invalidated
                ; cache bypasses the timer, so opening the menu or returning to
                ; it from a submenu updates immediately.
_HWF_TMR        MOVE    HWF_OSM_LAST, R0
                CMP     HWF_OS_INVALID, @R0
                RBRA    _HWF_POLL, Z
                MOVE    IO$CYC_MID, R0
                MOVE    @R0, R1
                MOVE    HWF_OSM_TICK, R0
                CMP     @R0, R1
                RBRA    _HWF_RET, Z             ; same timer slice
                MOVE    R1, @R0
                AND     HWF_OSM_POLL_MASK, R1
                RBRA    _HWF_RET, !Z

_HWF_POLL       MOVE    IO$CYC_MID, R0
                MOVE    @R0, R1
                MOVE    HWF_OSM_TICK, R0
                MOVE    R1, @R0

                ; one device selection and two word reads
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    AEXP_DEV_FDD, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0                  ; the bank decodes addr[5:0]
                MOVE    HWF_DIAG_STAT, R0
                MOVE    @R0, R3                 ; R3: front-end status word
                MOVE    HWF_DIAG_SERVED, R0
                MOVE    @R0, R4                 ; R4: words served into Paula

                MOVE    HWF_LAST_CNT, R0        ; did that counter move since
                MOVE    @R0, R5                 ; the previous poll?
                MOVE    R4, @R0

                MOVE    HWF_OS_IDLE, R6         ; classify, cheapest first
                MOVE    R3, R7
                AND     HWF_ST_MOTOR, R7
                RBRA    _HWF_CLS, Z             ; motor off: idle
                MOVE    HWF_OS_MOTOR, R6
                CMP     R5, R4
                RBRA    _HWF_CLS, Z             ; spinning, but nothing served
                MOVE    HWF_OS_READ, R6         ; words are reaching Paula

_HWF_CLS        MOVE    HWF_OSM_LAST, R0        ; coarse state unchanged?
                CMP     @R0, R6
                RBRA    _HWF_RET, Z             ; then do not touch the screen
                MOVE    R6, @R0

                ; Build the label: the state template with the drive digit
                ; patched in, so three templates cover all three drives.
                MOVE    HWF_OSM_STR, R0
                ADD     R6, R0
                MOVE    @R0, R8
                RSUB    RODATA_STR, 1           ; (read-only data: in RAM)
                MOVE    HWF_LABEL, R9
                SYSCALL(strcpy, 1)
                MOVE    HWF_LABEL, R0
                ADD     HWF_LABEL_DIGIT, R0
                MOVE    R2, R1
                ADD     HWF_ASCII_ZERO, R1
                MOVE    R1, @R0

                MOVE    ADF_HW_LN_TAB, R0       ; the TEXT twin of that drive
                ADD     R2, R0
                MOVE    @R0, R8
                MOVE    1, R9                   ; skip the selection marker
                MOVE    HWF_LABEL, R10
                MOVE    HWF_LABEL_LEN, R11
                RSUB    OPTM_LIVE_TEXT, 1
                RBRA    _HWF_RET, 1

                ; Not visible. Invalidate so the first visible poll repaints:
                ; HELP_MENU re-copies the item string from config.vhd on every
                ; OSM opening, so the heap always reverts to the static text
                ; and a cached "the screen already shows this" would be wrong.
_HWF_HIDE       MOVE    HWF_OSM_LAST, R0
                CMP     HWF_OS_INVALID, @R0
                RBRA    _HWF_RET, Z
                MOVE    HWF_OS_INVALID, @R0
                MOVE    HWF_OSM_LDRV, R0
                MOVE    HWF_DRV_NONE, @R0

_HWF_RET        DECRB
                RET

; ----------------------------------------------------------------------------
; Live SD card status line at the bottom of the main menu
;
; While the main menu is on screen, the bottom row inside its frame shows the
; mode of both SD host controllers (sdhost.vhd, one per slot, M2M-UPSTREAM
; sd-host): "SD0:4-bit  SD1:SPI 25 ", read from register 6 of each (bit 0
; native 4-bit, bit 1 slow = SPI 12.5 MHz, bit 2 ready). sdhost falls back on
; its own (native -> SPI 25 MHz -> SPI 12.5 MHz after a failed transfer; a
; card used in SPI mode since power-up stays in SPI mode), and this line is
; where the user sees it. Same gates, throttle and label buffer as
; HWF_STATUS_STEP (the two never interleave).
;
; The row is painted straight into the VRAM, not through a menu item: the main
; menu is shorter than its frame unless all three drives are shown, and a
; status line as the last item would float under "Close Menu". The last item
; (AEXP_OSM_SD_STATUS) is an empty text line, so when the menu does fill the
; frame, the row under the separator is free for it. A full menu redraw
; (OPTM_SHOW) clears the row, so every poll paints the characters and the
; attributes again (about 95 times a second, 46 VRAM words).
;
; The row is dimmed with M2M$SA_DARK. The OSM renderer halves foreground AND
; background with it, so the line reads as a darker status bar.
; ----------------------------------------------------------------------------

SD_OSM_INIT     INCRB
                MOVE    SD_OSM_LAST, R0
                MOVE    HWF_OS_INVALID, @R0
                MOVE    IO$CYC_MID, R0
                MOVE    SD_OSM_TICK, R1
                MOVE    @R0, @R1
                DECRB
                RET

; SD_STATUS_STEP: one poll of the SD card status line. Changes the RAMROM
; selection (HANDLE_CORE_IO restores it). Input/Output: none.
SD_STATUS_STEP  INCRB

                MOVE    M2M$CSR, R0             ; the OSM on screen?
                MOVE    @R0, R0
                AND     M2M$CSR_OSM, R0
                RBRA    _SDS_HIDE, Z
                MOVE    OSM_SUB_ACTIVE, R0      ; no browser or help page?
                CMP     0, @R0
                RBRA    _SDS_HIDE, !Z
                MOVE    OPTM_MENULEVEL, R0      ; the main menu?
                CMP     0, @R0
                RBRA    _SDS_HIDE, !Z
                MOVE    OPTM_STRUCT, R0         ; is OPTM_RUN running?
                CMP     0, @R0
                RBRA    _SDS_HIDE, Z

                ; throttle as HWF_STATUS_STEP; invalid = paint at once
                MOVE    IO$CYC_MID, R0
                MOVE    @R0, R1
                MOVE    SD_OSM_TICK, R0
                MOVE    SD_OSM_LAST, R2
                CMP     HWF_OS_INVALID, @R2
                RBRA    _SDS_POLL, Z
                CMP     @R0, R1
                RBRA    _SDS_RET, Z             ; same timer slice
                MOVE    R1, @R0
                AND     HWF_OSM_POLL_MASK, R1
                RBRA    _SDS_RET, !Z
                RBRA    _SDS_CLS0, 1
_SDS_POLL       MOVE    R1, @R0

_SDS_CLS0       MOVE    1, R8                   ; classify both: R6 = the
                RSUB    _SDS_MODE, 1            ; internal card's state +
                MOVE    R9, R6                  ; 4 x the external one's
                ADD     R6, R6
                ADD     R6, R6
                XOR     R8, R8
                RSUB    _SDS_MODE, 1
                ADD     R9, R6

_SDS_CLS        MOVE    SD_OSM_LAST, R0         ; remember: no longer invalid
                MOVE    R6, @R0
                MOVE    HWF_LABEL, R9           ; "SD0:" + state + "SD1:" +
                XOR     R8, R8                  ; state
                MOVE    R6, R5
                AND     3, R5
                RSUB    _SDS_PUT, 1
                MOVE    1, R8
                MOVE    R6, R5
                AND     0xFFFB, SR
                SHR     2, R5
                RSUB    _SDS_PUT, 1

                ; the bottom row inside the frame: y = OPTM_Y + OPTM_DY - 2
                ; (OPTM_DY counts the frame), x from OPTM_X + 1 (the marker
                ; column, a blank) over the inner width OPTM_DX - 2
                MOVE    OPTM_Y, R9
                MOVE    @R9, R9
                MOVE    OPTM_DY, R0
                ADD     @R0, R9
                SUB     2, R9
                MOVE    SCR$SYS_DX, R8
                MOVE    @R8, R8
                SYSCALL(mulu, 1)                ; R10: y * screen width
                MOVE    OPTM_X, R0
                ADD     @R0, R10
                ADD     1, R10
                ADD     M2M$RAMROM_DATA, R10
                MOVE    OPTM_DX, R1             ; R1: inner width
                MOVE    @R1, R1
                SUB     2, R1
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0
                MOVE    M2M$RAMROM_DEV, R0      ; the characters: a blank,
                MOVE    M2M$VRAM_DATA, @R0      ; the label, blanks
                MOVE    R10, R2
                MOVE    R1, R3
                MOVE    HWF_LABEL, R4
                MOVE    HWF_LABEL_LEN, R5
                MOVE    0x0020, @R2++
                SUB     1, R3
_SDS_CHR        CMP     0, R3
                RBRA    _SDS_ATT0, Z
                MOVE    0x0020, R7
                CMP     0, R5
                RBRA    _SDS_CHR1, Z
                MOVE    @R4++, R7
                SUB     1, R5
_SDS_CHR1       MOVE    R7, @R2++
                SUB     1, R3
                RBRA    _SDS_CHR, 1
_SDS_ATT0       MOVE    M2M$VRAM_ATTR, @R0      ; dimmed: a status bar
_SDS_ATTR       MOVE    SD_OSM_ATTR, @R10++
                SUB     1, R1
                RBRA    _SDS_ATTR, !Z
                RBRA    _SDS_RET, 1

                ; not visible: the next visible poll paints at once
_SDS_HIDE       MOVE    SD_OSM_LAST, R0
                MOVE    HWF_OS_INVALID, @R0

_SDS_RET        DECRB
                RET

; _SDS_MODE: the state (SD_OS_*) of the controller of slot R8 -> R9. R10 used.
_SDS_MODE       RSUB    SDC$SEL, 1
                MOVE    SD_REG_MODE, R10
                MOVE    @R10, R10
                MOVE    SD_OS_NONE, R9
                AND     SD_MODE_READY, R10
                RBRA    _SDSM_RET, Z
                MOVE    SD_REG_MODE, R10
                MOVE    @R10, R10
                MOVE    SD_OS_4BIT, R9
                AND     SD_MODE_NATIVE, R10
                RBRA    _SDSM_RET, !Z
                MOVE    SD_REG_MODE, R10
                MOVE    @R10, R10
                MOVE    SD_OS_SPI25, R9
                AND     SD_MODE_SLOW, R10
                RBRA    _SDSM_RET, Z
                MOVE    SD_OS_SPI12, R9
_SDSM_RET       RET

; _SDS_PUT: "SDx:" (slot R8) and the text of state R5 at R9 -> R9 behind it.
; R8, R10..R12 used.
_SDS_PUT        MOVE    0x0053, @R9++           ; "SDx:"
                MOVE    0x0044, @R9++
                MOVE    R8, @R9
                ADD     0x0030, @R9++
                MOVE    0x003A, @R9++
                MOVE    R9, R10                 ; the text (read-only data)
                MOVE    SD_OSM_STR, R8
                ADD     R5, R8
                MOVE    @R8, R8
                RSUB    RODATA_STR, 1
                MOVE    R10, R9
                SYSCALL(strcpy, 1)
                ADD     SD_OSM_LEN, R9
                RET

; ----------------------------------------------------------------------------
; Drive Settings: keep the drive count and the per-drive modes consistent
; ----------------------------------------------------------------------------

; IS_ADF_GROUP: is this menu group id one of the three ADF mount items?
;
; The Shell hands the plain group id to FILTER_FILES and PREP_LOAD_IMAGE, and
; every drive needs its OWN mount group (a manual CRT/ROM line is bound to its
; id by its position in the static array). Both callbacks have to accept all
; three, otherwise the extension filter and the file-size guard silently apply
; to df0 only - and an oversized file streamed into df1 would run past the
; HyperRAM pool of that drive.
;
; Input:  R8: menu group id
; Output: C=1 if it is a df0/df1/df2 mount item, C=0 otherwise.
;         All registers preserved.
IS_ADF_GROUP    INCRB
                MOVE    ADF_GRP_TAB, R0
                XOR     R1, R1                  ; R1: drive under inspection
_IAG_D          CMP     @R0++, R8
                RBRA    _IAG_YES, Z
                ADD     1, R1
                CMP     ADF_DRIVES, R1
                RBRA    _IAG_D, !Z
                AND     0xFFFB, SR              ; clear Carry: not a mount item
                DECRB
                RET
_IAG_YES        MOVE    R1, R9                  ; the drive behind the group id
                OR      0x0004, SR              ; set Carry
                DECRB
                RET

; Menu line of each mode item, three words per drive: Disk Image, Hardware
; Floppy, Off. df0 always exists and therefore has no Off item - 0xFFFF marks
; that, and every loop below skips it.
DRV_MODE_TAB    .DW AEXP_OSM_DF0_IMG, AEXP_OSM_DF0_HW, 0xFFFF
                .DW AEXP_OSM_DF1_IMG, AEXP_OSM_DF1_HW, AEXP_OSM_DF1_OFF
                .DW AEXP_OSM_DF2_IMG, AEXP_OSM_DF2_HW, AEXP_OSM_DF2_OFF

; DRV_ENFORCE_COUNT: called after the "Drives" radio changed.
;
; A drive that the new count does not cover must sit on its Off item, and a
; drive that just came back must leave it. The Off item is the one the count
; radio swaps in through the menu dependency, so this is what makes the drive
; appear in and disappear from the main menu. Note that we cannot simply hide
; the mode radio instead: the main-menu twin lines depend on the MODE, not on
; the count, and a dependent line may name only one mother group.
;
; Input:  none    Output: none    All registers preserved.
DRV_ENFORCE_COUNT SYSCALL(enter, 1)

                MOVE    1, R0                   ; R0: number of drives
                MOVE    AEXP_OSM_DRIVES_2, R8
                RSUB    M2M$GET_SETTING, 1
                CMP     0, R9
                RBRA    _DRVEC_C3, Z
                MOVE    2, R0
                RBRA    _DRVEC_L, 1
_DRVEC_C3       MOVE    AEXP_OSM_DRIVES_3, R8
                RSUB    M2M$GET_SETTING, 1
                CMP     0, R9
                RBRA    _DRVEC_L, Z
                MOVE    3, R0

_DRVEC_L        MOVE    1, R1                   ; R1: drive under inspection
                                                ; (df0 always exists)
_DRVEC_D        CMP     3, R1                   ; all drives done?
                RBRA    _DRVEC_RET, Z
                MOVE    DRV_MODE_TAB, R2        ; R2: &tab[drive]
                MOVE    R1, R3
                ADD     R3, R3                  ; three words per drive
                ADD     R1, R3
                ADD     R3, R2

                ; QNICE CMP sets N for an unsigned src > dst, so this asks
                ; "count > drive index", i.e. "the count still covers it"
                CMP     R0, R1
                RBRA    _DRVEC_OFF, !N          ; no: the drive is gone

                ; the drive exists: leave Off if it is still selected
                MOVE    R2, R4
                ADD     2, R4
                MOVE    @R4, R8                 ; Off item of this drive
                RSUB    M2M$GET_SETTING, 1
                CMP     0, R9
                RBRA    _DRVEC_N, Z             ; not on Off: nothing to do
                MOVE    @R2, R8                 ; select Disk Image instead
                MOVE    1, R9
                RSUB    M2M$FORCE_MENU, 1
                RBRA    _DRVEC_N, 1

                ; the drive does not exist any more: force it to Off - but only
                ; if it is not already there. OPTM_SET goes FATAL when it is
                ; asked to select the item of a menu group that is ALREADY the
                ; selected one: its "unselect the other member" scan then finds
                ; nothing and falls through into OPTM_F_MENUGRP.
_DRVEC_OFF      MOVE    R2, R4
                ADD     2, R4
                MOVE    @R4, R8
                RSUB    M2M$GET_SETTING, 1
                CMP     0, R9
                RBRA    _DRVEC_N, !Z            ; already Off: nothing to do
                MOVE    1, R9
                RSUB    M2M$FORCE_MENU, 1

_DRVEC_N        ADD     1, R1
                RBRA    _DRVEC_D, 1

_DRVEC_RET      SYSCALL(leave, 1)
                RET

; DRV_STEAL_HW: called after the mode radio of one drive changed.
;
; There is exactly one physical mechanism in a MEGA65, so if the drive that
; just changed took "Hardware Floppy", every other drive that still claims it
; has to fall back to "Disk Image" (clear-before-set, the C64MEGA65
; _OSM_PRE_STEAL pattern). If it took something else, nothing is stolen.
;
; Input:  R8: the drive whose mode changed (0..2)
; Output: R8/R9 undefined; all other registers preserved.
DRV_STEAL_HW    SYSCALL(enter, 1)

                MOVE    R8, R0                  ; R0: the drive that changed
                MOVE    DRV_MODE_TAB, R1
                MOVE    R0, R2
                ADD     R2, R2
                ADD     R0, R2
                ADD     R2, R1                  ; R1: &tab[changed drive]
                MOVE    R1, R3
                ADD     1, R3
                MOVE    @R3, R8                 ; its Hardware Floppy item
                RSUB    M2M$GET_SETTING, 1
                CMP     0, R9
                RBRA    _DRVSH_RET, Z           ; not the hardware drive: done

                XOR     R4, R4                  ; R4: drive to check
_DRVSH_D        CMP     3, R4
                RBRA    _DRVSH_RET, Z
                CMP     R4, R0                  ; skip the drive that changed
                RBRA    _DRVSH_N, Z
                MOVE    DRV_MODE_TAB, R5
                MOVE    R4, R6
                ADD     R6, R6
                ADD     R4, R6
                ADD     R6, R5                  ; R5: &tab[drive]
                MOVE    R5, R6
                ADD     1, R6
                MOVE    @R6, R8                 ; its Hardware Floppy item
                RSUB    M2M$GET_SETTING, 1
                CMP     0, R9
                RBRA    _DRVSH_N, Z             ; does not claim it: leave alone
                MOVE    @R5, R8                 ; hand it back a disk image
                MOVE    1, R9
                RSUB    M2M$FORCE_MENU, 1
_DRVSH_N        ADD     1, R4
                RBRA    _DRVSH_D, 1

_DRVSH_RET      SYSCALL(leave, 1)
                RET

; DRV_EJECT_GONE: eject the disk of every drive that is no longer a Disk Image.
;
; A drive that the user switches to "Hardware Floppy" or to "Off" would
; otherwise keep its ADF in HyperRAM and its write-back armed while losing every
; way of getting rid of it again: the mount line of that drive is hidden by the
; menu dependency, so the SPACE eject cannot reach it, and no other unmount path
; exists. That stranded mount would also hold its file against every other
; drive, because ADF_DUP_CHECK compares the fresh file against the armed drives -
; so taking a disk out of df1 by turning df1 off would make that same disk
; unmountable in df0. Leaving Disk Image mode therefore ejects, through the very
; routine the SPACE gesture uses: flush what is pending into the right file
; first, then disarm.
;
; Called from OSM_SEL_POST after the two consistency helpers have settled the
; model, so every mode item already carries its final value.
;
; Input:  none    Output: none    All registers preserved.
DRV_EJECT_GONE  SYSCALL(enter, 1)

                MOVE    M2M$RAMROM_DEV, R0      ; ADF_UNMOUNT switches devices
                MOVE    @R0, R1                 ; and does not restore them
                MOVE    M2M$RAMROM_4KWIN, R2
                MOVE    @R2, R3

                XOR     R4, R4                  ; R4: drive
_DEG_D          MOVE    DRV_MODE_TAB, R5        ; R5: &tab[drive]
                MOVE    R4, R6
                ADD     R6, R6                  ; three words per drive
                ADD     R4, R6
                ADD     R6, R5
                MOVE    @R5, R8                 ; its Disk Image item
                RSUB    M2M$GET_SETTING, 1
                CMP     0, R9
                RBRA    _DEG_N, !Z              ; still a Disk Image: keep it

                MOVE    ADF_DEV_TAB, R5         ; is anything mounted in it?
                ADD     R4, R5
                MOVE    @R5, R8
                MOVE    CRTROM_CSR_PARSEST, R9
                RSUB    CRTROM_CSR_R, 1
                CMP     CRTROM_CSR_PT_OK, R10
                RBRA    _DEG_N, !Z              ; empty: nothing to eject

                MOVE    R4, R8
                RSUB    ADF_UNMOUNT, 1          ; eject + flush + disarm

_DEG_N          ADD     1, R4
                CMP     ADF_DRIVES, R4
                RBRA    _DEG_D, !Z

                MOVE    R1, @R0                 ; restore RAMROM selection
                MOVE    R3, @R2
                SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; Shared folder entry points (Megamiga 0.6.1): the code is in code bank BANK_SHARE (see
; "Code banks" after END_OF_ROM); these are its entry points in the fixed ROM.
; ----------------------------------------------------------------------------

SHARE_INIT      RSUB    FAR_CALL, 1
                .DW     BANK_SHARE, B0_SHARE_INIT
SHARE_STEP      RSUB    FAR_CALL, 1
                .DW     BANK_SHARE, B0_SHARE_STEP

; the files a machine profile remembers (in code bank BANK_F32F)
PROF_REMEMBER   RSUB    FAR_CALL, 1
                .DW     BANK_F32F, B2_PROF_REMEMBER
PROF_SAVED      RSUB    FAR_CALL, 1
                .DW     BANK_F32F, B2_PROF_SAVED
PROF_FORGET     RSUB    FAR_CALL, 1
                .DW     BANK_F32F, B2_PROF_FORGET
PROF_AR3_APPLY  RSUB    FAR_CALL, 1
                .DW     BANK_F32F, B2_PROF_AR3
; Megamiga 0.7: profiles as files (profiles.asm, code bank 3)
PRF_BOOT        RSUB    FAR_CALL, 1
                .DW     BANK_PROF, B4_PRF_BOOT
PRF_SELECT      RSUB    FAR_CALL, 1
                .DW     BANK_PROF, B4_PRF_SELECT
PRF_RENAME      RSUB    FAR_CALL, 1
                .DW     BANK_PROF, B4_PRF_RENAME
PRF_STEP        RSUB    FAR_CALL, 1
                .DW     BANK_PROF, B4_PRF_STEP
PRF_CHANGED     RSUB    FAR_CALL, 1
                .DW     BANK_PROF, B4_PRF_CHANGED
PRF_KGET        RSUB    FAR_CALL, 1
                .DW     BANK_PROF, B4_PRF_KGET
PRF_KSET        RSUB    FAR_CALL, 1
                .DW     BANK_PROF, B4_PRF_KSET
HDF_MAPBAR      RSUB    FAR_CALL, 1             ; HDF_PREP: the extent map
                .DW     BANK_PROF, B4_HDF_MAP
; the signature of the settings file (M2M-UPSTREAM cfg-strings, options.asm)
CFG_SIGCHECK    RSUB    FAR_CALL, 1
                .DW     BANK_F32F, B2_CFG_CHECK
CFG_SIGSET      RSUB    FAR_CALL, 1
                .DW     BANK_F32F, B2_CFG_SIGSET
CFG_SIGWARN     RSUB    FAR_CALL, 1
                .DW     BANK_F32F, B2_CFG_WARN

; ----------------------------------------------------------------------------
; The FAT32 write layer (M2M/QNICE/monitor/fat32_write.asm, fat32_wfile.asm):
; the core is code bank BANK_F32W, writing files is BANK_F32F. These stubs are
; their entry points - the names that fat32_wglue.asm gives them in a flat
; program - including the core routines that the file part calls.
; ----------------------------------------------------------------------------

FAT32$W_CREATE  RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_CREATE
FAT32$W_DELETE  RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_DELETE
FAT32$W_SETDE   RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_SETDE
FAT32$W_MKDIR   RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_MKDIR
FAT32$W_RENAME  RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_RENAME
FAT32$W_FDH     RSUB    FAR_CALL, 1
                .DW     BANK_F32F, _F32W_FDH
FAT32$W_PUT     RSUB    FAR_CALL, 1
                .DW     BANK_F32F, _F32W_PUT
FAT32$W_ADV     RSUB    FAR_CALL, 1
                .DW     BANK_F32F, _F32W_ADV
FAT32$W_SYNC    RSUB    FAR_CALL, 1
                .DW     BANK_F32F, _F32W_SYNC
FAT32$W_SETSIZE RSUB    FAR_CALL, 1
                .DW     BANK_F32F, _F32W_SETSIZE
_F32WX_BEGIN    RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_BEGIN
_F32WX_END      RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_END
_F32WX_SCAN     RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_SCAN
_F32WX_FATGET   RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_FATGET
_F32WX_FATSET   RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_FATSET
_F32WX_ISDATA   RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_ISDATA
_F32WX_ALLOC    RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_ALLOC
_F32WX_FREE     RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_FREE
_F32WX_ZEROCL   RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_ZEROCL
_F32WX_CLSEC    RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_CLSEC
_F32WX_SEC      RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_SEC
_F32WX_SETDE    RSUB    FAR_CALL, 1
                .DW     BANK_F32W, _F32W_SETDE

; ----------------------------------------------------------------------------
; FAR_CALL: call a routine in a code bank (Megamiga, M2M-UPSTREAM code-banks).
;
; The QNICE address space is 64K words, so code that does not fit into the
; 32K-word ROM lives in code banks: 4K-word banks that M2M$CODE_BANK shows in
; the window M2M$CODE_WIN (0x9000-0x9FFF). An entry point of a bank is a stub
; in the fixed ROM:
;
;   NAME            RSUB    FAR_CALL, 1
;                   .DW     <bank>, <address in the window>
;
; FAR_CALL selects the bank, calls the routine and selects the bank of the
; caller again, then returns to the caller of the stub. R8..R12 and the Carry
; pass through both ways (the other flags do not); the stack holds one word
; more during the call. Code in a bank may call the fixed ROM directly but
; never another bank (only through a stub); the fixed ROM never calls into a
; bank except through a stub.
; ----------------------------------------------------------------------------

FAR_CALL        INCRB
                MOVE    @SP++, R0               ; R0: the two words of the stub
                MOVE    M2M$CODE_BANK, R3
                MOVE    @R3, R4                 ; R4: the bank of the caller
                MOVE    @R0++, @R3              ; select the bank
                MOVE    @R0, R0
                ASUB    R0, 1
                MOVE    R4, @R3                 ; the caller's bank again
                DECRB
                RET

; ----------------------------------------------------------------------------
; IDE board: HDF hard disk image (WIP-V2-A11-JS-02)
;
; ide_board.vhd is a Zorro II IDE controller that is register-compatible with
; RIPPLE, so the lide.device boot ROM (/amiga/lide.rom, auto-loaded into the
; HyperRAM behind C_DEV_AMIGA_IDEROM) autoboots Kickstart 1.3 from it. The
; hardware only does what has to happen within a 68000 bus cycle: BSY on a
; command write and DRQ off with the 256th data word. This firmware is the
; drive behind it - like ide.cpp on the HPS side of MiSTer - and serves the
; ATA commands straight from the HDF file on the SD card, one sector per
; HANDLE_CORE_IO time slice:
;
;   * The " HDF:%s" line of the Drive Settings submenu is a manual CRT/ROM
;     load into C_DEV_AMIGA_IDE. PREP_LOAD_IMAGE (HDF_PREP) validates the
;     file, keeps its own copy of the file handle (the Shell re-opens its
;     handle for the next load), builds an extent map for seeking without FAT
;     reads (FAT32$FILE_MAP) and moves the read pointer of the Shell to the end
;     of the file, so nothing is streamed. The board answers the CSR handshake
;     itself. A mount resets the Amiga, so that Kickstart autoconfigs the board
;     and lide.device reads the RDB of the new disk.
;   * The board is in the autoconfig chain only while lide.rom was loaded AND
;     an HDF is mounted: without a disk the Amiga stays a plain A500.
;   * Every written sector is flushed before the time slice ends: the SD
;     controller has ONE sector buffer that every SD user shares (see
;     FLUSH_ADF_STEP), so no dirty sector may survive a return to the loop.
;   * LBA28 only: IDENTIFY reports LBA support and no multiple mode, so
;     lide.device uses READ/WRITE SECTORS with LBA addressing. A CHS command
;     is aborted.
;   * The IDE bus of RIPPLE is byte-swapped: sector data needs no swapping
;     (byte 2i of the sector is the high byte of word i), IDENTIFY words do
;     (lide.device swaps them back).
; ----------------------------------------------------------------------------

; IDE_SEL: select the window 0 of the IDE board device.
; Input/Output: none; all registers preserved
IDE_SEL         INCRB
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    AEXP_DEV_IDE, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0
                DECRB
                RET

#if IDE_DIAG
; IDE_DIAG_STEP: every 1024 x 65536 QNICE cycles (1.34 s): the snapshot of the
; board's diagnostics counters as one line on the UART, always (the CPU entries
; 12/13 show a hung CPU too). Changes the RAMROM selection. Registers preserved.
IDE_DIAG_STEP   INCRB
                MOVE    IO$CYC_MID, R0
                MOVE    @R0, R0                 ; R0: now, in 65536 cycles
                MOVE    IDE_DLAST_T, R1
                MOVE    R0, R2
                SUB     @R1, R2                 ; R2: elapsed (mod 65536)
                AND     0xFC00, R2              ; 1024 or more?
                RBRA    _IDG_RET, Z
                MOVE    R0, @R1
                RSUB    IDE_SEL, 1
                MOVE    IDE_DIAG_REQ, R2
                MOVE    0, @R2                  ; snapshot request
                MOVE    200, R3                 ; (the snapshot crosses over
_IDG_W          SUB     1, R3                   ; in well under 10 us)
                RBRA    _IDG_W, !Z
                MOVE    IDE_DIAG_CNT, R2
                ADD     2, R2                   ; counter 1 (data words), lo
                MOVE    @R2, R4
                MOVE    IDE_DLAST_W, R5
                ;CMP     @R5, R4
                ;RBRA    _IDG_RET, Z             ; nothing moved: no line
                MOVE    R4, @R5
                INCRB                           ; (the syscalls use R8..R12)
                MOVE    IDE_DIAG_STR, R8
                SYSCALL(puts, 1)
                MOVE    IDE_DIAG_CNT, R0
                MOVE    14, R1
_IDG_L          MOVE    @R0++, R2               ; lo
                MOVE    @R0++, R8               ; hi
                SYSCALL(puthex, 1)
                MOVE    R2, R8
                SYSCALL(puthex, 1)
                MOVE    IDE_DIAG_SP, R8
                SYSCALL(puts, 1)
                SUB     1, R1
                RBRA    _IDG_L, !Z
                SYSCALL(crlf, 1)
                DECRB
_IDG_RET        DECRB
                RET
IDE_DIAG_STR    .ASCII_W "IDE "
IDE_DIAG_SP     .ASCII_W " "
#endif

; IDE_MULT_REG: the multiple count of drive R8 into the board (READ/WRITE
; MULTIPLE: the sector engine takes them while it is not 0, the board groups
; their sectors into blocks of this size). Selects the IDE device.
; Input: R8: drive, R9: count. Registers preserved.
IDE_MULT_REG    INCRB
                RSUB    IDE_SEL, 1
                MOVE    IDE_ENG_U0, R0
                CMP     0, R8
                RBRA    _IMR_U, Z
                MOVE    IDE_ENG_U1, R0
_IMR_U          ADD     IDE_ENG_MULT, R0
                MOVE    R9, @R0
                DECRB
                RET

; IDE_GEOM_REG: the CHS geometry of drive R8 (HDF_HEADS / HDF_SPT of the active
; disk state, which must be that drive's) into the board: (heads - 1) << 12 |
; sectors per track. The sector engine converts CHS commands with it (Megamiga
; 0.7, the scsi.device of Kickstart 3.1); invalid addresses still come here.
; Input: R8: drive. Registers preserved. Selects the IDE device.
IDE_GEOM_REG    INCRB
                RSUB    IDE_SEL, 1
                MOVE    IDE_ENG_U0, R0
                CMP     0, R8
                RBRA    _IGR_U, Z
                MOVE    IDE_ENG_U1, R0
_IGR_U          ADD     IDE_ENG_GEOM, R0
                MOVE    HDF_HEADS, R1
                MOVE    @R1, R1
                SUB     1, R1
                AND     0x000F, R1
                AND     0xFFFD, SR              ; (X = 0: shift in zeros)
                SHL     12, R1
                MOVE    HDF_SPT, R2
                MOVE    @R2, R2
                AND     0x01FF, R2
                OR      R2, R1
                MOVE    R1, @R0
                DECRB
                RET

; IDE_INIT: called once from START_FIRMWARE. No disk, board out of the
; autoconfig chain, event shadow in sync with the hardware.
IDE_INIT        INCRB
                MOVE    FL_NOBAR, R0            ; (PROFILE_APPLY)
                MOVE    0, @R0
                MOVE    HDF_UNITS, R0           ; no disk, the master active,
                MOVE    HDF_SAVE_END, R1        ; both disk states zero (no
_IDI_Z          MOVE    0, @R0++                ; device pointer: HDF_SELECT
                CMP     R0, R1                  ; releases no SD buffer for a
                RBRA    _IDI_Z, !Z              ; drive that was never mounted)
                MOVE    IDE_STATE, R0
                MOVE    IDE_ST_IDLE, @R0
                RSUB    IDE_SEL, 1
                MOVE    IDE_CTRL, R0
                MOVE    0, @R0
                MOVE    IDE_ENG_U0, R0          ; sector engine off
                MOVE    IDE_ENG_OFF, @R0
                MOVE    IDE_ENG_U1, R0
                MOVE    IDE_ENG_OFF, @R0
                MOVE    IDE_EVENTS, R0
                MOVE    IDE_LAST_EV, R1
                MOVE    @R0, @R1
                DECRB
                RET

; IDE_LIDE_OK: was /amiga/lide.rom loaded at startup (optional auto-load ROM 1)?
; Megamiga 0.7: always yes while the board is the Gayle (the scsi.device of the Kickstart
; drives it, no boot ROM needed).
; Output: C=1 if loaded, C=0 if not; all registers preserved
; (results travel in C: the RET is a MOVE and may change Z and N)
IDE_LIDE_OK     INCRB
                MOVE    M2M$RAMROM_DEV, R0      ; Gayle mode? (keep the selection)
                MOVE    @R0, R1
                MOVE    M2M$RAMROM_4KWIN, R2
                MOVE    @R2, R3
                RSUB    IDE_SEL, 1
                MOVE    IDE_GAYLE, R4
                MOVE    @R4, R4
                MOVE    R1, @R0
                MOVE    R3, @R2
                AND     1, R4
                RBRA    _ILO_YES, !Z
                MOVE    CRTROM_AUT_LDF, R0
                ADD     IDE_LIDE_AUTO_ID, R0
                CMP     0, @R0
                RBRA    _ILO_NO, Z
_ILO_YES        OR      0x0004, SR              ; C=1
                DECRB
                RET
_ILO_NO         AND     0xFFFB, SR              ; C=0
                DECRB
                RET

; HDF_DROP: forget mounted disks. The drives vanish from the IDE bus at once
; (their registers read 0xFF, a command in progress is never completed). The
; board itself stays in the autoconfig chain until the next reset. Their menu
; lines revert to <Load>: the CSR STATUS of their devices goes IDLE, which the
; Shell turns into "not loaded" (CRTROM_MLST_GET).
; Input: R8: drives, bit 0 master, bit 1 slave. Output: none; registers preserved
HDF_DROP        INCRB
                MOVE    R8, R2                  ; R2: the drives
                MOVE    R9, R6
                MOVE    R10, R7
                NOT     R8, R0
                MOVE    HDF_UNITS, R1
                AND     R0, @R1
                MOVE    IDE_STATE, R0
                MOVE    IDE_ST_IDLE, @R0
                MOVE    HDF_DEV_TAB, R3         ; R3: device of the drive
                MOVE    R2, R4                  ; R4: drives still to do
_HDD_L          MOVE    R4, R5
                AND     1, R5
                RBRA    _HDD_N, Z
                MOVE    @R3, R8
                MOVE    CRTROM_CSR_STATUS, R9
                MOVE    CRTROM_CSR_ST_IDLE, R10
                RSUB    CRTROM_CSR_W, 1
_HDD_N          ADD     1, R3
                AND     0xFFFB, SR
                SHR     1, R4
                CMP     0, R4
                RBRA    _HDD_L, !Z
                RSUB    IDE_SEL, 1
                MOVE    R2, R4                  ; the sector engine of the
                AND     1, R4                   ; dropped drives off
                RBRA    _HDD_E1, Z
                MOVE    IDE_ENG_U0, R4
                MOVE    IDE_ENG_OFF, @R4
_HDD_E1         MOVE    R2, R4
                AND     2, R4
                RBRA    _HDD_E2, Z
                MOVE    IDE_ENG_U1, R4
                MOVE    IDE_ENG_OFF, @R4
_HDD_E2         MOVE    IDE_CTRL, R8            ; keep the board bit
                MOVE    @R8, R8
                AND     IDE_CTRL_BOARD, R8
                RSUB    HDF_CTRL, 1
                MOVE    R2, R8
                MOVE    R6, R9
                MOVE    R7, R10
                DECRB
                RET

; HDF_EJECT: SPACE on an HDF line of the menu (HANDLE_UNMOUNT_KEY). The drive
; goes, without any drive the board leaves the autoconfig chain, and the Amiga
; restarts: Kickstart and lide.device only look for drives at a reset.
; Input: R8: drive 0 / 1. Output: none; R8 clobbered. Selects the IDE device.
HDF_EJECT       INCRB
                ADD     1, R8                   ; drive mask
                RSUB    HDF_DROP, 1
                MOVE    HDF_UNITS, R0
                CMP     0, @R0
                RBRA    _HEJ_RST, !Z
                MOVE    IDE_CTRL, R0            ; (HDF_DROP selected the board)
                MOVE    0, @R0
_HEJ_RST        RSUB    IDE_RESET_AMIGA, 1
                DECRB
                RET

; HDF_CTRL: IDE_CTRL = the present bits of HDF_UNITS + R8 (0 or
; IDE_CTRL_BOARD). Selects the IDE device; all registers preserved.
HDF_CTRL        INCRB
                RSUB    IDE_SEL, 1
                MOVE    HDF_UNITS, R0
                MOVE    @R0, R0
                MOVE    R0, R1
                AND     1, R1                   ; master: bit 0
                AND     2, R0                   ; slave: bit 1 -> bit 2
                ADD     R0, R0
                OR      R0, R1
                OR      R8, R1
                MOVE    IDE_CTRL, R0
                MOVE    R1, @R0
                DECRB
                RET

; HDF_SELECT: make the disk state of drive R8 (0 master, 1 slave) the active
; one, HDF_FDH up to HDF_SAVE: swap it with HDF_SAVE. The one SD sector buffer
; is tracked by the ADDRESS of its owner, and both drives use HDF_FDH, so the
; buffer is released first (a written sector is always flushed already, so this
; only drops a cached one).
; Input: R8: drive. Output: none; all registers preserved
HDF_SELECT      INCRB
                MOVE    HDF_ACTIVE, R0
                CMP     @R0, R8
                RBRA    _HSE_RET, Z
                MOVE    R8, @R0
                MOVE    R8, R4
                MOVE    R9, R5
                MOVE    HDF_FDH, R8             ; (FAT32$FDH_DEVICE = 0)
                CMP     0, @R8                  ; never mounted: no device
                RBRA    _HSE_SWAP, Z
                RSUB    _F32_RELEASE_BUF, 1
_HSE_SWAP       MOVE    HDF_FDH, R0
                MOVE    HDF_SAVE, R1
                MOVE    R1, R2                  ; R2: words
                SUB     R0, R2
_HSE_L          MOVE    @R0, R3
                MOVE    @R1, @R0++
                MOVE    R3, @R1++
                SUB     1, R2
                RBRA    _HSE_L, !Z
                MOVE    R4, R8
                MOVE    R5, R9
_HSE_RET        DECRB
                RET

; HDF_PREP: the PREP_LOAD_IMAGE part of the HDF mount
;
; Input:  R8: the file handle of the Shell (just opened)
;         R9: drive, 0 = master, 1 = slave
; Output: R8: 0=OK, else error; R9: 0 or pointer to an error message
HDF_PREP        INCRB
                MOVE    R10, @--SP              ; the Shell keeps the ROM id in
                MOVE    R11, @--SP              ; R12 across PREP_LOAD_IMAGE
                MOVE    R12, @--SP              ; (HDF_LINK returns in R9..R12)
                MOVE    R8, R0                  ; R0: the handle of the Shell
                MOVE    R9, R6                  ; R6: the drive

                RSUB    IDE_LIDE_OK, 1          ; no boot ROM, no board
                RBRA    _HDFP_NOROM, !C

                MOVE    HDF_VPART, R1           ; a partition, not the file
                CMP     0, @R1                  ; (the file browser or a
                RBRA    _HDFP_NVP, Z            ; profile chose it): slot <<
                MOVE    @R1, R8                 ; 8 | number. The handle is
                SWAP    R8, R8                  ; an empty one: its device
                AND     0x00FF, R8              ; is that card's (FAT32
                RSUB    SDC$BLKDEV, 1           ; or not; M2M-UPSTREAM sd-host)
                CMP     0, R9
                RBRA    _HDFP_BADPT, !Z
                MOVE    R8, @R0                 ; (FAT32$FDH_DEVICE = 0)
                MOVE    R0, R8
                MOVE    @R1, R9
                AND     0x00FF, R9
                RSUB    HDF_PART_GET, 1
                CMP     0x00FF, R8
                RBRA    _HDFP_BADPT, Z
                MOVE    R8, R3                  ; R3: the partition
                RBRA    _HDFP_LINK, 1
_HDFP_NVP

                MOVE    R0, R1                  ; R2/R3: file size
                ADD     FAT32$FDH_SIZE_LO, R1
                MOVE    @R1, R2
                MOVE    R0, R1
                ADD     FAT32$FDH_SIZE_HI, R1
                MOVE    @R1, R3
                CMP     0, R3                   ; under 512 bytes: maybe a link
                RBRA    _HDFP_FILE, !Z          ; file that names a partition
                CMP     R2, 0x01FF
                RBRA    _HDFP_FILE, N           ; (R2 > 511)
                MOVE    R0, R8
                RSUB    HDF_LINK, 1
                CMP     0, R8
                RBRA    _HDFP_FILE, Z           ; not a link file
                CMP     0xFF, R8
                RBRA    _HDFP_BADPT, Z          ; a link, but no such partition
                MOVE    R8, R3                  ; R3: the partition (size hi
                RBRA    _HDFP_LINK, 1           ; is 0 here anyway)
_HDFP_FILE      MOVE    R2, R1                  ; a whole number of sectors
                AND     0x01FF, R1
                RBRA    _HDFP_BADSZ, !Z
                CMP     HDF_MIN_SIZE_HI, R3     ; at least HDF_MIN_SIZE_HI
                RBRA    _HDFP_BADSZ, N          ; x 64 KB (unsigned compare)

                ; the disk state of this drive; its old disk goes first:
                ; from here on the drive is absent until the new one is complete
                MOVE    R6, R8
                RSUB    HDF_SELECT, 1
                ADD     1, R8                   ; drive mask: 1 or 2
                RSUB    HDF_DROP, 1

                MOVE    R0, R8                  ; our own copy of the handle
                MOVE    HDF_FDH, R9
                MOVE    FAT32$FDH_STRUCT_SIZE, R10
                SYSCALL(memcpy, 1)
                MOVE    HDF_FDH, R1             ; never start out DIRTY: the
                ADD     FAT32$FDH_FLAGS, R1     ; one sector buffer is tracked
                MOVE    0, @R1                  ; by the handle address
                MOVE    HDF_PART, R1            ; a file, not a partition
                MOVE    0, @R1

                ; total sectors = size >> 9
                MOVE    R2, R4
                AND     0xFFFB, SR              ; clear C: shift in zeros
                SHR     9, R4
                MOVE    R3, R5
                AND     0xFFFD, SR              ; clear X: shift in zeros
                SHL     7, R5
                OR      R5, R4
                MOVE    HDF_SECT_LO, R1
                MOVE    R4, @R1
                MOVE    R3, R4
                AND     0xFFFB, SR
                SHR     9, R4
                MOVE    HDF_SECT_HI, R1
                MOVE    R4, @R1

                ; extent map: seeks without FAT reads. A file with more
                ; extents than the map holds still works, through the
                ; cluster-stepping FAT32$FILE_SEEK.
                RSUB    HDF_MAPBAR, 1           ; (0.7: with a progress bar)
                MOVE    HDF_MAPOK, R1
                MOVE    1, @R1
                CMP     0, R9
                RBRA    _HDFP_SEEK, Z
                MOVE    0, @R1
                CMP     FAT32$ERR_MAPSIZE, R9
                RBRA    _HDFP_FATERR, !Z

                ; the Shell would stream the file into the device: move its
                ; read pointer to the end, so that it reads EOF right away
_HDFP_SEEK      RSUB    HDF_GEOM_INIT, 1        ; direct block I/O state
                MOVE    R0, R8
                MOVE    R2, R9
                MOVE    R3, R10
                MOVE    HDF_MAP, R11
                MOVE    HDF_MAPOK, R1
                CMP     1, @R1
                RBRA    _HDFP_SKM, Z
                SYSCALL(f32_fseek, 1)
                RBRA    _HDFP_SKD, 1
_HDFP_SKM       RSUB    FAT32$FILE_SEEK_MAP, 1
_HDFP_SKD       CMP     0, R9
                RBRA    _HDFP_FATERR, !Z

                MOVE    HDF_FDH, R8             ; remember the card and its
                MOVE    @R8, R8                 ; generation (see the SD
                RSUB    SDC$SLOT, 1             ; guards in IDE_STEP; M2M-
                MOVE    HDF_DSLOT, R1           ; UPSTREAM sd-host: each drive
                ADD     R6, R1                  ; can be on either card)
                MOVE    R8, @R1
                RSUB    SDC$GEN, 1
                MOVE    HDF_DGEN, R1
                ADD     R6, R1
                MOVE    R8, @R1
                MOVE    HDF_HEADS, R8           ; the default CHS geometry
                MOVE    IDE_DEF_HEADS, @R8      ; (until INITIALIZE DEVICE
                MOVE    HDF_SPT, R8             ; PARAMETERS changes it)
                MOVE    IDE_DEF_SPT, @R8
                MOVE    HDF_MULT, R8            ; READ/WRITE MULTIPLE in blocks
                MOVE    IDE_MULT_MAX, @R8       ; of 16 (until SET MULTIPLE)
                RSUB    HDF_VRDB_DET, 1         ; Megamiga 0.7: a virtual RDB?
                MOVE    R6, R8                  ; mounted: bit 0 or 1
                ADD     1, R8
                MOVE    HDF_UNITS, R1
                OR      R8, @R1
                MOVE    R6, R8                  ; READ/WRITE SECTORS in hardware
                RSUB    HDF_ENG_SETUP, 1
                MOVE    R6, R8                  ; the multiple count for the
                MOVE    IDE_MULT_MAX, R9        ; board (engine, block size)
                RSUB    IDE_MULT_REG, 1
                MOVE    R6, R8                  ; and the CHS geometry (the
                RSUB    IDE_GEOM_REG, 1         ; engine converts CHS itself)

                ; drive present, board in the chain; restart the Amiga so that
                ; Kickstart configures the board and boots from the disk
                RSUB    IDE_SEL, 1
                MOVE    IDE_EVENTS, R1
                MOVE    IDE_LAST_EV, R4
                MOVE    @R1, @R4
                MOVE    IDE_CTRL_BOARD, R8
                RSUB    HDF_CTRL, 1
                RSUB    IDE_RESET_AMIGA, 1

                XOR     R8, R8
                XOR     R9, R9
                RBRA    _HDFP_RET, 1

                ; a link file: the drive is partition R4 of the SD card (start
                ; R10:R9, size R12:R11 blocks). It must not be the disk of the
                ; other drive already; after HDF_SELECT, HDF_SAVE holds that one.
_HDFP_LINK      MOVE    R9, R4                  ; R4/R5: start, R1/R7: size
                MOVE    R10, R5
                MOVE    R11, R1
                MOVE    R12, R7
                MOVE    R6, R8
                RSUB    HDF_SELECT, 1
                MOVE    HDF_UNITS, R8           ; the other drive mounted?
                MOVE    @R8, R8
                MOVE    R6, R9                  ; its bit: the other drive
                XOR     1, R9                   ; (R6 xor 1) + 1 = 1 for the
                ADD     1, R9                   ; master, 2 for the slave
                AND     R9, R8
                RBRA    _HDFP_LDUP, Z           ; no
                MOVE    HDF_SAVE, R8            ; on the same card? (its
                CMP     @R8, @R0                ; FAT32$FDH_DEVICE)
                RBRA    _HDFP_LDUP, !Z
                MOVE    HDF_SAVE, R8            ; its HDF_PART
                ADD     HDF_PART, R8
                SUB     HDF_FDH, R8
                CMP     0, @R8++
                RBRA    _HDFP_LDUP, Z           ; it holds a file
                CMP     R4, @R8++               ; its HDF_PST_LO / _HI
                RBRA    _HDFP_LDUP, !Z
                CMP     R5, @R8
                RBRA    _HDFP_PDUP, Z           ; the very same partition
_HDFP_LDUP      MOVE    R6, R8                  ; drop the old disk of this
                ADD     1, R8                   ; drive
                RSUB    HDF_DROP, 1
                MOVE    R0, R8                  ; the handle copy: the device
                MOVE    HDF_FDH, R9             ; for the block I/O
                MOVE    FAT32$FDH_STRUCT_SIZE, R10
                SYSCALL(memcpy, 1)
                MOVE    HDF_FDH, R8
                ADD     FAT32$FDH_FLAGS, R8
                MOVE    0, @R8
                MOVE    HDF_PART, R8            ; partition number and start
                MOVE    R3, @R8                 ; (R3: from HDF_LINK)
                MOVE    HDF_PST_LO, R8
                MOVE    R4, @R8
                MOVE    HDF_PST_HI, R8
                MOVE    R5, @R8
                CMP     R7, 0x0FFF              ; the size, at most what LBA28
                RBRA    _HDFP_L28, !N           ; addresses (128 GB)
                MOVE    0x0FFF, R7
                MOVE    0xFFFF, R1
_HDFP_L28       MOVE    HDF_SECT_LO, R8
                MOVE    R1, @R8
                MOVE    HDF_SECT_HI, R8
                MOVE    R7, @R8
                MOVE    HDF_MAPOK, R8           ; the fast block path
                MOVE    1, @R8
                XOR     R9, R9                  ; no file (HDF_VPART): no
                MOVE    HDF_VPART, R8           ; seek in it
                CMP     0, @R8
                RBRA    _HDFP_SKD, !Z
                MOVE    R0, R8                  ; the Shell reads EOF at once
                MOVE    R2, R9                  ; (the file is under 512 bytes)
                XOR     R10, R10
                SYSCALL(f32_fseek, 1)
                RBRA    _HDFP_SKD, 1

_HDFP_BADPT     MOVE    WRN_HDF_PART, R8
                RBRA    _HDFP_ERR, 1
_HDFP_PDUP      MOVE    WRN_HDF_PDUP, R8
_HDFP_ERR       RSUB    RODATA_STR, 1           ; (texts in the read-only data
                MOVE    R8, R9                  ; device: copy them to RAM)
                MOVE    1, R8
                RBRA    _HDFP_RET, 1

_HDFP_NOROM     MOVE    1, R8
                MOVE    WRN_HDF_NOROM, R8
                RSUB    RODATA_STR, 1           ; (text in the read-only data
                MOVE    R8, R9                  ; device: copy it to RAM)
                MOVE    1, R8
                RBRA    _HDFP_RET, 1
_HDFP_BADSZ     MOVE    1, R8
                MOVE    WRN_HDF_SIZE, R8
                RSUB    RODATA_STR, 1           ; (text in the read-only data
                MOVE    R8, R9                  ; device: copy it to RAM)
                MOVE    1, R8
                RBRA    _HDFP_RET, 1
_HDFP_FATERR    MOVE    1, R8
                MOVE    WRN_HDF_FAT, R8
                RSUB    RODATA_STR, 1           ; (text in the read-only data
                MOVE    R8, R9                  ; device: copy it to RAM)
                MOVE    1, R8

_HDFP_RET       MOVE    HDF_VPART, R1           ; (one load only)
                MOVE    0, @R1
                MOVE    @SP++, R12
                MOVE    @SP++, R11
                MOVE    @SP++, R10
                DECRB
                RET

; HDF_LINK, HDF_PART_GET: in code bank BANK_IDE (moved there in Megamiga 0.7)
HDF_LINK        RSUB    FAR_CALL, 1
                .DW     BANK_IDE, B3_HDF_LINK
HDF_PART_GET    RSUB    FAR_CALL, 1
                .DW     BANK_IDE, B3_HDF_PART_GET
; the virtual RDB of images without one (Megamiga 0.7, see B3_VRDB_DET)
HDF_VRDB_DET    RSUB    FAR_CALL, 1
                .DW     BANK_IDE, B3_VRDB_DET
HDF_VRDB_RD     RSUB    FAR_CALL, 1
                .DW     BANK_IDE, B3_VRDB_RD
HDF_VRDB_WR     RSUB    FAR_CALL, 1
                .DW     BANK_IDE, B3_VRDB_WR
HDF_VRDB_ID     RSUB    FAR_CALL, 1
                .DW     BANK_IDE, B3_VRDB_ID
; the quick HDF of the main page (Megamiga 0.7, see B3_QHDF_PREP)
QHDF_PREP       RSUB    FAR_CALL, 1
                .DW     BANK_IDE, B3_QHDF_PREP
QHDF_HREM       RSUB    FAR_CALL, 1
                .DW     BANK_IDE, B3_QHDF_HREM
HDF_SPACE_OK    RSUB    FAR_CALL, 1
                .DW     BANK_IDE, B3_HDF_SPOK
HDF_SPACE       RSUB    FAR_CALL, 1
                .DW     BANK_IDE, B3_HDF_SPACE

; HDF_GEOM_INIT: state of the direct block I/O for a freshly mapped HDF:
; log2 of the sectors per cluster of its device, extent cache at the start
; Input/Output: none; all registers preserved
HDF_GEOM_INIT   INCRB
                MOVE    HDF_FDH, R0
                MOVE    @R0, R0                 ; device handle
                ADD     FAT32$DEV_SECT_PER_CLUS, R0
                MOVE    @R0, R0                 ; R0: sectors per cluster
                XOR     R1, R1                  ; R1: shift
_HGI_L          CMP     R0, 1
                RBRA    _HGI_D, !N              ; R0 <= 1: done
                AND     0xFFFB, SR
                SHR     1, R0
                ADD     1, R1
                RBRA    _HGI_L, 1
_HGI_D          MOVE    HDF_SPC_SHIFT, R0
                MOVE    R1, @R0
                MOVE    HDF_EXT_IDX, R0
                MOVE    0, @R0
                MOVE    HDF_EXT_CLO, R0
                MOVE    0, @R0
                MOVE    HDF_EXT_CHI, R0
                MOVE    0, @R0
                DECRB
                RET

; HDF_ENG_SETUP: hand drive R8 (the active disk state) to the sector engine of
; the board (ide_engine.vhd), which then serves READ/WRITE SECTORS itself: a
; partition by its first block, a file by an extent map that FAT32$FILE_MAP
; writes straight into window 1 of the board (up to 511 extents). A file with
; more extents stays with the firmware (IDE_STEP). The mode goes last: the
; engine reads the other values when a command arrives.
; Input: R8: drive. Output: none; R8..R12 clobbered. Selects the IDE device.
HDF_ENG_SETUP   INCRB
#if !IDE_ENGINE
                RBRA    _HES_RET, 1             ; (the engine stays off)
#endif
                MOVE    IDE_ENG_U0, R0          ; R0: the unit's registers
                CMP     0, R8
                RBRA    _HES_U, Z
                MOVE    IDE_ENG_U1, R0
_HES_U          MOVE    R8, R7                  ; R7: drive
                RSUB    IDE_SEL, 1
                MOVE    IDE_ENG_OFF, @R0        ; off while it changes
                MOVE    IDE_ENG_SKIP0, R1       ; Megamiga 0.7: the virtual RDB
                ADD     R7, R1                  ; in front of the image; a board
                MOVE    HDF_VRDB, R2            ; without the register (it reads
                MOVE    @R2, @R1                ; 0) leaves such a drive to the
                CMP     @R2, @R1                ; firmware
                RBRA    _HES_RET, !Z
                MOVE    HDF_SECT_LO, R1         ; sectors
                MOVE    R0, R2
                ADD     IDE_ENG_SECT, R2
                MOVE    @R1++, @R2++            ; (HDF_SECT_HI follows)
                MOVE    @R1, @R2
                MOVE    HDF_PART, R1
                CMP     0, @R1
                RBRA    _HES_FILE, Z

                ; a partition: base = its first block
                MOVE    HDF_PST_LO, R1
                MOVE    R0, R2
                ADD     IDE_ENG_BASE, R2
                MOVE    @R1, @R2++
                MOVE    HDF_PST_HI, R1
                MOVE    @R1, @R2++
                MOVE    0, @R2                  ; shift
                MOVE    IDE_ENG_PART, R3
                RBRA    _HES_ON, 1

                ; a file: the extent map into window 1
_HES_FILE       MOVE    M2M$RAMROM_4KWIN, R1
                MOVE    1, @R1
                MOVE    IDE_ENG_MAP, R9
                CMP     0, R7
                RBRA    _HES_M0, Z
                ADD     IDE_ENG_MAPW, R9
                ; Megamiga 0.7: HDF_PREP has just mapped the file into HDF_MAP;
                ; if it fit (up to 64 extents), the engine gets a copy instead
                ; of a second walk of the whole cluster chain (the slow part of
                ; mounting a large HDF). The map format does not depend on the
                ; size of the buffer.
_HES_M0         MOVE    HDF_MAPOK, R4
                CMP     1, @R4
                RBRA    _HES_WALK, !Z
                MOVE    HDF_MAP, R4
                MOVE    HDF_MAP_WORDS, R5
_HES_CP         MOVE    @R4++, @R9++
                SUB     1, R5
                RBRA    _HES_CP, !Z
                XOR     R4, R4                  ; R4: result (OK)
                RBRA    _HES_MAPD, 1
_HES_WALK       MOVE    HDF_FDH, R8
                MOVE    IDE_ENG_MAPW, R10
                RSUB    FAT32$FILE_MAP, 1       ; (not in the M2M syscall table)
                MOVE    R9, R4                  ; R4: result
_HES_MAPD       RSUB    IDE_SEL, 1
                CMP     0, R4
                RBRA    _HES_RET, !Z            ; too many extents: firmware
                ; base = DEV_CLUSTER - (2 << shift): the block of cluster 0
                MOVE    HDF_SPC_SHIFT, R1
                MOVE    @R1, R1                 ; R1: shift
                MOVE    2, R4
                AND     0xFFFD, SR              ; (X = 0: shift in zeros)
                SHL     R1, R4                  ; R4: 2 << shift
                MOVE    HDF_FDH, R2
                MOVE    @R2, R2                 ; (FAT32$FDH_DEVICE = 0)
                ADD     FAT32$DEV_CLUSTER_LO, R2
                MOVE    @R2++, R5               ; R6:R5: DEV_CLUSTER
                MOVE    @R2, R6                 ; (FAT32$DEV_CLUSTER_HI)
                SUB     R4, R5
                SUBC    0, R6
                MOVE    R0, R2
                ADD     IDE_ENG_BASE, R2
                MOVE    R5, @R2++
                MOVE    R6, @R2++
                MOVE    R1, @R2                 ; shift
                MOVE    IDE_ENG_FILE, R3

_HES_ON         MOVE    HDF_DSLOT, R1           ; bit 2: the card of the drive
                ADD     R7, R1                  ; (M2M-UPSTREAM sd-host: the
                CMP     0, @R1                  ; engine port's controller)
                RBRA    _HES_ON2, Z
                OR      IDE_ENG_SLOT1, R3
_HES_ON2        MOVE    R3, @R0                 ; mode last
_HES_RET        DECRB
                RET

; IDE_RESET_AMIGA: a short reset pulse for the core (M2M$CSR reset bit)
; Input/Output: none; all registers preserved
IDE_RESET_AMIGA INCRB
                MOVE    M2M$CSR, R0
                OR      M2M$CSR_RESET, @R0
                MOVE    IDE_RESET_LOOPS, R1
_IRA_W          SUB     1, R1
                RBRA    _IRA_W, !Z
                AND     M2M$CSR_UN_RESET, @R0
                DECRB
                RET

; IDE_COMMIT: hand a new status to the board and wait for the acknowledge
;
; The board applies the commit only while BSY is set (so a late commit after
; an Amiga reset can never raise DRQ), but acknowledges every commit.
;
; Input:  R8: status, R9: error register, R10: flags (IDE_FL_*: bit 0 the data
;         phase is CPU -> buffer, bit 2 raise INTRQ, bit 3 the buffer -> CPU block
;         ends the command); the IDE device must be selected
;
; INTRQ (Megamiga 0.7, Gayle mode; the board ignores it as RIPPLE) follows ide.cpp
; of MiSTer, the drive behind the Minimig Gayle that the A600/A1200 scsi.device
; runs against: every commit that ends BSY raises it - a completed command, an error, each
; buffer -> CPU block, each further CPU -> buffer block - except the first DRQ of a
; WRITE. The last block of a READ and IDENTIFY carries IDE_FL_END: the drive is ready
; as soon as the CPU has its 256th word (ATA_STATUS_END in ide.cpp), so those commands
; end without a commit of their own - one sent then could hit the next command.
; Output: none; all registers preserved
IDE_COMMIT      INCRB
                MOVE    IDE_NSTAT, R0
                MOVE    R8, @R0
                MOVE    IDE_NERR, R0
                MOVE    R9, @R0
                MOVE    IDE_NFLAGS, R0
                MOVE    R10, @R0
                MOVE    IDE_COMMIT_REG, R0
                MOVE    1, @R0
                MOVE    IDE_EVENTS, R0
                MOVE    IDE_LAST_EV, R1
                MOVE    IDE_ACK_LOOPS, R2
_IDC_W          MOVE    @R0, R3
                XOR     @R1, R3
                AND     IDE_EV_ACK, R3
                RBRA    _IDC_ACK, !Z
                SUB     1, R2
                RBRA    _IDC_W, !Z
                MOVE    @R0, @R1                ; no acknowledge (cannot
                RBRA    _IDC_RET, 1             ; happen): resync everything
_IDC_ACK        XOR     IDE_EV_ACK, @R1
_IDC_RET        DECRB
                RET

; IDE_STEP: one time slice of the ATA command server, called from
; HANDLE_CORE_IO in every poll. Changes the RAMROM selection.
; Input/Output: none; R8..R12 are clobbered
IDE_STEP        INCRB
                RSUB    IDE_SEL, 1
                MOVE    HDF_UNITS, R0
                CMP     0, @R0
                RBRA    _IDS_VALID, !Z

                ; no disk: keep the event shadow in sync, nothing to serve
_IDS_SYNC       MOVE    IDE_EVENTS, R0
                MOVE    IDE_LAST_EV, R1
                MOVE    @R0, @R1
                MOVE    IDE_STATE, R1
                MOVE    IDE_ST_IDLE, @R1
                RBRA    _IDS_RET, 1

                ; SD guards (see HANDLE_CORE_IO): a swapped card makes the
                ; retained handle useless - the drive vanishes, never write
                ; to a card the file was not opened on. M2M-UPSTREAM sd-host
                ; (two slots): per drive, by the generation of its card.
_IDS_VALID      XOR     R2, R2                  ; R2: drive
                MOVE    1, R3                   ; R3: its bit
_IDS_GL         MOVE    HDF_UNITS, R0
                MOVE    @R0, R0
                AND     R3, R0
                RBRA    _IDS_GN, Z              ; not mounted
                MOVE    HDF_DSLOT, R0
                ADD     R2, R0
                MOVE    @R0, R8
                RSUB    SDC$GEN, 1
                MOVE    HDF_DGEN, R0
                ADD     R2, R0
                CMP     @R0, R8
                RBRA    _IDS_GN, Z
                MOVE    R3, R8                  ; its card changed: it goes
                RSUB    HDF_DROP, 1
_IDS_GN         ADD     1, R2
                ADD     R3, R3
                CMP     2, R2
                RBRA    _IDS_GL, !Z
                MOVE    HDF_UNITS, R0
                CMP     0, @R0
                RBRA    _IDS_SYNC, Z            ; no drive left

_IDS_EV         MOVE    IDE_EVENTS, R0
                MOVE    @R0, R1
                MOVE    IDE_LAST_EV, R2
                XOR     @R2, R1                 ; R1: event bits that toggled
                MOVE    IDE_STATE, R3           ; R3: &state

                ; reset (Amiga reset, RESET instruction, SRST): abandon
                ; whatever was going on, the board is idle again
                MOVE    R1, R4
                AND     IDE_EV_RST, R4
                RBRA    _IDS_NORST, Z
                MOVE    @R0, @R2
                MOVE    IDE_ST_IDLE, @R3
                RBRA    _IDS_RET, 1

                ; a new command replaces anything in progress (a host only
                ; writes the command register while BSY is clear)
_IDS_NORST      MOVE    R1, R4
                AND     IDE_EV_CMD, R4
                RBRA    _IDS_NOCMD, Z
                XOR     IDE_EV_CMD, @R2
                MOVE    @R0, R4                 ; a buffer event of the previous
                XOR     @R2, R4                 ; command (its last block ended
                AND     IDE_EV_BUF, R4          ; it, IDE_FL_END) is done with
                XOR     R4, @R2
                RSUB    IDE_CMD_START, 1
                RBRA    _IDS_RET, 1

_IDS_NOCMD      MOVE    @R3, R4                 ; R4: state
                CMP     IDE_ST_RDPREP, R4
                RBRA    _IDS_RDPREP, Z
                MOVE    R1, R5                  ; everything else waits for
                AND     IDE_EV_BUF, R5          ; the CPU to finish a buffer
                RBRA    _IDS_RET, Z
                XOR     IDE_EV_BUF, @R2
                CMP     IDE_ST_RDWAIT, R4
                RBRA    _IDS_RDDONE, Z
                CMP     IDE_ST_WRWAIT, R4
                RBRA    _IDS_WRDONE, Z
                CMP     IDE_ST_IDWAIT, R4
                RBRA    _IDS_IDLE, Z            ; (IDE_FL_END: already ready)
                RBRA    _IDS_RET, 1             ; stray buffer event

_IDS_RDPREP     RSUB    IDE_READ_SECT, 1        ; next sector into the buffer
                RBRA    _IDS_RET, 1

_IDS_RDDONE     RSUB    IDE_NEXT, 1             ; the CPU has read a sector
                RBRA    _IDS_IDLE, C            ; (IDE_FL_END: already ready)
                MOVE    IDE_ST_RDPREP, @R3
                RBRA    _IDS_RET, 1

_IDS_WRDONE     RSUB    IDE_WRITE_SECT, 1       ; the CPU has written a sector
                RBRA    _IDS_RET, C             ; (error: already reported)
                RSUB    IDE_NEXT, 1
                RBRA    _IDS_FIN, C
                MOVE    IDE_ST_DRQ, R8          ; next sector: DRQ again
                XOR     R9, R9
                MOVE    IDE_FL_WRIRQ, R10
                RSUB    IDE_MFLAGS, 1           ; (MULTIPLE: within a block)
                RSUB    IDE_COMMIT, 1
                RBRA    _IDS_RET, 1

_IDS_FIN        MOVE    IDE_ST_READY, R8        ; WRITE complete
                XOR     R9, R9
                MOVE    IDE_FL_IRQ, R10
                RSUB    IDE_COMMIT, 1
_IDS_IDLE       MOVE    IDE_STATE, R3
                MOVE    IDE_ST_IDLE, @R3

_IDS_RET        DECRB
                RET

; IDE_NEXT: advance to the next sector of a READ/WRITE
; Output: C=1 if that was the last sector, else C=0; all registers preserved
IDE_NEXT        INCRB
                MOVE    IDE_BPOS, R0            ; the position in the block
                ADD     1, @R0                  ; (READ/WRITE MULTIPLE; else
                MOVE    IDE_BSIZE, R1           ; blocks of 1 sector)
                CMP     @R1, @R0
                RBRA    _INX_B, !Z
                MOVE    0, @R0
_INX_B          MOVE    IDE_LBA_HI, R1          ; both addresses first: an ADD
                MOVE    IDE_LBA_LO, R0          ; between ADD and ADDC would
                ADD     1, @R0                  ; eat the carry
                ADDC    0, @R1
                MOVE    IDE_LEFT, R0
                SUB     1, @R0
                RBRA    _INX_DONE, Z
                AND     0xFFFB, SR              ; C=0: more sectors
                DECRB
                RET
_INX_DONE       OR      0x0004, SR              ; C=1: done
                DECRB
                RET

; IDE_MFLAGS: the commit flags R10 of a sector for its place in the block
; (Megamiga 0.7, READ/WRITE MULTIPLE in blocks of IDE_BSIZE sectors; every other
; data command has blocks of 1, which leaves R10 as it is): INTRQ only for the
; first sector of a block, IDE_FL_MORE when the next sector belongs to the same
; block (the board then holds the CPU's data accesses after this sector until
; the next commit - a host moves a block without looking at the status).
; Input/Output: R10: flags; IDE_BPOS and IDE_LEFT describe the sector.
; Other registers preserved.
IDE_MFLAGS      INCRB
                MOVE    IDE_BPOS, R0
                MOVE    @R0, R0                 ; R0: position in the block
                CMP     0, R0
                RBRA    _IMF_1, Z
                AND     IDE_FL_NOIRQ, R10       ; within a block: no INTRQ
_IMF_1          MOVE    IDE_LEFT, R1
                CMP     1, @R1
                RBRA    _IMF_RET, Z             ; the last sector of the command
                ADD     1, R0
                MOVE    IDE_BSIZE, R1
                CMP     @R1, R0
                RBRA    _IMF_RET, Z             ; the last sector of the block
                OR      IDE_FL_MORE, R10
_IMF_RET        DECRB
                RET

; IDE_ERROR: finish the command with ERR set
; Input:  R9: error register value
; Output: none; R8..R10 clobbered
IDE_ERROR       INCRB
                MOVE    IDE_ST_ERROR, R8
                MOVE    IDE_FL_IRQ, R10
                RSUB    IDE_COMMIT, 1
                MOVE    IDE_STATE, R0
                MOVE    IDE_ST_IDLE, @R0
                DECRB
                RET

; IDE_CMD_START: a command was written to the board
; Output: none; R8..R12 clobbered
IDE_CMD_START   INCRB
                MOVE    IDE_TF_DEVH, R8         ; DEV (bit 4) picks the drive:
                MOVE    @R8, R8                 ; the board only takes commands
                AND     IDE_DEVH_DEV, R8        ; for a present one
                AND     0xFFFB, SR
                SHR     4, R8
                RSUB    HDF_SELECT, 1
                RSUB    IDE_SEL, 1
                MOVE    IDE_TF_CMD, R0
                MOVE    @R0, R0                 ; R0: command
                AND     0x00FF, R0

                CMP     IDE_CMD_IDENTIFY, R0
                RBRA    _ICS_ID, Z
                CMP     IDE_CMD_READ, R0
                RBRA    _ICS_RD, Z
                CMP     IDE_CMD_READ_NR, R0
                RBRA    _ICS_RD, Z
                CMP     IDE_CMD_WRITE, R0
                RBRA    _ICS_WR, Z
                CMP     IDE_CMD_WRITE_NR, R0
                RBRA    _ICS_WR, Z
                CMP     IDE_CMD_READ_MULT, R0   ; Megamiga 0.7: READ/WRITE
                RBRA    _ICS_RDM, Z             ; MULTIPLE, SET MULTIPLE MODE
                CMP     IDE_CMD_WRITE_MULT, R0
                RBRA    _ICS_WRM, Z
                CMP     IDE_CMD_SET_MULT, R0
                RBRA    _ICS_SETM, Z

                CMP     IDE_CMD_INITDP, R0      ; the CHS geometry for the
                RBRA    _ICS_OKN, !Z            ; Gayle's scsi.device: sectors
                MOVE    IDE_TF_COUNT, R1        ; per track = count (0 = 256),
                MOVE    @R1, R1                 ; heads = DEVH 3..0 + 1
                AND     0x00FF, R1
                RBRA    _ICS_IDP1, !Z
                MOVE    256, R1
_ICS_IDP1       MOVE    HDF_SPT, R2
                MOVE    R1, @R2
                MOVE    IDE_TF_DEVH, R1
                MOVE    @R1, R1
                AND     0x000F, R1
                ADD     1, R1
                MOVE    HDF_HEADS, R2
                MOVE    R1, @R2
                MOVE    HDF_ACTIVE, R8          ; the board's copy (before the
                MOVE    @R8, R8                 ; commit: the engine converts
                RSUB    IDE_GEOM_REG, 1         ; the next CHS command with it)

                ; commands that need no data and nothing from us: OK
_ICS_OKN        MOVE    IDE_CMD_OK_TAB, R1
_ICS_OKL        CMP     0xFFFF, @R1
                RBRA    _ICS_ABRT, Z
                CMP     @R1++, R0
                RBRA    _ICS_OKL, !Z
_ICS_OKD        MOVE    IDE_ST_READY, R8
                XOR     R9, R9
                MOVE    IDE_FL_IRQ, R10
                RSUB    IDE_COMMIT, 1
                MOVE    IDE_STATE, R1
                MOVE    IDE_ST_IDLE, @R1
                RBRA    _ICS_RET, 1

                ; SET MULTIPLE MODE: 0 (off) or a power of two up to
                ; IDE_MULT_MAX, else aborted (ATA); the board gets it first
_ICS_SETM       MOVE    IDE_TF_COUNT, R1
                MOVE    @R1, R1
                AND     0x00FF, R1              ; R1: count
                RBRA    _ICS_SM1, Z
                MOVE    R1, R2
                AND     IDE_MULT_BAD, R2        ; 32 or more
                RBRA    _ICS_ABRT, !Z
                MOVE    R1, R2
                SUB     1, R2
                AND     R1, R2                  ; not a power of two (17..31
                RBRA    _ICS_ABRT, !Z           ; are none either)
_ICS_SM1        MOVE    HDF_MULT, R2
                MOVE    R1, @R2
                MOVE    HDF_ACTIVE, R8
                MOVE    @R8, R8
                MOVE    R1, R9
                RSUB    IDE_MULT_REG, 1
                RBRA    _ICS_OKD, 1

_ICS_ABRT       MOVE    IDE_ERR_ABRT, R9        ; everything else: aborted
                RSUB    IDE_ERROR, 1
                RBRA    _ICS_RET, 1

_ICS_ID         RSUB    IDE_IDENTIFY, 1
                MOVE    IDE_ST_DRQ, R8
                XOR     R9, R9
                MOVE    IDE_FL_ENDIRQ, R10
                RSUB    IDE_COMMIT, 1
                MOVE    IDE_STATE, R1
                MOVE    IDE_ST_IDWAIT, @R1
                RBRA    _ICS_RET, 1

                ; READ/WRITE MULTIPLE: as READ/WRITE SECTORS in blocks of
                ; the drive's multiple count (none: aborted). The sector engine
                ; serves them itself unless they come here (CHS, engine off).
_ICS_RDM        RSUB    IDE_MBLOCK, 1
                RBRA    _ICS_ABRT, C
                RBRA    _ICS_RD2, 1
_ICS_RD         RSUB    IDE_SBLOCK, 1
_ICS_RD2        RSUB    IDE_TF_LBA, 1           ; LBA + count, range-checked
                RBRA    _ICS_RET, C             ; (error: already reported)
                MOVE    IDE_STATE, R1           ; the first sector is read in
                MOVE    IDE_ST_RDPREP, @R1      ; the next time slice
                RBRA    _ICS_RET, 1

_ICS_WRM        RSUB    IDE_MBLOCK, 1
                RBRA    _ICS_ABRT, C
                RBRA    _ICS_WR2, 1
_ICS_WR         RSUB    IDE_SBLOCK, 1
_ICS_WR2        RSUB    IDE_TF_LBA, 1
                RBRA    _ICS_RET, C
                MOVE    IDE_ST_DRQ, R8          ; DRQ: the CPU fills the buffer
                XOR     R9, R9
                MOVE    IDE_FL_WRITE, R10       ; (the first block: no INTRQ)
                RSUB    IDE_MFLAGS, 1
                RSUB    IDE_COMMIT, 1
                MOVE    IDE_STATE, R1
                MOVE    IDE_ST_WRWAIT, @R1

_ICS_RET        DECRB
                RET

; IDE_SBLOCK: blocks of 1 sector (READ/WRITE SECTORS)
; IDE_MBLOCK: blocks of the drive's multiple count (READ/WRITE MULTIPLE);
;             C=1: the drive has none (the command is to be aborted)
; Registers preserved.
IDE_SBLOCK      INCRB
                MOVE    1, R1
                RBRA    _ISB_SET, 1
IDE_MBLOCK      INCRB
                MOVE    HDF_MULT, R1
                MOVE    @R1, R1
                CMP     0, R1
                RBRA    _ISB_SET, !Z
                OR      0x0004, SR              ; C=1: no multiple count
                DECRB
                RET
_ISB_SET        MOVE    IDE_BSIZE, R0
                MOVE    R1, @R0
                MOVE    IDE_BPOS, R0
                MOVE    0, @R0
                AND     0xFFFB, SR              ; C=0
                DECRB
                RET

; IDE_TF_LBA: LBA28 and sector count of a READ/WRITE from the task file
;
; CHS addressing (Megamiga 0.7: the scsi.device of Kickstart 3.1 and older uses
; it on the Gayle; lide.device always uses LBA) is converted with the geometry
; of the drive, HDF_HEADS / HDF_SPT, like ide.cpp of MiSTer:
; LBA = (cylinder x heads + head) x sectors per track + sector - 1.
;
; Output: C=0: IDE_LBA_LO/HI and IDE_LEFT are set up
;         C=1: the command was finished with an error (out of range or an
;              invalid CHS address: IDNF)
;         R8..R12 clobbered
IDE_TF_LBA      INCRB
                MOVE    IDE_TF_DEVH, R0
                MOVE    @R0, R0                 ; R0: device/head
                MOVE    R0, R1
                AND     IDE_DEVH_LBA, R1
                RBRA    _ITL_CHS, Z             ; CHS: convert

                MOVE    IDE_TF_LBA1, R1         ; LBA 15:0
                MOVE    @R1, R1
                AND     0x00FF, R1
                AND     0xFFFD, SR
                SHL     8, R1
                MOVE    IDE_TF_LBA0, R2
                MOVE    @R2, R2
                AND     0x00FF, R2
                OR      R2, R1                  ; R1: LBA low word
                MOVE    R0, R2                  ; LBA 27:16
                AND     0x000F, R2
                AND     0xFFFD, SR
                SHL     8, R2
                MOVE    IDE_TF_LBA2, R3
                MOVE    @R3, R3
                AND     0x00FF, R3
                OR      R3, R2                  ; R2: LBA high word
_ITL_COUNT      MOVE    IDE_TF_COUNT, R3
                MOVE    @R3, R3
                AND     0x00FF, R3              ; R3: count, 0 means 256
                RBRA    _ITL_CNT, !Z
                MOVE    256, R3

                ; range: LBA + count must not exceed the number of sectors
_ITL_CNT        MOVE    R1, R4
                MOVE    R2, R5
                ADD     R3, R4
                ADDC    0, R5                   ; R5/R4: end (exclusive)
                MOVE    HDF_SECT_HI, R6
                MOVE    @R6, R6
                CMP     R5, R6                  ; end hi > sectors hi?
                RBRA    _ITL_IDNF, N
                RBRA    _ITL_OK, !Z             ; end hi < sectors hi: fits
                MOVE    HDF_SECT_LO, R6
                MOVE    @R6, R6
                CMP     R4, R6                  ; end lo > sectors lo?
                RBRA    _ITL_IDNF, N

_ITL_OK         MOVE    IDE_LBA_LO, R6
                MOVE    R1, @R6
                MOVE    IDE_LBA_HI, R6
                MOVE    R2, @R6
                MOVE    IDE_LEFT, R6
                MOVE    R3, @R6
                AND     0xFFFB, SR              ; C=0
                RBRA    _ITL_RET, 1

                ; CHS: cylinder = LBA2:LBA1, head = DEVH 3..0, sector = LBA0
_ITL_CHS        MOVE    R0, R4                  ; R4: head, below the heads
                AND     0x000F, R4
                MOVE    HDF_HEADS, R5
                MOVE    @R5, R5                 ; R5: heads
                CMP     R5, R4                  ; heads > head?
                RBRA    _ITL_IDNF, !N
                MOVE    IDE_TF_LBA0, R6         ; R6: sector, 1..spt
                MOVE    @R6, R6
                AND     0x00FF, R6
                RBRA    _ITL_IDNF, Z
                MOVE    HDF_SPT, R7
                MOVE    @R7, R7                 ; R7: sectors per track
                CMP     R6, R7                  ; sector > spt?
                RBRA    _ITL_IDNF, N
                MOVE    IDE_TF_LBA2, R8         ; R8: cylinder
                MOVE    @R8, R8
                AND     0x00FF, R8
                AND     0xFFFD, SR
                SHL     8, R8
                MOVE    IDE_TF_LBA1, R9
                MOVE    @R9, R9
                AND     0x00FF, R9
                OR      R9, R8
                MOVE    R5, R9
                SYSCALL(mulu, 1)                ; R11|R10 = cylinder x heads
                ADD     R4, R10                 ; + head
                ADDC    0, R11
                MOVE    R11, R2                 ; (the high word, R2)
                MOVE    R10, R8                 ; x sectors per track: the
                MOVE    R7, R9                  ; low word ...
                SYSCALL(mulu, 1)
                MOVE    R10, R1                 ; R1: LBA low word
                MOVE    R11, R3                 ; R3: its carry into the high
                MOVE    R2, R8                  ; ... and the high word (the
                MOVE    R7, R9                  ; product fits 32 bits: at most
                SYSCALL(mulu, 1)                ; 2^20 x 256)
                MOVE    R10, R2
                ADD     R3, R2                  ; R2: LBA high word
                SUB     1, R6                   ; + sector - 1
                ADD     R6, R1
                ADDC    0, R2
                RBRA    _ITL_COUNT, 1

_ITL_IDNF       MOVE    IDE_ERR_IDNF, R9
_ITL_ERR        RSUB    IDE_ERROR, 1
                OR      0x0004, SR              ; C=1
_ITL_RET        DECRB
                RET

; IDE_SEEK: seek the HDF to the sector IDE_LBA_LO/HI
; Output: R9: 0=OK, else FAT32 error; R8 = HDF_FDH; R10..R12 clobbered
IDE_SEEK        INCRB
                MOVE    IDE_LBA_LO, R0
                MOVE    @R0, R0
                MOVE    IDE_LBA_HI, R1
                MOVE    @R1, R1
                MOVE    HDF_VRDB, R2            ; Megamiga 0.7: behind the
                SUB     @R2, R0                 ; virtual RDB
                SUBC    0, R1
                MOVE    R0, R9                  ; byte offset = LBA << 9
                AND     0xFFFD, SR
                SHL     9, R9
                MOVE    R1, R10
                AND     0xFFFD, SR
                SHL     9, R10
                AND     0xFFFB, SR
                SHR     7, R0
                OR      R0, R10
                MOVE    HDF_FDH, R8
                MOVE    HDF_MAP, R11
                MOVE    HDF_MAPOK, R0
                CMP     1, @R0
                RBRA    _ISK_M, Z
                SYSCALL(f32_fseek, 1)
                RBRA    _ISK_RET, 1
_ISK_M          RSUB    FAT32$FILE_SEEK_MAP, 1
_ISK_RET        DECRB
                RET

; IDE_READ_SECT: read sector IDE_LBA into the buffer of the board and raise DRQ
; Output: none; R8..R12 clobbered
IDE_READ_SECT   INCRB
                RSUB    HDF_VRDB_RD, 1          ; Megamiga 0.7: a block of the
                RBRA    _IRS_DONE, C            ; virtual RDB
                MOVE    HDF_MAPOK, R0           ; extent map: direct block I/O
                CMP     1, @R0
                RBRA    _IRS_SLOW, !Z
                RSUB    IDE_READ_FAST, 1
                RBRA    _IRS_ERR, C
                RBRA    _IRS_DONE, 1
_IRS_SLOW       RSUB    IDE_SEEK, 1
                CMP     0, R9
                RBRA    _IRS_ERR, !Z
                RSUB    IDE_SEL, 1
                MOVE    IDE_DATA, R0            ; R0: buffer pointer
                MOVE    256, R1                 ; R1: words
                MOVE    HDF_FDH, R2
_IRS_L          MOVE    R2, R8                  ; high byte = byte 2i
                SYSCALL(f32_fread, 1)
                CMP     0, R10
                RBRA    _IRS_ERR, !Z
                MOVE    R9, R3
                AND     0xFFFD, SR
                SHL     8, R3
                MOVE    R2, R8                  ; low byte = byte 2i + 1
                SYSCALL(f32_fread, 1)
                CMP     0, R10
                RBRA    _IRS_ERR, !Z
                OR      R9, R3
                MOVE    R3, @R0++
                SUB     1, R1
                RBRA    _IRS_L, !Z

_IRS_DONE       MOVE    IDE_ST_DRQ, R8          ; the CPU may read now
                XOR     R9, R9
                MOVE    IDE_FL_IRQ, R10
                MOVE    IDE_LEFT, R0            ; the last sector ends the command
                CMP     1, @R0
                RBRA    _IRS_COMMIT, !Z
                MOVE    IDE_FL_ENDIRQ, R10
_IRS_COMMIT     RSUB    IDE_MFLAGS, 1           ; (MULTIPLE: within a block)
                RSUB    IDE_COMMIT, 1
                MOVE    IDE_STATE, R0
                MOVE    IDE_ST_RDWAIT, @R0
                RBRA    _IRS_RET, 1

_IRS_ERR        RSUB    IDE_SEL, 1
                MOVE    IDE_ERR_UNC, R9
                RSUB    IDE_ERROR, 1
_IRS_RET        DECRB
                RET

; IDE_WRITE_SECT: write the buffer the CPU filled to sector IDE_LBA
; Output: C=0: OK; C=1: failed, the command was finished with an error;
;         R8..R12 clobbered
IDE_WRITE_SECT  INCRB
                RSUB    HDF_VRDB_WR, 1          ; Megamiga 0.7: the virtual RDB
                RBRA    _IWS_OK, C              ; is not written
                MOVE    HDF_MAPOK, R0           ; extent map: direct block I/O
                CMP     1, @R0
                RBRA    _IWS_SLOW, !Z
                RSUB    IDE_WRITE_FAST, 1
                RBRA    _IWS_ERR, C
                RBRA    _IWS_OK, 1
_IWS_SLOW       RSUB    IDE_SEEK, 1
                CMP     0, R9
                RBRA    _IWS_ERR, !Z
                RSUB    IDE_SEL, 1
                MOVE    IDE_DATA, R0            ; R0: buffer pointer
                MOVE    256, R1                 ; R1: words
                MOVE    HDF_FDH, R2
_IWS_L          MOVE    @R0++, R3
                MOVE    R3, R9                  ; byte 2i = high byte
                AND     0xFFFB, SR
                SHR     8, R9
                MOVE    R2, R8
                SYSCALL(f32_fwrite, 1)
                CMP     0, R9
                RBRA    _IWS_ERR, !Z
                MOVE    R3, R9                  ; byte 2i + 1 = low byte
                AND     0x00FF, R9
                MOVE    R2, R8
                SYSCALL(f32_fwrite, 1)
                CMP     0, R9
                RBRA    _IWS_ERR, !Z
                SUB     1, R1
                RBRA    _IWS_L, !Z

                MOVE    R2, R8                  ; persist the sector NOW (the
                SYSCALL(f32_fflush, 1)          ; one SD sector buffer is
                CMP     0, R9                   ; shared, see FLUSH_ADF_STEP)
                RBRA    _IWS_ERR, !Z
_IWS_OK         RSUB    IDE_SEL, 1
                AND     0xFFFB, SR              ; C=0
                RBRA    _IWS_RET, 1

_IWS_ERR        RSUB    IDE_SEL, 1
                MOVE    IDE_ERR_UNC, R9
                RSUB    IDE_ERROR, 1
                OR      0x0004, SR              ; C=1
_IWS_RET        DECRB
                RET

; ----------------------------------------------------------------------------
; Direct block I/O (used whenever the extent map describes the whole file)
;
; The FAT32 byte API costs a library call per byte plus, for a write, a read of
; the sector before it is overwritten. With the extent map, the SD block of an
; HDF sector is a lookup without any medium access, so a sector is ONE block
; read or write, and its 512 bytes are copied directly between the buffer of
; the SD controller and the buffer of the IDE board.
;
; The SD controller has ONE 512-byte buffer for every SD user. FAT32 handles
; track it by the address of the handle that filled it (FAT32$DEV_BUFFERED_FDH)
; and flush it on an owner change. Before using it directly, _F32_RELEASE_BUF
; therefore flushes a dirty owner and marks the buffer as owned by nobody, so
; every handle re-reads its sector on its next access.
; ----------------------------------------------------------------------------

; IDE_SHR32 / IDE_SHL32: R9:R8 (hi:lo) shifted right/left by R10 bits (0..15)
; Output: R8/R9; all other registers preserved
IDE_SHR32       INCRB
                MOVE    R10, R0
                RBRA    _IS3R_RET, Z
_IS3R_L         MOVE    R9, R1                  ; bit 0 of hi -> bit 15 of lo
                AND     0x0001, R1
                AND     0xFFFD, SR
                SHL     15, R1
                AND     0xFFFB, SR
                SHR     1, R8
                OR      R1, R8
                AND     0xFFFB, SR
                SHR     1, R9
                SUB     1, R0
                RBRA    _IS3R_L, !Z
_IS3R_RET       DECRB
                RET

IDE_SHL32       INCRB
                MOVE    R10, R0
                RBRA    _IS3L_RET, Z
_IS3L_L         MOVE    R8, R1                  ; bit 15 of lo -> bit 0 of hi
                AND     0xFFFB, SR
                SHR     15, R1
                AND     0xFFFD, SR
                SHL     1, R9
                OR      R1, R9
                AND     0xFFFD, SR
                SHL     1, R8
                SUB     1, R0
                RBRA    _IS3L_L, !Z
_IS3L_RET       DECRB
                RET

; IDE_LBA2BLK: the SD block of the HDF sector IDE_LBA_LO/HI
;
; cluster index ci = LBA >> HDF_SPC_SHIFT, sector in cluster = the rest; the
; extent holding ci is searched from the one found last time (HDF_EXT_IDX,
; HDF_EXT_CLO/HI = the cluster index the extent starts at), so sequential access
; costs one comparison. block = DEV_CLUSTER + ((cluster - 2) << shift) + sector.
;
; Output: C=0: R9:R8 = SD block; C=1: not in the map (a damaged map)
;         R10..R12 clobbered
IDE_LBA2BLK     INCRB
                MOVE    IDE_LBA_LO, R8
                MOVE    @R8, R8
                MOVE    IDE_LBA_HI, R9
                MOVE    @R9, R9
                MOVE    HDF_VRDB, R0            ; Megamiga 0.7: behind the
                SUB     @R0, R8                 ; virtual RDB
                SUBC    0, R9
                MOVE    HDF_PART, R0            ; a partition of the card: the
                CMP     0, @R0                  ; block is its first block plus
                RBRA    _IL2B_FILE, Z           ; the sector (the IDE server
                MOVE    HDF_PST_LO, R0          ; checked the sector against the
                ADD     @R0, R8                 ; size already)
                MOVE    HDF_PST_HI, R0
                ADDC    @R0, R9
                AND     0xFFFB, SR              ; C=0
                RBRA    _IL2B_RET, 1
_IL2B_FILE
                MOVE    HDF_SPC_SHIFT, R2
                MOVE    @R2, R2                 ; R2: shift
                MOVE    1, R3                   ; R3: sector in cluster =
                AND     0xFFFD, SR              ; LBA & (2^shift - 1)
                SHL     R2, R3
                SUB     1, R3
                AND     R8, R3
                MOVE    R2, R10
                RSUB    IDE_SHR32, 1
                MOVE    R8, R4                  ; R5:R4: cluster index ci
                MOVE    R9, R5

                MOVE    HDF_EXT_IDX, R7         ; start at the cached extent if
                MOVE    @R7, R7                 ; ci is not in front of it
                MOVE    HDF_EXT_CLO, R0
                MOVE    @R0, R0                 ; R1:R0: cluster index at which
                MOVE    HDF_EXT_CHI, R1         ; extent R7 starts
                MOVE    @R1, R1
                CMP     R1, R5                  ; cached start hi > ci hi?
                RBRA    _IL2B_REW, N
                RBRA    _IL2B_GO, !Z
                CMP     R0, R4                  ; cached start lo > ci lo?
                RBRA    _IL2B_GO, !N
_IL2B_REW       XOR     R7, R7                  ; from the first extent
                XOR     R0, R0
                XOR     R1, R1

_IL2B_GO        MOVE    R7, R6                  ; R6: &extent R7
                AND     0xFFFD, SR
                SHL     2, R6
                ADD     HDF_MAP, R6
                ADD     1, R6
_IL2B_L         MOVE    HDF_MAP, R8             ; past the last extent?
                CMP     @R8, R7
                RBRA    _IL2B_NF, Z
                MOVE    R4, R8                  ; R9:R8: offset = ci - start
                MOVE    R5, R9
                SUB     R0, R8
                SUBC    R1, R9
                MOVE    R6, R10
                ADD     2, R10
                MOVE    @R10++, R11             ; R11: extent length lo
                MOVE    @R10, R10               ; R10: extent length hi
                CMP     R9, R10                 ; offset hi > length hi?
                RBRA    _IL2B_NX, N
                RBRA    _IL2B_FOUND, !Z         ; offset hi < length hi
                CMP     R11, R8                 ; length lo > offset lo?
                RBRA    _IL2B_FOUND, N
_IL2B_NX        ADD     R11, R0                 ; next extent
                ADDC    R10, R1
                ADD     1, R7
                ADD     4, R6
                RBRA    _IL2B_L, 1

_IL2B_FOUND     MOVE    HDF_EXT_IDX, R10        ; cache the extent
                MOVE    R7, @R10
                MOVE    HDF_EXT_CLO, R10
                MOVE    R0, @R10
                MOVE    HDF_EXT_CHI, R10
                MOVE    R1, @R10
                MOVE    @R6++, R11              ; cluster = start + offset
                MOVE    @R6, R12
                ADD     R11, R8
                ADDC    R12, R9
                SUB     2, R8                   ; (cluster - 2) << shift
                SUBC    0, R9
                MOVE    R2, R10
                RSUB    IDE_SHL32, 1
                MOVE    HDF_FDH, R10            ; + start of the cluster area
                MOVE    @R10, R10               ; (FAT32$FDH_DEVICE = 0)
                ADD     FAT32$DEV_CLUSTER_LO, R10
                MOVE    @R10++, R11
                MOVE    @R10, R12               ; (FAT32$DEV_CLUSTER_HI)
                ADD     R11, R8
                ADDC    R12, R9
                ADD     R3, R8                  ; + sector in cluster
                ADDC    0, R9
                AND     0xFFFB, SR              ; C=0
                RBRA    _IL2B_RET, 1

_IL2B_NF        OR      0x0004, SR              ; C=1
_IL2B_RET       DECRB
                RET

; IDE_SD_TAKE: release the SD sector buffer and select the block R9:R8
; Output: C=0: R9:R8 still the block; C=1: the owner could not be flushed
IDE_SD_TAKE     INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    HDF_FDH, R8             ; flush a dirty owner, then the
                RSUB    _F32_RELEASE_BUF, 1     ; buffer belongs to nobody
                MOVE    R9, R2                  ; R2: flush result
                MOVE    HDF_FDH, R8             ; the SD controller of the file
                MOVE    @R8, R8                 ; (M2M-UPSTREAM sd-host: the
                RSUB    SDC$SELDEV, 1           ; buffer is used directly)
                MOVE    R0, R8
                MOVE    R1, R9
                CMP     0, R2                   ; (MOVE changes Z: test last)
                RBRA    _IST_ERR, !Z
                AND     0xFFFB, SR              ; C=0
                RBRA    _IST_RET, 1
_IST_ERR        OR      0x0004, SR              ; C=1
_IST_RET        DECRB
                RET

; IDE_READ_FAST: sector IDE_LBA into the buffer of the IDE board
; Output: C=0: OK; C=1: map or SD error. The IDE device is selected again.
;         R8..R12 clobbered
IDE_READ_FAST   INCRB
                RSUB    IDE_LBA2BLK, 1
                RBRA    _IRF_ERR, C
                RSUB    IDE_SD_TAKE, 1
                RBRA    _IRF_ERR, C
                MOVE    HDF_FDH, R11            ; one block read through the
                MOVE    @R11, R11               ; device of the file
                MOVE    FAT32$DEV_BLOCK_READ, R10
                RSUB    FAT32$CALL_DEV, 1       ; R8: 0 = OK
                CMP     0, R8
                RBRA    _IRF_ERR, !Z
                RSUB    IDE_SEL, 1
                MOVE    IDE_DATA, R0            ; R0: IDE buffer
                MOVE    IO$SD_DATA_POS, R1
                MOVE    IO$SD_DATA, R2
                XOR     R3, R3                  ; R3: byte position
                MOVE    256, R4                 ; R4: words
_IRF_L          MOVE    R3, @R1                 ; byte 2i: high byte
                MOVE    @R2, R5
                AND     0x00FF, R5
                AND     0xFFFD, SR
                SHL     8, R5
                ADD     1, R3
                MOVE    R3, @R1                 ; byte 2i + 1: low byte
                MOVE    @R2, R6
                AND     0x00FF, R6
                OR      R6, R5
                MOVE    R5, @R0++
                ADD     1, R3
                SUB     1, R4
                RBRA    _IRF_L, !Z
                AND     0xFFFB, SR              ; C=0
                RBRA    _IRF_RET, 1
_IRF_ERR        RSUB    IDE_SEL, 1
                OR      0x0004, SR              ; C=1
_IRF_RET        DECRB
                RET

; IDE_WRITE_FAST: the buffer the CPU filled to sector IDE_LBA
; Output: C=0: OK; C=1: map or SD error. The IDE device is selected again.
;         R8..R12 clobbered
IDE_WRITE_FAST  INCRB
                RSUB    IDE_LBA2BLK, 1
                RBRA    _IWF_ERR, C
                RSUB    IDE_SD_TAKE, 1
                RBRA    _IWF_ERR, C
                MOVE    R8, R6                  ; R7:R6: the block
                MOVE    R9, R7
                RSUB    IDE_SEL, 1
                MOVE    IDE_DATA, R0            ; R0: IDE buffer (CPU data)
                MOVE    IO$SD_DATA_POS, R1
                MOVE    IO$SD_DATA, R2
                XOR     R3, R3                  ; R3: byte position
                MOVE    256, R4                 ; R4: words
_IWF_L          MOVE    @R0++, R5
                MOVE    R3, @R1                 ; byte 2i: high byte
                MOVE    R5, R8
                AND     0xFFFB, SR
                SHR     8, R8
                MOVE    R8, @R2
                ADD     1, R3
                MOVE    R3, @R1                 ; byte 2i + 1: low byte
                AND     0x00FF, R5
                MOVE    R5, @R2
                ADD     1, R3
                SUB     1, R4
                RBRA    _IWF_L, !Z
                MOVE    R6, R8                  ; one block write through the
                MOVE    R7, R9                  ; device of the file
                MOVE    HDF_FDH, R11
                MOVE    @R11, R11
                MOVE    FAT32$DEV_BLOCK_WRITE, R10
                RSUB    FAT32$CALL_DEV, 1       ; R8: 0 = OK
                CMP     0, R8
                RBRA    _IWF_ERR, !Z
                RSUB    IDE_SEL, 1
                AND     0xFFFB, SR              ; C=0
                RBRA    _IWF_RET, 1
_IWF_ERR        RSUB    IDE_SEL, 1
                OR      0x0004, SR              ; C=1
_IWF_RET        DECRB
                RET

; IDE_IDENTIFY: build the IDENTIFY DEVICE data in the buffer of the board
;
; Geometry: 16 heads, 63 sectors per track, cylinders = sectors / 1008
; (at most 16383). The words are byte-swapped for the RIPPLE bus.
; Output: none; R8..R12 clobbered
IDE_IDENTIFY    INCRB
                RSUB    IDE_SEL, 1
                MOVE    IDE_DATA, R0            ; all words zero first
                MOVE    256, R1
_IID_Z          MOVE    0, @R0++
                SUB     1, R1
                RBRA    _IID_Z, !Z

                MOVE    IDE_ID_TAB, R0          ; fixed words: index, value
_IID_T          MOVE    @R0++, R1
                CMP     0xFFFF, R1
                RBRA    _IID_S, Z
                MOVE    @R0++, R8
                MOVE    R1, R9
                RSUB    IDE_ID_PUT, 1
                RBRA    _IID_T, 1

_IID_S          MOVE    IDE_ID_SERIAL, R8       ; strings (read-only data
                RSUB    RODATA_STR, 1           ; device: copied to RAM)
                MOVE    IDE_IDW_SERIAL, R9
                MOVE    10, R10
                RSUB    IDE_ID_STR, 1
                MOVE    IDE_ID_FWREV, R8
                RSUB    RODATA_STR, 1
                MOVE    IDE_IDW_FWREV, R9
                MOVE    4, R10
                RSUB    IDE_ID_STR, 1
                MOVE    IDE_ID_MODEL, R8
                RSUB    RODATA_STR, 1
                MOVE    IDE_IDW_MODEL, R9
                MOVE    20, R10
                RSUB    IDE_ID_STR, 1

                MOVE    HDF_SECT_LO, R8         ; capacity in sectors
                MOVE    @R8, R8
                MOVE    IDE_IDW_LBA_LO, R9
                RSUB    IDE_ID_PUT, 1
                MOVE    HDF_SECT_HI, R8
                MOVE    @R8, R8
                MOVE    IDE_IDW_LBA_HI, R9
                RSUB    IDE_ID_PUT, 1

                MOVE    HDF_SECT_LO, R8         ; cylinders = sectors / 1008
                MOVE    @R8, R8
                MOVE    HDF_SECT_HI, R9
                MOVE    @R9, R9
                MOVE    IDE_SECT_PER_CYL, R10
                XOR     R11, R11
                SYSCALL(divu32, 1)
                CMP     0, R9                   ; more than 16 bits or more
                RBRA    _IID_CMAX, !Z           ; than the CHS maximum: clamp
                CMP     R8, IDE_MAX_CYL         ; quotient > maximum?
                RBRA    _IID_CYL, !N
_IID_CMAX       MOVE    IDE_MAX_CYL, R8
_IID_CYL        MOVE    IDE_IDW_CYL, R9
                RSUB    IDE_ID_PUT, 1

                MOVE    HDF_HEADS, R8           ; the current CHS geometry
                MOVE    @R8, R8                 ; (words 54..58)
                MOVE    R8, R2                  ; R2: heads
                MOVE    IDE_IDW_CUR_HDS, R9
                RSUB    IDE_ID_PUT, 1
                MOVE    HDF_SPT, R8
                MOVE    @R8, R8
                MOVE    IDE_IDW_CUR_SPT, R9
                RSUB    IDE_ID_PUT, 1
                MOVE    R2, R9                  ; R3: sectors per cylinder
                SYSCALL(mulu, 1)
                MOVE    R10, R3
                MOVE    HDF_SECT_LO, R8         ; cylinders, at most 65535
                MOVE    @R8, R8
                MOVE    HDF_SECT_HI, R9
                MOVE    @R9, R9
                XOR     R11, R11
                SYSCALL(divu32, 1)
                CMP     0, R9
                RBRA    _IID_CC, Z
                MOVE    0xFFFF, R8
_IID_CC         MOVE    IDE_IDW_CUR_CYL, R9
                RSUB    IDE_ID_PUT, 1
                MOVE    R3, R9                  ; capacity = cylinders x
                SYSCALL(mulu, 1)                ; heads x sectors
                MOVE    R10, R8
                MOVE    IDE_IDW_CUR_CAP, R9
                RSUB    IDE_ID_PUT, 1
                MOVE    R11, R8
                ADD     1, R9
                RSUB    IDE_ID_PUT, 1

                MOVE    HDF_MULT, R8            ; the current multiple count
                MOVE    @R8, R8                 ; (bit 8: valid; 0 = off)
                CMP     0, R8
                RBRA    _IID_M0, Z
                OR      0x0100, R8
_IID_M0         MOVE    IDE_IDW_MULT, R9
                RSUB    IDE_ID_PUT, 1
                RSUB    HDF_VRDB_ID, 1          ; Megamiga 0.7: its geometry

                DECRB
                RET

; IDE_ID_PUT: store one IDENTIFY word, byte-swapped for the bus
; Input: R8: value, R9: word index; device selected. Registers preserved.
IDE_ID_PUT      INCRB
                MOVE    R8, R0
                SWAP    R0, R0
                MOVE    IDE_DATA, R1
                ADD     R9, R1
                MOVE    R0, @R1
                DECRB
                RET

; IDE_ID_STR: store an ATA string (two characters per word, the first in the
; high byte, padded with spaces), byte-swapped for the bus
; Input: R8: string (one character per word, zero-terminated)
;        R9: first word index, R10: number of words. Registers preserved.
IDE_ID_STR      INCRB
                MOVE    R8, R0                  ; R0: string pointer
                MOVE    IDE_DATA, R1
                ADD     R9, R1                  ; R1: destination
                MOVE    R10, R2                 ; R2: words left
_IIS_W          RSUB    _IIS_CH, 1              ; R3: first character
                MOVE    R3, R4
                RSUB    _IIS_CH, 1              ; R3: second character
                AND     0xFFFD, SR              ; bus word = second << 8 |
                SHL     8, R3                   ; first (byte-swapped)
                OR      R4, R3
                MOVE    R3, @R1++
                SUB     1, R2
                RBRA    _IIS_W, !Z
                DECRB
                RET
_IIS_CH         MOVE    @R0, R3                 ; next character, or a space
                CMP     0, R3
                RBRA    _IIS_SP, Z              ; once the string has ended
                ADD     1, R0
                RET
_IIS_SP         MOVE    IDE_ASCII_SPACE, R3
                RET

; ----------------------------------------------------------------------------
; HDMI Filter dispatch
; (ported from C64MEGA65 V6, CORE/m2m-rom/m2m-rom.asm)
; ----------------------------------------------------------------------------

; LOAD_HDMI_FILTER: Read the saved HDMI Filter selection from M2M$CFM_DATA
; and configure ascal accordingly. Called from PREP_START (boot) and
; OSM_SEL_POST (runtime). Eight options, single-select: exactly one of the
; AEXP_OSM_FLT_* bits is set at any time -- OPTM_G_STDSEL in config.vhd
; guarantees a default ("Lanczos") if the saved SD config file is missing
; or empty.
;
; Two execution shapes, both encoded in HDMI_FLT_TABLE rows
; (OSM_bit, ASCAL_MODE_word, H_label, V_label):
;
;   * Native modes (No Filter / Sharp Bilinear / Bicubic) -> write the
;                  matching mode word (NEAREST / SBILINEAR / BICUBIC) to
;                  M2M$ASCAL_MODE. The H/V labels are 0 sentinels: we skip
;                  the polyphase RAM write entirely and let ascal run its
;                  built-in scaler datapath.
;   * Polyphase modes (Smooth / Lanczos / Scanlines / CRT (S-Video) /
;                  CRT (Composite)) -> write POLYPHASE then push the
;                  (H_label, V_label) pair into the ascal polyphase RAM
;                  via M2M$LOAD_POLYPHASE.
;
; This routine assumes ASCAL_USAGE=1 (AUSE_CUSTOM) in config.vhd: ASCAL_INIT
; in M2M/rom/gencfg.asm always clears the M2M$CSR ascal-autosync bit first
; and only re-sets it for AUSE_AUTO, so with AUSE_CUSTOM the M2M$ASCAL_MODE
; register stays firmware-writable. If a future core sets ASCAL_USAGE back
; to 2 (AUSE_AUTO), the mode writes below silently no-op.
;
; Input:  None
; Output: R8 = 0, R9 = 0 on success
LOAD_HDMI_FILTER INCRB
                MOVE    HDMI_FLT_TABLE, R0
                MOVE    8, R1                   ; option count

_LHF_LOOP       MOVE    @R0++, R8               ; R8 = OSM bit for this option
                RSUB    M2M$GET_SETTING, 1
                CMP     1, R9                   ; selected?
                RBRA    _LHF_FOUND, Z           ; yes -> apply this row
                ADD     3, R0                   ; no -> skip MODE, H, V
                SUB     1, R1
                RBRA    _LHF_LOOP, !Z

                ; Defensive fallback: no bit set. Force the Lanczos preset
                ; (polyphase mode + Lanczos2_12 on both axes), matching the
                ; config.vhd OPTM_G_STDSEL default.
                MOVE    M2M$ASCAL_MODE, R2
                MOVE    M2M$ASCAL_POLYPHASE, @R2
                MOVE    LANCZOS2_12,    R8
                MOVE    LANCZOS2_12,    R9
                RSUB    M2M$LOAD_POLYPHASE, 1
                RBRA    _LHF_RET, 1

_LHF_FOUND      MOVE    @R0++, R3               ; R3 = ASCAL_MODE word
                MOVE    M2M$ASCAL_MODE, R2
                MOVE    R3, @R2                 ; write mode register
                MOVE    @R0++, R8               ; R8 = H label (0 = sentinel)
                MOVE    @R0,   R9               ; R9 = V label (0 = sentinel)
                CMP     0, R8                   ; native-mode sentinel?
                RBRA    _LHF_RET, Z             ; yes -> done, no RAM write
                RSUB    M2M$LOAD_POLYPHASE, 1

_LHF_RET        XOR     R8, R8
                XOR     R9, R9
                DECRB
                RET

; Filter table: (OSM_bit, ASCAL_MODE_word, H_label, V_label) per option, in
; OPTM_ITEMS display order. The first three rows use ascal native modes
; (NEAREST / SBILINEAR / BICUBIC); their H and V are 0 sentinels so the
; dispatcher skips the polyphase RAM write for them. The remaining five
; rows all select polyphase (mode 100) and provide real coefficient table
; labels.
;
; See CORE/m2m-rom/video_filters/README.md for per-blob notes and
; CORE/vhdl/config.vhd for the OPTM_ITEMS / OPTM_GROUPS structure.
HDMI_FLT_TABLE  .DW AEXP_OSM_FLT_NO_FILTER,     M2M$ASCAL_NEAREST,   0,                   0
                .DW AEXP_OSM_FLT_SHARP,         M2M$ASCAL_SBILINEAR, 0,                   0
                .DW AEXP_OSM_FLT_BICUBIC,       M2M$ASCAL_BICUBIC,   0,                   0
                .DW AEXP_OSM_FLT_SMOOTH,        M2M$ASCAL_POLYPHASE, GS_SHARPNESS_050,    GS_SHARPNESS_050
                .DW AEXP_OSM_FLT_LANCZOS,       M2M$ASCAL_POLYPHASE, LANCZOS2_12,         LANCZOS2_12
                .DW AEXP_OSM_FLT_SCANLINES,     M2M$ASCAL_POLYPHASE, LANCZOS2_12,         SCAN_BR_110_80

                ; Both CRT rows reuse SCAN_BR_110_80 as the V file (same as
                ; Scanlines mode). CRT_Sim_*_V is a deep ~40% mid-phase
                ; plateau designed to be combined with the MiSTer gamma LUT
                ; + shadow mask; M2M supports neither, so standalone the
                ; plateau crushes bright content into a dark band. The
                ; Composite vs S-Video character lives entirely in the H
                ; file (Composite has heavy horizontal blur, S-Video has
                ; mild softening), so swapping only the V file preserves the
                ; perceptual distinction while restoring near-unity mean
                ; brightness.
                .DW AEXP_OSM_FLT_CRT_SVIDEO,    M2M$ASCAL_POLYPHASE, CRT_SIM_SVIDEO_H,    SCAN_BR_110_80
                .DW AEXP_OSM_FLT_CRT_COMPOSITE, M2M$ASCAL_POLYPHASE, CRT_SIM_COMPOSITE_H, SCAN_BR_110_80

; ----------------------------------------------------------------------------
; LOAD_SCREEN_OFFSETS: screen adjustment (issue #5). Reads the per-Amiga-mode
; table of signed screen offsets (HDMI crop, analog overscan, analog pan) from
; /amiga/aexp_screen.cfg into RAM (SCR_TABLE). It does NOT push anything
; itself; DETECT_SCREEN_MODE (called from HANDLE_CORE_IO) watches the
; ascal-measured geometry + interlace flag, picks the matching row, and pushes
; it into the CFD gp_reg: HDMI crop to words 4..7 (ascal input crop
; himin/himax/vimin/vimax), analog overscan to words 0..3 (soft-blank) and
; analog pan to words 8..9 (analog_positioner sync phase), all M2M-UPSTREAM.
; On a missing/invalid file the table is zeroed (all 0 = no adjustment).
; Loading (re)arms the detector so the row of the current mode is re-pushed.
; Called from PREP_START (boot, before the core un-resets) and from
; OSM_SEL_POST on the "Reload screen cfg" item (live, no core reset / no
; re-synth -- the point of the SD-file tuning loop).
;
; File /amiga/aexp_screen.cfg (big-endian 16-bit words): "A","X", ver, count=4,
; then 4 rows in the fixed order lores-progressive, hires-progressive,
; lores-interlaced, hires-interlaced. A v4 row has 10 signed words:
; (himin_off, himax_off, vimin_off, vimax_off,   <- HDMI ascal input crop
;  os_l, os_r, os_t, os_b,                       <- analog overscan soft-blank
;  pan_x, pan_y)                                 <- analog position
; A legacy v3 row has only the first 8 words; the two pan words are zeroed on
; load, so existing v3 files keep working as overscan-only. The overscan four
; bias the analog soft-blank window; the pan pair drives the analog_positioner
; sync-phase shift (both M2M-UPSTREAM screen-center, applied in the framework
; av_pipeline). Only the low 12 bits of each word reach the core.
;
; Input:  None      Output: R8 = 0, R9 = 0
; ----------------------------------------------------------------------------
LOAD_SCREEN_OFFSETS INCRB

                RSUB    SDC$HOMEDEV, 1          ; the card of the settings file
                CMP     0, R9                   ; (M2M-UPSTREAM sd-host; it is
                RBRA    _LSO_ZERO, !Z           ; mounted again after a card
                                                ; change) - none: zero table
                MOVE    R8, R0                  ; R0: device handle
                MOVE    SCR_FILE_NAME, R8       ; "/amiga/aexp_screen.cfg"
                RSUB    RODATA_STR, 1           ; (read-only data: in RAM)
                MOVE    R8, R10
                MOVE    R0, R8
                MOVE    SCR_FDH, R9        ; empty file handle struct
                XOR     R11, R11                ; "/" path separator
                SYSCALL(f32_fopen, 1)
                CMP     0, R10                  ; open OK?
                RBRA    _LSO_ZERO, !Z           ; no -> zero table

                RSUB    _LSO_RDBYTE, 1          ; header byte 0: 'A'
                CMP     0, R10
                RBRA    _LSO_ZERO, !Z
                CMP     0x0041, R8
                RBRA    _LSO_ZERO, !Z
                RSUB    _LSO_RDBYTE, 1          ; header byte 1: 'X'
                CMP     0x0058, R8
                RBRA    _LSO_ZERO, !Z
                RSUB    _LSO_RDBYTE, 1          ; header byte 2: version 3 or 4
                MOVE    R8, R7                  ; R7: file version (banked reg)
                CMP     SCR_VER_V3, R8
                RBRA    _LSO_VEROK, Z
                CMP     SCR_VER_V4, R8
                RBRA    _LSO_ZERO, !Z
_LSO_VEROK      RSUB    _LSO_RDBYTE, 1          ; header byte 3: count = 4 modes
                CMP     SCR_MODES, R8
                RBRA    _LSO_ZERO, !Z

                MOVE    SCR_TABLE, R0           ; R0: table destination
                MOVE    SCR_MODES, R2           ; R2: row counter
_LSO_ROWLOOP    MOVE    SCR_V3_WORDS, R1        ; 8 words: HDMI + overscan
_LSO_RDLOOP     RSUB    _LSO_RDWORD, 1          ; R8 = 16-bit value, R10 status
                CMP     0, R10                  ; full word read?
                RBRA    _LSO_ZERO, !Z           ; truncated -> zero table
                MOVE    R8, @R0++               ; store into the RAM table
                SUB     1, R1
                RBRA    _LSO_RDLOOP, !Z
                CMP     SCR_VER_V4, R7          ; v4: two pan words follow
                RBRA    _LSO_PANZ, !Z
                MOVE    SCR_PAN_WORDS, R1
_LSO_PANLOOP    RSUB    _LSO_RDWORD, 1
                CMP     0, R10
                RBRA    _LSO_ZERO, !Z
                MOVE    R8, @R0++
                SUB     1, R1
                RBRA    _LSO_PANLOOP, !Z
                RBRA    _LSO_NXROW, 1
_LSO_PANZ       MOVE    0, @R0++                ; v3: pan_x = pan_y = 0
                MOVE    0, @R0++
_LSO_NXROW      SUB     1, R2
                RBRA    _LSO_ROWLOOP, !Z
                RBRA    _LSO_ARM, 1

_LSO_ZERO       MOVE    SCR_TABLE, R0      ; no/invalid file -> all zeros
                MOVE    SCR_TABLE_WORDS, R1      ; (0,0,0,0 = no centering)
_LSO_ZLOOP      MOVE    0, @R0++
                SUB     1, R1
                RBRA    _LSO_ZLOOP, !Z

                ; force the mode detector to (re-)push the row of the current
                ; mode by invalidating the applied-mode latch and restarting the
                ; debounce
_LSO_ARM        MOVE    SCR_APPLIED_MODE, R0
                MOVE    SCR_MODE_NONE, @R0
                MOVE    SCR_CAND_MODE, R0
                MOVE    SCR_MODE_NONE, @R0
                MOVE    SCR_CAND_CNT, R0
                MOVE    0, @R0

                XOR     R8, R8
                XOR     R9, R9
                DECRB
                RET

; read one byte from SCR_FDH -> R8 = byte, R10 = status (0 = OK). Shares the
; register bank of the caller (touches only R8/R9/R10).
_LSO_RDBYTE     MOVE    SCR_FDH, R8
                SYSCALL(f32_fread, 1)           ; R9 = byte, R10 = status
                MOVE    R9, R8
                RET

; read a big-endian 16-bit word -> R8 = value, R10 = status (0 = OK only if
; both bytes were read). Combines (hi << 8) | lo via SWAP.
_LSO_RDWORD     INCRB
                RSUB    _LSO_RDBYTE, 1          ; R8 = hi byte
                CMP     0, R10
                RBRA    _LSO_RDW_ERR, !Z
                MOVE    R8, R0
                SWAP    R0, R0                  ; R0 = hi << 8
                RSUB    _LSO_RDBYTE, 1          ; R8 = lo byte
                CMP     0, R10
                RBRA    _LSO_RDW_ERR, !Z
                OR      R8, R0
                MOVE    R0, R8                  ; R8 = (hi << 8) | lo
                XOR     R10, R10                ; status = OK
_LSO_RDW_RET    DECRB
                RET
_LSO_RDW_ERR    MOVE    1, R10                  ; status = error
                RBRA    _LSO_RDW_RET, 1

; push value R8 into CFD gp_reg word R9 (0..15). Fresh bank for the scratch.
_LSO_CFDW       INCRB
                MOVE    M2M$CFD_ADDR, R0
                MOVE    R9, @R0                 ; select 16-bit window
                MOVE    M2M$CFD_DATA, R0
                MOVE    R8, @R0                 ; write value into the window
                DECRB
                RET

; ----------------------------------------------------------------------------
; DETECT_SCREEN_MODE: screen adjustment (issue #5), the runtime half. Called
; from HANDLE_CORE_IO every main-loop / wait-loop iteration. Reads the
; ascal-measured input geometry (SYS_CORE_X/Y) and the interlace flag
; (SYS_CORE_FLAGS bit 0, M2M-UPSTREAM screen-center), classifies the Amiga
; graphics mode, debounces it, and on a stable CHANGE pushes the matching
; SCR_TABLE row into CFD gp_reg: HDMI crop into words 4..7, analog overscan
; into words 0..3, analog pan into words 8..9, and logs a MiSTer-style
; two-line (HDMI + Analog) trace to the serial UART. A mode outside the table
; (unexpected geometry) applies all zeros and logs "unsupported". Fully
; self-contained: own enter/leave and RAMROM device/window save/restore.
;
; Input/Output: none; all registers preserved
; ----------------------------------------------------------------------------
DETECT_SCREEN_MODE SYSCALL(enter, 1)

                ; --- read SYS_CORE geometry + interlace flag, transparently
                ; restoring the RAMROM device/window selection of the caller ---
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    @R0, R1
                MOVE    M2M$RAMROM_4KWIN, R2
                MOVE    @R2, R3
                MOVE    M2M$SYS_INFO, @R0
                MOVE    M2M$SYS_CORE, @R2
                MOVE    M2M$SYS_CORE_X, R4
                MOVE    @R4, R4                 ; R4 = hdmax (measured + 1)
                MOVE    M2M$SYS_CORE_Y, R5
                MOVE    @R5, R5                 ; R5 = vdmax
                MOVE    M2M$SYS_CORE_FLAGS, R6
                MOVE    @R6, R6                 ; R6 = flags (bit 0 = interlaced)
                MOVE    R1, @R0                 ; restore RAMROM selection
                MOVE    R3, @R2

                ; --- classify hdmax (OCS PAL is bimodal; the in_range_u syscall
                ;     tests the half-open window R9 <= R8 < R10) ---
                CMP     SCR_HDMAX_NOSIG, R4     ; hdmax < 200 -> no video yet
                RBRA    _DSM_RET, N             ;   (boot / mode change) -> skip
                MOVE    R4, R8                  ; R8 = hdmax for the range checks
                MOVE    SCR_LORES_LO, R9        ; lores window [367, 388)
                MOVE    SCR_LORES_HI, R10
                SYSCALL(in_range_u, 1)
                RBRA    _DSM_LORES, C
                MOVE    SCR_HIRES_LO, R9        ; hires window [744, 765)
                MOVE    SCR_HIRES_HI, R10       ; (R8 still = hdmax)
                SYSCALL(in_range_u, 1)
                RBRA    _DSM_HIRES, C
                RBRA    _DSM_UNK, 1             ; present but unrecognised

_DSM_LORES      XOR     R7, R7                  ; horizontal bit 0 = lores
                RBRA    _DSM_SCAN, 1
_DSM_HIRES      MOVE    SCR_HIRES_BIT, R7       ; horizontal bit 1 = hires
_DSM_SCAN       MOVE    R6, R0                  ; interlaced -> rows 2/3
                AND     M2M$SYS_CORE_FL_INT, R0
                RBRA    _DSM_DEB, Z
                ADD     SCR_LACE_ADD, R7
                RBRA    _DSM_DEB, 1
_DSM_UNK        MOVE    SCR_MODE_UNKNOWN, R7    ; = 4

                ; --- debounce: SCR_DEBOUNCE stable reads before acting ---
_DSM_DEB        MOVE    SCR_CAND_MODE, R0
                CMP     @R0, R7                 ; same as the candidate?
                RBRA    _DSM_SAME, Z
                MOVE    R7, @R0                 ; no: restart the candidate
                MOVE    SCR_CAND_CNT, R0
                MOVE    0, @R0
                RBRA    _DSM_RET, 1
_DSM_SAME       MOVE    SCR_CAND_CNT, R0
                CMP     SCR_DEBOUNCE, @R0       ; count < DEBOUNCE -> settling
                RBRA    _DSM_SETTLE, N
                MOVE    SCR_APPLIED_MODE, R0
                CMP     @R0, R7                 ; already the applied mode?
                RBRA    _DSM_RET, Z
                MOVE    R7, @R0                 ; latch the newly applied mode
                RBRA    _DSM_APPLY, 1
_DSM_SETTLE     MOVE    SCR_CAND_CNT, R0
                ADD     1, @R0
                RBRA    _DSM_RET, 1

                ; --- apply mode R7: push offsets to the CFD, then log ---
_DSM_APPLY      CMP     SCR_MODE_UNKNOWN, R7
                RBRA    _DSM_KNOWN, !Z
                MOVE    SCR_ROW_WORDS, R2       ; unknown: push 10 zeros = all off
                MOVE    SCR_CFD_VGA, R9         ; CFD words 0..9 (overscan 0..3,
_DSM_ZLOOP      XOR     R8, R8                  ;  HDMI 4..7, pan 8..9)
                RSUB    _LSO_CFDW, 1
                ADD     1, R9
                SUB     1, R2
                RBRA    _DSM_ZLOOP, !Z
                MOVE    MSG_SCR_UNSUP, R8
                RSUB    RODATA_PUTS, 1
                RBRA    _DSM_LOGGEO, 1

_DSM_KNOWN      MOVE    R7, R0                  ; row offset = mode * SCR_ROW_WORDS
                ADD     R0, R0                  ; (= *10: *2, keep, *8, add)
                MOVE    R0, R1                  ; R1 = mode * 2
                ADD     R0, R0
                ADD     R0, R0                  ; R0 = mode * 8
                ADD     R1, R0                  ; R0 = mode * 10
                ADD     SCR_TABLE, R0           ; R0 -> table row (10 words)
                MOVE    R0, R3                  ; keep the row ptr for the log
                ; push the HDMI half (row words 0..3) -> CFD words 4..7
                MOVE    SCR_HALF_WORDS, R2
                MOVE    SCR_CFD_HDMI, R9
_DSM_PLOOPH     MOVE    @R0++, R8
                RSUB    _LSO_CFDW, 1
                ADD     1, R9
                SUB     1, R2
                RBRA    _DSM_PLOOPH, !Z
                ; push the overscan half (row words 4..7) -> CFD words 0..3
                MOVE    SCR_HALF_WORDS, R2      ; R0 now points at the overscan half
                MOVE    SCR_CFD_VGA, R9
_DSM_PLOOPV     MOVE    @R0++, R8
                RSUB    _LSO_CFDW, 1
                ADD     1, R9
                SUB     1, R2
                RBRA    _DSM_PLOOPV, !Z
                ; push the pan pair (row words 8..9) -> CFD words 8..9
                MOVE    SCR_PAN_WORDS, R2
                MOVE    SCR_CFD_PAN, R9
_DSM_PLOOPP     MOVE    @R0++, R8
                RSUB    _LSO_CFDW, 1
                ADD     1, R9
                SUB     1, R2
                RBRA    _DSM_PLOOPP, !Z
                MOVE    MSG_SCR_PFX, R8         ; "Screen: Amiga mode "
                RSUB    RODATA_PUTS, 1
                MOVE    R7, R0                  ; LORES / HIRES
                AND     SCR_HIRES_BIT, R0
                RBRA    _DSM_LHIR, !Z
                MOVE    MSG_SCR_LORES, R8
                RBRA    _DSM_LHPUT, 1
_DSM_LHIR       MOVE    MSG_SCR_HIRES, R8
_DSM_LHPUT      RSUB    RODATA_PUTS, 1
                MOVE    R6, R0                  ; PROGRESSIVE / INTERLACED
                AND     M2M$SYS_CORE_FL_INT, R0
                RBRA    _DSM_LLAC, !Z
                MOVE    MSG_SCR_PROG, R8
                RBRA    _DSM_LSPUT, 1
_DSM_LLAC       MOVE    MSG_SCR_LACE, R8
_DSM_LSPUT      RSUB    RODATA_PUTS, 1

_DSM_LOGGEO     MOVE    MSG_SCR_GEO1, R8        ; "  (hdmax="
                RSUB    RODATA_PUTS, 1
                MOVE    R4, R8
                RSUB    _SCR_LOGDEC, 1
                MOVE    MSG_SCR_GEO2, R8        ; " vdmax="
                RSUB    RODATA_PUTS, 1
                MOVE    R5, R8
                RSUB    _SCR_LOGDEC, 1
                MOVE    MSG_SCR_GEO3, R8        ; ")"
                RSUB    RODATA_PUTS, 1
                SYSCALL(crlf, 1)
                CMP     SCR_MODE_UNKNOWN, R7    ; unknown: no offset lines
                RBRA    _DSM_RET, Z
                MOVE    R3, R0                  ; row ptr -> HDMI half then VGA half
                ; --- line "HDMI:": ascal input-crop offsets (row words 0..3) ---
                MOVE    MSG_SCR_HDMI, R8        ; "HDMI: himin="
                RSUB    RODATA_PUTS, 1
                MOVE    @R0++, R8
                RSUB    _SCR_LOGSDEC, 1
                MOVE    MSG_SCR_OFF2, R8        ; " himax="
                RSUB    RODATA_PUTS, 1
                MOVE    @R0++, R8
                RSUB    _SCR_LOGSDEC, 1
                MOVE    MSG_SCR_OFF3, R8        ; " vimin="
                RSUB    RODATA_PUTS, 1
                MOVE    @R0++, R8
                RSUB    _SCR_LOGSDEC, 1
                MOVE    MSG_SCR_OFF4, R8        ; " vimax="
                RSUB    RODATA_PUTS, 1
                MOVE    @R0++, R8
                RSUB    _SCR_LOGSDEC, 1
                SYSCALL(crlf, 1)
                ; --- line "Analog:": overscan (row words 4..7) + pan (8..9) ---
                MOVE    MSG_SCR_VGA, R8         ; "Analog: os_l="
                RSUB    RODATA_PUTS, 1
                MOVE    @R0++, R8
                RSUB    _SCR_LOGSDEC, 1
                MOVE    MSG_SCR_VOF2, R8        ; " os_r="
                RSUB    RODATA_PUTS, 1
                MOVE    @R0++, R8
                RSUB    _SCR_LOGSDEC, 1
                MOVE    MSG_SCR_VOF3, R8        ; " os_t="
                RSUB    RODATA_PUTS, 1
                MOVE    @R0++, R8
                RSUB    _SCR_LOGSDEC, 1
                MOVE    MSG_SCR_VOF4, R8        ; " os_b="
                RSUB    RODATA_PUTS, 1
                MOVE    @R0++, R8
                RSUB    _SCR_LOGSDEC, 1
                MOVE    MSG_SCR_VOF5, R8        ; " pan_x="
                RSUB    RODATA_PUTS, 1
                MOVE    @R0++, R8
                RSUB    _SCR_LOGSDEC, 1
                MOVE    MSG_SCR_VOF6, R8        ; " pan_y="
                RSUB    RODATA_PUTS, 1
                MOVE    @R0++, R8
                RSUB    _SCR_LOGSDEC, 1
                SYSCALL(crlf, 1)

_DSM_RET        SYSCALL(leave, 1)
                RET

; log the unsigned value in R8 as decimal on the serial UART
_SCR_LOGDEC     SYSCALL(enter, 1)
                XOR     R9, R9                  ; high word = 0
                SUB     11, SP                  ; scratch decimal-string buffer
                MOVE    SP, R10
                SYSCALL(h2dstr, 1)              ; R11 -> decimal string
                MOVE    R11, R8
                SYSCALL(puts, 1)
                ADD     11, SP
                SYSCALL(leave, 1)
                RET

; log the signed value in R8 as decimal with an explicit +/- sign
_SCR_LOGSDEC    SYSCALL(enter, 1)
                MOVE    R8, R0                  ; keep the value
                AND     0x8000, R8              ; negative?
                RBRA    _SLS_NEG, !Z
                MOVE    0x002B, R8              ; '+'
                SYSCALL(putc, 1)
                MOVE    R0, R8
                RBRA    _SLS_MAG, 1
_SLS_NEG        MOVE    0x002D, R8              ; '-'
                SYSCALL(putc, 1)
                MOVE    R0, R8
                XOR     0xFFFF, R8              ; magnitude = -value
                ADD     1, R8
_SLS_MAG        RSUB    _SCR_LOGDEC, 1
                SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; M2M$LOAD_POLYPHASE  Load a (horizontal, vertical) filter pair into the
;                    ascal polyphase coefficient RAM. ASCAL_FILTER_LEN
;                    (= 0x100, defined in M2M/rom/filters.asm) words are
;                    copied into the H slot at M2M$ASCAL_PP_HORIZ and another
;                    0x100 words into the V slot at M2M$ASCAL_PP_VERT,
;                    through QNICE device M2M$ASCAL_PPHASE.
;
;                    Safe to call at boot or at runtime from a core OSM
;                    callback. Does NOT touch ascal mode bits, does NOT reset
;                    the core.
;
;                    BACKPORT from M2M V2.1 (M2M/rom/tools.asm): our M2M
;                    V2.0.1 framework does not ship this routine and M2M/rom
;                    firmware stays unmodified in this repo, so it lives here
;                    (the only sanctioned M2M/ change is the VHDL interlace
;                    feature, tagged M2M-UPSTREAM interlace). When the
;                    framework is upgraded to V2.1+, delete this copy -- the
;                    assembler will flag the duplicate label -- and re-apply
;                    or upstream the M2M-UPSTREAM interlace patch.
;
; Input:  R8 = pointer to a 256-word horizontal coefficient table
;         R9 = pointer to a 256-word vertical   coefficient table
; Output: -
; ----------------------------------------------------------------------------

M2M$LOAD_POLYPHASE  SYSCALL(enter, 1)

                ; select the ascal Polyphase RAM device
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    M2M$ASCAL_PPHASE, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0

                MOVE    ASCAL_FILTER_LEN, R10

                ; copy horizontal filter (R8 already = H label) to PP_HORIZ
                MOVE    R9, R0                  ; stash V pointer
                MOVE    M2M$RAMROM_DATA, R9
                ADD     M2M$ASCAL_PP_HORIZ, R9
                RSUB    _PP_COPY, 1

                ; copy vertical filter (R0 = stashed V label) to PP_VERT.
                MOVE    R0, R8
                MOVE    M2M$RAMROM_DATA, R9
                ADD     M2M$ASCAL_PP_VERT, R9
                RSUB    _PP_COPY, 1

                SYSCALL(leave, 1)
                RET

; _PP_COPY: copy R10 words from the table R8 to R9 in the polyphase window.
; Megamiga: a table at 0x8000 or above is a window address of the read-only
; data device (m2m-rodata.asm) - the QNICE ROM ends at 0x8000 - and is copied
; word by word, switching between that device and the polyphase device;
; tables in the ROM (LANCZOS2_12 of the framework, SCAN_BR_110_80) are copied
; with memcpy as before. Expects the polyphase device to be selected and
; leaves it selected. R8..R10 preserved.
_PP_COPY        CMP     R8, 0x7FFF              ; table in the ROM?
                RBRA    _PPC_RD, N              ; no (R8 > 0x7FFF)
                SYSCALL(memcpy, 1)
                RET
_PPC_RD         INCRB
                MOVE    R8, R0                  ; R0: source, R1: target
                MOVE    R9, R1
                MOVE    R10, R2                 ; R2: words
                MOVE    M2M$RAMROM_DEV, R3
                MOVE    M2M$RAMROM_4KWIN, R4    ; (polyphase and data device
_PPC_L          MOVE    AEXP_DEV_RODATA, @R3    ; both use window 0)
                MOVE    @R0++, R5
                MOVE    M2M$ASCAL_PPHASE, @R3
                MOVE    0, @R4
                MOVE    R5, @R1++
                SUB     1, R2
                RBRA    _PPC_L, !Z
                DECRB
                RET

; The three core-local filter coefficient blobs (GS_SHARPNESS_050,
; CRT_SIM_COMPOSITE_H, CRT_SIM_SVIDEO_H) live in m2m-rodata.asm; their labels
; are window addresses >= 0x8000 of the read-only data device, which
; M2M$LOAD_POLYPHASE recognises.

; ----------------------------------------------------------------------------
; Core specific constants and strings
; ----------------------------------------------------------------------------

; OSM menu constants are autogenerated by make_rom.sh (like in C64MEGA65):
; the AEXP_OSM_* line numbers are scraped from the C_MENU_* constants in
; ../vhdl/mega65.vhd and the AEXP_OPTM_G_* group ids from the OPTM_G_*
; constants in ../vhdl/config.vhd -- no hardcoded menu indexes here.
#include "osm_const.asm"

; Labels of the read-only data device (window addresses), generated by
; make_rom.sh from m2m-rodata.asm. RODATA_BUF_SIZE must hold the longest text
; (make_rom.sh checks it).
#include "rodata_sym.asm"
RODATA_BUF_SIZE .EQU    200

; ADF file extension (needs to be upper case)
ADF_FILE_EXT    .ASCII_W ".ADF"
HDF_FILE_EXT    .ASCII_W ".HDF"

; IDE board (ide_board.vhd), device AEXP_DEV_IDE, window 0
IDE_DATA        .EQU    0x8000              ; W: data for the CPU, R: data from it
IDE_EVENTS      .EQU    0x8100              ; event toggles, see IDE_EV_*
IDE_TF_CMD      .EQU    0x8101              ; task file snapshot ...
IDE_TF_COUNT    .EQU    0x8103
IDE_TF_LBA0     .EQU    0x8104
IDE_TF_LBA1     .EQU    0x8105
IDE_TF_LBA2     .EQU    0x8106
IDE_TF_DEVH     .EQU    0x8107
IDE_NSTAT       .EQU    0x8110              ; status to apply on commit
IDE_NERR        .EQU    0x8111              ; error register to apply on commit
IDE_NFLAGS      .EQU    0x8112              ; bit 0: data phase CPU -> buffer
IDE_CTRL        .EQU    0x8118              ; see IDE_CTRL_*
IDE_COMMIT_REG  .EQU    0x811F              ; any write: commit
IDE_ENG_U0      .EQU    0x8120              ; sector engine, unit 0: mode, sectors
IDE_ENG_U1      .EQU    0x8128              ; lo/hi, base lo/hi, shift (+0..+5)
IDE_ENG_MODE    .EQU    0                   ; offsets in a unit's block
IDE_ENG_SECT    .EQU    1
IDE_ENG_BASE    .EQU    3
IDE_ENG_SHIFT   .EQU    5
IDE_ENG_MULT    .EQU    6                   ; the multiple count (Megamiga 0.7)
IDE_ENG_GEOM    .EQU    7                   ; the CHS geometry (Megamiga 0.7)
IDE_ENG_SKIP0   .EQU    0x8138              ; unit 0/1: blocks in front of the image
IDE_ENG_SKIP1   .EQU    0x8139              ; (Megamiga 0.7, the virtual RDB)
IDE_DIAG_REQ    .EQU    0x8134              ; diagnostics: snapshot request
IDE_DIAG_CNT    .EQU    0x8140              ; ... 12 x 32-bit counters (lo, hi)
IDE_ENG_OFF     .EQU    0                   ; modes: firmware (IDE_STEP)
IDE_ENG_FILE    .EQU    1                   ; extent map of the file
IDE_ENG_PART    .EQU    2                   ; partition of the card
IDE_ENG_SLOT1   .EQU    4                   ; + bit 2: on the external card
IDE_ENG_MAP     .EQU    0x8000              ; window 1: the extent maps (W only),
IDE_ENG_MAPW    .EQU    2048                ; unit u at u * IDE_ENG_MAPW
IDE_EV_CMD      .EQU    0x0001              ; a command was written
IDE_EV_BUF      .EQU    0x0002              ; the CPU finished a buffer
IDE_EV_RST      .EQU    0x0004              ; reset (Amiga, RESET instr., SRST)
IDE_EV_ACK      .EQU    0x0008              ; a commit was applied
IDE_CTRL_PRESENT .EQU   0x0001              ; the master answers on the bus
IDE_CTRL_PRES1  .EQU    0x0004              ; the slave answers on the bus
IDE_CTRL_BOARD  .EQU    0x0002              ; the board is in the autoconfig chain
IDE_ST_IDLE     .EQU    0                   ; server states: no command
IDE_ST_RDPREP   .EQU    1                   ; READ: next sector to be read
IDE_ST_RDWAIT   .EQU    2                   ; READ: the CPU reads the buffer
IDE_ST_WRWAIT   .EQU    3                   ; WRITE: the CPU fills the buffer
IDE_ST_IDWAIT   .EQU    4                   ; IDENTIFY: the CPU reads the buffer
IDE_ST_READY    .EQU    0x0050              ; DRDY | DSC
IDE_ST_DRQ      .EQU    0x0058              ; DRDY | DSC | DRQ
IDE_ST_ERROR    .EQU    0x0051              ; DRDY | DSC | ERR
IDE_FL_WRITE    .EQU    0x0001
IDE_FL_IRQ      .EQU    0x0004              ; raise INTRQ (Gayle mode, the rules of ide.cpp)
IDE_FL_END      .EQU    0x0008              ; the last buffer -> CPU block ends the command
IDE_FL_WRIRQ    .EQU    0x0005              ; IDE_FL_WRITE | IDE_FL_IRQ
IDE_FL_ENDIRQ   .EQU    0x000C              ; IDE_FL_END | IDE_FL_IRQ
IDE_FL_MORE     .EQU    0x0010              ; the next sector is in the same block
IDE_FL_NOIRQ    .EQU    0xFFFB              ; AND mask: no IDE_FL_IRQ
IDE_GAYLE       .EQU    0x8119              ; bit 0: the board is the Gayle (read only)
IDE_ERR_ABRT    .EQU    0x0004              ; command aborted
IDE_ERR_IDNF    .EQU    0x0010              ; sector not found (out of range)
IDE_ERR_UNC     .EQU    0x0040              ; uncorrectable (SD card error)
IDE_DEVH_LBA    .EQU    0x0040              ; device/head: LBA addressing
IDE_DEVH_DEV    .EQU    0x0010              ; device/head: 0 master, 1 slave
IDE_CMD_IDENTIFY .EQU   0x00EC
IDE_CMD_READ    .EQU    0x0020
IDE_CMD_READ_NR .EQU    0x0021
IDE_CMD_WRITE   .EQU    0x0030
IDE_CMD_WRITE_NR .EQU   0x0031
IDE_SECT_PER_CYL .EQU   1008                ; 16 heads x 63 sectors
IDE_DEF_HEADS   .EQU    16                  ; the default CHS geometry
IDE_DEF_SPT     .EQU    63
IDE_CMD_READ_MULT  .EQU 0x00C4              ; READ MULTIPLE (Megamiga 0.7)
IDE_CMD_WRITE_MULT .EQU 0x00C5              ; WRITE MULTIPLE
IDE_CMD_SET_MULT   .EQU 0x00C6              ; SET MULTIPLE MODE
IDE_MULT_MAX    .EQU    16                  ; the largest block (IDENTIFY 47)
IDE_MULT_BAD    .EQU    0xFFE0              ; counts of 32 and more
IDE_IDW_MULT    .EQU    59                  ; IDENTIFY: the current count
IDE_CMD_INITDP  .EQU    0x0091              ; INITIALIZE DEVICE PARAMETERS
IDE_MAX_CYL     .EQU    16383               ; CHS maximum
IDE_IDW_CYL     .EQU    1                   ; IDENTIFY word indexes
IDE_IDW_HDS     .EQU    3                   ; (Megamiga 0.7: the default heads and
IDE_IDW_SPT     .EQU    6                   ; sectors of a virtual RDB, B3_VRDB_ID)
IDE_IDW_SERIAL  .EQU    10
IDE_IDW_FWREV   .EQU    23
IDE_IDW_MODEL   .EQU    27
IDE_IDW_CUR_CYL .EQU    54
IDE_IDW_CUR_HDS .EQU    55
IDE_IDW_CUR_SPT .EQU    56
IDE_IDW_CUR_CAP .EQU    57                  ; 57/58: current capacity
IDE_IDW_LBA_LO  .EQU    60
IDE_IDW_LBA_HI  .EQU    61
IDE_ACK_LOOPS   .EQU    20000               ; a commit is acknowledged in ~2 us
IDE_RESET_LOOPS .EQU    5000                ; ~0.5 ms reset pulse
IDE_LIDE_AUTO_ID .EQU   1                   ; lide.rom = auto-load ROM 1
AR3_AUTO_ID     .EQU    2                   ; ar3.rom = auto-load ROM 2
IDE_ASCII_SPACE .EQU    0x0020
HDF_MIN_SIZE_HI .EQU    1                   ; at least 64 KB
HDF_MAP_WORDS   .EQU    257                 ; extent map: 64 extents
HDF_BLK_WORDS   .EQU    288                 ; FDH (15 since the FAT32 write
                                            ; layer) + 16 + HDF_MAP_WORDS

; commands that need no data and no action: answered with DRDY right away
; (INITIALIZE DEVICE PARAMETERS, SET FEATURES, RECALIBRATE, READ VERIFY,
; SEEK, power management, FLUSH CACHE)
IDE_CMD_OK_TAB  .DW     0x0091, 0x00EF, 0x0010, 0x0040, 0x0041, 0x0070
                .DW     0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E6, 0x00E7
                .DW     0xFFFF

; fixed IDENTIFY DEVICE words (index, value), 0xFFFF terminates
IDE_ID_TAB      .DW     0, 0x0040           ; fixed disk
                .DW     3, 16               ; heads
                .DW     6, 63               ; sectors per track
                ;.DW     47, 0x8000          ; no READ/WRITE MULTIPLE
                .DW     47, 0x8010          ; READ/WRITE MULTIPLE: up to 16
                .DW     49, 0x0200          ; LBA supported
                .DW     51, 0x0200          ; PIO mode 2 timing
                .DW     53, 0x0001          ; words 54..58 valid
                .DW     80, 0x001E          ; ATA-1..ATA-4
                .DW     0xFFFF
; (the IDENTIFY strings IDE_ID_SERIAL / _FWREV / _MODEL are in m2m-rodata.asm)

; ADF write-back CSR (WBC): one instance per simulated drive, behind the device
; of that drive (AEXP_DEV_ADF0/1/2, autogenerated into osm_const.asm from
; globals.vhd), 4k window 0xFFFE - register map defined in
; CORE/vhdl/adf_mount_wrapper.vhd (keep in sync!). The register OFFSETS are the
; same for every drive; only the device id differs, which is what ADF_SEL_WBC
; encapsulates.
ADF_WBC_4KWIN   .EQU    0xFFFE              ; the write-back CSR window
ADF_WBC_CTRL    .EQU    0x8000              ; bit 0: WR_EN (this unit writable)
ADF_WBC_STAT    .EQU    0x8001              ; bit 0: any_dirty  bit 1: flush_start
ADF_WBC_ATDELAY .EQU    0x8002              ; anti-thrashing delay in ms
ADF_WBC_DIRTY0  .EQU    0x8010              ; ..0x701A: dirty bitmap, W1C
ADF_WBC_DIRTY_W .EQU    11                  ; bitmap words (166 tracks -> 11)
ADF_TRACK_BYTES .EQU    5632                ; 11 sectors x 512 bytes
ADF_FLUSH_CHUNK .EQU    512                 ; bytes per background time slice

; Number of simulated Amiga drive units. The index 0..2 is at the same time the
; Amiga unit (df0/df1/df2), the manual CRT/ROM id of the Shell - and therefore
; the index into HNDL_RM_FILES - and the index into the three tables below.
; This identity is what the whole per-drive write-back rests on; it holds
; because the three OPTM_G_LOAD_ROM mount lines sit in that order in the static
; OPTM_GROUPS array of config.vhd (a manual CRT/ROM line is bound to its id by
; POSITION, and hiding a line through a menu dependency does not renumber the
; others).
ADF_DRIVES      .EQU    3

; Kickstart selector: accepted ROM sizes (high words; the low words are 0)
PROF_KICK_ID    .EQU    6                       ; manual ROM ids (order of the
PROF_HDF_ID     .EQU    4                       ; OPTM_G_LOAD_ROM lines); the
                                                ; slave HDF is PROF_HDF_ID + 1
PROF_AR3_ID     .EQU    7                       ; the AR3 ROM line (0.6.5)
PROF_QHDF_ID    .EQU    3                       ; 0.7: the quick HDF line of the
                                                ; main page (QHDF_PREP)
PROF_DIR_LEN    .EQU    7                       ; strlen("/amiga/")
PROF_PEND_NUM   .EQU    4                       ; PROF_HDF_ID..PROF_AR3_ID
PROF_PN_LEN     .EQU    21                      ; a name in PROF_PNAME (+ zero)
KICK_256K_HI    .EQU    0x0004
KICK_512K_HI    .EQU    0x0008
KICK_1M_HI      .EQU    0x0010                  ; Megamiga 0.7: AROS (1 MB)

; The ADF track buffer (CORE/vhdl/adf_sd.vhd - keep in sync!): behind the device
; of each drive, window ADF_TB_REGWIN holds the registers of that drive and
; window ADF_TB_MAPWIN the extent map of its file.
ADF_TB_REGWIN   .EQU    0xFFFD
ADF_TB_MAPWIN   .EQU    0xFFFC
ADF_TB_MODE     .EQU    0x8000              ; bit 0: on, bit 1: the card in slot 1
ADF_TB_SECT     .EQU    0x8001              ; 512-byte sectors of the file lo, hi
ADF_TB_BASE     .EQU    0x8003              ; block of cluster 0 lo, hi; +2: shift
ADF_TB_STAT     .EQU    0x8008              ; bit 0 dirty, 1 busy, 2 FAULT, 3 pending
ADF_TB_FLUSH    .EQU    0x8009              ; write: write the dirty sectors now
ADF_TB_MAP      .EQU    0x8000              ; the extent map (FAT32$FILE_MAP)
ADF_TB_MAPW     .EQU    2048                ; map words per drive: 511 extents
ADF_TB_ON       .EQU    1                   ; modes
ADF_TB_SLOT1    .EQU    2
ADF_TB_WAIT     .EQU    9                   ; STAT: dirty or pending

; Per-drive tables, indexed by the drive 0..2. The only place in the firmware
; that knows how a drive maps to a QNICE device, to its own retained file
; handle and to its mount menu group.
ADF_DEV_TAB     .DW AEXP_DEV_ADF0, AEXP_DEV_ADF1, AEXP_DEV_ADF2
ADF_FDH_TAB     .DW ADF_FDH0, ADF_FDH1, ADF_FDH2
ADF_GRP_TAB     .DW AEXP_OPTM_G_ADF0, AEXP_OPTM_G_ADF1, AEXP_OPTM_G_ADF2

; Flat main-menu indexes of the twin lines of each drive, scraped from the
; C_MENU_*_LN constants of mega65.vhd - the mount line and its Hardware Floppy
; TEXT twin. Cross-checked against the item text by check_osm_menu.py.
ADF_MNT_LN_TAB  .DW AEXP_OSM_DF0_MOUNT_LN, AEXP_OSM_DF1_MOUNT_LN, AEXP_OSM_DF2_MOUNT_LN
ADF_HW_LN_TAB   .DW AEXP_OSM_DF0_HW_LN, AEXP_OSM_DF1_HW_LN, AEXP_OSM_DF2_HW_LN

; Hardware Floppy diagnostics: device C_DEV_AMIGA_FDD (globals.vhd), a read-only
; register bank in CORE/vhdl/physical_fdd/physical_fdd_diag.vhd. It decodes
; addr[5:0] only, so the 4k window is irrelevant and the register number is the
; offset into the data window. Only the two registers the status line needs are
; named here; the full map lives in the header of that file (keep in sync!).
AEXP_DEV_FDD    .EQU    0x0104              ; the diagnostics bank
HWF_DIAG_STAT   .EQU    0x8002              ; front-end status word
HWF_DIAG_SERVED .EQU    0x801B              ; words served into Paula (0x1B)
HWF_ST_MOTOR    .EQU    0x0004              ; status bit 2: the motor runs

; Live status line states. The order is the index into HWF_OSM_STR.
HWF_OS_IDLE     .EQU    0
HWF_OS_MOTOR    .EQU    1
HWF_OS_READ     .EQU    2
HWF_OS_INVALID  .EQU    0xFFFF              ; nothing painted; repaint at once
HWF_DRV_NONE    .EQU    0xFFFF              ; no drive owns the mechanism

HWF_OSM_POLL_MASK .EQU  0x0007              ; 763 Hz / 8 = about 95 Hz
HWF_LABEL_LEN   .EQU    22                  ; characters after the marker
HWF_LABEL_DIGIT .EQU    2                   ; the N of "dfN:" in the label
HWF_ASCII_ZERO  .EQU    0x0030

; The three status labels, each EXACTLY HWF_LABEL_LEN characters so that the
; previous text is always fully erased. The idle label is byte-identical to the
; static line in config.vhd, which makes painting it a visual no-op. The drive
; digit is patched in at runtime (HWF_LABEL_DIGIT), so one set covers all three
; drives.
HWF_OSM_STR     .DW HWF_OSM_IDLE, HWF_OSM_MOTOR, HWF_OSM_READ  ; (in m2m-rodata.asm)

; Live SD card status line (SD_STATUS_STEP). The order is the index into
; SD_OSM_STR; every label is EXACTLY HWF_LABEL_LEN characters.
SD_REG_MODE     .EQU    0xFF26              ; sdhost register 6 (read only)
SD_MODE_NATIVE  .EQU    0x0001              ; native 4-bit SD bus
SD_MODE_SLOW    .EQU    0x0002              ; 12.5 MHz (SPI after a failure)
SD_MODE_READY   .EQU    0x0004              ; card initialised
SD_OS_NONE      .EQU    0
SD_OS_4BIT      .EQU    1
SD_OS_SPI25     .EQU    2
SD_OS_SPI12     .EQU    3
SD_OSM_ATTR     .EQU    0x004F              ; M2M$SA_DARK + white on blue
SD_OSM_LEN      .EQU    7                   ; the state texts (m2m-rodata.asm)
SD_OSM_STR      .DW SD_OSM_NONE, SD_OSM_4BIT, SD_OSM_SPI25, SD_OSM_SPI12 ; (rodata)

; MEGA65 battery RTC (issue #13): framework device C_DEV_RTC (qnice_wrapper.vhd)
; exposing the QNICE date/time interface of M2M/vhdl/i2c/rtc_controller.vhd. The
; core reads the same time at $DC0000 (Minimig MSM6242B). The window offset
; equals the register address (keep in sync with rtc_controller.vhd).
AEXP_DEV_RTC    .EQU    0x0006              ; framework RTC device (C_DEV_RTC)
RTC_4KWIN       .EQU    0x0000              ; RTC decodes addr[7:0] only
RTC_MINUTES     .EQU    0x8002              ; internal timer: minutes (BCD, RO)
RTC_COMMAND     .EQU    0x8008              ; b0 busy(RO) b1 read b2 write b3 running
RTC_CMD_STOP    .EQU    0x0000              ; stop the internal timer
RTC_CMD_RESYNC  .EQU    0x000A              ; b1 read RTC->internal + b3 keep running

; Mount warnings, returned by PREP_LOAD_IMAGE as error message strings. The
; Shell prints them after "Error code: <code>" and then appends its own
; "Press Space to continue." prompt (_HM_SDMOUNTED5S in M2M/rom/shell.asm),
; so the strings must not contain such a prompt themselves. The trailing
; newline leaves one empty line between the message and the Shell prompt.

; The warning texts themselves live in the read-only data device
; (m2m-rodata.asm); RODATA_STR copies one into RAM before it is used.

; Screen centering (issue #5): per-Amiga-mode HDMI input-crop + VGA soft-blank table.
; File name, table geometry, mode indices and the serial-log strings. The four
; rows (lores-prog, hires-prog, lores-lace, hires-lace) default to all zeros
; (no centering) until /amiga/aexp_screen.cfg provides tuned values.
; (SCR_FILE_NAME and SCR_LOADING_STR are in m2m-rodata.asm)

; Momentary "Reload Screen Config" busy label (issue #19). SCR$PRINTSTR renders
; the < > as the arrow glyphs of the framework (same look as <Mount>/<Load>). It
; is exactly OPTM_DX (23) characters, so printed at the left edge of the content
; it fills the whole width; it is shown while the SD re-mount + reload runs and
; then OPTM_SHOW repaints it away.

SCR_MODES         .EQU 4                  ; table rows (file "count" byte)
SCR_TABLE_WORDS   .EQU 40                 ; 4 rows x 10 words (HDMI 4 + overscan 4 + pan 2)
SCR_MODE_UNKNOWN  .EQU 4                  ; detected mode outside the table
SCR_MODE_NONE     .EQU 0xFFFF             ; "nothing applied yet" latch value
SCR_DEBOUNCE      .EQU 3                  ; stable detects before a mode change
                                          ; (detect is throttled, so these span
                                          ; frames -- keep it small)
SCR_TICK_MASK     .EQU 0x00FF             ; run DETECT_SCREEN_MODE every 256th poll

SCR_CFD_HDMI      .EQU 4                  ; HDMI-offset CFD gp_reg words (4..7)
SCR_CFD_VGA       .EQU 0                  ; analog-overscan CFD gp_reg words (0..3)
SCR_CFD_PAN       .EQU 8                  ; analog-pan CFD gp_reg words (8..9)
SCR_ROW_WORDS     .EQU 10                 ; words per mode row (HDMI 4 + overscan 4 + pan 2)
SCR_HALF_WORDS    .EQU 4                  ; edge offsets per output group
SCR_V3_WORDS      .EQU 8                  ; row words shared by v3 and v4 (before pan)
SCR_PAN_WORDS     .EQU 2                  ; pan words per row (v4 only)
SCR_VER_V3        .EQU 3                  ; legacy file: no pan words (pan = 0)
SCR_VER_V4        .EQU 4                  ; current file: overscan + pan per row
SCR_HIRES_BIT     .EQU 1                  ; mode bit 0: 1 = hires horizontal
SCR_LACE_ADD      .EQU 2                  ; mode += 2 when interlaced (rows 2/3)

; hdmax (ascal-measured, +1) classification. OCS PAL geometry is deterministic
; (fixed Agnus beam constants: lores ~377/378, hires ~754/755, only +/-1..2
; ce-phase rounding), so the windows are tight (+/-~10 px). An unexpected geometry
; (a genuinely new/unknown mode) is thus flagged "unsupported" rather than forced
; into lores/hires. The raw hdmax is always logged, so if a board ever measures
; outside a window it is a one-line retune (the logged value +/-10). Windows are
; half-open [lo, hi) to match MTH$IN_RANGE_U.
SCR_HDMAX_NOSIG   .EQU 200                ; hdmax < 200: no video yet -> skip
SCR_LORES_LO      .EQU 367                ; lores hdmax window [367, 388) (~377/378)
SCR_LORES_HI      .EQU 388
SCR_HIRES_LO      .EQU 744                ; hires hdmax window [744, 765) (~754/755)
SCR_HIRES_HI      .EQU 765

; The serial-terminal log strings (MSG_SCR_*) live in m2m-rodata.asm; they
; are printed through RODATA_PUTS.

; This needs to be the last thing before the code banks and the variables
END_OF_ROM      .DW 0

; ----------------------------------------------------------------------------
; Code banks (Megamiga, M2M-UPSTREAM code-banks, see FAR_CALL): each bank is
; a section that starts with ".ORG 0x9000" (M2M$CODE_WIN) and its marker word
; 0x4B00 + n, bank n in source order. make_rom.sh (make_banks.py) writes them
; into m2m-banks.rom and checks the markers.
; ----------------------------------------------------------------------------

BANK_SHARE      .EQU    0                       ; the shared folder
BANK_F32W       .EQU    1                       ; FAT32 write layer: core
BANK_F32F       .EQU    2                       ; FAT32 write layer: files
BANK_IDE        .EQU    3                       ; 0.7: link files, virtual RDB
BANK_PROF       .EQU    4                       ; 0.7: profiles as files

#ifdef RELEASE
                .ORG    0x9000                  ; M2M$CODE_WIN (.ORG takes no symbol)
                .DW     0x4B00                  ; bank 0: BANK_SHARE

; ----------------------------------------------------------------------------
; Shared folder (Megamiga 0.6.1)
;
; The folder /amiga of the external SD card (the back slot, M2M-UPSTREAM
; sd-host: the card one can pull to share files with a computer) as an AmigaOS
; volume. On the
; Amiga, the handler MegamigaFS (CORE/share) turns every DOS packet into a
; request in the shared memory at $DD4000 (share_buf.vhd, QNICE device
; AEXP_DEV_SHARE) and waits; SHARE_STEP answers it from the SD card. The
; protocol is the one of MiSTer's MiSTerFileSystem (request layouts of MiSTer's
; miminig_fs_messages.h), so MiSTer's own handler works too:
;
;   word 0x000  request number, written last by the Amiga: (n + 77) << 8 | n
;   word 0x001  0xA55A while the request is pending; the firmware writes the
;               request number there once the response is complete
;   word 0x002  the request, then the response: 32-bit fields, big-endian,
;               field n at words 2 + 2n (n = 0 is a size), names as BSTRs
;   word 0x7FC  Megamiga status for MegamigaFS: 0x4D53 ('MS'), then bit 15 =
;               volume present and bits 14..0 = the generation, then the
;               protocol version. The generation changes whenever the volume
;               goes away or comes back: MegamigaFS shows that as a disk change.
;   word 0x7F6  event counters (diagnostics, the ShareInfo tool shows them):
;               0 (was: raw card-detect changes), card removals and
;               insertions, new card generations, 0 (was: slot switches),
;               mounts
;   word 0x800  the data buffer (4 KB) of READ
;
; Volume: /amiga is mounted on the device handle SHARE_DEV of its own (a copy
; of SDC_DEV1, the handle of the external card that the Shell and the core
; use: the volume needs its own current directory) about a second after the
; core starts and after a card is inserted. Every new generation of the
; external card (sdcards.asm: a card-detect level that held for ~100 ms, so a
; glitch of the signal does not look like a disk change to the Amiga) takes
; the volume down first.
; The main menu item " Mount SDCard" (AEXP_OSM_SHARE) ejects the volume
; while it is off, without touching the card; switching it on inserts it
; (after the same ~1 s as a card change). It is off at every start: the
; settings file may hold it on, so PREP_START clears it, and until then
; (SHR_INSW = SHR_INSW_BOOT) SHARE_STEP does not look at it.
;
; Locks and files: a lock is an object - the root (/amiga), a directory (its
; first cluster) or a file (the first cluster of its directory and its index
; in that directory) - in one of SHR_LOCKS_N slots. Its key is the generation
; (high word) and the slot + 1 (low word), so a lock from before a card change
; is refused (ERROR_DEVICE_NOT_MOUNTED) instead of meaning something else.
; Key 0 is the root. Open files are FAT32 handles in SHR_FILES_N slots, keyed
; the same way. An Amiga reset (the reset counter of share_buf.vhd) frees all.
;
; The SD sector buffer of the external card: SHARE_DEV is a second device
; handle on its controller (next to SDC_DEV1), and every device handle tracks
; the owner of the buffer itself. So a request first flushes and releases the
; buffer of SDC_DEV1 (SHR_TAKE_BUF) and finally releases its own
; (SHR_GIVE_BUF): between two time slices nobody claims the buffer, and every
; handle re-reads its sector on its next access.
; ----------------------------------------------------------------------------

SHR_W_FLAG      .EQU    0x8000                  ; the shared memory (window 0):
SHR_W_ACK       .EQU    0x8001                  ; request flag, answer flag,
SHR_W_REQ       .EQU    0x8002                  ; request/response,
SHR_W_STAT      .EQU    0x87FC                  ; status words,
SHR_W_EVC       .EQU    0x87F6                  ; event counters,
SHR_W_DATA      .EQU    0x8800                  ; data buffer
SHR_W_RSTC      .EQU    0x8000                  ; window 1: the reset counter
SHR_W_BYTES     .EQU    0x8000                  ; byte 0 of the shared memory
SHR_ST_UP       .EQU    0x8000                  ; status: volume present
SHR_LOCKS_N     .EQU    64                      ; lock slots
SHR_LOCK_SZ     .EQU    8                       ; an object (see SHR_OT)
SHR_FILES_N     .EQU    8                       ; open files: the FDH (15
SHR_FILE_SZ     .EQU    24                      ; words, FAT32$FDH_STRUCT_SIZE),
SHR_F_OBJ       .EQU    15                      ; its object (8 words) and
SHR_F_USED      .EQU    23                      ; "used" (1: read, 2: write)
SHR_DEBOUNCE    .EQU    768                     ; IO$CYC_MID ticks: ~1 s
SHR_EVC_N       .EQU    6                       ; event counters:
SHR_EV_RAW      .EQU    0                       ; (unused: 0)
SHR_EV_OUT      .EQU    1                       ; card removed
SHR_EV_IN       .EQU    2                       ; card inserted
SHR_EV_SDCH     .EQU    3                       ; new card generations
SHR_EV_SLOT     .EQU    4                       ; (unused: 0)
SHR_EV_MOUNT    .EQU    5                       ; mount attempts
SHR_INSW_BOOT   .EQU    0xFFFF                  ; SHR_INSW before PREP_START
SHR_PROTO       .EQU    2                       ; protocol version (2: writes)
SHR_W_TIME      .EQU    0x87F0                  ; the Amiga time of a request
SHR_MAXNAME     .EQU    106                     ; fib_FileName: 108 bytes

SHR_T_ROOT      .EQU    1                       ; object types
SHR_T_DIR       .EQU    2
SHR_T_FILE      .EQU    3

; AmigaOS DOS packet types
SHR_A_LOCATE    .EQU    8
SHR_A_FREELOCK  .EQU    15
SHR_A_DELETE    .EQU    16
SHR_A_RENAME    .EQU    17
SHR_A_COPYDIR   .EQU    19
SHR_A_SETPROT   .EQU    21
SHR_A_CREATEDIR .EQU    22
SHR_A_EXAMINE   .EQU    23
SHR_A_EXNEXT    .EQU    24
SHR_A_DISKINFO  .EQU    25
SHR_A_INFO      .EQU    26
SHR_A_SETCOMM   .EQU    28
SHR_A_PARENT    .EQU    29
SHR_A_SETDATE   .EQU    34
SHR_A_SAMELOCK  .EQU    40
SHR_A_READ      .EQU    82                      ; 'R'
SHR_A_WRITE     .EQU    87                      ; 'W'
SHR_A_FINDUPD   .EQU    1004
SHR_A_FINDIN    .EQU    1005
SHR_A_FINDOUT   .EQU    1006
SHR_A_END       .EQU    1007
SHR_A_SEEK      .EQU    1008
SHR_A_TRUNCATE  .EQU    1022
SHR_A_EXFH      .EQU    1034

; AmigaOS DOS error codes
SHR_E_NOMEM     .EQU    103                     ; ERROR_NO_FREE_STORE
SHR_E_INUSE     .EQU    202                     ; ERROR_OBJECT_IN_USE
SHR_E_EXISTS    .EQU    203                     ; ERROR_OBJECT_EXISTS
SHR_E_NAME      .EQU    210                     ; ERROR_INVALID_COMPONENT_NAME
SHR_E_DIRNE     .EQU    216                     ; ERROR_DIRECTORY_NOT_EMPTY
SHR_E_FULL      .EQU    221                     ; ERROR_DISK_FULL
SHR_E_NOTFOUND  .EQU    205                     ; ERROR_OBJECT_NOT_FOUND
SHR_E_UNKNOWN   .EQU    209                     ; ERROR_ACTION_NOT_KNOWN
SHR_E_LOCK      .EQU    211                     ; ERROR_INVALID_LOCK
SHR_E_TYPE      .EQU    212                     ; ERROR_OBJECT_WRONG_TYPE
SHR_E_WPROT     .EQU    214                     ; ERROR_DISK_WRITE_PROTECTED
SHR_E_NOTMNT    .EQU    218                     ; ERROR_DEVICE_NOT_MOUNTED
SHR_E_SEEK      .EQU    219                     ; ERROR_SEEK_ERROR
SHR_E_NODISK    .EQU    226                     ; ERROR_NO_DISK
SHR_E_NOMORE    .EQU    232                     ; ERROR_NO_MORE_ENTRIES

SHR_DIRNAME     .ASCII_W "/amiga"
SHR_VOLNAME     .ASCII_W "SDCard"

; the packet types and their handlers; each handler returns the DOS error
; code in R8 (0 = success) and may clobber R8..R12
SHR_ACTIONS     .DW     SHR_A_LOCATE,    SHR_DO_LOCATE
                .DW     SHR_A_FREELOCK,  SHR_DO_FREELOCK
                .DW     SHR_A_COPYDIR,   SHR_DO_COPYDIR
                .DW     SHR_A_PARENT,    SHR_DO_PARENT
                .DW     SHR_A_EXAMINE,   SHR_DO_EXAMINE
                .DW     SHR_A_EXNEXT,    SHR_DO_EXNEXT
                .DW     SHR_A_EXFH,      SHR_DO_EXFH
                .DW     SHR_A_FINDIN,    SHR_DO_FINDIN
                .DW     SHR_A_READ,      SHR_DO_READ
                .DW     SHR_A_SEEK,      SHR_DO_SEEK
                .DW     SHR_A_END,       SHR_DO_END
                .DW     SHR_A_SAMELOCK,  SHR_DO_SAMELOCK
                .DW     SHR_A_INFO,      SHR_DO_INFO
                .DW     SHR_A_DISKINFO,  SHR_DO_INFO
                .DW     SHR_A_FINDOUT,   SHR_DO_FINDOUT
                .DW     SHR_A_FINDUPD,   SHR_DO_FINDUPD
                .DW     SHR_A_WRITE,     SHR_DO_WRITE
                .DW     SHR_A_DELETE,    SHR_DO_DELETE
                .DW     SHR_A_RENAME,    SHR_DO_RENAME
                .DW     SHR_A_CREATEDIR, SHR_DO_MKDIR
                .DW     SHR_A_SETPROT,   SHR_DO_SETPROT
                .DW     SHR_A_SETCOMM,   SHR_DO_SETCOMM
                .DW     SHR_A_SETDATE,   SHR_DO_SETDATE
                .DW     SHR_A_TRUNCATE,  SHR_DO_SETSIZE
                .DW     0xFFFF

; days before the month (no leap day)
SHR_MDAYS       .DW     0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334

; SHARE_INIT: called once from START_FIRMWARE. No volume yet; the first mount
; follows after the debounce time. Requests already in the memory are ignored.
B0_SHARE_INIT   INCRB
                MOVE    SHARE_DEV, R0           ; nothing mounted
                MOVE    0, @R0
                MOVE    SHR_UP, R0
                MOVE    0, @R0
                MOVE    SHR_GEN, R0
                MOVE    1, @R0
                RSUB    SHR_CLOSE_ALL, 1
                RSUB    SHR_SEL, 1
                MOVE    SHR_W_FLAG, R0
                MOVE    SHR_LASTREQ, R1
                MOVE    @R0, @R1
                MOVE    M2M$RAMROM_4KWIN, R0    ; window 1: the reset counter
                MOVE    1, @R0
                MOVE    SHR_W_RSTC, R1
                MOVE    SHR_RSTSEEN, R2
                MOVE    @R1, @R2
                MOVE    0, @R0
                MOVE    SHR_SDGEN, R0           ; the first SHARE_STEP sees a
                MOVE    0, @R0                  ; new card (generations start
                                                ; at 1, sdcards.asm)
                MOVE    SHR_EVC, R0             ; no events yet
                MOVE    SHR_EVC_N, R1
_SHI_EV         MOVE    0, @R0++
                SUB     1, R1
                RBRA    _SHI_EV, !Z
                MOVE    SHR_MNT_PEND, R0
                MOVE    0, @R0
                MOVE    SHR_INSW, R0            ; the menu toggle: not read
                MOVE    SHR_INSW_BOOT, @R0      ; before PREP_START cleared it
                RSUB    SHR_STATUS, 1
                DECRB
                RET

; SHARE_STEP: called from HANDLE_CORE_IO. Follows the card, then answers a
; pending request. Leaves the device AEXP_DEV_SHARE selected; all registers
; preserved.
B0_SHARE_STEP   SYSCALL(enter, 1)
                RSUB    SHR_SEL, 1
                MOVE    M2M$RAMROM_4KWIN, R0    ; window 1: the reset counter
                MOVE    1, @R0
                MOVE    SHR_W_RSTC, R1
                MOVE    @R1, R1
                MOVE    0, @R0
                MOVE    SHR_RSTSEEN, R2
                CMP     @R2, R1
                RBRA    _SHS_MEDIA, Z
                MOVE    R1, @R2                 ; the Amiga was reset: its
                RSUB    SHR_CLOSE_ALL, 1        ; locks and files are gone

_SHS_MEDIA      RSUB    SHR_MEDIA, 1

                RSUB    SHR_SEL, 1              ; a new request?
                MOVE    SHR_W_FLAG, R0
                MOVE    @R0, R1                 ; R1: request number
                MOVE    SHR_LASTREQ, R2
                CMP     @R2, R1
                RBRA    _SHS_RET, Z
                MOVE    R1, @R2
                MOVE    SHR_W_ACK, R0
                CMP     0xA55A, @R0
                RBRA    _SHS_RET, !Z
                MOVE    R1, R2                  ; high byte - 77 = low byte
                SWAP    R2, R2
                SUB     77, R2
                AND     0x00FF, R2
                MOVE    R1, R3
                AND     0x00FF, R3
                CMP     R2, R3
                RBRA    _SHS_RET, !Z
                RSUB    SHR_REQUEST, 1
                RSUB    SHR_SEL, 1
                MOVE    SHR_W_ACK, R0           ; answered
                MOVE    R1, @R0
_SHS_RET        SYSCALL(leave, 1)
                RET

; SHR_SEL: select window 0 of the shared memory. All registers preserved.
SHR_SEL         INCRB
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    AEXP_DEV_SHARE, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0
                DECRB
                RET

; SHR_PEND: (re)mount after the debounce time. All registers preserved.
SHR_PEND        INCRB
                MOVE    SHR_MNT_PEND, R0
                MOVE    1, @R0
                MOVE    IO$CYC_MID, R0
                MOVE    SHR_MNT_T, R1
                MOVE    @R0, @R1
                DECRB
                RET

; SHR_MEDIA: follow the external SD card (see the header): a new generation of
; it (sdcards.asm: pulled, inserted, swapped) takes the volume down, and if a
; card is there, it comes back after SHR_DEBOUNCE. All registers preserved.
SHR_MEDIA       SYSCALL(enter, 1)
                MOVE    1, R8                   ; the external card
                RSUB    SDC$GEN, 1
                MOVE    SHR_SDGEN, R0
                CMP     @R0, R8
                RBRA    _SHM_PND, Z             ; no change
                MOVE    R8, @R0
                MOVE    SHR_EVC, R3
                ADD     SHR_EV_SDCH, R3
                ADD     1, @R3
                RSUB    SHR_DOWN, 1
                MOVE    SHR_MNT_PEND, R0
                MOVE    0, @R0
                MOVE    1, R8
                RSUB    SDC$PRESENT, 1
                RBRA    _SHM_INS, C
                MOVE    SHR_EVC, R3             ; removed: down until a card
                ADD     SHR_EV_OUT, R3          ; is inserted
                ADD     1, @R3
                RBRA    _SHM_PND, 1
_SHM_INS        MOVE    SHR_EVC, R3             ; inserted
                ADD     SHR_EV_IN, R3
                ADD     1, @R3
                RSUB    SHR_PEND, 1
_SHM_PND        MOVE    SHR_INSW, R0            ; still booting: off
                XOR     R9, R9
                CMP     SHR_INSW_BOOT, @R0
                RBRA    _SHM_EJ, Z
                MOVE    AEXP_OSM_SHARE, R8      ; the menu: mounted?
                RSUB    M2M$GET_SETTING, 1
                MOVE    SHR_INSW, R0
                CMP     @R0, R9
                RBRA    _SHM_EJ, Z
                MOVE    R9, @R0                 ; switched: on = insert
                CMP     0, R9
                RBRA    _SHM_EJ, Z
                RSUB    SHR_PEND, 1
_SHM_EJ         CMP     0, R9                   ; ejected: down, no mount
                RBRA    _SHM_MNT, !Z
                RSUB    SHR_DOWN, 1
                MOVE    SHR_MNT_PEND, R0
                MOVE    0, @R0
                RBRA    _SHM_RET, 1
_SHM_MNT        MOVE    SHR_MNT_PEND, R0        ; mount when the time is up
                CMP     0, @R0
                RBRA    _SHM_RET, Z
                MOVE    IO$CYC_MID, R1
                MOVE    @R1, R1
                MOVE    SHR_MNT_T, R3
                SUB     @R3, R1
                CMP     SHR_DEBOUNCE, R1
                RBRA    _SHM_RET, N             ; (SHR_DEBOUNCE > R1)
                MOVE    0, @R0
                MOVE    SHR_EVC, R3
                ADD     SHR_EV_MOUNT, R3
                ADD     1, @R3
                RSUB    SHR_MOUNT, 1
_SHM_RET        RSUB    SHR_STATUS, 1
                SYSCALL(leave, 1)
                RET

; SHR_DOWN: the volume goes away (if it was there). All registers preserved.
SHR_DOWN        INCRB
                MOVE    SHR_UP, R0
                CMP     0, @R0
                RBRA    _SHD_RET, Z
                MOVE    0, @R0
                MOVE    SHARE_DEV, R0
                MOVE    0, @R0
                RSUB    SHR_CLOSE_ALL, 1
                RSUB    SHR_NEWGEN, 1
                RSUB    SHR_STATUS, 1
_SHD_RET        DECRB
                RET

; SHR_NEWGEN: next generation, 1..0x7FFF. All registers preserved.
SHR_NEWGEN      INCRB
                MOVE    SHR_GEN, R0
                MOVE    @R0, R1
                ADD     1, R1
                AND     0x7FFF, R1
                RBRA    _SHN_W, !Z
                MOVE    1, R1
_SHN_W          MOVE    R1, @R0
                DECRB
                RET

; SHR_STATUS: publish the status words. All registers preserved.
SHR_STATUS      INCRB
                RSUB    SHR_SEL, 1
                MOVE    SHR_EVC, R0
                MOVE    SHR_W_EVC, R1
                MOVE    SHR_EVC_N, R2
_SST_E          MOVE    @R0++, @R1++
                SUB     1, R2
                RBRA    _SST_E, !Z
                MOVE    SHR_W_STAT, R0
                MOVE    0x4D53, @R0++
                MOVE    SHR_GEN, R1
                MOVE    @R1, R1
                MOVE    SHR_UP, R2
                CMP     0, @R2
                RBRA    _SST_W, Z
                OR      SHR_ST_UP, R1
_SST_W          MOVE    R1, @R0++
                MOVE    SHR_PROTO, @R0
                DECRB
                RET

; SHR_CLOSE_ALL: free every lock and file, forget the directory cursor.
; All registers preserved.
SHR_CLOSE_ALL   INCRB
                MOVE    SHR_LOCKS, R0
                MOVE    SHR_LOCKS_N, R1
_SCA_L          MOVE    0, @R0
                ADD     SHR_LOCK_SZ, R0
                SUB     1, R1
                RBRA    _SCA_L, !Z
                MOVE    SHR_FILES, R0
                ADD     SHR_F_USED, R0
                MOVE    SHR_FILES_N, R1
_SCA_F          MOVE    0, @R0
                ADD     SHR_FILE_SZ, R0
                SUB     1, R1
                RBRA    _SCA_F, !Z
                MOVE    SHR_CVAL, R0
                MOVE    0, @R0
                DECRB
                RET

; SHR_TAKE_BUF: flush and release the SD sector buffer of the device handle of
; the external card that everybody else uses (see the header). All registers
; preserved.
SHR_TAKE_BUF    SYSCALL(enter, 1)
                MOVE    SDC_DEV1, R8
                RSUB    _SHR_RELDEV, 1
                SYSCALL(leave, 1)
                RET

; SHR_GIVE_BUF: release the buffer of SHARE_DEV. All registers preserved.
SHR_GIVE_BUF    SYSCALL(enter, 1)
                MOVE    SHARE_DEV, R8
                RSUB    _SHR_RELDEV, 1
                SYSCALL(leave, 1)
                RET

; _SHR_RELDEV: device handle R8, if mounted: flush the owner of the buffer,
; then nobody owns it. R8..R12 clobbered.
_SHR_RELDEV     CMP     0, @R8
                RBRA    _SRD_RET, Z
                RSUB    FAT32$FLUSH_OWNER, 1
                ADD     FAT32$DEV_BUFFERED_FDH, R8
                MOVE    0, @R8
_SRD_RET        RET

; SHR_MOUNT: mount the volume: the SD card on SHARE_DEV, /amiga as the root.
; All registers preserved.
SHR_MOUNT       SYSCALL(enter, 1)
                RSUB    SHR_TAKE_BUF, 1
                MOVE    SHARE_DEV, R8
                MOVE    0, @R8
                MOVE    1, R8                   ; the external card, mounted
                RSUB    SDC$MOUNT, 1            ; (R8: SDC_DEV1; M2M-UPSTREAM
                CMP     0, R9                   ; sd-host)
                RBRA    _SMT_ERR, !Z
                MOVE    SHARE_DEV, R9           ; a copy of its device handle:
                MOVE    FAT32$DEV_STRUCT_SIZE, R10  ; the volume needs its own
                SYSCALL(memcpy, 1)              ; current directory
                MOVE    SHARE_DEV, R8           ; (nobody owns the buffer)
                ADD     FAT32$DEV_BUFFERED_FDH, R8
                MOVE    0, @R8
                MOVE    SHARE_DEV, R8           ; the root: /amiga
                MOVE    SHR_DIRNAME, R9
                XOR     R10, R10
                RSUB    FAT32$CD, 1
                CMP     0, R9
                RBRA    _SMT_ERR, !Z
                MOVE    SHARE_DEV, R0
                ADD     FAT32$DEV_AD_1STCLUS_LO, R0
                MOVE    SHR_ROOTLOCK, R1        ; the lock of key 0
                MOVE    SHR_T_ROOT, @R1++
                MOVE    @R0++, @R1++            ; (AD_1STCLUS_HI follows LO)
                MOVE    @R0, @R1++
                MOVE    5, R2                   ; no entry address, no parent
_SMT_RL         MOVE    0, @R1++
                SUB     1, R2
                RBRA    _SMT_RL, !Z
                RSUB    SHR_CLOSE_ALL, 1
                RSUB    SHR_SPACE, 1
                MOVE    SHR_UP, R0
                MOVE    1, @R0
                RSUB    SHR_NEWGEN, 1
                RSUB    SHR_STATUS, 1
                RBRA    _SMT_RET, 1
_SMT_ERR        MOVE    SHARE_DEV, R8           ; no volume until the next
                MOVE    0, @R8                  ; card event
_SMT_RET        RSUB    SHR_GIVE_BUF, 1
                SYSCALL(leave, 1)
                RET

; SHR_SPACE: SHR_TOTAL and SHR_USED in 512-byte blocks, from the boot sector
; (total sectors) and the FSInfo sector (free clusters) of the volume. Without
; a valid free count, the volume counts as full. R8..R12 clobbered.
SHR_SPACE       INCRB
                MOVE    SHR_TOTAL, R0           ; defaults: 0 blocks
                MOVE    0, @R0++
                MOVE    0, @R0
                MOVE    SHR_USED, R0
                MOVE    0, @R0++
                MOVE    0, @R0
                MOVE    SHARE_DEV, R0
                ADD     FAT32$DEV_FS_LO, R0
                MOVE    @R0++, R4               ; R5:R4: the boot sector
                MOVE    @R0, R5
                MOVE    R4, R8
                MOVE    R5, R9
                RSUB    SHR_BLOCK, 1
                RBRA    _SSP_RET, C
                MOVE    0x0020, R8              ; total sectors (32 bit)
                RSUB    SHR_SDDW, 1
                MOVE    SHR_TOTAL, R0
                MOVE    R8, @R0++
                MOVE    R9, @R0
                MOVE    R8, R6                  ; R7:R6: total
                MOVE    R9, R7
                MOVE    SHR_USED, R0            ; full until proven otherwise
                MOVE    R8, @R0++
                MOVE    R9, @R0
                MOVE    0x0030, R8              ; the FSInfo sector
                RSUB    _SHR_SDW, 1
                ADD     R8, R4
                ADDC    0, R5
                MOVE    R4, R8
                MOVE    R5, R9
                RSUB    SHR_BLOCK, 1
                RBRA    _SSP_RET, C
                MOVE    0x01E8, R8              ; free clusters
                RSUB    SHR_SDDW, 1
                CMP     0xFFFF, R9              ; unknown (0xFFFFFFFF)
                RBRA    _SSP_RET, Z
                MOVE    SHARE_DEV, R0           ; blocks = clusters x
                ADD     FAT32$DEV_SECT_PER_CLUS, R0
                MOVE    @R0, R0                 ; sectors per cluster
_SSP_MUL        CMP     R0, 1
                RBRA    _SSP_SUB, !N            ; (R0 <= 1)
                ADD     R8, R8
                ADDC    R9, R9
                AND     0xFFFB, SR              ; (shift right: clear C)
                SHR     1, R0
                AND     0x7FFF, R0
                RBRA    _SSP_MUL, 1
_SSP_SUB        CMP     R9, R7                  ; free > total: full
                RBRA    _SSP_RET, N             ; (R9 > R7, unsigned)
                RBRA    _SSP_S1, !Z
                CMP     R8, R6
                RBRA    _SSP_RET, N             ; (R8 > R6, unsigned)
_SSP_S1         SUB     R8, R6                  ; used = total - free
                SUBC    R9, R7
                MOVE    SHR_USED, R0
                MOVE    R6, @R0++
                MOVE    R7, @R0
_SSP_RET        DECRB
                RET

; SHR_BLOCK: read the SD block R9:R8 into the sector buffer of the controller.
; C=1 on an error. R8..R12 clobbered.
SHR_BLOCK       MOVE    FAT32$DEV_BLOCK_READ, R10
                MOVE    SHARE_DEV, R11
                RSUB    FAT32$CALL_DEV, 1
                CMP     0, R8
                RBRA    _SBL_ERR, !Z
                AND     0xFFFB, SR              ; C=0
                RET
_SBL_ERR        OR      0x0004, SR              ; C=1
                RET

; _SHR_SDB: byte R8 of the sector buffer -> R8. _SHR_SDW: little-endian word
; at R8 -> R8. SHR_SDDW: little-endian double word at R8 -> R9:R8.
; R9 clobbered (SDB, SDW), R10 clobbered (SDDW).
_SHR_SDB        MOVE    IO$SD_DATA_POS, R9
                MOVE    R8, @R9
                MOVE    IO$SD_DATA, R9
                MOVE    @R9, R8
                AND     0x00FF, R8
                RET
_SHR_SDW        MOVE    R8, @--SP
                ADD     1, R8                   ; high byte
                RSUB    _SHR_SDB, 1
                SWAP    R8, R9
                MOVE    @SP++, R8               ; low byte
                MOVE    R9, @--SP
                RSUB    _SHR_SDB, 1
                OR      @SP++, R8
                RET
SHR_SDDW        MOVE    R8, R10
                ADD     2, R8
                RSUB    _SHR_SDW, 1
                MOVE    R8, @--SP               ; the high word
                MOVE    R10, R8
                RSUB    _SHR_SDW, 1
                MOVE    @SP++, R9
                RET

; ----------------------------------------------------------------------------
; Shared folder: requests
; ----------------------------------------------------------------------------

; SHR_REQUEST: answer the request in the shared memory. All registers
; preserved; the shared memory is selected on return.
SHR_REQUEST     SYSCALL(enter, 1)
                MOVE    SHR_UP, R0              ; no volume: no disk
                CMP     0, @R0
                RBRA    _SRQ_UP, !Z
                MOVE    SHR_E_NODISK, R8
                RBRA    _SRQ_ANS, 1
_SRQ_UP         RSUB    SHR_TAKE_BUF, 1
                RSUB    SHR_SEL, 1
                MOVE    1, R8                   ; the packet type
                RSUB    SHR_RL, 1
                MOVE    SHR_ACTIONS, R0
_SRQ_L          MOVE    @R0++, R1
                CMP     0xFFFF, R1
                RBRA    _SRQ_UNK, Z
                MOVE    @R0++, R2
                CMP     R1, R10
                RBRA    _SRQ_L, !Z
                CMP     0, R9
                RBRA    _SRQ_L, !Z
                ASUB    R2, 1                   ; R8: error code
                RBRA    _SRQ_GIVE, 1
_SRQ_UNK        MOVE    SHR_E_UNKNOWN, R8
_SRQ_GIVE       RSUB    SHR_GIVE_BUF, 1

_SRQ_ANS        RSUB    SHR_SEL, 1              ; success and error code
                MOVE    R8, R10
                XOR     R9, R9
                CMP     0, R10
                RBRA    _SRQ_A1, !V             ; (negative: -1 etc.)
                MOVE    0xFFFF, R9
_SRQ_A1         MOVE    2, R8
                RSUB    SHR_WL, 1
                XOR     R9, R9
                XOR     R11, R11
                CMP     0, R10
                RBRA    _SRQ_A2, !Z
                MOVE    1, R11
_SRQ_A2         MOVE    R11, R10
                MOVE    1, R8
                RSUB    SHR_WL, 1
                SYSCALL(leave, 1)
                RET

; SHR_RL: field R8 of the request -> R9 (high), R10 (low). SHR_WL: R9:R10 ->
; field R8 of the response. Expect the shared memory selected. R8 preserved.
SHR_RL          MOVE    R8, R10
                ADD     R10, R10
                ADD     SHR_W_REQ, R10
                MOVE    @R10++, R9
                MOVE    @R10, R10
                RET
SHR_WL          MOVE    R8, @--SP
                ADD     R8, R8
                ADD     SHR_W_REQ, R8
                MOVE    R9, @R8++
                MOVE    R10, @R8
                MOVE    @SP++, R8
                RET

; SHR_GETB: byte R8 of the shared memory -> R9. SHR_PUTB: R9 -> byte R8.
; Expect the shared memory selected. R8 preserved; R10 clobbered (PUTB: R9).
SHR_GETB        MOVE    R8, R10
                AND     0xFFFB, SR              ; (shift right: clear C)
                SHR     1, R10
                ADD     SHR_W_BYTES, R10
                MOVE    @R10, R9
                MOVE    R8, R10
                AND     1, R10
                RBRA    _SGB_LO, !Z
                SWAP    R9, R9
_SGB_LO         AND     0x00FF, R9
                RET
SHR_PUTB        MOVE    R11, @--SP
                MOVE    R8, R10
                AND     0xFFFB, SR
                SHR     1, R10
                ADD     SHR_W_BYTES, R10
                MOVE    @R10, R11
                AND     0x00FF, R9
                MOVE    R8, @--SP
                AND     1, R8
                RBRA    _SPB_LO, !Z
                AND     0x00FF, R11             ; even byte: bits 15:8
                SWAP    R9, R9
                RBRA    _SPB_W, 1
_SPB_LO         AND     0xFF00, R11             ; odd byte: bits 7:0
_SPB_W          OR      R9, R11
                MOVE    R11, @R10
                MOVE    @SP++, R8
                MOVE    @SP++, R11
                RET

; SHR_GETNAME: the BSTR at byte R8 of the shared memory -> SHR_PATH (one
; character per word), SHR_PATH_LEN. R8..R12 clobbered.
SHR_GETNAME     INCRB
                MOVE    R8, R0
                RSUB    SHR_GETB, 1
                MOVE    R9, R1                  ; R1: length
                MOVE    SHR_PATH_LEN, R2
                MOVE    R1, @R2
                MOVE    SHR_PATH, R2
_SGN_L          CMP     0, R1
                RBRA    _SGN_RET, Z
                ADD     1, R0
                MOVE    R0, R8
                RSUB    SHR_GETB, 1
                MOVE    R9, @R2++
                SUB     1, R1
                RBRA    _SGN_L, 1
_SGN_RET        DECRB
                RET

; SHR_PUTNAME: the zero-terminated name R8 (one character per word) as the
; BSTR at byte 44 of the shared memory (the file_name of the Examine
; responses), at most SHR_MAXNAME characters. R8..R12 clobbered.
SHR_PUTNAME     INCRB
                MOVE    R8, R0
                XOR     R1, R1                  ; R1: length
_SPN_L          CMP     0, @R0
                RBRA    _SPN_E, Z
                CMP     SHR_MAXNAME, R1
                RBRA    _SPN_E, Z
                MOVE    @R0++, R9
                MOVE    45, R8
                ADD     R1, R8
                RSUB    SHR_PUTB, 1
                ADD     1, R1
                RBRA    _SPN_L, 1
_SPN_E          MOVE    44, R8
                MOVE    R1, R9
                RSUB    SHR_PUTB, 1
                DECRB
                RET

; SHR_KEY: field R8 of the request (a key) -> R8 (high), R9 (low).
; R10 clobbered.
SHR_KEY         RSUB    SHR_RL, 1
                MOVE    R9, R8
                MOVE    R10, R9
                RET

; SHR_LOCK_GET: the lock of key R8 (high):R9 (low) -> R8 = pointer to its slot
; (key 0: SHR_ROOTLOCK), C=0; or C=1 and R8 = error code. R9, R10 clobbered.
SHR_LOCK_GET    MOVE    R8, R10
                OR      R9, R10
                RBRA    _SLG_KEY, !Z
                MOVE    SHR_ROOTLOCK, R8
                RBRA    _SLG_OK, 1
_SLG_KEY        MOVE    SHR_GEN, R10
                CMP     @R10, R8
                RBRA    _SLG_SLOT, Z
                MOVE    SHR_E_NOTMNT, R8        ; a lock of another volume
                RBRA    _SLG_ERR, 1
_SLG_SLOT       SUB     1, R9
                CMP     SHR_LOCKS_N, R9
                RBRA    _SLG_INV, !N            ; (SHR_LOCKS_N <= R9 unsigned)
                MOVE    R9, R8
                AND     0xFFFD, SR              ; (x 8: clear X)
                SHL     3, R8
                ADD     SHR_LOCKS, R8
                CMP     0, @R8
                RBRA    _SLG_OK, !Z
_SLG_INV        MOVE    SHR_E_LOCK, R8
_SLG_ERR        OR      0x0004, SR              ; C=1
                RET
_SLG_OK         AND     0xFFFB, SR              ; C=0
                RET

; SHR_LOCK_NEW: a new lock of the object SHR_OT -> R9 (high), R10 (low) = its
; key, C=0; or C=1 and R8 = error code (no free slot). R11 clobbered.
SHR_LOCK_NEW    MOVE    SHR_LOCKS, R11
                XOR     R10, R10
_SLN_L          CMP     0, @R11
                RBRA    _SLN_F, Z
                ADD     SHR_LOCK_SZ, R11
                ADD     1, R10
                CMP     SHR_LOCKS_N, R10
                RBRA    _SLN_L, !Z
                MOVE    SHR_E_NOMEM, R8
                OR      0x0004, SR              ; C=1
                RET
_SLN_F          MOVE    R8, @--SP
                MOVE    SHR_OT, R8
                MOVE    R11, R9
                RSUB    SHR_OBJ_CPY, 1
                MOVE    @SP++, R8
                ADD     1, R10
                MOVE    SHR_GEN, R9
                MOVE    @R9, R9
                AND     0xFFFB, SR              ; C=0
                RET

; SHR_OBJ_CPY: copy the object (lock slot layout, 8 words) R8 to R9.
; All registers preserved.
SHR_OBJ_CPY     INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    SHR_LOCK_SZ, R2
_SOC_L          MOVE    @R0++, @R1++
                SUB     1, R2
                RBRA    _SOC_L, !Z
                DECRB
                RET

; SHR_OBJ_LOAD: the object of the lock slot R8 -> SHR_OT. R8 preserved.
SHR_OBJ_LOAD    MOVE    R9, @--SP
                MOVE    SHR_OT, R9
                RSUB    SHR_OBJ_CPY, 1
                MOVE    @SP++, R9
                RET

; SHR_OBJ_DIR: SHR_OT := the directory with the first cluster R9:R8 (the
; root if that is /amiga), its entry address unknown. All registers kept.
SHR_OBJ_DIR     INCRB
                MOVE    SHR_OT, R0
                MOVE    SHR_T_DIR, @R0++
                MOVE    R8, @R0++
                MOVE    R9, @R0++
                MOVE    5, R1
_SOD_Z          MOVE    0, @R0++
                SUB     1, R1
                RBRA    _SOD_Z, !Z
                MOVE    SHR_ROOTLOCK, R0
                ADD     1, R0
                CMP     @R0++, R8
                RBRA    _SOD_RET, !Z
                CMP     @R0, R9
                RBRA    _SOD_RET, !Z
                MOVE    SHR_OT, R0
                MOVE    SHR_T_ROOT, @R0
_SOD_RET        DECRB
                RET

; SHR_KEY_OBJ: SHR_OT := the object of the key in field R8 of the request.
; C=1 and R8 = error code if the key is not valid. R8..R10 clobbered.
SHR_KEY_OBJ     RSUB    SHR_KEY, 1
                RSUB    SHR_LOCK_GET, 1
                RBRA    _SKO_RET, C
                RSUB    SHR_OBJ_LOAD, 1
                AND     0xFFFB, SR              ; C=0
_SKO_RET        RET

; ----------------------------------------------------------------------------
; Shared folder: directories and names
; ----------------------------------------------------------------------------

; SHR_DIR_GET: the first entry of the directory with the first cluster R9:R8
; whose slot number is R10 or higher (hidden entries, "." and ".." skipped)
; -> SHR_DE, SHR_CEA, SHR_CORD, R8 = 1; R8 = 0 if there is none. The
; directory cursor continues where it can. C=1 on a FAT32 error. R9..R12
; clobbered.
SHR_DIR_GET     INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    R10, R2                 ; R2: the slot number
                MOVE    SHR_CVAL, R3
                CMP     0, @R3
                RBRA    _SDG_OPEN, Z
                MOVE    SHR_CCLO, R3            ; (SHR_CCHI follows)
                CMP     @R3++, R0
                RBRA    _SDG_OPEN, !Z
                CMP     @R3, R1
                RBRA    _SDG_OPEN, !Z
                MOVE    SHR_CIDX, R3            ; not past it yet?
                CMP     @R3, R2
                RBRA    _SDG_L, !N              ; (SHR_CIDX <= R2)
_SDG_OPEN       MOVE    SHARE_DEV, R8           ; the directory becomes the
                MOVE    R8, R3                  ; current one of SHARE_DEV
                ADD     FAT32$DEV_AD_1STCLUS_LO, R3
                MOVE    R0, @R3++               ; (AD_1STCLUS_HI follows)
                MOVE    R1, @R3
                MOVE    SHR_CFDH, R9
                RSUB    FAT32$DIR_OPEN, 1
                CMP     0, R9
                RBRA    _SDG_ERR, !Z
                MOVE    SHR_CCLO, R3
                MOVE    R0, @R3++
                MOVE    R1, @R3
                MOVE    SHR_CIDX, R3
                MOVE    0, @R3
                MOVE    SHR_CCIX, R3            ; cluster 0 of the directory
                MOVE    0, @R3++
                MOVE    R0, @R3++               ; (SHR_CLCL)
                MOVE    R1, @R3
                MOVE    SHR_CVAL, R3
                MOVE    1, @R3
_SDG_L          RSUB    SHR_DIR_NEXT, 1
                RBRA    _SDG_ERR, C
                CMP     0, R8
                RBRA    _SDG_OK, Z              ; (the end)
                MOVE    SHR_CORD, R3
                CMP     R2, @R3                 ; slot number < R2: on
                RBRA    _SDG_L, N               ; (R2 > SHR_CORD)
_SDG_OK         AND     0xFFFB, SR              ; C=0
                DECRB
                RET
_SDG_ERR        MOVE    SHR_CVAL, R3
                MOVE    0, @R3
                OR      0x0004, SR              ; C=1
                DECRB
                RET

; SHR_DIR_NEXT: the next entry of the directory cursor (hidden entries and
; "." and ".." skipped) -> SHR_DE, its entry address SHR_CEA and slot number
; SHR_CORD, R8 = 1; R8 = 0 at the end. C=1 on a FAT32 error. R9..R12
; clobbered.
SHR_DIR_NEXT    INCRB
_SDN_L          MOVE    SHR_CFDH, R8
                MOVE    SHR_DE, R9
                MOVE    FAT32$FA_DEFAULT, R10
                RSUB    FAT32$DIR_LIST, 1
                CMP     0, R11
                RBRA    _SDN_ERR, !Z
                CMP     0, R10
                RBRA    _SDN_END, Z

                ; where it is: the cursor's handle points behind its short
                ; name slot (DIR_LIST moves the index on by 32)
                MOVE    SHR_CFDH, R0
                ADD     FAT32$FDH_CLUSTER_LO, R0
                MOVE    @R0++, R1               ; R2:R1: cluster
                MOVE    @R0++, R2
                MOVE    @R0++, R3               ; R3: sector (FDH_SECTOR)
                MOVE    @R0, R4                 ; R4: slot = (index - 32) / 32
                SUB     32, R4
                SHR     5, R4
                AND     0x000F, R4
                MOVE    SHR_CLCL, R0            ; a new cluster: count it
                CMP     @R0++, R1
                RBRA    _SDN_NC, !Z
                CMP     @R0, R2
                RBRA    _SDN_C, Z
_SDN_NC         RSUB    _SHR_CLSTEP, 1          ; count the clusters on the
                MOVE    SHR_CLCL, R0            ; way (DIR_LIST skips whole
                MOVE    R1, @R0++               ; clusters of deleted
                MOVE    R2, @R0                 ; entries)
_SDN_C          MOVE    SHR_CEA, R0             ; the entry address
                MOVE    R1, @R0++
                MOVE    R2, @R0++
                MOVE    R3, R5
                AND     0xFFFD, SR
                SHL     4, R5
                OR      R4, R5
                MOVE    R5, @R0
                MOVE    SHR_CCIX, R8            ; the slot number:
                MOVE    @R8, R8                 ; ((clusters x spc) +
                MOVE    SHARE_DEV, R9           ; sector) x 16 + slot
                ADD     FAT32$DEV_SECT_PER_CLUS, R9
                MOVE    @R9, R9
                SYSCALL(mulu, 1)                ; R10 (16 bits suffice:
                ADD     R3, R10                 ; FAT allows 65536 slots)
                AND     0xFFFD, SR
                SHL     4, R10
                OR      R4, R10
                MOVE    SHR_CORD, R0
                MOVE    R10, @R0
                RSUB    SHR_ISDOT, 1
                RBRA    _SDN_L, C
                MOVE    SHR_CORD, R0            ; the next slot number to
                MOVE    @R0, R1                 ; look at
                ADD     1, R1
                MOVE    SHR_CIDX, R0
                MOVE    R1, @R0
                MOVE    1, R8
                AND     0xFFFB, SR              ; C=0
                DECRB
                RET
_SDN_END        XOR     R8, R8
                AND     0xFFFB, SR              ; C=0
                DECRB
                RET
_SDN_ERR        MOVE    SHR_CVAL, R0
                MOVE    0, @R0
                OR      0x0004, SR              ; C=1
                DECRB
                RET

; _SHR_CLSTEP: SHR_CCIX += the number of steps in the cluster chain from
; SHR_CLCL to the cluster R2:R1 of the caller (SHR_DIR_NEXT). The FAT
; sectors pass through the sector buffer: the directory handle re-reads its
; sector on its next access. R8..R12 clobbered.
_SHR_CLSTEP     MOVE    SHR_CLCL, R8
                MOVE    @R8++, R5               ; R6:R5: the chain so far
                MOVE    @R8, R6
                MOVE    SHR_CFDH, R8            ; the buffer: nobody's
                RSUB    _F32_RELEASE_BUF, 1
                MOVE    0xFFFF, @--SP           ; the FAT sector cache of
                MOVE    0xFFFF, @--SP           ; _F32_FATNEXT
_SCS_L          MOVE    SHARE_DEV, R8
                MOVE    R5, R9
                MOVE    R6, R10
                MOVE    SP, R11
                RSUB    _F32_FATNEXT, 1         ; R11:R10: the next one
                MOVE    SHR_CCIX, R8
                ADD     1, @R8
                CMP     0, R9                   ; the end, or broken: stop
                RBRA    _SCS_E, !Z
                MOVE    R10, R5
                MOVE    R11, R6
                CMP     R5, R1
                RBRA    _SCS_L, !Z
                CMP     R6, R2
                RBRA    _SCS_L, !Z
_SCS_E          ADD     2, SP
                MOVE    SHR_CFDH, R8            ; (DIR_LIST owned it)
                MOVE    SHARE_DEV, R9
                ADD     FAT32$DEV_BUFFERED_FDH, R9
                MOVE    0, @R9
                RET

; SHR_ISDOT: C=1 if SHR_DE is "." or "..". R9 clobbered.
; (Results come back in C: RET is a MOVE, which changes Z and N.)
SHR_ISDOT       MOVE    SHR_DE, R9
                CMP     0x002E, @R9++
                RBRA    _SID_NO, !Z
                CMP     0, @R9                  ; "."
                RBRA    _SID_YES, Z
                CMP     0x002E, @R9++
                RBRA    _SID_NO, !Z
                CMP     0, @R9                  ; ".."
                RBRA    _SID_YES, Z
_SID_NO         AND     0xFFFB, SR              ; C=0
                RET
_SID_YES        OR      0x0004, SR              ; C=1
                RET

; SHR_DOTDOT: the first cluster of the parent of the directory R9:R8 (its
; ".." entry) -> R9:R8. C=1 on an error. The cursor is lost. R10..R12
; clobbered.
SHR_DOTDOT      INCRB
                MOVE    SHR_CVAL, R0
                MOVE    0, @R0
                MOVE    SHARE_DEV, R0
                ADD     FAT32$DEV_AD_1STCLUS_LO, R0
                MOVE    R8, @R0++
                MOVE    R9, @R0
                MOVE    SHARE_DEV, R8
                MOVE    SHR_CFDH, R9
                RSUB    FAT32$DIR_OPEN, 1
                CMP     0, R9
                RBRA    _SDD_ERR, !Z
_SDD_L          MOVE    SHR_CFDH, R8
                MOVE    SHR_DE, R9
                MOVE    FAT32$FA_DEFAULT, R10
                RSUB    FAT32$DIR_LIST, 1
                CMP     0, R11
                RBRA    _SDD_ERR, !Z
                CMP     0, R10
                RBRA    _SDD_ERR, Z             ; no ".."
                MOVE    SHR_DE, R9
                CMP     0x002E, @R9++
                RBRA    _SDD_L, !Z
                CMP     0x002E, @R9++
                RBRA    _SDD_L, !Z
                CMP     0, @R9
                RBRA    _SDD_L, !Z
                MOVE    SHR_DE, R0
                ADD     FAT32$DE_CLUS_LO, R0
                MOVE    @R0++, R8               ; (DE_CLUS_HI follows)
                MOVE    @R0, R9
                AND     0xFFFB, SR              ; C=0
                DECRB
                RET
_SDD_ERR        OR      0x0004, SR              ; C=1
                DECRB
                RET

; SHR_UPC: R8 in upper case (ASCII and ISO 8859-1). Other registers kept.
SHR_UPC         CMP     0x0061, R8
                RBRA    _SUC_RET, N             ; (R8 < 'a')
                CMP     R8, 0x007A
                RBRA    _SUC_UP, !N             ; (R8 <= 'z')
                CMP     0x00E0, R8
                RBRA    _SUC_RET, N             ; (R8 < 0xE0)
                CMP     R8, 0x00FE
                RBRA    _SUC_RET, N             ; (R8 > 0xFE)
                CMP     0x00F7, R8              ; (division sign)
                RBRA    _SUC_RET, Z
_SUC_UP         SUB     0x0020, R8
_SUC_RET        RET

; SHR_NAMEEQ: C=1 if the name in SHR_DE equals the path component SHR_CPOS,
; SHR_CLEN of SHR_PATH, ignoring case. R8..R12 clobbered.
SHR_NAMEEQ      INCRB
                MOVE    SHR_DE, R0
                MOVE    SHR_CPOS, R1
                MOVE    @R1, R1
                ADD     SHR_PATH, R1
                MOVE    SHR_CLEN, R2
                MOVE    @R2, R2
_SNE_L          CMP     0, R2
                RBRA    _SNE_END, Z
                MOVE    @R0++, R8
                CMP     0, R8
                RBRA    _SNE_NO, Z
                RSUB    SHR_UPC, 1
                MOVE    R8, R3
                MOVE    @R1++, R8
                RSUB    SHR_UPC, 1
                CMP     R3, R8
                RBRA    _SNE_NO, !Z
                SUB     1, R2
                RBRA    _SNE_L, 1
_SNE_END        CMP     0, @R0                  ; the names end together?
                RBRA    _SNE_NO, !Z
                OR      0x0004, SR              ; C=1
                DECRB
                RET
_SNE_NO         AND     0xFFFB, SR              ; C=0
                DECRB
                RET

; SHR_FIND: look up the component SHR_CPOS, SHR_CLEN in the directory R9:R8.
; Found: C=0, SHR_DE = its entry, SHR_CEA its entry address. Else C=1, R8 =
; error code. R9..R12 clobbered.
SHR_FIND        INCRB
                XOR     R10, R10
                RSUB    SHR_DIR_GET, 1
_SFI_L          RBRA    _SFI_NF, C
                CMP     0, R8
                RBRA    _SFI_NF, Z
                RSUB    SHR_NAMEEQ, 1
                RBRA    _SFI_OK, C
                RSUB    SHR_DIR_NEXT, 1
                RBRA    _SFI_L, 1
_SFI_OK         AND     0xFFFB, SR              ; C=0
                DECRB
                RET
_SFI_NF         MOVE    SHR_E_NOTFOUND, R8
                OR      0x0004, SR              ; C=1
                DECRB
                RET

; SHR_PARENT: SHR_OT := its parent directory. C=1 and R8 = error code for the
; root. R8..R12 clobbered.
SHR_PARENT      MOVE    SHR_OT, R8
                CMP     SHR_T_ROOT, @R8
                RBRA    _SPA_ROOT, Z
                CMP     SHR_T_FILE, @R8
                RBRA    _SPA_DIR, !Z
                MOVE    SHR_OC, R9              ; a file: its directory
                MOVE    @R9++, R8
                MOVE    @R9, R9
                RBRA    _SPA_SET, 1
_SPA_DIR        MOVE    SHR_OC, R9              ; a directory: ".."
                MOVE    @R9++, R8
                MOVE    @R9, R9
                RSUB    SHR_DOTDOT, 1
                RBRA    _SPA_NF, C
_SPA_SET        RSUB    SHR_OBJ_DIR, 1
                AND     0xFFFB, SR              ; C=0
                RET
_SPA_ROOT
_SPA_NF         MOVE    SHR_E_NOTFOUND, R8
                OR      0x0004, SR              ; C=1
                RET

; SHR_RESOLVE: SHR_OT := the object of the key in field R8 of the request and
; the path in SHR_PATH. AmigaDOS paths: "x:" anywhere means the root when
; nothing stands before the colon (":c/d"), otherwise the key's directory (a
; device, volume or assign name); "/" alone is the parent; a component is
; looked up ignoring case. C=1 and R8 = error code on a failure; if only the
; last component is missing, SHR_MISS = 1, SHR_OT is its directory and
; SHR_CPOS, SHR_CLEN is the component. R8..R12 clobbered.
SHR_RESOLVE     INCRB
                MOVE    SHR_MISS, R1
                MOVE    0, @R1
                RSUB    SHR_KEY_OBJ, 1
                RBRA    _SRS_ERR, C
                MOVE    SHR_PATH_LEN, R1
                MOVE    @R1, R1                 ; R1: length
                XOR     R2, R2                  ; R2: position
                MOVE    SHR_PATH, R3            ; a colon?
_SRS_C          CMP     R2, R1
                RBRA    _SRS_NOC, Z
                CMP     0x003A, @R3++
                RBRA    _SRS_COL, Z
                ADD     1, R2
                RBRA    _SRS_C, 1
_SRS_COL        CMP     0, R2                   ; ":..." is the root
                RBRA    _SRS_C1, !Z
                MOVE    SHR_ROOTLOCK, R8
                RSUB    SHR_OBJ_LOAD, 1
_SRS_C1         ADD     1, R2                   ; the path follows the colon
                RBRA    _SRS_LOOP, 1
_SRS_NOC        XOR     R2, R2

_SRS_LOOP       CMP     R2, R1                  ; the end of the path
                RBRA    _SRS_OK, Z
                MOVE    SHR_PATH, R3
                ADD     R2, R3
                CMP     0x002F, @R3             ; "/": the parent
                RBRA    _SRS_NAME, !Z
                ADD     1, R2
                RSUB    SHR_PARENT, 1
                RBRA    _SRS_ERR, C
                RBRA    _SRS_LOOP, 1

_SRS_NAME       MOVE    R2, R4                  ; R4: start of the component
_SRS_N1         ADD     1, R2
                CMP     R2, R1
                RBRA    _SRS_N2, Z
                ADD     1, R3
                CMP     0x002F, @R3
                RBRA    _SRS_N1, !Z
                MOVE    R2, R5                  ; its end; one "/" separates
                ADD     1, R2                   ; it from the next component
                RBRA    _SRS_N3, 1
_SRS_N2         MOVE    R2, R5
_SRS_N3         MOVE    SHR_CPOS, R6
                MOVE    R4, @R6
                SUB     R4, R5
                MOVE    SHR_CLEN, R6
                MOVE    R5, @R6
                MOVE    SHR_OT, R6              ; only directories have
                CMP     SHR_T_FILE, @R6         ; components
                RBRA    _SRS_INDIR, !Z
                MOVE    SHR_E_TYPE, R8
                RBRA    _SRS_ERR, 1
_SRS_INDIR      MOVE    SHR_OC, R6
                MOVE    @R6++, R8
                MOVE    @R6, R9
                RSUB    SHR_FIND, 1
                RBRA    _SRS_MISS, C
                MOVE    SHR_OC, R0              ; the directory searched:
                MOVE    @R0++, R7               ; R7 low, R6 high word
                MOVE    @R0, R6
                MOVE    SHR_DE, R0              ; a directory or a file?
                ADD     FAT32$DE_ATTRIB, R0
                MOVE    @R0, R0
                AND     FAT32$FA_DIR, R0
                RBRA    _SRS_FILE, Z
                MOVE    SHR_DE, R0
                ADD     FAT32$DE_CLUS_LO, R0
                MOVE    @R0++, R8
                MOVE    @R0, R9
                RSUB    SHR_OBJ_DIR, 1
                RBRA    _SRS_EA, 1
_SRS_FILE       MOVE    SHR_OT, R0              ; a file in the directory
                MOVE    SHR_T_FILE, @R0         ; (SHR_OC stays)
_SRS_EA         MOVE    SHR_OEA, R0             ; its entry address and
                MOVE    SHR_CEA, R8             ; directory
                MOVE    @R8++, @R0++
                MOVE    @R8++, @R0++
                MOVE    @R8, @R0++
                MOVE    R7, @R0++               ; (SHR_OPC follows SHR_OEA)
                MOVE    R6, @R0
                RBRA    _SRS_LOOP, 1

_SRS_MISS       CMP     SHR_E_NOTFOUND, R8      ; the last component is
                RBRA    _SRS_ERR, !Z            ; missing?
                CMP     R2, R1
                RBRA    _SRS_ERR, !Z
                MOVE    SHR_MISS, R0
                MOVE    1, @R0
                RBRA    _SRS_ERR, 1

_SRS_OK         AND     0xFFFB, SR              ; C=0
                DECRB
                RET
_SRS_ERR        OR      0x0004, SR              ; C=1
                DECRB
                RET

; SHR_OBJ_DE: the directory entry of the object SHR_OT (not the root) ->
; SHR_DE; SHR_OEA and SHR_OPC are known afterwards. C=1 and R8 = error code
; if it is not there (any more). R8..R12 clobbered.
SHR_OBJ_DE      INCRB
                MOVE    SHR_OEA, R0             ; the entry address known:
                MOVE    @R0++, R1               ; find it in its directory
                OR      @R0, R1
                RBRA    _SOE_DIR, Z
                MOVE    SHR_OPC, R0
                MOVE    @R0++, R8
                MOVE    @R0, R9
                XOR     R10, R10
                RSUB    SHR_DIR_GET, 1
_SOE_FL         RBRA    _SOE_NF, C
                CMP     0, R8
                RBRA    _SOE_NF, Z
                MOVE    SHR_CEA, R0
                MOVE    SHR_OEA, R1
                CMP     @R0++, @R1++
                RBRA    _SOE_FN, !Z
                CMP     @R0++, @R1++
                RBRA    _SOE_FN, !Z
                CMP     @R0, @R1
                RBRA    _SOE_OK, Z
_SOE_FN         RSUB    SHR_DIR_NEXT, 1
                RBRA    _SOE_FL, 1

_SOE_DIR        MOVE    SHR_OT, R0              ; a directory (address not
                CMP     SHR_T_FILE, @R0         ; known): the entry of its
                RBRA    _SOE_NF, Z              ; parent that has its cluster
                MOVE    SHR_OC, R0
                MOVE    @R0++, R8
                MOVE    @R0, R9
                MOVE    R8, R4
                MOVE    R9, R5
                RSUB    SHR_DOTDOT, 1
                RBRA    _SOE_NF, C
                MOVE    R8, R6                  ; R7:R6: the parent
                MOVE    R9, R7
                XOR     R10, R10
                RSUB    SHR_DIR_GET, 1
_SOE_L          RBRA    _SOE_NF, C
                CMP     0, R8
                RBRA    _SOE_NF, Z
                MOVE    SHR_DE, R0
                ADD     FAT32$DE_ATTRIB, R0
                MOVE    @R0, R1
                AND     FAT32$FA_DIR, R1
                RBRA    _SOE_N, Z
                ADD     FAT32$DE_CLUS_LO, R0    ; (DE_CLUS_LO = DE_ATTRIB + 9)
                SUB     FAT32$DE_ATTRIB, R0
                CMP     @R0++, R4
                RBRA    _SOE_N, !Z
                CMP     @R0, R5
                RBRA    _SOE_FD, Z
_SOE_N          RSUB    SHR_DIR_NEXT, 1
                RBRA    _SOE_L, 1
_SOE_FD         MOVE    SHR_OEA, R0             ; found: remember where
                MOVE    SHR_CEA, R1
                MOVE    @R1++, @R0++
                MOVE    @R1++, @R0++
                MOVE    @R1, @R0++
                MOVE    R6, @R0++               ; (SHR_OPC)
                MOVE    R7, @R0
_SOE_OK         AND     0xFFFB, SR              ; C=0
                DECRB
                RET
_SOE_NF         MOVE    SHR_E_NOTFOUND, R8
                OR      0x0004, SR              ; C=1
                DECRB
                RET

; SHR_EXFILL: the Examine response (fields 3..9 and the name) for the object
; SHR_OT; R8 = the disk key to return. R8 = error code (0 = OK). R9..R12
; clobbered.
SHR_EXFILL      INCRB
                MOVE    R8, R7                  ; R7: disk key
                MOVE    SHR_OT, R0
                CMP     SHR_T_ROOT, @R0
                RBRA    _SEF_ENT, !Z
                RSUB    SHR_SEL, 1              ; the root: the volume name,
                MOVE    SHR_VOLNAME, R8         ; no size, no date
                RSUB    SHR_PUTNAME, 1
                MOVE    SHR_T_ROOT, R1          ; R1: type (low word)
                XOR     R2, R2                  ; R2: high word of the type
                XOR     R3, R3                  ; R3: size lo, R4: size hi
                XOR     R4, R4
                XOR     R5, R5                  ; R5: protection
                MOVE    7, R8                   ; date 0
                XOR     R9, R9
                XOR     R10, R10
                RSUB    SHR_WL, 1
                MOVE    8, R8
                RSUB    SHR_WL, 1
                MOVE    9, R8
                RSUB    SHR_WL, 1
                RBRA    _SEF_W, 1

_SEF_ENT        RSUB    SHR_OBJ_DE, 1
                RBRA    _SEF_RET, C
                RBRA    _SEF_DE, 1

; SHR_EXFILL_DE: SHR_EXFILL for the entry in SHR_DE (R8 = disk key)
SHR_EXFILL_DE   INCRB
                MOVE    R8, R7
_SEF_DE         RSUB    SHR_SEL, 1
                MOVE    SHR_DE, R8
                RSUB    SHR_PUTNAME, 1
                RSUB    SHR_DATE, 1
                MOVE    SHR_DE, R0
                ADD     FAT32$DE_ATTRIB, R0
                MOVE    @R0++, R6               ; R6: attributes
                MOVE    @R0++, R3               ; (DE_SIZE_LO, DE_SIZE_HI)
                MOVE    @R0, R4
                XOR     R5, R5
                MOVE    R6, R0
                AND     FAT32$FA_READ_ONLY, R0
                RBRA    _SEF_T, Z
                MOVE    0x0005, R5              ; read-only: no write/delete
_SEF_T          MOVE    SHR_T_DIR, R1
                XOR     R2, R2
                MOVE    R6, R0
                AND     FAT32$FA_DIR, R0
                RBRA    _SEF_DIR, !Z
                MOVE    0xFFFD, R1              ; ST_FILE = -3
                MOVE    0xFFFF, R2
                RBRA    _SEF_W, 1
_SEF_DIR        XOR     R3, R3
                XOR     R4, R4

_SEF_W          MOVE    3, R8                   ; disk_key
                XOR     R9, R9
                MOVE    R7, R10
                RSUB    SHR_WL, 1
                MOVE    4, R8                   ; entry_type
                MOVE    R2, R9
                MOVE    R1, R10
                RSUB    SHR_WL, 1
                MOVE    5, R8                   ; size
                MOVE    R4, R9
                MOVE    R3, R10
                RSUB    SHR_WL, 1
                MOVE    6, R8                   ; protection
                XOR     R9, R9
                MOVE    R5, R10
                RSUB    SHR_WL, 1
                XOR     R8, R8
_SEF_RET        DECRB
                RET

; SHR_DATE: the date of SHR_DE as an AmigaOS DateStamp (days since 1978,
; minutes, ticks) in fields 7..9 of the response. R8..R12 clobbered.
SHR_DATE        INCRB
                MOVE    SHR_DE, R0
                ADD     FAT32$DE_YEAR, R0
                MOVE    @R0++, R1               ; R1: year
                MOVE    @R0++, R2               ; R2: month
                MOVE    @R0++, R3               ; R3: day
                MOVE    R1, R4                  ; R4: years since 1980
                SUB     1980, R4
                RBRA    _SDT_Y, !N
                XOR     R4, R4
_SDT_Y          MOVE    R4, R8                  ; days = 730 + 365 x years
                MOVE    365, R9                 ; + leap days before
                SYSCALL(mulu, 1)
                MOVE    R10, R5
                ADD     730, R5
                MOVE    R4, R6
                ADD     3, R6
                AND     0xFFFB, SR
                SHR     2, R6
                AND     0x3FFF, R6
                ADD     R6, R5
                CMP     R1, 2100                ; 2100 is no leap year
                RBRA    _SDT_M, !N              ; (R1 <= 2100)
                SUB     1, R5
_SDT_M          SUB     1, R2                   ; + days before the month
                AND     0x000F, R2
                CMP     R2, 11
                RBRA    _SDT_M1, !N             ; (R2 <= 11)
                XOR     R2, R2
_SDT_M1         MOVE    SHR_MDAYS, R6
                ADD     R2, R6
                ADD     @R6, R5
                CMP     2, R2                   ; March or later in a leap
                RBRA    _SDT_D, N               ; year: + 1 (2 > R2)
                MOVE    R1, R6
                AND     3, R6
                RBRA    _SDT_D, !Z
                CMP     2100, R1
                RBRA    _SDT_D, Z
                ADD     1, R5
_SDT_D          CMP     0, R3                   ; + day - 1
                RBRA    _SDT_D1, Z
                SUB     1, R3
_SDT_D1         ADD     R3, R5
                MOVE    7, R8                   ; days
                XOR     R9, R9
                MOVE    R5, R10
                RSUB    SHR_WL, 1
                MOVE    @R0++, R8               ; minutes = hour x 60 + minute
                MOVE    60, R9
                SYSCALL(mulu, 1)
                ADD     @R0++, R10
                MOVE    8, R8
                XOR     R9, R9
                RSUB    SHR_WL, 1
                MOVE    @R0, R8                 ; ticks = second x 50
                MOVE    50, R9
                SYSCALL(mulu, 1)
                MOVE    9, R8
                XOR     R9, R9
                RSUB    SHR_WL, 1
                DECRB
                RET

; SHR_FILE_GET: the open file of the handle in field 2 of the request -> R8 =
; its slot, C=0; or C=1 and R8 = error code. R9, R10 clobbered.
SHR_FILE_GET    MOVE    2, R8
                RSUB    SHR_KEY, 1
                MOVE    SHR_GEN, R10
                CMP     @R10, R8
                RBRA    _SFG_SLOT, Z
                MOVE    SHR_E_NOTMNT, R8
                RBRA    _SFG_ERR, 1
_SFG_SLOT       SUB     1, R9
                CMP     SHR_FILES_N, R9
                RBRA    _SFG_INV, !N            ; (SHR_FILES_N <= R9)
                MOVE    R9, R8                  ; x 24 = x 16 + x 8
                AND     0xFFFD, SR
                SHL     3, R8
                MOVE    R8, R10
                AND     0xFFFD, SR
                SHL     1, R8
                ADD     R10, R8
                ADD     SHR_FILES, R8
                MOVE    R8, R10
                ADD     SHR_F_USED, R10
                CMP     0, @R10
                RBRA    _SFG_INV, Z
                AND     0xFFFB, SR              ; C=0
                RET
_SFG_INV        MOVE    SHR_E_NOTFOUND, R8
_SFG_ERR        OR      0x0004, SR              ; C=1
                RET

; ----------------------------------------------------------------------------
; Shared folder: writing (the FAT32 write layer, fat32_write.asm)
; ----------------------------------------------------------------------------

; SHR_TIMEFAT: the Amiga time of the request (a DateStamp the handler puts at
; SHR_W_TIME: days since 1978, minutes, ticks) -> SHR_FDATE as FAT date and
; time. Dates before 1980 become 1980-01-01. R8..R12 clobbered.
SHR_TIMEFAT     INCRB
                RSUB    SHR_SEL, 1
                MOVE    SHR_W_TIME, R0
                ADD     1, R0
                MOVE    @R0, R1                 ; R1: days (low word)
                ADD     2, R0
                MOVE    @R0, R2                 ; R2: minutes
                ADD     2, R0
                MOVE    @R0, R3                 ; R3: ticks
                SUB     2, R0                   ; (days >= 65536: far future,
                SUB     3, R0                   ;  treated like 2157)
                MOVE    1978, R4                ; R4: year
_STF_Y          MOVE    365, R5                 ; R5: days of the year
                MOVE    R4, R6
                AND     3, R6
                RBRA    _STF_Y1, !Z
                CMP     2100, R4
                RBRA    _STF_Y1, Z
                ADD     1, R5
_STF_Y1         CMP     R5, R1                  ; days < year: this year
                RBRA    _STF_M, N               ; (R5 > R1)
                SUB     R5, R1
                ADD     1, R4
                CMP     2107, R4                ; FAT ends with 2107
                RBRA    _STF_Y, !Z
                MOVE    364, R1
_STF_M          XOR     R6, R6                  ; R6: month 0..11
_STF_ML         MOVE    SHR_MDAYS, R7           ; days in month R6: the
                ADD     R6, R7                  ; next start - this start,
                CMP     11, R6                  ; December: 31
                RBRA    _STF_DEC, Z
                MOVE    R7, R9
                ADD     1, R9
                MOVE    @R9, R8
                SUB     @R7, R8
                RBRA    _STF_M3, 1
_STF_DEC        MOVE    31, R8
_STF_M3         CMP     1, R6                   ; February in a leap year
                RBRA    _STF_M4, !Z
                CMP     365, R5
                RBRA    _STF_M4, Z
                ADD     1, R8
_STF_M4         CMP     R8, R1                  ; day in this month?
                RBRA    _STF_DT, N              ; (R8 > R1)
                SUB     R8, R1
                ADD     1, R6
                RBRA    _STF_ML, 1
_STF_DT         CMP     1980, R4                ; before 1980: 1980-01-01
                RBRA    _STF_D2, !N             ; (1980 <= R4)
                MOVE    1980, R4
                XOR     R6, R6
                XOR     R1, R1
_STF_D2         SUB     1980, R4                ; date = year << 9 | month
                AND     0xFFFD, SR              ; << 5 | day
                SHL     9, R4
                ADD     1, R6
                AND     0xFFFD, SR
                SHL     5, R6
                ADD     1, R1
                OR      R6, R4
                OR      R1, R4
                MOVE    SHR_FDATE, R0
                MOVE    R4, @R0++
                XOR     R4, R4                  ; hours = minutes / 60
_STF_H          CMP     60, R2
                RBRA    _STF_H1, N              ; (60 > R2)
                SUB     60, R2
                ADD     1, R4
                RBRA    _STF_H, 1
_STF_H1         XOR     R5, R5                  ; seconds / 2 = ticks / 100
_STF_S          CMP     100, R3
                RBRA    _STF_S1, N
                SUB     100, R3
                ADD     1, R5
                RBRA    _STF_S, 1
_STF_S1         AND     0x001F, R4              ; time = h << 11 | m << 5 |
                AND     0xFFFD, SR              ; s / 2
                SHL     11, R4
                AND     0xFFFD, SR
                SHL     5, R2
                OR      R2, R4
                AND     0x001F, R5
                OR      R5, R4
                MOVE    R4, @R0
                DECRB
                RET

; CFGS_PBSET_TMP: CFGS_PB for the directory R9:R8: the device, the directory, the
; time of the request; everything else 0. R8..R12 clobbered.
CFGS_PBSET_TMP      INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    CFGS_PB, R8              ; all 0 first
                MOVE    FAT32$PB_WS, R9
                XOR     R10, R10
                SYSCALL(memset, 1)
                MOVE    CFGS_PB, R2
                MOVE    SHARE_DEV, @R2++        ; PB_DEV
                MOVE    R0, @R2++               ; PB_DIR
                MOVE    R1, @R2
                RSUB    SHR_TIMEFAT, 1
                MOVE    SHR_FDATE, R0
                MOVE    CFGS_PB, R2
                ADD     FAT32$PB_DATE, R2
                MOVE    @R0++, @R2++
                MOVE    @R0, @R2
                MOVE    SHR_SPDIRTY, R0         ; something will change
                MOVE    1, @R0
                DECRB
                RET

; SHR_WERR: the FAT32 error code R9 as an AmigaDOS error code -> R8.
SHR_WERR        MOVE    SHR_E_FULL, R8
                CMP     FAT32$ERR_DISKFULL, R9
                RBRA    _SWE_RET, Z
                CMP     FAT32$ERR_DIRFULL, R9
                RBRA    _SWE_RET, Z
                MOVE    SHR_E_EXISTS, R8
                CMP     FAT32$ERR_EXISTS, R9
                RBRA    _SWE_RET, Z
                MOVE    SHR_E_NAME, R8
                CMP     FAT32$ERR_NAME, R9
                RBRA    _SWE_RET, Z
                MOVE    SHR_E_DIRNE, R8
                CMP     FAT32$ERR_NOTEMPTY, R9
                RBRA    _SWE_RET, Z
                MOVE    SHR_E_INUSE, R8
                CMP     FAT32$ERR_LOOP, R9
                RBRA    _SWE_RET, Z
                MOVE    SHR_E_NOTFOUND, R8
_SWE_RET        RET

; SHR_NAMECP: the path component SHR_CPOS, SHR_CLEN -> SHR_NAME (zero-
; terminated). R8..R10 clobbered.
SHR_NAMECP      MOVE    SHR_CPOS, R8
                MOVE    @R8, R8
                ADD     SHR_PATH, R8
                MOVE    SHR_CLEN, R9
                MOVE    @R9, R9
                MOVE    SHR_NAME, R10
_SNC_L          CMP     0, R9
                RBRA    _SNC_E, Z
                MOVE    @R8++, @R10++
                SUB     1, R9
                RBRA    _SNC_L, 1
_SNC_E          MOVE    0, @R10
                RET

; SHR_INUSE: C=1 if the object SHR_OT is in use: the Amiga has a lock on it
; or it is open (files: the same entry address, directories: the same
; cluster), or the core uses the file (SHR_COREUSE, SHR_DE must hold its
; entry). R8..R12 clobbered.
SHR_INUSE       INCRB
                MOVE    SHR_LOCKS, R0           ; the locks
                MOVE    SHR_LOCKS_N, R1
_SIU_L          CMP     0, @R0
                RBRA    _SIU_N, Z
                MOVE    R0, R8
                RSUB    _SHR_SAMEOBJ, 1
                RBRA    _SIU_YES, C
_SIU_N          ADD     SHR_LOCK_SZ, R0
                SUB     1, R1
                RBRA    _SIU_L, !Z
                MOVE    SHR_FILES, R0           ; the open files
                MOVE    SHR_FILES_N, R1
_SIU_F          MOVE    R0, R8
                ADD     SHR_F_USED, R8
                CMP     0, @R8
                RBRA    _SIU_FN, Z
                MOVE    R0, R8
                ADD     SHR_F_OBJ, R8
                RSUB    _SHR_SAMEOBJ, 1
                RBRA    _SIU_YES, C
_SIU_FN         ADD     SHR_FILE_SZ, R0
                SUB     1, R1
                RBRA    _SIU_F, !Z
                MOVE    SHR_DE, R8              ; the core
                ADD     FAT32$DE_CLUS_LO, R8
                MOVE    @R8++, R9
                MOVE    @R8, R10
                RSUB    SHR_COREUSE, 1
                DECRB
                RET
_SIU_YES        DECRB
                OR      0x0004, SR              ; C=1
                RET

; _SHR_SAMEOBJ: C=1 if the object R8 (lock slot layout) is SHR_OT: a file
; with the same entry address, a directory with the same cluster.
; R8..R10 clobbered.
_SHR_SAMEOBJ    MOVE    SHR_OT, R9
                CMP     @R8, @R9                ; the same type?
                RBRA    _SSO_NO, !Z
                CMP     SHR_T_FILE, @R9
                RBRA    _SSO_DIR, !Z
                ADD     3, R8                   ; files: the entry address
                ADD     3, R9
                MOVE    3, R10
                RBRA    _SSO_L, 1
_SSO_DIR        ADD     1, R8                   ; directories: the cluster
                ADD     1, R9
                MOVE    2, R10
_SSO_L          CMP     @R8++, @R9++
                RBRA    _SSO_NO, !Z
                SUB     1, R10
                RBRA    _SSO_L, !Z
                OR      0x0004, SR              ; C=1
                RET
_SSO_NO         AND     0xFFFB, SR              ; C=0
                RET

; SHR_COREUSE: C=1 if the core uses the file with the first cluster R10:R9
; (0: never): a mounted disk image, a hard disk (or its link file), the
; settings file - on the external card (M2M-UPSTREAM sd-host: the shared
; folder's card; the core may use files on both cards). R8..R12 clobbered.
SHR_COREUSE     INCRB
                MOVE    R9, R0
                MOVE    R10, R1
                MOVE    R0, R2
                OR      R1, R2
                RBRA    _SCU_NO, Z
                XOR     R2, R2                  ; the disk images
_SCU_ADF        MOVE    ADF_FDH_VALID, R3
                ADD     R2, R3
                CMP     0, @R3
                RBRA    _SCU_AN, Z
                MOVE    ADF_FDH_TAB, R8
                ADD     R2, R8
                MOVE    @R8, R8
                RSUB    _SCU_FDH, 1
                RBRA    _SCU_YES, C
_SCU_AN         ADD     1, R2
                CMP     ADF_DRIVES, R2
                RBRA    _SCU_ADF, !Z
                MOVE    HDF_UNITS, R3           ; the hard disks: the active
                CMP     0, @R3                  ; drive in HDF_FDH, the other
                RBRA    _SCU_CFG, Z             ; one in HDF_SAVE
                MOVE    HDF_FDH, R8
                RSUB    _SCU_FDH, 1
                RBRA    _SCU_YES, C
                MOVE    HDF_SAVE, R8
                RSUB    _SCU_FDH, 1
                RBRA    _SCU_YES, C
_SCU_CFG        MOVE    CONFIG_FILE, R8         ; the settings file
                RSUB    _SCU_FDH, 1
                RBRA    _SCU_YES, C
_SCU_NO         DECRB
                AND     0xFFFB, SR              ; C=0
                RET
_SCU_YES        DECRB
                OR      0x0004, SR              ; C=1
                RET
; _SCU_FDH: C=1 if the file handle R8 is on the external card and starts at
; cluster R1:R0 (caller's bank). R11 clobbered.
_SCU_FDH        MOVE    R8, R11
                MOVE    @R11, R8                ; its device (0: none)
                RBRA    _SCF_NO, Z
                RSUB    SDC$SLOT, 1
                CMP     1, R8
                RBRA    _SCF_NO, !Z
                MOVE    R11, R8
                ADD     FAT32$FDH_START_CLUS_LO, R8
                CMP     @R8++, R0
                RBRA    _SCF_NO, !Z
                CMP     @R8, R1
                RBRA    _SCF_NO, !Z
                OR      0x0004, SR
                RET
_SCF_NO         AND     0xFFFB, SR
                RET

; ----------------------------------------------------------------------------
; Shared folder: the packet handlers (R8 = DOS error code on return)
; ----------------------------------------------------------------------------

; LOCATE_OBJECT: key, mode, name -> key
SHR_DO_LOCATE   MOVE    20, R8
                RSUB    SHR_GETNAME, 1
                MOVE    2, R8
                RSUB    SHR_RESOLVE, 1
                RBRA    _SDL_RET, C
_SDL_NEW        RSUB    SHR_LOCK_NEW, 1
                RBRA    _SDL_RET, C
                RSUB    SHR_SEL, 1
                MOVE    3, R8
                RSUB    SHR_WL, 1
                XOR     R8, R8
_SDL_RET        RET

; FREE_LOCK: key
SHR_DO_FREELOCK MOVE    2, R8
                RSUB    SHR_KEY, 1
                MOVE    R8, R10
                OR      R9, R10
                RBRA    _SDF_RET, Z             ; (the root lock is static)
                RSUB    SHR_LOCK_GET, 1
                RBRA    _SDF_RET, C
                MOVE    0, @R8
_SDF_RET        XOR     R8, R8
                RET

; COPY_DIR (DupLock): key -> key
SHR_DO_COPYDIR  MOVE    2, R8
                RSUB    SHR_KEY_OBJ, 1
                RBRA    _SDL_RET, C
                RBRA    _SDL_NEW, 1

; PARENT: key -> key of the parent, 0 for the root
SHR_DO_PARENT   MOVE    2, R8
                RSUB    SHR_KEY_OBJ, 1
                RBRA    _SDL_RET, C
                MOVE    SHR_OT, R8
                CMP     SHR_T_ROOT, @R8
                RBRA    _SDP_UP, !Z
                RSUB    SHR_SEL, 1
                MOVE    3, R8
                XOR     R9, R9
                XOR     R10, R10
                RSUB    SHR_WL, 1
                XOR     R8, R8
                RET
_SDP_UP         RSUB    SHR_PARENT, 1
                RBRA    _SDL_RET, C
                RBRA    _SDL_NEW, 1

; EXAMINE_OBJECT: key -> FileInfoBlock fields
SHR_DO_EXAMINE  MOVE    2, R8
                RSUB    SHR_KEY_OBJ, 1
                RBRA    _SDL_RET, C
                XOR     R8, R8                  ; the first ExNext: slot 0
                RBRA    SHR_EXFILL, 1           ; (returns from there)

; EXAMINE_NEXT: key, disk key (the slot number to go on from) -> the entry.
; Slot numbers do not change when entries are deleted or created, so a
; directory can be changed while it is examined (Delete #?).
SHR_DO_EXNEXT   MOVE    2, R8
                RSUB    SHR_KEY_OBJ, 1
                RBRA    _SDL_RET, C
                MOVE    SHR_OT, R8
                CMP     SHR_T_FILE, @R8
                RBRA    _SDX_DIR, !Z
_SDX_END        MOVE    SHR_E_NOMORE, R8
                RET
_SDX_DIR        MOVE    3, R8                   ; the slot number
                RSUB    SHR_RL, 1
                CMP     0, R9
                RBRA    _SDX_END, !Z
                MOVE    SHR_OC, R8
                MOVE    @R8++, R11
                MOVE    @R8, R9
                MOVE    R11, R8
                RSUB    SHR_DIR_GET, 1
                RBRA    _SDX_END, C
                CMP     0, R8
                RBRA    _SDX_END, Z
                MOVE    SHR_CORD, R8            ; the next ExNext: behind it
                MOVE    @R8, R8
                ADD     1, R8
                RBRA    SHR_EXFILL_DE, 1        ; (returns from there)

; EXAMINE_FH: file handle -> FileInfoBlock fields
SHR_DO_EXFH     RSUB    SHR_FILE_GET, 1
                RBRA    _SDL_RET, C
                MOVE    R8, R9                  ; write back what is buffered
                RSUB    _SHR_FSYNC, 1
                ADD     SHR_F_OBJ, R8
                RSUB    SHR_OBJ_LOAD, 1
                XOR     R8, R8
                RBRA    SHR_EXFILL, 1           ; (returns from there)

; _SHR_FSYNC: write back the file slot R9 (its buffer and, if it changed,
; its size). R8 preserved; R9..R12 clobbered.
_SHR_FSYNC      MOVE    R8, @--SP
                MOVE    R9, @--SP
                MOVE    SHR_FDATE, R8           ; dated with this request
                RSUB    SHR_TIMEFAT, 1
                MOVE    CFGS_PB, R8
                ADD     FAT32$PB_DATE, R8
                MOVE    SHR_FDATE, R9
                MOVE    @R9++, @R8++
                MOVE    @R9, @R8
                MOVE    @SP++, R8
                MOVE    CFGS_PB, R9
                RSUB    FAT32$W_SYNC, 1
                MOVE    @SP++, R8
                RET

; FINDINPUT (Open MODE_OLDFILE): key, name -> file handle
SHR_DO_FINDIN   XOR     R12, R12                ; R12: 0 = existing only
                RBRA    _SDI_GO, 1
; FINDUPDATE (Open MODE_READWRITE): key, name -> file handle; a new file if
; there is none
SHR_DO_FINDUPD  MOVE    1, R12
                RBRA    _SDI_GO, 1
; FINDOUTPUT (Open MODE_NEWFILE): key, name -> file handle; an existing file
; becomes empty
SHR_DO_FINDOUT  MOVE    2, R12                  ; R12: 2 = make it empty
_SDI_GO         INCRB
                MOVE    R12, R7                 ; R7: the mode
                MOVE    16, R8
                RSUB    SHR_GETNAME, 1
                MOVE    2, R8
                RSUB    SHR_RESOLVE, 1
                RBRA    _SDI_MISS, !C
                CMP     0, R7                   ; not there: create it?
                RBRA    _SDI_RET, Z
                MOVE    SHR_MISS, R0
                CMP     0, @R0
                RBRA    _SDI_RET, Z
                RSUB    SHR_NAMECP, 1
                MOVE    SHR_OC, R0              ; in the directory SHR_OT
                MOVE    @R0++, R8
                MOVE    @R0, R9
                RSUB    CFGS_PBSET_TMP, 1
                MOVE    CFGS_PB, R8
                ADD     FAT32$PB_NAME, R8
                MOVE    SHR_NAME, @R8++
                MOVE    FAT32$FA_ARCHIVE, @R8   ; (PB_ATTR)
                MOVE    CFGS_PB, R8
                RSUB    FAT32$W_CREATE, 1
                CMP     0, R9
                RBRA    _SDI_NEW, Z
                RSUB    SHR_WERR, 1
                RBRA    _SDI_RET, 1
_SDI_NEW        MOVE    SHR_OT, R0              ; the new file: its object
                MOVE    SHR_OC, R1
                MOVE    SHR_T_FILE, @R0
                MOVE    SHR_OEA, R0
                MOVE    CFGS_PB, R2
                ADD     FAT32$PB_EA, R2
                MOVE    @R2++, @R0++
                MOVE    @R2++, @R0++
                MOVE    @R2, @R0++
                MOVE    @R1++, @R0++            ; SHR_OPC := SHR_OC
                MOVE    @R1, @R0
                XOR     R7, R7                  ; (it is empty already)
                RBRA    _SDI_FILE, 1
_SDI_MISS       MOVE    SHR_OT, R8              ; it is there: a file?
                CMP     SHR_T_FILE, @R8
                RBRA    _SDI_FILE, Z
                MOVE    SHR_E_TYPE, R8
                RBRA    _SDI_RET, 1

_SDI_FILE       MOVE    SHR_FILES, R0           ; a free file slot
                XOR     R1, R1
_SDI_L          MOVE    R0, R2
                ADD     SHR_F_USED, R2
                CMP     0, @R2
                RBRA    _SDI_F, Z
                ADD     SHR_FILE_SZ, R0
                ADD     1, R1
                CMP     SHR_FILES_N, R1
                RBRA    _SDI_L, !Z
                MOVE    SHR_E_NOMEM, R8
                RBRA    _SDI_RET, 1
_SDI_F          MOVE    SHR_OPC, R2             ; open it from its address
                MOVE    @R2++, R8
                MOVE    @R2, R9
                CMP     2, R7
                RBRA    _SDI_F1, Z
                MOVE    CFGS_PB, R2              ; (no PB_SET: no time needed)
                MOVE    SHARE_DEV, @R2++
                MOVE    R8, @R2++
                MOVE    R9, @R2
                RBRA    _SDI_F2, 1
_SDI_F1         RSUB    CFGS_PBSET_TMP, 1
_SDI_F2         MOVE    SHR_OEA, R2
                MOVE    CFGS_PB, R3
                ADD     FAT32$PB_EA, R3
                MOVE    @R2++, @R3++
                MOVE    @R2++, @R3++
                MOVE    @R2, @R3
                MOVE    CFGS_PB, R8
                MOVE    R0, R9
                RSUB    FAT32$W_FDH, 1
                CMP     0, R9
                RBRA    _SDI_OPEN, Z
                RSUB    SHR_WERR, 1
                RBRA    _SDI_RET, 1
_SDI_OPEN       MOVE    1, R6                   ; R6: "used": 1, 3 = the core
                MOVE    R0, R8                  ; uses the file (read only)
                ADD     FAT32$FDH_START_CLUS_LO, R8
                MOVE    @R8++, R9
                MOVE    @R8, R10
                RSUB    SHR_COREUSE, 1
                RBRA    _SDI_O1, !C
                MOVE    3, R6
_SDI_O1         CMP     2, R7                   ; make it empty?
                RBRA    _SDI_O2, !Z
                MOVE    SHR_E_INUSE, R8
                CMP     3, R6
                RBRA    _SDI_RET, Z
                MOVE    R0, R8
                MOVE    CFGS_PB, R9
                XOR     R10, R10
                XOR     R11, R11
                RSUB    FAT32$W_SETSIZE, 1
                CMP     0, R9
                RBRA    _SDI_O2, Z
                RSUB    SHR_WERR, 1
                RBRA    _SDI_RET, 1
_SDI_O2         MOVE    SHR_OT, R8              ; the object, for EXAMINE_FH
                MOVE    R0, R9
                ADD     SHR_F_OBJ, R9
                RSUB    SHR_OBJ_CPY, 1
                MOVE    R0, R8
                ADD     SHR_F_USED, R8
                MOVE    R6, @R8
                RSUB    SHR_SEL, 1
                MOVE    3, R8
                MOVE    SHR_GEN, R9
                MOVE    @R9, R9
                MOVE    R1, R10
                ADD     1, R10
                RSUB    SHR_WL, 1
                XOR     R8, R8
_SDI_RET        DECRB
                RET

; READ: file handle, buffer address (ignored), length -> bytes read, in the
; data buffer at word 0x800. Sector by sector: FAT32$FILE_SEEK to the current
; position puts its sector into the sector buffer of the SD controller, and
; the bytes are copied straight from there (a library call per byte would cost
; ten times as much); then the position moves on in the file handle.
SHR_DO_READ     RSUB    SHR_FILE_GET, 1
                RBRA    _SDL_RET, C
                INCRB
                MOVE    R8, R0                  ; R0: the file handle
                MOVE    4, R8                   ; R1: length, at most 4 KB
                RSUB    SHR_RL, 1
                MOVE    R10, R1
                CMP     0, R9
                RBRA    _SDR_MAX, !Z
                CMP     R1, 0x1000
                RBRA    _SDR_GO, !N             ; (R1 <= 0x1000)
_SDR_MAX        MOVE    0x1000, R1
_SDR_GO         XOR     R2, R2                  ; R2: bytes read
                MOVE    SHR_W_DATA, R3          ; R3: next word
                XOR     R4, R4                  ; R4: high byte waiting

_SDR_SECT       CMP     R2, R1                  ; done?
                RBRA    _SDR_DONE, Z
                MOVE    R0, R8                  ; R7:R6 = size - position
                ADD     FAT32$FDH_SIZE_LO, R8
                MOVE    @R8++, R6               ; (SIZE_HI, ACCESS_LO,
                MOVE    @R8++, R7               ;  ACCESS_HI follow)
                MOVE    @R8++, R9
                MOVE    @R8, R10
                SUB     R9, R6
                SUBC    R10, R7
                MOVE    R6, R8
                OR      R7, R8
                RBRA    _SDR_DONE, Z            ; the end of the file
                MOVE    R0, R8                  ; the sector of the position
                RSUB    FAT32$FILE_SEEK, 1      ; (R9, R10: the position)
                CMP     0, R9
                RBRA    _SDR_ERR, !Z
                MOVE    R0, R8                  ; R5: bytes from this sector:
                ADD     FAT32$FDH_INDEX, R8     ; 512 - index, at most the
                MOVE    @R8, R12                ; rest of the request and of
                MOVE    512, R5                 ; the file
                SUB     R12, R5
                MOVE    R1, R8
                SUB     R2, R8
                CMP     R5, R8
                RBRA    _SDR_N1, !N             ; (R5 <= R8)
                MOVE    R8, R5
_SDR_N1         CMP     0, R7
                RBRA    _SDR_N2, !Z
                CMP     R5, R6
                RBRA    _SDR_N2, !N             ; (R5 <= R6)
                MOVE    R6, R5
_SDR_N2         MOVE    R5, R6                  ; R6: bytes of this sector
                MOVE    R12, R7                 ; R7: index in the sector
                MOVE    IO$SD_DATA_POS, R10
                MOVE    IO$SD_DATA, R11
_SDR_B          MOVE    R7, @R10
                MOVE    @R11, R9
                ADD     1, R7
                AND     0x00FF, R9
                MOVE    R2, R12
                AND     1, R12
                RBRA    _SDR_ODD, !Z
                SWAP    R9, R4                  ; an even byte: bits 15:8
                RBRA    _SDR_NX, 1
_SDR_ODD        OR      R4, R9                  ; an odd byte completes the
                MOVE    R9, @R3++               ; word
_SDR_NX         ADD     1, R2
                SUB     1, R5
                RBRA    _SDR_B, !Z
                MOVE    R0, R8                  ; the file handle moves on
                ADD     FAT32$FDH_INDEX, R8     ; (an index of 512 is what
                MOVE    R7, @R8                 ; FAT32$FILE_RB leaves, too)
                MOVE    R0, R8
                ADD     FAT32$FDH_ACCESS_LO, R8
                ADD     R6, @R8++
                ADDC    0, @R8
                RBRA    _SDR_SECT, 1

_SDR_DONE       MOVE    R2, R5                  ; a last even byte
                AND     1, R5
                RBRA    _SDR_RES, Z
                MOVE    R4, @R3
_SDR_RES        MOVE    3, R8
                XOR     R9, R9
                MOVE    R2, R10
                RSUB    SHR_WL, 1
                XOR     R8, R8
                DECRB
                RET
_SDR_ERR        MOVE    SHR_E_NOTFOUND, R8
                DECRB
                RET

; WRITE: file handle, buffer address (ignored), length -> bytes written, from
; the data buffer at word 0x800. Like READ the other way round: FAT32$W_PUT
; puts the sector of the position into the sector buffer of the SD
; controller (and adds a cluster at the end of the file), the bytes go
; straight in, FAT32$W_ADV moves the position on. At the end, the new size
; goes into the directory entry (FAT32$W_SYNC).
SHR_DO_WRITE    RSUB    SHR_FILE_GET, 1
                RBRA    _SDL_RET, C
                INCRB
                MOVE    R8, R0                  ; R0: the file handle
                MOVE    R8, R1
                ADD     SHR_F_USED, R1
                MOVE    SHR_E_INUSE, R8         ; the core uses it
                CMP     3, @R1
                RBRA    _SDW_RET, Z
                MOVE    SHR_SPDIRTY, R1
                MOVE    1, @R1
                MOVE    4, R8                   ; R1: length, at most 4 KB
                RSUB    SHR_RL, 1
                MOVE    R10, R1
                CMP     0, R9
                RBRA    _SDW_MAX, !Z
                CMP     R1, 0x1000
                RBRA    _SDW_GO, !N             ; (R1 <= 0x1000)
_SDW_MAX        MOVE    0x1000, R1
_SDW_GO         XOR     R2, R2                  ; R2: bytes written
                MOVE    SHR_W_DATA, R3          ; R3: next word
_SDW_SECT       CMP     R2, R1                  ; done?
                RBRA    _SDW_DONE, Z
                MOVE    R0, R8
                MOVE    CFGS_PB, R9
                RSUB    FAT32$W_PUT, 1          ; R10: index, R11: room
                CMP     0, R9
                RBRA    _SDW_ERR, !Z
                MOVE    R1, R5                  ; R5: bytes now: the room,
                SUB     R2, R5                  ; at most what is left
                CMP     R5, R11
                RBRA    _SDW_N1, !N             ; (R5 <= R11)
                MOVE    R11, R5
_SDW_N1         MOVE    R5, R6                  ; R6: bytes of this sector
                MOVE    R10, R7                 ; R7: index in the sector
                MOVE    IO$SD_DATA_POS, R10
                MOVE    IO$SD_DATA, R11
_SDW_B          MOVE    R2, R12                 ; the byte: even = bits
                AND     1, R12                  ; 15:8 of the word
                RBRA    _SDW_ODD, !Z
                MOVE    @R3, R9
                SWAP    R9, R9
                RBRA    _SDW_W, 1
_SDW_ODD        MOVE    @R3++, R9
_SDW_W          AND     0x00FF, R9
                MOVE    R7, @R10
                MOVE    R9, @R11
                ADD     1, R7
                ADD     1, R2
                SUB     1, R5
                RBRA    _SDW_B, !Z
                MOVE    R0, R8
                MOVE    R6, R9
                RSUB    FAT32$W_ADV, 1
                RBRA    _SDW_SECT, 1
_SDW_DONE       MOVE    R0, R9                  ; the size, durable
                RSUB    _SHR_FSYNC, 1
                CMP     0, R9
                RBRA    _SDW_ERR, !Z
                MOVE    3, R8
                XOR     R9, R9
                MOVE    R2, R10
                RSUB    SHR_SEL, 1
                RSUB    SHR_WL, 1
                XOR     R8, R8
                RBRA    _SDW_RET, 1
_SDW_ERR        RSUB    SHR_WERR, 1
_SDW_RET        DECRB
                RET

; SEEK: file handle, position, mode (-1 start, 0 current, 1 end) -> the old
; position
SHR_DO_SEEK     RSUB    SHR_FILE_GET, 1
                RBRA    _SDL_RET, C
                INCRB
                MOVE    R8, R0                  ; R0: the file handle
                RSUB    _SHR_NEWPOS, 1          ; R2:R1: the new position
                RBRA    _SDS_ERR, C
                CMP     R2, R5                  ; past the end?
                RBRA    _SDS_ERR, N             ; (R2 > R5)
                RBRA    _SDS_GO, !Z
                CMP     R1, R4
                RBRA    _SDS_ERR, N             ; (R1 > R4)
_SDS_GO         MOVE    R0, R8
                MOVE    R1, R9
                MOVE    R2, R10
                RSUB    FAT32$FILE_SEEK, 1
                CMP     0, R9
                RBRA    _SDS_ERR, !Z
                MOVE    3, R8                   ; the old position
                MOVE    R7, R9
                MOVE    R6, R10
                RSUB    SHR_WL, 1
                XOR     R8, R8
                DECRB
                RET
_SDS_ERR        MOVE    SHR_E_SEEK, R8
                DECRB
                RET

; _SHR_NEWPOS: for the file handle R0 (caller's bank): R5:R4 := size, R7:R6
; := position, R2:R1 := the position that fields 3 (offset) and 4 (mode)
; of the request ask for; C=1 if the mode is unknown or the position is
; before the start. R3, R8..R10 clobbered.
_SHR_NEWPOS     MOVE    R0, R1
                ADD     FAT32$FDH_SIZE_LO, R1
                MOVE    @R1++, R4               ; R5:R4: size (SIZE_HI
                MOVE    @R1++, R5               ; follows, then ACCESS_LO/HI)
                MOVE    @R1++, R6               ; R7:R6: position
                MOVE    @R1, R7
                MOVE    4, R8                   ; mode
                RSUB    SHR_RL, 1
                MOVE    R10, R3
                MOVE    3, R8                   ; R2:R1 = offset
                RSUB    SHR_RL, 1
                MOVE    R10, R1
                MOVE    R9, R2
                CMP     0xFFFF, R3              ; OFFSET_BEGINNING
                RBRA    _SNP_ADD, Z
                CMP     0, R3                   ; OFFSET_CURRENT
                RBRA    _SNP_CUR, Z
                CMP     1, R3                   ; OFFSET_END
                RBRA    _SNP_ERR, !Z
                ADD     R4, R1
                ADDC    R5, R2
                RBRA    _SNP_ADD, 1
_SNP_CUR        ADD     R6, R1
                ADDC    R7, R2
_SNP_ADD        CMP     0, R2                   ; before the start?
                RBRA    _SNP_ERR, V             ; (signed 0 > R2)
                AND     0xFFFB, SR              ; C=0
                RET
_SNP_ERR        OR      0x0004, SR              ; C=1
                RET

; SET_FILE_SIZE: file handle, offset, mode -> the new size. The position
; stays, unless it is behind the new end (then it is the end).
SHR_DO_SETSIZE  RSUB    SHR_FILE_GET, 1
                RBRA    _SDL_RET, C
                INCRB
                MOVE    R8, R0                  ; R0: the file handle
                MOVE    R8, R1
                ADD     SHR_F_USED, R1
                MOVE    SHR_E_INUSE, R8         ; the core uses it
                CMP     3, @R1
                RBRA    _SDZ_RET, Z
                RSUB    _SHR_NEWPOS, 1          ; R2:R1: the new size
                MOVE    SHR_E_SEEK, R8
                RBRA    _SDZ_RET, C
                CMP     R2, R7                  ; the position stays, or is
                RBRA    _SDZ_P, N               ; the new end (R2 > R7)
                RBRA    _SDZ_PE, !Z
                CMP     R6, R1
                RBRA    _SDZ_P, !N              ; (position <= new size)
_SDZ_PE         MOVE    R1, R6
                MOVE    R2, R7
_SDZ_P          XOR     R8, R8                  ; (PB_SET for the time; the
                XOR     R9, R9                  ;  directory does not matter)
                RSUB    CFGS_PBSET_TMP, 1
                MOVE    R0, R8
                MOVE    CFGS_PB, R9
                MOVE    R1, R10
                MOVE    R2, R11
                RSUB    FAT32$W_SETSIZE, 1
                CMP     0, R9
                RBRA    _SDZ_SK, Z
                RSUB    SHR_WERR, 1
                RBRA    _SDZ_RET, 1
_SDZ_SK         MOVE    R0, R8                  ; back to the position
                MOVE    R6, R9
                MOVE    R7, R10
                RSUB    FAT32$FILE_SEEK, 1
                RSUB    SHR_SEL, 1
                MOVE    3, R8
                MOVE    R2, R9
                MOVE    R1, R10
                RSUB    SHR_WL, 1
                XOR     R8, R8
_SDZ_RET        DECRB
                RET

; END (Close): file handle
SHR_DO_END      RSUB    SHR_FILE_GET, 1
                RBRA    _SDE_RET, C
                MOVE    R8, R9
                RSUB    _SHR_FSYNC, 1
                ADD     SHR_F_USED, R8
                MOVE    0, @R8
_SDE_RET        XOR     R8, R8
                RET

; SAME_LOCK: key, key -> LOCK_SAME (0, success), LOCK_SAME_VOLUME (1) or
; LOCK_DIFFERENT (-1)
SHR_DO_SAMELOCK INCRB
                MOVE    2, R8
                RSUB    SHR_KEY, 1
                RSUB    SHR_LOCK_GET, 1
                RBRA    _SDM_DIFF, C
                RSUB    SHR_OBJ_LOAD, 1
                MOVE    3, R8
                RSUB    SHR_KEY, 1
                RSUB    SHR_LOCK_GET, 1
                RBRA    _SDM_DIFF, C
                RSUB    _SHR_SAMEOBJ, 1
                RBRA    _SDM_VOL, !C
                XOR     R8, R8
                DECRB
                RET
_SDM_VOL        MOVE    1, R8
                DECRB
                RET
_SDM_DIFF       MOVE    0xFFFF, R8
                DECRB
                RET

; INFO, DISK_INFO: -> total and used blocks
SHR_DO_INFO     MOVE    SHR_SPDIRTY, R8         ; changed: count again
                CMP     0, @R8
                RBRA    _SDN_S, Z
                MOVE    0, @R8
                RSUB    SHR_SPACE, 1
_SDN_S          RSUB    SHR_SEL, 1
                MOVE    SHR_TOTAL, R11
                MOVE    3, R8
                MOVE    @R11++, R10
                MOVE    @R11, R9
                RSUB    SHR_WL, 1
                MOVE    SHR_USED, R11
                MOVE    4, R8
                MOVE    @R11++, R10
                MOVE    @R11, R9
                RSUB    SHR_WL, 1
                MOVE    5, R8
                XOR     R9, R9
                XOR     R10, R10
                RSUB    SHR_WL, 1
                XOR     R8, R8
                RET

; DELETE_OBJECT: key, name. Not the root, nothing in use, no directory with
; entries; the clusters are freed.
SHR_DO_DELETE   MOVE    16, R8
                RSUB    SHR_GETNAME, 1
                MOVE    2, R8
                RSUB    SHR_RESOLVE, 1
                RBRA    _SDD_RET, C
                RSUB    _SHR_WOBJ, 1            ; its entry, not in use
                RBRA    _SDD_RET, C
                MOVE    SHR_OT, R8              ; a directory: empty?
                CMP     SHR_T_DIR, @R8
                RBRA    _SDD_GO, !Z
                MOVE    SHR_OC, R8
                MOVE    @R8++, R11
                MOVE    @R8, R9
                MOVE    R11, R8
                XOR     R10, R10
                RSUB    SHR_DIR_GET, 1
                RBRA    _SDD_GO, C
                CMP     0, R8
                RBRA    _SDD_GO, Z
                MOVE    SHR_E_DIRNE, R8
                RET
_SDD_GO         RSUB    _CFGS_PBOBJ, 1           ; PB: its directory, entry
                MOVE    CFGS_PB, R8
                ADD     FAT32$PB_FLAGS, R8
                MOVE    FAT32$WDF_FREE, @R8
                MOVE    CFGS_PB, R8
                RSUB    FAT32$W_DELETE, 1
                MOVE    SHR_CVAL, R8            ; (the cursor saw it)
                MOVE    0, @R8
                XOR     R8, R8
                CMP     0, R9
                RBRA    _SDD_RET, Z
                RSUB    SHR_WERR, 1
_SDD_RET        RET

; _SHR_WOBJ: the object SHR_OT is about to change: not the root, its entry
; (SHR_DE, SHR_OEA, SHR_OPC), not in use. C=1 and R8 = error code if not.
; R8..R12 clobbered.
_SHR_WOBJ       MOVE    SHR_OT, R8
                CMP     SHR_T_ROOT, @R8
                RBRA    _SWO_ROOT, Z
                RSUB    SHR_OBJ_DE, 1
                RBRA    _SWO_RET, C
                RSUB    SHR_INUSE, 1
                RBRA    _SWO_USE, C
                AND     0xFFFB, SR              ; C=0
_SWO_RET        RET
_SWO_USE        MOVE    SHR_E_INUSE, R8
                OR      0x0004, SR
                RET
_SWO_ROOT       MOVE    SHR_E_WPROT, R8         ; (the volume itself)
                OR      0x0004, SR
                RET

; _CFGS_PBOBJ: CFGS_PB for the entry of the object SHR_OT: its directory
; SHR_OPC, its entry address SHR_OEA. R8..R12 clobbered.
_CFGS_PBOBJ      MOVE    SHR_OPC, R8
                MOVE    @R8++, R11
                MOVE    @R8, R9
                MOVE    R11, R8
                RSUB    CFGS_PBSET_TMP, 1
                MOVE    SHR_OEA, R8
                MOVE    CFGS_PB, R9
                ADD     FAT32$PB_EA, R9
                MOVE    @R8++, @R9++
                MOVE    @R8++, @R9++
                MOVE    @R8, @R9
                RET

; CREATE_DIR: key, name -> the key of a lock on the new directory
SHR_DO_MKDIR    MOVE    16, R8
                RSUB    SHR_GETNAME, 1
                MOVE    2, R8
                RSUB    SHR_RESOLVE, 1
                RBRA    _SDK_MISS, C
                MOVE    SHR_E_EXISTS, R8
                RET
_SDK_MISS       MOVE    SHR_MISS, R9
                CMP     0, @R9
                RBRA    _SDK_RET, Z
                RSUB    SHR_NAMECP, 1
                MOVE    SHR_OC, R8
                MOVE    @R8++, R11
                MOVE    @R8, R9
                MOVE    R11, R8
                RSUB    CFGS_PBSET_TMP, 1
                MOVE    CFGS_PB, R8
                ADD     FAT32$PB_NAME, R8
                MOVE    SHR_NAME, @R8
                MOVE    CFGS_PB, R8
                RSUB    FAT32$W_MKDIR, 1
                CMP     0, R9
                RBRA    _SDK_NEW, Z
                RSUB    SHR_WERR, 1
_SDK_RET        RET
_SDK_NEW        MOVE    SHR_OC, R8              ; the object: the new
                MOVE    SHR_OPC, R9             ; directory, in SHR_OC
                MOVE    @R8++, @R9++
                MOVE    @R8, @R9
                MOVE    SHR_OT, R8
                MOVE    SHR_T_DIR, @R8++
                MOVE    CFGS_PB, R9
                ADD     FAT32$PB_CL_LO, R9
                MOVE    @R9++, @R8++            ; SHR_OC
                MOVE    @R9, @R8++
                MOVE    CFGS_PB, R9              ; SHR_OEA
                ADD     FAT32$PB_EA, R9
                MOVE    @R9++, @R8++
                MOVE    @R9++, @R8++
                MOVE    @R9, @R8
                MOVE    SHR_CVAL, R8
                MOVE    0, @R8
                RBRA    _SDL_NEW, 1

; SET_PROTECT: key, mask, name. FAT knows "read-only" only: it is set when
; the file must not be written or deleted (FIBF_WRITE or FIBF_DELETE).
SHR_DO_SETPROT  MOVE    20, R8
                RSUB    SHR_GETNAME, 1
                MOVE    2, R8
                RSUB    SHR_RESOLVE, 1
                RBRA    _SDT_RET, C
                MOVE    SHR_OT, R8              ; (the volume: nothing)
                CMP     SHR_T_ROOT, @R8
                RBRA    _SDT_OK, Z
                RSUB    SHR_OBJ_DE, 1
                RBRA    _SDT_RET, C
                RSUB    _CFGS_PBOBJ, 1
                MOVE    SHR_DE, R8              ; the attributes: read-only?
                ADD     FAT32$DE_ATTRIB, R8
                MOVE    @R8, R10
                AND     0x00FE, R10
                MOVE    3, R8                   ; the mask
                RSUB    SHR_RL, 1
                AND     0x0005, R10             ; (R10: mask low word)
                RBRA    _SDT_RW, Z
                MOVE    SHR_DE, R8
                ADD     FAT32$DE_ATTRIB, R8
                MOVE    @R8, R10
                OR      FAT32$FA_READ_ONLY, R10
                RBRA    _SDT_SET, 1
_SDT_RW         MOVE    SHR_DE, R8
                ADD     FAT32$DE_ATTRIB, R8
                MOVE    @R8, R10
                AND     0x00FE, R10
_SDT_SET        AND     0x00FF, R10             ; PB_FLAGS: the attributes in
                SWAP    R10, R10                ; the high byte
                OR      FAT32$WSF_ATTR, R10
                MOVE    CFGS_PB, R8
                ADD     FAT32$PB_FLAGS, R8
                MOVE    R10, @R8
                MOVE    CFGS_PB, R8
                RSUB    FAT32$W_SETDE, 1
                CMP     0, R9
                RBRA    _SDT_OK, Z
                RSUB    SHR_WERR, 1
                RET
_SDT_OK         XOR     R8, R8
_SDT_RET        RET

; SET_COMMENT: key, name, comment. FAT has no comments: the object has to
; exist, the comment is not kept (until the .uaem files).
SHR_DO_SETCOMM  MOVE    16, R8                  ; the name: length at byte
                RSUB    SHR_GETB, 1             ; 16, characters from 18
                MOVE    SHR_PATH_LEN, R8
                MOVE    R9, @R8
                MOVE    18, R8
                RSUB    _SHR_GETCH, 1
                MOVE    2, R8
                RSUB    SHR_RESOLVE, 1
                RBRA    _SDT_RET, C
                XOR     R8, R8
                RET

; _SHR_GETCH: SHR_PATH_LEN characters from byte R8 of the shared memory ->
; SHR_PATH. R8..R12 clobbered.
_SHR_GETCH      INCRB
                MOVE    R8, R0
                MOVE    SHR_PATH_LEN, R1
                MOVE    @R1, R1
                MOVE    SHR_PATH, R2
_SGC_L          CMP     0, R1
                RBRA    _SGC_RET, Z
                MOVE    R0, R8
                RSUB    SHR_GETB, 1
                MOVE    R9, @R2++
                ADD     1, R0
                SUB     1, R1
                RBRA    _SGC_L, 1
_SGC_RET        DECRB
                RET

; SET_DATE: key, DateStamp (fields 3..5), name (BSTR at byte 28)
SHR_DO_SETDATE  MOVE    28, R8
                RSUB    SHR_GETNAME, 1
                MOVE    2, R8
                RSUB    SHR_RESOLVE, 1
                RBRA    _SDT_RET, C
                MOVE    SHR_OT, R8
                CMP     SHR_T_ROOT, @R8
                RBRA    _SDT_OK, Z
                RSUB    SHR_OBJ_DE, 1
                RBRA    _SDT_RET, C
                RSUB    _CFGS_PBOBJ, 1
                RSUB    SHR_SEL, 1              ; the date of the request
                MOVE    SHR_W_REQ, R8           ; (fields 3..5) where
                ADD     6, R8                   ; SHR_TIMEFAT expects one
                MOVE    SHR_W_TIME, R9
                MOVE    @R8++, @R9++
                MOVE    @R8++, @R9++
                MOVE    @R8++, @R9++
                MOVE    @R8++, @R9++
                MOVE    @R8++, @R9++
                MOVE    @R8, @R9
                RSUB    SHR_TIMEFAT, 1
                MOVE    SHR_FDATE, R8
                MOVE    CFGS_PB, R9
                ADD     FAT32$PB_DATE, R9
                MOVE    @R8++, @R9++
                MOVE    @R8, @R9
                MOVE    CFGS_PB, R8
                ADD     FAT32$PB_FLAGS, R8
                MOVE    FAT32$WSF_TIME, @R8
                MOVE    CFGS_PB, R8
                RSUB    FAT32$W_SETDE, 1
                CMP     0, R9
                RBRA    _SDT_OK, Z
                RSUB    SHR_WERR, 1
                RET

; RENAME_OBJECT: key, target directory key, name length (byte 20), new name
; length (21), the names (from byte 22). The object keeps its locks and open files.
SHR_DO_RENAME   INCRB
                MOVE    20, R8                  ; the old name
                RSUB    SHR_GETB, 1
                MOVE    R9, R0                  ; R0: its length
                MOVE    SHR_PATH_LEN, R8
                MOVE    R9, @R8
                MOVE    22, R8
                RSUB    _SHR_GETCH, 1
                MOVE    2, R8
                RSUB    SHR_RESOLVE, 1
                RBRA    _SDO_RET, C
                MOVE    SHR_OT, R8
                CMP     SHR_T_ROOT, @R8
                RBRA    _SDO_WP, Z
                RSUB    SHR_OBJ_DE, 1
                RBRA    _SDO_RET, C
                MOVE    SHR_DE, R8              ; R7:R6: its first cluster
                ADD     FAT32$DE_CLUS_LO, R8
                MOVE    @R8++, R6
                MOVE    @R8, R7
                MOVE    SHR_OT, R8              ; keep the object
                MOVE    SHR_RNOBJ, R9
                RSUB    SHR_OBJ_CPY, 1

                MOVE    21, R8                  ; the new name
                RSUB    SHR_GETB, 1
                MOVE    SHR_PATH_LEN, R8
                MOVE    R9, @R8
                MOVE    22, R8
                ADD     R0, R8
                RSUB    _SHR_GETCH, 1
                MOVE    3, R8
                RSUB    SHR_RESOLVE, 1
                RBRA    _SDO_MISS, C
                MOVE    SHR_RNOBJ, R8          ; it exists: only allowed if
                RSUB    _SHR_SAMEOBJ, 1         ; it is the object itself
                RBRA    _SDO_EX, !C             ; (another case of letters)
                MOVE    SHR_OT, R8              ; then: its directory, its
                CMP     SHR_T_FILE, @R8         ; name from the path
                RBRA    _SDO_SD, Z
                MOVE    SHR_OPC, R8
                MOVE    SHR_OC, R9
                MOVE    @R8++, @R9++
                MOVE    @R8, @R9
_SDO_SD         RSUB    SHR_NAMECP, 1
                RBRA    _SDO_GO, 1
_SDO_EX         MOVE    SHR_E_EXISTS, R8
                RBRA    _SDO_RET, 1
_SDO_MISS       MOVE    SHR_MISS, R9
                CMP     0, @R9
                RBRA    _SDO_RET, Z
                RSUB    SHR_NAMECP, 1

                ; SHR_OC: the target directory, SHR_NAME: the new name
_SDO_GO         MOVE    SHR_OC, R1
                MOVE    @R1++, R2               ; R3:R2: the target directory
                MOVE    @R1, R3
                MOVE    SHR_RNOBJ, R8           ; back to the object; only
                RSUB    SHR_OBJ_LOAD, 1         ; the core matters (locks
                MOVE    R6, R9                  ; and open files move along)
                MOVE    R7, R10
                RSUB    SHR_COREUSE, 1
                RBRA    _SDO_CHK, !C
                MOVE    SHR_E_INUSE, R8
                RBRA    _SDO_RET, 1
_SDO_CHK        RSUB    _CFGS_PBOBJ, 1
                MOVE    CFGS_PB, R8
                ADD     FAT32$PB_NAME, R8
                MOVE    SHR_NAME, @R8
                MOVE    CFGS_PB, R8
                ADD     FAT32$PB_DIR2_LO, R8
                MOVE    R2, @R8++
                MOVE    R3, @R8
                MOVE    CFGS_PB, R8
                RSUB    FAT32$W_RENAME, 1
                CMP     0, R9
                RBRA    _SDO_UPD, Z
                RSUB    SHR_WERR, 1
                RBRA    _SDO_RET, 1

                ; locks and open files of the object follow it: new entry
                ; address and directory (files: also SHR_OC; open files:
                ; also the entry address in their FDH)
_SDO_UPD        MOVE    SHR_LOCKS, R4
                MOVE    SHR_LOCKS_N, R5
_SDO_UL         CMP     0, @R4
                RBRA    _SDO_UN, Z
                MOVE    R4, R8
                RSUB    _SHR_SAMEOBJ, 1
                RBRA    _SDO_UN, !C
                MOVE    R4, R8
                RSUB    _SHR_RNSET, 1
_SDO_UN         ADD     SHR_LOCK_SZ, R4
                SUB     1, R5
                RBRA    _SDO_UL, !Z
                MOVE    SHR_FILES, R4
                MOVE    SHR_FILES_N, R5
_SDO_FL         MOVE    R4, R8
                ADD     SHR_F_USED, R8
                CMP     0, @R8
                RBRA    _SDO_FN, Z
                MOVE    R4, R8
                ADD     SHR_F_OBJ, R8
                RSUB    _SHR_SAMEOBJ, 1
                RBRA    _SDO_FN, !C
                MOVE    R4, R8
                ADD     SHR_F_OBJ, R8
                RSUB    _SHR_RNSET, 1
                MOVE    CFGS_PB, R8              ; the FDH: FDH_EA
                ADD     FAT32$PB_EA, R8
                MOVE    R4, R9
                ADD     FAT32$FDH_EA_CL_LO, R9
                MOVE    @R8++, @R9++
                MOVE    @R8++, @R9++
                MOVE    @R8, @R9
_SDO_FN         ADD     SHR_FILE_SZ, R4
                SUB     1, R5
                RBRA    _SDO_FL, !Z
                MOVE    SHR_CVAL, R8
                MOVE    0, @R8
                XOR     R8, R8
                RBRA    _SDO_RET, 1
_SDO_WP         MOVE    SHR_E_WPROT, R8
_SDO_RET        DECRB
                RET

; _SHR_RNSET: the object R8 (a lock slot or the object of a file) is now at
; PB_EA in the directory R3:R2 of the caller (SHR_DO_RENAME). R8, R9 used.
_SHR_RNSET      CMP     SHR_T_FILE, @R8
                RBRA    _SRN_D, !Z
                ADD     1, R8                   ; a file: SHR_OC too
                MOVE    R2, @R8++
                MOVE    R3, @R8++
                RBRA    _SRN_E, 1
_SRN_D          ADD     3, R8
_SRN_E          MOVE    CFGS_PB, R9              ; the entry address
                ADD     FAT32$PB_EA, R9
                MOVE    @R9++, @R8++
                MOVE    @R9++, @R8++
                MOVE    @R9, @R8++
                MOVE    R2, @R8++               ; SHR_OPC
                MOVE    R3, @R8
                RET

; End of the shared folder bank

                .ORG    0x9000                  ; M2M$CODE_WIN
                .DW     0x4B01                  ; bank 1: BANK_F32W
#include "../../M2M/QNICE/monitor/fat32_write.asm"

                .ORG    0x9000                  ; M2M$CODE_WIN
                .DW     0x4B02                  ; bank 2: BANK_F32F
#include "../../M2M/QNICE/monitor/fat32_wfile.asm"

; ----------------------------------------------------------------------------
; Machine profiles: the files a profile remembers (Megamiga 0.6.1)
;
; The settings file keeps text (M2M-UPSTREAM cfg-strings, cfgstr.asm): per
; profile the Kickstart and the two hard disks the user loaded through the
; menu, as paths with the card in front (M2M-UPSTREAM sd-host, two slots:
; "SD0:" = the internal card, "SD1:" = the external one):
; "a1200.hdf0=SD1:/amiga/disks/work.hdf", "a1200.hdf1=SD0:partition:2". A
; path without the card is invalid (a missing file). PROFILE_APPLY loads them.
; This code is in code bank BANK_F32F (with the FAT32 write layer's file part,
; which has room), behind FAR_CALL stubs.
; ----------------------------------------------------------------------------

; Megamiga 0.7: the keys are lines of the active profile's file (profiles.asm,
; code bank 3: PRF_KGET / PRF_KSET work on its text, the key by its NUMBER
; (ROM id - PROF_HDF_ID): 0 hdf0, 1 hdf1, 2 kick, 3 ar3rom - a string of this bank could
; not be read there). (0.6.1..0.6.4: "a500.kick" & co. in the settings file.)
_PR_S_PART      .ASCII_W "partition:"           ; a value: an SD card partition
_PR_S_PLEN      .EQU    10

; _PR_KEY: the number of the key of ROM id R9 -> R8 (PRF_KGET / PRF_KSET).
; Other registers kept.
_PR_KEY         MOVE    R9, R8
                SUB     PROF_HDF_ID, R8
                RET

; B2_PROF_REMEMBER: the user loaded the file handle R8 (opened through the
; device handle of its card from its current directory) as ROM id R9
; (PROF_HDF_ID .. PROF_AR3_ID): the selected profile remembers its path. All
; registers preserved.
B2_PROF_REMEMBER SYSCALL(enter, 1)
                MOVE    R9, R1                  ; R1: ROM id
                MOVE    SF_VIRTUAL, R2          ; an SD card partition from the
                MOVE    @R2, R2                 ; browser (BROWSE_EXTRA: id =
                CMP     0, R2                   ; slot << 8 | its number):
                RBRA    _PRR_FILE, Z            ; "SDx:partition:N"
                SUB     1, R2
                MOVE    R2, R8
                SWAP    R8, R8
                AND     0x00FF, R8
                MOVE    PROF_PATH, R9
                RSUB    _PR_PUTCARD, 1          ; "SDx:"
                MOVE    _PR_S_PART, R8
                SYSCALL(strcpy, 1)
                ADD     _PR_S_PLEN, R9
                AND     0x00FF, R2
                ADD     0x0030, R2
                MOVE    R2, @R9++
                MOVE    0, @R9
                RBRA    _PRR_OK, 1
_PRR_FILE       RSUB    _PR_PATHOF, 1           ; PROF_PATH
                RBRA    _PRR_OK, C
                MOVE    PROF_PATH, R0           ; unknown: forget it (the
                MOVE    0, @R0                  ; standard file then)
_PRR_OK         MOVE    R1, R9
                RSUB    _PR_KEY, 1
                MOVE    PROF_PATH, R9
                RSUB    PRF_KSET, 1             ; (the active profile's text)
                SYSCALL(leave, 1)
                RET

; B2_PROF_FORGET: the selected profile forgets its file for ROM id R9 (SPACE
; ejected it). All registers preserved.
B2_PROF_FORGET  SYSCALL(enter, 1)
                MOVE    R9, R0                  ; R0: ROM id
                RSUB    _PR_KEY, 1
                MOVE    PROF_PATH, R9           ; the empty value removes it
                MOVE    0, @R9
                RSUB    PRF_KSET, 1             ; (the active profile's text)
                SYSCALL(leave, 1)
                RET

; B2_PROF_AR3 (PROFILE_APPLY): the Action Replay III ROM of profile R8 (R9: 0 =
; boot, 1 = a switch). One the profile remembers is loaded (the Amiga is held
; in reset meanwhile, a complete ROM cold-boots it); without one - or if it is
; not there - the loaded ROM stays, and at boot the line shows /amiga/ar3.rom
; if that was auto-loaded. All registers preserved.
B2_PROF_AR3     SYSCALL(enter, 1)
                MOVE    R9, R1                  ; R1: 1 = switch, 0 = boot
                MOVE    PROF_AR3_ID, R9         ; one the profile remembers?
                RSUB    B2_PROF_SAVED, 1        ; (C=1: open, R8: its name)
                RBRA    _PA3_LD, C
                CMP     0, R1                   ; none (or not there): the
                RBRA    _PA3_RET, !Z            ; loaded one stays; at boot
                MOVE    CRTROM_AUT_LDF, R8      ; the line shows ar3.rom if it
                ADD     AR3_AUTO_ID, R8         ; was loaded (C_CRTROMS_AUTO)
                CMP     0, @R8
                RBRA    _PA3_RET, Z
                MOVE    PN_AR3, R8
                RBRA    _PA3_NAME, 1
_PA3_LD         MOVE    R8, R3                  ; R3: its name
                MOVE    AEXP_DEV_AR3, R8        ; LOADING holds the Amiga
                MOVE    CRTROM_CSR_STATUS, R9   ; in reset
                MOVE    CRTROM_CSR_ST_LDNG, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    PROF_FDH, R8
                RSUB    AR3_PREP, 1             ; error: CSR back to IDLE
                CMP     0, R8
                RBRA    _PA3_ERR, !Z
                MOVE    AEXP_DEV_AR3, R8        ; OK: the cold boot
                MOVE    CRTROM_CSR_STATUS, R9
                MOVE    CRTROM_CSR_ST_OK, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    R3, R8
_PA3_NAME       MOVE    PROF_AR3_ID, R9
                RSUB    PROF_NAME, 1
                RBRA    _PA3_RET, 1
_PA3_ERR        MOVE    CRTROM_MAN_LDF, R8      ; a broken ROM (no cartridge):
                ADD     PROF_AR3_ID, R8         ; the menu shows <Load>
                MOVE    0, @R8
                MOVE    PROF_PEND, R8
                ADD     PROF_AR3_ID, R8
                SUB     PROF_HDF_ID, R8
                MOVE    0, @R8
_PA3_RET        SYSCALL(leave, 1)
                RET

; B2_PROF_SAVED: the active profile remembers a file for ROM id R9 and it opens
; (0.7: R8, the profile, is ignored):
; C=1, PROF_FDH is open, R8 = its name (for the menu line, in PROF_PNAME);
; C=0 otherwise, R8 = 0 if it remembers none, 1 if it cannot be opened.
; R9..R12 preserved.
B2_PROF_SAVED   INCRB
                MOVE    R9, R0                  ; R0: ROM id
                MOVE    R10, R1
                MOVE    R11, R2
                MOVE    R12, R3
                RSUB    _PR_KEY, 1
                MOVE    PROF_PATH, R9
                MOVE    128, R10
                RSUB    PRF_KGET, 1             ; (the active profile's text)
                RBRA    _PRS_NO, !C
                MOVE    PROF_PATH, R10
                CMP     0, @R10
                RBRA    _PRS_NO, Z
                RSUB    _PR_CARD, 1             ; "SDx:" -> R8: slot, R10: the
                RBRA    _PRS_NF, !C             ; rest (none: not there)
                MOVE    R8, R7                  ; R7: the slot
                RSUB    SDC$BLKDEV, 1           ; R8: the card's device
                CMP     0, R9                   ; (a partition needs no FAT32)
                RBRA    _PRS_NF, !Z
                MOVE    R8, R6                  ; R6: the device handle
                MOVE    R10, R4                 ; "partition:N"?
                MOVE    _PR_S_PART, R5
_PRS_PP         CMP     0, @R5
                RBRA    _PRS_PART, Z
                CMP     @R4++, @R5++
                RBRA    _PRS_PP, Z
                MOVE    R7, R8                  ; a file: FAT32 mounted?
                RSUB    SDC$MOUNT, 1
                CMP     0, R9
                RBRA    _PRS_NF, !Z
                MOVE    R6, R8
                MOVE    PROF_FDH, R9
                XOR     R11, R11                ; "/" separator
                SYSCALL(f32_fopen, 1)
                CMP     0, R10
                RBRA    _PRS_NF, !Z
                MOVE    PROF_PATH, R4           ; the name: behind the last
                MOVE    R4, R5                  ; "/"
_PRS_SL         CMP     0, @R4
                RBRA    _PRS_SE, Z
                CMP     0x002F, @R4++
                RBRA    _PRS_SL, !Z
                MOVE    R4, R5
                RBRA    _PRS_SL, 1
_PRS_SE         MOVE    R0, R4                  ; PROF_PNAME + (id - HDF id)
                SUB     PROF_HDF_ID, R4         ; x PROF_PN_LEN
                MOVE    R4, R8
                MOVE    PROF_PN_LEN, R9
                SYSCALL(mulu, 1)                ; R11:R10 = R8 x R9
                MOVE    R10, R6
                ADD     PROF_PNAME, R6
                MOVE    R6, R8                  ; R8: the name
                MOVE    PROF_PN_LEN, R7         ; (at most PROF_PN_LEN - 1
                SUB     1, R7                   ; characters: the menu line)
_PRS_NC         CMP     0, @R5
                RBRA    _PRS_NE, Z
                MOVE    @R5++, @R6++
                SUB     1, R7
                RBRA    _PRS_NC, !Z
_PRS_NE         MOVE    0, @R6
                MOVE    R1, R10
                MOVE    R2, R11
                MOVE    R3, R12
                MOVE    R0, R9
                DECRB
                OR      0x0004, SR              ; C=1
                RET
                ; an SD card partition: HDF_PREP mounts it (HDF_VPART = slot
                ; << 8 | number), the handle is an empty one on the device of
                ; the card (only its device counts)
_PRS_PART       CMP     PROF_KICK_ID, R0        ; (not a Kickstart, not an
                RBRA    _PRS_NF, Z              ; AR3 ROM)
                CMP     PROF_AR3_ID, R0
                RBRA    _PRS_NF, Z
                MOVE    @R4, R5                 ; the digit 1..4
                SUB     0x0031, R5
                CMP     R5, 3
                RBRA    _PRS_NF, N              ; (R5 > 3, also below "1")
                ADD     1, R5
                MOVE    R6, R8                  ; the slot of the device
                RSUB    SDC$SLOT, 1
                SWAP    R8, R8
                OR      R5, R8
                MOVE    HDF_VPART, R7
                MOVE    R8, @R7
                MOVE    PROF_FDH, R8
                MOVE    FAT32$FDH_STRUCT_SIZE, R9
                XOR     R10, R10
                SYSCALL(memset, 1)
                MOVE    PROF_FDH, R8
                MOVE    R6, @R8
                MOVE    BRX_S_PART, R8          ; its name: "Partition N"
                MOVE    PROF_PATH, R9
                SYSCALL(strcpy, 1)
                MOVE    R9, R6
                ADD     BRX_S_PLEN, R6
                ADD     0x0030, R5
                MOVE    R5, @R6++
                MOVE    0, @R6
                MOVE    PROF_PATH, R5
                RBRA    _PRS_SE, 1
_PRS_NF         MOVE    1, R8                   ; remembered, not there
                RBRA    _PRS_C0, 1
_PRS_NO         XOR     R8, R8                  ; none remembered
_PRS_C0         MOVE    R0, R9
                MOVE    R1, R10
                MOVE    R2, R11
                MOVE    R3, R12
                DECRB
                AND     0xFFFB, SR              ; C=0
                RET

; _PR_CARD: PROF_PATH starts with the card, "SD0:" or "SD1:" (M2M-UPSTREAM
; sd-host)? C=1: R8 = the slot, R10 = the rest of the path; C=0: no card.
; R9 clobbered.
_PR_CARD        MOVE    PROF_PATH, R10
                MOVE    @R10++, R9              ; "S" or "s"
                OR      0x0020, R9
                CMP     0x0073, R9
                RBRA    _PRC_NO, !Z
                MOVE    @R10++, R9              ; "D" or "d"
                OR      0x0020, R9
                CMP     0x0064, R9
                RBRA    _PRC_NO, !Z
                MOVE    @R10++, R8              ; "0" or "1"
                SUB     0x0030, R8
                CMP     R8, 1
                RBRA    _PRC_NO, N              ; (R8 > 1, also below "0")
                CMP     0x003A, @R10++          ; ":"
                RBRA    _PRC_NO, !Z
                OR      0x0004, SR              ; C=1
                RET
_PRC_NO         AND     0xFFFB, SR              ; C=0
                RET

; _PR_PUTCARD: "SDx:" for slot R8 at R9 -> R9 behind it (no terminator: the
; callers write the rest right behind it; a path that fills PROF_PATH starts
; exactly there). R8 preserved.
_PR_PUTCARD     MOVE    0x0053, @R9++
                MOVE    0x0044, @R9++
                MOVE    R8, @R9
                ADD     0x0030, @R9++
                MOVE    0x003A, @R9++
                RET

; _PR_PATHOF: the path of the file handle R8 (opened through the device handle
; of its card from the current directory of that, FDH_EA set by
; FAT32$FILE_OPEN) -> PROF_PATH with the card in front ("SD1:/amiga/x.hdf"),
; C=1; C=0 if it cannot be found or is longer than 127 characters. The names
; come from directory listings (PROF_FDH as the directory handle, SHR_DE as
; the entry): the file's own entry, then upwards through ".." - each directory
; by its cluster in its parent. All registers preserved.
_PR_PATHOF      SYSCALL(enter, 1)
                MOVE    R8, R7                  ; R7: the file handle
                MOVE    PROF_DEVP, R6           ; its device handle
                MOVE    @R7, @R6                ; (FAT32$FDH_DEVICE = 0)
                MOVE    @R6, R6
                ADD     FAT32$DEV_AD_1STCLUS_LO, R6
                MOVE    @R6++, R0               ; R1:R0: the current directory
                MOVE    @R6, R1                 ; (restored at the end)
                MOVE    R0, R2                  ; R3:R2: the directory now
                MOVE    R1, R3
                MOVE    PROF_PATH, R4           ; R4: the path, built from
                ADD     127, R4                 ; the end backwards
                MOVE    0, @R4

                ; the file's own name: the entry at its address
                RSUB    _PP_OPEN, 1
                RBRA    _PP_FAIL, !C
_PP_FL          RSUB    _PP_NEXT, 1
                RBRA    _PP_FAIL, !C
                MOVE    PROF_FDH, R8            ; its address (behind its
                ADD     FAT32$FDH_CLUSTER_LO, R8 ; short name slot)
                MOVE    R7, R9
                ADD     FAT32$FDH_EA_CL_LO, R9
                CMP     @R8++, @R9++
                RBRA    _PP_FL, !Z
                CMP     @R8++, @R9++
                RBRA    _PP_FL, !Z
                MOVE    @R8++, R10              ; sector << 4 | slot
                AND     0xFFFD, SR
                SHL     4, R10
                MOVE    @R8, R11
                SUB     32, R11
                SHR     5, R11
                AND     0x000F, R11
                OR      R11, R10
                CMP     @R9, R10
                RBRA    _PP_FL, !Z
                RSUB    _PP_PUT, 1
                RBRA    _PP_FAIL, !C

                ; the directories up to the root
_PP_UP          MOVE    PROF_DEVP, R8
                MOVE    @R8, R8
                ADD     FAT32$DEV_RD_1STCLUS_LO, R8
                CMP     @R8++, R2
                RBRA    _PP_PAR, !Z
                CMP     @R8, R3
                RBRA    _PP_DONE, Z
_PP_PAR         RSUB    _PP_OPEN, 1             ; its parent: ".."
                RBRA    _PP_FAIL, !C
_PP_DD          RSUB    _PP_NEXT, 1
                RBRA    _PP_FAIL, !C
                MOVE    SHR_DE, R8
                CMP     0x002E, @R8++
                RBRA    _PP_DD, !Z
                CMP     0x002E, @R8++
                RBRA    _PP_DD, !Z
                CMP     0, @R8
                RBRA    _PP_DD, !Z
                MOVE    R2, R5                  ; R6:R5: the directory
                MOVE    R3, R6
                MOVE    SHR_DE, R8
                ADD     FAT32$DE_CLUS_LO, R8
                MOVE    @R8++, R2               ; the parent (0: the root)
                MOVE    @R8, R3
                MOVE    R2, R8
                OR      R3, R8
                RBRA    _PP_P1, !Z
                MOVE    PROF_DEVP, R8
                MOVE    @R8, R8
                ADD     FAT32$DEV_RD_1STCLUS_LO, R8
                MOVE    @R8++, R2
                MOVE    @R8, R3
_PP_P1          RSUB    _PP_OPEN, 1             ; the directory's name in it
                RBRA    _PP_FAIL, !C
_PP_DN          RSUB    _PP_NEXT, 1
                RBRA    _PP_FAIL, !C
                MOVE    SHR_DE, R8
                ADD     FAT32$DE_ATTRIB, R8
                MOVE    @R8, R9
                AND     FAT32$FA_DIR, R9
                RBRA    _PP_DN, Z
                MOVE    SHR_DE, R8
                ADD     FAT32$DE_CLUS_LO, R8
                CMP     @R8++, R5
                RBRA    _PP_DN, !Z
                CMP     @R8, R6
                RBRA    _PP_DN, !Z
                RSUB    _PP_PUT, 1
                RBRA    _PP_FAIL, !C
                RBRA    _PP_UP, 1

                ; done: the card and the path to the start of PROF_PATH
_PP_DONE        MOVE    PROF_DEVP, R8
                MOVE    @R8, R8
                RSUB    SDC$SLOT, 1
                MOVE    PROF_PATH, R9
                RSUB    _PR_PUTCARD, 1
                MOVE    R9, R8
_PP_MV          MOVE    @R4++, R9
                MOVE    R9, @R8++
                CMP     0, R9
                RBRA    _PP_MV, !Z
                RSUB    _PP_END, 1
                SYSCALL(leave, 1)
                OR      0x0004, SR              ; C=1
                RET
_PP_FAIL        RSUB    _PP_END, 1
                SYSCALL(leave, 1)
                AND     0xFFFB, SR              ; C=0
                RET

; _PP_OPEN: the directory R3:R2 (caller's bank) as the current directory of
; the device PROF_DEVP, open in PROF_FDH. C=1 if OK. R8..R12 used.
_PP_OPEN        MOVE    PROF_DEVP, R8
                MOVE    @R8, R8
                ADD     FAT32$DEV_AD_1STCLUS_LO, R8
                MOVE    R2, @R8++
                MOVE    R3, @R8
                MOVE    PROF_DEVP, R8
                MOVE    @R8, R8
                MOVE    PROF_FDH, R9
                RSUB    FAT32$DIR_OPEN, 1
                CMP     0, R9
                RBRA    _PPO_NO, !Z
                OR      0x0004, SR
                RET
_PPO_NO         AND     0xFFFB, SR
                RET

; _PP_NEXT: the next entry (also hidden ones) -> SHR_DE. C=1 if there is one.
; R8..R12 used.
_PP_NEXT        MOVE    PROF_FDH, R8
                MOVE    SHR_DE, R9
                MOVE    FAT32$FA_ALL, R10
                RSUB    FAT32$DIR_LIST, 1
                CMP     0, R11
                RBRA    _PPN_NO, !Z
                CMP     0, R10
                RBRA    _PPN_NO, Z
                OR      0x0004, SR
                RET
_PPN_NO         AND     0xFFFB, SR
                RET

; _PP_PUT: "/" and the name in SHR_DE in front of the path at R4 (caller's
; bank). C=0 if it does not fit (with the "SDx:" in front). R8..R10 used.
_PP_PUT         MOVE    SHR_DE, R8
                SYSCALL(strlen, 1)              ; R9: its length
                MOVE    R4, R10                 ; room: R4 - PROF_PATH - 1
                SUB     PROF_PATH, R10          ; - 4 ("SDx:")
                SUB     5, R10
                CMP     R9, R10
                RBRA    _PPP_NO, N              ; (R9 > R10)
                SUB     R9, R4
                MOVE    R4, R10
                MOVE    SHR_DE, R8
_PPP_C          CMP     0, @R8
                RBRA    _PPP_E, Z
                MOVE    @R8++, @R10++
                RBRA    _PPP_C, 1
_PPP_E          SUB     1, R4
                MOVE    0x002F, @R4
                OR      0x0004, SR
                RET
_PPP_NO         AND     0xFFFB, SR
                RET

; _PP_END: the current directory of PROF_DEVP back to R1:R0 (caller's bank);
; the sector buffer is nobody's if PROF_FDH has it. R8, R9 used.
_PP_END         MOVE    PROF_DEVP, R8
                MOVE    @R8, R8
                ADD     FAT32$DEV_AD_1STCLUS_LO, R8
                MOVE    R0, @R8++
                MOVE    R1, @R8
                MOVE    PROF_DEVP, R8
                MOVE    @R8, R8
                ADD     FAT32$DEV_BUFFERED_FDH, R8
                CMP     PROF_FDH, @R8
                RBRA    _PPE_RET, !Z
                MOVE    0, @R8
_PPE_RET        RET

; ----------------------------------------------------------------------------
; The signature of the settings file (2026-10-19)
;
; The menu bytes of the settings file only mean something to a menu with the
; same items in the same order. The text of the file therefore carries
; "menu=XXXX": a 16-bit hash of OPTM_SIZE and the group word of every item
; (config.vhd), i.e. of the menu's structure - the same for every settings
; file of this menu, whatever is selected. A file without it, or with another
; one (a core with another menu), is reset when it is loaded: OPTM_SIZE bytes,
; byte 0 = 0xFF (the standard selectors), no text - its settings are gone (the
; profiles are files of their own since 0.7); the core says so on the
; screen at the start (PREP_START). A new file gets the line at its first
; save. Not caught: options of one radio group swapped (same group words).
; ----------------------------------------------------------------------------

_B2_SIG_KEY     .ASCII_W "menu"
_B2_SIG_LOG     .ASCII_W "Settings file: made for another menu - reset to the defaults\n"
_B2_SIG_TXT     .ASCII_P "\n"
                .ASCII_P " Settings reset\n"
                .ASCII_P "\n"
                .ASCII_P " The settings file was written by a core\n"
                .ASCII_P " with a different menu, so its settings\n"
                .ASCII_P " would end up on the wrong options. It was\n"
                .ASCII_P " replaced by a new one with the defaults.\n"
                .ASCII_P "\n"
                .ASCII_P " The machine profiles in /amiga/profiles\n"
                .ASCII_P " are not affected.\n"
                .ASCII_P "\n"
                .ASCII_W " Press any key to continue.\n"

; _B2_SIGHEX: the signature of this menu as 4 hex digits and a zero -> the
; buffer R8 (5 words). All registers preserved.
_B2_SIGHEX      SYSCALL(enter, 1)
                MOVE    R8, R7                  ; R7: buffer
                MOVE    M2M$RAMROM_DEV, R0      ; R5/R6: the window as it was
                MOVE    @R0, R5
                MOVE    M2M$RAMROM_4KWIN, R1
                MOVE    @R1, R6
                MOVE    M2M$CONFIG, @R0
                MOVE    M2M$CFG_OPTM_GROUPS, @R1
                MOVE    OPTM_ICOUNT, R2
                MOVE    @R2, R2                 ; R2: items left
                MOVE    R2, R3                  ; R3: hash, from the count
                MOVE    M2M$RAMROM_DATA, R4
_B2_SH_1        MOVE    R3, R8                  ; rotate left, then the
                AND     0xFFFB, SR              ; group word
                SHR     15, R8
                AND     0xFFFD, SR
                SHL     1, R3
                OR      R8, R3
                XOR     @R4++, R3
                SUB     1, R2
                RBRA    _B2_SH_1, !Z
                MOVE    R5, @R0
                MOVE    R6, @R1
                MOVE    4, R2                   ; 4 hex digits, the high one
_B2_SH_2        MOVE    R3, R8                  ; first
                AND     0xFFFB, SR
                SHR     12, R8
                AND     0x000F, R8
                ADD     0x0030, R8
                CMP     R8, 0x0039              ; above "9"?
                RBRA    _B2_SH_3, !N
                ADD     7, R8
_B2_SH_3        MOVE    R8, @R7++
                AND     0xFFFD, SR
                SHL     4, R3
                SUB     1, R2
                RBRA    _B2_SH_2, !Z
                MOVE    0, @R7
                SYSCALL(leave, 1)
                RET

; B2_CFG_CHECK: the settings file R8 (open, its text loaded by CFGS_LOAD)
; -> C=1: it carries the signature of this menu. C=0: it did not and is reset
; (see above; CFGS_RESET = 1); the caller then treats it as a new file.
; Registers preserved.
B2_CFG_CHECK    SYSCALL(enter, 1)
                MOVE    R8, R0                  ; R0: file handle
                SUB     10, SP                  ; SP: this menu's signature,
                MOVE    SP, R8                  ; SP + 5: the file's
                RSUB    _B2_SIGHEX, 1
                MOVE    _B2_SIG_KEY, R8
                MOVE    SP, R9
                ADD     5, R9
                MOVE    5, R10
                RSUB    CFGS_GET, 1
                MOVE    SP, R8
                SYSCALL(strcmp, 1)
                ADD     10, SP
                CMP     0, R10
                RBRA    _B2_CC_OK, Z
                MOVE    _B2_SIG_LOG, R8
                SYSCALL(puts, 1)
                MOVE    CFGS_RESET, R8
                MOVE    1, @R8
                MOVE    CFGS_LEN, R8            ; no text: CFGS_SIZE makes it
                MOVE    0, @R8                  ; OPTM_SIZE bytes long
                MOVE    CFGS_BUF, R8
                MOVE    0, @R8
                MOVE    CFGS_DIRTY, R8
                MOVE    0, @R8
                MOVE    R0, R8
                RSUB    CFGS_SIZE, 1
                MOVE    R0, R8                  ; byte 0: 0xFF (on an error the
                XOR     R9, R9                  ; defaults are used anyway and
                XOR     R10, R10                ; the next save rewrites it)
                SYSCALL(f32_fseek, 1)
                CMP     0, R9
                RBRA    _B2_CC_NO, !Z
                MOVE    R0, R8
                MOVE    0x00FF, R9
                SYSCALL(f32_fwrite, 1)
                CMP     0, R9
                RBRA    _B2_CC_NO, !Z
                MOVE    R0, R8
                SYSCALL(f32_fflush, 1)
_B2_CC_NO       SYSCALL(leave, 1)
                AND     0xFFFB, SR              ; C=0
                RET
_B2_CC_OK       SYSCALL(leave, 1)
                OR      0x0004, SR              ; C=1
                RET

; B2_CFG_SIGSET: a new settings file: its text gets the signature of this menu
; (CFGS_DIRTY, so the next save writes it). Registers preserved.
B2_CFG_SIGSET   SYSCALL(enter, 1)
                SUB     5, SP
                MOVE    SP, R8
                RSUB    _B2_SIGHEX, 1
                MOVE    SP, R9
                MOVE    _B2_SIG_KEY, R8
                RSUB    CFGS_SET, 1
                ADD     5, SP
                SYSCALL(leave, 1)
                RET

; B2_CFG_WARN: if B2_CFG_CHECK reset the settings file, say so on the screen
; until a key is pressed (at the start of the core, PREP_START). Registers
; preserved.
B2_CFG_WARN     SYSCALL(enter, 1)
                MOVE    CFGS_RESET, R0
                CMP     0, @R0
                RBRA    _B2_CW_RET, Z
                MOVE    0, @R0
                RSUB    SCR$OSM_M_ON, 1
                RSUB    FRAME_FULLSCR, 1
                MOVE    _B2_SIG_TXT, R8
                RSUB    SCR$PRINTSTR, 1
_B2_CW_1        RSUB    HANDLE_IO, 1
                RSUB    KEYB$SCAN, 1
                RSUB    KEYB$GETKEY, 1
                CMP     0, R8
                RBRA    _B2_CW_1, Z
                RSUB    SCR$OSM_OFF, 1
_B2_CW_RET      SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; Code bank BANK_IDE (Megamiga 0.7): hard disk image code off the sector path -
; the link files (HDF_LINK, HDF_PART_GET, moved here from the fixed ROM) and the
; virtual RDB. Entered through the stubs next to HDF_LINK.
; ----------------------------------------------------------------------------

                .ORG    0x9000                  ; M2M$CODE_WIN
                .DW     0x4B03                  ; bank 3: BANK_IDE

; HDF_LINK: is the file R8 a link file that names a partition of the SD card?
;
; A link file is an .hdf file under 512 bytes that starts with
; "MEGAMIGA-PARTITION n" (n = 1..4, upper or lower case): the drive is then
; partition n of the card the file is on, which must have the MBR type 0x7F
; (the type for local / experimental use: no operating system claims it) and
; at least 64 KB. Nothing else is ever used as a disk: the FAT32 partition, an
; empty entry or another type are refused. The partition holds the disk as a
; whole, from its own RDB on, exactly like an HDF file.
;
; Input:  R8: the file handle of the Shell, at position 0
; Output: R8: 0 = not a link file, 1..4 = the partition, 0xFF = a link file but
;         no usable partition; for 1..4: R10:R9 = its first block, R12:R11 =
;         its size in blocks. The SD sector buffer is released (owned by
;         nobody) once the MBR was read.
B3_HDF_LINK     INCRB
                MOVE    R8, R0                  ; R0: the handle
                MOVE    HDF_LINK_MAGIC, R8
                RSUB    RODATA_STR, 1
                MOVE    R8, R1                  ; R1: the magic text (RAM copy)
_HLK_M          MOVE    @R1++, R2
                CMP     0, R2
                RBRA    _HLK_NUM, Z             ; the whole magic matched
                RSUB    _HLK_RD, 1
                RBRA    _HLK_NO, C
                CMP     R2, R9
                RBRA    _HLK_M, Z
                RBRA    _HLK_NO, 1
_HLK_NUM        RSUB    _HLK_RD, 1              ; the partition digit
                RBRA    _HLK_NO, C
                SUB     0x0031, R9              ; '1'..'4' -> 0..3
                CMP     R9, 3
                RBRA    _HLK_NO, N              ; (R9 > 3, also for < '1')
                MOVE    R9, R3                  ; R3: partition - 1

_HLK_MBR        MOVE    R0, R8                  ; the MBR: block 0, read
                RSUB    _F32_RELEASE_BUF, 1     ; straight into the buffer
                CMP     0, R9
                RBRA    _HLK_BAD, !Z
                XOR     R8, R8
                XOR     R9, R9
                MOVE    FAT32$DEV_BLOCK_READ, R10
                MOVE    @R0, R11                ; the device of the file
                RSUB    FAT32$CALL_DEV, 1
                CMP     0, R8
                RBRA    _HLK_BAD, !Z
                MOVE    0x01FE, R8              ; the MBR signature 55 AA
                RSUB    _HLK_B, 1
                CMP     0x0055, R8
                RBRA    _HLK_BAD, !Z
                MOVE    0x01FF, R8
                RSUB    _HLK_B, 1
                CMP     0x00AA, R8
                RBRA    _HLK_BAD, !Z
                MOVE    R3, R4                  ; R4: the entry, 0x1BE + 16 n
                AND     0xFFFD, SR
                SHL     4, R4
                ADD     0x01BE, R4
                MOVE    R4, R8                  ; the type
                ADD     4, R8
                RSUB    _HLK_B, 1
                CMP     0x007F, R8
                RBRA    _HLK_BAD, !Z
                MOVE    R4, R8                  ; R6:R5: first block
                ADD     8, R8
                RSUB    _HLK_W, 1
                MOVE    R8, R5
                MOVE    R4, R8
                ADD     10, R8
                RSUB    _HLK_W, 1
                MOVE    R8, R6
                MOVE    R4, R8                  ; R12:R11: size
                ADD     12, R8
                RSUB    _HLK_W, 1
                MOVE    R8, R11
                MOVE    R4, R8
                ADD     14, R8
                RSUB    _HLK_W, 1
                MOVE    R8, R12
                MOVE    R5, R8                  ; block 0 is the MBR itself
                OR      R6, R8
                RBRA    _HLK_BAD, Z
                CMP     0, R12                  ; at least 128 blocks = 64 KB
                RBRA    _HLK_OK, !Z
                CMP     R11, 0x007F
                RBRA    _HLK_BAD, !N            ; (R11 <= 127)
_HLK_OK         MOVE    R5, R9
                MOVE    R6, R10
                MOVE    R3, R8
                ADD     1, R8
                RBRA    _HLK_RET, 1
_HLK_BAD        MOVE    0x00FF, R8
                RBRA    _HLK_RET, 1
_HLK_NO         XOR     R8, R8
_HLK_RET        DECRB
                RET

; HDF_PART_GET: partition R9 (1..4) of the SD card of the file handle R8 (only
; its device word is read, see HDF_DEVREF): the checks of HDF_LINK (MBR type
; 0x7F, not at block 0, at least 64 KB).
; Output: R8: R9 if usable, else 0xFF; R10:R9 = its first block, R12:R11 = its
;         size in blocks. The SD sector buffer is released.
B3_HDF_PART_GET INCRB
                MOVE    R8, R0
                MOVE    R9, R3
                SUB     1, R3
                CMP     R3, 3
                RBRA    _HLK_BAD, N             ; (R3 > 3, also for 0)
                RBRA    _HLK_MBR, 1

; _HLK_RD: next byte of the link file R0 (in the register bank of HDF_LINK) into R9, a-z as A-Z
; Output: C=1 at the end of the file or on an error
_HLK_RD         MOVE    R0, R8
                SYSCALL(f32_fread, 1)
                CMP     0, R10
                RBRA    _HLKR_E, !Z
                CMP     R9, 0x0060              ; 'a'..'z'?
                RBRA    _HLKR_OK, !N            ; (R9 <= 0x60)
                CMP     R9, 0x007A
                RBRA    _HLKR_OK, N             ; (R9 > 'z')
                SUB     0x0020, R9
_HLKR_OK        AND     0xFFFB, SR              ; C=0
                RET
_HLKR_E         OR      0x0004, SR              ; C=1
                RET

; _HLK_B: byte R8 of the SD sector buffer -> R8. _HLK_W: the little-endian
; word at R8 -> R8. R9 clobbered.
_HLK_B          MOVE    IO$SD_DATA_POS, R9
                MOVE    R8, @R9
                MOVE    IO$SD_DATA, R9
                MOVE    @R9, R8
                AND     0x00FF, R8
                RET
_HLK_W          MOVE    R8, @--SP
                ADD     1, R8                   ; high byte
                RSUB    _HLK_B, 1
                AND     0xFFFD, SR
                SHL     8, R8
                MOVE    R8, R9
                MOVE    @SP++, R8               ; low byte
                MOVE    R9, @--SP
                RSUB    _HLK_B, 1
                OR      @SP++, R8
                RET

; ----------------------------------------------------------------------------
; Virtual RDB (Megamiga 0.7): hard disk images without a Rigid Disk Block
;
; UAE's "hardfiles" (and many images made with or for it) hold one file system
; from block 0 on, without the RDB that lide.device and the scsi.device of the
; Kickstart look for. Like ide.cpp of MiSTer, the drive then shows a virtual
; cylinder in front of the image: block 0 a Rigid Disk Block, block 1 one
; partition that covers the image, the rest zeros. The image starts at block
; HDF_VRDB of the drive; IDE_LBA2BLK and IDE_SEEK subtract it, the sector engine
; does too (its skip register; HDF_ENG_SETUP leaves the drive to the firmware
; when the board has none). Writes to the virtual blocks are ignored, the RDB's
; product name says "DONT REPARTITION".
;
; Detection (B3_VRDB_DET, at every mount of a file or a partition): block 0
; starts with a file system id - DOS\0..DOS\7, PFS\x, PDS\x or SFS\0 - and blocks
; 1..15 hold no "RDSK". Blank images and images with an RDB stay as they are.
;
; Geometry: the partition must be exactly as large as the file system was
; formatted, because OFS/FFS put the root block in its middle. UAE's default
; for a hardfile is 32 blocks per track, 1 surface, 2 reserved blocks and as
; many whole cylinders as fit; MiSTer takes 32 blocks per cylinder too up to
; about 1 GB and 64..2048 above (ide.cpp, guess_geometry). UAE's geometry is
; used unless only MiSTer's finds an OFS/FFS root block (type 2, secondary type
; 1) in the middle. The partition: DH0 (master) or DH1 (slave), bootable, the
; DosType of the image, MaxTransfer 0x1FE00, Mask 0x7FFFFFFE.
; ----------------------------------------------------------------------------

; B3_VRDB_DET: the virtual RDB of the active drive: HDF_VRDB (blocks in front of
; the image, 0 = none), HDF_VDOS_HI/LO; HDF_SECT_LO/HI grow by HDF_VRDB.
; HDF_PREP calls it once the image is mapped (HDF_MAPOK, HDF_PART, HDF_PST_*,
; HDF_SPC_SHIFT) and HDF_SECT_LO/HI hold its size.
; Input/Output: none; R8..R12 clobbered. Uses the SD sector buffer; IDE_LBA_LO/HI
; are restored (a command of the other drive may be under way).
B3_VRDB_DET     INCRB
                MOVE    HDF_VRDB, R0            ; the image as it is
                MOVE    0, @R0
                MOVE    IDE_LBA_LO, R0
                MOVE    @R0, @--SP
                MOVE    IDE_LBA_HI, R0
                MOVE    @R0, @--SP

                MOVE    HDF_SECT_HI, R0         ; LBA28 must hold the virtual
                CMP     @R0, 0x0FF0             ; cylinder too (partitions: up
                RBRA    _VRD_RET, N             ; to 128 GB)

                XOR     R8, R8                  ; block 0: a file system id
                XOR     R9, R9
                XOR     R10, R10
                RSUB    _VR_LONG, 1
                RBRA    _VRD_RET, C
                MOVE    R8, R4                  ; R4: high word, R5: low word
                MOVE    R9, R5
                MOVE    R5, R6                  ; the third letter is an 'S'
                AND     0xFF00, R6
                CMP     0x5300, R6
                RBRA    _VRD_RET, !Z
                CMP     0x444F, R4              ; "DO": DOS\0..DOS\7
                RBRA    _VRD_NDOS, !Z
                MOVE    R5, R6
                AND     0x00FF, R6
                CMP     R6, 7
                RBRA    _VRD_RET, N             ; (R6 > 7)
                RBRA    _VRD_FS, 1
_VRD_NDOS       CMP     0x5046, R4              ; "PF": PFS\x
                RBRA    _VRD_FS, Z
                CMP     0x5044, R4              ; "PD": PDS\x
                RBRA    _VRD_FS, Z
                CMP     0x5346, R4              ; "SF": SFS\0
                RBRA    _VRD_RET, !Z
                CMP     0x5300, R5
                RBRA    _VRD_RET, !Z

_VRD_FS         MOVE    1, R6                   ; no RDB in blocks 1..15
_VRD_RL         MOVE    R6, R8
                XOR     R9, R9
                XOR     R10, R10
                RSUB    _VR_LONG, 1
                RBRA    _VRD_RET, C
                CMP     0x5244, R8              ; "RD"
                RBRA    _VRD_RN, !Z
                CMP     0x534B, R9              ; "SK"
                RBRA    _VRD_RET, Z
_VRD_RN         ADD     1, R6
                CMP     16, R6
                RBRA    _VRD_RL, !Z

                MOVE    32, R6                  ; R6: blocks per cylinder, UAE's
                CMP     0x444F, R4              ; (root blocks: OFS/FFS only)
                RBRA    _VRD_SET, !Z
                MOVE    R6, R8
                RSUB    _VR_ROOT, 1
                RBRA    _VRD_SET, !C
                RSUB    _VR_MISTER, 1           ; MiSTer's, if another one
                CMP     32, R8
                RBRA    _VRD_SET, Z
                MOVE    R8, R7
                RSUB    _VR_ROOT, 1
                RBRA    _VRD_SET, C
                MOVE    R7, R6

_VRD_SET        MOVE    HDF_VDOS_HI, R0
                MOVE    R4, @R0
                MOVE    HDF_VDOS_LO, R0
                MOVE    R5, @R0
                MOVE    HDF_SECT_LO, R0         ; the drive: one cylinder more
                MOVE    HDF_SECT_HI, R1
                ADD     R6, @R0
                ADDC    0, @R1
                MOVE    HDF_VRDB, R0
                MOVE    R6, @R0
                MOVE    R6, R5                  ; the drive's CHS geometry is
                RSUB    _VRB_GEO, 1             ; the partition's (scsi.device
                MOVE    HDF_HEADS, R0           ; of Kickstart 3.1 addresses by
                MOVE    R4, @R0                 ; CHS and stops at the IDENTIFY
                MOVE    HDF_SPT, R0             ; capacity: with 16 x 63 the
                MOVE    R3, @R0                 ; last cylinder was out of reach)

_VRD_RET        MOVE    IDE_LBA_HI, R0
                MOVE    @SP++, @R0
                MOVE    IDE_LBA_LO, R0
                MOVE    @SP++, @R0
                DECRB
                RET

; _VRB_GEO (the caller's register bank): R3 = sectors per track = min(R5, 128),
; R4 = heads = R5 / R3 for R5 blocks per cylinder (as MiSTer's ide.cpp)
_VRB_GEO        MOVE    R5, R3
                MOVE    1, R4
                CMP     R3, 128
                RBRA    _VRG_RET, !N            ; (R3 <= 128)
                MOVE    128, R3
                MOVE    R5, R4
                AND     0xFFFB, SR
                SHR     7, R4
_VRG_RET        RET

; B3_VRDB_ID: the end of IDE_IDENTIFY: a drive with a virtual RDB reports the
; partition's geometry as its default one (words 1, 3, 6: cylinders = sectors /
; blocks per cylinder, at most 65535), so that a host addressing by CHS reaches
; every block of it - like MiSTer. Output: none; R8..R12 clobbered.
B3_VRDB_ID      INCRB
                MOVE    HDF_VRDB, R5
                MOVE    @R5, R5                 ; R5: blocks per cylinder
                RBRA    _VRID_RET, Z
                RSUB    _VRB_GEO, 1
                MOVE    R4, R8
                MOVE    IDE_IDW_HDS, R9
                RSUB    IDE_ID_PUT, 1
                MOVE    R3, R8
                MOVE    IDE_IDW_SPT, R9
                RSUB    IDE_ID_PUT, 1
                XOR     R10, R10                ; R10: log2(R5)
_VRID_LG        MOVE    1, R1
                AND     0xFFFD, SR
                SHL     R10, R1
                CMP     R1, R5
                RBRA    _VRID_LGD, Z
                ADD     1, R10
                RBRA    _VRID_LG, 1
_VRID_LGD       MOVE    HDF_SECT_LO, R8
                MOVE    @R8, R8
                MOVE    HDF_SECT_HI, R9
                MOVE    @R9, R9
                RSUB    IDE_SHR32, 1
                CMP     0, R9
                RBRA    _VRID_C, Z
                MOVE    0xFFFF, R8
_VRID_C         MOVE    IDE_IDW_CYL, R9
                RSUB    IDE_ID_PUT, 1
_VRID_RET       DECRB
                RET

; _VR_MISTER: MiSTer's blocks per cylinder for an image of HDF_SECT_LO/HI blocks:
; the smallest of 32, 64, .., 2048 that gives fewer than 65535 cylinders, else
; 2048. Output: R8; R9, R10 clobbered.
_VR_MISTER      INCRB
                MOVE    5, R0                   ; R0: log2
_VRM_L          MOVE    HDF_SECT_LO, R8
                MOVE    @R8, R8
                MOVE    HDF_SECT_HI, R9
                MOVE    @R9, R9
                MOVE    R0, R10
                RSUB    IDE_SHR32, 1            ; R9:R8: cylinders
                CMP     11, R0
                RBRA    _VRM_D, Z
                CMP     0, R9
                RBRA    _VRM_N, !Z
                CMP     0xFFFF, R8
                RBRA    _VRM_D, !Z
_VRM_N          ADD     1, R0
                RBRA    _VRM_L, 1
_VRM_D          MOVE    1, R8
                AND     0xFFFD, SR
                SHL     R0, R8
                DECRB
                RET

; _VR_ROOT: is the middle block of the whole cylinders of R8 blocks (a power of
; two) an OFS/FFS root block (long 0 = 2, T_HEADER; long 127 = 1, ST_ROOT)? A
; partition of B blocks with 2 reserved has its root at (B - 1 + 2) / 2 = B / 2.
; Output: C=0: yes; C=1: no. R8..R12 clobbered.
_VR_ROOT        INCRB
                SUB     1, R8                   ; B = size & ~(R8 - 1)
                NOT     R8, R0
                MOVE    HDF_SECT_LO, R8
                MOVE    @R8, R8
                AND     R0, R8
                MOVE    HDF_SECT_HI, R9
                MOVE    @R9, R9
                MOVE    1, R10                  ; B / 2
                RSUB    IDE_SHR32, 1
                MOVE    R8, R0                  ; R1:R0: the root block
                MOVE    R9, R1
                XOR     R10, R10
                RSUB    _VR_LONG, 1
                RBRA    _VRR_NO, C
                CMP     0, R8
                RBRA    _VRR_NO, !Z
                CMP     2, R9
                RBRA    _VRR_NO, !Z
                MOVE    R0, R8
                MOVE    R1, R9
                MOVE    508, R10
                RSUB    _VR_LONG, 1
                RBRA    _VRR_NO, C
                CMP     0, R8
                RBRA    _VRR_NO, !Z
                CMP     1, R9
                RBRA    _VRR_NO, !Z
                AND     0xFFFB, SR              ; C=0
                DECRB
                RET
_VRR_NO         OR      0x0004, SR              ; C=1
                DECRB
                RET

; _VR_LONG: the big-endian long at byte R10 (0..508, a multiple of 4) of block
; R9:R8 of the image (HDF_VRDB must be 0 here: IDE_LBA2BLK subtracts it).
; Output: C=0: R8 = high word, R9 = low word; C=1: read error. R10..R12
; clobbered; IDE_LBA_LO/HI = the block.
_VR_LONG        INCRB
                MOVE    R10, R6                 ; R6: byte position
                MOVE    IDE_LBA_LO, R0
                MOVE    R8, @R0
                MOVE    IDE_LBA_HI, R0
                MOVE    R9, @R0
                XOR     R4, R4                  ; R4:R5: the long
                XOR     R5, R5
                MOVE    4, R3                   ; R3: bytes to go
                MOVE    HDF_MAPOK, R0           ; the extent map (or a partition):
                CMP     1, @R0                  ; one block read
                RBRA    _VRL_SLOW, !Z
                RSUB    IDE_LBA2BLK, 1
                RBRA    _VRL_ERR, C
                RSUB    IDE_SD_TAKE, 1
                RBRA    _VRL_ERR, C
                MOVE    HDF_FDH, R11
                MOVE    @R11, R11
                MOVE    FAT32$DEV_BLOCK_READ, R10
                RSUB    FAT32$CALL_DEV, 1
                CMP     0, R8
                RBRA    _VRL_ERR, !Z
_VRL_FB         MOVE    IO$SD_DATA_POS, R0
                MOVE    R6, @R0
                MOVE    IO$SD_DATA, R0
                MOVE    @R0, R7
                RSUB    _VRL_PUT, 1
                CMP     0, R3
                RBRA    _VRL_FB, !Z
                RBRA    _VRL_OK, 1

_VRL_SLOW       MOVE    R8, R0                  ; a fragmented file: seek to
                MOVE    R9, R1                  ; block << 9 + R6, byte reads
                MOVE    R0, R9
                AND     0xFFFD, SR
                SHL     9, R9
                OR      R6, R9
                MOVE    R1, R10
                AND     0xFFFD, SR
                SHL     9, R10
                AND     0xFFFB, SR
                SHR     7, R0
                OR      R0, R10
                MOVE    HDF_FDH, R8
                SYSCALL(f32_fseek, 1)
                CMP     0, R9
                RBRA    _VRL_ERR, !Z
_VRL_SB         MOVE    HDF_FDH, R8
                SYSCALL(f32_fread, 1)
                CMP     0, R10
                RBRA    _VRL_ERR, !Z
                MOVE    R9, R7
                RSUB    _VRL_PUT, 1
                CMP     0, R3
                RBRA    _VRL_SB, !Z

_VRL_OK         MOVE    R4, R8
                MOVE    R5, R9
                AND     0xFFFB, SR              ; C=0
                DECRB
                RET
_VRL_ERR        OR      0x0004, SR              ; C=1
                DECRB
                RET

; _VRL_PUT (the register bank of _VR_LONG): byte R7 into R4:R5 from the right,
; R6 + 1, R3 - 1
_VRL_PUT        AND     0x00FF, R7
                AND     0xFFFD, SR
                SHL     8, R4
                MOVE    R5, R2
                AND     0xFFFB, SR
                SHR     8, R2
                OR      R2, R4
                AND     0xFFFD, SR
                SHL     8, R5
                OR      R7, R5
                ADD     1, R6
                SUB     1, R3
                RET

; B3_VRDB_WR: IDE_WRITE_SECT's first step: C=1 if sector IDE_LBA_LO/HI is a
; virtual block (it is not written), else C=0. Registers preserved.
B3_VRDB_WR      INCRB
                RSUB    _VR_IS, 1
                DECRB
                RET

; _VR_IS (the caller's register bank): C=1 if sector IDE_LBA_LO/HI is a virtual
; block, R0 = its number; else C=0. R1 clobbered.
_VR_IS          MOVE    HDF_VRDB, R1
                MOVE    @R1, R1
                RBRA    _VRI_NO, Z
                MOVE    IDE_LBA_HI, R0
                CMP     0, @R0
                RBRA    _VRI_NO, !Z
                MOVE    IDE_LBA_LO, R0
                MOVE    @R0, R0
                CMP     R1, R0                  ; HDF_VRDB > LBA?
                RBRA    _VRI_NO, !N
                OR      0x0004, SR              ; C=1
                RET
_VRI_NO         AND     0xFFFB, SR              ; C=0
                RET

; B3_VRDB_RD: IDE_READ_SECT's first step: is sector IDE_LBA_LO/HI a virtual
; block? Output: C=1: yes, it is in the buffer of the board (selected); C=0: no.
; R8..R12 clobbered. The board's buffer cannot be read back, so the checksum
; is summed while the longs are written (_VR_PUTL).
B3_VRDB_RD      INCRB
                RSUB    _VR_IS, 1               ; R0: the block
                RBRA    _VRB_RET, !C
                RSUB    IDE_SEL, 1
                MOVE    IDE_DATA, R1            ; zeros
                MOVE    256, R2
_VRB_Z          MOVE    0, @R1++
                SUB     1, R2
                RBRA    _VRB_Z, !Z
                CMP     R0, 1
                RBRA    _VRB_DONE, N            ; blocks 2.. stay zero

                XOR     R6, R6                  ; R6:R7: the sum of the longs
                XOR     R7, R7
                MOVE    HDF_VRDB, R5
                MOVE    @R5, R5                 ; R5: blocks per cylinder
                XOR     R10, R10                ; R10: log2(R5)
_VRB_LG         MOVE    1, R1
                AND     0xFFFD, SR
                SHL     R10, R1
                CMP     R1, R5
                RBRA    _VRB_LGD, Z
                ADD     1, R10
                RBRA    _VRB_LG, 1
_VRB_LGD        MOVE    HDF_SECT_LO, R8         ; cylinders = drive / R5
                MOVE    @R8, R8
                MOVE    HDF_SECT_HI, R9
                MOVE    @R9, R9
                RSUB    IDE_SHR32, 1
                MOVE    R9, R11                 ; R11:R12: cylinders
                MOVE    R8, R12
                CMP     0, R0
                RBRA    _VRB_PART, !Z

                MOVE    _VR_RDSK, R8            ; block 0: the RDB
                RSUB    _VR_TAB, 1
                MOVE    16, R1                  ; rdb_Cylinders
                RSUB    _VRB_CYL, 1
                MOVE    17, R1                  ; rdb_Sectors
                RSUB    _VRB_SPT, 1
                MOVE    18, R1                  ; rdb_Heads
                RSUB    _VRB_HEADS, 1
                MOVE    20, R1                  ; rdb_Park
                RSUB    _VRB_CYL, 1
                MOVE    24, R1                  ; rdb_WritePreComp
                RSUB    _VRB_CYL, 1
                MOVE    25, R1                  ; rdb_ReducedWrite
                RSUB    _VRB_CYL, 1
                MOVE    35, R1                  ; rdb_HiCylinder
                RSUB    _VRB_HCYL, 1
                MOVE    36, R1                  ; rdb_CylBlocks
                XOR     R2, R2
                MOVE    R5, R3
                RSUB    _VR_PUTL, 1
                RBRA    _VRB_SUM, 1

_VRB_PART       MOVE    _VR_PART, R8            ; block 1: the partition
                RSUB    _VR_TAB, 1
                MOVE    9, R1                   ; pb_DriveName: BCPL "DH0"/"DH1"
                MOVE    0x0344, R2
                MOVE    HDF_ACTIVE, R3
                MOVE    @R3, R3
                ADD     0x4830, R3
                RSUB    _VR_PUTL, 1
                MOVE    35, R1                  ; de_Surfaces
                RSUB    _VRB_HEADS, 1
                MOVE    37, R1                  ; de_BlocksPerTrack
                RSUB    _VRB_SPT, 1
                MOVE    42, R1                  ; de_HighCyl
                RSUB    _VRB_HCYL, 1
                MOVE    48, R1                  ; de_DosType
                MOVE    HDF_VDOS_HI, R2
                MOVE    @R2, R2
                MOVE    HDF_VDOS_LO, R3
                MOVE    @R3, R3
                RSUB    _VR_PUTL, 1

_VRB_SUM        MOVE    2, R1                   ; the checksum: the 64 longs add
                XOR     R2, R2                  ; up to 0
                XOR     R3, R3
                SUB     R7, R3
                SUBC    R6, R2
                RSUB    _VR_PUTL, 1
_VRB_DONE       OR      0x0004, SR              ; C=1
_VRB_RET        DECRB
                RET

; (the register bank of B3_VRDB_RD) long R1 of the block := cylinders (_VRB_CYL),
; cylinders - 1 (_VRB_HCYL), sectors = min(R5, 128) (_VRB_SPT), heads = R5 /
; sectors (_VRB_HEADS)
_VRB_CYL        MOVE    R11, R2
                MOVE    R12, R3
                RBRA    _VR_PUTL, 1
_VRB_HCYL       MOVE    R11, R2
                MOVE    R12, R3
                SUB     1, R3
                SUBC    0, R2
                RBRA    _VR_PUTL, 1
_VRB_SPT        RSUB    _VRB_GEO, 1             ; (R4 clobbered)
                XOR     R2, R2
                RBRA    _VR_PUTL, 1
_VRB_HEADS      RSUB    _VRB_GEO, 1
                XOR     R2, R2
                MOVE    R4, R3
                RBRA    _VR_PUTL, 1

; _VR_TAB (the register bank of B3_VRDB_RD): the longs of table R8 (long, high
; word, low word; 0xFFFF ends it) into the block. R1..R4 clobbered.
_VR_TAB         MOVE    @R8++, R1
                CMP     0xFFFF, R1
                RBRA    _VRT_RET, Z
                MOVE    @R8++, R2
                MOVE    @R8++, R3
                RSUB    _VR_PUTL, 1
                RBRA    _VR_TAB, 1
_VRT_RET        RET

; _VR_PUTL (the register bank of B3_VRDB_RD): long R1 of the block := R2:R3 (high,
; low), summed into R6:R7. R4 clobbered.
_VR_PUTL        ADD     R3, R7
                ADDC    R2, R6
                MOVE    R1, R4
                AND     0xFFFD, SR
                SHL     1, R4
                ADD     IDE_DATA, R4
                MOVE    R2, @R4++
                MOVE    R3, @R4
                RET

; RigidDiskBlock (devices/hardblocks.h), the fixed longs: long, high, low
_VR_RDSK        .DW     0, 0x5244, 0x534B       ; rdb_ID "RDSK"
                .DW     1, 0x0000, 0x0040       ; rdb_SummedLongs
                .DW     3, 0x0000, 0x0007       ; rdb_HostID
                .DW     4, 0x0000, 0x0200       ; rdb_BlockBytes
                .DW     5, 0x0000, 0x0012       ; rdb_Flags: last LUN, disk id valid
                .DW     6, 0xFFFF, 0xFFFF       ; rdb_BadBlockList: none
                .DW     7, 0x0000, 0x0001       ; rdb_PartitionList: block 1
                .DW     8, 0xFFFF, 0xFFFF       ; rdb_FileSysHeaderList: none
                .DW     9, 0xFFFF, 0xFFFF       ; rdb_DriveInit: none
                .DW     10, 0xFFFF, 0xFFFF      ; rdb_Reserved1[6]
                .DW     11, 0xFFFF, 0xFFFF
                .DW     12, 0xFFFF, 0xFFFF
                .DW     13, 0xFFFF, 0xFFFF
                .DW     14, 0xFFFF, 0xFFFF
                .DW     15, 0xFFFF, 0xFFFF
                .DW     19, 0x0000, 0x0001      ; rdb_Interleave
                .DW     26, 0x0000, 0x0003      ; rdb_StepRate
                .DW     33, 0x0000, 0x0001      ; rdb_RDBBlocksHi
                .DW     34, 0x0000, 0x0001      ; rdb_LoCylinder
                .DW     38, 0x0000, 0x0001      ; rdb_HighRDSKBlock
                .DW     40, 0x4D45, 0x4741      ; rdb_DiskVendor "MEGAMIGA"
                .DW     41, 0x4D49, 0x4741
                .DW     42, 0x444F, 0x4E54      ; rdb_DiskProduct "DONT REPARTITION"
                .DW     43, 0x2052, 0x4550
                .DW     44, 0x4152, 0x5449
                .DW     45, 0x5449, 0x4F4E
                .DW     46, 0x5652, 0x4442      ; rdb_DiskRevision "VRDB"
                .DW     0xFFFF

; PartitionBlock, the fixed longs (pb_Environment = DosEnvec from long 32 on)
_VR_PART        .DW     0, 0x5041, 0x5254       ; pb_ID "PART"
                .DW     1, 0x0000, 0x0040       ; pb_SummedLongs
                .DW     3, 0x0000, 0x0007       ; pb_HostID
                .DW     4, 0xFFFF, 0xFFFF       ; pb_Next: none
                .DW     5, 0x0000, 0x0001       ; pb_Flags: bootable
                .DW     32, 0x0000, 0x0010      ; de_TableSize: up to de_DosType
                .DW     33, 0x0000, 0x0080      ; de_SizeBlock: 128 longs
                .DW     36, 0x0000, 0x0001      ; de_SectorPerBlock
                .DW     38, 0x0000, 0x0002      ; de_Reserved
                .DW     41, 0x0000, 0x0001      ; de_LowCyl
                .DW     43, 0x0000, 0x001E      ; de_NumBuffers
                .DW     45, 0x0001, 0xFE00      ; de_MaxTransfer
                .DW     46, 0x7FFF, 0xFFFE      ; de_Mask
                .DW     0xFFFF

; ----------------------------------------------------------------------------
; The quick HDF (Megamiga 0.7): " hdf:%s" on the main page
;
; For the one-game WHDLoad hard disk images: a file chosen on that line becomes
; the master drive (the slave is emptied) in place of the profile's HDF 0 / HDF 1
; until Space on that line ejects it or the core restarts - it is never saved.
; The profile keeps its disks: their lines in Profile Settings still show them,
; a profile switch mounts nothing over the quick HDF, and a file chosen on those
; lines meanwhile is only noted in the profile (QHDF_HREM). The eject mounts the
; profile's disks again (PROF_HDFS) and restarts the Amiga. QHDF_ON says which.
; ----------------------------------------------------------------------------

; B3_QHDF_PREP: PREP_LOAD_IMAGE of the quick HDF line. Input: R8 = the file
; handle of the Shell (a partition from the browser: SF_VIRTUAL).
; Output: R8: 0 = OK, else error; R9: 0 or an error message; R10..R12 preserved
B3_QHDF_PREP    INCRB
                MOVE    R10, @--SP
                MOVE    R11, @--SP
                MOVE    R12, @--SP
                MOVE    R8, R0                  ; R0: the handle
                MOVE    SF_VIRTUAL, R4          ; a partition: as on the HDF
                MOVE    @R4, R4                 ; lines (HDF_VPART = slot << 8 |
                CMP     0, R4                   ; its number)
                RBRA    _QP_F, Z
                SUB     1, R4
                MOVE    HDF_VPART, R5
                MOVE    R4, @R5
_QP_F           MOVE    2, R8                   ; the slave goes, the master
                RSUB    HDF_DROP, 1             ; gets the file
                MOVE    R0, R8
                XOR     R9, R9
                RSUB    HDF_PREP, 1             ; (restarts the Amiga)
                MOVE    R8, R2                  ; R2/R3: the result
                MOVE    R9, R3
                CMP     0, R2
                RBRA    _QP_ERR, !Z
                MOVE    QHDF_ON, R1
                MOVE    1, @R1
                XOR     R4, R4                  ; the profile's lines keep the
_QP_L           MOVE    CRTROM_MAN_LDF, R5      ; names they show (HDF_DROP and
                ADD     PROF_HDF_ID, R5         ; HDF_PREP set their devices
                ADD     R4, R5                  ; IDLE)
                CMP     0, @R5
                RBRA    _QP_N, Z
                MOVE    HDF_DEV_TAB, R8
                ADD     R4, R8
                MOVE    @R8, R8
                MOVE    CRTROM_CSR_STATUS, R9
                MOVE    CRTROM_CSR_ST_OK, R10
                RSUB    CRTROM_CSR_W, 1
_QP_N           ADD     1, R4
                CMP     2, R4
                RBRA    _QP_L, !Z
                RBRA    _QP_RET, 1
_QP_ERR         MOVE    QHDF_ON, R1             ; refused while the profile's
                CMP     0, @R1                  ; disks were in: them again
                RBRA    _QP_RET, !Z             ; (the slave was dropped, the
                XOR     R8, R8                  ; master maybe too)
                MOVE    1, R9
                RSUB    PROF_HDFS, 1
_QP_RET         MOVE    R2, R8
                MOVE    R3, R9
                MOVE    @SP++, R12
                MOVE    @SP++, R11
                MOVE    @SP++, R10
                DECRB
                RET

; B3_QHDF_HREM: an HDF line of Profile Settings while the quick HDF is on: the
; profile notes the file (PREP_LOAD_IMAGE calls PROF_REMEMBER next) and it is
; mounted when the quick HDF is ejected; the Shell reads EOF at once.
; Input: R8 = the file handle of the Shell. Output: R8 = R9 = 0
B3_QHDF_HREM    INCRB
                MOVE    HDF_VPART, R0           ; (one load only)
                MOVE    0, @R0
                MOVE    SF_VIRTUAL, R0          ; a partition: no file to read
                CMP     0, @R0
                RBRA    _QH_OK, !Z
                MOVE    R8, R0
                ADD     FAT32$FDH_SIZE_LO, R0
                MOVE    @R0, R9
                MOVE    R8, R0
                ADD     FAT32$FDH_SIZE_HI, R0
                MOVE    @R0, R10
                SYSCALL(f32_fseek, 1)
_QH_OK          XOR     R8, R8
                XOR     R9, R9
                DECRB
                RET

; B3_HDF_SPOK (HANDLE_UNMOUNT_KEY): does Space on line R8 (0 = HDF 0, 1 = HDF 1,
; 2 = the quick HDF) eject or forget something? Output: C=1 yes, C=0 no (Space
; opens the file browser). Registers preserved.
B3_HDF_SPOK     INCRB
                MOVE    QHDF_ON, R0
                MOVE    @R0, R0                 ; R0: the quick HDF is on
                CMP     2, R8
                RBRA    _QS_D, !Z
                CMP     0, R0                   ; the quick line: its disk
                RBRA    _QS_NO, Z
                RBRA    _QS_YES, 1
_QS_D           CMP     0, R0
                RBRA    _QS_U, Z
                MOVE    CRTROM_MAN_LDF, R1      ; quick on: a file the profile
                ADD     PROF_HDF_ID, R1         ; notes (the line shows it)
                ADD     R8, R1
                CMP     0, @R1
                RBRA    _QS_NO, Z
                RBRA    _QS_YES, 1
_QS_U           MOVE    R8, R1                  ; else: the drive is mounted
                ADD     1, R1
                MOVE    HDF_UNITS, R2
                AND     @R2, R1
                RBRA    _QS_NO, Z
_QS_YES         OR      0x0004, SR              ; C=1
                DECRB
                RET
_QS_NO          AND     0xFFFB, SR              ; C=0
                DECRB
                RET

; B3_HDF_SPACE (HANDLE_UNMOUNT_KEY, after B3_HDF_SPOK said yes): Space on line R8
; (as there). HDF 0 / 1: the drive is ejected (the Amiga restarts) and the
; profile forgets the file - while the quick HDF is on, only the profile forgets
; it. The quick line: the quick HDF is ejected, the profile's disks come back.
; Registers preserved.
B3_HDF_SPACE    SYSCALL(enter, 1)
                MOVE    R8, R0                  ; R0: the line
                CMP     2, R0
                RBRA    _QX_Q, Z
                MOVE    QHDF_ON, R1
                CMP     0, @R1
                RBRA    _QX_F, !Z
                MOVE    R0, R8                  ; as before: eject and forget
                RSUB    HDF_EJECT, 1
                RBRA    _QX_FG, 1
_QX_F           MOVE    HDF_DEV_TAB, R8         ; quick on: the line shows
                ADD     R0, R8                  ; <Load> again
                MOVE    @R8, R8
                MOVE    CRTROM_CSR_STATUS, R9
                MOVE    CRTROM_CSR_ST_IDLE, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    CRTROM_MAN_LDF, R8
                ADD     PROF_HDF_ID, R8
                ADD     R0, R8
                MOVE    0, @R8
_QX_FG          MOVE    R0, R9                  ; the profile forgets it
                ADD     PROF_HDF_ID, R9
                RSUB    PROF_FORGET, 1
                RBRA    _QX_RET, 1

_QX_Q           MOVE    QHDF_ON, R1             ; the quick HDF goes
                MOVE    0, @R1
                MOVE    AEXP_DEV_IDEQ, R8       ; its line: <Load>
                MOVE    CRTROM_CSR_STATUS, R9
                MOVE    CRTROM_CSR_ST_IDLE, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    CRTROM_MAN_LDF, R8
                ADD     PROF_QHDF_ID, R8
                MOVE    0, @R8
                MOVE    1, R8                   ; out of the master
                RSUB    HDF_DROP, 1
                XOR     R8, R8                  ; the profile's disks again (a
                MOVE    1, R9                   ; drive without one stays empty;
                RSUB    PROF_HDFS, 1            ; a mount restarts the Amiga)
                MOVE    HDF_UNITS, R8           ; none: restart it here (the
                CMP     0, @R8                  ; board has left the chain)
                RBRA    _QX_RET, !Z
                RSUB    IDE_RESET_AMIGA, 1
_QX_RET         SYSCALL(leave, 1)
                RET

; End of the bank BANK_IDE

                .ORG    0x9000                  ; M2M$CODE_WIN
                .DW     0x4B04                  ; bank 4: BANK_PROF
#include "profiles.asm"
#endif

; ----------------------------------------------------------------------------
; Variables: Need to be located in RAM
; ----------------------------------------------------------------------------

#ifdef RELEASE
                .ORG    0xA000                  ; RAM starts at 0xA000: the 4k device
                                                ; window takes 0x8000-0x8FFF (M2M-UPSTREAM
                                                ; rom-32k, the ROM is 32k words now), the
                                                ; code window 0x9000-0x9FFF (code-banks)
#endif

;
; add your own variables here
;

; ADF write-back state (see HANDLE_CORE_IO / FLUSH_ADF_STEP). Everything here
; is PER DRIVE: the scalars are three-word arrays indexed by the drive 0..2,
; and each drive owns a full file-handle snapshot of its own. That per-drive
; handle is the whole point - a single shared handle plus a second armed drive
; would flush the tracks of one drive into the file of another.
ADF_FDH0        .BLOCK FAT32$FDH_STRUCT_SIZE    ; our own snapshot of the file
ADF_FDH1        .BLOCK FAT32$FDH_STRUCT_SIZE    ; handle mounted into each
ADF_FDH2        .BLOCK FAT32$FDH_STRUCT_SIZE    ; drive: HNDL_RM_FILES[n] is
                                                ; re-opened by the Shell for
                                                ; the NEXT load, our snapshot
                                                ; stays valid until the card
                                                ; or the SD slot changes
                                                ; (reached via ADF_FDH_TAB)
ADF_FDH_VALID   .BLOCK ADF_DRIVES               ; 1: the FDH of that drive is
                                                ; usable, i.e. armed
ADF_SD_SLOT     .BLOCK ADF_DRIVES               ; SD card slot at arm time
ADF_SD_GEN      .BLOCK ADF_DRIVES               ; ... and its card generation
ADF_MOUNT_SEEN  .BLOCK ADF_DRIVES               ; 1: armed or blocked; 0: a
                                                ; fresh PARSEST=READY may arm
ADF_FL_STATE    .BLOCK ADF_DRIVES               ; 0: idle  1: track session
ADF_FL_REMAIN   .BLOCK ADF_DRIVES               ; bytes left in session track
ADF_FL_BADDR_LO .BLOCK ADF_DRIVES               ; session byte address within
ADF_FL_BADDR_HI .BLOCK ADF_DRIVES               ; image and file (32 bit)
ADF_FL_RR       .BLOCK 1                        ; drive that gets the next
                                                ; background flush time slice
RODATA_BUF      .BLOCK RODATA_BUF_SIZE          ; RAM copy of one read-only text
FL_NOBAR        .BLOCK 1                        ; PROFILE_APPLY: FAST_LOAD without bar
PROF_FDH        .BLOCK FAT32$FDH_STRUCT_SIZE    ; PROFILE_APPLY: the Kickstart / HDF file
PROF_PENDF      .BLOCK 1                        ; PROF_NAME: a name waits for the menu
PROF_PEND       .BLOCK PROF_PEND_NUM            ; its path labels (0 = none), by ROM id
; Megamiga 0.7: profiles as files (profiles.asm). NOT between PROF_PENDF and
; PROF_PEND: PROFILE_APPLY clears PROF_PENDF and PROF_PEND in one run.
PRF_NAME        .BLOCK 21                       ; the active profile (PRF_NLEN)
PRF_FILE        .BLOCK 25                       ; ... its file "NN_<name>" (PRF_FLEN)
PRF_FULL        .BLOCK 25                       ; a file name being chosen/made
PRF_TXT         .BLOCK CFGS_MAX                 ; its text
PRF_LEN         .BLOCK 1
PRF_DIRTY       .BLOCK 1                        ; 1: to be written back
PRF_PAINT       .BLOCK 1                        ; 1: the menu line shows the name
PRF_FDH         .BLOCK FAT32$FDH_STRUCT_SIZE
PRF_FNAME       .BLOCK 30                       ; "<file>.prof"
PRF_PATH        .BLOCK 46                       ; "/amiga/profiles/<file>.prof"
PRF_SAVCD       .BLOCK 2                        ; the current directory, saved
PRF_VAL         .BLOCK 16                       ; a value (PRF_VALN)
PRF_EDBUF       .BLOCK 21                       ; a name being edited/chosen
PRF_LINE        .BLOCK 24                       ; one line of the inner area
PRF_LN          .BLOCK 1                        ; the profiles in PRF_LIST
PRF_LIST        .BLOCK 500                      ; PRF_LMAX x PRF_FLEN
PROF_PATH       .BLOCK 128                      ; a remembered path (cfg text)
PROF_DEVP       .BLOCK 1                        ; _PR_PATHOF: the device handle
PROF_PNAME      .BLOCK 84                       ; PROF_PEND_NUM x PROF_PN_LEN:
                                                ; the names of remembered files
HDF_VPART       .BLOCK 1                        ; HDF_PREP: slot << 8 | 1..4 =
                                                ; mount this SD card partition,
                                                ; not the file
BRX_NAME        .BLOCK 32                       ; BROWSE_EXTRA: an entry's name
BRX_DEVREF      .BLOCK 1                        ; ... its card's device handle
BRX_DEC         .BLOCK 11                       ; its decimal size
FL_BAR_TOTAL    .BLOCK 1                        ; FAST_LOAD progress bar: sectors
FL_BAR_WIDTH    .BLOCK 1                        ; bar width in characters
FL_BAR_ACC      .BLOCK 1                        ; Bresenham accumulator

; ADF unmount-with-SPACE state (issue #16, see HANDLE_UNMOUNT_KEY)
ADF_UNMNT_PREV  .BLOCK 1                        ; SPACE state last poll (edge)
IDE_LAST_EV     .BLOCK 1                        ; event toggles seen so far
IDE_STATE       .BLOCK 1                        ; IDE_ST_*
IDE_LBA_LO      .BLOCK 1                        ; sector of the command
IDE_LBA_HI      .BLOCK 1
IDE_LEFT        .BLOCK 1                        ; sectors left in the command
IDE_BSIZE       .BLOCK 1                        ; sectors per block (MULTIPLE)
IDE_BPOS        .BLOCK 1                        ; sector within the block
#if IDE_DIAG
IDE_DLAST_T     .BLOCK 1                        ; diagnostics: time of the last
IDE_DLAST_W     .BLOCK 1                        ; line, data words then (lo)
#endif
HDF_UNITS       .BLOCK 1                        ; mounted drives: bit 0 master
                                                ; (unit 0), bit 1 slave (unit 1)
HDF_ACTIVE      .BLOCK 1                        ; drive whose state is in the
                                                ; block below (see HDF_SELECT)
QHDF_ON         .BLOCK 1                        ; 0.7: 1 = the quick HDF is the
                                                ; master, the profile's are out
HDF_DSLOT       .BLOCK 2                        ; per drive: its SD card slot
HDF_DGEN        .BLOCK 2                        ; ... and that card's generation
                                                ; at the mount (M2M-UPSTREAM
                                                ; sd-host, see IDE_STEP)
; The disk state of ONE drive, HDF_FDH up to HDF_SAVE. HDF_SELECT swaps it with
; HDF_SAVE, which holds the other drive; keep it contiguous and keep
; HDF_BLK_WORDS equal to its length (the fw-ide harness checks both).
HDF_FDH         .BLOCK FAT32$FDH_STRUCT_SIZE    ; our own copy of the HDF handle
HDF_SECT_LO     .BLOCK 1                        ; size of the HDF in sectors
HDF_SECT_HI     .BLOCK 1
HDF_MAPOK       .BLOCK 1                        ; 1: HDF_MAP describes the file
HDF_SPC_SHIFT   .BLOCK 1                        ; log2(sectors per cluster)
HDF_EXT_IDX     .BLOCK 1                        ; extent of the last block lookup
HDF_EXT_CLO     .BLOCK 1                        ; ... and the cluster index at
HDF_EXT_CHI     .BLOCK 1                        ; which it starts
HDF_PART        .BLOCK 1                        ; 0: an HDF file; 1..4: the SD
                                                ; card partition of a link file
HDF_PST_LO      .BLOCK 1                        ; ... and its first block
HDF_PST_HI      .BLOCK 1
HDF_HEADS       .BLOCK 1                        ; CHS geometry (INITIALIZE DEVICE
HDF_SPT         .BLOCK 1                        ; PARAMETERS), see IDE_TF_LBA
HDF_MULT        .BLOCK 1                        ; multiple count (SET MULTIPLE)
HDF_VRDB        .BLOCK 1                        ; Megamiga 0.7: blocks of the virtual
                                                ; RDB in front of the image (0: none)
HDF_VDOS_HI     .BLOCK 1                        ; ... and the DosType of its
HDF_VDOS_LO     .BLOCK 1                        ; partition (B3_VRDB_DET)
HDF_MAP         .BLOCK HDF_MAP_WORDS            ; FAT32$FILE_MAP extent map
HDF_SAVE        .BLOCK HDF_BLK_WORDS            ; the other drive
HDF_SAVE_END    .BLOCK 1
OSM_SUB_ACTIVE  .BLOCK 1                        ; 1 while the sub-activity of a
                                                ; menu selection (browser/help)
                                                ; runs: gate 4 for the unmount

; Screen adjustment (issue #5): file handle for /amiga/aexp_screen.cfg
SCR_FDH    .BLOCK FAT32$FDH_STRUCT_SIZE
; per-Amiga-mode table (loaded by LOAD_SCREEN_OFFSETS, applied by
; DETECT_SCREEN_MODE): 4 rows x 10 signed words = HDMI crop
; (himin,himax,vimin,vimax), analog overscan (os_l,os_r,os_t,os_b),
; analog pan (pan_x,pan_y)
SCR_TABLE        .BLOCK 40                       ; 4 mode rows x 10 words (HDMI 4 + overscan 4 + pan 2)
SCR_APPLIED_MODE .BLOCK 1                        ; 0..3 row / 4 unknown / NONE
SCR_CAND_MODE    .BLOCK 1                        ; debounce candidate mode
SCR_CAND_CNT     .BLOCK 1                        ; debounce counter
SCR_TICK         .BLOCK 1                        ; detector throttle counter

; Live Hardware Floppy status line (see HANDLE_CORE_IO / HWF_STATUS_STEP)
HWF_OSM_LAST    .BLOCK 1                        ; last painted coarse state,
                                                ; HWF_OS_INVALID = none
HWF_OSM_LDRV    .BLOCK 1                        ; drive whose line was painted
                                                ; last, HWF_DRV_NONE = none
HWF_OSM_TICK    .BLOCK 1                        ; last IO$CYC_MID value seen
HWF_LAST_CNT    .BLOCK 1                        ; served-word count last poll
HWF_LABEL       .BLOCK 23                       ; the built label: 22 chars
                                                ; plus the terminator
                                                ; (SD_STATUS_STEP uses it too)
SD_OSM_LAST     .BLOCK 1                        ; SD status line: last state
SD_OSM_TICK     .BLOCK 1                        ; last IO$CYC_MID value seen

; Battery-RTC reseed state (see HANDLE_CORE_IO / RTC_STEP, issue #13)
RTC_LAST_MIN    .BLOCK 1                        ; last internal minute seen by
                                                ; RTC_STEP; 0xFFFF = none yet

; Megamiga 0.6.1: the shared folder (see SHARE_STEP)
SHARE_DEV       .BLOCK  FAT32$DEV_STRUCT_SIZE   ; device handle of the volume
SHR_UP          .BLOCK 1                        ; 1: the volume is mounted
SHR_GEN         .BLOCK 1                        ; generation 1..0x7FFF
SHR_LASTREQ     .BLOCK 1                        ; last request number seen
SHR_RSTSEEN     .BLOCK 1                        ; last Amiga reset count seen
SHR_SDGEN       .BLOCK 1                        ; generation of the external
                                                ; card seen last (sdcards.asm)
SHR_INSW        .BLOCK 1                        ; the menu toggle seen last
SHR_EVC         .BLOCK 6                        ; event counters (SHR_EV_*)
SHR_MNT_PEND    .BLOCK 1                        ; 1: mount after SHR_MNT_T
SHR_MNT_T       .BLOCK 1                        ; IO$CYC_MID at the event
SHR_TOTAL       .BLOCK 2                        ; blocks of the volume (lo, hi)
SHR_USED        .BLOCK 2                        ; used blocks (lo, hi)
SHR_ROOTLOCK    .BLOCK 8                        ; the lock of key 0 (/amiga)
SHR_OT          .BLOCK 1                        ; the current object: type,
SHR_OC          .BLOCK 2                        ; cluster (a directory: its own,
                                                ; a file: its directory),
SHR_OEA         .BLOCK 3                        ; entry address (0: unknown),
SHR_OPC         .BLOCK 2                        ; the directory of the entry
                                                ; (the layout of a lock slot)
SHR_CVAL        .BLOCK 1                        ; directory cursor: valid,
SHR_CCLO        .BLOCK 1                        ; cluster, number of entries
SHR_CCHI        .BLOCK 1                        ; returned, slot number of the
SHR_CIDX        .BLOCK 1                        ; last one, its entry address,
SHR_CORD        .BLOCK 1                        ; the directory's cluster count
SHR_CEA         .BLOCK 3                        ; and the cluster seen last
SHR_CCIX        .BLOCK 1
SHR_CLCL        .BLOCK 2
SHR_CFDH        .BLOCK  FAT32$FDH_STRUCT_SIZE
SHR_PATH_LEN    .BLOCK 1                        ; the path of the request
SHR_CPOS        .BLOCK 1                        ; the component being looked up
SHR_CLEN        .BLOCK 1
SHR_PATH        .BLOCK 256                      ; one character per word
SHR_DE          .BLOCK  FAT32$DE_STRUCT_SIZE    ; directory entry
SHR_LOCKS       .BLOCK 512                      ; SHR_LOCKS_N x SHR_LOCK_SZ
SHR_FILES       .BLOCK 192                      ; SHR_FILES_N x SHR_FILE_SZ
SHR_NAME        .BLOCK 108                      ; a name for the write layer
SHR_FDATE       .BLOCK 2                        ; the request time as FAT date,
                                                ; time
SHR_MISS        .BLOCK 1                        ; SHR_RESOLVE: 1 = only the last
                                                ; component is missing
SHR_SPDIRTY     .BLOCK 1                        ; 1: SHR_TOTAL/USED are stale
SHR_RNOBJ       .BLOCK 8                        ; RENAME: the object

; M2M Shell variables (only include, if you included "shell.asm" above)
#include "../../M2M/rom/shell_vars.asm"

; ----------------------------------------------------------------------------
; Heap and Stack: Need to be located in RAM after the variables
; ----------------------------------------------------------------------------

; The On-Screen-Menu uses the heap for several data structures. This heap
; is located before the main system heap in memory.
; You need to deduct MENU_HEAP_SIZE from the actual heap size below.
; Example: If your HEAP_SIZE would be 30208, then you write 30208-1920=28288
; instead, but when doing the sanity check calculations, you use 30208
;
; Budget (HELP_MENU in M2M/rom/options.asm, checked at runtime by LOG_HEAP1/
; LOG_HEAP2): the 154 menu items are a 1471-character string plus the 20-word
; menu structure plus FOUR per-item arrays = 20 + 1471 + 1 + 4 x 154 + 1 =
; 2109 words; on top of that, OPTM_HEAP needs one (OPTM_DX + 2)-wide buffer
; per submenu (9), manual ROM (3) and vdrive (0) plus one scratch buffer =
; 13 x 25 = 325 words. Total demand is 2434 words, rounded up to the next
; 32-word boundary: 2464 words, leaving 30 words headroom. (WIP-V2-A11-JS-01:
; the Memory submenu with the Fast RAM toggle grew the menu 148 -> 154 items,
; demand 2325 -> 2434, MENU_HEAP_SIZE 2336 -> 2464, both HEAP_SIZE -128.)
; Round to 32 and no further. Every word reserved here is taken directly
; from the file browser - FB_HEAP starts at HEAP + MENU_HEAP_SIZE
; (M2M/rom/shell.asm) - and a small
; quantum still absorbs the usual menu-text tweak without an edit. Allocating
; tight is safe because a shortfall is LOUD, never silent: HELP_MENU checks
; the permanent structure against MENU_HEAP_SIZE (ERR_FATAL_HEAP1) and the
; OPTM_HEAP demand against whatever is left over (ERR_FATAL_HEAP2), so the
; core stops with a fatal screen at boot and on every menu open - and
; .research/check_osm_menu.py catches it statically long before that.
; Whenever OPTM_SIZE, OPTM_ITEMS, OPTM_DX, or the submenu/drive/
; manual-ROM counts grow, recalculate both budgets and rebalance the
; HEAP_SIZE constants below by the same delta.
; .research/check_osm_menu.py recomputes all of this from config.vhd.
;
; HELP_MENU_INIT additionally borrows 20 + 3 x 154 = 482 words of this region
; as transient scratch for the boot-time dependency validation (_HLP_DEPVAL in
; M2M/rom/options.asm) - far below the permanent demand, so it never binds.
;
; The fourth per-item array and the 19th->20th structure word are the menu
; dependency feature (M2M-UPSTREAM osm-deps); the manual-ROM count grew from
; 1 to 3 with the second and third simulated floppy drive, and to 4 with the
; HDF line of the IDE board (WIP-V2-A11-JS-02: 156 items, demand 2478), and to
; 5 with the Kickstart selector of the Memory menu (Megamiga 0.2: 158 items,
; demand 2528 = exactly 79 x 32, so MENU_HEAP_SIZE 2496 -> 2528 with no
; headroom - both checks fail only on demand > size - and both HEAP_SIZE -32),
; and to 160 items with the Drive spin-up delay toggle (demand 2560, again
; exactly 80 x 32: MENU_HEAP_SIZE 2560, both HEAP_SIZE -32), and to 164 items
; with the Zorro III RAM toggle and the CPU radio (demand 2628, MENU_HEAP_SIZE
; 2656, headroom 28, both HEAP_SIZE -96), and to 168 items with the chipset
; radio (demand 2691, MENU_HEAP_SIZE 2720, headroom 29, both HEAP_SIZE -64).
; Megamiga 0.3 machine profiles (A500 / A600 / A1200 with one settings block
; each) and the Settings page with nested submenus: 206 items, 10 submenus,
; demand 3403, MENU_HEAP_SIZE 3424, headroom 21, both HEAP_SIZE -704.
; Megamiga 0.3.1 master + slave HDF: 207 items, 6 manual ROMs, demand 3445,
; MENU_HEAP_SIZE 3456, headroom 11, both HEAP_SIZE -32.
; Megamiga serial port on PMOD (Settings > Ports): 211 items, demand 3495,
; MENU_HEAP_SIZE 3520, headroom 25, both HEAP_SIZE -64.
; Megamiga 68040: the blank line after each profile's CPU radio became " CPU: 68040"
; (+33 characters, still 211 items), demand 3528, MENU_HEAP_SIZE 3552, headroom 24,
; release HEAP_SIZE -32 (the combined total and the stack margin are unchanged).
; Megamiga 0.6.1: " SDCard: inserted" (shared folder toggle) and a line after the
; profile radio: 213 items, demand 3557, MENU_HEAP_SIZE 3584, headroom 27, release
; HEAP_SIZE -32 (the combined total is unchanged).
; Megamiga 0.6.1 fast disks: the live SD card status line at the bottom of the
; main menu (+25 characters, 214 items): demand 3586, MENU_HEAP_SIZE 3616,
; headroom 30, release HEAP_SIZE -32 (the combined total is unchanged).
;MENU_HEAP_SIZE  .EQU 3584
;MENU_HEAP_SIZE  .EQU 3616
; Megamiga 0.6.2 freezer cartridges: a cartridge radio per profile (+4 lines each,
; with its blank line), the " AR3 ROM:%s" line (7 manual ROMs) and "Freeze
; cartridge" with its blank line (229 items): demand 3867, MENU_HEAP_SIZE 3872,
; headroom 5, release HEAP_SIZE -256 (the combined total is unchanged).
;MENU_HEAP_SIZE  .EQU 3872
; Megamiga 0.6.3 RTG native resolution: the line before "Back to Settings" in
; the HDMI submenu became the "RTG native resolution" toggle (+22 characters,
; 229 items): demand 3889, MENU_HEAP_SIZE 3904, headroom 15, release HEAP_SIZE
; -32 (the combined total is unchanged).
;MENU_HEAP_SIZE  .EQU 3904
; Megamiga 0.6.4 A4000 profile: " A4000 (AGA)" in the profile radio (its
; separator line kept) and the A4000 block in Profile Settings (19 lines, +271
; characters, 248 items): demand 4236, MENU_HEAP_SIZE 4256, headroom 20, release
; HEAP_SIZE -352 (the combined total is unchanged).
;MENU_HEAP_SIZE  .EQU 4256
; Megamiga 0.7 merged onto 0.6.4: the blank line after the chipset radio of each
; of the four profiles became the Gayle IDE controller toggle (+84 characters,
; still 248 items): demand 4320 = exactly 135 x 32, MENU_HEAP_SIZE 4320, headroom
; 0 (both checks fail only on demand > size), release HEAP_SIZE -64.
;MENU_HEAP_SIZE  .EQU 4320
; Megamiga 0.7 48 MB Zorro III: the blank line after the "Zorro III RAM (16 MB)"
; toggle of each profile became " Zorro III RAM (32 MB)" (+88 characters, still
; 248 items): demand 4408, MENU_HEAP_SIZE 4416, headroom 8, release HEAP_SIZE -96.
;MENU_HEAP_SIZE  .EQU 4416
; Megamiga 0.7 menu rows (M2M-UPSTREAM menu-rows): the options of CPU, Chip RAM,
; Slow RAM and Monitor Cartridge carry only their option text, the Slow RAM
; separator became "Slow RAM: None" (-148 characters, still 248 items): demand
; 4260, MENU_HEAP_SIZE 4288, headroom 28, release HEAP_SIZE +128.
;MENU_HEAP_SIZE  .EQU 4288
; Megamiga 0.7 profile page: rows for Chipset and Hard Disk Controller, a Zorro
; Boards section with Graphics/Network Card, Virtual Drive Sound; the 19
; separators under headlines are no items any more (+200 characters, 252 items):
; demand 4476, MENU_HEAP_SIZE 4480, headroom 4, release HEAP_SIZE -192.
;MENU_HEAP_SIZE  .EQU 4480
; Megamiga 0.7 profiles as files: ONE profile block, the " Profile:" and
; " Rename Profile" lines instead of the radio (181 items, 2020 characters):
; demand 3242, MENU_HEAP_SIZE 3264, headroom 22. The variables of profiles.asm
; (PRF_*, 1103 words) take the rest: see HEAP_SIZE.
;MENU_HEAP_SIZE  .EQU 3264
; Megamiga 0.7 quick HDF: the " hdf:%s" line of the main page (182 items, +9
; characters) and its manual CRT/ROM load (one more OPTM_HEAP buffer of OPTM_DX
; + 2 = 25 words): demand 3242 + 9 + 4 + 25 = 3280, MENU_HEAP_SIZE 3296,
; headroom 16, release HEAP_SIZE -32.
; Megamiga 0.7 NTSC: " NTSC (60 Hz)" at the end of the Display block of Settings (183 items,
; +15 characters + 4 words) and the HDMI mode lines without "50 Hz" (-8 characters):
; demand 3280 + 11 = 3291, MENU_HEAP_SIZE 3296 unchanged, headroom 5.
MENU_HEAP_SIZE  .EQU 3296

#ifndef RELEASE

; heap for storing the sorted structure of the current directory entries
; this needs to be the last variable before the monitor variables as it is
; only defined as "BLOCK 1" to avoid a large amount of null-values in
; the ROM file
; The combined total (HEAP_SIZE + MENU_HEAP_SIZE) was lowered from the C64
; figure of 30208 to 30080 words when the per-drive write-back and the live
; Hardware Floppy status line added 66 words of firmware VARIABLES: those sit
; below the heap, so they push HEAP up and eat directly into the space that is
; left for the stack between the end of the heap and VAR$STACK_START. Check it
; the way hard rule 11 of AGENTS.md describes, in the assembled m2m-rom.lis:
; HEAP 0x8280 + 30080 = 0xF800, VAR$STACK_START 0xFEE0, so 1760 words remain
; for a STACK_SIZE of 1536 - a 224-word margin, slightly better than the 1728
; words the 30208 total used to leave.
; WIP-V2-A11-JS-02: the IDE board added 280 words of variables (mostly the HDF
; extent map), so the release total went down by 384 words to 29696.
; Megamiga 0.2: RODATA_BUF (200 words, the RAM copy of a text from the
; read-only data device) - both totals down by 256 (release 29440, debug 6784).
; Megamiga 0.3.1: the slave HDF state (HDF_SAVE, 278 words of variables) - both
; totals down by 288 (release 29152, debug 6496).
; Megamiga, M2M-UPSTREAM rom-32k: the RAM lost 4096 words to the device
; window; the develop mode (firmware in RAM) has not fit for a long time, so
; its heap is only kept at a value that assembles.
HEAP_SIZE       .EQU 0
HEAP            .BLOCK 1

; in RELEASE mode: 26.97k of heap for folders with many files
#else

; Megamiga, M2M-UPSTREAM rom-32k: the device window moved into the RAM
; (0x8000-0x8FFF), so the variables start at 0x9000 and the combined total is
; 4096 words smaller: 25056 (the stack margin stays the same).
; Megamiga 0.6.1: the shared folder added 966 words of variables (SHARE_*,
; SHR_*), so the combined total went down by 992 to 24064.
;HEAP_SIZE       .EQU 21504                      ; 25056 - 3552 = 21504
; Megamiga, M2M-UPSTREAM code-banks: the code window takes 0x9000-0x9FFF, so
; the variables start at 0xA000 and the combined total is 4096 words smaller:
; 19968 (the stack margin stays the same).
; Megamiga 0.6.1: the shared folder writes (locks and open files grew, the
; write layer's parameter block, names, the larger device handles) - the
; combined total is 640 words smaller: 19328, stack margin 256 words.
; Megamiga 0.6.1: text in the settings file (M2M-UPSTREAM cfg-strings: CFGS_*)
; and the files a profile remembers (PROF_PATH, PROF_PNAME) added 705 words:
; the combined total is 736 words smaller: 18592, stack margin 287 words.
; Partitions in the HDF browser (HDF_VPART, BRX_*) and SF_VIRTUAL: 45 words,
; the combined total is 32 words smaller: 18560, stack margin 274 words.
;HEAP_SIZE       .EQU 14976                      ; 18560 - 3584 = 14976
; M2M-UPSTREAM sd-host, two slots (both SD cards at once): the per-slot card
; state, the browser's card and the per-drive card generations added 17 words:
; the combined total is 32 words smaller: 18528, stack margin 287 words.
;HEAP_SIZE       .EQU 14944                      ; 18560 - 3616 = 14944
;HEAP_SIZE       .EQU 14912                      ; 18528 - 3616 = 14912
;HEAP_SIZE       .EQU 14656                      ; 18528 - 3872 = 14656
;HEAP_SIZE       .EQU 14624                      ; 18528 - 3904 = 14624
;HEAP_SIZE       .EQU 14272                      ; 18528 - 4256 = 14272
;HEAP_SIZE       .EQU 14208                      ; 18528 - 4320 = 14208
;HEAP_SIZE       .EQU 14112                      ; 18528 - 4416 = 14112
;HEAP_SIZE       .EQU 14240                      ; 18528 - 4288 = 14240
;HEAP_SIZE       .EQU 14048                      ; 18528 - 4480 = 14048
; Megamiga 0.7 profiles as files: PRF_* added 1103 words of variables, so the
; combined total is 1120 words smaller: 17408; HEAP 0xB418 + 17408 = 0xF818,
; VAR$STACK_START 0xFED0: 1720 words for the stack (1703 before).
;HEAP_SIZE       .EQU 14144                      ; 17408 - 3264 = 14144
; The sort order (file names "NN_<name>"): PRF_FILE, PRF_FULL, longer file
; names and list entries, 138 words more: the combined total is 160 words
; smaller: 17248.
;HEAP_SIZE       .EQU 13984                      ; 17248 - 3264 = 13984
HEAP_SIZE       .EQU 13952                      ; 17248 - 3296 = 13952
HEAP            .BLOCK 1

; The monitor variables use 22 words, round to 32 for being safe and subtract
; it from FF00 because this is at the moment the highest address that we
; can use as RAM: 0xFEE0
; The stack starts at 0xFEE0 (search var VAR$STACK_START in osm_rom.lis to
; calculate the address). To see, if there is enough room for the stack
; given the HEAP_SIZE do this calculation: Add 30080 words to HEAP which
; is currently 0x8280 and subtract the result from 0xFEE0. This yields
; 1760 stack words, 224 more than STACK_SIZE. Recheck the HEAP and
; VAR$STACK_START addresses in m2m-rom.lis whenever variables are added.

; Megamiga: 0xFED0 since the FAT32 write layer grew the device handle
; (_SD$DEVICEHANDLE of qmon_vars.asm) to 27 words: 0xFED0 + 5 + 27 = 0xFEF0
; leaves 16 words below the IO page at 0xFF00 (0xFEE0 would end exactly at it).
                .ORG    0xFED0                  ; TODO: automate calculation
#endif

; STACK_SIZE: Size of the global stack and should be a minimum of 768 words
; after you subtract B_STACK_SIZE.
; B_STACK_SIZE: Size of local stack of the the file- and directory browser. It
; should also have a minimum size of 768 words. If you are not using the
; Shell, then B_STACK_SIZE is not used.
STACK_SIZE      .EQU    1536
B_STACK_SIZE    .EQU    768

#include "../../M2M/rom/main_vars.asm"
