; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Keyboard controller (expects low-active keys in the QNICE register)
;
; The basic idea is: A key first has to be released until it can be counted
; as pressed again.
;
; originally made for gbc4mega65 by sy2002 in 2021
; adpoted for MiSTer2MEGA65 by sy2002 in 2021 and licensed under GPL v3
; ****************************************************************************

; call this before working with this library
KEYB$INIT       INCRB
                MOVE    KEYB_PRESSED, R0
                MOVE    0xFFFF, @R0             ; low active, i.e. no keys
                MOVE    KEYB_NEWKEYS, R0
                MOVE    0, @R0                  ; high active, i.e. no keys
                MOVE    KEYB_TM, R0             ; M2M-UPSTREAM typematic-time
                MOVE    KEYB_TM_SIZE, R1
_KEYB_INIT_L    MOVE    0, @R0++
                SUB     1, R1
                RBRA    _KEYB_INIT_L, !Z
                DECRB
                RET

; perform one scan iteration; meant to be called repeatedly
KEYB$SCAN       INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    R10, R2
                MOVE    R11, R3
                INCRB

                MOVE    M2M$KEYBOARD, R0        ; R0: keyboard status
                MOVE    @R0, R0
                NOT     R0, R0                  ; convert to high-active

                MOVE    KEYB_PRESSED, R1        ; R1 points to PRESSED
                MOVE    KEYB_NEWKEYS, R2        ; R2 points to NEWKEYS

                ; keys need to be released first to count as new keys again
                NOT     @R1, R3
                AND     R0, R3
                OR      R3, @R2

                ; store currently pressed keys
                MOVE    R0, @R1

                ; typematic repeat for the cursor keys
                ; (only inside QNICE as Game Boy does its own thing)
                ; M2M-UPSTREAM typematic-time: all four of them (left/right
                ; page through the file browser and the help screens)
                MOVE    _KEYB_TM_KEYS, R4
                MOVE    R1, R9                  ; R9: PRESSED
                MOVE    KEYB_TM, R10            ; R10/R11: time/state
_KEYB_SCAN_TM   MOVE    @R4++, R8               ; R8: the key
                RBRA    _KEYB_SCAN_E, Z
                MOVE    R10, R11
                ADD     1, R11
                RSUB    _KEYB_TYPEMATIC, 1
                ADD     2, R10
                RBRA    _KEYB_SCAN_TM, 1

_KEYB_SCAN_E    DECRB
                MOVE    R0, R8
                MOVE    R1, R9
                MOVE    R2, R10
                MOVE    R3, R11
                DECRB
                RET

; returns new key in R8
KEYB$GETKEY     INCRB

                MOVE    1, R0                   ; R0: key scanner
                MOVE    KEYB_NEWKEYS, R1        ; R1: list of new keys

_KEYB_GK_LOOP   MOVE    @R1, R2                 ; scan at current R0 pos.
                AND     R0, R2
                RBRA    _KEYBGK_RET_R2, !Z      ; key found? return it
                AND     0xFFFD, SR              ; no: clear X-flag, shift in 0
                SHL     1, R0                   ; move "scanner"
                RBRA    _KEYB_GK_LOOP, !Z       ; loop if not yet done
                RBRA    _KEYBGK_RET_0, 1        ; return 0, if nothing found

_KEYBGK_RET_R2  MOVE    R2, R8                  ; return new key
                NOT     R2, R2
                AND     R2, @R1                 ; unmark this key as new
                RBRA    _KEYBGK_RET, 1

_KEYBGK_RET_0   MOVE    0, R8
_KEYBGK_RET     DECRB
                RET

; M2M-UPSTREAM typematic-time (Megamiga 2026-11-19): is the cursor key R8
; (M2M$KEY_UP/DOWN/LEFT/RIGHT) auto-repeating right now? Lists use it to stop
; at their end while a key is held and to wrap around only on a new press.
; Output: C = 1: repeating; registers preserved
KEYB$REPEAT     INCRB
                MOVE    _KEYB_TM_KEYS, R0
                MOVE    KEYB_TM, R1             ; R1: state of the key
                XOR     R2, R2                  ; (no cursor key: state 0)
_KEYB_RPT_L     CMP     0, @R0
                RBRA    _KEYB_RPT_C, Z
                ADD     1, R1
                CMP     @R0++, R8
                RBRA    _KEYB_RPT_F, Z
                ADD     1, R1
                RBRA    _KEYB_RPT_L, 1
_KEYB_RPT_F     MOVE    @R1, R2
_KEYB_RPT_C     MOVE    1, R3
                SUB     R2, R3                  ; C = 1 (borrow): state 2
                DECRB
                RET

; M2M-UPSTREAM typematic-time: the keys with typematic repeat, each with two
; words in KEYB_TM (time, state); zero-terminated
_KEYB_TM_KEYS   .DW     M2M$KEY_DOWN, M2M$KEY_UP, M2M$KEY_LEFT, M2M$KEY_RIGHT
                .DW     0

; internal helper function for typematic repeat
; M2M-UPSTREAM typematic-time (Megamiga 2026-11-19): the delay and the repeat
; rate are measured with the cycle counter (IO$CYC_MID ticks, 50 MHz / 65536
; = 1.31 ms) instead of in calls of this function: a core's HANDLE_CORE_IO
; runs in every key-wait iteration and made a long press wait seconds for the
; first repeat in the file browser.
; R8: key code of key that shall be handled
; R9: pointer to PRESSED flag-word
; R10: pointer to the IO$CYC_MID time of the press or of the last repeat
; R11: pointer to the state: 0 = released, 1 = delay, 2 = repeating
_KEYB_TYPEMATIC INCRB

                MOVE    @R9, R0
                AND     R8, R0                  ; to-be-handled key pressed?
                RBRA    _KEYB_TYPEM_REL, Z      ; no: state "released"
                MOVE    IO$CYC_MID, R1
                MOVE    @R1, R1                 ; R1: now
                CMP     0, @R11                 ; just pressed?
                RBRA    _KEYB_TYPEM_DN, !Z      ; no: it was down before
                MOVE    1, @R11                 ; yes: the delay starts now
                RBRA    _KEYB_TYPEM_TS, 1
_KEYB_TYPEM_DN  MOVE    M2M$TYPEMATIC_DLY, R6   ; delay or repeat rate
                CMP     1, @R11
                RBRA    _KEYB_TYPEM_C, Z
                MOVE    M2M$TYPEMATIC_SPD, R6
_KEYB_TYPEM_C   MOVE    R1, R2
                SUB     @R10, R2                ; R2: ticks since then
                CMP     R6, R2
                RBRA    _KEYB_TYPEM_RET, N      ; (R6 > R2): not yet

                MOVE    R8, R0                  ; yes: unpress key
                NOT     R0, R0
                AND     R0, @R9
                MOVE    2, @R11                 ; repeating from now on
_KEYB_TYPEM_TS  MOVE    R1, @R10                ; the time of this event
                RBRA    _KEYB_TYPEM_RET, 1

_KEYB_TYPEM_REL MOVE    0, @R11                 ; released

_KEYB_TYPEM_RET DECRB
                RET
