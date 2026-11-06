---------------------------------------------------------------------------------------------------------
-- Megamiga (Amiga for MEGA65, fork of AExp)
--
-- rb_bridge: the time base of the rubber-banded Amiga (doc/developers/rubber-band.md).
--
-- The Amiga runs on amiga_clk, a BUFGCE-gated copy of the free-running rb_clk (clk.vhd, ~1.7 x
-- the real-time core clock main_clk). It takes an edge only while gate_o (the BUFGCE CE, decided
-- before the edge from rb_clk registers) is high. Its average rate is exactly real time, and all
-- of its real-time I/O goes through two FIFOs, so it may run ahead, pause on slow memory and catch
-- up without anything outside noticing:
--
--   in-FIFO   main_clk -> rb_clk   one word of real-time inputs (keyboard scan, joysticks, pots,
--                                  serial RX/CTS) per main_clk; the Amiga takes one word per edge.
--                                  The Amiga can never take an edge whose input word does not
--                                  exist yet: this is the pacer. The Amiga at Amiga time a sees
--                                  the inputs of real time a, i.e. it never runs ahead of real
--                                  time; it lags by the in-FIFO's level.
--   out-FIFO  rb_clk -> main_clk   one word of real-time outputs (video, audio, serial TX/RTS,
--                                  LEDs) per Amiga edge; read one word per main_clk once G_DELAY
--                                  words are in. The outputs therefore replay the Amiga's
--                                  outputs exactly, G_DELAY clocks (~72 us) late, and the Amiga
--                                  may lag real time by up to G_DELAY clocks before the reader
--                                  runs dry (an underflow: the reader stops, rt_valid_o goes low,
--                                  and it waits for G_DELAY words again; counted in rt_under_o).
--                                  While the reader waits, the in-FIFO's backlog is thrown away
--                                  (the Amiga skips those input words), the Amiga fills the
--                                  out-FIFO only up to G_DELAY, and the reader starts again only
--                                  when the backlog is gone: so after the underflow the Amiga is
--                                  back at real time and the latency at G_DELAY. (Until
--                                  2026-11-04 the reader started as soon as the out-FIFO held
--                                  G_DELAY words, which the unblocked Amiga wrote faster than the
--                                  backlog was thrown away: the rest of the backlog stayed, the
--                                  latency grew with every underflow, until the out-FIFO was
--                                  full and the in-FIFO overflowed - R6 test r6rb-o.)
--
-- So in the steady state in-level + out-level = G_DELAY: when the Amiga is fast the in-FIFO is
-- empty and the out-FIFO holds G_DELAY words; a stretch of slow memory moves words from the one to
-- the other, and the Amiga's spare speed moves them back.
--
-- The gate: open while the in-FIFO has a word for the next edge, the out-FIFO has room for it and
-- the chip RAM (chip_hr's go, registered) allows it. Every rb_clk process that talks to the Amiga
-- follows the boundary rule (experiment 7): it samples the Amiga's outputs, and changes its
-- inputs, only at edges the Amiga takes (gate_o = '1' at that edge, a_edge_o).
--
-- Reset: while rb_rst_i and for 16 Amiga edges after it the gate is open and a_rst_o is high, so
-- the Amiga's synchronous resets see edges.
--
-- With G_RB = false everything is a wire: a_in_o = rt_in_i, rt_out_o = a_out_i, gate_o = '1',
-- a_rst_o = main_rst_i (amiga_clk is main_clk then).
--
-- Done in 2026 (Megamiga, fork of AExp) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

entity rb_bridge is
   generic (
      G_RB         : boolean := false;
      G_IN_W       : natural;                       -- real-time input word
      G_OUT_W      : natural;                       -- real-time output word
      G_DELAY      : natural := 2048;               -- output delay in clocks (the lag budget)
      G_DEPTH_LOG2 : natural := 12                  -- both FIFOs: 2**12 words
   );
   port (
      main_clk_i   : in  std_logic;                 -- real time
      main_rst_i   : in  std_logic;
      rb_clk_i     : in  std_logic;                 -- free running, the Amiga's ungated clock
      rb_rst_i     : in  std_logic;

      gate_o       : out std_logic;                 -- BUFGCE CE of the Amiga's clock
      a_edge_o     : out std_logic;                 -- = gate_o: the Amiga takes this rb_clk edge
      a_rst_o      : out std_logic;                 -- the Amiga's reset (rb_clk register)
      chip_go_i    : in  std_logic := '1';          -- chip_hr: the Amiga may take the next edge

      rt_in_i      : in  std_logic_vector(G_IN_W - 1 downto 0);   -- main_clk
      a_in_o       : out std_logic_vector(G_IN_W - 1 downto 0);   -- Amiga time
      a_out_i      : in  std_logic_vector(G_OUT_W - 1 downto 0);  -- Amiga time
      rt_out_o     : out std_logic_vector(G_OUT_W - 1 downto 0);  -- main_clk
      rt_valid_o   : out std_logic;                 -- main_clk: rt_out_o is a replayed word

      -- statistics (main_clk): underflows since reset, the lowest out-FIFO level while reading
      rt_under_o   : out unsigned(15 downto 0);
      rt_minlvl_o  : out unsigned(G_DEPTH_LOG2 downto 0);
      -- statistics (rb_clk): the largest lag of the Amiga behind real time (in clocks; an underflow
      -- happens when it passes G_DELAY): the in-FIFO level, plus, while the reader waits after an
      -- underflow, the words discarded since then (the lag the Amiga would have without the
      -- re-prime: the lead it would have needed); rb_lagclr_i = '1' starts a new maximum
      rb_lagmax_o  : out unsigned(23 downto 0);
      rb_lagclr_i  : in  std_logic := '0'
   );
end entity rb_bridge;

architecture synthesis of rb_bridge is
begin

   g_wire : if not G_RB generate
      gate_o      <= '1';
      a_edge_o    <= '1';
      a_rst_o     <= main_rst_i;
      a_in_o      <= rt_in_i;
      rt_out_o    <= a_out_i;
      rt_valid_o  <= '1';
      rt_under_o  <= (others => '0');
      rt_minlvl_o <= (others => '0');
      rb_lagmax_o <= (others => '0');
   end generate g_wire;

   g_band : if G_RB generate
      constant C_DEPTH : natural := 2 ** G_DEPTH_LOG2;

      -- in-FIFO
      signal i_wr_busy  : std_logic;
      signal i_rd_busy  : std_logic;
      signal i_full     : std_logic;
      signal i_empty    : std_logic;
      signal i_wr_en    : std_logic;
      signal i_rd_en    : std_logic;
      signal i_rd_count : std_logic_vector(G_DEPTH_LOG2 downto 0);
      signal i_wr_count : std_logic_vector(G_DEPTH_LOG2 downto 0);   -- (main_clk)
      signal i_dout     : std_logic_vector(G_IN_W - 1 downto 0);

      -- out-FIFO
      signal o_wr_busy  : std_logic;
      signal o_rd_busy  : std_logic;
      signal o_full     : std_logic;
      signal o_empty    : std_logic;
      signal o_wr_en    : std_logic;
      signal o_rd_en    : std_logic;
      signal o_wr_count : std_logic_vector(G_DEPTH_LOG2 downto 0);
      signal o_rd_count : std_logic_vector(G_DEPTH_LOG2 downto 0);
      signal o_dout     : std_logic_vector(G_OUT_W - 1 downto 0);

      -- the gate (rb_clk)
      type t_state is (S_RST, S_RUN);
      signal state      : t_state := S_RST;
      signal rst_edges  : unsigned(4 downto 0) := (others => '0');
      signal pace_ok    : std_logic := '0';
      signal gate       : std_logic;
      signal gate_d     : std_logic := '0';
      signal a_rst      : std_logic := '1';
      signal prime_m    : std_logic := '1';             -- the reader waits (2 flops from main_clk)
      signal prime_s    : std_logic := '1';
      signal discard    : std_logic;
      attribute async_reg : string;
      attribute async_reg of prime_m : signal is "true";
      attribute async_reg of prime_s : signal is "true";

      -- the reader (main_clk)
      signal reading    : std_logic := '0';
      signal out_r      : std_logic_vector(G_OUT_W - 1 downto 0) := (others => '0');
      signal valid_r    : std_logic := '0';
      signal under      : unsigned(15 downto 0) := (others => '0');
      signal minlvl     : unsigned(G_DEPTH_LOG2 downto 0) := (others => '1');
      signal lagmax     : unsigned(23 downto 0) := (others => '0');
      signal disc_n     : unsigned(23 downto 0) := (others => '0');   -- discarded in this re-prime
      signal vlag       : unsigned(23 downto 0) := (others => '0');

   begin

      -------------------------------------------------------------------------------------------
      -- the gate
      -------------------------------------------------------------------------------------------

      gate     <= '1' when state = S_RST else pace_ok and chip_go_i;
      gate_o   <= gate;
      a_edge_o <= gate;
      a_rst_o  <= a_rst;

      p_gate : process (rb_clk_i)
      begin
         if rising_edge(rb_clk_i) then
            gate_d  <= gate;
            -- the virtual lag (registered: a clock late, which does not matter for a maximum): a
            -- discarded word counts while chip_go_i holds the Amiga, not while only the pace does
            -- (the Amiga would have taken that word)
            if prime_s = '0' then
               disc_n <= (others => '0');
            elsif discard = '1' and gate = '0' and chip_go_i = '0' and i_empty = '0' and
                  state = S_RUN and disc_n /= x"FFFFFF" then
               disc_n <= disc_n + 1;
            end if;
            if i_rd_busy = '0' then
               vlag <= resize(unsigned(i_rd_count), 24) + disc_n;
            end if;
            if rb_lagclr_i = '1' then
               lagmax <= (others => '0');
            elsif state = S_RUN and vlag > lagmax then
               lagmax <= vlag;
            end if;
            prime_m <= not reading;
            prime_s <= prime_m;
            -- room for the next edge: the level counts lag the pops by a clock or two, hence
            -- the margins (an edge at this clock and one at the next must both find a word)
            -- (while the reader waits the out-FIFO is filled only up to G_DELAY: the latency after
            -- the restart is G_DELAY; the 8 words cover the edges in flight)
            if unsigned(i_rd_count) >= 4 and i_rd_busy = '0' and o_wr_busy = '0' and
               ((prime_s = '0' and unsigned(o_wr_count) < C_DEPTH - 16) or
                (prime_s = '1' and unsigned(o_wr_count) < G_DELAY + 8)) then
               pace_ok <= '1';
            else
               pace_ok <= '0';
            end if;

            case state is
               when S_RST =>
                  a_rst <= '1';
                  if rst_edges /= 16 then
                     rst_edges <= rst_edges + 1;
                  elsif i_rd_busy = '0' and o_wr_busy = '0' then
                     state <= S_RUN;
                     a_rst <= '0';
                  end if;
               when S_RUN =>
                  null;
            end case;

            if rb_rst_i = '1' then
               state     <= S_RST;
               rst_edges <= (others => '0');
               a_rst     <= '1';
               pace_ok   <= '0';
               lagmax    <= (others => '0');
            end if;
         end if;
      end process p_gate;

      -------------------------------------------------------------------------------------------
      -- in-FIFO: one word per real-time clock in, one per Amiga edge out
      -------------------------------------------------------------------------------------------

      i_wr_en <= not i_wr_busy and not i_full;
      -- one word per Amiga edge; while the reader waits after an underflow, also the backlog
      -- beyond a few words (the gate needs 4)
      discard <= '1' when prime_s = '1' and unsigned(i_rd_count) > 8 else '0';
      i_rd_en <= (gate or discard) and not i_empty when state = S_RUN else '0';
      a_in_o  <= i_dout;

      i_in_fifo : xpm_fifo_async
         generic map (
            CDC_SYNC_STAGES     => 2,
            DOUT_RESET_VALUE    => "0",
            ECC_MODE            => "no_ecc",
            FIFO_MEMORY_TYPE    => "block",
            FIFO_READ_LATENCY   => 0,
            FIFO_WRITE_DEPTH    => C_DEPTH,
            FULL_RESET_VALUE    => 0,
            PROG_EMPTY_THRESH   => 10,
            PROG_FULL_THRESH    => 10,
            RD_DATA_COUNT_WIDTH => G_DEPTH_LOG2 + 1,
            READ_DATA_WIDTH     => G_IN_W,
            READ_MODE           => "fwft",
            RELATED_CLOCKS      => 0,
            SIM_ASSERT_CHK      => 0,
            USE_ADV_FEATURES    => "0404",          -- rd_data_count, wr_data_count
            WAKEUP_TIME         => 0,
            WRITE_DATA_WIDTH    => G_IN_W,
            WR_DATA_COUNT_WIDTH => G_DEPTH_LOG2 + 1
         )
         port map (
            rst           => main_rst_i,
            wr_clk        => main_clk_i,
            wr_en         => i_wr_en,
            din           => rt_in_i,
            full          => i_full,
            wr_rst_busy   => i_wr_busy,
            rd_clk        => rb_clk_i,
            rd_en         => i_rd_en,
            dout          => i_dout,
            empty         => i_empty,
            rd_data_count => i_rd_count,
            rd_rst_busy   => i_rd_busy,
            injectdbiterr => '0',
            injectsbiterr => '0',
            sleep         => '0',
            almost_empty  => open,
            almost_full   => open,
            data_valid    => open,
            dbiterr       => open,
            overflow      => open,
            prog_empty    => open,
            prog_full     => open,
            sbiterr       => open,
            underflow     => open,
            wr_ack        => open,
            wr_data_count => i_wr_count
         ); -- i_in_fifo

      -------------------------------------------------------------------------------------------
      -- out-FIFO: one word per Amiga edge in (sampled at the next rb_clk edge, after the Amiga's
      -- registers have taken their new values), one per real-time clock out
      -------------------------------------------------------------------------------------------

      o_wr_en <= gate_d and not o_full and not o_wr_busy when state = S_RUN else '0';

      i_out_fifo : xpm_fifo_async
         generic map (
            CDC_SYNC_STAGES     => 2,
            DOUT_RESET_VALUE    => "0",
            ECC_MODE            => "no_ecc",
            FIFO_MEMORY_TYPE    => "block",
            FIFO_READ_LATENCY   => 0,
            FIFO_WRITE_DEPTH    => C_DEPTH,
            FULL_RESET_VALUE    => 0,
            PROG_EMPTY_THRESH   => 10,
            PROG_FULL_THRESH    => 10,
            RD_DATA_COUNT_WIDTH => G_DEPTH_LOG2 + 1,
            READ_DATA_WIDTH     => G_OUT_W,
            READ_MODE           => "fwft",
            RELATED_CLOCKS      => 0,
            SIM_ASSERT_CHK      => 0,
            USE_ADV_FEATURES    => "0404",          -- rd_data_count, wr_data_count
            WAKEUP_TIME         => 0,
            WRITE_DATA_WIDTH    => G_OUT_W,
            WR_DATA_COUNT_WIDTH => G_DEPTH_LOG2 + 1
         )
         port map (
            rst           => rb_rst_i,
            wr_clk        => rb_clk_i,
            wr_en         => o_wr_en,
            din           => a_out_i,
            full          => o_full,
            wr_rst_busy   => o_wr_busy,
            wr_data_count => o_wr_count,
            rd_clk        => main_clk_i,
            rd_en         => o_rd_en,
            dout          => o_dout,
            empty         => o_empty,
            rd_data_count => o_rd_count,
            rd_rst_busy   => o_rd_busy,
            injectdbiterr => '0',
            injectsbiterr => '0',
            sleep         => '0',
            almost_empty  => open,
            almost_full   => open,
            data_valid    => open,
            dbiterr       => open,
            overflow      => open,
            prog_empty    => open,
            prog_full     => open,
            sbiterr       => open,
            underflow     => open,
            wr_ack        => open
         ); -- i_out_fifo

      -------------------------------------------------------------------------------------------
      -- the real-time reader
      -------------------------------------------------------------------------------------------

      o_rd_en <= reading and not o_empty;

      p_read : process (main_clk_i)
      begin
         if rising_edge(main_clk_i) then
            valid_r <= o_rd_en;
            if o_rd_en = '1' then
               out_r <= o_dout;
            end if;
            if reading = '0' then
               -- the out-FIFO holds G_DELAY words and the in-FIFO's backlog is gone
               if o_rd_busy = '0' and unsigned(o_rd_count) >= G_DELAY and
                  i_wr_busy = '0' and unsigned(i_wr_count) <= 16 then
                  reading <= '1';
               end if;
            else
               if o_empty = '1' then                -- the Amiga is G_DELAY clocks behind
                  reading <= '0';
                  under   <= under + 1;
               elsif unsigned(o_rd_count) < minlvl then
                  minlvl  <= unsigned(o_rd_count);
               end if;
            end if;
            if main_rst_i = '1' then
               reading <= '0';
               valid_r <= '0';
               under   <= (others => '0');
               minlvl  <= (others => '1');
            end if;
         end if;
      end process p_read;

      rt_out_o    <= out_r;
      rt_valid_o  <= valid_r;
      rt_under_o  <= under;
      rt_minlvl_o <= minlvl;
      rb_lagmax_o <= lagmax;
   end generate g_band;

end architecture synthesis;
