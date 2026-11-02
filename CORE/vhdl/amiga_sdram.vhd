---------------------------------------------------------------------------------------------------------
-- Megamiga (Amiga for MEGA65, fork of AExp)
--
-- amiga_sdram: the Amiga memory in the board SDRAM (MEGA65 R4/R5/R6)
--
-- Chip RAM (up to 2 MB), Slow RAM, the Kickstart (up to 512 KB) and the 8 MB Zorro II Fast RAM
-- all live in the IS42S16320F SDRAM, served by Minimig's own SDRAM controller (sdram_ctrl.v, as
-- on MiSTer): 113.5 MHz, 16 states per 7 MHz bus cycle (re-synchronised to c_7m), one access per
-- 7 MHz cycle - the chipset port first, then a CPU write, a CPU read (cache fill), or a refresh.
-- The SDRAM clock is a register output (56.75 MHz), so commands, clock and data leave the FPGA
-- through matched IOB flip-flops.
--
-- SDRAM layout (16-bit words; sdram_ctrl maps address bits 24:23 to the bank):
--   bank 0, bytes 0 .. 8 MB   the banked "SRAM" address of minimig_sram_bridge.v unchanged:
--                             chip $000000.., slow $400000.., kick $780000 (512 KB)
--   bank 1, bytes 8 .. 16 MB  the 8 MB Zorro II Fast RAM ($200000-$9FFFFF; cpu_wrapper maps
--                             it 1:1 onto ramaddr[22:1], $800000-$9FFFFF wraps onto the first
--                             2 MB), out of the way of the chipset banks
--   banks 2/3                 the 16 MB Zorro III Fast RAM
--   columns 512..1023         (Megamiga 0.7) the 32 MB Zorro III Fast RAM: the upper halves of
--                             the rows of all four banks, word address bit 25 = column bit 9.
--                             Bank 0's half was the floppy area (ADF pools, lide.rom) until
--                             floppy-direct moved those to the SD card and to block RAM; the
--                             floppy port below is still here but tied off by mega65.vhd, and
--                             sdram_ctrl no longer serves it.
--   (before 0.7: bank 0, columns 512..1023 the floppy area: the three ADF image pools and
--   lide.rom, formerly in HyperRAM; the Amiga ports only reached columns 0..511.)
--
-- Floppy port: an Avalon-MM slave on the core clock for the ADF mount wrappers, the ADF
-- track engine and the IDE board's ROM (behind the arbiters in mega65.vhd). Every word is one
-- request to the controller's floppy port (toggle handshake; the controller runs on the 4x
-- clock of the same MMCM, so both directions are ordinary synchronous paths). Bursts are
-- split into single words. The controller gives the port at most every second slot while
-- the CPU waits, so the Amiga barely notices it.
--
-- Maintenance writer: while it has work it owns the chipset port of the controller (the Amiga
-- is in reset then: at startup, and during a cold boot):
--   * Kickstart loading: the QNICE Shell streams the ROM file byte by byte into this device
--     (C_DEV_AMIGA_KICK, byte address = file offset, the even byte is the high byte). Pairs
--     of bytes cross to the core clock through a FIFO and are written to the kick bank. A word
--     of the first 256 KB is also written to the second 256 KB, so a 256 KB Kickstart (1.x) is
--     mirrored like on real hardware; a 512 KB Kickstart then overwrites the mirror.
--     Megamiga 0.7: a 1 MB Kickstart (AROS; qnice_kick_1mb_i, the file size in the CSR) puts
--     its first 512 KB where minimig_sram_bridge.v reads $E00000-$E7FFFF (A22..A19 = 1100,
--     gary's sel_kick1mb), the second 512 KB into the kick bank. The mirror works per half
--     (later words overwrite it). Before the first word of a smaller Kickstart the $E00000
--     half is cleared, so that no AROS extension is left there for Kickstart 3.x to find.
--   * Cold-boot scrub (amiga_cold_boot.vhd): zero words in chip RAM at scrub_addr_i while
--     scrub_i is high (the SysBase pointer at $4, so that Kickstart cold-starts).
-- Every word is presented for 8 core clocks (= 2 controller slots) followed by 8 idle clocks,
-- so the controller sees it in at least one slot and still finds idle slots for refreshes.
--
-- Done in 2026 (Megamiga, fork of AExp) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

library work;
use work.globals.all;

entity amiga_sdram is
   port (
      clk_i          : in    std_logic;                      -- core clock (28.375 MHz)
      clk4x_i        : in    std_logic;                      -- 113.5 MHz, from the same MMCM
      rst_i          : in    std_logic;                      -- clock-generator reset only
      c7m_i          : in    std_logic;                      -- amiga_clk c1 (7 MHz phase)

      -- chipset port: minimig_sram_bridge.v (core clock)
      ram_addr_i     : in    std_logic_vector(22 downto 1);  -- banked word address
      ram_data_i     : in    std_logic_vector(15 downto 0);  -- write data
      ram_data_o     : out   std_logic_vector(15 downto 0);  -- read data
      chip48_o       : out   std_logic_vector(47 downto 0);  -- AGA wide read (fetch modes)
      ram_bhe_n_i    : in    std_logic;
      ram_ble_n_i    : in    std_logic;
      ram_we_n_i     : in    std_logic;
      ram_oe_n_i     : in    std_logic;

      -- CPU Fast RAM port: cpu_wrapper.v "ram*" (core clock)
      fram_sel_i     : in    std_logic;
      fram_state_i   : in    std_logic_vector(1 downto 0);   -- cpustate (3 = write)
      --fram_addr_i    : in    std_logic_vector(24 downto 1);   -- SDRAM word address (bank 24:23)
      fram_addr_i    : in    std_logic_vector(25 downto 1);   -- SDRAM word address (bank 24:23, 25 = column bit 9)
      cpu_020_i      : in    std_logic;                      -- '1' = TG68K (core clock, static)
      fram_uds_n_i   : in    std_logic;
      fram_lds_n_i   : in    std_logic;
      fram_data_i    : in    std_logic_vector(15 downto 0);
      fram_data_o    : out   std_logic_vector(15 downto 0);
      fram_ready_o   : out   std_logic;
      cpu_reset_n_i  : in    std_logic;                      -- clears the CPU read cache
      cpu_cacr_i     : in    std_logic_vector(3 downto 0);

      -- 68040 Fast RAM port (cpu040 branch): 32-bit accesses and 16-byte line reads straight
      -- into the controller, toggle handshake on the core clock (see sdram_ctrl.v); fp_addr_i
      -- is the SDRAM long address (bank 24:23, like fram_addr_i)
      fp_req_i       : in    std_logic := '0';
      fp_we_i        : in    std_logic := '0';
      fp_line_i      : in    std_logic := '0';
      fp_addr_i      : in    std_logic_vector(25 downto 2) := (others => '0');
      fp_be_i        : in    std_logic_vector(3 downto 0) := (others => '0');
      fp_data_i      : in    std_logic_vector(31 downto 0) := (others => '0');
      fp_data_o      : out   std_logic_vector(127 downto 0);
      fp_ack_o       : out   std_logic;
      -- Megamiga 0.7: the IDE board's DMA, a second client of the same slots and protocol
      -- (sdram_ctrl.v dm*; read data in fp_data_o, the line of the last read slot of either)
      dm_req_i       : in    std_logic := '0';
      dm_we_i        : in    std_logic := '0';
      dm_line_i      : in    std_logic := '0';
      dm_addr_i      : in    std_logic_vector(25 downto 2) := (others => '0');
      dm_be_i        : in    std_logic_vector(3 downto 0) := (others => '0');
      dm_data_i      : in    std_logic_vector(31 downto 0) := (others => '0');
      dm_ack_o       : out   std_logic;

      -- cold-boot scrub (amiga_cold_boot.vhd, core clock)
      scrub_i        : in    std_logic;
      scrub_addr_i   : in    std_logic_vector(17 downto 0);  -- chip RAM word address

      -- Kickstart loader: QNICE device (QNICE clock)
      qnice_clk_i    : in    std_logic;
      qnice_rst_i    : in    std_logic;
      qnice_addr_i   : in    std_logic_vector(27 downto 0);  -- byte address = file offset
      qnice_data_i   : in    std_logic_vector(15 downto 0);
      qnice_ce_i     : in    std_logic;
      qnice_we_i     : in    std_logic;
      qnice_wait_o   : out   std_logic;
      qnice_kick_1mb_i : in  std_logic := '0';               -- Megamiga 0.7: a 1 MB Kickstart
      kick_busy_o    : out   std_logic;                      -- core clock: words still in flight
      -- Megamiga (ntsc): while pause_i is high the maintenance writer (scrub, Kickstart, AR3 ROM,
      -- $E00000 clear, cartridge init) starts no new write; maint_idle_o says the last one is
      -- done. amiga_cold_boot.vhd switches the core clock between PAL and NTSC only then.
      pause_i        : in    std_logic := '0';
      maint_idle_o   : out   std_logic;
      -- Megamiga: the Action Replay III ROM loader, the same byte stream into the AR3 bank
      -- (QNICE device C_DEV_AMIGA_AR3, byte address = file offset 0..256 KB - 1; mega65.vhd
      -- passes only window 0..63)
      qnice_ar3_ce_i : in    std_logic := '0';

      -- Megamiga: cartridge init, once per cold boot (amiga_cold_boot.vhd, core clock):
      -- cart_type_i "01" HRTmon: copy the built-in HRTmon image to $A10000 (cartridge bank
      -- $200000, word $8000) with its configuration block patched like MiSTer's
      -- UploadActionReplay does (AGA flag, chip RAM size); "10" Action Replay III: clear its
      -- RAM half ($440000-$47FFFF = AR3 bank $2C0000); "00": nothing. cart_busy_o is high
      -- from the cart_init_i clock on until the last word is written.
      cart_init_i    : in    std_logic := '0';
      cart_type_i    : in    std_logic_vector(1 downto 0) := "00";
      cart_aga_i     : in    std_logic := '0';
      cart_chip_i    : in    std_logic_vector(1 downto 0) := "00";  -- "00" 512 KB, "01" 1 MB, "11" 2 MB
      cart_busy_o    : out   std_logic;

      -- floppy port: ADF pools + IDE boot ROM (core clock, word address 21:0)
      flp_rst_i             : in  std_logic;
      flp_avm_write_i       : in  std_logic;
      flp_avm_read_i        : in  std_logic;
      flp_avm_address_i     : in  std_logic_vector(31 downto 0);
      flp_avm_writedata_i   : in  std_logic_vector(15 downto 0);
      flp_avm_byteenable_i  : in  std_logic_vector( 1 downto 0);
      flp_avm_burstcount_i  : in  std_logic_vector( 7 downto 0);
      flp_avm_readdata_o    : out std_logic_vector(15 downto 0);
      flp_avm_readdatavalid_o : out std_logic;
      flp_avm_waitrequest_o : out std_logic;

      -- SDRAM pins
      sdram_clk_o    : out   std_logic;
      sdram_cke_o    : out   std_logic;
      sdram_ras_n_o  : out   std_logic;
      sdram_cas_n_o  : out   std_logic;
      sdram_we_n_o   : out   std_logic;
      sdram_cs_n_o   : out   std_logic;
      sdram_ba_o     : out   std_logic_vector(1 downto 0);
      sdram_a_o      : out   std_logic_vector(12 downto 0);
      sdram_dqml_o   : out   std_logic;
      sdram_dqmh_o   : out   std_logic;
      sdram_dq_io    : inout std_logic_vector(15 downto 0)
   );
end entity amiga_sdram;

architecture synthesis of amiga_sdram is

   component sdram_ctrl is
      port (
         sysclk         : in    std_logic;
         c_7m           : in    std_logic;
         reset_n        : in    std_logic;
         cache_rst      : in    std_logic;
         cache_inhibit  : in    std_logic;
         cpu_cache_ctrl : in    std_logic_vector(3 downto 0);
         sd_addr        : out   std_logic_vector(12 downto 0);
         sd_ba          : out   std_logic_vector(1 downto 0);
         sd_cs          : out   std_logic;
         sd_we          : out   std_logic;
         sd_ras         : out   std_logic;
         sd_cas         : out   std_logic;
         sd_dqm         : out   std_logic_vector(1 downto 0);
         sd_data        : inout std_logic_vector(15 downto 0);
         sd_clk         : out   std_logic;
         sd_cke         : out   std_logic;
         chipAddr       : in    std_logic_vector(24 downto 1);
         chipL          : in    std_logic;
         chipU          : in    std_logic;
         chipRW         : in    std_logic;
         chipDMA        : in    std_logic;
         chipWR         : in    std_logic_vector(15 downto 0);
         chipRD         : out   std_logic_vector(15 downto 0);
         chip48         : out   std_logic_vector(47 downto 0);
         cpuAddr        : in    std_logic_vector(25 downto 1);
         cpuCS          : in    std_logic;
         cpustate       : in    std_logic_vector(1 downto 0);
         cpuL           : in    std_logic;
         cpuU           : in    std_logic;
         cpuWR          : in    std_logic_vector(15 downto 0);
         cpuRD          : out   std_logic_vector(15 downto 0);
         ramready       : out   std_logic;
         flpReq         : in    std_logic;
         flpAddr        : in    std_logic_vector(22 downto 1);
         flpWE          : in    std_logic;
         flpL           : in    std_logic;
         flpU           : in    std_logic;
         flpWR          : in    std_logic_vector(15 downto 0);
         flpRD          : out   std_logic_vector(15 downto 0);
         flpAck         : out   std_logic;
         fpReq          : in    std_logic;
         fpWE           : in    std_logic;
         fpLine         : in    std_logic;
         fpAddr         : in    std_logic_vector(25 downto 2);
         fpBE           : in    std_logic_vector(3 downto 0);
         fpWR           : in    std_logic_vector(31 downto 0);
         fpRD           : out   std_logic_vector(127 downto 0);
         fpAck          : out   std_logic;
         dmReq          : in    std_logic;
         dmWE           : in    std_logic;
         dmLine         : in    std_logic;
         dmAddr         : in    std_logic_vector(25 downto 2);
         dmBE           : in    std_logic_vector(3 downto 0);
         dmWR           : in    std_logic_vector(31 downto 0);
         dmAck          : out   std_logic
      );
   end component sdram_ctrl;

   constant C_KICK_BANK : std_logic_vector(3 downto 0) := "1111";   -- minimig_sram_bridge.v
   constant C_E0_BANK   : std_logic_vector(3 downto 0) := "1100";   -- $E00000 (1 MB Kickstart)
   constant C_HOLD      : natural := 8;                              -- core clocks per phase

   -- Megamiga: the cartridge banks of the 8 MB chipset space (A22..A19, see minimig.v):
   -- HRTmon $200000-$27FFFF (where $A00000 lands), Action Replay III $280000-$2FFFFF
   constant C_HRT_BANK  : std_logic_vector(3 downto 0) := "0100";
   constant C_AR3_BANK  : std_logic_vector(3 downto 0) := "0101";
   constant C_HRT_START : natural := 16#8000#;                       -- word of $A10000 in its bank
   constant C_AR3_RAM_WORDS : natural := 131072;                      -- $440000-$47FFFF

   -- HRTmon's configuration block (WinUAE's HRTCFG at the start of the image), patched like
   -- MiSTer's Main_MiSTer support/minimig/minimig_config.cpp UploadActionReplay does:
   --   offset 20: mon_size = $00800000
   --   24: col0h $00, col0l $5A, col1h $0F, col1l $FF, right $FF, keyboard $00, key $FF,
   --       ide $00 (MiSTer: Gayle IDE on; Megamiga has no Gayle), a1200 $FF, aga, insert $FF,
   --       delay $0F, lview $FF, cd32 $00, screenmode $00 (PAL), novbr $FF, entered $00,
   --       hexmode $01
   --   68: max_chip = chip RAM size in bytes
   -- i is the word index in the image; every other word is passed through.
   function hrt_patch(i : natural; d : std_logic_vector(15 downto 0); aga : std_logic;
                      chip : std_logic_vector(1 downto 0)) return std_logic_vector is
   begin
      case i is
         when 10     => return x"0080";
         when 11     => return x"0000";
         when 12     => return x"005A";
         when 13     => return x"0FFF";
         when 14     => return x"FF00";
         when 15     => return x"FF00";
         when 16     => if aga = '1' then return x"FFFF"; else return x"FF00"; end if;
         when 17     => return x"FF0F";
         when 18     => return x"FF00";
         when 19     => return x"00FF";
         when 20     => return x"0001";
         when 34     => if chip = "00" then return x"0008";      -- 512 KB
                        elsif chip = "01" then return x"0010";   -- 1 MB
                        else return x"0020";                     -- 2 MB
                        end if;
         when 35     => return x"0000";
         when others => return d;
      end case;
   end function hrt_patch;

   -- chipset port of the controller (after the maintenance mux)
   signal c_addr    : std_logic_vector(24 downto 1);
   signal c_data    : std_logic_vector(15 downto 0);
   signal c_u, c_l  : std_logic;
   signal c_rw      : std_logic;
   signal c_dma     : std_logic;

   -- maintenance writer (core clock)
   type t_mstate is (M_IDLE, M_WRITE, M_GAP);
   signal m_state   : t_mstate := M_IDLE;
   signal m_cnt     : natural range 0 to C_HOLD - 1 := 0;
   signal m_active  : std_logic := '0';                        -- owns the chipset port
   signal m_addr    : std_logic_vector(22 downto 1) := (others => '0');
   signal m_data    : std_logic_vector(15 downto 0) := (others => '0');
   signal m_mirror  : std_logic := '0';                        -- second write pending
   signal m_scrub   : std_logic := '0';                        -- current write is a scrub
   -- Megamiga 0.7: clearing the $E00000 half before a 256/512 KB Kickstart
   signal e_run     : std_logic := '0';                        -- clearing
   signal e_done    : std_logic := '0';                        -- cleared for this load
   signal e_idx     : unsigned(17 downto 0) := (others => '0');
   signal f_head_clr : std_logic;                              -- FIFO head: word 0, clear first

   -- Kickstart loader FIFO: {AR3, E0, CLR, word address 17:0, data 15:0} (Megamiga: + the AR3
   -- tag; 0.7: E0 = the word goes to the $E00000 half, CLR = a 256/512 KB Kickstart, whose
   -- word 0 waits until the $E00000 half is cleared)
   signal q_hi      : std_logic_vector(7 downto 0) := (others => '0');
   signal q_wr_en   : std_logic := '0';
   signal q_din     : std_logic_vector(36 downto 0) := (others => '0');
   signal q_full    : std_logic;
   signal q_wr_rst_busy : std_logic;
   signal f_rd_en   : std_logic;
   signal f_dout    : std_logic_vector(36 downto 0);

   -- Megamiga: cartridge init (core clock)
   signal c_run     : std_logic := '0';                        -- words left to write
   signal c_tail    : std_logic := '0';                        -- last word still being written
   signal c_hrt     : std_logic := '0';                        -- '1' HRTmon copy, '0' AR3 clear
   signal c_prime   : std_logic := '0';                        -- rom_q shows word c_idx
   signal c_idx     : unsigned(16 downto 0) := (others => '0');
   signal c_aga     : std_logic := '0';
   signal c_chip    : std_logic_vector(1 downto 0) := "00";
   signal rom_q     : std_logic_vector(15 downto 0);
   type t_rom_q is array (0 to 3) of std_logic_vector(15 downto 0);
   signal rom_qs    : t_rom_q;                                 -- the four HRTmon ROM parts
   signal f_empty   : std_logic;
   signal f_rd_rst_busy : std_logic;

   signal reset_n   : std_logic;

   -- CPU port chip select (clk4x): MiSTer's Minimig.sv ram_cs. For the 68020 the select
   -- drops for one fast clock after ready at the fast clock that coincides with the core
   -- clock edge (cyc), where TG68K takes the clock enable - so the cache sees the end of
   -- every access although TG68K has no AS. The 68000 holds AS; cs = sel.
   signal fram_ready : std_logic;
   signal ram_cs     : std_logic := '0';
   signal cyc        : std_logic := '0';
   signal div        : unsigned(3 downto 0) := (others => '0');
   signal c7m_d      : std_logic := '0';

   -- floppy port (core clock): one controller request per word
   type t_fstate is (F_IDLE, F_WAIT, F_WNEXT, F_DRAIN);
   signal f_state    : t_fstate := F_IDLE;
   signal f_req      : std_logic := '0';                         -- request toggle
   signal f_ack      : std_logic;                                -- controller's toggle (4x clock)
   signal f_rd       : std_logic_vector(15 downto 0);            -- controller read data (4x clock)
   signal f_addr     : unsigned(21 downto 0) := (others => '0');
   signal f_cnt      : unsigned(7 downto 0) := (others => '0');  -- words left in the burst
   signal f_we       : std_logic := '0';
   signal f_data     : std_logic_vector(15 downto 0) := (others => '0');
   signal f_be       : std_logic_vector(1 downto 0) := "11";

begin

   reset_n <= not rst_i;

   ---------------------------------------------------------------------------------------
   -- Kickstart loader, QNICE side: pair the bytes, push the words. The QNICE writes device
   -- registers on the falling clock edge (M2M convention); the FIFO push happens on the
   -- following rising edge. The Shell reads one byte from the SD card per write, so the FIFO
   -- (drained at one word per 16 core clocks) never fills; qnice_wait_o covers it anyway.
   ---------------------------------------------------------------------------------------

   qnice_wait_o <= q_full or q_wr_rst_busy;

   -- Kickstart words still in flight (core clock): the FIFO is not empty or the writer has
   -- not finished the last word (or its mirror). amiga_cold_boot keeps the Amiga in reset
   -- while this is high after a Kickstart load from the OSM.
   kick_busy_o <= '1' when f_empty = '0' or m_state /= M_IDLE or m_mirror = '1' or
                           e_run = '1' else '0';

   p_qnice_bytes : process (qnice_clk_i)
   begin
      if falling_edge(qnice_clk_i) then
         q_wr_en <= '0';
         if (qnice_ce_i = '1' or qnice_ar3_ce_i = '1') and qnice_we_i = '1' and
            q_full = '0' and q_wr_rst_busy = '0' then
            if qnice_addr_i(0) = '0' then
               q_hi <= qnice_data_i(7 downto 0);                       -- even byte: high byte
            elsif qnice_ar3_ce_i = '1' then                            -- Megamiga: AR3 ROM word
               q_din   <= '1' & "00" & '0' & qnice_addr_i(17 downto 1) & q_hi &
                          qnice_data_i(7 downto 0);
               q_wr_en <= '1';
            else                                                       -- Kickstart word
               q_din   <= '0' & (qnice_kick_1mb_i and not qnice_addr_i(19)) &
                          (not qnice_kick_1mb_i) & qnice_addr_i(18 downto 1) & q_hi &
                          qnice_data_i(7 downto 0);
               q_wr_en <= '1';
            end if;
         end if;
      end if;
   end process p_qnice_bytes;

   i_kick_fifo : xpm_fifo_async
      generic map (
         FIFO_MEMORY_TYPE    => "distributed",
         FIFO_WRITE_DEPTH    => 16,
         WRITE_DATA_WIDTH    => 37,
         READ_DATA_WIDTH     => 37,
         READ_MODE           => "fwft",
         FIFO_READ_LATENCY   => 0,
         CDC_SYNC_STAGES     => 2,
         RELATED_CLOCKS      => 0,
         USE_ADV_FEATURES    => "0000",
         WAKEUP_TIME         => 0
      )
      port map (
         sleep         => '0',
         rst           => qnice_rst_i,
         wr_clk        => qnice_clk_i,
         wr_en         => q_wr_en,
         din           => q_din,
         full          => q_full,
         wr_rst_busy   => q_wr_rst_busy,
         rd_clk        => clk_i,
         rd_en         => f_rd_en,
         dout          => f_dout,
         empty         => f_empty,
         rd_rst_busy   => f_rd_rst_busy,
         injectsbiterr => '0',
         injectdbiterr => '0'
      ); -- i_kick_fifo

   ---------------------------------------------------------------------------------------
   -- Maintenance writer (core clock): scrub words first, then Kickstart words
   ---------------------------------------------------------------------------------------

   f_head_clr <= '1' when f_dout(36) = '0' and f_dout(34) = '1' and
                          unsigned(f_dout(33 downto 16)) = 0 else '0';
   f_rd_en <= '1' when m_state = M_IDLE and pause_i = '0' and scrub_i = '0' and f_empty = '0' and
                       f_rd_rst_busy = '0' and m_mirror = '0' and e_run = '0' and
                       (f_head_clr = '0' or e_done = '1') else '0';

   p_maint : process (clk_i)
   begin
      if rising_edge(clk_i) then
         -- Megamiga: cartridge init. rom_q follows c_idx one clock later, so a word is
         -- taken only after one clock with an unchanged c_idx (c_prime). Every clock that
         -- does not take a word primes (the M_IDLE branch that takes one clears it again);
         -- priming only outside M_IDLE never started the first word.
         if c_run = '1' then
            c_prime <= '1';
         end if;

         case m_state is
            when M_IDLE =>
               m_active <= '0';
               if pause_i = '1' then                                 -- Megamiga (ntsc): the
                  null;                                              -- clock switch
               elsif scrub_i = '1' then                              -- cold-boot scrub
                  m_addr   <= "0000" & scrub_addr_i;
                  m_data   <= (others => '0');
                  m_scrub  <= '1';
                  m_active <= '1';
                  m_cnt    <= C_HOLD - 1;
                  m_state  <= M_WRITE;
               elsif m_mirror = '1' then                             -- upper 256 KB copy
                  m_addr(18) <= '1';
                  m_mirror   <= '0';
                  m_scrub    <= '0';
                  m_active   <= '1';
                  m_cnt      <= C_HOLD - 1;
                  m_state    <= M_WRITE;
               elsif e_run = '1' then                                -- 0.7: clear $E00000
                  m_addr   <= C_E0_BANK & std_logic_vector(e_idx);
                  m_data   <= (others => '0');
                  m_scrub  <= '0';
                  m_active <= '1';
                  m_cnt    <= C_HOLD - 1;
                  m_state  <= M_WRITE;
                  e_idx    <= e_idx + 1;
                  if e_idx = 2**18 - 1 then
                     e_run  <= '0';
                     e_done <= '1';
                  end if;
               elsif f_empty = '0' and f_rd_rst_busy = '0' and f_head_clr = '1' and
                     e_done = '0' then                               -- word 0 of a 256/512 KB
                  e_run <= '1';                                      -- Kickstart: clear first
                  e_idx <= (others => '0');
               elsif f_rd_en = '1' and f_dout(36) = '1' then         -- Megamiga: AR3 ROM word
                  m_addr   <= C_AR3_BANK & f_dout(33 downto 16);     -- (bit 33 = '0': the ROM half)
                  m_data   <= f_dout(15 downto 0);
                  m_scrub  <= '0';
                  m_active <= '1';
                  m_cnt    <= C_HOLD - 1;
                  m_state  <= M_WRITE;
               elsif f_rd_en = '1' then                              -- next Kickstart word
                  if f_dout(35) = '1' then                           -- 0.7: 1 MB, first half
                     m_addr <= C_E0_BANK & f_dout(33 downto 16);
                  else
                     m_addr <= C_KICK_BANK & f_dout(33 downto 16);
                  end if;
                  if unsigned(f_dout(33 downto 16)) /= 0 then        -- the next word 0 is
                     e_done <= '0';                                  -- another load
                  end if;
                  m_data   <= f_dout(15 downto 0);
                  m_mirror <= not f_dout(33);                        -- word in the first 256 KB
                  m_scrub  <= '0';
                  m_active <= '1';
                  m_cnt    <= C_HOLD - 1;
                  m_state  <= M_WRITE;
               elsif c_run = '1' and c_prime = '1' then              -- Megamiga: cartridge init
                  if c_hrt = '1' then
                     m_addr <= C_HRT_BANK & std_logic_vector(to_unsigned(C_HRT_START, 18) + c_idx);
                     m_data <= hrt_patch(to_integer(c_idx), rom_q, c_aga, c_chip);
                  else
                     m_addr <= C_AR3_BANK & '1' & std_logic_vector(c_idx);
                     m_data <= (others => '0');
                  end if;
                  if (c_hrt = '1' and c_idx = C_HRTMON_WORDS - 1) or
                     (c_hrt = '0' and c_idx = C_AR3_RAM_WORDS - 1) then
                     c_run  <= '0';
                     c_tail <= '1';
                  end if;
                  c_idx    <= c_idx + 1;
                  c_prime  <= '0';
                  m_scrub  <= '0';
                  m_active <= '1';
                  m_cnt    <= C_HOLD - 1;
                  m_state  <= M_WRITE;
               end if;

            when M_WRITE =>
               if m_cnt = 0 then
                  m_active <= '0';
                  m_cnt    <= C_HOLD - 1;
                  m_state  <= M_GAP;
               else
                  m_cnt <= m_cnt - 1;
               end if;

            when M_GAP =>                                            -- idle slots: refresh
               if m_cnt = 0 then
                  c_tail  <= '0';                                    -- Megamiga: write done
                  m_state <= M_IDLE;
               else
                  m_cnt <= m_cnt - 1;
               end if;
         end case;

         if cart_init_i = '1' then
            c_run   <= cart_type_i(0) or cart_type_i(1);
            c_hrt   <= cart_type_i(0);
            c_idx   <= (others => '0');
            c_prime <= '0';
            c_aga   <= cart_aga_i;
            c_chip  <= cart_chip_i;
         end if;

         if rst_i = '1' then
            m_state  <= M_IDLE;
            m_active <= '0';
            m_mirror <= '0';
            c_run    <= '0';
            c_tail   <= '0';
            e_run    <= '0';
            e_done   <= '0';
         end if;
      end if;
   end process p_maint;

   cart_busy_o <= c_run or c_tail or cart_init_i;
   maint_idle_o <= '1' when m_state = M_IDLE else '0';

   -- Megamiga: the HRTmon cartridge image (CORE/hrtmon, GPL-2.0-or-later, built from the
   -- HRTmon 2.38 source by CORE/hrtmon/build.sh): C_HRTMON_WORDS words in block RAM, as
   -- four 32K-word parts hrtmon_0..3.hex - Vivado stops tdp_ram's file loader at 65536
   -- loop iterations (Synth 8-403), one per line. c_idx is unchanged while a word is taken
   -- (c_prime), so its top bits select the part directly.
   rom_q <= rom_qs(to_integer(c_idx(16 downto 15)));

   g_hrtmon : for i in 0 to 3 generate
   i_hrtmon : entity work.tdp_ram
      generic map (
         ADDR_WIDTH   => 15,
         DATA_WIDTH   => 16,
         ROM_PRELOAD  => true,
         ROM_FILE     => HRTMON_ROM_PREFIX & character'val(character'pos('0') + i) & ".hex",
         ROM_FILE_HEX => true
      )
      port map (
         clock_a   => clk_i,
         clen_a    => '1',
         address_a => std_logic_vector(c_idx(14 downto 0)),
         data_a    => (others => '0'),
         wren_a    => '0',
         q_a       => rom_qs(i),
         clock_b   => clk_i,
         clen_b    => '0',
         address_b => (others => '0'),
         data_b    => (others => '0'),
         wren_b    => '0',
         q_b       => open
      ); -- i_hrtmon
   end generate g_hrtmon;

   ---------------------------------------------------------------------------------------
   -- CPU port chip select (see the declaration of ram_cs); Minimig.sv, clk_114 process:
   --   div <= div + 1; if (~c1d & c1) div <= 3; cyc <= !div[1:0];
   --   ram_cs <= ~(ram_ready & cyc & cpu_type) & ram_sel;
   ---------------------------------------------------------------------------------------

   fram_ready_o <= fram_ready;

   p_ram_cs : process (clk4x_i)
   begin
      if rising_edge(clk4x_i) then
         div   <= div + 1;
         c7m_d <= c7m_i;
         if c7m_d = '0' and c7m_i = '1' then
            div <= to_unsigned(3, 4);
         end if;
         if div(1 downto 0) = "00" then
            cyc <= '1';
         else
            cyc <= '0';
         end if;
         ram_cs <= not (fram_ready and cyc and cpu_020_i) and fram_sel_i;
      end if;
   end process p_ram_cs;

   ---------------------------------------------------------------------------------------
   -- Floppy port: Avalon slave -> one controller request per word. A request is pending while
   -- f_req /= f_ack; the controller toggles f_ack when the word is done. A reset never drops
   -- a pending request (the controller may already be executing it): F_DRAIN waits for it.
   ---------------------------------------------------------------------------------------

   flp_avm_waitrequest_o <= '0' when f_state = F_IDLE or f_state = F_WNEXT else '1';

   p_flp : process (clk_i)
   begin
      if rising_edge(clk_i) then
         flp_avm_readdatavalid_o <= '0';

         case f_state is
            when F_IDLE =>
               if flp_avm_read_i = '1' or flp_avm_write_i = '1' then
                  f_addr  <= unsigned(flp_avm_address_i(21 downto 0));
                  f_cnt   <= unsigned(flp_avm_burstcount_i);
                  f_we    <= flp_avm_write_i;
                  f_data  <= flp_avm_writedata_i;
                  f_be    <= flp_avm_byteenable_i;
                  f_req   <= not f_req;
                  f_state <= F_WAIT;
               end if;

            when F_WAIT =>
               if f_ack = f_req then                                 -- word done
                  if f_we = '0' then
                     flp_avm_readdata_o      <= f_rd;
                     flp_avm_readdatavalid_o <= '1';
                  end if;
                  f_addr <= f_addr + 1;
                  f_cnt  <= f_cnt - 1;
                  if f_cnt <= 1 then
                     f_state <= F_IDLE;
                  elsif f_we = '0' then
                     f_req   <= not f_req;                           -- next word of the burst
                  else
                     f_state <= F_WNEXT;
                  end if;
               end if;

            when F_WNEXT =>                                          -- next beat of a write burst
               if flp_avm_write_i = '1' then
                  f_data  <= flp_avm_writedata_i;
                  f_be    <= flp_avm_byteenable_i;
                  f_req   <= not f_req;
                  f_state <= F_WAIT;
               end if;

            when F_DRAIN =>
               if f_ack = f_req then
                  f_state <= F_IDLE;
               end if;
         end case;

         if flp_rst_i = '1' then
            f_state <= F_DRAIN;
         end if;
      end if;
   end process p_flp;

   ---------------------------------------------------------------------------------------
   -- Chipset port mux: the maintenance writer or minimig_sram_bridge.v
   ---------------------------------------------------------------------------------------

   c_addr <= "00" & m_addr      when m_active = '1' else "00" & ram_addr_i;
   c_data <= m_data              when m_active = '1' else ram_data_i;
   c_u    <= '0'                 when m_active = '1' else ram_bhe_n_i;
   c_l    <= '0'                 when m_active = '1' else ram_ble_n_i;
   c_rw   <= '0'                 when m_active = '1' else ram_we_n_i;
   c_dma  <= '1'                 when m_active = '1' else ram_oe_n_i;

   i_sdram_ctrl : sdram_ctrl
      port map (
         sysclk         => clk4x_i,
         c_7m           => c7m_i,
         reset_n        => reset_n,
         cache_rst      => cpu_reset_n_i,
         cache_inhibit  => '0',
         cpu_cache_ctrl => cpu_cacr_i,
         sd_addr        => sdram_a_o,
         sd_ba          => sdram_ba_o,
         sd_cs          => sdram_cs_n_o,
         sd_we          => sdram_we_n_o,
         sd_ras         => sdram_ras_n_o,
         sd_cas         => sdram_cas_n_o,
         sd_dqm(1)      => sdram_dqmh_o,
         sd_dqm(0)      => sdram_dqml_o,
         sd_data        => sdram_dq_io,
         sd_clk         => sdram_clk_o,
         sd_cke         => sdram_cke_o,
         chipAddr       => c_addr,
         chipL          => c_l,
         chipU          => c_u,
         chipRW         => c_rw,
         chipDMA        => c_dma,
         chipWR         => c_data,
         chipRD         => ram_data_o,
         chip48         => chip48_o,
         cpuAddr        => fram_addr_i,                              -- bank chosen by main.vhd
         cpuCS          => ram_cs,
         cpustate       => fram_state_i,
         cpuL           => fram_lds_n_i,
         cpuU           => fram_uds_n_i,
         cpuWR          => fram_data_i,
         cpuRD          => fram_data_o,
         ramready       => fram_ready,
         flpReq         => f_req,
         flpAddr        => std_logic_vector(f_addr),
         flpWE          => f_we,
         flpL           => not f_be(0),
         flpU           => not f_be(1),
         flpWR          => f_data,
         flpRD          => f_rd,
         flpAck         => f_ack,
         fpReq          => fp_req_i,
         fpWE           => fp_we_i,
         fpLine         => fp_line_i,
         fpAddr         => fp_addr_i,
         fpBE           => fp_be_i,
         fpWR           => fp_data_i,
         fpRD           => fp_data_o,
         fpAck          => fp_ack_o,
         dmReq          => dm_req_i,
         dmWE           => dm_we_i,
         dmLine         => dm_line_i,
         dmAddr         => dm_addr_i,
         dmBE           => dm_be_i,
         dmWR           => dm_data_i,
         dmAck          => dm_ack_o
      ); -- i_sdram_ctrl

end architecture synthesis;
