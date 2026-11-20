; ****************************************************************************
; Megamiga 0.7: machine profiles are files (code bank 4, BANK_PROF)
;
; A profile is /amiga/profiles/<name>.prof on the card of the settings file:
; text lines "key=value" (doc/developers/profiles.md). Profile Settings holds
; ONE block of menu items (C_MENU_PROF_BASE in mega65.vhd): the settings of
; the active profile. Choosing a profile loads its file into the block
; (_P_APPLY) and its Kickstart / hard disks (PROFILE_APPLY); a change in the
; block or of a remembered file marks it dirty, and it is written back once
; the menu is closed (B4_PRF_STEP). The settings file only remembers the name
; of the active profile ("profile=<name>").
;
; The text of the active profile lives in PRF_TXT. The key/value routines of
; cfgstr.asm work on CFGS_BUF; _P_SWAP exchanges the two (and their lengths
; and dirty flags), so the same tested code reads and writes both.
;
; The defaults (A500, A600, A1200, A4000) are created only when the directory
; does not exist or holds no profile: otherwise the user deliberately changed
; them. The firmware's own profile selector lists the profiles, a separator
; bar and "Add New Profile"; the name editor (Add New / Rename Profile) reads
; the whole keyboard through C_DEV_AMIGA_KEYS (mega65.vhd) and accepts only
; the characters FAT32 allows in long names.
;
; The order of the profiles: a file name may start with a number and "_"
; ("02_A600.prof"), which the menu does not show. The profiles are sorted by
; that number (files without one behind the others), then by name. In the
; selector Left moves the profile under the cursor up and Right down: the files
; are then renamed "01_<name>", "02_<name>", ... in the new order (_P_RENUM).
; The settings file names the active profile without the number, so a renumber
; does not touch it. PRF_NAME is the name, PRF_FILE the file name ("full name").
;
; Every routine that changes the current directory of the card (f32_cd)
; restores it: the file browser walks into directories relative to it.
;
; Done by Megamiga in 2026 and licensed under GPL v3
; ****************************************************************************

PRF_NMAX        .EQU    20                      ; characters of a name
PRF_NLEN        .EQU    21                      ; a name + its zero
PRF_FMAX        .EQU    24                      ; a file name: "123_" + a name
PRF_FLEN        .EQU    25                      ; ... + its zero
PRF_LMAX        .EQU    20                      ; profiles the selector lists
PRF_VALN        .EQU    16                      ; a value + its zero
PRF_LBL_OFS     .EQU    9                       ; " Profile:" | the name
PRF_LBL_LEN     .EQU    12                      ; ... in the menu line
PRF_KMASK       .EQU    0x0070                  ; M2M$KEY_RETURN|SPACE|RUNSTOP

_PS_DIR         .ASCII_W "/amiga/profiles"
_PS_AMIGA       .ASCII_W "/amiga"
_PS_DIRNAME     .ASCII_W "profiles"
_PS_EXT         .ASCII_W ".prof"
_PS_KEY         .ASCII_W "profile"              ; in the settings file
_PS_USER        .ASCII_W "User "
_PS_TITLE       .ASCII_W " Profiles"
_PS_ADD         .ASCII_W " Add New Profile"
_PS_ETITLE      .ASCII_W " Profile name:"
_PS_EHELP1      .ASCII_W " Return: OK"
_PS_EHELP2      .ASCII_W " Run/Stop: cancel"
_PS_EXISTS      .ASCII_W " That name exists."
_PS_MOVE        .ASCII_W " Left/Right: reorder"
_PS_ON          .ASCII_W "on"
_PS_OFF         .ASCII_W "off"

; the keys: key, offset in the block, number of values (0: a toggle on/off),
; the values (radio); PRF_KW words each
PRF_KW          .EQU    6
PRF_KN          .EQU    11
PRF_KTAB        .DW     _PK_CPU,  0, 3, _PV_68000, _PV_68020, _PV_68040
                .DW     _PK_CS,   3, 3, _PV_OCS, _PV_ECS, _PV_AGA
                .DW     _PK_HDC,  6, 3, _PV_NONE, _PV_GAYLE, _PV_RIPPLE
                .DW     _PK_CHIP, 9, 3, _PV_512K, _PV_1M, _PV_2M
                .DW     _PK_SLOW, 12, 2, _PV_NONE, _PV_512K, 0
                .DW     _PK_CART, 14, 3, _PV_NONE, _PV_HRT, _PV_AR3
                .DW     _PK_Z2,   18, 0, 0, 0, 0
                .DW     _PK_Z3,   19, 0, 0, 0, 0
                .DW     _PK_Z3B,  20, 0, 0, 0, 0
                .DW     _PK_GFX,  21, 0, 0, 0, 0
                .DW     _PK_NET,  22, 0, 0, 0, 0
_PK_CPU         .ASCII_W "cpu"
_PK_CS          .ASCII_W "chipset"
_PK_HDC         .ASCII_W "hdc"
_PK_CHIP        .ASCII_W "chip"
_PK_SLOW        .ASCII_W "slow"
_PK_CART        .ASCII_W "cart"
_PK_Z2          .ASCII_W "z2ram"
_PK_Z3          .ASCII_W "z3ram16"
_PK_Z3B         .ASCII_W "z3ram32"
_PK_GFX         .ASCII_W "gfx"
_PK_NET         .ASCII_W "net"
_PV_68000       .ASCII_W "68000"
_PV_68020       .ASCII_W "68020"
_PV_68040       .ASCII_W "68040"
_PV_OCS         .ASCII_W "OCS"
_PV_ECS         .ASCII_W "ECS"
_PV_AGA         .ASCII_W "AGA"
_PV_NONE        .ASCII_W "none"
_PV_GAYLE       .ASCII_W "gayle"
_PV_RIPPLE      .ASCII_W "ripple"
_PV_512K        .ASCII_W "512K"
_PV_1M          .ASCII_W "1M"
_PV_2M          .ASCII_W "2M"
_PV_HRT         .ASCII_W "hrtmon"
_PV_AR3         .ASCII_W "ar3"

; the default profiles: the value of every key (radio: its index; toggle: 0/1)
; in PRF_KTAB order; row 0 (A500) is also the value of a missing key
PRF_DEFN        .EQU    4
PRF_DEFS        .DW     0, 0, 2, 0, 1, 0, 0, 0, 0, 0, 1     ; A500
                .DW     0, 1, 1, 2, 0, 0, 0, 0, 0, 0, 1     ; A600
                .DW     1, 2, 1, 2, 0, 0, 0, 0, 0, 1, 1     ; A1200
                .DW     2, 2, 2, 2, 0, 0, 0, 1, 0, 1, 1     ; A4000
PRF_DNAMES      .DW     _PD_F500, _PD_F600, _PD_F1200, _PD_F4000
_PD_F500        .ASCII_W "01_A500"
_PD_F600        .ASCII_W "02_A600"
_PD_F1200       .ASCII_W "03_A1200"
_PD_F4000       .ASCII_W "04_A4000"
_PD_A500        .ASCII_W "A500"

; the MEGA65 keyboard (key numbers of m2m_keyb.vhd) as characters: two words
; per key, without and with Shift, as the MEGA65 keycaps print them
; (keyboard.vhd, MEGA65 mode); 0 = no character, or one FAT32 does not allow
; in a long name (" * / : < > ? \ |)
PRF_KEYMAP      .DW     0, 0,       0, 0,       0, 0,       0, 0        ;  0 DEL RET RIGHT F7
                .DW     0, 0,       0, 0,       0, 0,       0, 0        ;  4 F1 F3 F5 DOWN
                .DW     0x33, 0x23, 0x77, 0x57, 0x61, 0x41, 0x34, 0x24  ;  8 3 W A 4
                .DW     0x7A, 0x5A, 0x73, 0x53, 0x65, 0x45, 0, 0        ; 12 Z S E LSHIFT
                .DW     0x35, 0x25, 0x72, 0x52, 0x64, 0x44, 0x36, 0x26  ; 16 5 R D 6
                .DW     0x63, 0x43, 0x66, 0x46, 0x74, 0x54, 0x78, 0x58  ; 20 C F T X
                .DW     0x37, 0x27, 0x79, 0x59, 0x67, 0x47, 0x38, 0x28  ; 24 7 Y G 8
                .DW     0x62, 0x42, 0x68, 0x48, 0x75, 0x55, 0x76, 0x56  ; 28 B H U V
                .DW     0x39, 0x29, 0x69, 0x49, 0x6A, 0x4A, 0x30, 0     ; 32 9 I J 0
                .DW     0x6D, 0x4D, 0x6B, 0x4B, 0x6F, 0x4F, 0x6E, 0x4E  ; 36 M K O N
                .DW     0x2B, 0,    0x70, 0x50, 0x6C, 0x4C, 0x2D, 0     ; 40 + P L -
                .DW     0x2E, 0,    0,    0x5B, 0x40, 0,    0x2C, 0     ; 44 . : @ ,
                .DW     0,    0,    0,    0,    0x3B, 0x5D, 0,    0     ; 48 GBP * ; HOME
                .DW     0,    0,    0x3D, 0x5F, 0x5E, 0,    0,    0     ; 52 RSHIFT = ^ /
                .DW     0x31, 0x21, 0x5F, 0x60, 0,    0,    0x32, 0     ; 56 1 <- CTRL 2
                .DW     0x20, 0x20, 0,    0,    0x71, 0x51, 0,    0     ; 60 SPACE MEGA Q STOP
                .DW     0, 0, 0, 0, 0, 0, 0, 0                          ; 64
                .DW     0, 0, 0, 0, 0, 0, 0, 0                          ; 68
                .DW     0, 0, 0, 0, 0, 0, 0, 0                          ; 72
                .DW     0, 0, 0, 0, 0, 0, 0, 0                          ; 76
PRF_K_DEL       .EQU    0                       ; INS/DEL: delete to the left
PRF_K_RET       .EQU    1
PRF_K_RIGHT     .EQU    2
PRF_K_HOME      .EQU    51                      ; CLR/HOME (Shift: clear)
PRF_K_STOP      .EQU    63
PRF_K_ESC       .EQU    71
PRF_K_LEFT      .EQU    74

; ----------------------------------------------------------------------------
; Small helpers (INCRB style: results in R8..R12 or C)
; ----------------------------------------------------------------------------

; _P_SWAP: exchange the text of the settings file (CFGS_LEN, CFGS_DIRTY,
; CFGS_BUF) with the text of the active profile. All registers preserved.
_P_SWAP         INCRB
                MOVE    CFGS_LEN, R0
                MOVE    PRF_LEN, R1
                MOVE    @R0, R2
                MOVE    @R1, @R0
                MOVE    R2, @R1
                MOVE    CFGS_DIRTY, R0
                MOVE    PRF_DIRTY, R1
                MOVE    @R0, R2
                MOVE    @R1, @R0
                MOVE    R2, @R1
                MOVE    CFGS_BUF, R0
                MOVE    PRF_TXT, R1
                MOVE    CFGS_MAX, R3
_P_SW1          MOVE    @R0, R2
                MOVE    @R1, @R0++
                MOVE    R2, @R1++
                SUB     1, R3
                RBRA    _P_SW1, !Z
                DECRB
                RET

; _P_KGET: the value of key R8 in the profile text -> PRF_VAL; C=1 if the key
; is there. All registers preserved.
_P_KGET         INCRB
                MOVE    R9, R0
                MOVE    R10, R1
                RSUB    _P_SWAP, 1
                MOVE    PRF_VAL, R9
                MOVE    PRF_VALN, R10
                RSUB    CFGS_GET, 1
                MOVE    SR, R2                  ; (C of CFGS_GET)
                RSUB    _P_SWAP, 1
                MOVE    R0, R9
                MOVE    R1, R10
                AND     0x0004, R2
                AND     0xFFFB, SR
                OR      R2, SR
                DECRB
                RET

; _P_KSET: key R8 := value R9 in the profile text (PRF_DIRTY if it changed).
; All registers preserved.
_P_KSET         INCRB
                RSUB    _P_SWAP, 1
                RSUB    CFGS_SET, 1
                RSUB    _P_SWAP, 1
                DECRB
                RET

; _P_UP: R8 as an upper-case letter (other characters unchanged)
; (CMP a, b: N = a > b, unsigned)
_P_UP           CMP     0x0061, R8              ; "a" > R8?
                RBRA    _P_UP_R, N
                CMP     R8, 0x007A              ; R8 > "z"?
                RBRA    _P_UP_R, N
                SUB     0x0020, R8
_P_UP_R         RET

; _P_ICMP: compare the strings R8 and R9, upper and lower case alike:
; R10 = 0 equal, negative R8 < R9, positive R8 > R9. R8, R9 preserved.
_P_ICMP         INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    R8, R3                  ; (R8 is global: kept here)
_P_IC1          MOVE    @R0++, R8
                RSUB    _P_UP, 1
                MOVE    R8, R2
                MOVE    @R1++, R8
                RSUB    _P_UP, 1
                MOVE    R2, R10
                SUB     R8, R10
                RBRA    _P_IC2, !Z
                CMP     0, R2                   ; both at their end
                RBRA    _P_IC1, !Z
_P_IC2          MOVE    R3, R8
                DECRB
                RET

; _P_PFX: the file name R8 ("<number>_<name>" or "<name>") -> R9 = its number
; (1 to 3 digits; 0xFFFF: none), R10 = its name (what the menu shows). R8
; preserved.
_P_PFX          INCRB
                MOVE    R8, R0
                XOR     R1, R1                  ; R1: number
                XOR     R2, R2                  ; R2: digits
_P_PF_L         MOVE    @R0, R3
                CMP     0x0030, R3              ; "0" > R3?
                RBRA    _P_PF_E, N
                CMP     R3, 0x0039              ; R3 > "9"?
                RBRA    _P_PF_E, N
                MOVE    R1, R4                  ; R1 := R1 x 10 + the digit
                AND     0xFFFD, SR              ; (SHL fills with X)
                SHL     3, R1
                AND     0xFFFD, SR
                SHL     1, R4
                ADD     R4, R1
                SUB     0x0030, R3
                ADD     R3, R1
                ADD     1, R0
                ADD     1, R2
                CMP     4, R2                   ; four digits: no number
                RBRA    _P_PF_L, !Z
                RBRA    _P_PF_NO, 1
_P_PF_E         CMP     0, R2
                RBRA    _P_PF_NO, Z
                CMP     0x005F, R3              ; "_"
                RBRA    _P_PF_NO, !Z
                ADD     1, R0
                CMP     0, @R0                  ; a name must follow
                RBRA    _P_PF_NO, Z
                MOVE    R1, R9
                MOVE    R0, R10
                DECRB
                RET
_P_PF_NO        MOVE    0xFFFF, R9
                MOVE    R8, R10
                DECRB
                RET

; _P_LCMP: the order of the profiles R8 and R9 (file names): by their numbers
; (none: behind all), then by their names, upper and lower case alike: R10 = 0
; equal, negative R8 first, positive R9 first. R8, R9 preserved.
_P_LCMP         INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                RSUB    _P_PFX, 1
                MOVE    R9, R2                  ; R2: number of R8
                MOVE    R10, R3                 ; R3: name of R8
                MOVE    R1, R8
                RSUB    _P_PFX, 1               ; R9: number, R10: name of R9
                CMP     R2, R9                  ; R8's number higher?
                RBRA    _P_LC_GT, N
                CMP     R9, R2                  ; R9's number higher?
                RBRA    _P_LC_LT, N
                MOVE    R3, R8
                MOVE    R10, R9
                RSUB    _P_ICMP, 1
                RBRA    _P_LC_R, 1
_P_LC_GT        MOVE    1, R10
                RBRA    _P_LC_R, 1
_P_LC_LT        MOVE    0xFFFF, R10
_P_LC_R         MOVE    R0, R8
                MOVE    R1, R9
                DECRB
                RET

; _P_MKFULL: PRF_FULL := number R8 (1..99, two digits) + "_" + name R9.
; Registers preserved.
_P_MKFULL       SYSCALL(enter, 1)
                MOVE    R9, R0
                MOVE    10, R9
                SYSCALL(divu, 1)                ; R10: tens, R11: ones
                MOVE    PRF_FULL, R1
                ADD     0x0030, R10
                MOVE    R10, @R1++
                ADD     0x0030, R11
                MOVE    R11, @R1++
                MOVE    0x005F, @R1++
                MOVE    R0, R8
                MOVE    R1, R9
                SYSCALL(strcpy, 1)
                SYSCALL(leave, 1)
                RET

; _P_ADDR: the address of a radio/toggle item: R8 = offset in the block ->
; R8 = its menu item index
_P_ADDR         ADD     AEXP_OSM_PROF_BASE, R8
                RET

; _P_SET: menu item R8 := R9 (0/1): the register of the hardware
; (M2M$SET_SETTING) and, while the menu is open, its selection array, from
; which the redraw after the selector paints. (Not M2M$FORCE_MENU: OPTM_SET
; goes fatal for a radio item that is already selected - HW, prof-p3.)
; Registers preserved.
_P_SET          INCRB
                RSUB    M2M$SET_SETTING, 1
                MOVE    M2M$CSR, R0             ; the menu on screen?
                MOVE    @R0, R0
                AND     M2M$CSR_OSM, R0
                RBRA    _P_SET_R, Z
                MOVE    OPTM_DATA, R0
                MOVE    @R0, R0
                CMP     0, R0
                RBRA    _P_SET_R, Z
                ADD     OPTM_IR_STDSEL, R0
                MOVE    @R0, R0
                ADD     R8, R0
                MOVE    R9, @R0
_P_SET_R        DECRB
                RET

; ----------------------------------------------------------------------------
; The profile text and the menu block
; ----------------------------------------------------------------------------

; _P_APPLY: the profile text -> the menu block (and so the hardware): every key
; of PRF_KTAB; a missing or unknown value takes the A500 default. Registers
; preserved.
_P_APPLY        SYSCALL(enter, 1)
                MOVE    PRF_KTAB, R0            ; R0: the key
                XOR     R1, R1                  ; R1: its number
_P_AP_K         MOVE    @R0, R8
                RSUB    _P_KGET, 1
                MOVE    SR, R7                  ; (C: the key is there)
                MOVE    PRF_DEFS, R2            ; R2: the default value
                ADD     R1, R2
                MOVE    @R2, R2
                AND     0x0004, R7
                RBRA    _P_AP_DEF, Z            ; missing: the default
                MOVE    R0, R3
                ADD     2, R3
                CMP     0, @R3                  ; a toggle?
                RBRA    _P_AP_RADIO, !Z
                MOVE    PRF_VAL, R8
                MOVE    _PS_ON, R9
                RSUB    _P_ICMP, 1
                CMP     0, R10
                RBRA    _P_AP_T1, !Z
                MOVE    1, R2
                RBRA    _P_AP_DEF, 1
_P_AP_T1        MOVE    _PS_OFF, R9
                RSUB    _P_ICMP, 1
                CMP     0, R10
                RBRA    _P_AP_DEF, !Z
                XOR     R2, R2
                RBRA    _P_AP_DEF, 1
_P_AP_RADIO     MOVE    @R3, R4                 ; R4: number of values
                MOVE    R0, R5
                ADD     3, R5                   ; R5: the value strings
                XOR     R6, R6                  ; R6: index
_P_AP_V         MOVE    PRF_VAL, R8
                MOVE    @R5++, R9
                RSUB    _P_ICMP, 1
                CMP     0, R10
                RBRA    _P_AP_VF, Z
                ADD     1, R6
                CMP     R6, R4
                RBRA    _P_AP_V, !Z
                RBRA    _P_AP_DEF, 1            ; unknown: the default
_P_AP_VF        MOVE    R6, R2
_P_AP_DEF       MOVE    R0, R3                  ; R2: the value -> the items
                ADD     1, R3
                MOVE    @R3++, R8               ; offset
                RSUB    _P_ADDR, 1
                CMP     0, @R3                  ; a toggle: item := value
                RBRA    _P_AP_SR, !Z
                MOVE    R2, R9
                RSUB    _P_SET, 1
                RBRA    _P_AP_NX, 1
_P_AP_SR        MOVE    @R3, R4                 ; a radio: item R2 := 1, the
                XOR     R6, R6                  ; others 0
_P_AP_SL        XOR     R9, R9
                CMP     R6, R2
                RBRA    _P_AP_SS, !Z
                MOVE    1, R9
_P_AP_SS        RSUB    _P_SET, 1
                ADD     1, R8
                ADD     1, R6
                CMP     R6, R4
                RBRA    _P_AP_SL, !Z
_P_AP_NX        ADD     PRF_KW, R0
                ADD     1, R1
                CMP     PRF_KN, R1
                RBRA    _P_AP_K, !Z
                SYSCALL(leave, 1)
                RET

; _P_SERIAL: the menu block -> the keys of the profile text (the other lines
; - Kickstart, hard disks, unknown keys - stay). Registers preserved.
_P_SERIAL       SYSCALL(enter, 1)
                MOVE    PRF_KTAB, R0
                XOR     R1, R1
_P_SE_K         MOVE    R0, R3
                ADD     1, R3
                MOVE    @R3++, R8
                RSUB    _P_ADDR, 1              ; R8: the first item
                CMP     0, @R3
                RBRA    _P_SE_R, !Z
                RSUB    M2M$GET_SETTING, 1      ; a toggle
                MOVE    _PS_OFF, R2
                CMP     0, R9
                RBRA    _P_SE_W, Z
                MOVE    _PS_ON, R2
                RBRA    _P_SE_W, 1
_P_SE_R         MOVE    @R3++, R4               ; a radio: the selected item
                XOR     R2, R2                  ; (none: the key stays as is)
_P_SE_RL        RSUB    M2M$GET_SETTING, 1
                CMP     1, R9
                RBRA    _P_SE_RF, Z
                ADD     1, R8
                ADD     1, R3
                SUB     1, R4
                RBRA    _P_SE_RL, !Z
                RBRA    _P_SE_NX, 1
_P_SE_RF        MOVE    @R3, R2
_P_SE_W         MOVE    @R0, R8
                MOVE    R2, R9
                RSUB    _P_KSET, 1
_P_SE_NX        ADD     PRF_KW, R0
                ADD     1, R1
                CMP     PRF_KN, R1
                RBRA    _P_SE_K, !Z
                SYSCALL(leave, 1)
                RET

; _P_DEFBITS: the menu block := default profile R8 (0..3). Registers preserved.
_P_DEFBITS      SYSCALL(enter, 1)
                MOVE    R8, R0                  ; the defaults as a text, then
                MOVE    PRF_KN, R9              ; applied like a file
                SYSCALL(mulu, 1)
                MOVE    R10, R0
                ADD     PRF_DEFS, R0            ; R0: its values
                MOVE    PRF_TXT, R8             ; a fresh text
                MOVE    0, @R8
                MOVE    PRF_LEN, R8
                MOVE    0, @R8
                MOVE    PRF_KTAB, R1
                MOVE    PRF_KN, R2
_P_DB_K         MOVE    @R0++, R3               ; the value
                MOVE    R1, R4
                ADD     2, R4
                CMP     0, @R4
                RBRA    _P_DB_R, !Z
                MOVE    _PS_OFF, R9
                CMP     0, R3
                RBRA    _P_DB_W, Z
                MOVE    _PS_ON, R9
                RBRA    _P_DB_W, 1
_P_DB_R         ADD     1, R4
                ADD     R3, R4
                MOVE    @R4, R9
_P_DB_W         MOVE    @R1, R8
                RSUB    _P_KSET, 1
                ADD     PRF_KW, R1
                SUB     1, R2
                RBRA    _P_DB_K, !Z
                RSUB    _P_APPLY, 1
                SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; Files
; ----------------------------------------------------------------------------

; _P_DEV: the card of the settings file -> R8 = its device handle, C=1 if it
; is mounted. R9 used.
_P_DEV          RSUB    SDC$HOMEDEV, 1          ; R8: device, R9: 0 = mounted
                CMP     0, R9
                RBRA    _P_DEV_N, !Z
                OR      0x0004, SR
                RET
_P_DEV_N        AND     0xFFFB, SR
                RET

; _P_CDSAVE / _P_CDREST: the current directory of device R8. R8 preserved.
_P_CDSAVE       INCRB
                MOVE    R8, R0
                ADD     FAT32$DEV_AD_1STCLUS_LO, R0
                MOVE    PRF_SAVCD, R1
                MOVE    @R0++, @R1++
                MOVE    @R0, @R1
                DECRB
                RET
_P_CDREST       INCRB
                MOVE    R8, R0
                ADD     FAT32$DEV_AD_1STCLUS_LO, R0
                MOVE    PRF_SAVCD, R1
                MOVE    @R1++, @R0++
                MOVE    @R1, @R0
                DECRB
                RET

; _P_FNAME: R8 = a profile name -> PRF_FNAME = "<name>.prof" and PRF_PATH =
; "/amiga/profiles/<name>.prof". Registers preserved.
_P_FNAME        SYSCALL(enter, 1)
                MOVE    PRF_FNAME, R9
                SYSCALL(strcpy, 1)              ; "<name>"
                MOVE    PRF_FNAME, R8
                SYSCALL(strlen, 1)              ; R9: its length
                MOVE    PRF_FNAME, R1
                ADD     R9, R1
                MOVE    _PS_EXT, R8
                MOVE    R1, R9
                SYSCALL(strcpy, 1)              ; + ".prof"
                MOVE    _PS_DIR, R8
                MOVE    PRF_PATH, R9
                SYSCALL(strcpy, 1)              ; "/amiga/profiles"
                MOVE    PRF_PATH, R8
                SYSCALL(strlen, 1)
                MOVE    PRF_PATH, R1
                ADD     R9, R1
                MOVE    0x002F, @R1++           ; "/"
                MOVE    PRF_FNAME, R8
                MOVE    R1, R9
                SYSCALL(strcpy, 1)
                SYSCALL(leave, 1)
                RET

; _P_PB: CFGS_PB := zeros, PB_DEV = device R8, PB_DIR = its current directory,
; PB_DATE 1980-01-01. Registers preserved.
_P_PB           SYSCALL(enter, 1)
                MOVE    R8, R0
                MOVE    CFGS_PB, R8
                MOVE    FAT32$PB_SIZE, R9
                XOR     R10, R10
                SYSCALL(memset, 1)
                MOVE    CFGS_PB, R1
                MOVE    R0, @R1++               ; PB_DEV
                MOVE    R0, R2
                ADD     FAT32$DEV_AD_1STCLUS_LO, R2
                MOVE    @R2++, @R1++            ; PB_DIR
                MOVE    @R2, @R1
                MOVE    CFGS_PB, R1
                ADD     FAT32$PB_DATE, R1
                MOVE    0x0021, @R1
                SYSCALL(leave, 1)
                RET

; _P_OPEN: the profile R8 -> PRF_FDH, C=1 if it opens (PRF_FNAME, PRF_PATH set;
; R8 = the device then). R9..R12 used.
_P_OPEN         RSUB    _P_FNAME, 1
                RSUB    _P_DEV, 1
                RBRA    _P_OP_NO, !C
                MOVE    PRF_FDH, R9
                MOVE    PRF_PATH, R10
                XOR     R11, R11                ; "/" separator
                SYSCALL(f32_fopen, 1)
                CMP     0, R10
                RBRA    _P_OP_NO, !Z
                OR      0x0004, SR
                RET
_P_OP_NO        AND     0xFFFB, SR
                RET

; _P_READ: the file of profile R8 -> PRF_TXT (a CR goes, PRF_DIRTY = 0); C=1
; if it was there. Registers preserved.
_P_READ         SYSCALL(enter, 1)
                RSUB    _P_OPEN, 1
                RBRA    _P_RD_NO, !C
                MOVE    PRF_TXT, R0
                XOR     R1, R1
                MOVE    1, R2                   ; R2: 1 = in a key
                MOVE    PRF_FDH, R8
_P_RD_L         CMP     CFGS_MAXC, R1
                RBRA    _P_RD_E, Z
                SYSCALL(f32_fread, 1)           ; R9: byte, R10: error/EOF
                CMP     0, R10
                RBRA    _P_RD_E, !Z
                CMP     0x000D, R9              ; (CR LF from a PC: the CR goes)
                RBRA    _P_RD_L, Z
                CMP     0x000A, R9              ; a new line: a key again
                RBRA    _P_RD_1, !Z
                MOVE    1, R2
_P_RD_1         CMP     0x003D, R9              ; "=": the value
                RBRA    _P_RD_2, !Z
                XOR     R2, R2
_P_RD_2         CMP     0, R2                   ; keys in lower case (the keys
                RBRA    _P_RD_3, Z              ; are case-insensitive, the
                CMP     0x0041, R9              ; key/value code is not)
                RBRA    _P_RD_3, N              ; ("A" > R9)
                CMP     R9, 0x005A
                RBRA    _P_RD_3, N              ; (R9 > "Z")
                ADD     0x0020, R9
_P_RD_3         MOVE    R9, @R0++
                ADD     1, R1
                RBRA    _P_RD_L, 1
_P_RD_E         MOVE    0, @R0
                MOVE    PRF_LEN, R0
                MOVE    R1, @R0
                MOVE    PRF_DIRTY, R0
                MOVE    0, @R0
                SYSCALL(leave, 1)
                OR      0x0004, SR
                RET
_P_RD_NO        SYSCALL(leave, 1)
                AND     0xFFFB, SR
                RET

; _P_WRITE: PRF_TXT -> the file of profile R8 (created in /amiga/profiles if it
; is not there), PRF_DIRTY = 0; C=1 if it worked. Registers preserved.
_P_WRITE        SYSCALL(enter, 1)
                RSUB    _P_OPEN, 1
                RBRA    _P_WR_OPEN, C
                RSUB    _P_DEV, 1               ; not there: create it
                RBRA    _P_WR_NO, !C
                MOVE    R8, R3                  ; R3: device
                RSUB    _P_CDSAVE, 1
                MOVE    _PS_DIR, R9
                XOR     R10, R10
                SYSCALL(f32_cd, 1)
                CMP     0, R9
                RBRA    _P_WR_CDF, !Z
                MOVE    R3, R8
                RSUB    _P_PB, 1
                MOVE    CFGS_PB, R4
                ADD     FAT32$PB_NAME, R4
                MOVE    PRF_FNAME, @R4
                MOVE    CFGS_PB, R4
                ADD     FAT32$PB_ATTR, R4
                MOVE    FAT32$FA_ARCHIVE, @R4
                MOVE    CFGS_PB, R8
                RSUB    FAT32$W_CREATE, 1
                CMP     0, R9
                RBRA    _P_WR_CDF, !Z
                MOVE    CFGS_PB, R8
                MOVE    PRF_FDH, R9
                RSUB    FAT32$W_FDH, 1
                MOVE    R9, R4                  ; R4: error
                MOVE    R3, R8
                RSUB    _P_CDREST, 1
                CMP     0, R4
                RBRA    _P_WR_NO, !Z
                RBRA    _P_WR_OPEN, 1
_P_WR_CDF       MOVE    R3, R8
                RSUB    _P_CDREST, 1
                RBRA    _P_WR_NO, 1

                ; size := PRF_LEN (the sector buffer of the card written back
                ; and released first), the text, flushed
_P_WR_OPEN      MOVE    PRF_FDH, R8
                RSUB    _F32_RELEASE_BUF, 1
                CMP     0, R9
                RBRA    _P_WR_NO, !Z
                MOVE    @R8, R8                 ; (FDH_DEVICE = 0)
                RSUB    _P_PB, 1                ; (PB_DATE: the entry is new
                MOVE    CFGS_PB, R1             ; or keeps its date: 0)
                ADD     FAT32$PB_DATE, R1
                MOVE    0, @R1
                MOVE    PRF_FDH, R8
                MOVE    CFGS_PB, R9
                MOVE    PRF_LEN, R10
                MOVE    @R10, R10
                XOR     R11, R11
                RSUB    FAT32$W_SETSIZE, 1      ; (position 0 afterwards)
                CMP     0, R9
                RBRA    _P_WR_NO, !Z
                MOVE    PRF_TXT, R0
                MOVE    PRF_LEN, R1
                MOVE    @R1, R1
_P_WR_L         CMP     0, R1
                RBRA    _P_WR_F, Z
                MOVE    PRF_FDH, R8
                MOVE    @R0++, R9
                SYSCALL(f32_fwrite, 1)
                CMP     0, R9
                RBRA    _P_WR_NO, !Z
                SUB     1, R1
                RBRA    _P_WR_L, 1
_P_WR_F         MOVE    PRF_FDH, R8
                SYSCALL(f32_fflush, 1)
                CMP     0, R9
                RBRA    _P_WR_NO, !Z
                MOVE    PRF_DIRTY, R0
                MOVE    0, @R0
                SYSCALL(leave, 1)
                OR      0x0004, SR
                RET
_P_WR_NO        SYSCALL(leave, 1)
                AND     0xFFFB, SR
                RET

; _P_LIST: the profiles of /amiga/profiles -> PRF_LIST (names without ".prof",
; sorted, at most PRF_LMAX), PRF_LN = their number. Registers preserved.
_P_LIST         SYSCALL(enter, 1)
                MOVE    PRF_LN, R0
                MOVE    0, @R0
                RSUB    _P_DEV, 1
                RBRA    _P_LI_RET, !C
                MOVE    R8, R6                  ; R6: device
                RSUB    _P_CDSAVE, 1
                MOVE    _PS_DIR, R9
                XOR     R10, R10
                SYSCALL(f32_cd, 1)
                CMP     0, R9
                RBRA    _P_LI_CD, !Z
                MOVE    R6, R8
                MOVE    _DIRBR_FH, R9           ; (the browser's handle and
                SYSCALL(f32_od, 1)              ; entry: it is not running)
                CMP     0, R9
                RBRA    _P_LI_CD, !Z
                MOVE    R8, R7                  ; R7: directory handle
_P_LI_L         MOVE    R7, R8
                MOVE    _DIRBR_ENTRY, R9
                MOVE    FAT32$FA_DEFAULT, R10
                SYSCALL(f32_ld, 1)
                CMP     0, R11
                RBRA    _P_LI_CD, !Z
                CMP     1, R10
                RBRA    _P_LI_CD, !Z            ; the end
                MOVE    _DIRBR_ENTRY, R0
                ADD     FAT32$DE_ATTRIB, R0
                MOVE    @R0, R0
                AND     FAT32$FA_DIR, R0
                RBRA    _P_LI_L, !Z
                MOVE    _DIRBR_ENTRY, R8        ; "<name>.prof"?
                ADD     FAT32$DE_NAME, R8
                SYSCALL(strlen, 1)
                CMP     6, R9                   ; at least "x.prof"
                RBRA    _P_LI_L, N
                MOVE    R9, R1                  ; R1: length
                SUB     5, R1                   ; R1: the file name's length
                CMP     R1, PRF_FMAX            ; too long
                RBRA    _P_LI_L, N
                MOVE    R8, R2
                ADD     R1, R2
                MOVE    R2, R8
                MOVE    _PS_EXT, R9
                RSUB    _P_ICMP, 1
                CMP     0, R10
                RBRA    _P_LI_L, !Z
                MOVE    PRF_LN, R2              ; room left?
                CMP     PRF_LMAX, @R2
                RBRA    _P_LI_CD, Z
                MOVE    @R2, R8                 ; the slot
                RSUB    _P_LNAME, 1
                MOVE    R8, R5                  ; R5: the slot
                MOVE    _DIRBR_ENTRY, R3        ; copy the file name
                ADD     FAT32$DE_NAME, R3
                MOVE    R1, R4
_P_LI_C         MOVE    @R3++, @R8++
                SUB     1, R4
                RBRA    _P_LI_C, !Z
                MOVE    0, @R8
                MOVE    R5, R8                  ; its name fits the menu?
                RSUB    _P_PFX, 1
                MOVE    R10, R8
                SYSCALL(strlen, 1)
                CMP     R9, PRF_NMAX
                RBRA    _P_LI_L, N              ; (no: the slot is used again)
                ADD     1, @R2
                RBRA    _P_LI_L, 1
_P_LI_CD        MOVE    R6, R8
                RSUB    _P_CDREST, 1
                RSUB    _P_SORT, 1
_P_LI_RET       SYSCALL(leave, 1)
                RET

; _P_SORT: PRF_LIST in the order of _P_LCMP (insertion sort, PRF_LMAX names
; at most). Registers preserved.
_P_SORT         SYSCALL(enter, 1)
                MOVE    1, R0                   ; R0: i
_P_SO_I         MOVE    PRF_LN, R1
                CMP     @R1, R0
                RBRA    _P_SO_RET, !N           ; i >= n (unsigned: n > i)
                RBRA    _P_SO_RET, Z
                MOVE    R0, R1                  ; R1: j
_P_SO_J         CMP     0, R1
                RBRA    _P_SO_NX, Z
                MOVE    R1, R2                  ; R2: j - 1
                SUB     1, R2
                MOVE    R2, R8
                RSUB    _P_LNAME, 1
                MOVE    R8, R9
                ADD     PRF_FLEN, R9
                RSUB    _P_LCMP, 1
                CMP     R10, 0                  ; j - 1 behind j? (CMP a, b:
                RBRA    _P_SO_NX, !V            ; V = a > b, signed)
                MOVE    R2, R8                  ; swap them
                RSUB    _P_LSWAP, 1
                SUB     1, R1
                RBRA    _P_SO_J, 1
_P_SO_NX        ADD     1, R0
                RBRA    _P_SO_I, 1
_P_SO_RET       SYSCALL(leave, 1)
                RET

; _P_ENSURE: /amiga/profiles with at least one profile: a missing directory is
; created, and a missing or empty one gets the default profiles. A directory
; with profiles stays as it is: the user changed the defaults on purpose.
; Registers preserved.
_P_ENSURE       SYSCALL(enter, 1)
                RSUB    _P_DEV, 1
                CMP     0, R9
                RBRA    _P_EN_RET, !Z
                MOVE    R8, R0                  ; R0: device
                RSUB    _P_CDSAVE, 1
                MOVE    _PS_DIR, R9
                XOR     R10, R10
                SYSCALL(f32_cd, 1)
                CMP     0, R9
                RBRA    _P_EN_HAS, Z
                MOVE    R0, R8                  ; no directory: create it
                MOVE    _PS_AMIGA, R9           ; in /amiga
                XOR     R10, R10
                SYSCALL(f32_cd, 1)
                CMP     0, R9
                RBRA    _P_EN_CDR, !Z
                MOVE    _PS_DIRNAME, R8         ; the name in RAM: the write
                MOVE    PRF_FNAME, R9           ; layer runs in another code
                SYSCALL(strcpy, 1)              ; bank (this one is not mapped
                MOVE    R0, R8                  ; there)
                RSUB    _P_PB, 1
                MOVE    CFGS_PB, R1
                ADD     FAT32$PB_NAME, R1
                MOVE    PRF_FNAME, @R1
                MOVE    CFGS_PB, R8
                RSUB    FAT32$W_MKDIR, 1
                MOVE    R9, R1
                MOVE    R0, R8
                RSUB    _P_CDREST, 1
                CMP     0, R1
                RBRA    _P_EN_RET, !Z
                RBRA    _P_EN_DEF, 1
_P_EN_HAS       MOVE    R0, R8
                RSUB    _P_CDREST, 1
                RSUB    _P_LIST, 1              ; any profile there?
                MOVE    PRF_LN, R1
                CMP     0, @R1
                RBRA    _P_EN_RET, !Z
_P_EN_DEF       XOR     R1, R1                  ; the defaults
_P_EN_D         MOVE    R1, R8
                RSUB    _P_DEFBITS, 1
                MOVE    PRF_DNAMES, R2
                ADD     R1, R2
                MOVE    @R2, R8
                RSUB    _P_WRITE, 1
                ADD     1, R1
                CMP     PRF_DEFN, R1
                RBRA    _P_EN_D, !Z
                RBRA    _P_EN_RET, 1
_P_EN_CDR       MOVE    R0, R8
                RSUB    _P_CDREST, 1
_P_EN_RET       SYSCALL(leave, 1)
                RET

; _P_ACTIVATE: the profile of file name R8 is the active one now: PRF_FILE,
; PRF_NAME, "profile=<name>" in the settings file, the menu line repainted.
; Registers preserved.
_P_ACTIVATE     SYSCALL(enter, 1)
                MOVE    PRF_FILE, R9
                CMP     R8, R9
                RBRA    _P_AC_1, Z
                SYSCALL(strcpy, 1)
_P_AC_1         MOVE    PRF_FILE, R8
                RSUB    _P_PFX, 1
                MOVE    R10, R8
                MOVE    PRF_NAME, R9
                SYSCALL(strcpy, 1)
                MOVE    _PS_KEY, R8
                MOVE    PRF_NAME, R9
                RSUB    CFGS_SET, 1
                MOVE    PRF_PAINT, R0
                MOVE    0, @R0
                SYSCALL(leave, 1)
                RET

; _P_FLUSH: the active profile written back if it changed. Registers preserved.
_P_FLUSH        SYSCALL(enter, 1)
                MOVE    PRF_DIRTY, R0
                CMP     0, @R0
                RBRA    _P_FL_RET, Z
                RSUB    _P_SERIAL, 1
                MOVE    PRF_FILE, R8
                RSUB    _P_WRITE, 1
                MOVE    PRF_DIRTY, R0           ; (failed: not again and again)
                MOVE    0, @R0
_P_FL_RET       SYSCALL(leave, 1)
                RET

; _P_INLIST: C=1 if a profile of PRF_LIST has the name R8 (upper and lower
; case alike; the name without its number); R9 = its file name then. R8
; preserved, R10 used.
_P_INLIST       INCRB
                MOVE    R8, R2                  ; R2: the name
                MOVE    PRF_LN, R0
                MOVE    @R0, R0
                MOVE    PRF_LIST, R1
_P_IL_L         CMP     0, R0
                RBRA    _P_IL_NO, Z
                MOVE    R1, R8
                RSUB    _P_PFX, 1               ; R10: its name
                MOVE    R2, R8
                MOVE    R10, R9
                RSUB    _P_ICMP, 1
                CMP     0, R10
                RBRA    _P_IL_YES, Z
                ADD     PRF_FLEN, R1
                SUB     1, R0
                RBRA    _P_IL_L, 1
_P_IL_YES       MOVE    R1, R9
                DECRB
                OR      0x0004, SR
                RET
_P_IL_NO        MOVE    R2, R8
                DECRB
                AND     0xFFFB, SR
                RET

; _P_LSWAP: the entries R8 and R8 + 1 of PRF_LIST change places. Registers
; preserved.
_P_LSWAP        SYSCALL(enter, 1)
                RSUB    _P_LNAME, 1
                MOVE    R8, R0
                MOVE    R8, R1
                ADD     PRF_FLEN, R1
                MOVE    PRF_FLEN, R2
_P_LS_L         MOVE    @R0, R3
                MOVE    @R1, @R0++
                MOVE    R3, @R1++
                SUB     1, R2
                RBRA    _P_LS_L, !Z
                SYSCALL(leave, 1)
                RET

; _P_RENFILE: the file of profile R8 renamed to R9 (file names; R9 in RAM, not
; PRF_FNAME/PRF_PATH); C=1 if it worked (FAT32$W_RENAME refuses a name that
; exists). Registers preserved.
_P_RENFILE      SYSCALL(enter, 1)
                MOVE    R9, R5                  ; R5: the new name
                RSUB    _P_OPEN, 1              ; (R8: its device)
                RBRA    _P_RF_NO, !C
                MOVE    R8, R0                  ; R0: device
                RSUB    _P_CDSAVE, 1
                MOVE    _PS_DIR, R9
                XOR     R10, R10
                SYSCALL(f32_cd, 1)
                CMP     0, R9
                RBRA    _P_RF_CD, !Z
                MOVE    R0, R8
                RSUB    _P_PB, 1                ; PB_DEV, PB_DIR
                MOVE    CFGS_PB, R1
                ADD     FAT32$PB_EA, R1         ; PB_EA: the old entry
                MOVE    PRF_FDH, R2
                ADD     FAT32$FDH_EA_CL_LO, R2
                MOVE    @R2++, @R1++
                MOVE    @R2++, @R1++
                MOVE    @R2, @R1
                MOVE    CFGS_PB, R1             ; PB_DIR2 = PB_DIR
                MOVE    R1, R2
                ADD     FAT32$PB_DIR_LO, R1
                ADD     FAT32$PB_DIR2_LO, R2
                MOVE    @R1++, @R2++
                MOVE    @R1, @R2
                MOVE    R5, R8                  ; PB_NAME: "<new>.prof"
                RSUB    _P_FNAME, 1
                MOVE    CFGS_PB, R1
                ADD     FAT32$PB_NAME, R1
                MOVE    PRF_FNAME, @R1
                MOVE    CFGS_PB, R8
                RSUB    FAT32$W_RENAME, 1
                MOVE    R9, R1                  ; R1: error
                MOVE    R0, R8
                RSUB    _P_CDREST, 1
                CMP     0, R1
                RBRA    _P_RF_NO, !Z
                SYSCALL(leave, 1)
                OR      0x0004, SR
                RET
_P_RF_CD        MOVE    R0, R8
                RSUB    _P_CDREST, 1
_P_RF_NO        SYSCALL(leave, 1)
                AND     0xFFFB, SR
                RET

; _P_RENUM: the files of PRF_LIST renamed "01_<name>", "02_<name>", ... in the
; order of the list (a file with its number already stays); the list and
; PRF_FILE follow. Registers preserved.
_P_RENUM        SYSCALL(enter, 1)
                XOR     R0, R0                  ; R0: entry
_P_RU_L         MOVE    PRF_LN, R1
                CMP     @R1, R0
                RBRA    _P_RU_RET, Z
                MOVE    R0, R8
                RSUB    _P_LNAME, 1
                MOVE    R8, R1                  ; R1: its file name
                RSUB    _P_PFX, 1               ; R10: its name
                MOVE    R0, R8
                ADD     1, R8
                MOVE    R10, R9
                RSUB    _P_MKFULL, 1            ; PRF_FULL: the new file name
                MOVE    R1, R8
                MOVE    PRF_FULL, R9
                SYSCALL(strcmp, 1)
                CMP     0, R10
                RBRA    _P_RU_NX, Z
                MOVE    R1, R8
                MOVE    PRF_FULL, R9
                RSUB    _P_RENFILE, 1
                RBRA    _P_RU_NX, !C
                MOVE    R1, R8                  ; the active one?
                MOVE    PRF_FILE, R9
                RSUB    _P_ICMP, 1
                MOVE    R10, R2
                MOVE    PRF_FULL, R8            ; the list follows
                MOVE    R1, R9
                SYSCALL(strcpy, 1)
                CMP     0, R2
                RBRA    _P_RU_NX, !Z
                MOVE    PRF_FILE, R9            ; and PRF_FILE
                SYSCALL(strcpy, 1)
_P_RU_NX        ADD     1, R0
                RBRA    _P_RU_L, 1
_P_RU_RET       SYSCALL(leave, 1)
                RET

; _P_USERN: PRF_EDBUF := "User N", the first N (1..99) that is no profile yet.
; Registers preserved.
_P_USERN        SYSCALL(enter, 1)
                MOVE    1, R0                   ; R0: N
_P_UN_L         MOVE    _PS_USER, R8
                MOVE    PRF_EDBUF, R9
                SYSCALL(strcpy, 1)
                MOVE    PRF_EDBUF, R1
                ADD     5, R1                   ; behind "User "
                MOVE    R0, R8
                MOVE    10, R9
                SYSCALL(divu, 1)                ; R10: N / 10, R11: N % 10
                CMP     0, R10
                RBRA    _P_UN_1, Z
                ADD     0x0030, R10
                MOVE    R10, @R1++
_P_UN_1         ADD     0x0030, R11
                MOVE    R11, @R1++
                MOVE    0, @R1
                MOVE    PRF_EDBUF, R8
                RSUB    _P_INLIST, 1
                RBRA    _P_UN_RET, !C
                ADD     1, R0
                CMP     100, R0
                RBRA    _P_UN_L, !Z
_P_UN_RET       SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; Drawing inside the frame of the menu (the selector and the name editor)
; ----------------------------------------------------------------------------

; _P_XY: row R8 of the inner area -> R9 = x, R10 = y on the screen
_P_XY           MOVE    OPTM_X, R9
                MOVE    @R9, R9
                ADD     1, R9
                MOVE    OPTM_Y, R10
                MOVE    @R10, R10
                ADD     1, R10
                ADD     R8, R10
                RET

; _P_PUT: string R8 at row R11 (column 0 of the inner area). Registers
; preserved.
_P_PUT          INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    R10, R2
                MOVE    R11, R8
                RSUB    _P_XY, 1
                MOVE    R0, R8
                RSUB    SCR$PRINTSTRXY, 1
                MOVE    R1, R9
                MOVE    R2, R10
                DECRB
                RET

; _P_ATTR: attribute R9 for the inner width of row R8. Registers preserved.
_P_ATTR         SYSCALL(enter, 1)
                MOVE    R9, R3                  ; R3: attribute
                RSUB    _P_XY, 1
                MOVE    R9, R0                  ; R0: x
                MOVE    SCR$SYS_DX, R8
                MOVE    @R8, R8
                MOVE    R10, R9
                SYSCALL(mulu, 1)
                ADD     R0, R10
                ADD     M2M$RAMROM_DATA, R10
                MOVE    M2M$RAMROM_DEV, R4
                MOVE    M2M$VRAM_ATTR, @R4
                MOVE    M2M$RAMROM_4KWIN, R4
                MOVE    0, @R4
                MOVE    OPTM_DX, R2
                MOVE    @R2, R2
                SUB     2, R2
_P_AT_L         MOVE    R3, @R10++
                SUB     1, R2
                RBRA    _P_AT_L, !Z
                SYSCALL(leave, 1)
                RET

; _P_CLR: the frame of the menu drawn again (without the junctions of the
; menu's separator lines), the inner area: spaces, standard colours. Registers
; preserved.
_P_CLR          SYSCALL(enter, 1)
                MOVE    OPTM_X, R8              ; the plain frame
                MOVE    @R8, R8
                MOVE    OPTM_Y, R9
                MOVE    @R9, R9
                MOVE    OPTM_DX, R10
                MOVE    @R10, R10
                MOVE    OPTM_DY, R11
                MOVE    @R11, R11
                RSUB    SCR$PRINTFRAME, 1
                MOVE    PRF_LINE, R0            ; a line of spaces
                MOVE    OPTM_DX, R1
                MOVE    @R1, R1
                SUB     2, R1
_P_CL_S         MOVE    0x0020, @R0++
                SUB     1, R1
                RBRA    _P_CL_S, !Z
                MOVE    0, @R0
                XOR     R11, R11                ; R11: row
                MOVE    OPTM_DY, R1
                MOVE    @R1, R1
                SUB     2, R1                   ; R1: rows
_P_CL_R         MOVE    PRF_LINE, R8
                RSUB    _P_PUT, 1
                MOVE    R11, R8
                MOVE    M2M$SA_COL_STD, R9
                RSUB    _P_ATTR, 1
                ADD     1, R11
                CMP     R11, R1
                RBRA    _P_CL_R, !Z
                SYSCALL(leave, 1)
                RET

; _P_RULE: a separator line at row R8 of the inner area. Registers preserved.
_P_RULE         INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    R10, R2
                RSUB    _P_XY, 1
                MOVE    R10, R8
                RSUB    OPT_LINE_AT, 1
                MOVE    R0, R8
                MOVE    R1, R9
                MOVE    R2, R10
                DECRB
                RET

; _P_RELEASE: wait until Return, Space and Run/Stop are up again, then let the
; key scanner of the menu see that (no key counts as new afterwards).
_P_RELEASE      INCRB
_P_RE_L         RSUB    HANDLE_IO, 1
                MOVE    M2M$KEYBOARD, R0        ; (low active)
                MOVE    @R0, R0
                AND     PRF_KMASK, R0
                CMP     PRF_KMASK, R0
                RBRA    _P_RE_L, !Z
                RSUB    KEYB$SCAN, 1
                MOVE    R8, @--SP
_P_RE_K         RSUB    KEYB$GETKEY, 1          ; (drop what came meanwhile)
                CMP     0, R8
                RBRA    _P_RE_K, !Z
                MOVE    @SP++, R8
                DECRB
                RET

; ----------------------------------------------------------------------------
; The name editor
;
; Input:  R8: the text to start with, R9: a message (0: none)
; Output: C=1: PRF_EDBUF = the name (trimmed, may be empty), C=0: cancelled
; ----------------------------------------------------------------------------

_P_EDIT         SYSCALL(enter, 1)
                MOVE    R9, R6                  ; R6: message
                MOVE    PRF_EDBUF, R9           ; (R8 may be PRF_EDBUF)
                CMP     R8, R9
                RBRA    _P_ED_0, Z
                SYSCALL(strcpy, 1)
_P_ED_0         MOVE    PRF_EDBUF, R8
                SYSCALL(strlen, 1)
                MOVE    R9, R0                  ; R0: length
                CMP     R0, PRF_NMAX
                RBRA    _P_ED_1, !N
                MOVE    PRF_NMAX, R0
                MOVE    PRF_EDBUF, R1
                ADD     R0, R1
                MOVE    0, @R1
_P_ED_1         MOVE    R0, R1                  ; R1: cursor
                RSUB    _P_CLR, 1
                MOVE    _PS_ETITLE, R8
                XOR     R11, R11
                RSUB    _P_PUT, 1
                XOR     R8, R8
                MOVE    M2M$SA_COL_TTLE, R9
                RSUB    _P_ATTR, 1
                MOVE    1, R8
                RSUB    _P_RULE, 1
                CMP     0, R6
                RBRA    _P_ED_2, Z
                MOVE    R6, R8
                MOVE    5, R11
                RSUB    _P_PUT, 1
_P_ED_2         MOVE    _PS_EHELP1, R8
                MOVE    7, R11
                RSUB    _P_PUT, 1
                MOVE    _PS_EHELP2, R8
                MOVE    8, R11
                RSUB    _P_PUT, 1
                RSUB    _P_KEYEV, 1             ; R8: the event now (its
                MOVE    R8, R2                  ; sequence is old news)
                AND     0xF000, R2              ; R2: last sequence

_P_ED_DRAW      MOVE    PRF_LINE, R3            ; " " + the text + spaces
                MOVE    0x0020, @R3++
                MOVE    PRF_EDBUF, R4
                MOVE    PRF_NLEN, R5            ; (PRF_NMAX + 1)
_P_ED_DL        CMP     0, @R4
                RBRA    _P_ED_DS, Z
                MOVE    @R4++, @R3++
                SUB     1, R5
                RBRA    _P_ED_DL, 1
_P_ED_DS        MOVE    0x0020, @R3++
                SUB     1, R5
                RBRA    _P_ED_DS, !Z
                MOVE    0, @R3
                MOVE    PRF_LINE, R8
                MOVE    3, R11
                RSUB    _P_PUT, 1
                MOVE    3, R8                   ; the cursor: one character
                MOVE    M2M$SA_COL_STD, R9      ; inverse
                RSUB    _P_ATTR, 1
                MOVE    3, R8
                RSUB    _P_XY, 1
                MOVE    SCR$SYS_DX, R8
                MOVE    @R8, R8
                MOVE    R10, R11                ; (R9: x)
                MOVE    R9, R12
                MOVE    R11, R9
                SYSCALL(mulu, 1)
                ADD     R12, R10
                ADD     1, R10                  ; behind the leading blank
                ADD     R1, R10
                ADD     M2M$RAMROM_DATA, R10
                MOVE    M2M$RAMROM_DEV, R3
                MOVE    M2M$VRAM_ATTR, @R3
                MOVE    M2M$RAMROM_4KWIN, R3
                MOVE    0, @R3
                MOVE    M2M$SA_COL_STD_INV, @R10

_P_ED_KEY       RSUB    HANDLE_IO, 1
                RSUB    _P_KEYEV, 1
                MOVE    R8, R3
                AND     0xF000, R3
                CMP     R3, R2                  ; a new key?
                RBRA    _P_ED_KEY, Z
                MOVE    R3, R2
                MOVE    R8, R4                  ; R4: key number
                AND     0x007F, R4
                MOVE    R8, R5                  ; R5: Shift
                AND     0x0100, R5
                CMP     PRF_K_RET, R4
                RBRA    _P_ED_OK, Z
                CMP     PRF_K_STOP, R4
                RBRA    _P_ED_CAN, Z
                CMP     PRF_K_ESC, R4
                RBRA    _P_ED_CAN, Z
                CMP     PRF_K_LEFT, R4
                RBRA    _P_ED_LEFT, Z
                CMP     PRF_K_RIGHT, R4
                RBRA    _P_ED_RIGHT, Z
                CMP     PRF_K_DEL, R4
                RBRA    _P_ED_DEL, Z
                CMP     PRF_K_HOME, R4
                RBRA    _P_ED_HOME, Z
                CMP     R4, 79                  ; a character?
                RBRA    _P_ED_KEY, N
                MOVE    R4, R3
                ADD     R4, R3
                CMP     0, R5
                RBRA    _P_ED_C1, Z
                ADD     1, R3
_P_ED_C1        ADD     PRF_KEYMAP, R3
                MOVE    @R3, R3                 ; R3: the character
                CMP     0, R3
                RBRA    _P_ED_KEY, Z
                CMP     PRF_NMAX, R0            ; full
                RBRA    _P_ED_KEY, Z
                MOVE    PRF_EDBUF, R4           ; insert at the cursor
                ADD     R0, R4                  ; (from the zero on: right)
                MOVE    R0, R5
                SUB     R1, R5
                ADD     1, R5                   ; characters to move
_P_ED_INS       MOVE    @R4, R7
                ADD     1, R4
                MOVE    R7, @R4
                SUB     2, R4
                SUB     1, R5
                RBRA    _P_ED_INS, !Z
                MOVE    PRF_EDBUF, R4
                ADD     R1, R4
                MOVE    R3, @R4
                ADD     1, R0
                ADD     1, R1
                RBRA    _P_ED_DRAW, 1
_P_ED_LEFT      CMP     0, R1
                RBRA    _P_ED_KEY, Z
                SUB     1, R1
                RBRA    _P_ED_DRAW, 1
_P_ED_RIGHT     CMP     R1, R0
                RBRA    _P_ED_KEY, Z
                ADD     1, R1
                RBRA    _P_ED_DRAW, 1
_P_ED_HOME      XOR     R1, R1
                CMP     0, R5                   ; Shift: clear
                RBRA    _P_ED_DRAW, Z
                XOR     R0, R0
                MOVE    PRF_EDBUF, R4
                MOVE    0, @R4
                RBRA    _P_ED_DRAW, 1
_P_ED_DEL       CMP     0, R1                   ; the character in front of
                RBRA    _P_ED_KEY, Z            ; the cursor goes
                MOVE    PRF_EDBUF, R4
                ADD     R1, R4
_P_ED_DLL       MOVE    @R4, R7
                SUB     1, R4
                MOVE    R7, @R4
                ADD     2, R4
                CMP     0, R7
                RBRA    _P_ED_DLL, !Z
                SUB     1, R0
                SUB     1, R1
                RBRA    _P_ED_DRAW, 1

_P_ED_OK        MOVE    PRF_EDBUF, R4           ; trim: leading blanks,
_P_ED_TL        CMP     0x0020, @R4             ; trailing blanks and dots
                RBRA    _P_ED_TL2, !Z
                ADD     1, R4
                RBRA    _P_ED_TL, 1
_P_ED_TL2       MOVE    R4, R8
                MOVE    PRF_EDBUF, R9
                SYSCALL(strcpy, 1)              ; (to the left: safe)
                MOVE    PRF_EDBUF, R8
                SYSCALL(strlen, 1)
_P_ED_TT        CMP     0, R9
                RBRA    _P_ED_TE, Z
                MOVE    PRF_EDBUF, R4
                ADD     R9, R4
                SUB     1, R4
                CMP     0x0020, @R4
                RBRA    _P_ED_TC, Z
                CMP     0x002E, @R4
                RBRA    _P_ED_TE, !Z
_P_ED_TC        MOVE    0, @R4
                SUB     1, R9
                RBRA    _P_ED_TT, 1
_P_ED_TE        RSUB    _P_RELEASE, 1
                SYSCALL(leave, 1)
                OR      0x0004, SR
                RET
_P_ED_CAN       RSUB    _P_RELEASE, 1
                SYSCALL(leave, 1)
                AND     0xFFFB, SR
                RET

; _P_KEYEV: the last key-down event of the whole keyboard (C_DEV_AMIGA_KEYS)
; -> R8. The RAMROM selection is changed.
_P_KEYEV        MOVE    M2M$RAMROM_DEV, R8
                MOVE    AEXP_DEV_KEYS, @R8
                MOVE    M2M$RAMROM_4KWIN, R8
                MOVE    0, @R8
                MOVE    M2M$RAMROM_DATA, R8
                MOVE    @R8, R8
                RET

; ----------------------------------------------------------------------------
; Entry points (FAR_CALL stubs PRF_* in the fixed ROM)
; ----------------------------------------------------------------------------

; B4_PRF_KGET / B4_PRF_KSET: CFGS_GET / CFGS_SET on the text of the active
; profile for bank 2 (B2_PROF_*): the files a profile remembers are its lines
; "hdf0", "hdf1", "kick" and "ar3rom". R8 is the NUMBER of the key (0..3), not a string:
; a string of bank 2 cannot be read while this bank is mapped. R9/R10 as for
; CFGS_GET/SET (RAM). A change marks the profile dirty. Registers preserved.
B4_PRF_KGET     INCRB
                MOVE    R8, R1
                ADD     _P_FKEYS, R8
                MOVE    @R8, R8
                RSUB    _P_SWAP, 1
                RSUB    CFGS_GET, 1
                MOVE    SR, R0                  ; (C of CFGS_GET)
                RSUB    _P_SWAP, 1
                MOVE    R1, R8
                AND     0x0004, R0
                AND     0xFFFB, SR
                OR      R0, SR
                DECRB
                RET
B4_PRF_KSET     INCRB
                MOVE    R8, R1
                ADD     _P_FKEYS, R8
                MOVE    @R8, R8
                RSUB    _P_KSET, 1
                MOVE    R1, R8
                DECRB
                RET
_P_FKEYS        .DW     _PF_H0, _PF_H1, _PF_K, _PF_A3
_PF_H0          .ASCII_W "hdf0"
_PF_H1          .ASCII_W "hdf1"
_PF_K           .ASCII_W "kick"
_PF_A3          .ASCII_W "ar3rom"

; B4_PRF_BOOT (PREP_START, before PROFILE_APPLY): the default profiles if
; needed, then the active one - the one the settings file names, else the first
; of the directory, else the A500 defaults in memory - into the menu block.
; Registers preserved.
B4_PRF_BOOT     SYSCALL(enter, 1)
                MOVE    PRF_NAME, R0
                MOVE    0, @R0
                MOVE    PRF_FILE, R0
                MOVE    0, @R0
                MOVE    PRF_DIRTY, R0
                MOVE    0, @R0
                MOVE    PRF_PAINT, R0
                MOVE    0, @R0
                MOVE    PRF_LEN, R0
                MOVE    0, @R0
                MOVE    PRF_TXT, R0
                MOVE    0, @R0
                RSUB    _P_ENSURE, 1
                RSUB    _P_LIST, 1
                MOVE    _PS_KEY, R8             ; the one the settings file names
                MOVE    PRF_EDBUF, R9
                MOVE    PRF_NLEN, R10
                RSUB    CFGS_GET, 1
                RBRA    _P_BO_A500, !C
                MOVE    PRF_EDBUF, R8
                RSUB    _P_INLIST, 1            ; R9: its file name
                RBRA    _P_BO_GO, C
_P_BO_A500      MOVE    _PD_A500, R8            ; else A500 (the default of
                RSUB    _P_INLIST, 1            ; a new setup, as before),
                RBRA    _P_BO_GO, C             ; else the first one
                MOVE    PRF_LN, R0
                CMP     0, @R0
                RBRA    _P_BO_DEF, Z
                MOVE    PRF_LIST, R9
_P_BO_GO        MOVE    R9, R8
                MOVE    PRF_FULL, R9
                SYSCALL(strcpy, 1)
                MOVE    PRF_FULL, R8
                RSUB    _P_READ, 1
                RBRA    _P_BO_OK, C
_P_BO_DEF       XOR     R8, R8                  ; nothing on the card: the
                RSUB    _P_DEFBITS, 1           ; A500 in memory
                MOVE    _PD_A500, R8
                MOVE    PRF_FULL, R9
                SYSCALL(strcpy, 1)
                MOVE    PRF_DIRTY, R0
                MOVE    0, @R0
                RBRA    _P_BO_NAME, 1
_P_BO_OK        RSUB    _P_APPLY, 1
_P_BO_NAME      MOVE    PRF_FULL, R8
                RSUB    _P_ACTIVATE, 1
                SYSCALL(leave, 1)
                RET

; B4_PRF_CHANGED (OSM_SEL_POST, R8 = the group): a setting of the block
; changed: the profile is written back when the menu closes. Registers
; preserved.
B4_PRF_CHANGED  INCRB
                MOVE    PRF_GRPS, R0
_P_CH_L         CMP     0, @R0
                RBRA    _P_CH_RET, Z
                CMP     @R0++, R8
                RBRA    _P_CH_L, !Z
                MOVE    PRF_DIRTY, R0
                MOVE    1, @R0
_P_CH_RET       DECRB
                RET
PRF_GRPS        .DW     AEXP_OPTM_G_P1CPU, AEXP_OPTM_G_P1CS, AEXP_OPTM_G_P1HDC
                .DW     AEXP_OPTM_G_P1CHIP, AEXP_OPTM_G_P1SLOW, AEXP_OPTM_G_P1CART
                .DW     AEXP_OPTM_G_P1FAST, AEXP_OPTM_G_P1Z3, AEXP_OPTM_G_P1Z3B
                .DW     AEXP_OPTM_G_P1GFX, AEXP_OPTM_G_P1NET, 0

; _P_PAINT: the name of the active profile into the " Profile:" line of the
; menu (OPTM_LIVE_TEXT: the heap copy of the item and, if visible, the screen).
; The caller makes sure the menu exists. Registers preserved.
_P_PAINT        SYSCALL(enter, 1)
                MOVE    PRF_LINE, R0            ; " " + the name, cut or filled
                MOVE    0x0020, @R0++           ; with blanks to PRF_LBL_LEN
                MOVE    PRF_NAME, R1
                MOVE    PRF_LBL_LEN, R2
                SUB     1, R2
_P_PA_L         CMP     0, @R1
                RBRA    _P_PA_S, Z
                MOVE    @R1++, @R0++
                SUB     1, R2
                RBRA    _P_PA_L, !Z
                RBRA    _P_PA_E, 1
_P_PA_S         MOVE    0x0020, @R0++
                SUB     1, R2
                RBRA    _P_PA_S, !Z
_P_PA_E         MOVE    0, @R0
                MOVE    AEXP_OSM_PROFILE, R8
                MOVE    PRF_LBL_OFS, R9
                MOVE    PRF_LINE, R10
                MOVE    PRF_LBL_LEN, R11
                RSUB    OPTM_LIVE_TEXT, 1
                SYSCALL(leave, 1)
                RET

; B4_PRF_STEP (HANDLE_CORE_IO): while the main menu is on screen, the name in
; the " Profile:" line (HELP_MENU copies the items anew at every opening);
; while the menu is closed, a changed profile is written back. RAMROM
; selection and registers preserved.
B4_PRF_STEP     SYSCALL(enter, 1)
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    @R0, R1
                MOVE    M2M$RAMROM_4KWIN, R2
                MOVE    @R2, R3
                MOVE    M2M$CSR, R4
                MOVE    @R4, R4
                AND     M2M$CSR_OSM, R4
                RBRA    _P_ST_CLOSED, Z
                MOVE    PRF_PAINT, R4           ; open: painted already?
                CMP     0, @R4
                RBRA    _P_ST_RET, !Z
                MOVE    OSM_SUB_ACTIVE, R4      ; (browser or help showing)
                CMP     0, @R4
                RBRA    _P_ST_RET, !Z
                MOVE    OPTM_MENULEVEL, R4      ; (the line is in the main
                CMP     0, @R4                  ; menu)
                RBRA    _P_ST_RET, !Z
                MOVE    OPTM_DATA, R4
                CMP     0, @R4
                RBRA    _P_ST_RET, Z
                RSUB    _P_PAINT, 1
                MOVE    PRF_PAINT, R4
                MOVE    1, @R4
                RBRA    _P_ST_RET, 1
_P_ST_CLOSED    MOVE    PRF_PAINT, R4           ; the next opening repaints
                MOVE    0, @R4
                RSUB    _P_FLUSH, 1
_P_ST_RET       MOVE    R1, @R0
                MOVE    R3, @R2
                SYSCALL(leave, 1)
                RET

; B4_PRF_SELECT (the " Profile:" line, OSM_SEL_POST): the profile selector -
; the profiles, a separator bar and "Add New Profile". The caller redraws the
; menu. Registers preserved.
B4_PRF_SELECT   SYSCALL(enter, 1)
                RSUB    _P_FLUSH, 1             ; the active one up to date
                RSUB    _P_LIST, 1
                MOVE    PRF_LN, R0
                MOVE    @R0, R0                 ; R0: profiles
                XOR     R1, R1                  ; R1: cursor (R0 = Add New)
_P_SL_F         CMP     R1, R0                  ; on the active profile
                RBRA    _P_SL_D, Z
                MOVE    R1, R8
                RSUB    _P_LNAME, 1
                MOVE    PRF_FILE, R9
                RSUB    _P_ICMP, 1
                CMP     0, R10
                RBRA    _P_SL_D, Z
                ADD     1, R1
                RBRA    _P_SL_F, 1
_P_SL_D         CMP     R1, R0                  ; (not in the list: the first)
                RBRA    _P_SL_D0, !Z
                XOR     R1, R1
_P_SL_D0        RSUB    _P_CLR, 1
                MOVE    _PS_TITLE, R8
                XOR     R11, R11
                RSUB    _P_PUT, 1
                XOR     R8, R8
                MOVE    M2M$SA_COL_TTLE, R9
                RSUB    _P_ATTR, 1
                MOVE    1, R8
                RSUB    _P_RULE, 1
                XOR     R2, R2                  ; the names, from row 2
_P_SL_N         CMP     R2, R0
                RBRA    _P_SL_A, Z
                MOVE    PRF_LINE, R3            ; marker + name
                MOVE    0x0020, @R3
                MOVE    R2, R8
                RSUB    _P_LNAME, 1
                MOVE    R8, R4
                MOVE    PRF_FILE, R9
                RSUB    _P_ICMP, 1
                CMP     0, R10
                RBRA    _P_SL_N1, !Z
                MOVE    M2M$OPT_SEL_MULTI, @R3  ; the active one
_P_SL_N1        MOVE    R4, R8                  ; its name (without the number)
                RSUB    _P_PFX, 1
                MOVE    R10, R8
                MOVE    PRF_LINE, R9
                ADD     1, R9
                SYSCALL(strcpy, 1)
                MOVE    PRF_LINE, R8
                MOVE    R2, R11
                ADD     2, R11
                RSUB    _P_PUT, 1
                ADD     1, R2
                RBRA    _P_SL_N, 1
_P_SL_A         MOVE    R0, R8                  ; the separator, Add New
                ADD     2, R8
                RSUB    _P_RULE, 1
                MOVE    _PS_ADD, R8
                MOVE    R0, R11
                ADD     3, R11
                RSUB    _P_PUT, 1
                CMP     2, R0                   ; something to reorder?
                RBRA    _P_SL_SEL, N            ; (2 > R0)
                MOVE    _PS_MOVE, R8
                MOVE    R0, R11
                ADD     5, R11
                RSUB    _P_PUT, 1

_P_SL_SEL       MOVE    R1, R8                  ; the cursor bar
                RSUB    _P_ROW, 1
                MOVE    M2M$SA_COL_STD_INV, R9
                RSUB    _P_ATTR, 1
_P_SL_KEY       RSUB    HANDLE_IO, 1
                RSUB    KEYB$SCAN, 1
                RSUB    KEYB$GETKEY, 1
                CMP     0, R8
                RBRA    _P_SL_KEY, Z
                MOVE    R8, R4                  ; R4: the key
                MOVE    R1, R8                  ; the old bar goes
                RSUB    _P_ROW, 1
                MOVE    M2M$SA_COL_STD, R9
                RSUB    _P_ATTR, 1
                CMP     M2M$KEY_UP, R4
                RBRA    _P_SL_K1, !Z
                SUB     1, R1                   ; up (wraps around on a
                RBRA    _P_SL_SEL, !N           ; new press, Megamiga 0.7;
                MOVE    R0, R1                  ; a held key stops at the top)
                MOVE    M2M$KEY_UP, R8
                RSUB    KEYB$REPEAT, 1
                RBRA    _P_SL_SEL, !C
                XOR     R1, R1
                RBRA    _P_SL_SEL, 1
_P_SL_K1        CMP     M2M$KEY_DOWN, R4
                RBRA    _P_SL_K2, !Z
                ADD     1, R1                   ; down (wraps around on a
                CMP     R1, R0                  ; new press; a held key
                RBRA    _P_SL_SEL, !N           ; stops at the bottom)
                MOVE    M2M$KEY_DOWN, R8
                RSUB    KEYB$REPEAT, 1
                MOVE    R0, R1
                RBRA    _P_SL_SEL, C
                XOR     R1, R1
                RBRA    _P_SL_SEL, 1
_P_SL_K2        CMP     M2M$KEY_LEFT, R4        ; Left: the profile moves up
                RBRA    _P_SL_K3, !Z
                MOVE    R4, R8                  ; (once per press: the keys
                RSUB    KEYB$REPEAT, 1          ; repeat since Megamiga 0.7,
                RBRA    _P_SL_SEL, C            ; each move renames files)
                CMP     0, R1                   ; (not the first, not Add New)
                RBRA    _P_SL_SEL, Z
                CMP     R1, R0
                RBRA    _P_SL_SEL, Z
                SUB     1, R1
                MOVE    R1, R8
                RBRA    _P_SL_MV, 1
_P_SL_K3        CMP     M2M$KEY_RIGHT, R4       ; Right: down
                RBRA    _P_SL_K4, !Z
                MOVE    R4, R8                  ; (once per press)
                RSUB    KEYB$REPEAT, 1
                RBRA    _P_SL_SEL, C
                MOVE    R1, R8                  ; (not the last, not Add New:
                ADD     1, R8                   ; R1 + 1 >= R0)
                CMP     R8, R0
                RBRA    _P_SL_SEL, Z
                RBRA    _P_SL_SEL, N
                MOVE    R1, R8
                ADD     1, R1
_P_SL_MV        RSUB    _P_LSWAP, 1             ; entries R8 and R8 + 1, then
                RSUB    _P_RENUM, 1             ; the files in the new order
                RBRA    _P_SL_D0, 1             ; (the cursor follows)
_P_SL_K4        CMP     M2M$KEY_RETURN, R4
                RBRA    _P_SL_GO, Z
                CMP     M2M$KEY_SPACE, R4
                RBRA    _P_SL_GO, Z
                CMP     M2M$KEY_RUNSTOP, R4
                RBRA    _P_SL_END, Z
                CMP     M2M$KEY_HELP, R4
                RBRA    _P_SL_END, Z
                RBRA    _P_SL_SEL, 1

_P_SL_GO        CMP     R1, R0                  ; Add New Profile
                RBRA    _P_SL_NEW, Z
                MOVE    R1, R8                  ; a profile: the active one
                RSUB    _P_LNAME, 1             ; already?
                MOVE    R8, R4
                MOVE    PRF_FILE, R9
                RSUB    _P_ICMP, 1
                CMP     0, R10
                RBRA    _P_SL_END, Z
                MOVE    R4, R8
                MOVE    PRF_FULL, R9
                SYSCALL(strcpy, 1)
                MOVE    PRF_FULL, R8
                RSUB    _P_READ, 1
                RBRA    _P_SL_END, !C           ; (gone meanwhile: nothing)
                RSUB    _P_APPLY, 1
                MOVE    PRF_FULL, R8
                RSUB    _P_ACTIVATE, 1
                XOR     R8, R8                  ; its Kickstart and hard disks
                MOVE    1, R9                   ; (a switch: the HDL cold-boots)
                RSUB    PROFILE_APPLY, 1
                RBRA    _P_SL_END, 1
_P_SL_NEW       RSUB    _P_ADDNEW, 1
_P_SL_END       RSUB    _P_RELEASE, 1
                RSUB    _P_CLR, 1               ; (standard colours again)
                RSUB    _P_PAINT, 1
                SYSCALL(leave, 1)
                RET

; _P_ROW: selector entry R8 (R0 = the number of profiles) -> R8 = its row
_P_ROW          CMP     R8, R0
                RBRA    _P_RO_A, Z
                ADD     2, R8                   ; a profile: from row 2
                RET
_P_RO_A         ADD     3, R8                   ; Add New: below the bar
                RET

; _P_LNAME: entry R8 of PRF_LIST -> R8 = its file name. R9..R11 used.
_P_LNAME        MOVE    PRF_FLEN, R9
                SYSCALL(mulu, 1)
                MOVE    R10, R8
                ADD     PRF_LIST, R8
                RET

; _P_ADDNEW: Add New Profile: the name (empty: "User N"), then a copy of the
; active profile under it, which becomes the active one: the last of the list
; (the list is numbered first). Registers preserved.
_P_ADDNEW       SYSCALL(enter, 1)
                MOVE    PRF_EMPTY, R8
                XOR     R9, R9
_P_AN_ED        RSUB    _P_EDIT, 1
                RBRA    _P_AN_RET, !C
                MOVE    PRF_EDBUF, R8
                CMP     0, @R8
                RBRA    _P_AN_HAVE, !Z
                RSUB    _P_USERN, 1
_P_AN_HAVE      MOVE    PRF_EDBUF, R8
                RSUB    _P_INLIST, 1
                RBRA    _P_AN_NEW, !C
                MOVE    PRF_EDBUF, R8           ; that name exists: again
                MOVE    _PS_EXISTS, R9
                RBRA    _P_AN_ED, 1
_P_AN_NEW       RSUB    _P_RENUM, 1             ; 01_, 02_, ... and the new one
                MOVE    PRF_LN, R8              ; behind them
                MOVE    @R8, R8
                ADD     1, R8
                MOVE    PRF_EDBUF, R9
                RSUB    _P_MKFULL, 1
                RSUB    _P_SERIAL, 1            ; the settings of the active
                MOVE    PRF_FULL, R8            ; profile under the new name
                RSUB    _P_WRITE, 1
                RBRA    _P_AN_RET, !C
                MOVE    PRF_FULL, R8
                RSUB    _P_ACTIVATE, 1
_P_AN_RET       SYSCALL(leave, 1)
                RET
PRF_EMPTY       .DW     0

; B4_PRF_RENAME (" Rename Profile", OSM_SEL_POST): a new name for the active
; profile (its file is renamed). The caller redraws the menu. Registers
; preserved.
B4_PRF_RENAME   SYSCALL(enter, 1)
                RSUB    _P_FLUSH, 1
                RSUB    _P_LIST, 1
                MOVE    PRF_NAME, R8
                XOR     R9, R9
_P_RN_ED        RSUB    _P_EDIT, 1
                RBRA    _P_RN_END, !C
                MOVE    PRF_EDBUF, R8
                CMP     0, @R8                  ; empty: the name stays
                RBRA    _P_RN_END, Z
                MOVE    PRF_NAME, R9
                SYSCALL(strcmp, 1)
                CMP     0, R10
                RBRA    _P_RN_END, Z            ; unchanged
                RSUB    _P_ICMP, 1              ; only upper/lower case differs:
                CMP     0, R10                  ; fine (FAT32 finds the old
                RBRA    _P_RN_GO, Z             ; entry itself)
                RSUB    _P_INLIST, 1
                RBRA    _P_RN_GO, !C
                MOVE    _PS_EXISTS, R9          ; exists: again
                RBRA    _P_RN_ED, 1
_P_RN_GO        MOVE    PRF_FILE, R8            ; the new file name: the number
                RSUB    _P_PFX, 1               ; of the old one + the new name
                CMP     0xFFFF, R9              ; (none yet: the list is
                RBRA    _P_RN_G1, !Z            ; numbered first, so a name
                RSUB    _P_RENUM, 1             ; like "7_up" stays as it is)
                MOVE    PRF_FILE, R8
                RSUB    _P_PFX, 1
_P_RN_G1        MOVE    PRF_FILE, R1
                MOVE    PRF_FULL, R2
_P_RN_P         CMP     R1, R10
                RBRA    _P_RN_P2, Z
                MOVE    @R1++, @R2++
                RBRA    _P_RN_P, 1
_P_RN_P2        MOVE    PRF_EDBUF, R8
                MOVE    R2, R9
                SYSCALL(strcpy, 1)
                MOVE    PRF_FILE, R8            ; the file of the old name
                RSUB    _P_OPEN, 1
                RBRA    _P_RN_NOF, !C
                MOVE    PRF_FILE, R8
                MOVE    PRF_FULL, R9
                RSUB    _P_RENFILE, 1
                RBRA    _P_RN_END, !C
                MOVE    PRF_FULL, R8
                RSUB    _P_ACTIVATE, 1
                RBRA    _P_RN_END, 1
_P_RN_NOF       RSUB    _P_SERIAL, 1            ; no file (the A500 defaults
                MOVE    PRF_FULL, R8            ; in memory): one with the new
                RSUB    _P_WRITE, 1             ; name
                RBRA    _P_RN_END, !C
                MOVE    PRF_FULL, R8
                RSUB    _P_ACTIVATE, 1
_P_RN_END       RSUB    _P_CLR, 1
                RSUB    _P_PAINT, 1
                SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; B4_HDF_MAP (HDF_PREP, 0.7): the extent map of the HDF (FAT32$FILE_MAP into
; HDF_MAP) with the progress bar of FAST_LOAD: walking the cluster chain of a
; large file takes seconds. FAT32$FILE_MAP_CB calls FL_BAR_STEP (all
; registers preserved) once per 256 clusters; the bar is set up for
; (size >> (17 + log2 sectors per cluster)) + 1 steps, one per 256 clusters
; (FL_NOBAR - PROFILE_APPLY - leaves it off). Output: R9, R10 as
; FAT32$FILE_MAP; R8 = HDF_FDH, R11 preserved.
; ----------------------------------------------------------------------------
B4_HDF_MAP      MOVE    R11, @--SP
                INCRB
                MOVE    HDF_FDH, R0
                MOVE    @R0, R1                 ; R1: sectors per cluster
                ADD     FAT32$DEV_SECT_PER_CLUS, R1
                MOVE    @R1, R1
                MOVE    R0, R2                  ; R3|R2: the size
                ADD     FAT32$FDH_SIZE_LO, R2
                MOVE    @R2++, R3
                MOVE    @R2, R2
                MOVE    R3, R4                  ; R2|R4 (hi|lo) >>= 17 + log2
                MOVE    17, R5                  ; (spc)
_B4_HM_L        CMP     1, R1
                RBRA    _B4_HM_S, Z
                SHR     1, R1
                AND     0x7FFF, R1
                ADD     1, R5
                RBRA    _B4_HM_L, 1
_B4_HM_S        MOVE    R2, R6                  ; one bit at a time: R2|R4
                AND     1, R6
                AND     0xFFFB, SR
                SHR     1, R2
                AND     0xFFFB, SR
                SHR     1, R4
                CMP     0, R6
                RBRA    _B4_HM_S1, Z
                OR      0x8000, R4
_B4_HM_S1       SUB     1, R5
                RBRA    _B4_HM_S, !Z
                ADD     1, R4                   ; R4: steps (the high word is 0
                MOVE    R4, R8                  ; for files below 8 GB)
                AND     0xFFFD, SR              ; FL_BAR_INIT wants a size:
                SHL     9, R8                   ; R9|R8 = steps x 512
                MOVE    R4, R9
                AND     0xFFFB, SR
                SHR     7, R9
_B4_HM_I        RSUB    FL_BAR_INIT, 1
                MOVE    HDF_FDH, R8
                MOVE    HDF_MAP, R9
                MOVE    HDF_MAP_WORDS, R10
                MOVE    FL_BAR_STEP, R11
                RSUB    FAT32$FILE_MAP_CB, 1
                DECRB
                MOVE    @SP++, R11
                RET

