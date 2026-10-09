Megamiga network card
=====================

The Megamiga core has a network card for the MEGA65's Ethernet port
(100 Mbit/s). This disk holds its SANA-II driver and a test tool.

  Devs/Networks/megamiga-eth.device   the driver (SANA-II, unit 0)
  C/ethtest                           checks the card without a TCP/IP stack
  Roadshow/                           configuration files for Roadshow

Test the card first, from a Shell (Kickstart 2.04 or newer):

  ethtest                  shows the card's address, the link and counters
  ethtest 192.168.1.1      sends an ARP probe to that address (use your
                           router's) and shows the reply: if it comes, the
                           card sends and receives
  ethtest 192.168.1.1 PHASES
                           tries every RX/TX sampling phase and shows which
                           ones get a reply (only if the plain test fails)

Roadshow:

  copy Devs/Networks/megamiga-eth.device DEVS:Networks/
  copy Roadshow/MegamigaEth DEVS:NetInterfaces/

The interface gets its address by DHCP; for a fixed address edit the file
and DEVS:Internet/routes and name_resolution (examples in Roadshow/).

Other stacks (AmiTCP, Miami, Genesis): use the SANA-II device
DEVS:Networks/megamiga-eth.device, unit 0.

The driver is based on a314eth.device by Niklas Ekstrom (CC0,
https://github.com/niklasekstrom/a314). Source and the card's description:
https://github.com/johansmolinski/Megamiga (CORE/eth, doc/developers/ethernet.md).
