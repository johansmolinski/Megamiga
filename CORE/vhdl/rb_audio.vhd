---------------------------------------------------------------------------------------------------------
-- Megamiga (Amiga for MEGA65, fork of AExp)
--
-- rb_audio: main.vhd's audio output stage (audio_filters.vhd and the master volume) in real time,
-- for the rubber-banded Amiga (doc/developers/rubber-band.md): rb_bridge replays Paula's raw output,
-- the filters' clock enable and the power LED exactly as the Amiga made them, in main_clk; the
-- filters' IIR does not close timing at the rubber band's 49.3 MHz, and needs no such speed.
-- Same arithmetic as main.vhd (the volume LUT is a copy of main.vhd's C_VOL_LUT).
--
-- Done in 2026 (Megamiga, fork of AExp) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rb_audio is
   port (
      clk_i          : in  std_logic;                     -- main_clk (real time)
      rst_i          : in  std_logic;
      ce_i           : in  std_logic;                     -- replayed clk7_en or clk7n_en
      ldata_i        : in  std_logic_vector(14 downto 0);
      rdata_i        : in  std_logic_vector(14 downto 0);
      pwr_led_i      : in  std_logic;
      a500_filter_i  : in  std_logic;
      led_filter_i   : in  std_logic;
      stereo_mix_i   : in  std_logic_vector(1 downto 0);
      volume_i       : in  natural range 0 to 20;
      audio_left_o   : out signed(15 downto 0);
      audio_right_o  : out signed(15 downto 0)
   );
end entity rb_audio;

architecture synthesis of rb_audio is

   type vol_lut_t is array (0 to 20) of unsigned(15 downto 0);
   constant C_VOL_LUT : vol_lut_t := (                     -- = main.vhd
      x"0000", x"00E2", x"02CB", x"057B", x"08D6", x"0CCD", x"1154", x"1662",
      x"1BF1", x"21FB", x"287A", x"2F6C", x"36CB", x"3E96", x"46C8", x"4F60",
      x"585C", x"61B8", x"6B73", x"758C", x"8000");

   signal flt_l : signed(15 downto 0);
   signal flt_r : signed(15 downto 0);

begin

   i_audio_filters : entity work.audio_filters
      port map (
         clk_main_i    => clk_i,
         reset_i       => rst_i,
         ce_i          => ce_i,
         ldata_i       => ldata_i,
         rdata_i       => rdata_i,
         a500_filter_i => a500_filter_i,
         led_filter_i  => led_filter_i,
         stereo_mix_i  => stereo_mix_i,
         pwr_led_i     => pwr_led_i,
         audio_left_o  => flt_l,
         audio_right_o => flt_r
      ); -- i_audio_filters

   p_volume : process (clk_i)
      variable gain   : signed(16 downto 0);
      variable prod_l : signed(32 downto 0);
      variable prod_r : signed(32 downto 0);
   begin
      if rising_edge(clk_i) then
         gain          := signed('0' & std_logic_vector(C_VOL_LUT(volume_i)));
         prod_l        := flt_l * gain;
         prod_r        := flt_r * gain;
         audio_left_o  <= prod_l(30 downto 15);
         audio_right_o <= prod_r(30 downto 15);
      end if;
   end process p_volume;

end architecture synthesis;
