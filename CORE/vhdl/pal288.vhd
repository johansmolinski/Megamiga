---------------------------------------------------------------------------------------------------------
-- Megamiga for MEGA65
--
-- pal288: every PAL field leaves the core with exactly 288 active lines.
--
-- Minimig blanks lines 0..25 of the beam counter (agnus_beamcounter.v: vbl = vpos <= vbstop, 25 on
-- PAL), so a PAL field has 287 active lines (313-line long field: non-interlaced, and every second
-- interlaced field) or 286 (312-line short field). HDMI 576p would then scale 286/287 lines to
-- 576 (x2.01), which a nearest-neighbour scaler draws as a few lines three times instead of twice,
-- and the two interlaced fields differ in height. 288 lines give exactly x2 (576p) and 1:1 for the
-- woven interlaced frame.
--
-- The extra lines go at the BOTTOM: the first one or two lines of Minimig's vertical blanking
-- (vpos 0 and 1, before the vertical sync starts in line 2) stay active and black. Moving
-- Minimig's own vbstop instead would move chipset behaviour: vblend (vpos = vbstop) is the line of
-- the sprite pointer fetch and vbl stops sprite DMA (agnus_spritedma.v). Here only the blanking
-- seen by the M2M video path changes; syncs, pixels and the beam counter are untouched.
--
-- Minimig's vblank changes in the same clock as its hblank falls (both at hpos = hbstop, Agnus
-- blanking with blver = 0, amiga_config.vhd 0xF6), so a line starts at a falling hblank. The start
-- and the end of the padding are combinational in that clock: the active part of a line is never
-- one clock short or long.
--
-- The field flag (Minimig's field1, for ascal's weave) is held at its old value during the padding:
-- Minimig flips it when vpos wraps to 0, so the padding lines would carry the NEXT field's flag, and
-- ascal takes the field of a frame from the flag of the last active line before it (i_flm, latched
-- at every rising DE) - the woven fields would land on the wrong half (seen on hardware, pal288-a).
-- Minimig flips it at hpos 2 of line 0, inside the active part of the last real line (which runs from
-- hpos 102 to hpos 25 of the next line), so the hold latches the flag where ascal does: at the start
-- of every active input line. Held, the last active line carries the flag it carried before the
-- padding existed.
--
-- Fields with another number of active lines are passed through unchanged: NTSC (241/242,
-- ECS/AGA software can switch BEAMCON0 to NTSC) and the programmable VARBEAMEN modes.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pal288 is
   generic (
      G_LINES  : natural := 288                  -- active lines of a padded field
   );
   port (
      clk_i    : in  std_logic;                  -- the video clock (Minimig's clk)
      hblank_i : in  std_logic;                  -- Minimig, active high
      vblank_i : in  std_logic;
      fl_i     : in  std_logic;                  -- Minimig field1
      vblank_o : out std_logic;                  -- vblank_i without the padding lines
      fl_o     : out std_logic;                  -- fl_i, held during the padding lines
      pad_o    : out std_logic                   -- '1' during the padding lines: show black
   );
end entity pal288;

architecture synthesis of pal288 is

   signal hblank_d : std_logic := '1';
   signal vblank_d : std_logic := '1';
   signal act_cnt  : unsigned(9 downto 0) := (others => '0');   -- active lines of this field
   signal pad_reg  : std_logic := '0';
   signal pad_rem  : unsigned(1 downto 0) := (others => '0');   -- padding lines after this one
   signal fl_hold  : std_logic := '0';                          -- fl_i at the last active line start

   signal line_start : std_logic;
   signal pad_start  : std_logic;
   signal pad_end    : std_logic;
   signal pad        : std_logic;

begin

   line_start <= hblank_d and not hblank_i;

   -- the first blank line of a field that is one or two lines short
   pad_start  <= '1' when vblank_i = '1' and vblank_d = '0' and
                          (act_cnt = G_LINES - 1 or act_cnt = G_LINES - 2) else '0';
   -- the first line after the padding
   pad_end    <= '1' when pad_reg = '1' and line_start = '1' and pad_rem = 0 else '0';

   pad        <= pad_start or (pad_reg and not pad_end and vblank_i);

   vblank_o   <= vblank_i and not pad;
   pad_o      <= pad;
   fl_o       <= fl_hold when pad = '1' else fl_i;

   p_pad : process (clk_i)
   begin
      if rising_edge(clk_i) then
         hblank_d <= hblank_i;
         vblank_d <= vblank_i;
         if line_start = '1' and vblank_i = '0' then
            fl_hold <= fl_i;                     -- as ascal: the flag at the start of a line
         end if;

         if vblank_i = '1' and vblank_d = '0' then
            act_cnt <= (others => '0');
         elsif line_start = '1' and vblank_i = '0' and act_cnt /= 1023 then
            act_cnt <= act_cnt + 1;
         end if;

         if pad_start = '1' then
            pad_reg <= '1';
            pad_rem <= to_unsigned(G_LINES - 1 - to_integer(act_cnt), 2);
         elsif vblank_i = '0' or pad_end = '1' then
            pad_reg <= '0';
         elsif pad_reg = '1' and line_start = '1' then
            pad_rem <= pad_rem - 1;
         end if;
      end if;
   end process p_pad;

end architecture synthesis;
