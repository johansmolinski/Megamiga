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
--
-- Maintenance writer: while it has work it owns the chipset port of the controller (the Amiga
-- is in reset then: at startup, and during a cold boot):
--   * Kickstart loading: the QNICE Shell streams the ROM file byte by byte into this device
--     (C_DEV_AMIGA_KICK, byte address = file offset, the even byte is the high byte). Pairs
--     of bytes cross to the core clock through a FIFO and are written to the kick bank. A word
--     of the first 256 KB is also written to the second 256 KB, so a 256 KB Kickstart (1.x) is
--     mirrored like on real hardware; a 512 KB Kickstart then overwrites the mirror.
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
      ram_bhe_n_i    : in    std_logic;
      ram_ble_n_i    : in    std_logic;
      ram_we_n_i     : in    std_logic;
      ram_oe_n_i     : in    std_logic;

      -- CPU Fast RAM port: cpu_wrapper.v "ram*" (core clock)
      fram_sel_i     : in    std_logic;
      fram_state_i   : in    std_logic_vector(1 downto 0);   -- cpustate (3 = write)
      fram_addr_i    : in    std_logic_vector(22 downto 1);
      fram_uds_n_i   : in    std_logic;
      fram_lds_n_i   : in    std_logic;
      fram_data_i    : in    std_logic_vector(15 downto 0);
      fram_data_o    : out   std_logic_vector(15 downto 0);
      fram_ready_o   : out   std_logic;
      cpu_reset_n_i  : in    std_logic;                      -- clears the CPU read cache
      cpu_cacr_i     : in    std_logic_vector(3 downto 0);

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
      kick_busy_o    : out   std_logic;                      -- core clock: words still in flight

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
         cpuAddr        : in    std_logic_vector(24 downto 1);
         cpuCS          : in    std_logic;
         cpustate       : in    std_logic_vector(1 downto 0);
         cpuL           : in    std_logic;
         cpuU           : in    std_logic;
         cpuWR          : in    std_logic_vector(15 downto 0);
         cpuRD          : out   std_logic_vector(15 downto 0);
         ramready       : out   std_logic
      );
   end component sdram_ctrl;

   constant C_KICK_BANK : std_logic_vector(3 downto 0) := "1111";   -- minimig_sram_bridge.v
   constant C_HOLD      : natural := 8;                              -- core clocks per phase

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

   -- Kickstart loader FIFO: {word address 17:0, data 15:0}
   signal q_hi      : std_logic_vector(7 downto 0) := (others => '0');
   signal q_wr_en   : std_logic := '0';
   signal q_din     : std_logic_vector(33 downto 0) := (others => '0');
   signal q_full    : std_logic;
   signal q_wr_rst_busy : std_logic;
   signal f_rd_en   : std_logic;
   signal f_dout    : std_logic_vector(33 downto 0);
   signal f_empty   : std_logic;
   signal f_rd_rst_busy : std_logic;

   signal reset_n   : std_logic;

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
   kick_busy_o <= '1' when f_empty = '0' or m_state /= M_IDLE or m_mirror = '1' else '0';

   p_qnice_bytes : process (qnice_clk_i)
   begin
      if falling_edge(qnice_clk_i) then
         q_wr_en <= '0';
         if qnice_ce_i = '1' and qnice_we_i = '1' and q_full = '0' and q_wr_rst_busy = '0' then
            if qnice_addr_i(0) = '0' then
               q_hi <= qnice_data_i(7 downto 0);                       -- even byte: high byte
            else
               q_din   <= qnice_addr_i(18 downto 1) & q_hi & qnice_data_i(7 downto 0);
               q_wr_en <= '1';
            end if;
         end if;
      end if;
   end process p_qnice_bytes;

   i_kick_fifo : xpm_fifo_async
      generic map (
         FIFO_MEMORY_TYPE    => "distributed",
         FIFO_WRITE_DEPTH    => 16,
         WRITE_DATA_WIDTH    => 34,
         READ_DATA_WIDTH     => 34,
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

   f_rd_en <= '1' when m_state = M_IDLE and scrub_i = '0' and f_empty = '0' and
                       f_rd_rst_busy = '0' and m_mirror = '0' else '0';

   p_maint : process (clk_i)
   begin
      if rising_edge(clk_i) then
         case m_state is
            when M_IDLE =>
               m_active <= '0';
               if scrub_i = '1' then                                 -- cold-boot scrub
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
               elsif f_rd_en = '1' then                              -- next Kickstart word
                  m_addr   <= C_KICK_BANK & f_dout(33 downto 16);
                  m_data   <= f_dout(15 downto 0);
                  m_mirror <= not f_dout(33);                        -- word in the first 256 KB
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
                  m_state <= M_IDLE;
               else
                  m_cnt <= m_cnt - 1;
               end if;
         end case;

         if rst_i = '1' then
            m_state  <= M_IDLE;
            m_active <= '0';
            m_mirror <= '0';
         end if;
      end if;
   end process p_maint;

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
         chip48         => open,
         cpuAddr        => "01" & fram_addr_i,                       -- Fast RAM: bank 1
         cpuCS          => fram_sel_i,
         cpustate       => fram_state_i,
         cpuL           => fram_lds_n_i,
         cpuU           => fram_uds_n_i,
         cpuWR          => fram_data_i,
         cpuRD          => fram_data_o,
         ramready       => fram_ready_o
      ); -- i_sdram_ctrl

end architecture synthesis;
