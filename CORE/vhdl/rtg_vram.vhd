---------------------------------------------------------------------------------------------------------
-- Megamiga (Amiga for MEGA65, fork of AExp)
--
-- rtg_vram: the RTG board memory for the 68020 - cpu_wrapper's ram* bus cycles to $02000000..
-- (ramaddr[26] = 1) as Avalon accesses to the MEGA65's HyperRAM, where ascal's
-- framebuffer mode reads the picture (M2M-UPSTREAM rtg-framebuffer).
--
-- Layout: 4 MB at HyperRAM byte address G_BASE_BYTE ($400000; the floppy buffers that used to be
-- there live in the SDRAM since Megamiga 0.3.1). The Amiga sees it at $02000000-$023FFFFF; higher
-- addresses wrap. Picasso96 learns the size from the driver (CORE/rtg/MiSTer.card.asm).
--
-- Byte order: as on MiSTer. cpu_wrapper swaps the bytes of every RTG access, so the EVEN Amiga byte
-- arrives in bits 7:0 with its strobe on lds_n_i; Avalon byte lane 0 (bits 7:0) is the even byte
-- address, which is what ascal reads (little-endian byte addressing, like MiSTer's DDR3).
--
-- Handshake with TG68K: ready_o is high for exactly ONE core clock per access. TG68K has no address
-- strobe gap between two accesses (MOVEM, longwords), so the clock after a ready is skipped (S_DONE):
-- the next access is only taken once the CPU has had a clock to present it (cpu_wrapper's ext_done
-- does the same for the IDE board). Writes are posted: they complete as soon as the CDC FIFO in the
-- parent took them.
--
-- Read-ahead: a read that misses fetches the whole aligned 16-word block (one HyperRAM burst) into
-- one of two line buffers; the CPU gets its word as soon as it arrives, later reads of the block are
-- answered here in one clock. The lines stay coherent: CPU writes update a line that holds their
-- word (and go to the HyperRAM as before), and inval_i (the blitter is busy) clears both lines - and
-- spoils a fill that sees it. Reads wait for the data; a watchdog returns 0xFFFF if a response never
-- comes (a reset of the HyperRAM side alone would otherwise hang the CPU for good).
--
-- Done in 2026 (Megamiga, fork of AExp) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rtg_vram is
   generic (
      G_BASE_WORD : natural := 16#200000#        -- HyperRAM 16-bit word address of the board memory
   );
   port (
      clk_i                 : in  std_logic;     -- core clock
      rst_i                 : in  std_logic;

      -- cpu_wrapper ram* cycle (already byte-swapped for RTG by cpu_wrapper)
      sel_i                 : in  std_logic;     -- ramsel and ramaddr[26]
      we_i                  : in  std_logic;     -- '1' = write
      addr_i                : in  std_logic_vector(21 downto 1);   -- word offset in the 4 MB
      lds_n_i               : in  std_logic;     -- lane 0 (bits 7:0) = the even byte
      uds_n_i               : in  std_logic;     -- lane 1 (bits 15:8) = the odd byte
      data_i                : in  std_logic_vector(15 downto 0);
      data_o                : out std_logic_vector(15 downto 0);
      ready_o               : out std_logic;
      inval_i               : in  std_logic := '0';   -- drop the read-ahead lines (blitter busy)

      -- Avalon master (core clock; the parent crosses it to the HyperRAM clock)
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
end entity rtg_vram;

architecture synthesis of rtg_vram is

   type t_state is (S_IDLE, S_WRITE, S_READ, S_RDATA, S_DONE);
   type t_lines is array (0 to 31) of std_logic_vector(7 downto 0);    -- line L, word i: L*16+i
   type t_tags  is array (0 to 1) of std_logic_vector(21 downto 5);

   signal state     : t_state := S_IDLE;
   signal ready     : std_logic := '0';
   signal data      : std_logic_vector(15 downto 0) := (others => '1');
   signal avm_write : std_logic := '0';
   signal avm_read  : std_logic := '0';
   signal watchdog  : unsigned(12 downto 0) := (others => '0');

   signal lines_lo  : t_lines;                       -- byte lanes, one write port each
   signal lines_hi  : t_lines;
   signal tags      : t_tags := (others => (others => '0'));
   signal valid     : std_logic_vector(1 downto 0) := "00";
   signal victim    : natural range 0 to 1 := 0;     -- the line the next miss replaces
   signal f_line    : natural range 0 to 1 := 0;     -- the line being filled
   signal f_idx     : unsigned(3 downto 0) := (others => '0');   -- next word of the fill
   signal f_want    : unsigned(3 downto 0) := (others => '0');   -- the word the CPU waits for
   signal f_given   : std_logic := '0';                          -- the CPU has it
   signal f_spoil   : std_logic := '0';                          -- inval_i during the fill

   signal hit0      : std_logic;
   signal hit1      : std_logic;

begin

   ready_o          <= ready;
   data_o           <= data;
   avm_write_o      <= avm_write;
   avm_read_o       <= avm_read;

   hit0 <= '1' when valid(0) = '1' and tags(0) = addr_i(21 downto 5) else '0';
   hit1 <= '1' when valid(1) = '1' and tags(1) = addr_i(21 downto 5) else '0';

   p_fsm : process (clk_i)
      variable v_l    : natural range 0 to 1;
      variable v_rdy  : std_logic;
      variable v_we   : std_logic_vector(1 downto 0);    -- line write (one per clock)
      variable v_widx : natural range 0 to 31;
      variable v_wd   : std_logic_vector(15 downto 0);
   begin
      if rising_edge(clk_i) then
         ready <= '0';
         v_rdy := '0';
         v_we  := "00";
         v_widx := 0;
         v_wd  := data_i;

         case state is
            when S_IDLE =>
               if sel_i = '1' then
                  avm_writedata_o  <= data_i;
                  avm_byteenable_o <= (not uds_n_i) & (not lds_n_i);
                  watchdog         <= (others => '0');
                  if hit1 = '1' then
                     v_l := 1;
                  else
                     v_l := 0;
                  end if;
                  if we_i = '1' then
                     avm_address_o    <= std_logic_vector(to_unsigned(G_BASE_WORD, 32) +
                                                          unsigned(addr_i));
                     avm_burstcount_o <= x"01";
                     avm_write        <= '1';
                     state            <= S_WRITE;
                     if (hit0 or hit1) = '1' then     -- keep the line up to date
                        v_we   := (not uds_n_i) & (not lds_n_i);
                        v_widx := v_l * 16 + to_integer(unsigned(addr_i(4 downto 1)));
                        v_wd   := data_i;
                     end if;
                  elsif (hit0 or hit1) = '1' then     -- read-ahead hit
                     data   <= lines_hi(v_l * 16 + to_integer(unsigned(addr_i(4 downto 1)))) &
                               lines_lo(v_l * 16 + to_integer(unsigned(addr_i(4 downto 1))));
                     ready  <= '1';
                     victim <= 1 - v_l;
                     state  <= S_DONE;
                  else                                -- miss: fetch the whole block
                     avm_address_o    <= std_logic_vector(to_unsigned(G_BASE_WORD, 32) +
                                         unsigned(std_logic_vector'(addr_i(21 downto 5) & "0000")));
                     avm_burstcount_o <= x"10";
                     avm_read         <= '1';
                     valid(victim)    <= '0';
                     tags(victim)     <= addr_i(21 downto 5);
                     f_line           <= victim;
                     victim           <= 1 - victim;
                     f_idx            <= (others => '0');
                     f_want           <= unsigned(addr_i(4 downto 1));
                     f_given          <= '0';
                     f_spoil          <= '0';
                     state            <= S_READ;
                  end if;
               end if;

            when S_WRITE =>                              -- posted: done once accepted
               if avm_waitrequest_i = '0' then
                  avm_write <= '0';
                  ready     <= '1';
                  state     <= S_DONE;
               end if;

            when S_READ | S_RDATA =>
               if state = S_READ and avm_waitrequest_i = '0' then
                  avm_read <= '0';
                  state    <= S_RDATA;
               end if;
               if state = S_RDATA then
                  watchdog <= watchdog + 1;
               end if;
               if avm_readdatavalid_i = '1' then
                  v_we   := "11";
                  v_widx := f_line * 16 + to_integer(f_idx);
                  v_wd   := avm_readdata_i;
                  f_idx <= f_idx + 1;
                  if f_idx = f_want and f_given = '0' then   -- the CPU's word: answer at once
                     data    <= avm_readdata_i;
                     ready   <= '1';
                     v_rdy   := '1';
                     f_given <= '1';
                  end if;
                  if f_idx = 15 then                         -- block complete
                     avm_read      <= '0';
                     valid(f_line) <= not (f_spoil or inval_i);
                     if v_rdy = '1' then
                        state <= S_DONE;                     -- the skipped clock after ready
                     else
                        state <= S_IDLE;
                     end if;
                  end if;
               elsif state = S_RDATA and watchdog = (watchdog'range => '1') then
                  if f_given = '0' then                      -- lost response: do not hang
                     data  <= (others => '1');
                     ready <= '1';
                     state <= S_DONE;
                  else
                     state <= S_IDLE;
                  end if;
               end if;

            when S_DONE =>                               -- the CPU takes ready now; skip
               state <= S_IDLE;                          -- this clock (see the header)
         end case;

         if v_we(0) = '1' then
            lines_lo(v_widx) <= v_wd(7 downto 0);
         end if;
         if v_we(1) = '1' then
            lines_hi(v_widx) <= v_wd(15 downto 8);
         end if;

         if inval_i = '1' then
            valid   <= "00";
            f_spoil <= '1';
         end if;

         if rst_i = '1' then
            state     <= S_IDLE;
            ready     <= '0';
            avm_write <= '0';
            avm_read  <= '0';
            valid     <= "00";
            victim    <= 0;
         end if;
      end if;
   end process p_fsm;

end architecture synthesis;
