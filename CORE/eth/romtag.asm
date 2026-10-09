; megamiga-eth.device: romtag, device process entry and the interrupt server.
; Based on a314eth.device by Niklas Ekstrom (CC0), https://github.com/niklasekstrom/a314

	XDEF	_device_process_seglist
	XDEF	_int_server
	XREF	_device_process_run
	XREF	_int_c

RTC_MATCHWORD:	equ	$4afc
RTF_AUTOINIT:	equ	(1<<7)
NT_DEVICE:	equ	3
VERSION:	equ	1
PRIORITY:	equ	0

		section	code,code

		moveq	#-1,d0
		rts

romtag:
		dc.w	RTC_MATCHWORD
		dc.l	romtag
		dc.l	endcode
		dc.b	RTF_AUTOINIT
		dc.b	VERSION
		dc.b	NT_DEVICE
		dc.b	PRIORITY
		dc.l	_device_name
		dc.l	_id_string
		dc.l	_auto_init_tables
endcode:

; INT2 (PORTS) server: a1 = is_Data. The C part checks the card, masks the RX interrupt,
; acknowledges TX done and signals the device process. Z set on return: the other servers of
; the chain run as well (the line is shared).
_int_server:
		jsr	_int_c
		moveq	#0,d0
		rts

		cnop	0,4

		dc.l	16
_device_process_seglist:
		dc.l	0
		jmp	_device_process_run
