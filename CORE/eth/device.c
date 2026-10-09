/*
 * megamiga-eth.device - SANA-II driver for the Megamiga network card (MEGA65 Ethernet port)
 *
 * Based on a314eth.device, Copyright (c) 2020 Niklas Ekström, released under CC0 1.0
 * (https://github.com/niklasekstrom/a314, Software/ethernet), which thanks Christian Vogelgsang
 * and Mike Sterling for inspiration from their SANA-II drivers:
 * - https://github.com/cnvogelg/plipbox
 * - https://github.com/mikestir/k1208-drivers
 *
 * Megamiga, October 2026: the A314 transport replaced by the card's registers and buffers
 * (CORE/vhdl/eth_card.vhd, doc/developers/ethernet.md): frames are copied straight between the
 * stack's buffers and the card's RX ring and TX buffer; an INT2 server wakes the device process.
 * The Megamiga changes are licensed under the GPL v3 like the rest of Megamiga.
 */

#include <exec/types.h>
#include <exec/execbase.h>
#include <exec/devices.h>
#include <exec/errors.h>
#include <exec/ports.h>
#include <exec/interrupts.h>
#include <hardware/intbits.h>
#include <libraries/dos.h>
#include <libraries/configvars.h>
#include <devices/sana2.h>

#include <proto/alib.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/timer.h>
#include <proto/expansion.h>

#include <string.h>

// Defines.

#define DEVICE_NAME		"megamiga-eth.device"

#define TASK_PRIO		10

#define MACADDR_SIZE		6
#define NIC_BPS			100000000

#define ETH_MTU			1500
#define RAW_MTU			1514

// The card (eth_card.vhd).
#define CARD_MANUFACTURER	2011
#define CARD_PRODUCT		101
#define CARD_ID			0xE7E7

#define R_ID			0x00
#define R_CTRL			0x04
#define R_STATUS		0x06
#define R_IRQ			0x08
#define R_RX_HEAD		0x0A
#define R_RX_TAIL		0x0C
#define R_TX_LEN		0x0E
#define R_MAC			0x10
#define R_RX_FRAMES		0x20
#define R_RX_DROPPED		0x22
#define R_RX_CRCERR		0x24
#define R_TX_FRAMES		0x26
#define TX_BUFFER		0x4000
#define RX_RING			0x8000
#define RX_SLOT_SIZE		0x800
#define RX_SLOTS		16

#define CTRL_RX			0x01
#define CTRL_BCAST		0x02
#define CTRL_MCAST		0x04
#define CTRL_PROMISC		0x08
#define CTRL_RXIRQ		0x10
#define CTRL_TXIRQ		0x20
#define STATUS_TXBUSY		0x08
#define IRQ_RX			0x01
#define IRQ_TX			0x02

#define REG(o)			(*(volatile UWORD *)(card + (o)))

// Typedefs.

typedef BOOL (*buf_copy_func_t)(__reg("a0") void *dst, __reg("a1") void *src, __reg("d0") LONG size);

// Structs.

#pragma pack(push, 1)
struct EthHdr
{
	unsigned char eh_Dst[MACADDR_SIZE];
	unsigned char eh_Src[MACADDR_SIZE];
	unsigned short eh_Type;
};
#pragma pack(pop)

struct IntData
{
	volatile UBYTE *id_Card;
	struct Task *id_Task;
	ULONG id_SigMask;
};

// Constants.

const char device_name[] = DEVICE_NAME;
const char id_string[] = DEVICE_NAME " 1.0 (9.10.2026)";

static const char expansion_name[] = "expansion.library";

// Global variables.

BPTR saved_seg_list;
struct ExecBase *SysBase;
struct DosLibrary *DOSBase;

buf_copy_func_t copyfrom;
buf_copy_func_t copyto;

volatile UBYTE *card;
unsigned char macaddr[MACADDR_SIZE];

volatile struct List ut_rbuf_list;
volatile struct List ut_wbuf_list;

volatile ULONG sana2_sigmask;
volatile ULONG shutdown_sigmask;

volatile struct Task *init_task;

struct Process *device_process;
volatile int device_start_error;

struct Sana2DeviceStats global_stats;

struct Interrupt card_int;
struct IntData int_data;

UWORD rx_tail;
UWORD ctrl_bits;

BOOL is_online;

// External declarations.

extern void device_process_seglist();
extern void int_server();

// Procedures.

static struct Library *init_device(__reg("a6") struct ExecBase *sys_base, __reg("a0") BPTR seg_list, __reg("d0") struct Library *dev)
{
	saved_seg_list = seg_list;

	dev->lib_Node.ln_Type = NT_DEVICE;
	dev->lib_Node.ln_Name = (char *)device_name;
	dev->lib_Flags = LIBF_SUMUSED | LIBF_CHANGED;
	dev->lib_Version = 1;
	dev->lib_Revision = 0;
	dev->lib_IdString = (APTR)id_string;

	SysBase = *(struct ExecBase **)4;
	DOSBase = (struct DosLibrary *)OpenLibrary(DOSNAME, 0);

	return dev;
}

static BPTR expunge(__reg("a6") struct Library *dev)
{
	if (dev->lib_OpenCnt)
	{
		dev->lib_Flags |= LIBF_DELEXP;
		return 0;
	}

	// Shady way of waiting for device process to terminate before unloading.
	Delay(10);

	CloseLibrary((struct Library *)DOSBase);

	Remove(&dev->lib_Node);
	FreeMem((char *)dev - dev->lib_NegSize, dev->lib_NegSize + dev->lib_PosSize);
	return saved_seg_list;
}

// INT2 server (called from int_server in romtag.asm): the RX interrupt is a level that stays
// up while frames wait, so it is masked here and unmasked by the device process once it has
// emptied the ring; TX done is acknowledged.
void int_c(__reg("a1") struct IntData *d)
{
	volatile UBYTE *c = d->id_Card;
	UWORD irq = *(volatile UWORD *)(c + R_IRQ);
	UWORD ctrl = *(volatile UWORD *)(c + R_CTRL);
	BOOL mine = FALSE;

	if ((irq & IRQ_RX) && (ctrl & CTRL_RXIRQ))
	{
		*(volatile UWORD *)(c + R_CTRL) = ctrl & ~CTRL_RXIRQ;
		mine = TRUE;
	}
	if ((irq & IRQ_TX) && (ctrl & CTRL_TXIRQ))
	{
		*(volatile UWORD *)(c + R_IRQ) = IRQ_TX;
		mine = TRUE;
	}
	if (mine)
		Signal(d->id_Task, d->id_SigMask);
}

static void copy_from_slot_and_reply(struct IOSana2Req *ios2, volatile UBYTE *slot, UWORD length)
{
	struct EthHdr *eh = (struct EthHdr *)(slot + 2);

	if (ios2->ios2_Req.io_Flags & SANA2IOF_RAW)
	{
		ios2->ios2_DataLength = length;
		copyto(ios2->ios2_Data, eh, ios2->ios2_DataLength);
		ios2->ios2_Req.io_Flags = SANA2IOF_RAW;
	}
	else
	{
		ios2->ios2_DataLength = length - sizeof(struct EthHdr);
		copyto(ios2->ios2_Data, &eh[1], ios2->ios2_DataLength);
		ios2->ios2_Req.io_Flags = 0;
	}

	memcpy(ios2->ios2_SrcAddr, eh->eh_Src, MACADDR_SIZE);
	memcpy(ios2->ios2_DstAddr, eh->eh_Dst, MACADDR_SIZE);

	BOOL bcast = TRUE;
	for (int i = 0; i < MACADDR_SIZE; i++)
	{
		if (eh->eh_Dst[i] != 0xff)
		{
			bcast = FALSE;
			break;
		}
	}

	if (bcast)
		ios2->ios2_Req.io_Flags |= SANA2IOF_BCAST;
	else if (eh->eh_Dst[0] & 1)
		ios2->ios2_Req.io_Flags |= SANA2IOF_MCAST;

	ios2->ios2_PacketType = eh->eh_Type;

	ios2->ios2_Req.io_Error = 0;
	ReplyMsg(&ios2->ios2_Req.io_Message);

	global_stats.PacketsReceived++;
}

static struct IOSana2Req *remove_matching_rbuf(ULONG type)
{
	struct Node *node = ut_rbuf_list.lh_Head;
	while (node->ln_Succ)
	{
		struct IOSana2Req *ios2 = (struct IOSana2Req *)node;
		if (ios2->ios2_PacketType == type)
		{
			Remove(node);
			return ios2;
		}
		node = node->ln_Succ;
	}
	return NULL;
}

// Hand every frame in the ring to a waiting CMD_READ of its type (or drop it), free the slots,
// then unmask the RX interrupt (a frame that came in meanwhile raises it again at once).
static void receive_frames()
{
	UWORD head = REG(R_RX_HEAD) & (RX_SLOTS - 1);

	while (rx_tail != head)
	{
		volatile UBYTE *slot = card + RX_RING + rx_tail * RX_SLOT_SIZE;
		UWORD length = *(volatile UWORD *)slot;
		UWORD type = *(volatile UWORD *)(slot + 2 + 12);

		if (is_online && length >= sizeof(struct EthHdr))
		{
			Forbid();
			struct IOSana2Req *ios2 = remove_matching_rbuf(type);
			Permit();

			if (ios2)
				copy_from_slot_and_reply(ios2, slot, length);
			else
				global_stats.UnknownTypesReceived++;
		}

		rx_tail = (rx_tail + 1) & (RX_SLOTS - 1);
		REG(R_RX_TAIL) = rx_tail;

		if (rx_tail == head)
			head = REG(R_RX_HEAD) & (RX_SLOTS - 1);
	}

	REG(R_CTRL) = ctrl_bits;
}

// Send the next waiting CMD_WRITE if the card's TX buffer is free.
static void send_frame()
{
	if (REG(R_STATUS) & STATUS_TXBUSY)
		return;

	Forbid();
	struct IOSana2Req *ios2 = (struct IOSana2Req *)RemHead((struct List *)&ut_wbuf_list);
	Permit();

	if (!ios2)
		return;

	volatile UBYTE *buf = card + TX_BUFFER;
	ULONG length;

	if (ios2->ios2_Req.io_Flags & SANA2IOF_RAW)
	{
		copyfrom((void *)buf, ios2->ios2_Data, ios2->ios2_DataLength);
		length = ios2->ios2_DataLength;
	}
	else
	{
		// the header with word writes (the TX buffer is write-only)
		volatile UWORD *w = (volatile UWORD *)buf;
		w[0] = (ios2->ios2_DstAddr[0] << 8) | ios2->ios2_DstAddr[1];
		w[1] = (ios2->ios2_DstAddr[2] << 8) | ios2->ios2_DstAddr[3];
		w[2] = (ios2->ios2_DstAddr[4] << 8) | ios2->ios2_DstAddr[5];
		w[3] = (macaddr[0] << 8) | macaddr[1];
		w[4] = (macaddr[2] << 8) | macaddr[3];
		w[5] = (macaddr[4] << 8) | macaddr[5];
		w[6] = (UWORD)ios2->ios2_PacketType;
		copyfrom((void *)(buf + sizeof(struct EthHdr)), ios2->ios2_Data, ios2->ios2_DataLength);
		length = ios2->ios2_DataLength + sizeof(struct EthHdr);
	}

	REG(R_TX_LEN) = (UWORD)length;

	ios2->ios2_Req.io_Error = 0;
	ReplyMsg(&ios2->ios2_Req.io_Message);

	global_stats.PacketsSent++;
}

void device_process_run()
{
	ULONG sana2_signal = AllocSignal(-1);
	sana2_sigmask = 1UL << sana2_signal;

	ULONG shutdown_signal = AllocSignal(-1);
	shutdown_sigmask = 1UL << shutdown_signal;

	ULONG int_signal = AllocSignal(-1);
	ULONG int_sigmask = 1UL << int_signal;

	// frames that arrived before the device was opened are stale
	rx_tail = REG(R_RX_HEAD) & (RX_SLOTS - 1);
	REG(R_RX_TAIL) = rx_tail;
	REG(R_IRQ) = IRQ_TX;

	int_data.id_Card = card;
	int_data.id_Task = FindTask(NULL);
	int_data.id_SigMask = int_sigmask;

	card_int.is_Node.ln_Type = NT_INTERRUPT;
	card_int.is_Node.ln_Pri = 0;
	card_int.is_Node.ln_Name = (char *)device_name;
	card_int.is_Data = &int_data;
	card_int.is_Code = (void (*)())int_server;
	AddIntServer(INTB_PORTS, &card_int);

	ctrl_bits = CTRL_RX | CTRL_BCAST | CTRL_MCAST | CTRL_RXIRQ | CTRL_TXIRQ;
	REG(R_CTRL) = ctrl_bits;

	device_start_error = 0;
	Signal((struct Task *)init_task, SIGF_SINGLE);

	while (TRUE)
	{
		receive_frames();
		send_frame();

		ULONG sigs = Wait(int_sigmask | sana2_sigmask | shutdown_sigmask);

		if (sigs & shutdown_sigmask)
			break;
	}

	REG(R_CTRL) = 0;
	RemIntServer(INTB_PORTS, &card_int);

	Signal((struct Task *)init_task, SIGF_SINGLE);
}

static struct TagItem *FindTagItem(Tag tagVal, struct TagItem *tagList)
{
	struct TagItem *ti = tagList;
	while (ti && ti->ti_Tag != tagVal)
	{
		switch (ti->ti_Tag)
		{
		case TAG_DONE:
			return NULL;
		case TAG_MORE:
			ti = (struct TagItem *)ti->ti_Data;
			break;
		case TAG_SKIP:
			ti += ti->ti_Data + 1;
			break;
		case TAG_IGNORE:
		default:
			ti++;
			break;
		}
	}
	return ti;
}

static ULONG GetTagData(Tag tagVal, ULONG defaultData, struct TagItem *tagList)
{
	struct TagItem *ti = FindTagItem(tagVal, tagList);
	return ti ? ti->ti_Data : defaultData;
}

static BOOL find_card()
{
	struct Library *ExpansionBase = OpenLibrary((char *)expansion_name, 0);
	if (!ExpansionBase)
		return FALSE;

	struct ConfigDev *cd = FindConfigDev(NULL, CARD_MANUFACTURER, CARD_PRODUCT);
	CloseLibrary(ExpansionBase);

	if (!cd)
		return FALSE;

	card = (volatile UBYTE *)cd->cd_BoardAddr;
	if (REG(R_ID) != CARD_ID)
		return FALSE;

	for (int i = 0; i < MACADDR_SIZE; i += 2)
	{
		UWORD w = REG(R_MAC + i);
		macaddr[i] = w >> 8;
		macaddr[i + 1] = w & 0xff;
	}
	return TRUE;
}

static void open(__reg("a6") struct Library *dev, __reg("a1") struct IOSana2Req *ios2, __reg("d0") ULONG unitnum, __reg("d1") ULONG flags)
{
	ios2->ios2_Req.io_Error = IOERR_OPENFAIL;
	ios2->ios2_Req.io_Message.mn_Node.ln_Type = NT_REPLYMSG;

	if (unitnum != 0 || dev->lib_OpenCnt)
		return;

	if (!find_card())
		return;

	dev->lib_OpenCnt++;

	copyfrom = (buf_copy_func_t)GetTagData(S2_CopyFromBuff, 0, (struct TagItem *)ios2->ios2_BufferManagement);
	copyto = (buf_copy_func_t)GetTagData(S2_CopyToBuff, 0, (struct TagItem *)ios2->ios2_BufferManagement);
	ios2->ios2_BufferManagement = (void *)0xdeadbeefUL;

	memset(&global_stats, 0, sizeof(global_stats));
	is_online = TRUE;

	NewList((struct List *)&ut_rbuf_list);
	NewList((struct List *)&ut_wbuf_list);

	init_task = FindTask(NULL);
	device_start_error = -1;

	struct MsgPort *device_mp = CreateProc((char *)device_name, TASK_PRIO, ((ULONG)device_process_seglist) >> 2, 2048);
	if (!device_mp)
		goto error;

	device_process = (struct Process *)((char *)device_mp - sizeof(struct Task));

	Wait(SIGF_SINGLE);

	if (device_start_error)
		goto error;

	ios2->ios2_Req.io_Error = 0;
	return;

error:
	dev->lib_OpenCnt--;
}

static void abort_all(volatile struct List *list)
{
	struct IOSana2Req *ios2;
	while ((ios2 = (struct IOSana2Req *)RemHead((struct List *)list)))
	{
		ios2->ios2_Req.io_Error = IOERR_ABORTED;
		ios2->ios2_WireError = 0;
		ReplyMsg(&ios2->ios2_Req.io_Message);
	}
}

static BPTR close(__reg("a6") struct Library *dev, __reg("a1") struct IOSana2Req *ios2)
{
	init_task = FindTask(NULL);
	Signal(&device_process->pr_Task, shutdown_sigmask);
	Wait(SIGF_SINGLE);

	Forbid();
	abort_all(&ut_rbuf_list);
	abort_all(&ut_wbuf_list);
	Permit();

	ios2->ios2_Req.io_Device = NULL;
	ios2->ios2_Req.io_Unit = NULL;

	dev->lib_OpenCnt--;

	if (dev->lib_OpenCnt == 0 && (dev->lib_Flags & LIBF_DELEXP))
		return expunge(dev);

	return 0;
}

static void device_query(struct IOSana2Req *req)
{
	struct Sana2DeviceQuery *query;

	query = req->ios2_StatData;
	query->DevQueryFormat = 0;
	query->DeviceLevel = 0;

	if (query->SizeAvailable >= 18)
		query->AddrFieldSize = MACADDR_SIZE * 8;

	if (query->SizeAvailable >= 22)
		query->MTU = ETH_MTU;

	if (query->SizeAvailable >= 26)
		query->BPS = NIC_BPS;

	if (query->SizeAvailable >= 30)
		query->HardwareType = S2WireType_Ethernet;

	query->SizeSupplied = query->SizeAvailable < 30 ? query->SizeAvailable : 30;
}

static void set_last_start()
{
	struct IORequest req;
	memset(&req, 0, sizeof(req));
	req.io_Message.mn_Length = sizeof(req);

	if (OpenDevice(TIMERNAME, UNIT_MICROHZ, &req, 0) == 0)
	{
		struct Device *TimerBase = req.io_Device;
		GetSysTime(&global_stats.LastStart);
		CloseDevice(&req);
	}
}

static void get_global_stats(struct Sana2DeviceStats *stats)
{
	global_stats.Overruns = REG(R_RX_DROPPED);
	global_stats.BadData = REG(R_RX_CRCERR);
	memcpy(stats, &global_stats, sizeof(struct Sana2DeviceStats));
}

static void begin_io(__reg("a6") struct Library *dev, __reg("a1") struct IOSana2Req *ios2)
{
	ios2->ios2_Req.io_Error = S2ERR_NO_ERROR;
	ios2->ios2_WireError = S2WERR_GENERIC_ERROR;

	switch (ios2->ios2_Req.io_Command)
	{
	case CMD_READ:
		if (!ios2->ios2_BufferManagement)
		{
			ios2->ios2_Req.io_Error = S2ERR_BAD_ARGUMENT;
			ios2->ios2_WireError = S2WERR_BUFF_ERROR;
			break;
		}

		Forbid();
		AddTail((struct List *)&ut_rbuf_list, &ios2->ios2_Req.io_Message.mn_Node);
		Permit();

		ios2->ios2_Req.io_Flags &= ~SANA2IOF_QUICK;
		ios2 = NULL;

		Signal(&device_process->pr_Task, sana2_sigmask);
		break;

	case S2_BROADCAST:
		memset(ios2->ios2_DstAddr, 0xff, MACADDR_SIZE);
		/* Fall through */

	case CMD_WRITE:
		if (((ios2->ios2_Req.io_Flags & SANA2IOF_RAW) != 0 && ios2->ios2_DataLength > RAW_MTU) ||
			((ios2->ios2_Req.io_Flags & SANA2IOF_RAW) == 0 && ios2->ios2_DataLength > ETH_MTU))
		{
			ios2->ios2_Req.io_Error = S2ERR_MTU_EXCEEDED;
			break;
		}

		if (!ios2->ios2_BufferManagement)
		{
			ios2->ios2_Req.io_Error = S2ERR_BAD_ARGUMENT;
			ios2->ios2_WireError = S2WERR_BUFF_ERROR;
			break;
		}

		Forbid();
		AddTail((struct List *)&ut_wbuf_list, &ios2->ios2_Req.io_Message.mn_Node);
		Permit();

		ios2->ios2_Req.io_Flags &= ~SANA2IOF_QUICK;
		ios2 = NULL;

		Signal(&device_process->pr_Task, sana2_sigmask);
		break;

	case S2_CONFIGINTERFACE:
		// the stack may set its own station address
		for (int i = 0; i < MACADDR_SIZE; i += 2)
			REG(R_MAC + i) = (ios2->ios2_SrcAddr[i] << 8) | ios2->ios2_SrcAddr[i + 1];
		memcpy(macaddr, ios2->ios2_SrcAddr, MACADDR_SIZE);
		/* Fall through */

	case S2_ONLINE:
		set_last_start();
		is_online = TRUE;
		break;

	case S2_OFFLINE:
		is_online = FALSE;
		break;

	case S2_GETSTATIONADDRESS:
		memcpy(ios2->ios2_SrcAddr, macaddr, sizeof(macaddr));
		memcpy(ios2->ios2_DstAddr, macaddr, sizeof(macaddr));
		break;

	case S2_DEVICEQUERY:
		device_query(ios2);
		break;

	case S2_ONEVENT:
	case S2_TRACKTYPE:
	case S2_UNTRACKTYPE:
	case S2_GETTYPESTATS:
	case S2_READORPHAN:
	case S2_GETSPECIALSTATS:
	case S2_ADDMULTICASTADDRESS:
	case S2_DELMULTICASTADDRESS:
		break;

	case S2_GETGLOBALSTATS:
		if (ios2->ios2_StatData)
			get_global_stats(ios2->ios2_StatData);
		break;

	default:
		ios2->ios2_Req.io_Error = IOERR_NOCMD;
		ios2->ios2_WireError = S2WERR_GENERIC_ERROR;
		break;
	}

	if (ios2)
	{
		if (ios2->ios2_Req.io_Flags & SANA2IOF_QUICK)
			ios2->ios2_Req.io_Message.mn_Node.ln_Type = NT_MESSAGE;
		else
			ReplyMsg(&ios2->ios2_Req.io_Message);
	}
}

static void remove_from_list(struct List *list, struct Node *node)
{
	for (struct Node *n = list->lh_Head; n->ln_Succ; n = n->ln_Succ)
	{
		if (n == node)
		{
			Remove(n);
			return;
		}
	}
}

static ULONG abort_io(__reg("a6") struct Library *dev, __reg("a1") struct IOSana2Req *ios2)
{
	Forbid();
	remove_from_list((struct List *)&ut_rbuf_list, &ios2->ios2_Req.io_Message.mn_Node);
	remove_from_list((struct List *)&ut_wbuf_list, &ios2->ios2_Req.io_Message.mn_Node);
	Permit();

	ios2->ios2_Req.io_Error = IOERR_ABORTED;
	ios2->ios2_WireError = 0;
	ReplyMsg(&ios2->ios2_Req.io_Message);

	return 0;
}

static ULONG device_vectors[] =
{
	(ULONG)open,
	(ULONG)close,
	(ULONG)expunge,
	0,
	(ULONG)begin_io,
	(ULONG)abort_io,
	-1,
};

ULONG auto_init_tables[] =
{
	sizeof(struct Library),
	(ULONG)device_vectors,
	0,
	(ULONG)init_device,
};
