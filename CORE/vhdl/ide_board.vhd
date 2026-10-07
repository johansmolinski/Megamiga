---------------------------------------------------------------------------------------------------------
-- Amiga 500 for MEGA65 (AExp)
--
-- ide_board: a Zorro II IDE controller, register-compatible with RIPPLE
-- (github.com/LIV2/RIPPLE-IDE), so that the open-source lide.device boot ROM
-- (github.com/LIV2/lide.device) autoboots Kickstart 1.3 from it. The drive behind it
-- is an HDF image on the SD card, served by the QNICE firmware.
--
-- The autoconfig part lives in cpu_wrapper.v (it owns the chain); this module serves the
-- bus cycles of the configured 128 KB board (sel_i = ext_sel of cpu_wrapper):
--
--   ROM    Before the first write to the board the ROM fills the whole board; afterwards
--          it is at +64 KB, and also wherever address bits 13 and 12 are equal (RIPPLE's
--          IDE_ROMEN). ROM byte k is at board offset 2k on the upper data byte (an 8-bit
--          flash on D15..D8), so the nibble-wide DiagArea at offset 0x0008 is ROM byte 4.
--          The 32 KB lide.rom lives in HyperRAM (loaded by a byte-window bridge, even ROM
--          bytes in bits 7:0 of a word); reads go through rom_avm_* with a 1-word cache.
--   IDE    Channel 0 at offset 0x1000, register n at 0x1000 + n * 0x200 (A11..A9), so that
--          a MOVEM burst stays on the data register. A14 selects the control block
--          (device control, alternate status). The 8-bit registers are on D15..D8 (RIPPLE's
--          IDE bus is byte-swapped, so sector data needs no swapping). Channel 1, an absent
--          drive and the slave read 0xFF: lide treats a register value with bits 7:6 = 11
--          as a floating bus.
--
-- Work split: the hardware does what must happen within a bus cycle - BSY on a command
-- write, DRQ off with the 256th data word - and the firmware does everything else, like
-- MiSTer's HPS side (ide.cpp) does for Minimig's ide.v. Firmware interface: QNICE device,
-- word addresses within the 4k window:
--
--   0x000-0x0FF  W: data for the CPU (read buffer)      R: data from the CPU (write buffer)
--   0x100        R: events: bit 0 command, bit 1 buffer done, bit 2 reset, bit 3 commit
--                   acknowledge - each a toggle; the firmware compares with the last value
--   0x101-0x107  R: task file snapshot: command, features, sector count, LBA 7:0, LBA 15:8,
--                   LBA 23:16, device/head (frozen while BSY)
--   0x110        R/W: status to apply on commit (BSY, DRDY, DF, DSC, DRQ, ..., ERR)
--   0x111        R/W: error register to apply on commit
--   0x112        R/W: bit 0: the data phase started by a commit with DRQ is CPU -> buffer
--                     bit 1: also apply the task file values 0x113-0x117
--   0x113-0x117  R/W: sector count, LBA 7:0, 15:8, 23:16, device/head to apply on commit
--   0x118        R/W: bit 0: drive present, bit 1: board enabled (in the autoconfig chain)
--   0x11F        W: commit (any value)
--   window 0xFFFF   the M2M CSR (qnice_csr.vhd): the OSM HDF mount line is a manual
--                CRT/ROM load into this device, so the Shell writes the file size and
--                STATUS=OK and then waits for PARSEST. PREP_LOAD_IMAGE moves the read
--                pointer to the end of the file (nothing is streamed: the firmware
--                serves the sectors from the file itself), and the responder answers
--                READY right away.
--
-- All registers above are in window 0; the firmware selects it before accessing them.
--
-- A commit is applied a few core clocks after its toggle crossed over (the payload was
-- written before it, so it has settled) and only while BSY is set: a late commit after an
-- Amiga reset can never raise DRQ. Each commit is acknowledged (event bit 3) either way.
-- Events are raised a few core clocks after the fact, so the snapshot has settled when
-- the firmware sees them. Resets (Amiga reset, 68000 RESET instruction, SRST) raise the
-- reset event, so the firmware can abandon a transfer in progress.
--
-- Done in 2026 (AExp fork, WIP-V2-A11-JS-01) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.qnice_csr_pkg.all;

entity ide_board is
   generic (
      G_ROM_BASE   : std_logic_vector(21 downto 0)   -- HyperRAM word address of lide.rom
   );
   port (
      -- core clock domain: the board's bus cycles (cpu_wrapper ext_* port)
      clk_i                  : in  std_logic;
      rst_i                  : in  std_logic;        -- Amiga reset or RESET instruction
      sel_i                  : in  std_logic;        -- bus cycle to the board
      rw_i                   : in  std_logic;        -- '1' = read
      uds_n_i                : in  std_logic;
      lds_n_i                : in  std_logic;
      addr_i                 : in  std_logic_vector(16 downto 1);  -- offset within the board
      data_i                 : in  std_logic_vector(15 downto 0);
      data_o                 : out std_logic_vector(15 downto 0);
      ready_o                : out std_logic;        -- -> DTACK
      board_ena_o            : out std_logic;        -- -> cpu_wrapper ide_ena
      activity_o             : out std_logic;        -- a command runs (BSY or DRQ): drive LED

      -- core clock domain: reading lide.rom from HyperRAM (via avm_fifo)
      rom_avm_read_o         : out std_logic;
      rom_avm_address_o      : out std_logic_vector(31 downto 0);
      rom_avm_waitrequest_i  : in  std_logic;
      rom_avm_readdata_i     : in  std_logic_vector(15 downto 0);
      rom_avm_readdatavalid_i: in  std_logic;

      -- QNICE clock domain: the firmware interface (see header)
      qnice_clk_i            : in  std_logic;
      qnice_rst_i            : in  std_logic;
      qnice_addr_i           : in  std_logic_vector(27 downto 0);
      qnice_data_i           : in  std_logic_vector(15 downto 0);
      qnice_ce_i             : in  std_logic;
      qnice_we_i             : in  std_logic;
      qnice_data_o           : out std_logic_vector(15 downto 0);
      qnice_wait_o           : out std_logic
   );
end entity ide_board;

architecture synthesis of ide_board is

   -- status bits
   constant C_BSY  : natural := 7;
   constant C_DRQ  : natural := 3;
   constant C_ST_READY : std_logic_vector(7 downto 0) := x"50";   -- DRDY | DSC
   constant C_ST_BUSY  : std_logic_vector(7 downto 0) := x"80";

   constant C_EVT_DELAY : natural := 8;   -- core clocks between an event and its toggle

   constant C_ERROR_STRINGS : string_vector(0 to 15) := (others => "OK                 \n");

   -- the two sector buffers: distributed RAM, one write port each, asynchronous read
   type t_buf is array (0 to 255) of std_logic_vector(15 downto 0);
   signal rd_buf : t_buf := (others => (others => '0'));   -- QNICE writes, CPU reads
   signal wr_buf : t_buf := (others => (others => '0'));   -- CPU writes, QNICE reads
   attribute ram_style : string;
   attribute ram_style of rd_buf : signal is "distributed";
   attribute ram_style of wr_buf : signal is "distributed";

   ---------------------------------------------------------------------------------------
   -- core clock domain
   ---------------------------------------------------------------------------------------

   type t_bus is (B_IDLE, B_ROM_REQ, B_ROM_WAIT, B_ACK);
   signal bus_state   : t_bus := B_IDLE;
   signal ready       : std_logic := '0';
   signal ack_rw      : std_logic := '1';
   signal rdata       : std_logic_vector(15 downto 0) := (others => '1');
   signal lat_addr    : std_logic_vector(16 downto 1) := (others => '0');

   signal ide_enabled : std_logic := '0';

   signal rom_read    : std_logic := '0';
   signal rom_c_valid : std_logic := '0';
   signal rom_c_addr  : std_logic_vector(13 downto 0) := (others => '0');
   signal rom_c_data  : std_logic_vector(15 downto 0) := (others => '0');

   -- ATA task file and state
   signal tf_feat, tf_scnt, tf_lba0, tf_lba1, tf_lba2, tf_cmd : std_logic_vector(7 downto 0) := (others => '0');
   signal tf_devh     : std_logic_vector(7 downto 0) := x"A0";
   signal status      : std_logic_vector(7 downto 0) := C_ST_READY;
   signal error       : std_logic_vector(7 downto 0) := x"01";
   signal srst        : std_logic := '0';
   signal phase_wr    : std_logic := '0';
   signal ptr         : unsigned(7 downto 0) := (others => '0');

   -- events to the firmware (toggles, raised C_EVT_DELAY clocks late)
   signal evt_cmd, evt_buf, evt_rst, evt_ack : std_logic := '0';
   signal dly_cmd, dly_buf, dly_rst, dly_ack : natural range 0 to C_EVT_DELAY := 0;

   -- commit from the firmware
   signal m_present, m_board_ena : std_logic;
   signal m_commit_tgl, commit_seen : std_logic := '0';
   signal m_nstat, m_nerr, m_nflags, m_nscnt, m_nlba0, m_nlba1, m_nlba2, m_ndevh : std_logic_vector(7 downto 0);
   signal dly_commit  : natural range 0 to C_EVT_DELAY := 0;

   ---------------------------------------------------------------------------------------
   -- QNICE clock domain
   ---------------------------------------------------------------------------------------

   signal q_nstat   : std_logic_vector(7 downto 0) := C_ST_READY;
   signal q_nerr    : std_logic_vector(7 downto 0) := (others => '0');
   signal q_nflags  : std_logic_vector(7 downto 0) := (others => '0');
   signal q_nscnt, q_nlba0, q_nlba1, q_nlba2 : std_logic_vector(7 downto 0) := (others => '0');
   signal q_ndevh   : std_logic_vector(7 downto 0) := x"A0";
   signal q_ctrl    : std_logic_vector(1 downto 0) := "00";
   signal q_commit  : std_logic := '0';
   signal q_win0, q_reg_ce, q_csr, q_csr_wait : std_logic;
   signal q_csr_data, q_rd : std_logic_vector(15 downto 0);
   signal q_req_status, q_resp_status : std_logic_vector(3 downto 0);

   signal q_events  : std_logic_vector(3 downto 0);
   signal q_tf      : std_logic_vector(55 downto 0);

   signal q_bufaddr : unsigned(7 downto 0);

   -- CPU -> write buffer, one clock after the bus cycle (own process: LUTRAM inference)
   signal wb_we     : std_logic := '0';
   signal wb_addr   : unsigned(7 downto 0) := (others => '0');
   signal wb_data   : std_logic_vector(15 downto 0) := (others => '0');

   -- helpers
   function rd8(v : std_logic_vector(7 downto 0)) return std_logic_vector is
   begin
      return v & x"FF";                      -- 8-bit registers are on D15..D8
   end function rd8;

begin

   ready_o     <= ready and sel_i and not (rw_i xor ack_rw);
   data_o      <= rdata;
   board_ena_o <= m_board_ena;
   activity_o  <= status(C_BSY) or status(C_DRQ);

   rom_avm_read_o    <= rom_read;
   rom_avm_address_o <= std_logic_vector(resize(unsigned(G_ROM_BASE) + unsigned(lat_addr(15 downto 2)), 32));

   ---------------------------------------------------------------------------------------
   -- Bus cycles, ATA register file, events and commits (core clock)
   ---------------------------------------------------------------------------------------

   bus_proc : process (clk_i)
      variable a         : std_logic_vector(16 downto 1);
      variable is_rom    : boolean;
      variable is_tf     : boolean;   -- channel 0 command block
      variable is_ctl    : boolean;   -- channel 0 control block
      variable reg       : natural range 0 to 7;
      variable present   : boolean;
      variable byte      : std_logic_vector(7 downto 0);

      procedure buffer_done is
      begin
         status  <= C_ST_BUSY;
         dly_buf <= C_EVT_DELAY;
      end procedure;

      procedure device_reset is
      begin
         status   <= C_ST_READY;
         error    <= x"01";                   -- diagnostic code: no error
         tf_devh  <= x"A0";
         ptr      <= (others => '0');
         phase_wr <= '0';
         dly_rst  <= C_EVT_DELAY;
      end procedure;
   begin
      if rising_edge(clk_i) then
         wb_we <= '0';

         -- delayed event toggles
         if dly_cmd = 1 then evt_cmd <= not evt_cmd; end if;
         if dly_buf = 1 then evt_buf <= not evt_buf; end if;
         if dly_rst = 1 then evt_rst <= not evt_rst; end if;
         if dly_ack = 1 then evt_ack <= not evt_ack; end if;
         if dly_cmd /= 0 then dly_cmd <= dly_cmd - 1; end if;
         if dly_buf /= 0 then dly_buf <= dly_buf - 1; end if;
         if dly_rst /= 0 then dly_rst <= dly_rst - 1; end if;
         if dly_ack /= 0 then dly_ack <= dly_ack - 1; end if;

         -- commits from the firmware: applied C_EVT_DELAY clocks after the toggle, only
         -- while BSY, always acknowledged
         if m_commit_tgl /= commit_seen then
            commit_seen <= m_commit_tgl;
            dly_commit  <= C_EVT_DELAY;
         end if;
         if dly_commit /= 0 then
            dly_commit <= dly_commit - 1;
            if dly_commit = 1 then
               if status(C_BSY) = '1' then
                  status <= m_nstat;
                  error  <= m_nerr;
                  if m_nflags(1) = '1' then
                     tf_scnt <= m_nscnt;
                     tf_lba0 <= m_nlba0;
                     tf_lba1 <= m_nlba1;
                     tf_lba2 <= m_nlba2;
                     tf_devh <= m_ndevh;
                  end if;
                  if m_nstat(C_DRQ) = '1' then
                     ptr      <= (others => '0');
                     phase_wr <= m_nflags(0);
                  end if;
               end if;
               dly_ack <= C_EVT_DELAY;
            end if;
         end if;

         present := m_present = '1' and tf_devh(4) = '0';

         case bus_state is

            when B_IDLE =>
               ready <= '0';
               -- a write starts once a data strobe is valid (the data is valid then)
               if sel_i = '1' and (rw_i = '1' or uds_n_i = '0' or lds_n_i = '0') then
                  a        := addr_i;
                  lat_addr <= addr_i;
                  ack_rw   <= rw_i;
                  is_rom   := ide_enabled = '0' or a(16) = '1' or a(13) = a(12);
                  is_tf    := ide_enabled = '1' and a(16 downto 12) = "00001";
                  is_ctl   := ide_enabled = '1' and a(16 downto 12) = "00101";
                  reg      := to_integer(unsigned(a(11 downto 9)));
                  byte     := data_i(15 downto 8);
                  rdata    <= (others => '1');

                  if rw_i = '1' then
                     -------------------------------------------------------------- reads
                     if is_rom then
                        if rom_c_valid = '1' and rom_c_addr = a(15 downto 2) then
                           rdata     <= (rom_c_data(7 downto 0) & x"FF") when a(1) = '0' else
                                        (rom_c_data(15 downto 8) & x"FF");
                           ready     <= '1';
                           bus_state <= B_ACK;
                        else
                           rom_read  <= '1';
                           bus_state <= B_ROM_REQ;
                        end if;
                     else
                        if (is_tf or is_ctl) and present then
                           if is_ctl then
                              if reg = 6 then rdata <= rd8(status); end if;   -- alternate status
                           else
                              case reg is
                                 when 0 =>
                                    if status(C_DRQ) = '1' and phase_wr = '0' then
                                       rdata <= rd_buf(to_integer(ptr));
                                       ptr   <= ptr + 1;
                                       if ptr = 255 then
                                          buffer_done;
                                       end if;
                                    else
                                       rdata <= (others => '0');
                                    end if;
                                 when 1 => rdata <= rd8(error);
                                 when 2 => rdata <= rd8(tf_scnt);
                                 when 3 => rdata <= rd8(tf_lba0);
                                 when 4 => rdata <= rd8(tf_lba1);
                                 when 5 => rdata <= rd8(tf_lba2);
                                 when 6 => rdata <= rd8(tf_devh);
                                 when others => rdata <= rd8(status);
                              end case;
                           end if;
                        end if;
                        ready     <= '1';
                        bus_state <= B_ACK;
                     end if;
                  else
                     -------------------------------------------------------------- writes
                     if uds_n_i = '0' then
                        ide_enabled <= '1';          -- RIPPLE: the first write maps the IDE in
                     end if;
                     if is_tf then
                        case reg is
                           when 0 =>
                              if present and status(C_DRQ) = '1' and phase_wr = '1' then
                                 wb_we   <= '1';
                                 wb_addr <= ptr;
                                 wb_data <= data_i;
                                 ptr     <= ptr + 1;
                                 if ptr = 255 then
                                    buffer_done;
                                 end if;
                              end if;
                           when 6 =>
                              tf_devh <= byte;       -- always: it selects master/slave
                           when 7 =>
                              if present and status(C_BSY) = '0' then
                                 tf_cmd  <= byte;
                                 status  <= C_ST_BUSY;
                                 error   <= x"00";
                                 dly_cmd <= C_EVT_DELAY;
                              end if;
                           when others =>
                              if status(C_BSY) = '0' then
                                 case reg is
                                    when 1 => tf_feat <= byte;
                                    when 2 => tf_scnt <= byte;
                                    when 3 => tf_lba0 <= byte;
                                    when 4 => tf_lba1 <= byte;
                                    when 5 => tf_lba2 <= byte;
                                    when others => null;
                                 end case;
                              end if;
                        end case;
                     elsif is_ctl and reg = 6 then   -- device control: SRST is bit 2
                        srst <= byte(2);
                        if byte(2) = '1' then
                           status <= C_ST_BUSY;
                        elsif srst = '1' then
                           device_reset;
                        end if;
                     end if;
                     ready     <= '1';
                     bus_state <= B_ACK;
                  end if;
               end if;

            when B_ROM_REQ =>
               if rom_avm_waitrequest_i = '0' then
                  rom_read  <= '0';
                  bus_state <= B_ROM_WAIT;
               end if;

            when B_ROM_WAIT =>
               if rom_avm_readdatavalid_i = '1' then
                  rom_c_valid <= '1';
                  rom_c_addr  <= lat_addr(15 downto 2);
                  rom_c_data  <= rom_avm_readdata_i;
                  rdata       <= (rom_avm_readdata_i(7 downto 0) & x"FF") when lat_addr(1) = '0' else
                                 (rom_avm_readdata_i(15 downto 8) & x"FF");
                  ready       <= '1';
                  bus_state   <= B_ACK;
               end if;

            when B_ACK =>
               -- hold DTACK until the cycle ends (AS negated or the direction changed)
               if sel_i = '0' or rw_i /= ack_rw then
                  ready     <= '0';
                  bus_state <= B_IDLE;
               end if;
         end case;

         if rst_i = '1' then
            bus_state   <= B_IDLE;
            ready       <= '0';
            rom_read    <= '0';
            rom_c_valid <= '0';
            ide_enabled <= '0';
            srst        <= '0';
            tf_feat <= (others => '0'); tf_scnt <= (others => '0'); tf_lba0 <= (others => '0');
            tf_lba1 <= (others => '0'); tf_lba2 <= (others => '0'); tf_cmd  <= (others => '0');
            device_reset;
         end if;
      end if;
   end process bus_proc;

   wr_buf_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if wb_we = '1' then
            wr_buf(to_integer(wb_addr)) <= wb_data;
         end if;
      end if;
   end process wr_buf_proc;

   ---------------------------------------------------------------------------------------
   -- Clock domain crossings (both directions: slowly changing values plus toggles; the
   -- toggles follow their payload, see the header)
   ---------------------------------------------------------------------------------------

   i_cdc_to_core : entity work.cdc_stable
      generic map (
         G_DATA_SIZE    => 67,
         G_REGISTER_SRC => true
      )
      port map (
         src_clk_i                => qnice_clk_i,
         src_data_i( 7 downto  0) => q_nstat,
         src_data_i(15 downto  8) => q_nerr,
         src_data_i(23 downto 16) => q_nflags,
         src_data_i(31 downto 24) => q_nscnt,
         src_data_i(39 downto 32) => q_nlba0,
         src_data_i(47 downto 40) => q_nlba1,
         src_data_i(55 downto 48) => q_nlba2,
         src_data_i(63 downto 56) => q_ndevh,
         src_data_i(64)           => q_ctrl(0),
         src_data_i(65)           => q_ctrl(1),
         src_data_i(66)           => q_commit,
         dst_clk_i                => clk_i,
         dst_data_o( 7 downto  0) => m_nstat,
         dst_data_o(15 downto  8) => m_nerr,
         dst_data_o(23 downto 16) => m_nflags,
         dst_data_o(31 downto 24) => m_nscnt,
         dst_data_o(39 downto 32) => m_nlba0,
         dst_data_o(47 downto 40) => m_nlba1,
         dst_data_o(55 downto 48) => m_nlba2,
         dst_data_o(63 downto 56) => m_ndevh,
         dst_data_o(64)           => m_present,
         dst_data_o(65)           => m_board_ena,
         dst_data_o(66)           => m_commit_tgl
      ); -- i_cdc_to_core

   i_cdc_to_qnice : entity work.cdc_stable
      generic map (
         G_DATA_SIZE    => 60,
         G_REGISTER_SRC => true
      )
      port map (
         src_clk_i                => clk_i,
         src_data_i( 7 downto  0) => tf_cmd,
         src_data_i(15 downto  8) => tf_feat,
         src_data_i(23 downto 16) => tf_scnt,
         src_data_i(31 downto 24) => tf_lba0,
         src_data_i(39 downto 32) => tf_lba1,
         src_data_i(47 downto 40) => tf_lba2,
         src_data_i(55 downto 48) => tf_devh,
         src_data_i(56)           => evt_cmd,
         src_data_i(57)           => evt_buf,
         src_data_i(58)           => evt_rst,
         src_data_i(59)           => evt_ack,
         dst_clk_i                => qnice_clk_i,
         dst_data_o(55 downto  0) => q_tf,
         dst_data_o(59 downto 56) => q_events
      ); -- i_cdc_to_qnice

   ---------------------------------------------------------------------------------------
   -- Firmware interface (QNICE clock)
   ---------------------------------------------------------------------------------------

   q_bufaddr    <= unsigned(qnice_addr_i(7 downto 0));
   q_win0       <= '1' when qnice_addr_i(27 downto 12) = x"0000" else '0';
   q_reg_ce     <= qnice_ce_i and q_win0;

   -- the M2M CSR in window 0xFFFF: answers READY as soon as the Shell reports the file
   i_qnice_csr : entity work.qnice_csr
      generic map (
         G_ERROR_STRINGS => C_ERROR_STRINGS
      )
      port map (
         qnice_clk_i          => qnice_clk_i,
         qnice_rst_i          => qnice_rst_i,
         qnice_addr_i         => qnice_addr_i,
         qnice_data_i         => qnice_data_i,
         qnice_ce_i           => qnice_ce_i,
         qnice_we_i           => qnice_we_i,
         qnice_data_o         => q_csr_data,
         qnice_wait_o         => q_csr_wait,
         qnice_csr_o          => q_csr,
         qnice_req_status_o   => q_req_status,
         qnice_req_length_o   => open,
         qnice_resp_status_i  => q_resp_status,
         qnice_resp_error_i   => x"0",
         qnice_resp_address_i => (others => '0')
      ); -- i_qnice_csr

   q_resp_status <= C_CSR_RESP_READY when q_req_status = C_CSR_REQ_OK else C_CSR_RESP_IDLE;

   qnice_data_o <= q_csr_data when q_csr = '1' else q_rd;
   qnice_wait_o <= q_csr_wait when q_csr = '1' else '0';

   qnice_write_proc : process (qnice_clk_i)
   begin
      if falling_edge(qnice_clk_i) then
         if q_reg_ce = '1' and qnice_we_i = '1' then
            if qnice_addr_i(8) = '0' then
               rd_buf(to_integer(q_bufaddr)) <= qnice_data_i;
            else
               case qnice_addr_i(7 downto 0) is
                  when x"10" => q_nstat  <= qnice_data_i(7 downto 0);
                  when x"11" => q_nerr   <= qnice_data_i(7 downto 0);
                  when x"12" => q_nflags <= qnice_data_i(7 downto 0);
                  when x"13" => q_nscnt  <= qnice_data_i(7 downto 0);
                  when x"14" => q_nlba0  <= qnice_data_i(7 downto 0);
                  when x"15" => q_nlba1  <= qnice_data_i(7 downto 0);
                  when x"16" => q_nlba2  <= qnice_data_i(7 downto 0);
                  when x"17" => q_ndevh  <= qnice_data_i(7 downto 0);
                  when x"18" => q_ctrl   <= qnice_data_i(1 downto 0);
                  when x"1F" => q_commit <= not q_commit;
                  when others => null;
               end case;
            end if;
         end if;
         if qnice_rst_i = '1' then
            q_ctrl <= "00";
         end if;
      end if;
   end process qnice_write_proc;

   -- Read data is registered on the falling edge (address stable then, data consumed at
   -- the following rising edge, no wait states): the QNICE device data path into the
   -- CPU only sees one flip-flop - the pattern of physical_fdd_diag (WIP-V2-A5), which
   -- keeps the half-period qnice_dev_data_o cone short.
   qnice_read_proc : process (qnice_clk_i)
      variable d : std_logic_vector(15 downto 0);
   begin
      if falling_edge(qnice_clk_i) then
         d := (others => '0');
         if qnice_addr_i(8) = '0' then
            d := wr_buf(to_integer(q_bufaddr));
         else
            case qnice_addr_i(7 downto 0) is
               when x"00" => d(3 downto 0) := q_events;
               when x"01" => d(7 downto 0) := q_tf( 7 downto  0);
               when x"02" => d(7 downto 0) := q_tf(15 downto  8);
               when x"03" => d(7 downto 0) := q_tf(23 downto 16);
               when x"04" => d(7 downto 0) := q_tf(31 downto 24);
               when x"05" => d(7 downto 0) := q_tf(39 downto 32);
               when x"06" => d(7 downto 0) := q_tf(47 downto 40);
               when x"07" => d(7 downto 0) := q_tf(55 downto 48);
               when x"10" => d(7 downto 0) := q_nstat;
               when x"11" => d(7 downto 0) := q_nerr;
               when x"12" => d(7 downto 0) := q_nflags;
               when x"13" => d(7 downto 0) := q_nscnt;
               when x"14" => d(7 downto 0) := q_nlba0;
               when x"15" => d(7 downto 0) := q_nlba1;
               when x"16" => d(7 downto 0) := q_nlba2;
               when x"17" => d(7 downto 0) := q_ndevh;
               when x"18" => d(1 downto 0) := q_ctrl;
               when others => null;
            end case;
         end if;
         q_rd <= d;
      end if;
   end process qnice_read_proc;

end architecture synthesis;
