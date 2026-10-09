/*
 * ethtest - check the Megamiga network card without a TCP/IP stack
 *
 *   ethtest                 card, station address, link, counters
 *   ethtest 192.168.1.1     + ARP probe for that address: the reply proves TX and RX
 *   ethtest 192.168.1.1 PHASES
 *                           + the probe with every RX/TX sampling phase (PHASE register),
 *                             for bringing up a board whose timing differs
 *
 * Needs Kickstart 2.04 or newer (dos.library Printf). Do not run it while the
 * megamiga-eth.device is in use (it takes the card over).
 *
 * Megamiga, October 2026. Licensed under the GPL v3.
 */

#include <exec/types.h>
#include <libraries/configvars.h>
#include <dos/dos.h>

#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/expansion.h>

#include <string.h>

#define R_ID		0x00
#define R_VERSION	0x02
#define R_CTRL		0x04
#define R_STATUS	0x06
#define R_IRQ		0x08
#define R_RX_HEAD	0x0A
#define R_RX_TAIL	0x0C
#define R_TX_LEN	0x0E
#define R_MAC		0x10
#define R_PHASE		0x18
#define R_RX_FRAMES	0x20
#define R_RX_DROPPED	0x22
#define R_RX_CRCERR	0x24
#define R_TX_FRAMES	0x26

#define REG(o)		(*(volatile UWORD *)(card + (o)))

struct ExpansionBase *ExpansionBase;
static volatile UBYTE *card;
static UBYTE mac[6];

static int parse_ip(const char *s, UBYTE ip[4])
{
	for (int i = 0; i < 4; i++)
	{
		int v = 0, n = 0;
		while (*s >= '0' && *s <= '9')
		{
			v = v * 10 + (*s++ - '0');
			n++;
		}
		if (n == 0 || v > 255 || (i < 3 && *s++ != '.'))
			return 0;
		ip[i] = v;
	}
	return *s == 0;
}

/* an ARP probe (sender IP 0.0.0.0) for ip; returns 1 and the replier's MAC if a reply
   came within about a second */
static int arp_probe(const UBYTE ip[4], UBYTE who[6])
{
	UBYTE f[42];
	memset(f, 0xff, 6);			/* broadcast */
	memcpy(f + 6, mac, 6);
	f[12] = 0x08; f[13] = 0x06;		/* ARP */
	f[14] = 0; f[15] = 1;			/* Ethernet */
	f[16] = 0x08; f[17] = 0x00;		/* IPv4 */
	f[18] = 6; f[19] = 4;
	f[20] = 0; f[21] = 1;			/* request */
	memcpy(f + 22, mac, 6);
	memset(f + 28, 0, 4);			/* sender IP 0: a probe */
	memset(f + 32, 0, 6);
	memcpy(f + 38, ip, 4);

	REG(R_RX_TAIL) = REG(R_RX_HEAD);	/* forget older frames */
	for (int i = 0; i < 42; i += 2)
		*(volatile UWORD *)(card + 0x4000 + i) = (f[i] << 8) | f[i + 1];
	while (REG(R_STATUS) & 8)
		;
	REG(R_TX_LEN) = 42;

	for (int t = 0; t < 50; t++)
	{
		Delay(1);
		UWORD tail = REG(R_RX_TAIL), head = REG(R_RX_HEAD);
		while (tail != head)
		{
			volatile UBYTE *s = card + 0x8000 + tail * 0x800;
			UWORD len = *(volatile UWORD *)s;
			volatile UBYTE *p = s + 2;
			tail = (tail + 1) & 15;
			REG(R_RX_TAIL) = tail;
			if (len >= 42 && p[12] == 0x08 && p[13] == 0x06 && p[21] == 2 &&
			    p[28] == ip[0] && p[29] == ip[1] && p[30] == ip[2] && p[31] == ip[3])
			{
				for (int i = 0; i < 6; i++)
					who[i] = p[22 + i];
				return 1;
			}
		}
	}
	return 0;
}

int main(int argc, char **argv)
{
	ExpansionBase = (struct ExpansionBase *)OpenLibrary("expansion.library", 36);
	if (!ExpansionBase)
	{
		Printf("ethtest needs Kickstart 2.04 or newer\n");
		return 20;
	}
	struct ConfigDev *cd = FindConfigDev(NULL, 2011, 101);
	CloseLibrary((struct Library *)ExpansionBase);
	if (!cd)
	{
		Printf("No Megamiga network card found (manufacturer 2011, product 101)\n");
		return 20;
	}
	card = (volatile UBYTE *)cd->cd_BoardAddr;

	Printf("Card at $%08lx: ID $%04lx, version %ld\n", (ULONG)card, (ULONG)REG(R_ID), (ULONG)REG(R_VERSION));
	if (REG(R_ID) != 0xE7E7)
	{
		Printf("Wrong ID\n");
		return 20;
	}
	for (int i = 0; i < 6; i += 2)
	{
		UWORD w = REG(R_MAC + i);
		mac[i] = w >> 8;
		mac[i + 1] = w & 0xff;
	}
	UWORD st = REG(R_STATUS);
	Printf("Station address %02lx:%02lx:%02lx:%02lx:%02lx:%02lx\n", (ULONG)mac[0], (ULONG)mac[1],
	       (ULONG)mac[2], (ULONG)mac[3], (ULONG)mac[4], (ULONG)mac[5]);
	Printf("Link %s%s%s, PHASE $%02lx\n", (st & 1) ? "up" : "DOWN", (st & 2) ? ", 100 Mbit/s" : "",
	       (st & 4) ? ", full duplex" : (st & 1) ? ", half duplex" : "", (ULONG)REG(R_PHASE));
	Printf("Counters: RX frames %ld, dropped %ld, bad %ld; TX frames %ld\n",
	       (ULONG)REG(R_RX_FRAMES), (ULONG)REG(R_RX_DROPPED), (ULONG)REG(R_RX_CRCERR), (ULONG)REG(R_TX_FRAMES));

	if (argc < 2)
		return 0;

	UBYTE ip[4], who[6];
	if (!parse_ip(argv[1], ip))
	{
		Printf("Usage: ethtest [ip-address [PHASES]]\n");
		return 10;
	}

	UWORD ctrl = REG(R_CTRL);
	REG(R_CTRL) = 0x03;			/* RX on, broadcast, no interrupts */

	int ok = 0;
	if (argc >= 3)
	{
		UWORD phase = REG(R_PHASE);
		Printf("        TX 0  TX 1  TX 2  TX 3\n");
		for (int rx = 0; rx < 4; rx++)
		{
			Printf("RX %ld   ", (ULONG)rx);
			for (int tx = 0; tx < 4; tx++)
			{
				REG(R_PHASE) = (tx << 2) | rx;
				Delay(2);
				int r = arp_probe(ip, who);
				ok |= r;
				Printf("%s", r ? " ok   " : " -    ");
			}
			Printf("\n");
		}
		REG(R_PHASE) = phase;
	}
	else
	{
		ok = arp_probe(ip, who);
		if (ok)
			Printf("ARP reply from %ld.%ld.%ld.%ld: %02lx:%02lx:%02lx:%02lx:%02lx:%02lx\n",
			       (ULONG)ip[0], (ULONG)ip[1], (ULONG)ip[2], (ULONG)ip[3],
			       (ULONG)who[0], (ULONG)who[1], (ULONG)who[2], (ULONG)who[3], (ULONG)who[4], (ULONG)who[5]);
		else
			Printf("No ARP reply from %ld.%ld.%ld.%ld\n", (ULONG)ip[0], (ULONG)ip[1], (ULONG)ip[2], (ULONG)ip[3]);
	}
	Printf("Counters: RX frames %ld, dropped %ld, bad %ld; TX frames %ld\n",
	       (ULONG)REG(R_RX_FRAMES), (ULONG)REG(R_RX_DROPPED), (ULONG)REG(R_RX_CRCERR), (ULONG)REG(R_TX_FRAMES));

	REG(R_CTRL) = ctrl;
	return ok ? 0 : 5;
}
