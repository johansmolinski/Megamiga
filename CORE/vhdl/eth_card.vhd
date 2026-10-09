---------------------------------------------------------------------------------------------------------
-- Megamiga (Amiga for MEGA65, fork of AExp)
--
-- eth_card: the Zorro II network card (64 KB) around eth_mac: registers, TX buffer, RX ring, PHY
-- management and the power-on station address. The register map and the driver's view are in
-- doc/developers/ethernet.md; in short (byte offsets, 16-bit registers):
--
--   $0000 ID $E7E7   $0002 VERSION 1
--   $0004 CTRL       0 RX on, 1 broadcast, 2 multicast, 3 promiscuous, 4 RX IRQ on, 5 TX IRQ on
--   $0006 STATUS     0 link, 1 100 Mbit/s, 2 full duplex, 3 TX busy, 4 RX ring full
--   $0008 IRQ        0 frames waiting (level), 1 TX done (write 1 to clear)
--   $000A RX_HEAD    $000C RX_TAIL (R/W)   $000E TX_LEN (write = send)
--   $0010..$0015 MAC $0018 PHASE (1:0 RX, 3:2 TX)
--   $0020 RX_FRAMES  $0022 RX_DROPPED  $0024 RX_CRCERR  $0026 TX_FRAMES
--   $4000..$47FF TX buffer (write only)
--   $8000..$FFFF RX ring: 16 slots of 2 KB, word 0 = length without FCS, the frame from byte 2
--
-- Clock domains: the CPU side runs on the core clock (clk_i), the MAC side on the 50 MHz RMII clock.
-- The buffers are block RAM with one port per side. RX_HEAD and RX_TAIL cross as Gray code through
-- two flip-flops; TX start/done and the RX error events are toggles; CTRL, MAC, PHASE and TX_LEN are
-- quasi-static (the driver changes them only while the MAC side does not use them) and cross through
-- two flip-flops each (CORE.xdc bounds those paths).
--
-- RX: every frame is written into the head slot while it arrives (that slot is never one the CPU
-- reads); at the end it is committed (length word written, head advanced) if the FCS was right, the
-- size was 60..1514 bytes, the address filter let it through and the ring had room; otherwise it is
-- dropped and counted.
--
-- PHY: eth_reset_n_o stays low for 10 ms after configuration; then the management interface
-- advertises 100BASE-TX only (full and half duplex), restarts autonegotiation and polls the link
-- state about ten times a second.
--
-- Done in 2026 (Megamiga, fork of AExp) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_card is
   generic (
      G_RESET_CYCLES : natural := 500_000;   -- 50 MHz clocks of PHY reset (10 ms)
      G_POLL_CYCLES  : natural := 5_000_000; -- 50 MHz clocks between two link polls (100 ms)
      G_MDC_DIV      : natural := 16          -- MDC = 50 MHz / (2 * G_MDC_DIV)
   );
   port (
      -- CPU side (core clock): cpu_wrapper ext_* port, as the IDE board
      clk_i           : in  std_logic;
      rst_i           : in  std_logic;        -- Amiga reset: RX and interrupts off
      sel_i           : in  std_logic;
      rw_i            : in  std_logic;        -- '1' = read
      uds_n_i         : in  std_logic;
      lds_n_i         : in  std_logic;
      addr_i          : in  std_logic_vector(15 downto 1);
      data_i          : in  std_logic_vector(15 downto 0);
      data_o          : out std_logic_vector(15 downto 0);
      ready_o         : out std_logic;
      irq_o           : out std_logic;        -- INT2, level
      mac_init_i      : in  std_logic_vector(47 downto 0);   -- power-on station address
      mac_init_vld_i  : in  std_logic;        -- mac_init_i is valid (copied once)

      -- MAC side
      clk50_i         : in  std_logic;
      clk200_i        : in  std_logic;
      rst50_i         : in  std_logic;

      -- PHY
      phy_rxd_i       : in  std_logic_vector(1 downto 0);
      phy_crsdv_i     : in  std_logic;
      phy_txd_o       : out std_logic_vector(1 downto 0);
      phy_txen_o      : out std_logic;
      phy_mdc_o       : out std_logic;
      phy_mdio_i      : in  std_logic;
      phy_mdio_o      : out std_logic;
      phy_mdio_oe_o   : out std_logic;
      phy_reset_n_o   : out std_logic
   );
end entity eth_card;

architecture synthesis of eth_card is

   constant C_SLOTS : natural := 16;

   function to_gray(b : unsigned(3 downto 0)) return std_logic_vector is
   begin
      return std_logic_vector(b xor ('0' & b(3 downto 1)));
   end function;

   function from_gray(g : std_logic_vector(3 downto 0)) return unsigned is
      variable b : unsigned(3 downto 0);
   begin
      b(3) := g(3);
      for i in 2 downto 0 loop
         b(i) := b(i + 1) xor g(i);
      end loop;
      return b;
   end function;

   -- buffers: even and odd byte lanes (the CPU side is 16 bit, the MAC side 8 bit)
   type t_rx is array (0 to 16383) of std_logic_vector(7 downto 0);
   type t_tx is array (0 to 1023) of std_logic_vector(7 downto 0);
   signal rx_ev, rx_od : t_rx;
   signal tx_ev, tx_od : t_tx;
   attribute ram_style : string;
   attribute ram_style of rx_ev, rx_od, tx_ev, tx_od : signal is "block";   -- two clocks: no LUTRAM

   ---------------------------------------------------------------------------------------------
   -- CPU side
   ---------------------------------------------------------------------------------------------
   type t_bus is (B_IDLE, B_RD1, B_RD2, B_ACK);
   signal bus_state  : t_bus := B_IDLE;
   signal ready      : std_logic := '0';
   signal ack_rw     : std_logic := '1';
   signal rdata      : std_logic_vector(15 downto 0) := (others => '1');
   signal rx_raddr   : unsigned(13 downto 0) := (others => '0');
   signal rx_q_ev    : std_logic_vector(7 downto 0);
   signal rx_q_od    : std_logic_vector(7 downto 0);

   signal ctrl       : std_logic_vector(5 downto 0) := (others => '0');
   signal mac        : std_logic_vector(47 downto 0) := x"02000000_0000";
   signal mac_set    : std_logic := '0';
   signal phase      : std_logic_vector(3 downto 0) := "0101";
   signal tx_len     : unsigned(10 downto 0) := (others => '0');
   signal tx_req     : std_logic := '0';     -- toggles: send
   signal tx_busy    : std_logic := '0';
   signal tx_done    : std_logic := '0';     -- IRQ bit 1
   signal rx_tail    : unsigned(3 downto 0) := (others => '0');
   signal head_m1, head_m2 : std_logic_vector(3 downto 0) := (others => '0');
   signal rx_head_m  : unsigned(3 downto 0);
   signal tx_ack_m1, tx_ack_m2, tx_ack_m3 : std_logic := '0';
   signal ev_m1, ev_m2, ev_m3 : std_logic_vector(1 downto 0) := "00";   -- dropped, crc
   signal link_m1, link_m2 : std_logic_vector(2 downto 0) := "000";
   signal cnt_frames, cnt_drop, cnt_crc, cnt_tx : unsigned(15 downto 0) := (others => '0');
   signal head_last  : unsigned(3 downto 0) := (others => '0');
   signal rx_pend    : std_logic;

   attribute ASYNC_REG : string;
   attribute ASYNC_REG of head_m1, head_m2, tx_ack_m1, tx_ack_m2, ev_m1, ev_m2, link_m1, link_m2 :
      signal is "TRUE";

   ---------------------------------------------------------------------------------------------
   -- MAC side (50 MHz)
   ---------------------------------------------------------------------------------------------
   signal e_ctrl1, e_ctrl  : std_logic_vector(5 downto 0) := (others => '0');
   signal e_mac1, e_mac    : std_logic_vector(47 downto 0) := (others => '0');
   signal e_ph1, e_ph      : std_logic_vector(3 downto 0) := "0101";
   signal e_len1, e_len    : unsigned(10 downto 0) := (others => '0');
   signal e_req1, e_req2, e_req3 : std_logic := '0';
   signal e_tail1, e_tail2 : std_logic_vector(3 downto 0) := (others => '0');
   attribute ASYNC_REG of e_ctrl1, e_ctrl, e_mac1, e_mac, e_ph1, e_ph, e_len1, e_len,
                          e_req1, e_req2, e_tail1, e_tail2 : signal is "TRUE";

   signal e_head      : unsigned(3 downto 0) := (others => '0');
   signal e_head_g    : std_logic_vector(3 downto 0) := (others => '0');
   signal e_tx_ack    : std_logic := '0';
   signal e_ev        : std_logic_vector(1 downto 0) := "00";
   signal e_link      : std_logic_vector(2 downto 0) := "000";

   -- MAC interface
   signal m_rx_start, m_rx_valid, m_rx_end, m_rx_ok : std_logic;
   signal m_rx_byte   : std_logic_vector(7 downto 0);
   signal m_tx_start  : std_logic := '0';
   signal m_tx_addr   : unsigned(10 downto 0);
   signal m_tx_data   : std_logic_vector(7 downto 0);
   signal m_tx_busy   : std_logic;
   signal e_tx_run    : std_logic := '0';
   signal tx_q_ev, tx_q_od : std_logic_vector(7 downto 0);
   signal tx_lane     : std_logic := '0';

   -- RX writer
   type t_rw is (W_IDLE, W_FRAME, W_LEN_HI, W_LEN_LO, W_COMMIT);
   signal ws          : t_rw := W_IDLE;
   signal w_n         : unsigned(10 downto 0) := (others => '0');   -- bytes received (with FCS)
   signal w_long      : std_logic := '0';
   signal w_own       : std_logic := '1';
   signal w_bcast     : std_logic := '1';
   signal w_mcast     : std_logic := '0';
   signal w_we        : std_logic := '0';
   signal w_addr      : unsigned(14 downto 0) := (others => '0');   -- byte address in the ring
   signal w_data      : std_logic_vector(7 downto 0) := (others => '0');
   signal w_len       : unsigned(10 downto 0) := (others => '0');

   -- PHY management
   signal rst_cnt     : natural range 0 to G_RESET_CYCLES := 0;
   signal phy_up      : std_logic := '0';
   type t_mi is (M_WAIT, M_START, M_SHIFT, M_NEXT);
   signal ms          : t_mi := M_WAIT;
   signal m_step      : natural range 0 to 3 := 0;     -- 0: reg 4, 1: reg 0, 2: reg 1, 3: reg $1E
   signal m_div       : natural range 0 to G_MDC_DIV - 1 := 0;
   signal m_mdc       : std_logic := '0';
   signal m_bit       : natural range 0 to 64 := 0;
   signal m_sh        : std_logic_vector(63 downto 0) := (others => '1');
   signal m_rd        : std_logic := '0';
   signal m_in        : std_logic_vector(15 downto 0) := (others => '0');
   signal m_dly      : natural range 0 to G_POLL_CYCLES := 0;
   signal m_mdio_o    : std_logic := '1';
   signal m_mdio_oe   : std_logic := '0';
   signal m_mdio_i    : std_logic := '1';
   signal m_link      : std_logic := '0';

begin

   ---------------------------------------------------------------------------------------------
   -- Buffers
   ---------------------------------------------------------------------------------------------

   p_rx_w : process (clk50_i)
   begin
      if rising_edge(clk50_i) then
         if w_we = '1' then
            if w_addr(0) = '0' then
               rx_ev(to_integer(w_addr(14 downto 1))) <= w_data;
            else
               rx_od(to_integer(w_addr(14 downto 1))) <= w_data;
            end if;
         end if;
      end if;
   end process p_rx_w;

   p_rx_r : process (clk_i)
   begin
      if rising_edge(clk_i) then
         rx_q_ev <= rx_ev(to_integer(rx_raddr));
         rx_q_od <= rx_od(to_integer(rx_raddr));
      end if;
   end process p_rx_r;

   p_tx_w : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if bus_state = B_IDLE and sel_i = '1' and rw_i = '0' and addr_i(15 downto 11) = "01000" then
            if uds_n_i = '0' then
               tx_ev(to_integer(unsigned(addr_i(10 downto 1)))) <= data_i(15 downto 8);
            end if;
            if lds_n_i = '0' then
               tx_od(to_integer(unsigned(addr_i(10 downto 1)))) <= data_i(7 downto 0);
            end if;
         end if;
      end if;
   end process p_tx_w;

   p_tx_r : process (clk50_i)
   begin
      if rising_edge(clk50_i) then
         tx_q_ev <= tx_ev(to_integer(m_tx_addr(10 downto 1)));
         tx_q_od <= tx_od(to_integer(m_tx_addr(10 downto 1)));
         tx_lane <= m_tx_addr(0);
      end if;
   end process p_tx_r;

   m_tx_data <= tx_q_od when tx_lane = '1' else tx_q_ev;

   ---------------------------------------------------------------------------------------------
   -- CPU side
   ---------------------------------------------------------------------------------------------

   rx_head_m <= from_gray(head_m2);
   data_o    <= rdata;
   ready_o   <= ready and sel_i and not (rw_i xor ack_rw);
   rx_pend   <= '0' when rx_head_m = rx_tail else '1';
   irq_o     <= (ctrl(4) and ctrl(0) and rx_pend) or (ctrl(5) and tx_done);

   p_cpu : process (clk_i)
      variable v_reg : natural range 0 to 127;
      variable v_st  : std_logic_vector(15 downto 0);
   begin
      if rising_edge(clk_i) then
         head_m1   <= e_head_g;
         head_m2   <= head_m1;
         tx_ack_m1 <= e_tx_ack;
         tx_ack_m2 <= tx_ack_m1;
         tx_ack_m3 <= tx_ack_m2;
         ev_m1     <= e_ev;
         ev_m2     <= ev_m1;
         ev_m3     <= ev_m2;
         link_m1   <= e_link;
         link_m2   <= link_m1;

         if mac_init_vld_i = '1' and mac_set = '0' then
            mac     <= mac_init_i;
            mac_set <= '1';
         end if;

         -- events from the MAC side
         if tx_ack_m3 /= tx_ack_m2 then
            tx_busy <= '0';
            tx_done <= '1';
            cnt_tx  <= cnt_tx + 1;
         end if;
         if ev_m3(0) /= ev_m2(0) then
            cnt_drop <= cnt_drop + 1;
         end if;
         if ev_m3(1) /= ev_m2(1) then
            cnt_crc <= cnt_crc + 1;
         end if;
         head_last <= rx_head_m;
         if head_last /= rx_head_m then
            cnt_frames <= cnt_frames + 1;           -- one slot at a time (see the MAC side)
         end if;

         v_reg := to_integer(unsigned(addr_i(7 downto 1)));

         case bus_state is
            when B_IDLE =>
               ready <= '0';
               if sel_i = '1' and (rw_i = '1' or uds_n_i = '0' or lds_n_i = '0') then
                  ack_rw   <= rw_i;
                  rdata    <= (others => '0');
                  rx_raddr <= unsigned(addr_i(14 downto 1));
                  if rw_i = '0' then
                     --------------------------------------------------------------- writes
                     if addr_i(15 downto 8) = x"00" then
                        case v_reg is
                           when 2 =>                                         -- CTRL
                              if lds_n_i = '0' then
                                 ctrl <= data_i(5 downto 0);
                              end if;
                           when 4 =>                                         -- IRQ: W1C
                              if lds_n_i = '0' and data_i(1) = '1' then
                                 tx_done <= '0';
                              end if;
                           when 6 =>                                         -- RX_TAIL
                              if lds_n_i = '0' then
                                 rx_tail <= unsigned(data_i(3 downto 0));
                              end if;
                           when 7 =>                                         -- TX_LEN
                              if tx_busy = '0' then
                                 tx_len  <= unsigned(data_i(10 downto 0));
                                 tx_req  <= not tx_req;
                                 tx_busy <= '1';
                              end if;
                           when 8 =>                                         -- MAC 0, 1
                              if uds_n_i = '0' then mac(47 downto 40) <= data_i(15 downto 8); end if;
                              if lds_n_i = '0' then mac(39 downto 32) <= data_i(7 downto 0);  end if;
                           when 9 =>                                         -- MAC 2, 3
                              if uds_n_i = '0' then mac(31 downto 24) <= data_i(15 downto 8); end if;
                              if lds_n_i = '0' then mac(23 downto 16) <= data_i(7 downto 0);  end if;
                           when 10 =>                                        -- MAC 4, 5
                              if uds_n_i = '0' then mac(15 downto 8)  <= data_i(15 downto 8); end if;
                              if lds_n_i = '0' then mac(7 downto 0)   <= data_i(7 downto 0);  end if;
                           when 12 =>                                        -- PHASE
                              if lds_n_i = '0' then
                                 phase <= data_i(3 downto 0);
                              end if;
                           when others => null;
                        end case;
                     end if;
                     ready     <= '1';
                     bus_state <= B_ACK;
                  else
                     ---------------------------------------------------------------- reads
                     if addr_i(15) = '1' then                                -- RX ring
                        bus_state <= B_RD1;
                     else
                        if addr_i(15 downto 8) = x"00" then
                           v_st := (others => '0');
                           case v_reg is
                              when 0  => rdata <= x"E7E7";
                              when 1  => rdata <= x"0001";
                              when 2  => rdata(5 downto 0) <= ctrl;
                              when 3  =>
                                 v_st(2 downto 0) := link_m2;
                                 v_st(3) := tx_busy;
                                 if rx_head_m + 1 = rx_tail then
                                    v_st(4) := '1';
                                 end if;
                                 rdata <= v_st;
                              when 4  =>
                                 if rx_head_m /= rx_tail then
                                    rdata(0) <= '1';
                                 end if;
                                 rdata(1) <= tx_done;
                              when 5  => rdata(3 downto 0) <= std_logic_vector(rx_head_m);
                              when 6  => rdata(3 downto 0) <= std_logic_vector(rx_tail);
                              when 7  => rdata(10 downto 0) <= std_logic_vector(tx_len);
                              when 8  => rdata <= mac(47 downto 32);
                              when 9  => rdata <= mac(31 downto 16);
                              when 10 => rdata <= mac(15 downto 0);
                              when 12 => rdata(3 downto 0) <= phase;
                              when 16 => rdata <= std_logic_vector(cnt_frames);
                              when 17 => rdata <= std_logic_vector(cnt_drop);
                              when 18 => rdata <= std_logic_vector(cnt_crc);
                              when 19 => rdata <= std_logic_vector(cnt_tx);
                              when others => null;
                           end case;
                        end if;
                        ready     <= '1';
                        bus_state <= B_ACK;
                     end if;
                  end if;
               end if;

            when B_RD1 =>                                -- the RAM address is registered now
               bus_state <= B_RD2;

            when B_RD2 =>
               rdata     <= rx_q_ev & rx_q_od;
               ready     <= '1';
               bus_state <= B_ACK;

            when B_ACK =>
               if sel_i = '0' or rw_i /= ack_rw then
                  ready     <= '0';
                  bus_state <= B_IDLE;
               end if;
         end case;

         if rst_i = '1' then
            bus_state <= B_IDLE;
            ready     <= '0';
            ctrl      <= (others => '0');
            tx_done   <= '0';
         end if;
      end if;
   end process p_cpu;

   ---------------------------------------------------------------------------------------------
   -- MAC side
   ---------------------------------------------------------------------------------------------

   i_mac : entity work.eth_mac
      port map (
         clk50_i     => clk50_i,
         clk200_i    => clk200_i,
         rst_i       => rst50_i,
         phy_rxd_i   => phy_rxd_i,
         phy_crsdv_i => phy_crsdv_i,
         phy_txd_o   => phy_txd_o,
         phy_txen_o  => phy_txen_o,
         rx_phase_i  => e_ph(1 downto 0),
         tx_phase_i  => e_ph(3 downto 2),
         rx_start_o  => m_rx_start,
         rx_valid_o  => m_rx_valid,
         rx_byte_o   => m_rx_byte,
         rx_end_o    => m_rx_end,
         rx_ok_o     => m_rx_ok,
         tx_start_i  => m_tx_start,
         tx_len_i    => e_len,
         tx_addr_o   => m_tx_addr,
         tx_data_i   => m_tx_data,
         tx_busy_o   => m_tx_busy
      ); -- i_mac

   e_head_g <= to_gray(e_head);

   p_e : process (clk50_i)
      variable v_tail : unsigned(3 downto 0);
      variable v_pass : std_logic;
   begin
      if rising_edge(clk50_i) then
         e_ctrl1 <= ctrl;      e_ctrl <= e_ctrl1;
         e_mac1  <= mac;       e_mac  <= e_mac1;
         e_ph1   <= phase;     e_ph   <= e_ph1;
         e_len1  <= tx_len;    e_len  <= e_len1;
         e_req1  <= tx_req;    e_req2 <= e_req1;    e_req3 <= e_req2;
         e_tail1 <= to_gray(rx_tail);
         e_tail2 <= e_tail1;
         v_tail  := from_gray(e_tail2);

         -- TX: a request toggle starts the MAC (TX_LEN crossed four clocks before); the end of
         -- the frame and its gap toggles the acknowledge
         m_tx_start <= '0';
         if e_req3 /= e_req2 then
            m_tx_start <= '1';
            e_tx_run   <= '1';
         elsif e_tx_run = '1' and m_tx_start = '0' and m_tx_busy = '0' then
            e_tx_run <= '0';
            e_tx_ack <= not e_tx_ack;
         end if;

         -- RX writer
         w_we <= '0';
         case ws is
            when W_IDLE =>
               if m_rx_start = '1' then
                  ws      <= W_FRAME;
                  w_n     <= (others => '0');
                  w_long  <= '0';
                  w_own   <= '1';
                  w_bcast <= '1';
                  w_mcast <= '0';
               end if;

            when W_FRAME =>
               if m_rx_valid = '1' then
                  if w_n < 6 then                                     -- the destination address
                     if m_rx_byte /= e_mac(47 - 8 * to_integer(w_n) downto 40 - 8 * to_integer(w_n)) then
                        w_own <= '0';
                     end if;
                     if m_rx_byte /= x"FF" then
                        w_bcast <= '0';
                     end if;
                     if w_n = 0 then
                        w_mcast <= m_rx_byte(0);
                     end if;
                  end if;
                  if w_n = 1518 then                                  -- 1514 + FCS
                     w_long <= '1';
                  else
                     w_n    <= w_n + 1;
                     w_we   <= '1';
                     w_addr <= (e_head & "00000000000") + resize(w_n, 15) + 2;
                     w_data <= m_rx_byte;
                  end if;
               end if;
               if m_rx_end = '1' then
                  -- a broadcast frame is also a multicast one: check it first
                  if w_bcast = '1' then
                     v_pass := e_ctrl(1);
                  elsif w_mcast = '1' then
                     v_pass := e_ctrl(2);
                  else
                     v_pass := w_own;
                  end if;
                  v_pass := (v_pass or e_ctrl(3)) and e_ctrl(0);
                  w_len  <= w_n - 4;
                  ws     <= W_IDLE;
                  if m_rx_ok = '0' or w_long = '1' or w_n < 64 then
                     e_ev(1) <= not e_ev(1);                          -- bad FCS, runt or giant
                  elsif v_pass = '1' then
                     if e_head + 1 = v_tail then
                        e_ev(0) <= not e_ev(0);                       -- no room
                     else
                        ws <= W_LEN_HI;
                     end if;
                  end if;
               end if;

            when W_LEN_HI =>                                          -- the length word, then commit
               w_we   <= '1';
               w_addr <= e_head & "00000000000";
               w_data <= "00000" & std_logic_vector(w_len(10 downto 8));
               ws     <= W_LEN_LO;

            when W_LEN_LO =>
               w_we   <= '1';
               w_addr <= (e_head & "00000000000") + 1;
               w_data <= std_logic_vector(w_len(7 downto 0));
               ws     <= W_COMMIT;

            when W_COMMIT =>                                          -- the length is in the RAM
               ws     <= W_IDLE;
               e_head <= e_head + 1;
         end case;

         if rst50_i = '1' then
            ws       <= W_IDLE;
            e_tx_run <= '0';
         end if;
      end if;
   end process p_e;

   ---------------------------------------------------------------------------------------------
   -- PHY reset and management (MDC/MDIO)
   ---------------------------------------------------------------------------------------------

   phy_reset_n_o <= phy_up;
   phy_mdc_o     <= m_mdc;
   phy_mdio_o    <= m_mdio_o;
   phy_mdio_oe_o <= m_mdio_oe;

   p_mii : process (clk50_i)
      variable v_reg  : std_logic_vector(4 downto 0);
      variable v_wr   : std_logic;
      variable v_val  : std_logic_vector(15 downto 0);
   begin
      if rising_edge(clk50_i) then
         m_mdio_i <= phy_mdio_i;

         if rst_cnt /= G_RESET_CYCLES then
            rst_cnt <= rst_cnt + 1;
         else
            phy_up <= '1';
         end if;

         case ms is
            when M_WAIT =>                               -- after reset, between polls
               m_mdc <= '0';
               if phy_up = '1' then
                  if m_dly = G_POLL_CYCLES then
                     m_dly <= 0;
                     ms     <= M_START;
                  else
                     m_dly <= m_dly + 1;
                  end if;
               end if;

            when M_START =>
               case m_step is
                  when 0      => v_reg := "00100"; v_wr := '1'; v_val := x"0181";  -- advertise 100 only
                  when 1      => v_reg := "00000"; v_wr := '1'; v_val := x"3300";  -- AN on, restart
                  when 2      => v_reg := "00001"; v_wr := '0'; v_val := x"FFFF";  -- status
                  when others => v_reg := "11110"; v_wr := '0'; v_val := x"FFFF";  -- PHY control 1
               end case;
               -- 32 x 1, start 01, op (01 write, 10 read), PHY 0, register, TA (10 or Z), data
               m_sh  <= x"FFFFFFFF" & "01" & (not v_wr) & v_wr & "00000" & v_reg & "10" & v_val;
               m_rd  <= not v_wr;
               m_bit <= 64;
               m_div <= 0;
               ms    <= M_SHIFT;

            when M_SHIFT =>                              -- MDIO changes after the falling MDC edge
               if m_div = G_MDC_DIV - 1 then
                  m_div <= 0;
                  m_mdc <= not m_mdc;
                  if m_mdc = '1' then                    -- falling edge: next bit out
                     if m_bit = 0 then
                        m_mdio_oe <= '0';
                        ms        <= M_NEXT;
                     else
                        m_bit     <= m_bit - 1;
                        m_mdio_o  <= m_sh(63);
                        m_sh      <= m_sh(62 downto 0) & '1';
                        -- reads: release MDIO for the turnaround and the data (the last 18 bits)
                        if m_rd = '1' and m_bit <= 18 then
                           m_mdio_oe <= '0';
                        else
                           m_mdio_oe <= '1';
                        end if;
                     end if;
                  else                                   -- rising edge: the PHY drives read data
                     if m_bit < 16 then
                        m_in <= m_in(14 downto 0) & m_mdio_i;
                     end if;
                  end if;
               else
                  m_div <= m_div + 1;
               end if;

            when M_NEXT =>
               ms <= M_WAIT;
               case m_step is
                  when 0 =>
                     m_step <= 1;
                     m_dly <= G_POLL_CYCLES;           -- no pause between the two writes
                  when 1 =>
                     m_step <= 2;
                  when 2 =>
                     m_link <= m_in(2);                 -- link status (latched low: a fall is
                     m_step <= 3;                       -- seen once, then the next poll is fresh)
                     m_dly <= G_POLL_CYCLES;
                  when others =>
                     -- $1E bits 2:0: 001 10 HD, 010 100 HD, 101 10 FD, 110 100 FD
                     e_link(0) <= m_link;
                     e_link(1) <= m_in(1);
                     e_link(2) <= m_in(2);
                     m_step    <= 2;
               end case;
         end case;
      end if;
   end process p_mii;

end architecture synthesis;
