#!/bin/sh
# Megamiga: build megamiga-eth.device (SANA-II driver for the network card) with vbcc 0.9h and the
# NDK 3.2 (Aminet dev/misc/NDK3.2.lha): VBCC = the vbcc installation (bin/, config/, targets/
# m68k-amigaos/), NDK = the unpacked NDK (Include_H, lib, SANA+RoadshowTCP-IP/include).
set -e
cd "$(dirname "$0")"
: "${VBCC:?set VBCC to the vbcc installation}"
: "${NDK:?set NDK to the unpacked NDK 3.2}"
PATH="$VBCC/bin:$PATH"
export VBCC
vc +aos68k romtag.asm device.c -O2 -nostdlib -I"$NDK/Include_H" -I"$NDK/SANA+RoadshowTCP-IP/include" \
   -L"$NDK/lib" -lamiga -o megamiga-eth.device
ls -l megamiga-eth.device
vc +aos68k ethtest.c -O2 -I"$NDK/Include_H" -L"$NDK/lib" -lamiga -o ethtest
ls -l ethtest
