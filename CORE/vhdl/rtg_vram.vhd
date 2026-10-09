---------------------------------------------------------------------------------------------------------
-- Megamiga (Amiga for MEGA65, fork of AExp)
--
-- rtg_vram: the RTG board memory for the 68020 - cpu_wrapper's ram* bus cycles to $02000000..
-- (ramaddr[26] = 1) as Avalon single-word accesses to the MEGA65's HyperRAM, where ascal's
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
-- parent took them. Reads wait for the data; a watchdog returns 0xFFFF if a response never comes (a
-- reset of the HyperRAM side alone would otherwise hang the CPU for good).
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
   signal state     : t_state := S_IDLE;
   signal ready     : std_logic := '0';
   signal data      : std_logic_vector(15 downto 0) := (others => '1');
   signal avm_write : std_logic := '0';
   signal avm_read  : std_logic := '0';
   signal watchdog  : unsigned(12 downto 0) := (others => '0');

begin

   ready_o          <= ready;
   data_o           <= data;
   avm_write_o      <= avm_write;
   avm_read_o       <= avm_read;
   avm_burstcount_o <= x"01";

   p_fsm : process (clk_i)
   begin
      if rising_edge(clk_i) then
         ready <= '0';

         case state is
            when S_IDLE =>
               if sel_i = '1' then
                  avm_address_o    <= std_logic_vector(to_unsigned(G_BASE_WORD, 32) +
                                                       unsigned(addr_i));
                  avm_writedata_o  <= data_i;
                  avm_byteenable_o <= (not uds_n_i) & (not lds_n_i);
                  watchdog         <= (others => '0');
                  if we_i = '1' then
                     avm_write <= '1';
                     state     <= S_WRITE;
                  else
                     avm_read  <= '1';
                     state     <= S_READ;
                  end if;
               end if;

            when S_WRITE =>                              -- posted: done once accepted
               if avm_waitrequest_i = '0' then
                  avm_write <= '0';
                  ready     <= '1';
                  state     <= S_DONE;
               end if;

            when S_READ =>
               if avm_waitrequest_i = '0' then
                  avm_read <= '0';
                  state    <= S_RDATA;
               end if;
               if avm_readdatavalid_i = '1' then         -- (a response in the same clock)
                  avm_read <= '0';
                  data     <= avm_readdata_i;
                  ready    <= '1';
                  state    <= S_DONE;
               end if;

            when S_RDATA =>
               watchdog <= watchdog + 1;
               if avm_readdatavalid_i = '1' then
                  data  <= avm_readdata_i;
                  ready <= '1';
                  state <= S_DONE;
               elsif watchdog = (watchdog'range => '1') then
                  data  <= (others => '1');              -- lost response: do not hang
                  ready <= '1';
                  state <= S_DONE;
               end if;

            when S_DONE =>                               -- the CPU takes ready now; skip
               state <= S_IDLE;                          -- this clock (see the header)
         end case;

         if rst_i = '1' then
            state     <= S_IDLE;
            ready     <= '0';
            avm_write <= '0';
            avm_read  <= '0';
         end if;
      end if;
   end process p_fsm;

end architecture synthesis;
