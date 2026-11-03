---------------------------------------------------------------------------------------------------------
-- Megamiga (Amiga for MEGA65, fork of AExp)
--
-- chip_hr: chip RAM in HyperRAM for a PAUSABLE Amiga (rubber banding, doc/developers/rubber-band.md).
-- EXPERIMENTAL: not in any build yet, verified in the pause bench (~/aexp-work/pause).
--
-- The Amiga (Minimig + CPU) runs on a gated copy of this module's clock: it takes an edge only
-- while the gate (BUFGCE CE) is high. a_edge_i tells this module, at every clock edge, whether the
-- Amiga takes that edge too. go_o (registered) says whether it may take the NEXT one.
--
-- Chipset port (minimig_sram_bridge.v): an access appears after an Amiga edge k; this module sees it
-- at its next clock edge. The read data must be there for Amiga edge k+2 (measured: Minimig latches
-- its RAM data two clocks after the address). So edge k+1 may happen at once (the one clock of
-- notice), edge k+2 only when the word is in place: ram_data_o comes from the cache's read port,
-- which reads the current address at every clock edge.
--
-- Cache: 4-way set associative, 2**G_SET_BITS sets, 16-word lines (one HyperRAM burst), round-robin
-- replacement; the data in four 16-bit lanes (word address bits 2:1), so one read gives the aligned
-- 64-bit group for AGA's fetch modes (chip48_o, sdram_ctrl.v's burst order). A hit costs nothing; a
-- miss fetches the line (the Amiga waits until the whole line is in). Tags in LUT RAM, compared in
-- the clock the address is seen.
--
-- Writes: posted into two write-combining buffers of one line each (byte enables per word); a write
-- to the buffered line merges, a write to another line hands the buffer over to be flushed as one
-- burst and takes the other buffer; the Amiga waits only when both are busy. A write to a cached
-- line also updates the cache. Before a line fill, the buffers are flushed (the Avalon path keeps the
-- order, so the fill sees every earlier write).
--
-- HyperRAM: chip word address w (ram_addr_i(22:1)) is HyperRAM word G_BASE_WORD + w.
--
-- Done in 2026 (Megamiga, fork of AExp) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity chip_hr is
   generic (
      G_SET_BITS   : natural := 7;                 -- 128 sets x 4 ways x 16 words = 16 KB
      G_BASE_WORD  : natural := 0
   );
   port (
      clk_i          : in  std_logic;              -- the ungated clock
      rst_i          : in  std_logic;
      a_edge_i       : in  std_logic;              -- the Amiga takes this clock edge too
      go_o           : out std_logic;              -- the Amiga may take the next edge

      -- chipset port (outputs of the gated Amiga domain)
      ram_addr_i     : in  std_logic_vector(22 downto 1);
      ram_data_i     : in  std_logic_vector(15 downto 0);
      ram_bhe_n_i    : in  std_logic;
      ram_ble_n_i    : in  std_logic;
      ram_we_n_i     : in  std_logic;
      ram_oe_n_i     : in  std_logic;
      ram_data_o     : out std_logic_vector(15 downto 0);
      chip48_o       : out std_logic_vector(47 downto 0);

      -- HyperRAM: Avalon master (16-bit words)
      avm_write_o         : out std_logic;
      avm_read_o          : out std_logic;
      avm_address_o       : out std_logic_vector(31 downto 0);
      avm_writedata_o     : out std_logic_vector(15 downto 0);
      avm_byteenable_o    : out std_logic_vector( 1 downto 0);
      avm_burstcount_o    : out std_logic_vector( 7 downto 0);
      avm_readdata_i      : in  std_logic_vector(15 downto 0);
      avm_readdatavalid_i : in  std_logic;
      avm_waitrequest_i   : in  std_logic;

      -- statistics
      n_read_o       : out unsigned(31 downto 0);
      n_miss_o       : out unsigned(31 downto 0);
      n_flush_o      : out unsigned(31 downto 0)
   );
end entity chip_hr;

architecture synthesis of chip_hr is

   constant C_SETS  : natural := 2 ** G_SET_BITS;
   constant C_TAGW  : natural := 22 - 4 - G_SET_BITS;      -- word address bits above set + offset
   constant C_DEPTH : natural := 4 * C_SETS * 4;            -- per lane: way, set, word bits 3:2

   type t_tags is array (0 to 4 * C_SETS - 1) of std_logic_vector(C_TAGW downto 0);   -- valid & tag
   signal tags : t_tags := (others => (others => '0'));
   type t_rr is array (0 to C_SETS - 1) of unsigned(1 downto 0);
   signal rr   : t_rr := (others => "00");

   type t_lane is array (0 to C_DEPTH - 1) of std_logic_vector(7 downto 0);
   type t_q is array (0 to 7) of std_logic_vector(7 downto 0);
   signal c_q   : t_q;
   signal c_we  : std_logic_vector(7 downto 0) := (others => '0');   -- lane*2 + 1 = high byte
   signal c_wa  : natural range 0 to C_DEPTH - 1 := 0;
   signal c_wd  : std_logic_vector(15 downto 0) := (others => '0');
   signal c_ra  : natural range 0 to C_DEPTH - 1;
   signal lane_r : unsigned(1 downto 0) := "00";

   -- the current access
   signal set_i  : natural range 0 to C_SETS - 1;
   signal tag_i  : std_logic_vector(C_TAGW - 1 downto 0);
   signal hit    : std_logic;
   signal hway   : unsigned(1 downto 0);
   signal acc    : std_logic;                               -- oe or we low
   signal acc_d  : std_logic := '0';
   signal addr_d : std_logic_vector(22 downto 1) := (others => '0');
   signal rd_d   : std_logic := '0';
   signal new_acc : std_logic;

   signal edge1  : std_logic := '0';                        -- the access has had its edge k+1
   signal wtaken : std_logic := '1';                        -- the current write is in a buffer
   signal go     : std_logic := '1';

   -- write-combining buffers
   -- buffer b: wb_used(b), wb_line(b), word w at wb_data(16 b + w), its byte enables at
   -- wb_be(32 b + 2 w + 1) (high byte) and wb_be(32 b + 2 w) (low byte)
   type t_wdata is array (0 to 31) of std_logic_vector(15 downto 0);
   type t_wline is array (0 to 1) of std_logic_vector(22 downto 5);
   signal wb_used : std_logic_vector(1 downto 0) := "00";
   signal wb_line : t_wline := (others => (others => '0'));
   signal wb_be   : std_logic_vector(63 downto 0) := (others => '0');
   signal wb_data : t_wdata := (others => (others => '0'));
   signal wa     : natural range 0 to 1 := 0;               -- the buffer that collects
   signal fl     : std_logic := '0';                        -- the other one is being flushed
   signal fl_q   : std_logic := '0';                        -- a flush is queued for it

   -- the Avalon master
   type t_mstate is (M_IDLE, M_WR, M_RD, M_RDATA);
   signal mstate : t_mstate := M_IDLE;
   signal m_idx  : unsigned(3 downto 0) := (others => '0');
   signal m_buf  : natural range 0 to 1 := 0;
   signal f_set  : natural range 0 to C_SETS - 1 := 0;
   signal f_way  : unsigned(1 downto 0) := "00";
   signal f_line : std_logic_vector(22 downto 5) := (others => '0');
   signal f_req  : std_logic := '0';                        -- a fill is wanted
   signal f_done : std_logic := '0';
   signal avm_write : std_logic := '0';
   signal avm_read  : std_logic := '0';

   signal n_read, n_miss, n_flush, n_write : unsigned(31 downto 0) := (others => '0');

begin

   go_o <= go;
   avm_write_o <= avm_write;
   avm_read_o  <= avm_read;
   n_read_o <= n_read; n_miss_o <= n_miss; n_flush_o <= n_flush;

   acc   <= not (ram_oe_n_i and ram_we_n_i);
   set_i <= to_integer(unsigned(ram_addr_i(4 + G_SET_BITS downto 5)));
   tag_i <= ram_addr_i(22 downto 5 + G_SET_BITS);
   new_acc <= '1' when acc = '1' and (acc_d = '0' or ram_addr_i /= addr_d or
                                      rd_d /= not ram_oe_n_i) else '0';

   p_hit : process (all)
   begin
      hit  <= '0';
      hway <= "00";
      for w in 0 to 3 loop
         if tags(w * C_SETS + set_i) = '1' & tag_i then
            hit  <= '1';
            hway <= to_unsigned(w, 2);
         end if;
      end loop;
   end process p_hit;

   -- cache read port: the current address, every clock (the data of a hit is there one clock later)
   c_ra <= to_integer(hway & to_unsigned(set_i, G_SET_BITS) & unsigned(ram_addr_i(4 downto 3)));

   g_lanes : for i in 0 to 7 generate
      signal mem : t_lane := (others => (others => '0'));
      attribute ram_style : string;
      attribute ram_style of mem : signal is "block";
   begin
      process (clk_i)
      begin
         if rising_edge(clk_i) then
            if c_we(i) = '1' then
               if i mod 2 = 1 then mem(c_wa) <= c_wd(15 downto 8); else mem(c_wa) <= c_wd(7 downto 0); end if;
            end if;
            c_q(i) <= mem(c_ra);
         end if;
      end process;
   end generate g_lanes;

   p_out : process (all)
      type t_w4 is array (0 to 3) of std_logic_vector(15 downto 0);
      variable v_w : t_w4;
   begin
      for k in 0 to 3 loop
         v_w(k) := c_q(2 * k + 1) & c_q(2 * k);
      end loop;
      ram_data_o <= v_w(to_integer(lane_r));
      chip48_o   <= v_w(to_integer(lane_r + 1)) & v_w(to_integer(lane_r + 2)) & v_w(to_integer(lane_r + 3));
   end process p_out;

   p_main : process (clk_i)
      variable v_line : std_logic_vector(22 downto 5);
      variable v_w    : natural range 0 to 15;
      variable v_lane : natural range 0 to 3;
      variable v_e1   : std_logic;                          -- edge k+1 has happened (after this edge)
      variable v_wr   : boolean;                            -- a write to take in this clock
      variable v_tk   : boolean;                            -- ... and it is taken
      variable v_cw   : boolean;                            -- the cache port is used by a write
   begin
      if rising_edge(clk_i) then
         c_we   <= (others => '0');
         lane_r <= unsigned(ram_addr_i(2 downto 1));
         acc_d  <= acc;
         addr_d <= ram_addr_i;
         rd_d   <= not ram_oe_n_i;
         v_line := ram_addr_i(22 downto 5);
         v_w    := to_integer(unsigned(ram_addr_i(4 downto 1)));
         v_lane := to_integer(unsigned(ram_addr_i(2 downto 1)));
         v_cw   := false;

         -- edge k+1: the access was produced by an Amiga edge before this clock edge, so the
         -- first Amiga edge after it is its k+1 (always allowed)
         if new_acc = '1' then
            v_e1 := a_edge_i;
         else
            v_e1 := edge1 or a_edge_i;
         end if;
         if acc = '1' then edge1 <= v_e1; else edge1 <= '0'; end if;

         -------------------------------------------------------------------------------
         -- reads: a miss asks for its line (once per access)
         -------------------------------------------------------------------------------
         if new_acc = '1' and ram_oe_n_i = '0' then
            n_read <= n_read + 1;
            if hit = '0' then
               n_miss <= n_miss + 1;
               f_req  <= '1';
               f_set  <= set_i;
               f_line <= v_line;
               f_way  <= rr(set_i);
               rr(set_i) <= rr(set_i) + 1;
            end if;
         end if;

         -------------------------------------------------------------------------------
         -- writes: into the collecting buffer (same line or empty), else hand it over
         -------------------------------------------------------------------------------
         v_wr := ram_we_n_i = '0' and (new_acc = '1' or wtaken = '0');
         v_tk := false;
         if new_acc = '1' then wtaken <= '0'; end if;
         if v_wr then
            if wb_used(wa) = '0' then
               v_tk := true;
               wb_used(wa) <= '1';
               wb_line(wa) <= v_line;
               for i in 0 to 31 loop
                  wb_be(32 * wa + i) <= '0';
               end loop;
               wb_be(32 * wa + 2 * v_w + 1) <= not ram_bhe_n_i;
               wb_be(32 * wa + 2 * v_w)     <= not ram_ble_n_i;
            elsif wb_line(wa) = v_line then
               v_tk := true;
               if ram_bhe_n_i = '0' then wb_be(32 * wa + 2 * v_w + 1) <= '1'; end if;
               if ram_ble_n_i = '0' then wb_be(32 * wa + 2 * v_w) <= '1'; end if;
            elsif fl = '0' and fl_q = '0' then
               fl_q  <= '1';                                -- hand it over; take next clock
               m_buf <= wa;
               wa    <= 1 - wa;
            end if;
            if v_tk then
               wtaken <= '1';
               n_write <= n_write + 1;
               if ram_bhe_n_i = '0' then wb_data(16 * wa + v_w)(15 downto 8) <= ram_data_i(15 downto 8); end if;
               if ram_ble_n_i = '0' then wb_data(16 * wa + v_w)(7 downto 0)  <= ram_data_i(7 downto 0);  end if;
               if hit = '1' then                            -- keep a cached line current
                  v_cw := true;
                  c_wa <= to_integer(hway & to_unsigned(set_i, G_SET_BITS) & unsigned(ram_addr_i(4 downto 3)));
                  c_wd <= ram_data_i;
                  c_we(2 * v_lane + 1) <= not ram_bhe_n_i;
                  c_we(2 * v_lane)     <= not ram_ble_n_i;
               end if;
            end if;
         end if;

         -------------------------------------------------------------------------------
         -- the Avalon master: flushes first, then fills (a fill flushes the collecting buffer)
         -------------------------------------------------------------------------------
         case mstate is
            when M_IDLE =>
               if fl_q = '1' then
                  fl_q <= '0'; fl <= '1';
                  m_idx <= (others => '0');
                  avm_address_o    <= std_logic_vector(to_unsigned(G_BASE_WORD, 32) +
                                      unsigned(std_logic_vector'(wb_line(m_buf) & "0000")));
                  avm_burstcount_o <= x"10";
                  avm_writedata_o  <= wb_data(16 * m_buf);
                  avm_byteenable_o <= wb_be(32 * m_buf + 1) & wb_be(32 * m_buf);
                  avm_write        <= '1';
                  n_flush <= n_flush + 1;
                  mstate <= M_WR;
               elsif f_req = '1' and wb_used(wa) = '1' then
                  if not v_wr then                          -- (a write takes the buffer first)
                     fl_q <= '1'; m_buf <= wa; wa <= 1 - wa;
                  end if;
               elsif f_req = '1' then
                  f_req <= '0';
                  m_idx <= (others => '0');
                  avm_address_o    <= std_logic_vector(to_unsigned(G_BASE_WORD, 32) + unsigned(std_logic_vector'(f_line & "0000")));
                  avm_burstcount_o <= x"10";
                  avm_read         <= '1';
                  tags(to_integer(f_way) * C_SETS + f_set)(C_TAGW) <= '0';   -- invalid while filling
                  mstate <= M_RD;
               end if;

            when M_WR =>
               if avm_waitrequest_i = '0' then
                  if m_idx = 15 then
                     avm_write <= '0';
                     wb_used(m_buf) <= '0';
                     fl <= '0';
                     mstate <= M_IDLE;
                  else
                     m_idx <= m_idx + 1;
                     avm_writedata_o  <= wb_data(16 * m_buf + to_integer(m_idx + 1));
                     avm_byteenable_o <= wb_be(32 * m_buf + 2 * to_integer(m_idx + 1) + 1) & wb_be(32 * m_buf + 2 * to_integer(m_idx + 1));
                  end if;
               end if;

            when M_RD | M_RDATA =>
               if mstate = M_RD and avm_waitrequest_i = '0' then
                  avm_read <= '0';
                  mstate   <= M_RDATA;
               end if;
               if avm_readdatavalid_i = '1' then
                  assert not v_cw report "chip_hr: a write and a fill want the cache port" severity failure;
                  c_wa <= to_integer(f_way & to_unsigned(f_set, G_SET_BITS) & m_idx(3 downto 2));
                  c_wd <= avm_readdata_i;
                  c_we <= (others => '0');
                  c_we(2 * to_integer(m_idx(1 downto 0)) + 1) <= '1';
                  c_we(2 * to_integer(m_idx(1 downto 0)))     <= '1';
                  m_idx <= m_idx + 1;
                  if m_idx = 15 then
                     f_done <= '1';
                     mstate <= M_IDLE;
                  end if;
               end if;
         end case;

         -- the filled line becomes valid once its last word is in the cache RAM (the write is
         -- registered); a read of it hits from then on
         if f_done = '1' then
            f_done <= '0';
            tags(to_integer(f_way) * C_SETS + f_set) <= '1' & f_line(22 downto 5 + G_SET_BITS);
         end if;

         -------------------------------------------------------------------------------
         -- the gate for the next Amiga edge: a read whose line is not in the cache may not see
         -- its k+2; a write that found no buffer waits
         -------------------------------------------------------------------------------
         go <= '1';
         if acc = '1' and ram_oe_n_i = '0' and hit = '0' and v_e1 = '1' then
            go <= '0';
         end if;
         if v_wr and not v_tk then
            go <= '0';
         end if;

         if rst_i = '1' then
            mstate <= M_IDLE; avm_write <= '0'; avm_read <= '0';
            edge1 <= '0'; go <= '1'; wtaken <= '1';
            f_req <= '0'; f_done <= '0'; fl <= '0'; fl_q <= '0';
            wb_used <= "00";
         end if;
      end if;
   end process p_main;

end architecture synthesis;
