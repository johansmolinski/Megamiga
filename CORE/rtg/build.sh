#!/bin/sh
# Megamiga: build MiSTer.card (the Picasso96 driver) with vasm, http://sun.hasenbraten.de/vasm/
# (make CPU=m68k SYNTAX=mot). With the original constants this reproduces MiSTer's MiSTer.card
# of MiSTer_RTG.lha byte for byte; MiSTer's build.bat links with vc instead.
VASM=${VASM:-vasmm68k_mot}
cd "$(dirname "$0")" && $VASM -quiet -nosym -Iinclude -Fhunkexe -phxass -opt-fconst -nowarn=62 -o MiSTer.card MiSTer.card.asm
