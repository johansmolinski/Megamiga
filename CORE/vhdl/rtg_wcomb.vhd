---------------------------------------------------------------------------------------------------------
-- Megamiga (Amiga for MEGA65, fork of AExp)
--
-- rtg_wcomb: write combining for the RTG board memory, on the HyperRAM clock between the clock domain
-- FIFO (avm_fifo after rtg_vram) and the framework's hr_core port.
--
-- The 68020 writes the RTG memory one 16-bit word at a time, and on its own every word is a whole
-- HyperRAM transaction (command, latency, one word, recovery: ~15-20 HyperRAM clocks). This entity
-- gathers the words of one aligned 16-word block and sends them as ONE burst:
--
--   * a write to the word right after the gathered ones appends (up to the end of the aligned block);
--   * a write to a word that is already gathered merges its bytes into it (two byte writes of an
--     8-bit pixel pair become one word);
--   * anything else flushes first: a write elsewhere, a full block, G_IDLE clocks without a new
--     write (so the picture never waits long), and a read of a gathered word (reads elsewhere pass
--     the gathered words; the CPU never has more than one access outstanding, so there is no
--     ordering to keep between a read and writes to OTHER words).
--
-- The burst is sent from the local buffer at the full HyperRAM clock, so the controller never sees
-- a gap inside a burst. Byte enables go with every beat (the controller masks with RWDS per word).
-- Reads are single words and pass through; the read data comes straight from the master port.
--
-- Done in 2026 (Megamiga, fork of AExp) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rtg_wcomb is
   generic (
      G_IDLE : natural := 128                    -- clocks without a write until a partial block goes
   );
   port (
      clk_i                 : in  std_logic;     -- HyperRAM clock
      rst_i                 : in  std_logic;

      -- slave: single-word accesses (burstcount 1) from the clock domain FIFO
      s_avm_write_i         : in  std_logic;
      s_avm_read_i          : in  std_logic;
      s_avm_address_i       : in  std_logic_vector(31 downto 0);
      s_avm_writedata_i     : in  std_logic_vector(15 downto 0);
      s_avm_byteenable_i    : in  std_logic_vector( 1 downto 0);
      s_avm_waitrequest_o   : out std_logic;
      s_avm_readdata_o      : out std_logic_vector(15 downto 0);
      s_avm_readdatavalid_o : out std_logic;

      -- master: hr_core
      m_avm_write_o         : out std_logic;
      m_avm_read_o          : out std_logic;
      m_avm_address_o       : out std_logic_vector(31 downto 0);
      m_avm_writedata_o     : out std_logic_vector(15 downto 0);
      m_avm_byteenable_o    : out std_logic_vector( 1 downto 0);
      m_avm_burstcount_o    : out std_logic_vector( 7 downto 0);
      m_avm_readdata_i      : in  std_logic_vector(15 downto 0);
      m_avm_readdatavalid_i : in  std_logic;
      m_avm_waitrequest_i   : in  std_logic
   );
end entity rtg_wcomb;

architecture synthesis of rtg_wcomb is

   type t_state is (S_GATHER, S_FLUSH, S_READ, S_RDATA);
   type t_data  is array (0 to 15) of std_logic_vector(15 downto 0);
   type t_be    is array (0 to 15) of std_logic_vector( 1 downto 0);

   signal state     : t_state := S_GATHER;
   signal cnt       : unsigned(4 downto 0) := (others => '0');   -- gathered words (0..16)
   signal base      : unsigned(31 downto 0) := (others => '0');  -- address of the first one
   signal buf_d     : t_data;
   signal buf_be    : t_be := (others => "00");
   signal fidx      : unsigned(3 downto 0) := (others => '0');   -- beat being sent
   signal idle      : natural range 0 to G_IDLE := 0;
   signal rd_addr   : std_logic_vector(31 downto 0) := (others => '0');

   signal offs      : unsigned(31 downto 0);                     -- incoming address - base
   signal hit       : std_logic;                                 -- offs < cnt: a gathered word
   signal append    : std_logic;                                 -- offs = cnt, same block
   signal take_wr   : std_logic;
   signal take_rd   : std_logic;

begin

   offs    <= unsigned(s_avm_address_i) - base;
   hit     <= '1' when cnt /= 0 and offs < cnt else '0';
   append  <= '1' when cnt = 0 or
                       (offs = cnt and cnt /= 16 and s_avm_address_i(3 downto 0) /= "0000") else '0';

   -- a write is taken while gathering if it merges or appends; a read if it misses the buffer
   take_wr <= '1' when state = S_GATHER and s_avm_write_i = '1' and (hit = '1' or append = '1') else '0';
   take_rd <= '1' when state = S_GATHER and s_avm_read_i = '1' and s_avm_write_i = '0' and hit = '0'
              else '0';

   s_avm_waitrequest_o   <= not (take_wr or take_rd);
   s_avm_readdata_o      <= m_avm_readdata_i;
   s_avm_readdatavalid_o <= m_avm_readdatavalid_i;

   m_avm_write_o      <= '1' when state = S_FLUSH else '0';
   m_avm_read_o       <= '1' when state = S_READ else '0';
   m_avm_address_o    <= rd_addr when state = S_READ else std_logic_vector(base);
   m_avm_writedata_o  <= buf_d(to_integer(fidx));
   m_avm_byteenable_o <= buf_be(to_integer(fidx));
   m_avm_burstcount_o <= x"01" when state = S_READ else std_logic_vector(resize(cnt, 8));

   p_fsm : process (clk_i)
      variable i : natural range 0 to 15;
   begin
      if rising_edge(clk_i) then
         case state is
            when S_GATHER =>
               if take_wr = '1' then
                  idle <= 0;
                  if cnt = 0 then
                     base <= unsigned(s_avm_address_i);
                     i    := 0;
                  else
                     i    := to_integer(offs(3 downto 0));
                  end if;
                  if hit = '1' then                      -- merge the bytes
                     if s_avm_byteenable_i(0) = '1' then
                        buf_d(i)(7 downto 0)  <= s_avm_writedata_i(7 downto 0);
                     end if;
                     if s_avm_byteenable_i(1) = '1' then
                        buf_d(i)(15 downto 8) <= s_avm_writedata_i(15 downto 8);
                     end if;
                     buf_be(i) <= buf_be(i) or s_avm_byteenable_i;
                  else                                   -- append
                     buf_d(i)  <= s_avm_writedata_i;
                     buf_be(i) <= s_avm_byteenable_i;
                     cnt       <= cnt + 1;
                  end if;
               elsif take_rd = '1' then
                  rd_addr <= s_avm_address_i;
                  state   <= S_READ;
               elsif cnt /= 0 and (s_avm_write_i = '1' or s_avm_read_i = '1' or cnt = 16 or
                                   idle = G_IDLE) then
                  fidx  <= (others => '0');              -- the request waits for the flush
                  state <= S_FLUSH;
               elsif cnt /= 0 then
                  idle <= idle + 1;
               end if;

            when S_FLUSH =>
               if m_avm_waitrequest_i = '0' then
                  fidx <= fidx + 1;
                  if fidx = cnt - 1 then
                     cnt   <= (others => '0');
                     idle  <= 0;
                     state <= S_GATHER;
                  end if;
               end if;

            when S_READ =>
               if m_avm_waitrequest_i = '0' then
                  state <= S_RDATA;
               end if;
               if m_avm_readdatavalid_i = '1' then      -- (a response in the same clock)
                  state <= S_GATHER;
               end if;

            when S_RDATA =>
               if m_avm_readdatavalid_i = '1' then
                  state <= S_GATHER;
               end if;
         end case;

         if rst_i = '1' then
            state <= S_GATHER;
            cnt   <= (others => '0');
            idle  <= 0;
         end if;
      end if;
   end process p_fsm;

end architecture synthesis;
