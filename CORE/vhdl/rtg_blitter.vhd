---------------------------------------------------------------------------------------------------------
-- Megamiga (Amiga for MEGA65, fork of AExp)
--
-- rtg_blitter: a fill and copy engine for the RTG board memory, used by the Picasso96 driver
-- (CORE/rtg/MiSTer.card.asm: FillRect, BlitRect, BlitRectNoMaskComplete, WaitBlitter).
--
-- Registers (68020, cpu_wrapper's fastchip port at $B80800, 16 bit, core clock):
--
--   $00/$02  SRC     source byte address of the FIRST line to do ($02xxxxxx; bits 21:0 are used)
--   $04/$06  DST     destination byte address of the first line to do
--   $08      SSTRIDE signed byte distance from one source line to the next (negative: bottom-up)
--   $0A      DSTRIDE signed byte distance from one destination line to the next
--   $0C      WIDTH   bytes per line, 1..8190
--   $0E      HEIGHT  lines, 1..65535 (0 = nothing)
--   $10/$12  PAT     fill pattern, in memory order: byte 0 = bits 31:24 (what a move.l writes)
--   $14      BPP     bytes per pixel of the fill pattern: 1, 2 or 4
--   $16      CMD     write 1 = fill, 2 = copy (starts); read: bit 0 = busy
--   $1E      ID      read: $B11B
--
-- The driver sets the parameters, then CMD, and waits for busy = 0 before it touches any of them
-- again and before the CPU accesses the board memory (Picasso96 calls WaitBlitter for that).
-- A CPU reset does not stop a command: it runs to its end (busy then clears by itself).
--
-- Copy: each source line is first read completely into a line buffer (BRAM) and then written, so
-- an overlap WITHIN a line needs no care; for an overlap between lines the driver starts at the
-- last line with negative strides when the destination lies behind the source in memory.
-- Source and destination may have different byte alignment (odd x in 8-bit modes).
--
-- Ordering with the CPU's own writes: they travel rtg_vram -> avm_fifo -> rtg_wcomb. A start waits
-- until that path has been quiet (quiet_i: FIFO output empty and the combiner holding nothing) for
-- C_QUIET clocks, and asks the combiner to send what it holds (h_flush_o) meanwhile; the CPU's
-- start write is issued after its last board write was accepted by the FIFO, and the start toggle
-- needs longer to cross than the FIFO.
--
-- Board memory layout as in rtg_vram: byte A at HyperRAM word G_BASE_WORD + A/2, the even byte in
-- bits 7:0.
--
-- Done in 2026 (Megamiga, fork of AExp) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rtg_blitter is
   generic (
      G_BASE_WORD : natural := 16#200000#
   );
   port (
      -- registers (core clock)
      m_clk_i               : in  std_logic;
      m_sel_i               : in  std_logic;     -- an access to $B808xx
      m_wr_i                : in  std_logic;
      m_rs_i                : in  std_logic_vector(7 downto 1);
      m_data_i              : in  std_logic_vector(15 downto 0);
      m_data_o              : out std_logic_vector(15 downto 0);   -- valid the clock after m_sel_i

      -- engine (HyperRAM clock)
      h_clk_i               : in  std_logic;
      h_rst_i               : in  std_logic;
      h_quiet_i             : in  std_logic;     -- no CPU access on its way to the HyperRAM
      h_flush_o             : out std_logic;     -- to rtg_wcomb: send what you gathered
      h_busy_o              : out std_logic;     -- (for tests)
      avm_write_o           : out std_logic;
      avm_read_o            : out std_logic;
      avm_address_o         : out std_logic_vector(31 downto 0);
      avm_writedata_o       : out std_logic_vector(15 downto 0);
      avm_byteenable_o      : out std_logic_vector( 1 downto 0);
      avm_burstcount_o      : out std_logic_vector( 7 downto 0);
      avm_readdata_i        : in  std_logic_vector(15 downto 0);
      avm_readdatavalid_i   : in  std_logic;
      avm_waitrequest_i     : in  std_logic
   );
end entity rtg_blitter;

architecture synthesis of rtg_blitter is

   constant C_QUIET : natural := 16;

   -- register side (core clock); m_par_* are read by the engine only while a command runs
   signal m_par_src    : std_logic_vector(21 downto 0) := (others => '0');
   signal m_par_dst    : std_logic_vector(21 downto 0) := (others => '0');
   signal m_par_sstr   : std_logic_vector(15 downto 0) := (others => '0');
   signal m_par_dstr   : std_logic_vector(15 downto 0) := (others => '0');
   signal m_par_width  : std_logic_vector(12 downto 0) := (others => '0');
   signal m_par_height : std_logic_vector(15 downto 0) := (others => '0');
   signal m_par_pat    : std_logic_vector(31 downto 0) := (others => '0');
   signal m_par_bpp    : std_logic_vector( 2 downto 0) := "001";
   signal m_par_copy   : std_logic := '0';
   signal m_req        : std_logic := '0';  -- toggles on every command
   signal m_ack_meta   : std_logic := '0';
   signal m_ack        : std_logic := '0';
   signal m_dout       : std_logic_vector(15 downto 0) := (others => '0');

   attribute ASYNC_REG : string;
   attribute ASYNC_REG of m_ack_meta, m_ack : signal is "TRUE";

   -- engine (HyperRAM clock)
   type t_state is (E_IDLE, E_QUIET, E_LINE, E_RD_REQ, E_RD_DATA, E_WR_CHUNK, E_STAGE, E_WR_BURST,
                    E_NEXT, E_DONE);
   signal state        : t_state := E_IDLE;
   signal h_req_meta   : std_logic := '0';
   signal h_req        : std_logic := '0';
   signal h_ack        : std_logic := '0';  -- = h_req once a command is done
   attribute ASYNC_REG of h_req_meta, h_req : signal is "TRUE";
   signal quiet_cnt    : natural range 0 to C_QUIET := 0;

   -- latched parameters
   signal copy         : std_logic := '0';
   signal sline        : unsigned(21 downto 0) := (others => '0');  -- byte address of this line
   signal dline        : unsigned(21 downto 0) := (others => '0');
   signal sstr         : signed(15 downto 0) := (others => '0');
   signal dstr         : signed(15 downto 0) := (others => '0');
   signal width        : unsigned(12 downto 0) := (others => '0');
   signal lines        : unsigned(15 downto 0) := (others => '0');
   signal pat          : std_logic_vector(31 downto 0) := (others => '0');
   signal bpp          : unsigned(2 downto 0) := "001";

   -- per line
   signal rd_word      : unsigned(20 downto 0) := (others => '0');  -- next source word to read
   signal rd_left      : unsigned(12 downto 0) := (others => '0');  -- source words left
   signal rd_n         : unsigned(4 downto 0) := (others => '0');   -- words of this read burst
   signal rd_got       : unsigned(4 downto 0) := (others => '0');
   signal buf_widx     : unsigned(11 downto 0) := (others => '0');
   signal wr_word      : unsigned(20 downto 0) := (others => '0');  -- next destination word
   signal wr_first     : unsigned(20 downto 0) := (others => '0');  -- first destination word
   signal wr_last      : unsigned(20 downto 0) := (others => '0');  -- last destination word
   signal last_lane1   : std_logic := '0';                          -- last word: odd byte inside
   signal first_lane0  : std_logic := '0';                          -- first word: even byte inside
   signal misal        : std_logic := '0';                          -- source/destination parity differ
   signal d1           : std_logic := '0';                          -- (S odd, D even)
   signal pidx         : unsigned(1 downto 0) := (others => '0');   -- pattern byte of lane 0

   -- staging of one burst
   type t_data is array (0 to 15) of std_logic_vector(15 downto 0);
   type t_be   is array (0 to 15) of std_logic_vector( 1 downto 0);
   signal st_d         : t_data;
   signal st_be        : t_be := (others => "00");
   signal st_n         : unsigned(4 downto 0) := (others => '0');   -- words in the burst
   signal st_t         : unsigned(4 downto 0) := (others => '0');   -- staging step
   signal st_k         : unsigned(11 downto 0) := (others => '0');  -- next buffer word to read
   signal st_prev      : std_logic_vector(15 downto 0) := (others => '0');
   signal fidx         : unsigned(3 downto 0) := (others => '0');

   -- line buffer (one source line, up to 4096 words)
   type t_buf is array (0 to 4095) of std_logic_vector(15 downto 0);
   signal linebuf      : t_buf;
   signal buf_rdata    : std_logic_vector(15 downto 0) := (others => '0');
   signal buf_raddr    : unsigned(11 downto 0) := (others => '0');

   function pbyte(p : std_logic_vector(31 downto 0); i : unsigned(1 downto 0)) return std_logic_vector is
   begin
      case i is
         when "00"   => return p(31 downto 24);
         when "01"   => return p(23 downto 16);
         when "10"   => return p(15 downto 8);
         when others => return p(7 downto 0);
      end case;
   end function;

   -- (i + n) mod bpp for bpp 1, 2, 4
   function pnext(i : unsigned(1 downto 0); n : natural; b : unsigned(2 downto 0)) return unsigned is
      variable r : unsigned(1 downto 0);
   begin
      r := i + to_unsigned(n mod 4, 2);
      case b is
         when "001"  => return "00";
         when "010"  => return '0' & r(0);
         when others => return r;
      end case;
   end function;

begin

   ---------------------------------------------------------------------------------------------
   -- Registers
   ---------------------------------------------------------------------------------------------

   m_data_o <= m_dout;

   p_regs : process (m_clk_i)
   begin
      if rising_edge(m_clk_i) then
         m_ack_meta <= h_ack;
         m_ack      <= m_ack_meta;

         if m_sel_i = '1' and m_wr_i = '1' then
            case to_integer(unsigned(m_rs_i)) is
               when 0  => m_par_src(21 downto 16)  <= m_data_i(5 downto 0);
               when 1  => m_par_src(15 downto 0)   <= m_data_i;
               when 2  => m_par_dst(21 downto 16)  <= m_data_i(5 downto 0);
               when 3  => m_par_dst(15 downto 0)   <= m_data_i;
               when 4  => m_par_sstr               <= m_data_i;
               when 5  => m_par_dstr               <= m_data_i;
               when 6  => m_par_width              <= m_data_i(12 downto 0);
               when 7  => m_par_height             <= m_data_i;
               when 8  => m_par_pat(31 downto 16)  <= m_data_i;
               when 9  => m_par_pat(15 downto 0)   <= m_data_i;
               when 10 => m_par_bpp                <= m_data_i(2 downto 0);
               when 11 =>
                  if m_req = m_ack and (m_data_i(1 downto 0) = "01" or m_data_i(1 downto 0) = "10") then
                     m_par_copy <= m_data_i(1);
                     m_req      <= not m_req;
                  end if;
               when others => null;
            end case;
         end if;

         m_dout <= (others => '0');
         case to_integer(unsigned(m_rs_i)) is
            when 11     => m_dout(0) <= m_req xor m_ack;
            when 15     => m_dout    <= x"B11B";
            when others => null;
         end case;
      end if;
   end process p_regs;

   ---------------------------------------------------------------------------------------------
   -- Engine
   ---------------------------------------------------------------------------------------------

   h_busy_o  <= '0' when state = E_IDLE else '1';
   h_flush_o <= '1' when state = E_QUIET else '0';

   avm_write_o      <= '1' when state = E_WR_BURST else '0';
   avm_read_o       <= '1' when state = E_RD_REQ else '0';
   avm_address_o    <= std_logic_vector(to_unsigned(G_BASE_WORD, 32) + resize(rd_word, 32))
                       when state = E_RD_REQ else
                       std_logic_vector(to_unsigned(G_BASE_WORD, 32) + resize(wr_word, 32));
   avm_burstcount_o <= std_logic_vector(resize(rd_n, 8)) when state = E_RD_REQ else
                       std_logic_vector(resize(st_n, 8));
   avm_writedata_o  <= st_d(to_integer(fidx));
   avm_byteenable_o <= st_be(to_integer(fidx));

   -- line buffer: write from the read bursts, synchronous read for the staging
   p_buf : process (h_clk_i)
   begin
      if rising_edge(h_clk_i) then
         if state = E_RD_DATA and avm_readdatavalid_i = '1' then
            linebuf(to_integer(buf_widx)) <= avm_readdata_i;
         end if;
         buf_rdata <= linebuf(to_integer(buf_raddr));
      end if;
   end process p_buf;

   p_engine : process (h_clk_i)
      variable v_send  : unsigned(21 downto 0);
      variable v_n     : unsigned(4 downto 0);
      variable v_left  : unsigned(21 downto 0);
      variable v_i     : natural range 0 to 15;
      variable v_w     : std_logic_vector(15 downto 0);
      variable v_be    : std_logic_vector(1 downto 0);
      variable v_wa    : unsigned(20 downto 0);
   begin
      if rising_edge(h_clk_i) then
         h_req_meta <= m_req;
         h_req      <= h_req_meta;

         case state is
            when E_IDLE =>
               quiet_cnt <= 0;
               if h_req /= h_ack then
                  state <= E_QUIET;
               end if;

            when E_QUIET =>                              -- the CPU's own writes are through
               if h_quiet_i = '0' then
                  quiet_cnt <= 0;
               elsif quiet_cnt = C_QUIET then
                  copy  <= m_par_copy;
                  sline <= unsigned(m_par_src);
                  dline <= unsigned(m_par_dst);
                  sstr  <= signed(m_par_sstr);
                  dstr  <= signed(m_par_dstr);
                  width <= unsigned(m_par_width);
                  lines <= unsigned(m_par_height);
                  pat   <= m_par_pat;
                  bpp   <= unsigned(m_par_bpp);
                  state <= E_LINE;
               else
                  quiet_cnt <= quiet_cnt + 1;
               end if;

            when E_LINE =>                               -- set up one line
               if lines = 0 or width = 0 then
                  state <= E_DONE;
               else
                  v_send      := dline + resize(width, 22) - 1;
                  wr_first    <= dline(21 downto 1);
                  wr_word     <= dline(21 downto 1);
                  wr_last     <= v_send(21 downto 1);
                  first_lane0 <= not dline(0);
                  last_lane1  <= v_send(0);
                  misal       <= sline(0) xor dline(0);
                  d1          <= sline(0) and not dline(0);
                  -- pattern byte of lane 0 of the first word: 0, or the last one (D odd)
                  if dline(0) = '0' or bpp = "001" then
                     pidx <= "00";
                  elsif bpp = "010" then
                     pidx <= "01";
                  else
                     pidx <= "11";
                  end if;
                  v_send      := sline + resize(width, 22) - 1;
                  rd_word     <= sline(21 downto 1);
                  rd_left     <= resize(v_send(21 downto 1) - sline(21 downto 1) + 1, 13);
                  buf_widx    <= (others => '0');
                  if copy = '1' then
                     state <= E_RD_REQ;
                     v_left := resize(v_send(21 downto 1) - sline(21 downto 1) + 1, 22);
                     v_n    := to_unsigned(16 - to_integer(sline(4 downto 1)), 5);
                     if v_left < v_n then
                        v_n := v_left(4 downto 0);
                     end if;
                     rd_n <= v_n;
                  else
                     state <= E_WR_CHUNK;
                  end if;
               end if;

            when E_RD_REQ =>                             -- one read burst, inside a 16-word block
               rd_got <= (others => '0');
               if avm_waitrequest_i = '0' then
                  state <= E_RD_DATA;
               end if;

            when E_RD_DATA =>
               if avm_readdatavalid_i = '1' then
                  buf_widx <= buf_widx + 1;
                  rd_got   <= rd_got + 1;
                  if rd_got = rd_n - 1 then
                     rd_word <= rd_word + rd_n;
                     rd_left <= rd_left - rd_n;
                     if rd_left = rd_n then
                        state <= E_WR_CHUNK;
                     else
                        v_n := to_unsigned(16 - to_integer(rd_word(3 downto 0) + rd_n(3 downto 0)), 5);
                        if v_n = 0 then
                           v_n := to_unsigned(16, 5);
                        end if;
                        if resize(rd_left - rd_n, 13) < v_n then
                           v_n := resize(rd_left - rd_n, 5);
                        end if;
                        rd_n  <= v_n;
                        state <= E_RD_REQ;
                     end if;
                  end if;
               end if;

            when E_WR_CHUNK =>                           -- the next aligned destination block
               v_n := to_unsigned(16 - to_integer(wr_word(3 downto 0)), 5);
               if resize(wr_last - wr_word + 1, 21) < v_n then
                  v_n := resize(wr_last - wr_word + 1, 5);
               end if;
               st_n <= v_n;
               st_t <= (others => '0');
               -- buffer word of the first output word of this chunk, minus one (the "previous")
               st_k      <= resize(wr_word - wr_first, 12) + ("00000000000" & d1) - 1;
               buf_raddr <= resize(wr_word - wr_first, 12) + ("00000000000" & d1) - 1;
               state     <= E_STAGE;

            when E_STAGE =>                              -- one staging word per clock
               -- copy: buf_rdata is buffer word st_k-1+... (read issued the clock before)
               st_k      <= st_k + 1;
               buf_raddr <= st_k + 1;
               st_t      <= st_t + 1;
               if copy = '1' then
                  st_prev <= buf_rdata;
               end if;
               -- copy: the buffer read has two clocks of latency here (address register, BRAM
               -- output register), so word i is there at st_t = i + 2 and its predecessor in
               -- st_prev
               if st_t >= 2 or copy = '0' then
                  if copy = '1' then
                     v_i := to_integer(st_t - 2);
                     if misal = '1' then
                        v_w := buf_rdata(7 downto 0) & st_prev(15 downto 8);
                     else
                        v_w := buf_rdata;
                     end if;
                  else
                     v_i := to_integer(st_t);
                     v_w := pbyte(pat, pnext(pidx, 1, bpp)) & pbyte(pat, pidx);
                     pidx <= pnext(pidx, 2, bpp);
                  end if;
                  v_wa := wr_word + v_i;
                  v_be := "11";
                  if v_wa = wr_first and first_lane0 = '0' then
                     v_be(0) := '0';
                  end if;
                  if v_wa = wr_last and last_lane1 = '0' then
                     v_be(1) := '0';
                  end if;
                  st_d(v_i)  <= v_w;
                  st_be(v_i) <= v_be;
                  if (copy = '1' and st_t = st_n + 1) or (copy = '0' and st_t = st_n - 1) then
                     fidx  <= (others => '0');
                     state <= E_WR_BURST;
                  end if;
               end if;

            when E_WR_BURST =>
               if avm_waitrequest_i = '0' then
                  fidx <= fidx + 1;
                  if fidx = st_n - 1 then
                     wr_word <= wr_word + st_n;
                     if resize(wr_word, 22) + st_n > resize(wr_last, 22) then
                        state <= E_NEXT;
                     else
                        state <= E_WR_CHUNK;
                     end if;
                  end if;
               end if;

            when E_NEXT =>
               sline <= unsigned(signed(sline) + resize(sstr, 22));
               dline <= unsigned(signed(dline) + resize(dstr, 22));
               lines <= lines - 1;
               state <= E_LINE;

            when E_DONE =>
               h_ack <= h_req;
               state <= E_IDLE;
         end case;

         if h_rst_i = '1' then
            state <= E_IDLE;
            h_ack <= h_req;
         end if;
      end if;
   end process p_engine;

end architecture synthesis;
