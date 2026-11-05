---------------------------------------------------------------------------------------------------------
-- Megamiga (Amiga for MEGA65, fork of AExp)
--
-- amiga_mem_r3: the Amiga memory on the MEGA65 R3/R3A, which has no SDRAM (amiga_sdram.vhd's
-- counterpart there; same ports minus the SDRAM pins, plus an Avalon master into the HyperRAM)
--
-- Chip and Slow RAM: 1 MB of block RAM on Minimig's chipset port (minimig_sram_bridge.v), one core
-- clock from address to data like AExp's original BRAM design. HyperRAM cannot be chip RAM:
-- Minimig wants the data ~70 ns after the address and accesses can be 141 ns apart (measured,
-- doc/developers/r3.md). Banks of the banked "SRAM" address (ram_addr_i[22:19]):
--   0000 chip $000000-$07FFFF  -> block RAM half 0
--   0001 chip $080000-$0FFFFF  -> block RAM half 1
--   1000 slow $C00000-$C7FFFF  -> block RAM half 1 (only with 512 KB chip RAM: the parent keeps
--                                 chip + slow <= 1 MB)
--   others                     -> nothing (reads 0, writes ignored)
-- The block RAM is four 16-bit lanes (word address bits 2:1 pick the lane), so one read gives
-- the aligned 64-bit group: chip48_o carries the three words after the addressed one in
-- sdram_ctrl.v's burst order (sequential, wrapping in the group) for AGA's fetch modes.
--
-- Kickstart (512 KB) and Zorro II Fast RAM (up to 4 MB) are in the HyperRAM, behind cpu_wrapper's
-- ram* port, which on R3 also carries every Kickstart read of the 68000 (cpu_wrapper kick_ram).
-- HyperRAM word addresses (16-bit words; the scaler's framebuffer has words 0..0FFFFF = 2 MB):
--   Zorro II  $200000-$5FFFFF  -> words 100000-2FFFFF (= fram_addr_i(22:1): byte address 1:1)
--   Kickstart bank 1111        -> words 300000-33FFFF (fram_addr_i(18:1) = the offset)
-- A direct-mapped read cache of 2**G_CACHE_BITS words in block RAM (16-word lines = one HyperRAM
-- burst) sits in front: a hit answers two core clocks after the select, a miss fetches the line
-- and answers as soon as the CPU's word arrives (the rest of the line still fills). Writes go
-- through (posted, one word) and update a line that holds their word. Only this port and the
-- Kickstart loader write these HyperRAM words, so the cache stays coherent; a loader write
-- clears it.
--
-- Handshake: the 68000 (cpu_020_i = '0') holds its select for the whole bus cycle and needs
-- DTACK (fram_ready_o) until it ends: ready stays high until the select drops. Its write cycles
-- assert UDS/LDS (and the data) a clock after the select, so a write waits for a strobe. TG68K has no
-- address strobe: ready is high for one clock and the clock after it is skipped, then the next
-- access is taken (as rtg_vram.vhd).
--
-- Kickstart loader: the QNICE Shell writes the ROM file byte by byte into this device (byte
-- address = file offset, even byte = high byte); words cross to the core clock through a FIFO
-- and are written into the HyperRAM. A word of the first 256 KB also goes to the second 256 KB,
-- so a 256 KB Kickstart (1.x) is mirrored like on real hardware. No 1 MB Kickstart on R3.
--
-- G_KICK_BRAM (rubber banding, mega65.vhd C_RB): the Kickstart is in 512 KB of block RAM here
-- instead (128 tiles, free once the chip RAM moved to HyperRAM), so its HyperRAM words go to the
-- chip RAM and the Zorro II RAM can have 4 MB. The loader writes the block RAM (the mirror too);
-- a CPU read of the Kickstart bypasses the cache and is answered two clocks after it is taken
-- (registered address, block RAM, registered output: the 128 tiles spread over the die). The CPU
-- port never writes the Kickstart (cpu_wrapper sends only reads there).
--
-- Cold-boot scrub (amiga_cold_boot.vhd): zero words in chip RAM at scrub_addr_i while scrub_i.
--
-- Not on R3 (inputs ignored, outputs idle): the 68040 port, IDE DMA, the cartridges.
--
-- Done in 2026 (Megamiga, fork of AExp) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

entity amiga_mem_r3 is
   generic (
      G_CACHE_BITS   : natural := 13;                        -- 2**13 words = 16 KB read cache
      G_KICK_WORD    : natural := 16#300000#;                -- HyperRAM word of the Kickstart
      G_KICK_BRAM    : boolean := false;                     -- the Kickstart in block RAM instead
      G_CHIP_BITS    : natural := 19                         -- block RAM words: 2**19 = 1 MB
   );
   port (
      clk_i          : in    std_logic;                      -- core clock (28.375 MHz)
      rst_i          : in    std_logic;                      -- clock-generator reset only

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
      fram_addr_i    : in    std_logic_vector(25 downto 1);  -- main.vhd fram_addr_o
      cpu_020_i      : in    std_logic;                      -- '1' = TG68K (static)
      fram_uds_n_i   : in    std_logic;
      fram_lds_n_i   : in    std_logic;
      fram_data_i    : in    std_logic_vector(15 downto 0);
      fram_data_o    : out   std_logic_vector(15 downto 0);
      fram_ready_o   : out   std_logic;
      cpu_reset_n_i  : in    std_logic;                      -- clears the read cache

      -- cold-boot scrub
      scrub_i        : in    std_logic;
      scrub_addr_i   : in    std_logic_vector(17 downto 0);  -- chip RAM word address

      -- Kickstart loader (QNICE clock)
      qnice_clk_i    : in    std_logic;
      qnice_rst_i    : in    std_logic;
      qnice_addr_i   : in    std_logic_vector(27 downto 0);  -- byte address = file offset
      qnice_data_i   : in    std_logic_vector(15 downto 0);
      qnice_ce_i     : in    std_logic;
      qnice_we_i     : in    std_logic;
      qnice_wait_o   : out   std_logic;
      kick_busy_o    : out   std_logic;                      -- core clock: words in flight
      maint_idle_o   : out   std_logic;

      -- HyperRAM: Avalon master (core clock; the parent crosses to the HyperRAM clock)
      avm_write_o         : out std_logic;
      avm_read_o          : out std_logic;
      avm_address_o       : out std_logic_vector(31 downto 0);
      avm_writedata_o     : out std_logic_vector(15 downto 0);
      avm_byteenable_o    : out std_logic_vector( 1 downto 0);
      avm_burstcount_o    : out std_logic_vector( 7 downto 0);
      avm_readdata_i      : in  std_logic_vector(15 downto 0);
      avm_readdatavalid_i : in  std_logic;
      avm_waitrequest_i   : in  std_logic
   );
end entity amiga_mem_r3;

architecture synthesis of amiga_mem_r3 is

   ---------------------------------------------------------------------------------------
   -- chip/slow block RAM: 4 lanes x 2 bytes, 2**(G_CHIP_BITS-2) rows each
   ---------------------------------------------------------------------------------------
   constant C_ROWS : natural := 2 ** (G_CHIP_BITS - 2);
   type t_lane is array (0 to C_ROWS - 1) of std_logic_vector(7 downto 0);

   signal b_addr    : unsigned(G_CHIP_BITS - 1 downto 0);    -- block RAM word address
   signal b_hit     : std_logic;                              -- the bank is in the block RAM
   signal b_row     : natural range 0 to C_ROWS - 1;
   signal b_we      : std_logic_vector(7 downto 0);           -- lane*2 + 1 = high byte
   signal b_wd      : std_logic_vector(15 downto 0);
   type t_q is array (0 to 7) of std_logic_vector(7 downto 0);
   signal b_q       : t_q;
   signal b_lane_r  : unsigned(1 downto 0) := "00";
   signal b_hit_r   : std_logic := '0';

   ---------------------------------------------------------------------------------------
   -- Kickstart loader
   ---------------------------------------------------------------------------------------
   signal q_hi      : std_logic_vector(7 downto 0) := (others => '0');
   signal q_wr_en   : std_logic := '0';
   signal q_din     : std_logic_vector(33 downto 0) := (others => '0');   -- word 17:0 & data
   signal q_full    : std_logic;
   signal q_wr_rst_busy : std_logic;
   signal f_rd_en   : std_logic;
   signal f_dout    : std_logic_vector(33 downto 0);
   signal f_empty   : std_logic;
   signal f_rd_rst_busy : std_logic;

   ---------------------------------------------------------------------------------------
   -- CPU port + cache + Avalon master
   ---------------------------------------------------------------------------------------
   constant C_LINES : natural := 2 ** (G_CACHE_BITS - 4);
   constant C_TAGW  : natural := 22 - G_CACHE_BITS;          -- HyperRAM word address bits 21..
   type t_cdata is array (0 to 2 ** G_CACHE_BITS - 1) of std_logic_vector(7 downto 0);
   type t_tags  is array (0 to C_LINES - 1) of std_logic_vector(C_TAGW - 1 downto 0);
   signal c_lo, c_hi : t_cdata;
   attribute ram_style : string;
   attribute ram_style of c_lo : signal is "block";
   attribute ram_style of c_hi : signal is "block";
   signal tags      : t_tags := (others => (others => '0'));
   attribute ram_style of tags : signal is "distributed";
   signal valid     : std_logic_vector(C_LINES - 1 downto 0) := (others => '0');

   type t_state is (S_IDLE, S_WRITE, S_FILLREQ, S_FILL, S_FILLEND, S_LOAD, S_LOAD2, S_KICK1,
                    S_KICK2);
   signal state     : t_state := S_IDLE;
   signal hr_word   : unsigned(21 downto 0);                  -- the CPU access in HyperRAM
   signal line      : natural range 0 to C_LINES - 1;
   signal tag       : std_logic_vector(C_TAGW - 1 downto 0);
   signal hit       : std_logic;
   signal c_rd      : std_logic_vector(15 downto 0);          -- cache read port (registered)
   signal c_wa      : natural range 0 to 2 ** G_CACHE_BITS - 1;
   signal c_wd      : std_logic_vector(15 downto 0);
   signal c_we      : std_logic_vector(1 downto 0);

   signal data      : std_logic_vector(15 downto 0) := (others => '1');
   signal from_c    : std_logic := '0';                       -- the answer is c_rd (a hit)
   signal served    : std_logic := '0';                       -- the current access is answered
   signal ready     : std_logic := '0';
   signal f_line    : natural range 0 to C_LINES - 1 := 0;
   signal f_idx     : unsigned(3 downto 0) := (others => '0');
   signal f_want    : unsigned(3 downto 0) := (others => '0');
   signal f_given   : std_logic := '0';
   signal l_word    : unsigned(17 downto 0) := (others => '0');   -- loader: the word offset
   signal l_data    : std_logic_vector(15 downto 0) := (others => '0');
   signal l_mirror  : std_logic := '0';
   signal avm_write : std_logic := '0';
   signal avm_read  : std_logic := '0';
   signal watchdog  : unsigned(11 downto 0) := (others => '0');

   -- G_KICK_BRAM: the Kickstart block RAM (256K words)
   type t_kick is array (0 to 2 ** 18 - 1) of std_logic_vector(7 downto 0);
   signal is_kick   : std_logic;                              -- the CPU access is a Kickstart read
   signal from_k    : std_logic := '0';                       -- the answer is k_q
   signal k_ra      : unsigned(17 downto 0) := (others => '0');
   signal k_we      : std_logic := '0';
   signal k_wa      : unsigned(17 downto 0) := (others => '0');
   signal k_wd      : std_logic_vector(15 downto 0) := (others => '0');
   signal k_rd      : std_logic_vector(15 downto 0) := (others => '0');
   signal k_q       : std_logic_vector(15 downto 0) := (others => '0');

begin

   ---------------------------------------------------------------------------------------
   -- Chip/slow RAM on the chipset port. The scrub owns the port while scrub_i is high (the
   -- Amiga is held in reset then).
   ---------------------------------------------------------------------------------------

   p_map : process (all)
      variable v_hit  : std_logic;
      variable v_addr : unsigned(G_CHIP_BITS - 1 downto 0);
      variable v_we   : std_logic_vector(7 downto 0);
   begin
      v_hit  := '0';
      v_addr := (others => '0');
      v_we   := (others => '0');
      b_wd   <= ram_data_i;
      if scrub_i = '1' then
         v_hit  := '1';
         v_addr := resize(unsigned(scrub_addr_i), G_CHIP_BITS);
         b_wd   <= (others => '0');
      else
         case ram_addr_i(22 downto 19) is
            when "0000" =>
               v_hit  := '1';
               v_addr := resize(unsigned('0' & ram_addr_i(18 downto 1)), G_CHIP_BITS);
            when "0001" | "1000" =>
               v_hit  := '1';
               v_addr := resize(unsigned('1' & ram_addr_i(18 downto 1)), G_CHIP_BITS);
            when others =>
               null;
         end case;
      end if;
      if scrub_i = '1' or (ram_we_n_i = '0' and v_hit = '1') then
         for i in 0 to 3 loop
            if to_integer(v_addr(1 downto 0)) = i then
               if scrub_i = '1' then
                  v_we(2 * i + 1 downto 2 * i) := "11";
               else
                  v_we(2 * i + 1) := not ram_bhe_n_i;
                  v_we(2 * i)     := not ram_ble_n_i;
               end if;
            end if;
         end loop;
      end if;
      b_hit  <= v_hit;
      b_addr <= v_addr;
      b_we   <= v_we;
   end process p_map;

   b_row <= to_integer(b_addr(G_CHIP_BITS - 1 downto 2));

   g_bytes : for i in 0 to 7 generate
      signal mem : t_lane := (others => (others => '0'));   -- block RAM powers up zero
      attribute ram_style of mem : signal is "block";
   begin
      process (clk_i)
      begin
         if rising_edge(clk_i) then
            if b_we(i) = '1' then
               if i mod 2 = 1 then
                  mem(b_row) <= b_wd(15 downto 8);
               else
                  mem(b_row) <= b_wd(7 downto 0);
               end if;
            end if;
            b_q(i) <= mem(b_row);
         end if;
      end process;
   end generate g_bytes;

   p_lane : process (clk_i)
   begin
      if rising_edge(clk_i) then
         b_lane_r <= b_addr(1 downto 0);
         b_hit_r  <= b_hit;
      end if;
   end process p_lane;

   p_out : process (all)
      type t_w4 is array (0 to 3) of std_logic_vector(15 downto 0);
      variable v_w : t_w4;                             -- the four lanes of the group
      variable l   : unsigned(1 downto 0);
   begin
      for k in 0 to 3 loop
         v_w(k) := b_q(2 * k + 1) & b_q(2 * k);
      end loop;
      l := b_lane_r;
      if b_hit_r = '1' then
         ram_data_o <= v_w(to_integer(l));
         chip48_o   <= v_w(to_integer(l + 1)) & v_w(to_integer(l + 2)) & v_w(to_integer(l + 3));
      else
         ram_data_o <= (others => '0');
         chip48_o   <= (others => '0');
      end if;
   end process p_out;

   ---------------------------------------------------------------------------------------
   -- Kickstart loader, QNICE side (as amiga_sdram.vhd): pair the bytes, push the words
   ---------------------------------------------------------------------------------------

   qnice_wait_o <= q_full or q_wr_rst_busy;
   kick_busy_o  <= '1' when f_empty = '0' or state = S_LOAD or state = S_LOAD2 or
                            l_mirror = '1' else '0';
   maint_idle_o <= '1' when f_empty = '1' and state /= S_LOAD and state /= S_LOAD2 and
                            l_mirror = '0' and scrub_i = '0' else '0';

   p_qnice_bytes : process (qnice_clk_i)
   begin
      if falling_edge(qnice_clk_i) then
         q_wr_en <= '0';
         if qnice_ce_i = '1' and qnice_we_i = '1' and q_full = '0' and q_wr_rst_busy = '0' then
            if qnice_addr_i(0) = '0' then
               q_hi <= qnice_data_i(7 downto 0);                       -- even byte: high byte
            elsif unsigned(qnice_addr_i(27 downto 19)) = 0 then        -- 512 KB at most
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
   -- CPU port: address in HyperRAM, cache lookup
   ---------------------------------------------------------------------------------------

   hr_word <= unsigned(fram_addr_i(22 downto 1)) when fram_addr_i(24 downto 23) = "01" else
              to_unsigned(G_KICK_WORD, 22) + unsigned(fram_addr_i(18 downto 1));
   line    <= to_integer(hr_word(G_CACHE_BITS - 1 downto 4));
   tag     <= std_logic_vector(hr_word(21 downto G_CACHE_BITS));
   hit     <= '1' when valid(line) = '1' and tags(line) = tag else '0';
   is_kick <= '1' when G_KICK_BRAM and fram_addr_i(24 downto 23) /= "01" else '0';

   -- G_KICK_BRAM: one write port (the loader), one read port (registered address, registered
   -- output)
   g_kick_mem : if G_KICK_BRAM generate
      signal k_hi, k_lo : t_kick;
      attribute ram_style of k_hi : signal is "block";
      attribute ram_style of k_lo : signal is "block";
   begin
      p_kick_ram : process (clk_i)
      begin
         if rising_edge(clk_i) then
            if k_we = '1' then
               k_hi(to_integer(k_wa)) <= k_wd(15 downto 8);
               k_lo(to_integer(k_wa)) <= k_wd(7 downto 0);
            end if;
            k_rd <= k_hi(to_integer(k_ra)) & k_lo(to_integer(k_ra));
            k_q  <= k_rd;
         end if;
      end process p_kick_ram;
   end generate g_kick_mem;

   -- cache data: one write port (fill, write-through update), one read port (the CPU address)
   p_cache_ram : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if c_we(0) = '1' then
            c_lo(c_wa) <= c_wd(7 downto 0);
         end if;
         if c_we(1) = '1' then
            c_hi(c_wa) <= c_wd(15 downto 8);
         end if;
         c_rd <= c_hi(to_integer(hr_word(G_CACHE_BITS - 1 downto 0))) &
                 c_lo(to_integer(hr_word(G_CACHE_BITS - 1 downto 0)));
      end if;
   end process p_cache_ram;

   fram_data_o      <= c_rd when from_c = '1' else k_q when from_k = '1' else data;
   fram_ready_o     <= ready;
   avm_write_o      <= avm_write;
   avm_read_o       <= avm_read;

   f_rd_en <= '1' when state = S_IDLE and l_mirror = '0' and f_empty = '0' and
                       f_rd_rst_busy = '0' else '0';

   p_fsm : process (clk_i)
      variable v_answer : boolean;
   begin
      if rising_edge(clk_i) then
         c_we     <= "00";
         k_we     <= '0';
         v_answer := false;

         -- the handshake: TG68K takes ready in the one clock it is high and presents its next
         -- access in the clock after, so the select is looked at again one clock later (served
         -- is still set while that clock's edge is evaluated); the 68000 keeps ready until its
         -- select drops
         if cpu_020_i = '1' then
            if ready = '1' then
               ready  <= '0';
               served <= '0';
            end if;
         elsif served = '1' and fram_sel_i = '0' then
            ready  <= '0';
            served <= '0';
         end if;

         case state is
            when S_IDLE =>
               if G_KICK_BRAM and l_mirror = '1' then               -- the 256 KB mirror
                  k_we     <= '1';
                  k_wa     <= l_word + 16#20000#;
                  k_wd     <= l_data;
                  l_mirror <= '0';
               elsif G_KICK_BRAM and f_rd_en = '1' then             -- a Kickstart word
                  l_word   <= unsigned(f_dout(33 downto 16));
                  l_data   <= f_dout(15 downto 0);
                  l_mirror <= not f_dout(33);                       -- in the first 256 KB
                  k_we     <= '1';
                  k_wa     <= unsigned(f_dout(33 downto 16));
                  k_wd     <= f_dout(15 downto 0);
               elsif l_mirror = '1' then                            -- the 256 KB mirror
                  avm_address_o    <= std_logic_vector(to_unsigned(G_KICK_WORD, 32) +
                                                       resize(l_word, 32) + 16#20000#);
                  avm_writedata_o  <= l_data;
                  avm_byteenable_o <= "11";
                  avm_burstcount_o <= x"01";
                  avm_write        <= '1';
                  l_mirror         <= '0';
                  state            <= S_LOAD;              -- (the word itself cleared the cache)
               elsif f_rd_en = '1' then                             -- a Kickstart word
                  l_word           <= unsigned(f_dout(33 downto 16));
                  l_data           <= f_dout(15 downto 0);
                  l_mirror         <= not f_dout(33);               -- in the first 256 KB
                  avm_address_o    <= std_logic_vector(to_unsigned(G_KICK_WORD, 32) +
                                                       resize(unsigned(f_dout(33 downto 16)), 32));
                  avm_writedata_o  <= f_dout(15 downto 0);
                  avm_byteenable_o <= "11";
                  avm_burstcount_o <= x"01";
                  avm_write        <= '1';
                  valid            <= (others => '0');
                  state            <= S_LOAD;
               -- a 68000 write cycle asserts its data strobes a clock after the address strobe
               -- (with the data): a write is taken once a strobe is there
               elsif fram_sel_i = '1' and served = '0' and
                     (fram_state_i /= "11" or fram_uds_n_i = '0' or fram_lds_n_i = '0') then
                  watchdog <= (others => '0');
                  if is_kick = '1' then                             -- the Kickstart (block RAM)
                     k_ra  <= unsigned(fram_addr_i(18 downto 1));
                     state <= S_KICK1;
                  elsif fram_state_i = "11" then                    -- write: through
                     avm_address_o    <= std_logic_vector(resize(hr_word, 32));
                     avm_writedata_o  <= fram_data_i;
                     avm_byteenable_o <= (not fram_uds_n_i) & (not fram_lds_n_i);
                     avm_burstcount_o <= x"01";
                     avm_write        <= '1';
                     if hit = '1' then                              -- keep the line up to date
                        c_wa <= to_integer(hr_word(G_CACHE_BITS - 1 downto 0));
                        c_wd <= fram_data_i;
                        c_we <= (not fram_uds_n_i) & (not fram_lds_n_i);
                     end if;
                     state <= S_WRITE;
                  elsif hit = '1' then                              -- c_rd shows the word in
                     from_c   <= '1';                               -- the clock after this edge
                     from_k   <= '0';
                     v_answer := true;
                  else                                              -- miss: fetch the line
                     avm_address_o    <= std_logic_vector(resize(hr_word(21 downto 4) & "0000", 32));
                     avm_burstcount_o <= x"10";
                     avm_read         <= '1';
                     valid(line)      <= '0';
                     tags(line)       <= tag;
                     f_line           <= line;
                     f_idx            <= (others => '0');
                     f_want           <= hr_word(3 downto 0);
                     f_given          <= '0';
                     state            <= S_FILLREQ;
                  end if;
               end if;

            when S_KICK1 =>                                         -- the block RAM reads k_ra
               state <= S_KICK2;

            when S_KICK2 =>                                         -- k_q shows the word in the
               from_c   <= '0';                                     -- clock after this edge
               from_k   <= '1';
               v_answer := true;
               state    <= S_IDLE;

            when S_WRITE =>                                         -- posted: done once taken
               if avm_waitrequest_i = '0' then
                  avm_write <= '0';
                  v_answer  := true;
                  from_c    <= '0';
                  from_k    <= '0';
                  state     <= S_IDLE;
               end if;

            when S_FILLREQ | S_FILL =>
               if state = S_FILLREQ and avm_waitrequest_i = '0' then
                  avm_read <= '0';
                  state    <= S_FILL;
               end if;
               if state = S_FILL then
                  watchdog <= watchdog + 1;
               end if;
               if avm_readdatavalid_i = '1' then
                  c_wa  <= f_line * 16 + to_integer(f_idx);
                  c_wd  <= avm_readdata_i;
                  c_we  <= "11";
                  f_idx <= f_idx + 1;
                  if f_idx = f_want and f_given = '0' then          -- the CPU's word: answer now
                     data     <= avm_readdata_i;
                     v_answer := true;
                     from_c   <= '0';
                     from_k   <= '0';
                     f_given  <= '1';
                  end if;
                  if f_idx = 15 then                                -- line complete
                     avm_read <= '0';
                     state    <= S_FILLEND;
                  end if;
               elsif state = S_FILL and watchdog = (watchdog'range => '1') then
                  if f_given = '0' then                             -- lost response: no hang
                     data     <= (others => '1');
                     v_answer := true;
                     from_c   <= '0';
                     from_k   <= '0';
                  end if;
                  state <= S_IDLE;
               end if;

            when S_FILLEND =>
               -- the cache RAM takes the line's last word at this edge (c_we is registered): the
               -- line becomes valid only now, so a hit in the next clock reads it complete
               valid(f_line) <= '1';
               state         <= S_IDLE;

            when S_LOAD =>                                          -- Kickstart word, posted
               if avm_waitrequest_i = '0' then
                  avm_write <= '0';
                  state     <= S_LOAD2;
               end if;

            when S_LOAD2 =>
               state <= S_IDLE;
         end case;

         if v_answer then
            ready  <= '1';
            served <= '1';
         end if;

         if cpu_reset_n_i = '0' then
            valid <= (others => '0');
         end if;

         if rst_i = '1' then
            state     <= S_IDLE;
            ready     <= '0';
            served    <= '0';
            avm_write <= '0';
            avm_read  <= '0';
            l_mirror  <= '0';
            k_we      <= '0';
            from_k    <= '0';
            valid     <= (others => '0');
         end if;
      end if;
   end process p_fsm;

end architecture synthesis;
