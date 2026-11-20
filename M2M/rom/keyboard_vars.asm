; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Variables for Keyboard Controller (keyboard.asm): Need to be located in RAM
;
; originally made for gbc4mega65 by sy2002 in 2021
; adpoted for MiSTer2MEGA65 by sy2002 in 2021 and licensed under GPL v3
; ****************************************************************************

; each key represented by one bit in these two words
KEYB_PRESSED    .BLOCK 1                        ; currently pressed
KEYB_NEWKEYS    .BLOCK 1                        ; newly pressed since last..
                                                ; ..call of KEYB_GETKEY

; typematic repeat (M2M-UPSTREAM typematic-time, Megamiga 2026-11-19): two
; words per key of _KEYB_TM_KEYS (keyboard.asm: down, up, left, right): the
; IO$CYC_MID time of the press or of the last repeat, then the state
; (0 = released, 1 = delay, 2 = repeating)
KEYB_TM_SIZE    .EQU 8
KEYB_TM         .BLOCK 8
