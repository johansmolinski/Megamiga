---------------------------------------------------------------------------------------------------------
-- Megamiga (Amiga for MEGA65, fork of AExp)
--
-- chip_hr: chip RAM in HyperRAM for a PAUSABLE Amiga (rubber banding, doc/developers/rubber-band.md).
-- Verified in the pause bench (~/aexp-work/pause); used by the R3 build with rubber banding (mega65.vhd C_RB).
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
-- Prefetch (2026-11-04: on the R6 test a miss cost ~1 us and bursts of them made the Amiga fall
-- behind real time): tagged next-line prefetch. A demand miss of line N also asks for N+1; a line
-- brought in by a prefetch carries a bit, and its first read clears it and asks for the next line -
-- so a sequential stream (bitplanes, blitter, copper) stays one line ahead and the Amiga does not
-- wait for it. A prefetch runs while the Amiga runs. Rules that keep the cache coherent with that:
--   * one fill at a time (demand first, then a queued write-back, then the prefetch);
--   * a line is fetched only if it is neither cached (a second tag lookup) nor in a write buffer;
--     a read of the line that is being filled waits for that fill (never two copies of a line);
--   * a write to the line that is being filled makes the fill stale: it is not validated, and a
--     read that waits for it asks again (and the write is flushed first, see below);
--   * a write that would update the cache in the clock a fill word is written waits one clock.
-- Timing: the chipset address arrives late in the clock (Agnus' address generator), so no write to
-- the tags or prefetch bits depends on the current access - only on registers (r6rb-k/l: the first
-- prefetch version had such paths and missed timing by 2.4 ns).
--
-- Writes: posted into two write-combining buffers of one line each (byte enables per word); a write
-- to the buffered line merges, a write to another line hands the buffer over to be flushed as one
-- burst and takes the other buffer; the Amiga waits only when both are busy. A write to a cached
-- line also updates the cache. A line fill goes before queued write-backs unless a buffer holds its
-- own line; then that buffer is flushed first (the Avalon path keeps the order, so the fill sees the
-- write). (Until 2026-11-04 every fill waited for both buffers.)
--
-- Second level (2026-11-05): 4-way, 2**G_L2_BITS sets x 16-word lines (10 = 128 KB), in block RAM,
-- its tags in LUT RAM read only at registered addresses (the fill's line, the flushed line): a
-- first-level miss looks the line up there first (M_L2) and copies it in four 64-bit groups (M_L2C,
-- ~6 clocks) instead of reading HyperRAM (~1 us); a line from HyperRAM goes into both levels. The
-- first level stays 16 KB: its tag lookup is in the clock the chipset address arrives, and a
-- 128 KB first level missed timing there (r6rb-u/-v/-w: the 1024-deep tag RAM). Workbench's line
-- blits miss on every pixel, and the bitplane stream pushes those rows out of 16 KB (rubber-band.md).
-- The second level is updated by the write-backs (a flush writes the words it sends into the
-- line if the second level holds it); a fill never reads a line a write buffer holds (it is
-- flushed first), so neither level is ever older than HyperRAM plus the buffers.
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
      G_L2_BITS    : natural := 10;                -- second level: 1024 sets x 4 ways = 128 KB
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
      n_flush_o      : out unsigned(31 downto 0);
      n_pf_o         : out unsigned(31 downto 0);   -- prefetches issued
      n_pfhit_o      : out unsigned(31 downto 0);   -- prefetched lines that were read
      n_l2hit_o      : out unsigned(31 downto 0)    -- first-level fills from the second level
   );
end entity chip_hr;

architecture synthesis of chip_hr is

   constant C_SETS  : natural := 2 ** G_SET_BITS;
   constant C_TAGW  : natural := 22 - 4 - G_SET_BITS;      -- word address bits above set + offset
   constant C_DEPTH : natural := 4 * C_SETS * 4;            -- per lane: way, set, word bits 3:2

   -- tags: one LUT RAM per way (valid & tag), ONE write address (f_way, f_set) and two read
   -- addresses (the current access, the prefetch); two write addresses made Vivado build them
   -- from 6144 flip-flops and ~20K LUTs (r6rb-k/l, 2026-11-04: unroutable, WNS -2.4 ns)
   type t_tagm is array (0 to C_SETS - 1) of std_logic_vector(C_TAGW downto 0);
   type t_tq is array (0 to 3) of std_logic_vector(C_TAGW downto 0);
   signal tq_i  : t_tq;                                      -- the ways at set_i
   signal tq_p  : t_tq;                                      -- the ways at pq_set
   signal t_we  : std_logic;                                 -- write tag (f_way, f_set) := f_done & f_line
   signal iss_d : std_logic := '0';                          -- a fill was issued in the last clock
   type t_rr is array (0 to C_SETS - 1) of unsigned(1 downto 0);
   signal rr   : t_rr := (others => "00");

   type t_lane is array (0 to C_DEPTH - 1) of std_logic_vector(7 downto 0);
   type t_q is array (0 to 7) of std_logic_vector(7 downto 0);
   signal c_q   : t_q;
   signal c_we  : std_logic_vector(7 downto 0) := (others => '0');   -- lane*2 + 1 = high byte
   signal c_wa  : natural range 0 to C_DEPTH - 1 := 0;
   signal c_wd  : std_logic_vector(63 downto 0) := (others => '0');   -- lane i: bits 8i+7..8i
   signal c_ra  : natural range 0 to C_DEPTH - 1;
   signal lane_r : unsigned(1 downto 0) := "00";
   signal c48_now : std_logic_vector(47 downto 0);           -- the group's other words, this clock
   signal c48_q   : std_logic_vector(47 downto 0) := (others => '0');
   signal c48_ld  : std_logic := '0';                       -- the current read has loaded chip48

   -- the current access
   signal set_i  : natural range 0 to C_SETS - 1;
   signal tag_i  : std_logic_vector(C_TAGW - 1 downto 0);
   signal hit    : std_logic;
   signal hway   : unsigned(1 downto 0);
   signal hit_d  : std_logic := '0';                        -- hit in the last clock
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
   type t_mstate is (M_IDLE, M_WR, M_RD, M_RDATA, M_L2, M_L2C);
   signal mstate : t_mstate := M_IDLE;
   signal m_idx  : unsigned(3 downto 0) := (others => '0');
   signal m_buf  : natural range 0 to 1 := 0;
   signal f_set  : natural range 0 to C_SETS - 1 := 0;
   signal f_way  : unsigned(1 downto 0) := "00";
   signal f_line : std_logic_vector(22 downto 5) := (others => '0');
   signal f_done : std_logic := '0';
   signal f_busy : std_logic := '0';                        -- a fill is issued, its tag not yet written
   signal f_pf   : std_logic := '0';                        -- ... and it is a prefetch
   signal f_dirty : std_logic := '0';                       -- ... and a write hit its line meanwhile
   signal dq_req  : std_logic := '0';                       -- a demand fill is wanted
   signal dq_line : std_logic_vector(22 downto 5) := (others => '0');
   signal pq_req  : std_logic := '0';                       -- a prefetch is wanted
   signal pq_line : std_logic_vector(22 downto 5) := (others => '0');
   signal pq_set  : natural range 0 to C_SETS - 1;
   signal pq_tag  : std_logic_vector(C_TAGW - 1 downto 0);
   signal pq_hit  : std_logic;                              -- pq_line is cached
   signal pfb     : std_logic_vector(0 to 4 * C_SETS - 1) := (others => '0');   -- prefetched, unread
   signal s_pf    : std_logic := '0';                       -- the last clock began a read hit ...
   signal s_way   : unsigned(1 downto 0) := "00";           -- ... of this way
   signal s_set   : natural range 0 to C_SETS - 1 := 0;     -- ... and set
   signal s_line  : std_logic_vector(22 downto 5) := (others => '0');
   signal avm_write : std_logic := '0';
   signal avm_read  : std_logic := '0';

   signal n_read, n_miss, n_flush, n_write, n_pf, n_pfhit : unsigned(31 downto 0) := (others => '0');

   -- the second level
   constant C_L2SETS  : natural := 2 ** G_L2_BITS;
   constant C_L2TAGW  : natural := 22 - 4 - G_L2_BITS;
   constant C_L2DEPTH : natural := 4 * C_L2SETS * 4;        -- per lane: way, set, word bits 3:2
   type t_l2tag is array (0 to C_L2SETS - 1) of std_logic_vector(C_L2TAGW downto 0);   -- valid & tag
   type t_l2tq is array (0 to 3) of std_logic_vector(C_L2TAGW downto 0);
   type t_l2lane is array (0 to C_L2DEPTH - 1) of std_logic_vector(7 downto 0);
   type t_q8 is array (0 to 7) of std_logic_vector(7 downto 0);
   signal f_set2   : natural range 0 to C_L2SETS - 1;        -- the fill's line in the second level
   signal f_tag2   : std_logic_vector(C_L2TAGW - 1 downto 0);
   signal w_set2   : natural range 0 to C_L2SETS - 1;        -- the flushed line (wb_line(m_buf))
   signal w_tag2   : std_logic_vector(C_L2TAGW - 1 downto 0);
   signal l2q_f    : t_l2tq;
   signal l2q_w    : t_l2tq;
   signal l2_hit_f : std_logic;
   signal l2_way_f : unsigned(1 downto 0);
   signal l2_hit_w : std_logic;
   signal l2_way_w : unsigned(1 downto 0);
   signal l2_tw_en : std_logic;                             -- the tag write (from registers)
   signal l2_tw_way : unsigned(1 downto 0);
   signal l2_tw_d  : std_logic_vector(C_L2TAGW downto 0);
   signal l2_rr    : unsigned(1 downto 0) := "00";           -- the next victim way (all sets)
   signal l2v_way  : unsigned(1 downto 0) := "00";           -- the way a HyperRAM fill goes into
   signal f_l2fill : std_logic := '0';                      -- the fill comes from HyperRAM
   signal l2f_hit  : std_logic := '0';                      -- the flushed line is in the second level
   signal l2f_way  : unsigned(1 downto 0) := "00";
   signal l2c_way  : unsigned(1 downto 0) := "00";           -- the copy's way
   signal c_idx    : unsigned(2 downto 0) := "000";          -- the group the copy reads
   signal l2c_v    : std_logic := '0';                      -- l2_q holds group l2c_g of the copy
   signal l2c_g    : unsigned(1 downto 0) := "00";
   signal l2_ra    : natural range 0 to C_L2DEPTH - 1;
   signal l2_wa    : natural range 0 to C_L2DEPTH - 1 := 0;
   signal l2_we    : std_logic_vector(7 downto 0) := (others => '0');
   signal l2_wd    : std_logic_vector(15 downto 0) := (others => '0');
   signal l2_q     : t_q8;
   signal n_l2hit  : unsigned(31 downto 0) := (others => '0');

begin

   go_o <= go;
   avm_write_o <= avm_write;
   avm_read_o  <= avm_read;
   n_read_o <= n_read; n_miss_o <= n_miss; n_flush_o <= n_flush;
   n_pf_o <= n_pf; n_pfhit_o <= n_pfhit; n_l2hit_o <= n_l2hit;

   -------------------------------------------------------------------------------------------
   -- the second level: tags (LUT RAM, read at registered addresses only), data (block RAM)
   -------------------------------------------------------------------------------------------
   f_set2 <= to_integer(unsigned(f_line(4 + G_L2_BITS downto 5)));
   f_tag2 <= f_line(22 downto 5 + G_L2_BITS);
   w_set2 <= to_integer(unsigned(wb_line(m_buf)(4 + G_L2_BITS downto 5)));
   w_tag2 <= wb_line(m_buf)(22 downto 5 + G_L2_BITS);

   -- one tag write, at the fill's set: the victim's tag invalidated when the lookup misses (M_L2;
   -- its data is overwritten only from the first HyperRAM word on), the line's tag written valid
   -- with f_done (unless a write made the fill stale)
   l2_tw_en  <= '1' when (mstate = M_L2 and l2_hit_f = '0') or
                         (f_done = '1' and f_dirty = '0' and f_l2fill = '1') else '0';
   l2_tw_way <= l2_rr when mstate = M_L2 else l2v_way;
   l2_tw_d   <= '0' & f_tag2 when mstate = M_L2 else '1' & f_tag2;

   g_l2tags : for w in 0 to 3 generate
      signal tm2 : t_l2tag := (others => (others => '0'));
      attribute ram_style : string;
      attribute ram_style of tm2 : signal is "distributed";
   begin
      process (clk_i)
      begin
         if rising_edge(clk_i) then
            if l2_tw_en = '1' and l2_tw_way = w then
               tm2(f_set2) <= l2_tw_d;
            end if;
            -- pragma translate_off
            assert not (mstate = M_L2 and l2_hit_f = '0' and tm2(f_set2) = '1' & f_tag2)
               report "chip_hr: a second-level miss of a line it holds" severity failure;
            -- pragma translate_on
         end if;
      end process;
      l2q_f(w) <= tm2(f_set2);
      l2q_w(w) <= tm2(w_set2);
   end generate g_l2tags;

   p_l2_hit : process (all)
   begin
      l2_hit_f <= '0'; l2_way_f <= "00"; l2_hit_w <= '0'; l2_way_w <= "00";
      for w in 0 to 3 loop
         if l2q_f(w) = '1' & f_tag2 then
            l2_hit_f <= '1'; l2_way_f <= to_unsigned(w, 2);
         end if;
         if l2q_w(w) = '1' & w_tag2 then
            l2_hit_w <= '1'; l2_way_w <= to_unsigned(w, 2);
         end if;
      end loop;
   end process p_l2_hit;

   l2_ra <= to_integer(l2c_way & to_unsigned(f_set2, G_L2_BITS) & c_idx(1 downto 0));

   g_l2lanes : for i in 0 to 7 generate
      signal mem2 : t_l2lane := (others => (others => '0'));
      attribute ram_style : string;
      attribute ram_style of mem2 : signal is "block";
   begin
      process (clk_i)
      begin
         if rising_edge(clk_i) then
            if l2_we(i) = '1' then
               if i mod 2 = 1 then mem2(l2_wa) <= l2_wd(15 downto 8); else mem2(l2_wa) <= l2_wd(7 downto 0); end if;
            end if;
            l2_q(i) <= mem2(l2_ra);
         end if;
      end process;
   end generate g_l2lanes;

   acc   <= not (ram_oe_n_i and ram_we_n_i);
   set_i <= to_integer(unsigned(ram_addr_i(4 + G_SET_BITS downto 5)));
   tag_i <= ram_addr_i(22 downto 5 + G_SET_BITS);
   new_acc <= '1' when acc = '1' and (acc_d = '0' or ram_addr_i /= addr_d or
                                      rd_d /= not ram_oe_n_i) else '0';

   pq_set <= to_integer(unsigned(pq_line(4 + G_SET_BITS downto 5)));
   pq_tag <= pq_line(22 downto 5 + G_SET_BITS);

   -- every tag write goes to (f_way, f_set), from registers only: the victim's tag is invalidated
   -- one clock after the issue (its data stays intact until the first fill word, many clocks
   -- later), the filled line's tag is written in the clock after its last word (f_done)
   t_we <= iss_d or (f_done and not f_dirty);

   g_tags : for w in 0 to 3 generate
      signal tm : t_tagm := (others => (others => '0'));
      attribute ram_style : string;
      attribute ram_style of tm : signal is "distributed";
   begin
      process (clk_i)
      begin
         if rising_edge(clk_i) then
            if t_we = '1' and f_way = w then
               tm(f_set) <= f_done & f_line(22 downto 5 + G_SET_BITS);
            end if;
            -- pragma translate_off
            -- the line a fill was issued for is in no way (never two copies of a line)
            assert not (iss_d = '1' and tm(f_set) = '1' & f_line(22 downto 5 + G_SET_BITS))
               report "chip_hr: a fill of a cached line" severity failure;
            -- pragma translate_on
         end if;
      end process;
      tq_i(w) <= tm(set_i);
      tq_p(w) <= tm(pq_set);
   end generate g_tags;

   p_hit : process (all)
   begin
      hit  <= '0';
      hway <= "00";
      for w in 0 to 3 loop
         if tq_i(w) = '1' & tag_i then
            hit  <= '1';
            hway <= to_unsigned(w, 2);
         end if;
      end loop;
   end process p_hit;

   -- the second tag lookup: is the line the prefetch wants already cached?
   p_pq_hit : process (all)
   begin
      pq_hit <= '0';
      for w in 0 to 3 loop
         if tq_p(w) = '1' & pq_tag then
            pq_hit <= '1';
         end if;
      end loop;
   end process p_pq_hit;

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
               mem(c_wa) <= c_wd(8 * i + 7 downto 8 * i);
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
      c48_now    <= v_w(to_integer(lane_r + 1)) & v_w(to_integer(lane_r + 2)) & v_w(to_integer(lane_r + 3));
   end process p_out;

   -- chip48 is HELD, like sdram_ctrl.v's chip48_1..3 (loaded in a chip slot, kept until the next):
   -- Denise takes ram data at clk7_en (the access's Amiga edge k+2) but chip48 half a 7 MHz cycle
   -- later (bplNdat <= {data16, chip48} at clk7n_en), when the bus may already carry the next
   -- slot's address (the CPU between AGA's 64-bit fetches). So it is loaded at the read's Amiga
   -- edge k+2 - the edge at which Minimig takes ram_data_o, from the same c_q - and changes only at
   -- Amiga edges (the boundary rule). Found on the R6 test (r6rb-b, 2026-11-04): Workbench at FMODE
   -- 3 showed only the first word of every 64-bit group. Exactly once per read, at k+2: the gate
   -- guarantees the data of that edge, but a background fill may take the line as its victim right
   -- then (hit falls in that very clock) and overwrite it word by word in the clocks after.
   chip48_o <= c48_q;

   p_main : process (clk_i)
      variable v_line : std_logic_vector(22 downto 5);
      variable v_w    : natural range 0 to 15;
      variable v_lane : natural range 0 to 3;
      variable v_e1   : std_logic;                          -- edge k+1 has happened (after this edge)
      variable v_wr   : boolean;                            -- a write to take in this clock
      variable v_tk   : boolean;                            -- ... and it is taken
      variable v_cw   : boolean;                            -- the cache port is used by a write
      variable v_wpost : boolean;                           -- a write waits for the cache port
      variable v_iss  : boolean;                            -- a fill is issued in this clock
      variable v_il   : std_logic_vector(22 downto 5);      -- ... of this line
      variable v_ipf  : std_logic;                          -- ... as a prefetch
      variable v_iset : natural range 0 to C_SETS - 1;
      variable v_pqnew : boolean;                           -- a read asked for a prefetch in this clock
      variable v_fhit : boolean;                            -- the access is to the line validated now
      variable v_cway : unsigned(1 downto 0);
   begin
      if rising_edge(clk_i) then
         c_we   <= (others => '0');
         l2_we  <= (others => '0');
         lane_r <= unsigned(ram_addr_i(2 downto 1));
         acc_d  <= acc;
         addr_d <= ram_addr_i;
         rd_d   <= not ram_oe_n_i;
         v_line := ram_addr_i(22 downto 5);
         v_w    := to_integer(unsigned(ram_addr_i(4 downto 1)));
         v_lane := to_integer(unsigned(ram_addr_i(2 downto 1)));
         v_cw   := false;
         v_iss  := false;
         v_il   := dq_line;
         v_ipf  := '0';
         v_pqnew := false;

         -- edge k+1: the access was produced by an Amiga edge before this clock edge, so the
         -- first Amiga edge after it is its k+1 (always allowed)
         if new_acc = '1' then
            v_e1 := a_edge_i;
         else
            v_e1 := edge1 or a_edge_i;
         end if;
         if acc = '1' then edge1 <= v_e1; else edge1 <= '0'; end if;
         -- edge k+2 (or later) of a read: the Amiga takes ram_data_o now, chip48 is loaded with it
         if new_acc = '1' then
            c48_ld <= '0';
         elsif a_edge_i = '1' and edge1 = '1' and acc = '1' and ram_oe_n_i = '0' and c48_ld = '0' then
            c48_q  <= c48_now;
            c48_ld <= '1';
         end if;

         -------------------------------------------------------------------------------
         -- reads: a miss asks for its line (once per access)
         -------------------------------------------------------------------------------
         hit_d <= hit;
         -- the first read of a prefetched line asks for the next one (one clock after the read
         -- began: pfb is addressed by registers; if the line was taken as a victim meanwhile its
         -- bit is clear, and a lost prefetch costs only time)
         if s_pf = '1' and pfb(to_integer(s_way) * C_SETS + s_set) = '1' then
            pfb(to_integer(s_way) * C_SETS + s_set) <= '0';
            n_pfhit <= n_pfhit + 1;
            v_pqnew := true;
            pq_req  <= '1';
            pq_line <= std_logic_vector(unsigned(s_line) + 1);
         end if;
         s_pf <= '0';
         if new_acc = '1' and ram_oe_n_i = '0' then
            n_read <= n_read + 1;
            if hit = '0' then
               n_miss <= n_miss + 1;
            else
               s_pf   <= '1';
               s_way  <= hway;
               s_set  <= set_i;
               s_line <= v_line;
            end if;
         end if;

         -------------------------------------------------------------------------------
         -- writes: into the collecting buffer (same line or empty), else hand it over
         -------------------------------------------------------------------------------
         v_wr := ram_we_n_i = '0' and (new_acc = '1' or wtaken = '0');
         -- a write that would update the cache in the clock a fill word does: next clock. By the
         -- last clock's hit (a new access waits whenever a word comes): the tag lookup stays out of
         -- the write path. A line's tag becomes valid only in the clock after f_done, and no fill
         -- word comes then, so hit = '1' with hit_d = '0' never meets a fill word.
         v_wpost := v_wr and (avm_readdatavalid_i = '1' or l2c_v = '1') and (new_acc = '1' or hit_d = '1');
         -- a write in the clock the filled line's tag is written: it updates the cache too (it is
         -- not a hit yet, but will be one from the next clock on)
         v_fhit := f_done = '1' and f_dirty = '0' and v_line = f_line;
         if v_wpost then
            v_wr := false;
         end if;
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
               -- (the data whether it hits or not: only the enables wait for the tag lookup)
               c_wd <= ram_data_i & ram_data_i & ram_data_i & ram_data_i;
               if hit = '1' or v_fhit then                  -- keep a cached line current
                  v_cw := true;
                  if hit = '1' then v_cway := hway; else v_cway := f_way; end if;
                  c_wa <= to_integer(v_cway & to_unsigned(set_i, G_SET_BITS) & unsigned(ram_addr_i(4 downto 3)));
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
               if f_done = '1' then
                  null;                                     -- the last fill's tag is written now
               elsif dq_req = '1' and not (wb_used(0) = '1' and wb_line(0) = dq_line) and
                                      not (wb_used(1) = '1' and wb_line(1) = dq_line) then
                  -- a demand fill, before queued write-backs of other lines (its line is not
                  -- cached: it was not when asked for, and was neither being filled nor issued
                  -- then; while it waits, no other fill is issued)
                  dq_req <= '0';
                  v_iss := true; v_il := dq_line; v_ipf := '0';
                  pq_req  <= '1';                           -- and the next line behind it
                  pq_line <= std_logic_vector(unsigned(dq_line) + 1);
               elsif fl_q = '1' then
                  fl_q <= '0'; fl <= '1';
                  m_idx <= (others => '0');
                  avm_address_o    <= std_logic_vector(to_unsigned(G_BASE_WORD, 32) +
                                      unsigned(std_logic_vector'(wb_line(m_buf) & "0000")));
                  avm_burstcount_o <= x"10";
                  avm_writedata_o  <= wb_data(16 * m_buf);
                  avm_byteenable_o <= wb_be(32 * m_buf + 1) & wb_be(32 * m_buf);
                  avm_write        <= '1';
                  n_flush <= n_flush + 1;
                  l2f_hit <= l2_hit_w;                      -- (wb_line(m_buf): set with fl_q)
                  l2f_way <= l2_way_w;
                  mstate <= M_WR;
               elsif dq_req = '1' then
                  -- its line is in the collecting buffer (a queued one is flushed above): hand it over
                  if wb_used(wa) = '1' and wb_line(wa) = dq_line and not v_wr then
                     fl_q <= '1'; m_buf <= wa; wa <= 1 - wa;
                  end if;
               elsif pq_req = '1' then
                  if not v_pqnew then                       -- (a new request replaces this one)
                     pq_req <= '0';
                  end if;
                  if pq_hit = '0' and not (wb_used(0) = '1' and wb_line(0) = pq_line) and
                                      not (wb_used(1) = '1' and wb_line(1) = pq_line) then
                     v_iss := true; v_il := pq_line; v_ipf := '1';
                  end if;
               end if;
               if v_iss then
                  v_iset := to_integer(unsigned(v_il(4 + G_SET_BITS downto 5)));
                  f_line  <= v_il;
                  f_set   <= v_iset;
                  f_way   <= rr(v_iset);
                  rr(v_iset) <= rr(v_iset) + 1;
                  f_pf    <= v_ipf;
                  f_busy  <= '1';
                  -- a write to this line in this very clock makes the fill stale already
                  if v_tk and v_line = v_il then f_dirty <= '1'; else f_dirty <= '0'; end if;
                  if v_ipf = '1' then n_pf <= n_pf + 1; end if;
                  mstate <= M_L2;          -- (the victim's tag and pfb are cleared in the next clock)
               end if;

            when M_WR =>
               if avm_waitrequest_i = '0' then
                  -- the word just sent also into the second level's copy of the line
                  if l2f_hit = '1' then
                     l2_wa <= to_integer(l2f_way & to_unsigned(w_set2, G_L2_BITS) & m_idx(3 downto 2));
                     l2_wd <= avm_writedata_o;
                     l2_we(2 * to_integer(m_idx(1 downto 0)) + 1) <= avm_byteenable_o(1);
                     l2_we(2 * to_integer(m_idx(1 downto 0)))     <= avm_byteenable_o(0);
                  end if;
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
                  c_wd <= avm_readdata_i & avm_readdata_i & avm_readdata_i & avm_readdata_i;
                  c_we <= (others => '0');
                  c_we(2 * to_integer(m_idx(1 downto 0)) + 1) <= '1';
                  c_we(2 * to_integer(m_idx(1 downto 0)))     <= '1';
                  l2_wa <= to_integer(l2v_way & to_unsigned(f_set2, G_L2_BITS) & m_idx(3 downto 2));
                  l2_wd <= avm_readdata_i;
                  l2_we(2 * to_integer(m_idx(1 downto 0)) + 1) <= '1';
                  l2_we(2 * to_integer(m_idx(1 downto 0)))     <= '1';
                  m_idx <= m_idx + 1;
                  if m_idx = 15 then
                     f_done <= '1';
                     mstate <= M_IDLE;
                  end if;
               end if;

            when M_L2 =>
               -- the line in the second level? copy it; else read HyperRAM into both levels
               if l2_hit_f = '1' then
                  l2c_way  <= l2_way_f;
                  c_idx    <= "000";
                  f_l2fill <= '0';
                  n_l2hit  <= n_l2hit + 1;
                  mstate   <= M_L2C;
               else
                  l2v_way  <= l2_rr;                        -- (its tag is invalidated now: l2_tw_en)
                  l2_rr    <= l2_rr + 1;
                  f_l2fill <= '1';
                  m_idx    <= (others => '0');
                  avm_address_o    <= std_logic_vector(to_unsigned(G_BASE_WORD, 32) + unsigned(std_logic_vector'(f_line & "0000")));
                  avm_burstcount_o <= x"10";
                  avm_read         <= '1';
                  mstate   <= M_RD;
               end if;

            when M_L2C =>
               -- group c_idx is read (l2_ra), the group read in the last clock written (l2c_v)
               if c_idx /= 4 then
                  c_idx <= c_idx + 1;
                  l2c_v <= '1';
                  l2c_g <= c_idx(1 downto 0);
               else
                  l2c_v <= '0';
               end if;
               if l2c_v = '1' then
                  assert not v_cw report "chip_hr: a write and a fill want the cache port" severity failure;
                  c_wa <= to_integer(f_way & to_unsigned(f_set, G_SET_BITS) & l2c_g);
                  c_wd <= l2_q(7) & l2_q(6) & l2_q(5) & l2_q(4) & l2_q(3) & l2_q(2) & l2_q(1) & l2_q(0);
                  c_we <= (others => '1');
                  if l2c_g = 3 then
                     f_done <= '1';
                     mstate <= M_IDLE;
                  end if;
               end if;
         end case;

         -- the filled line becomes valid once its last word is in the cache RAM (the write is
         -- registered); a read of it hits from then on
         -- a write to the line in flight: the fill is stale
         -- (in the f_done clock such a write goes into the cache, see v_fhit)
         if f_busy = '1' and f_done = '0' and v_tk and v_line = f_line and not v_iss then
            f_dirty <= '1';
         end if;
         iss_d <= '0';
         if v_iss then
            iss_d <= '1';
         end if;
         -- the victim (f_way, f_set) of the fill issued in the last clock: its tag is invalidated
         -- now (t_we), its prefetch bit too
         if iss_d = '1' then
            pfb(to_integer(f_way) * C_SETS + f_set) <= '0';
         end if;
         if f_done = '1' then
            f_done <= '0';
            f_busy <= '0';
            if f_dirty = '0' then                           -- (the tag: t_we)
               pfb(to_integer(f_way) * C_SETS + f_set) <= f_pf;
            end if;
         end if;

         -- a read that misses asks for its line - unless that line is being filled (it waits for
         -- that fill), is issued in this clock, or a request is pending; asked again after a stale
         -- fill
         if acc = '1' and ram_oe_n_i = '0' and hit = '0' and dq_req = '0' and
            not (f_busy = '1' and f_line = v_line) and not (v_iss and v_il = v_line) then
            dq_req  <= '1';
            dq_line <= v_line;
         end if;

         -------------------------------------------------------------------------------
         -- the gate for the next Amiga edge: a read whose line is not in the cache may not see
         -- its k+2; a write that found no buffer waits
         -------------------------------------------------------------------------------
         go <= '1';
         if acc = '1' and ram_oe_n_i = '0' and hit = '0' and v_e1 = '1' then
            go <= '0';
         end if;
         if (v_wr and not v_tk) or v_wpost then
            go <= '0';
         end if;

         if rst_i = '1' then
            mstate <= M_IDLE; avm_write <= '0'; avm_read <= '0';
            edge1 <= '0'; go <= '1'; wtaken <= '1';
            f_done <= '0'; f_busy <= '0'; dq_req <= '0'; pq_req <= '0'; s_pf <= '0';
            l2c_v <= '0'; f_l2fill <= '0';
            fl <= '0'; fl_q <= '0';
            wb_used <= "00";
         end if;
      end if;
   end process p_main;

end architecture synthesis;
