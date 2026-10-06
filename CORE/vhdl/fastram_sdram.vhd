---------------------------------------------------------------------------------------------
-- Amiga 500 for MEGA65 (AExp)
--
-- 8 MB Zorro II Fast RAM in the R4/R5/R6 board SDRAM (IS42S16320F, 32M x 16)
--
-- Serves cpu_wrapper.v's "ram*" port (MiSTer's SDRAM/DDR3 CPU port) for the autoconfig'd
-- Zorro II window $200000-$9FFFFF. The 68000 waits for DTACK, which cpu_wrapper derives
-- combinationally from ready_o, so the latency is absorbed by the CPU bus protocol.
--
-- Clocking: the controller runs SYNCHRONOUSLY on the core clock (28.375 MHz, or the
-- 28.4375 MHz HDMI flicker-free twin, see clk.vhd). There is no clock-domain crossing at
-- all. An SDR SDRAM has no DLL and no minimum clock frequency, and the glitch-free
-- BUFGMUX_CTRL switch only stretches one clock phase, which the SDRAM tolerates. All
-- SDRAM timing parameters (tRCD/tRP 18 ns, tRAS 42 ns, tRC/tRFC 60 ns, tWR 12 ns) are met
-- with one or more 35 ns cycles of slack each.
--
-- I/O timing (no set_input/output_delay needed; see the budget below):
--   * sdram_clk_o is the core clock INVERTED (ODDR D1='0', D2='1'): the SDRAM samples on
--     the core clock's falling edge, half a cycle (17.6 ns) after the IOB output registers
--     changed on the rising edge -> ~17 ns setup and hold for every command/address/data.
--   * Read data is captured on the core clock's FALLING edge, 2.5 cycles after the READ
--     command left the FPGA (CAS latency 2). Data valid window at the FPGA pin, with
--     d_clk = clock-out delay and d_in = pin-to-IOB delay (both a few ns):
--       [F2 + d_clk + tAC(6.0) + d_in,  F3 + d_clk + tOH(2.5) + d_in]
--     where F2/F3 are the falling edges 1.5/2.5 cycles after the READ. Capturing at F3
--     gives ~35 - 6 - d_clk - d_in (~20 ns) setup and d_clk + d_in + 2.5 (~8 ns) hold.
--     A rising-edge capture would lose its setup margin for slow d_clk, hence the falling
--     edge. The half-cycle hop into the rising-edge domain is timed by Vivado.
--
-- Access sequence (one 16-bit word per 68000 bus cycle, bank closed after every access,
-- so a refresh can always be issued from IDLE/DONE without a PRECHARGE first):
--   read : ACT, READ, NOP, PRECHARGE, capture+ready  -> ready 4 clocks after the request
--   write: ACT, WRITE, NOP, PRECHARGE, ready         -> ready 4 clocks after the request
-- That is 141 ns vs. a 564 ns 68000 bus cycle: the CPU runs from Fast RAM without being
-- slowed down by the chipset, exactly what Fast RAM is for.
--
-- 68000 bus protocol details that matter here:
--   * A write's UDS/LDS (and thus valid data) follow AS by one CPU half-clock, so a
--     write only starts once a data strobe is asserted.
--   * TAS (read-modify-write) keeps AS asserted across its read and write halves, so
--     sel_i never drops in between. A transaction therefore ends when sel_i drops OR when
--     the bus direction changes; ready_o is gated with both conditions so a stale ready
--     can never acknowledge the next transaction.
--
-- Address map: the 22-bit word address from cpu_wrapper (ramaddr[22:1]) maps the Zorro II
-- window 1:1 onto the first 8 MB: column = addr(10:1), row = addr(22:11), bank 0.
--
-- Fast RAM extension of the AExp core (fork increment WIP-V2-A11-JS-01), 2026,
-- licensed under GPL v3 like the rest of the core.
---------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity fastram_sdram is
   generic (
      -- Power-up wait before the init sequence (spec: >= 100 us with stable clock).
      -- 8192 cycles = 288 us at 28.4 MHz.
      G_INIT_CYCLES    : natural := 8192;
      -- Refresh interval: 8192 AUTO REFRESH per 64 ms = one per 7.81 us = 222 clocks at
      -- 28.4375 MHz. 192 leaves room for the ~10-clock worst-case postponement.
      G_REFRESH_CYCLES : natural := 192
   );
   port (
      clk_i          : in    std_logic;   -- core clock (28.375 / 28.4375 MHz)
      rst_i          : in    std_logic;   -- clock-generator reset only: the RAM contents
                                          -- survive every Amiga reset, like real Fast RAM

      -- cpu_wrapper.v "ram*" port (all in the core clock domain)
      sel_i          : in    std_logic;                      -- Fast RAM bus cycle in progress
      we_i           : in    std_logic;                      -- '1' = write (cpustate = 3)
      addr_i         : in    std_logic_vector(22 downto 1);  -- word address
      uds_n_i        : in    std_logic;                      -- byte enable 15:8, active low
      lds_n_i        : in    std_logic;                      -- byte enable  7:0, active low
      data_i         : in    std_logic_vector(15 downto 0);  -- write data
      data_o         : out   std_logic_vector(15 downto 0);  -- read data, valid with ready_o
      ready_o        : out   std_logic;                      -- -> DTACK

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
end entity fastram_sdram;

architecture synthesis of fastram_sdram is

   -- SDRAM commands: CS#, RAS#, CAS#, WE#
   subtype t_cmd is std_logic_vector(3 downto 0);
   constant C_CMD_NOP       : t_cmd := "0111";
   constant C_CMD_ACTIVE    : t_cmd := "0011";
   constant C_CMD_READ      : t_cmd := "0101";
   constant C_CMD_WRITE     : t_cmd := "0100";
   constant C_CMD_PRECHARGE : t_cmd := "0010";
   constant C_CMD_REFRESH   : t_cmd := "0001";
   constant C_CMD_LOAD_MODE : t_cmd := "0000";

   -- Mode register: A9 = 1 single-location write, A8:7 = 00 standard, A6:4 = 010 CAS
   -- latency 2, A3 = 0 sequential, A2:0 = 000 burst length 1
   constant C_MODE_REG      : std_logic_vector(12 downto 0) := "0001000100000";

   constant C_INIT_REFRESHES : natural := 8;   -- spec minimum is 2
   constant C_TRFC_WAIT      : natural := 3;   -- NOPs after AUTO REFRESH (3 x 35 ns > tRFC)

   type t_state is (
      INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH, INIT_REFRESH_WAIT, INIT_LOAD_MODE,
      IDLE, RD_CMD, RD_NOP, RD_PRECHARGE, RD_CAPTURE,
      WR_CMD, WR_NOP, WR_PRECHARGE, WR_DONE,
      CMD_WAIT, DONE
   );

   signal state         : t_state := INIT_WAIT;
   signal wait_count    : natural range 0 to G_INIT_CYCLES := G_INIT_CYCLES;
   signal init_refs     : natural range 0 to C_INIT_REFRESHES := 0;
   signal refresh_count : natural range 0 to G_REFRESH_CYCLES := 0;
   signal refresh_due   : std_logic := '0';

   -- request latched in IDLE: the SDRAM sequence never looks at the CPU bus again
   signal col           : std_logic_vector(9 downto 0)  := (others => '0');
   signal wr_data       : std_logic_vector(15 downto 0) := (others => '0');
   signal wr_mask       : std_logic_vector(1 downto 0)  := (others => '0');

   -- transaction bookkeeping for ready_o
   signal ready         : std_logic := '0';
   signal ready_we      : std_logic := '0';   -- direction of the acknowledged transaction
   signal rd_data       : std_logic_vector(15 downto 0) := (others => '0');

   -- I/O registers: kept as flip-flops in the IOBs for a fixed, placement-independent
   -- pin timing (the timing budget in the header assumes this)
   signal cmd           : t_cmd := C_CMD_NOP;
   signal a             : std_logic_vector(12 downto 0) := (others => '0');
   signal ba            : std_logic_vector(1 downto 0)  := (others => '0');
   signal dqm           : std_logic_vector(1 downto 0)  := (others => '1');
   signal dq_out        : std_logic_vector(15 downto 0) := (others => '0');
   signal dq_t          : std_logic_vector(15 downto 0) := (others => '1');  -- '1' = high-Z
   signal dq_in         : std_logic_vector(15 downto 0) := (others => '0');

   attribute IOB : string;
   attribute IOB of cmd    : signal is "TRUE";
   attribute IOB of a      : signal is "TRUE";
   attribute IOB of ba     : signal is "TRUE";
   attribute IOB of dqm    : signal is "TRUE";
   attribute IOB of dq_out : signal is "TRUE";
   attribute IOB of dq_t   : signal is "TRUE";
   attribute IOB of dq_in  : signal is "TRUE";

   -- one tristate-control flip-flop per DQ pin, otherwise synthesis merges them into a
   -- single register that cannot be packed into 16 IOBs. Two more rules keep dq_t in the
   -- OLOGIC site next to dq_out (Shape Builder 18-132 in the first R6 builds otherwise):
   --   * ACTIVE-LOW ("T" polarity of the I/O buffer, '1' = high-Z), so no inverter sits
   --     between the flip-flop and the buffer;
   --   * NO reset: an OLOGIC's output and tristate flip-flops share one set/reset line,
   --     and dq_out has none. dq_t needs none either - the FSM drives it to '1' every
   --     clock except in WR_CMD, and its power-up value is '1'.
   attribute equivalent_register_removal : string;
   attribute equivalent_register_removal of dq_t : signal is "no";

begin

   ---------------------------------------------------------------------------------------
   -- Pins
   ---------------------------------------------------------------------------------------

   -- Inverted forwarded clock: Q = D1 after the rising edge, D2 after the falling edge
   i_oddr_clk : ODDR
      generic map (
         DDR_CLK_EDGE => "SAME_EDGE",
         INIT         => '0',
         SRTYPE       => "SYNC"
      )
      port map (
         Q  => sdram_clk_o,
         C  => clk_i,
         CE => '1',
         D1 => '0',
         D2 => '1',
         R  => '0',
         S  => '0'
      ); -- i_oddr_clk

   sdram_cke_o   <= '1';
   sdram_cs_n_o  <= cmd(3);
   sdram_ras_n_o <= cmd(2);
   sdram_cas_n_o <= cmd(1);
   sdram_we_n_o  <= cmd(0);
   sdram_ba_o    <= ba;
   sdram_a_o     <= a;
   sdram_dqmh_o  <= dqm(1);
   sdram_dqml_o  <= dqm(0);

   g_dq : for i in 0 to 15 generate
      sdram_dq_io(i) <= dq_out(i) when dq_t(i) = '0' else 'Z';
   end generate g_dq;

   -- free-running falling-edge capture of the data bus (see the I/O timing budget)
   dq_capture_proc : process (clk_i)
   begin
      if falling_edge(clk_i) then
         dq_in <= sdram_dq_io;
      end if;
   end process dq_capture_proc;

   ---------------------------------------------------------------------------------------
   -- CPU side
   ---------------------------------------------------------------------------------------

   -- Gated so that a ready left over from the previous transaction can never acknowledge
   -- the next one: it drops combinationally the moment AS is negated or a TAS cycle turns
   -- from its read half into its write half.
   ready_o <= ready and sel_i and not (we_i xor ready_we);
   data_o  <= rd_data;

   ---------------------------------------------------------------------------------------
   -- Controller FSM incl. initialization and refresh
   ---------------------------------------------------------------------------------------

   fsm_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         -- Refresh timer. The FSM below clears refresh_due when it issues the command; a
         -- set and a clear can never coincide, because a pending refresh is served within
         -- a few clocks (IDLE and DONE both serve it, every other state is transient).
         if refresh_count = G_REFRESH_CYCLES - 1 then
            refresh_count <= 0;
            refresh_due   <= '1';
         else
            refresh_count <= refresh_count + 1;
         end if;

         -- defaults: NOP, bus released, all bytes enabled for reads
         cmd   <= C_CMD_NOP;
         dq_t  <= (others => '1');
         dqm   <= "00";

         case state is

            ------------------------------------------------------------------------------
            -- Power-up initialization (JEDEC SDR sequence)
            ------------------------------------------------------------------------------

            when INIT_WAIT =>
               dqm <= "11";
               if wait_count = 0 then
                  state <= INIT_PRECHARGE;
               else
                  wait_count <= wait_count - 1;
               end if;

            when INIT_PRECHARGE =>
               dqm       <= "11";
               cmd       <= C_CMD_PRECHARGE;
               a(10)     <= '1';                         -- all banks
               init_refs <= C_INIT_REFRESHES;
               state     <= INIT_REFRESH;

            when INIT_REFRESH =>
               dqm        <= "11";
               cmd        <= C_CMD_REFRESH;
               init_refs  <= init_refs - 1;
               wait_count <= C_TRFC_WAIT;
               state      <= INIT_REFRESH_WAIT;

            when INIT_REFRESH_WAIT =>
               dqm <= "11";
               if wait_count = 0 then
                  if init_refs = 0 then
                     state <= INIT_LOAD_MODE;
                  else
                     state <= INIT_REFRESH;
                  end if;
               else
                  wait_count <= wait_count - 1;
               end if;

            when INIT_LOAD_MODE =>
               cmd         <= C_CMD_LOAD_MODE;
               a           <= C_MODE_REG;
               ba          <= "00";
               refresh_due <= '0';
               wait_count  <= 2;                         -- tMRD
               state       <= CMD_WAIT;

            ------------------------------------------------------------------------------
            -- Idle: refresh has priority (it costs at most four clocks of CPU latency)
            ------------------------------------------------------------------------------

            when IDLE =>
               ready <= '0';
               if refresh_due = '1' then
                  cmd         <= C_CMD_REFRESH;
                  refresh_due <= '0';
                  wait_count  <= C_TRFC_WAIT;
                  state       <= CMD_WAIT;
               elsif sel_i = '1' and (we_i = '0' or uds_n_i = '0' or lds_n_i = '0') then
                  -- Latch the whole request, so the SDRAM sequence is self-contained even
                  -- if the CPU is reset in the middle of it. A write waits for a data
                  -- strobe: only then are the data and byte enables valid.
                  cmd      <= C_CMD_ACTIVE;
                  a        <= '0' & addr_i(22 downto 11);  -- row
                  ba       <= "00";
                  col      <= addr_i(10 downto 1);
                  wr_data  <= data_i;
                  wr_mask  <= uds_n_i & lds_n_i;           -- active-low strobe = DQM mask
                  ready_we <= we_i;
                  if we_i = '1' then
                     state <= WR_CMD;
                  else
                     state <= RD_CMD;
                  end if;
               end if;

            ------------------------------------------------------------------------------
            -- Read: ACT, READ, NOP, PRECHARGE, capture
            ------------------------------------------------------------------------------

            when RD_CMD =>
               cmd   <= C_CMD_READ;
               a     <= "000" & col;                     -- A10 = 0: no auto precharge
               state <= RD_NOP;

            when RD_NOP =>
               state <= RD_PRECHARGE;

            when RD_PRECHARGE =>
               cmd   <= C_CMD_PRECHARGE;                 -- tRAS: 3 clocks after ACT
               a(10) <= '1';
               state <= RD_CAPTURE;

            when RD_CAPTURE =>
               rd_data <= dq_in;                         -- captured on the falling edge
               ready   <= '1';                           -- 2.5 clocks after READ (CL 2)
               state   <= DONE;

            ------------------------------------------------------------------------------
            -- Write: ACT, WRITE, NOP, PRECHARGE, ready
            ------------------------------------------------------------------------------

            when WR_CMD =>
               cmd    <= C_CMD_WRITE;
               a      <= "000" & col;                    -- A10 = 0: no auto precharge
               dq_out <= wr_data;
               dq_t   <= (others => '0');
               dqm    <= wr_mask;
               state  <= WR_NOP;

            when WR_NOP =>
               state <= WR_PRECHARGE;

            when WR_PRECHARGE =>
               cmd   <= C_CMD_PRECHARGE;                 -- tWR: 2 clocks after WRITE
               a(10) <= '1';
               state <= WR_DONE;

            when WR_DONE =>
               ready <= '1';
               state <= DONE;

            ------------------------------------------------------------------------------
            -- Hold the acknowledge until the transaction ends: AS negated, or the
            -- direction changed (read half -> write half of a TAS). A refresh that falls
            -- due meanwhile is served right here, since the bank is already closed.
            ------------------------------------------------------------------------------

            when DONE =>
               if ready = '0' or sel_i = '0' or we_i /= ready_we then
                  ready <= '0';
                  state <= IDLE;
               elsif refresh_due = '1' then
                  cmd         <= C_CMD_REFRESH;
                  refresh_due <= '0';
                  wait_count  <= C_TRFC_WAIT;
                  state       <= CMD_WAIT;
               end if;

            -- NOPs after REFRESH / LOAD MODE, then DONE: DONE drops a stale ready and
            -- falls through to IDLE, or keeps holding a still-running transaction
            when CMD_WAIT =>
               if sel_i = '0' or we_i /= ready_we then
                  ready <= '0';
               end if;
               if wait_count = 0 then
                  state <= DONE;
               else
                  wait_count <= wait_count - 1;
               end if;

         end case;

         if rst_i = '1' then
            state         <= INIT_WAIT;
            wait_count    <= G_INIT_CYCLES;
            refresh_count <= 0;
            refresh_due   <= '0';
            ready         <= '0';
            cmd           <= C_CMD_NOP;
            dqm           <= "11";
         end if;
      end if;
   end process fsm_proc;

end architecture synthesis;
