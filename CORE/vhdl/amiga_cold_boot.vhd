---------------------------------------------------------------------------------------------
-- AExp: Amiga-local cold boot controller
--
-- A normal 68000 reset is a warm boot: Kickstart reuses the ExecBase pointer stored at
-- Chip RAM $000004 and therefore keeps the old Exec memory list. That is wrong after the
-- OSM changes the physical memory topology (the Slow RAM / A501 and the Fast RAM toggles).
--
-- This controller turns such a topology change into a cold boot of the emulated Amiga only.
-- It holds Minimig in reset and asks the Chip RAM wrapper to clear the two 16-bit words at
-- $000004-$000007. Kickstart then rejects the warm-boot state, probes the new memory map and
-- rebuilds Exec. QNICE, the framework, HyperRAM and mounted media remain untouched.
--
-- The floppy drive configuration (drv_map_i: how many Amiga units exist and what each of
-- them is) is a topology change too: Paula latches the drive count only at reset, AmigaOS
-- enumerates units at boot, and a unit changing identity under a running OS would confuse
-- mounted volumes. A configuration change therefore triggers the same cold boot (the
-- SysBase scrub is harmless there).
--
-- Megamiga: a Kickstart load from the OSM (kick_hold_i) is a cold boot too. The Amiga is
-- held in reset for the whole load, and released only after kick_hold_i has been low for
-- C_RESET_HOLD_CYCLES clocks, so the last ROM words are in the SDRAM before the CPU starts.
--
-- Megamiga: the freezer cartridge (cart_i: "00" none, "01" HRTmon, "10" Action Replay III,
-- where the AR3 counts only with its ROM loaded) is part of the topology too. Each cold boot
-- also (re-)initialises the cartridge memory in the SDRAM: cart_init_o is high for one clock
-- with cart_type_o = the cartridge that is plugged in from then on (HRTmon: its image is
-- copied to $A10000; AR3: its RAM is cleared), and the Amiga stays in reset until
-- cart_busy_i is low again. That value - latched when the init starts - is also the one
-- that is applied, so a change during the init leads to another cold boot.
-- Megamiga (ntsc): the video standard (ntsc_i, the menu's global "NTSC (60 Hz)" toggle) is the
-- crystal of the machine: the core clock is PAL 28.375 MHz or NTSC 28.636364 MHz (clk.vhd, two
-- MMCMs and glitch-free BUFGMUX_CTRLs selected by ntsc_o), and Agnus starts in that standard
-- (amiga_config.vhd sends it in 0xF3 at every reset). A change is a cold boot with one more step:
-- in CLK_DRAIN the Amiga is in reset and the SDRAM controller's other users are stopped (pause_o
-- halts the maintenance writer); once nothing has been in flight (sdram_quiet_i) for
-- C_SWITCH_CYCLES clocks, ntsc_o flips. The core clock and the SDRAM's 4x clock then switch one
-- after the other within a few clocks: their relation is undefined meanwhile, which only matters
-- for an access in flight - hence the drain. CLK_SETTLE gives the new clock C_SWITCH_CYCLES clocks
-- (sdram_ctrl re-synchronises its 16 states to c_7m at the next bus cycle) before the scrub writes.
-- If the SDRAM never gets quiet, the switch happens after C_SWITCH_TIMEOUT anyway.
-- The request is level-based (requested /= applied), not a pulse. Consequently a change
-- cannot be lost, and changes arriving during a cold boot converge to the latest value.
---------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity amiga_cold_boot is
   port (
      clk_i             : in  std_logic;
      slow_ram_i        : in  std_logic;
      fast_ram_i        : in  std_logic;                     -- 8 MB Zorro II Fast RAM present
      cpu_020_i         : in  std_logic;                     -- Megamiga: 68020 instead of 68000
      cpu_040_i         : in  std_logic;                     -- Megamiga: the 68040 (cpu_020_i is '1' too)
      z3_ram_i          : in  std_logic;                     -- Megamiga: 16 MB Zorro III board
      z3b_ram_i         : in  std_logic;                     -- Megamiga 0.7: 32 MB Zorro III board
      gayle_i           : in  std_logic;                     -- Megamiga 0.7: IDE as the Gayle
      boards_i          : in  std_logic_vector(2 downto 0);  -- Megamiga 0.7: {network card, graphics card, no IDE}
      chipset_i         : in  std_logic_vector(1 downto 0);  -- Megamiga: OCS / ECS / AGA
      chip_size_i       : in  std_logic_vector(1 downto 0);  -- Megamiga: chip RAM 512K / 1M / 2M
      drv_map_i         : in  std_logic_vector(7 downto 0);  -- Drive Settings: {count, mode per unit}
      kick_hold_i       : in  std_logic;                     -- Kickstart load in progress
      cart_i            : in  std_logic_vector(1 downto 0);  -- Megamiga: none / HRTmon / AR3
      cart_busy_i       : in  std_logic;                     -- Megamiga: cartridge init running
      ntsc_i            : in  std_logic;                     -- Megamiga (ntsc): requested standard
      sdram_quiet_i     : in  std_logic;                     -- ... nothing in flight in the SDRAM

      ntsc_o            : out std_logic;                     -- ... applied: the clock select
      pause_o           : out std_logic;                     -- ... stop the SDRAM writer (amiga_sdram)

      cart_init_o       : out std_logic;                     -- Megamiga: start the cartridge init
      cart_type_o       : out std_logic_vector(1 downto 0);  -- Megamiga: for the init and the Amiga

      amiga_reset_o     : out std_logic;
      chip_scrub_o      : out std_logic;
      chip_scrub_addr_o : out std_logic_vector(17 downto 0)
   );
end entity amiga_cold_boot;

architecture synthesis of amiga_cold_boot is

   type t_state is (IDLE, ASSERT_RESET, CLK_DRAIN, CLK_SETTLE, SCRUB_SYSBASE_HI, SCRUB_SYSBASE_LO,
                    CART_INIT, HOLD_RESET);

   -- minimig_syscontrol samples its master reset only on clk7_en (one out of four clk28
   -- ticks). Keep the request high for 64 clocks, matching the established keyboard-reset
   -- scale and leaving generous phase margin before Chip RAM is touched.
   constant C_RESET_HOLD_CYCLES : natural := 64;

   signal state            : t_state := IDLE;
   signal slow_ram_applied : std_logic := '1'; -- OSM default is A501 enabled
   signal fast_ram_applied : std_logic := '0'; -- OSM default is no Fast RAM (and R3 has none)
   signal cpu_020_applied  : std_logic := '0'; -- OSM default is the 68000
   signal cpu_040_applied  : std_logic := '0';
   signal z3_ram_applied   : std_logic := '0'; -- OSM default is no Zorro III RAM
   signal z3b_ram_applied  : std_logic := '0';
   signal gayle_applied    : std_logic := '0';
   signal boards_applied   : std_logic_vector(2 downto 0) := "000";
   -- the power-on values are the menu defaults = the A500 profile (68000, OCS, 512 KB
   -- chip + 512 KB slow), so there is no spurious cold boot at t=0
   signal chipset_applied  : std_logic_vector(1 downto 0) := "00"; -- OSM default is OCS
   signal chip_size_applied : std_logic_vector(1 downto 0) := "00"; -- OSM default is 512 KB
   signal drv_map_applied  : std_logic_vector(7 downto 0) := "00" & "10" & "10" & "00";
                                       -- OSM default: one drive, df0 Disk Image,
                                       -- df1 and df2 Off (see mega65.vhd C_DRV_*)
   signal reset_hold_count : natural range 0 to C_RESET_HOLD_CYCLES - 1 := 0;
   signal cart_applied     : std_logic_vector(1 downto 0) := "00"; -- OSM default: no cartridge
   signal cart_q           : std_logic_vector(1 downto 0) := "00"; -- the one being initialised

   -- Megamiga (ntsc): the clock switch. 32768 clocks are 1.15 ms; the timeout 2**22 = 148 ms.
   constant C_SWITCH_CYCLES  : natural := 32768;
   constant C_SWITCH_TIMEOUT : natural := 2**22;
   signal ntsc_applied     : std_logic := '0';  -- power-up: PAL (the menu default)
   signal switch_count     : natural range 0 to C_SWITCH_CYCLES - 1 := 0;
   signal switch_timeout   : natural range 0 to C_SWITCH_TIMEOUT - 1 := 0;

begin

   -- ASSERT_RESET gives main.vhd a complete clock before the first scrub write. HOLD_RESET
   -- keeps the Amiga stopped for C_RESET_HOLD_CYCLES clocks after the second write.
   amiga_reset_o <= '0' when state = IDLE else '1';

   chip_scrub_o <= '1' when state = SCRUB_SYSBASE_HI or state = SCRUB_SYSBASE_LO else '0';

   ntsc_o  <= ntsc_applied;
   pause_o <= '1' when state = CLK_DRAIN or state = CLK_SETTLE else '0';

   -- Megamiga: the cartridge. cart_type_o is what the Amiga sees. During the init clock it
   -- must already be the new value, so the init works on that cartridge: CART_INIT only
   -- stores it into cart_applied at its end, hence cart_q there. (cart_applied alone gave
   -- amiga_sdram the PREVIOUS cartridge at the init - None -> HRTmon copied nothing.)
   cart_init_o  <= '1' when state = CART_INIT else '0';
   cart_type_o  <= cart_q when state = CART_INIT else cart_applied;

   -- main_ram_addr is a word address: byte addresses $000004 and $000006 are words 2 and 3.
   chip_scrub_addr_o <= std_logic_vector(to_unsigned(2, chip_scrub_addr_o'length))
                        when state = SCRUB_SYSBASE_HI else
                        std_logic_vector(to_unsigned(3, chip_scrub_addr_o'length));

   cold_boot_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         case state is
            when IDLE =>
               if slow_ram_i /= slow_ram_applied or fast_ram_i /= fast_ram_applied or
                  cpu_020_i /= cpu_020_applied or z3_ram_i /= z3_ram_applied or
                  cpu_040_i /= cpu_040_applied or gayle_i /= gayle_applied or
                  boards_i /= boards_applied or
                  z3b_ram_i /= z3b_ram_applied or
                  chipset_i /= chipset_applied or chip_size_i /= chip_size_applied or
                  drv_map_i /= drv_map_applied or kick_hold_i = '1' or cart_i /= cart_applied or
                  ntsc_i /= ntsc_applied then
                  reset_hold_count <= C_RESET_HOLD_CYCLES - 1;
                  state            <= ASSERT_RESET;
               end if;

            when ASSERT_RESET =>
               if reset_hold_count = 0 then
                  reset_hold_count <= C_RESET_HOLD_CYCLES - 1;
                  switch_count     <= C_SWITCH_CYCLES - 1;
                  switch_timeout   <= C_SWITCH_TIMEOUT - 1;
                  if ntsc_i /= ntsc_applied then
                     state <= CLK_DRAIN;
                  else
                     state <= SCRUB_SYSBASE_HI;
                  end if;
               else
                  reset_hold_count <= reset_hold_count - 1;
               end if;

            -- Megamiga (ntsc): the Amiga is in reset and the writer paused; wait until the SDRAM
            -- has had nothing in flight for C_SWITCH_CYCLES clocks, then switch the clock
            when CLK_DRAIN =>
               if switch_timeout /= 0 then
                  switch_timeout <= switch_timeout - 1;
               end if;
               if sdram_quiet_i = '0' and switch_timeout /= 0 then
                  switch_count <= C_SWITCH_CYCLES - 1;
               elsif switch_count /= 0 then
                  switch_count <= switch_count - 1;
               else
                  ntsc_applied <= ntsc_i;
                  switch_count <= C_SWITCH_CYCLES - 1;
                  state        <= CLK_SETTLE;
               end if;

            when CLK_SETTLE =>
               if switch_count /= 0 then
                  switch_count <= switch_count - 1;
               else
                  state <= SCRUB_SYSBASE_HI;
               end if;

            -- Megamiga: chip RAM is in the SDRAM, where amiga_sdram.vhd writes the word in
            -- one of its 7 MHz slots: hold each address for C_RESET_HOLD_CYCLES clocks
            when SCRUB_SYSBASE_HI =>
               if reset_hold_count = 0 then
                  reset_hold_count <= C_RESET_HOLD_CYCLES - 1;
                  state            <= SCRUB_SYSBASE_LO;
               else
                  reset_hold_count <= reset_hold_count - 1;
               end if;

            when SCRUB_SYSBASE_LO =>
               if reset_hold_count = 0 then
                  reset_hold_count <= C_RESET_HOLD_CYCLES - 1;
                  cart_q           <= cart_i;
                  state            <= CART_INIT;
               else
                  reset_hold_count <= reset_hold_count - 1;
               end if;

            -- Megamiga: one clock with cart_init_o; amiga_sdram raises cart_busy_i from the
            -- next clock on and holds it until the init is done (HOLD_RESET waits for it)
            when CART_INIT =>
               cart_applied <= cart_q;
               state        <= HOLD_RESET;

            when HOLD_RESET =>
               -- Stay in reset while a Kickstart load runs, and for C_RESET_HOLD_CYCLES
               -- clocks after it. Then capture the latest requested values, not the values
               -- that originally triggered the reset. If one changes again after this edge,
               -- IDLE detects the mismatch and immediately performs another complete cold
               -- boot; no request can be lost.
               if kick_hold_i = '1' or cart_busy_i = '1' then
                  reset_hold_count <= C_RESET_HOLD_CYCLES - 1;
               elsif reset_hold_count /= 0 then
                  reset_hold_count <= reset_hold_count - 1;
               else
                  slow_ram_applied <= slow_ram_i;
                  fast_ram_applied <= fast_ram_i;
                  cpu_020_applied  <= cpu_020_i;
                  cpu_040_applied  <= cpu_040_i;
                  z3_ram_applied   <= z3_ram_i;
                  z3b_ram_applied  <= z3b_ram_i;
                  gayle_applied    <= gayle_i;
                  boards_applied   <= boards_i;
                  chipset_applied  <= chipset_i;
                  chip_size_applied <= chip_size_i;
                  drv_map_applied  <= drv_map_i;
                  state            <= IDLE;
               end if;
         end case;
      end if;
   end process cold_boot_proc;

end architecture synthesis;
