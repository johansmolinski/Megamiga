# Ethernet (design)

Megamiga's network card: a Zorro II board in the FPGA, wired to the MEGA65's
KSZ8081 PHY (RMII, 100 Mbit/s), and a SANA-II driver `megamiga-eth.device`
adapted from Niklas Ekström's a314eth.device (CC0,
https://github.com/niklasekstrom/a314). No real card is emulated; the
register interface below is ours. Status: implemented and hardware-confirmed on R6, 2026-10-09 (ARP, Roadshow 1.15:
ping, an 8 MB HTTP download).

## Board

- Zorro II, 64 KB, in `cpu_wrapper.v`'s autoconfig chain after the IDE board
  (`ac_eth`, `eth_ena`), so it works with the 68000 and the 68020 and with
  Kickstart 1.3 (expansion.library `FindConfigDev`).
- Manufacturer 2011 ($07DB, the Commodore "hacker" ID for experimental
  boards), product 101 ($65). The driver looks for exactly this pair.
- Bus cycles leave the chip bus through cpu_wrapper's `ext_*` port, shared
  with the IDE board (`ext_eth` tells them apart).
- Interrupt: INT2 (PORTS), ORed into Paula's `int2` in minimig.v, level, held
  while (IRQ status and IRQ enable) /= 0.

## Register map (byte offsets in the board; registers are 16 bit)

| Offset | Name | Access | Meaning |
|---|---|---|---|
| $0000 | ID | R | $E7E7 |
| $0002 | VERSION | R | 1 |
| $0004 | CTRL | R/W | 0 RX enable, 1 accept broadcast, 2 accept multicast, 3 promiscuous, 4 RX IRQ enable, 5 TX IRQ enable (an Amiga reset clears it) |
| $0006 | STATUS | R | 0 link up, 1 100 Mbit/s, 2 full duplex, 3 TX busy, 4 RX ring full |
| $0008 | IRQ | R / W1C | 0 RX frame(s) waiting (a level: clears when RX_TAIL reaches RX_HEAD), 1 TX done (write 1 to clear) |
| $000A | RX_HEAD | R | slot the card fills next (0..15); slots RX_TAIL .. RX_HEAD-1 hold frames |
| $000C | RX_TAIL | R/W | slot the driver reads next; write the next slot to free one (RX_TAIL := RX_HEAD discards everything) |
| $000E | TX_LEN | W | start sending the TX buffer, length in bytes (60..1514, shorter frames are padded; without FCS, the card appends it); R: last value |
| $0010-$0015 | MAC | R/W | station address, byte order as on the wire; power-on value from the FPGA's DNA (locally administered, 02:xx:xx:xx:xx:xx) |
| $0018 | PHASE | R/W | 1:0 RX sample phase, 3:2 TX drive phase (200 MHz steps); default $05 (the MEGA65's etherload values) |
| $0020 | RX_FRAMES | R | counter, frames stored |
| $0022 | RX_DROPPED | R | counter, frames lost because the ring was full |
| $0024 | RX_CRCERR | R | counter, frames with a bad FCS or too long |
| $0026 | TX_FRAMES | R | counter |
| $4000-$47FF | TX buffer | W | the frame to send (destination MAC first); write-only |
| $8000-$FFFF | RX ring | R | 16 slots of 2 KB; slot n at $8000 + n * $800: word 0 = length (without FCS), bytes 2.. = the frame; a frame is stored if its FCS is right, it has 60..1514 bytes and a whole number of bytes, the filter lets it through and the ring has room (15 slots usable) |

The frame in an RX slot starts at offset 2, so the IP header after the 14-byte
Ethernet header is longword aligned.

## FPGA side

- Clocks: a new MMCM, 100 MHz board clock -> 50 MHz (RMII reference, driven
  straight to `eth_clock_o` as the MEGA65 core does) and 200 MHz, phase
  aligned. RX data is latched at 200 MHz at the selected phase and taken over
  by the 50 MHz MAC; TX data goes through a 4-stage 200 MHz delay line (the
  MEGA65 core's scheme, `ethernet.vhdl`).
- MAC (50 MHz): RX: CRS_DV, preamble/SFD, dibits to bytes, CRC-32 check,
  address filter (own MAC, broadcast, multicast, promiscuous), frame into the
  current ring slot, drop if the ring is full or the frame is too long. TX:
  preamble, SFD, data, padding to 60 bytes, FCS, 96-bit inter-frame gap.
- 100 Mbit/s only: the management interface (MDC/MDIO) advertises 100BASE-TX
  full and half duplex only, restarts autonegotiation and polls the link
  state. No collision handling (half duplex hubs are not supported).
- PHY reset: low for 10 ms after configuration.
- Buffers: dual-clock block RAM, CPU side on the core clock, MAC side on
  50 MHz; ring indices and the TX start/done handshake cross by toggles and
  synchronizers.
- Board tops: the `eth_*` pins are routed into `MEGA65_Core` (new M2M
  exception `eth-pins`, the floppy-pins pattern).

## Driver

a314eth.device with the A314 transport replaced:

- open: `FindConfigDev(NULL, 2011, 101)`, board base from `cd_BoardAddr`;
  an INT2 server (`AddIntServer(INTB_PORTS)`) that checks IRQ & CTRL, acks
  and signals the device process.
- RX: the device process walks RX_TAIL .. RX_HEAD, matches the frame type
  against the queued CMD_READ requests and copies straight from the card
  (S2_CopyToBuff), then frees the slot.
- TX: when TX is not busy, the next CMD_WRITE is copied into the TX buffer
  (S2_CopyFromBuff) and TX_LEN starts it.
- S2_GETSTATIONADDRESS / S2_CONFIGINTERFACE from and to the MAC registers.
- Built with vbcc and NDK 3.2 (`~/aexp-work/eth/tc`).
