-------------------------------------------------------------------------------------------------------------
-- Amiga 500 for MEGA65 (AExp)
--
-- Clock Generator using the Xilinx specific MMCME2_ADV:
--
--   Single core clock domain: clk_main = 28.375000 MHz (PAL Amiga master clock)
--
-- Frequency math (PAL):
--    The original PAL Amiga master crystal runs at 28.37516 MHz, i.e.
--    6.4 x 4.43361875 MHz (PAL colorburst) = 4 x 7.09379 MHz (CCK x 4).
--    We generate from the 100 MHz board clock:
--       f_VCO  = 100 MHz x CLKFBOUT_MULT_F / DIVCLK_DIVIDE = 100 x 56.750 / 5 = 1135.000 MHz
--       f_OUT  = f_VCO / CLKOUT0_DIVIDE_F                  = 1135.000 / 40    =   28.375000 MHz
--    Error vs. ideal 28.3751600 MHz: -160 Hz = -5.6 ppm. A real Amiga crystal is
--    specified at +/-50 ppm (typ.), so we are well within the tolerance of original hardware.
--
-- MMCME2_ADV legality checks (Artix-7 XC7A200T-2, see Xilinx DS181 / UG472):
--    * VCO = 1135.000 MHz is within the -2 speed grade MMCM VCO range of 600..1440 MHz
--    * PFD = 100 MHz / DIVCLK_DIVIDE(5) = 20 MHz, within the allowed 10..500 MHz (-2)
--    * CLKFBOUT_MULT_F = 56.750 is a multiple of 0.125 within 2.000..64.000 (legal fractional);
--      fractional dividers are only permitted on CLKFBOUT and CLKOUT0 - here only CLKFBOUT
--      is fractional, CLKOUT0_DIVIDE_F = 40.000 is integer-valued (1.000..128.000, legal)
--
-- NTSC (Megamiga, October 2026, branch ntsc): the NTSC Amiga master clock is 28.636364 MHz
--    (= 315/11 MHz = 8 x 3.579545 MHz colorburst). A second MMCM "i_clk_ntsc" makes it EXACTLY:
--       f_VCO  = 100 MHz x 63.000 / 5 = 1260.000 MHz,  CLKOUT0 / 44 = 28.636364 MHz (0 ppm)
--                                                       CLKOUT1 / 11 = 114.545455 MHz (4x, SDRAM)
--    Legality (Artix-7 -2): VCO 1260 MHz in 600..1440; PFD 20 MHz in 10..500; all dividers integer.
--    Two glitch-free BUFGMUX_CTRLs pick the core clock and its 4x twin from the PAL or the NTSC
--    MMCM with ONE select, ntsc_i (amiga_cold_boot.vhd switches it while the Amiga is held in
--    reset and the SDRAM controller has nothing in flight; a BUFGMUX_CTRL switch only stretches
--    one low phase, so nothing is reset and the logic just sees one long clock). Both MMCMs run
--    all the time, so there is no reconfiguration, no relock and no output gating.
--    The AP68040's clock (CLKOUT2 of the PAL MMCM, 42.04 MHz) is asynchronous to the core clock
--    anyway (ap040_island), so it stays the same in both modes.
--    Timing: CORE.xdc times the NTSC leg (the faster one; set_case_analysis 1 on both selects).
--
--    (This MMCM was the HDMI flicker-free "fast" twin of AExp (issue #12, 28.4375 MHz, selected
--    by core_speed_i from ascal's over/underflow feedback). Megamiga never used it: the SDRAM's
--    4x clock came from the native MMCM only, so core_speed_i was tied to "00" since 0.2.0.)
--
-- MiSTer2MEGA65 (AExp Amiga 500 port), June 2026: rewrote the M2M template clock
-- (single MMCM, 54 MHz demo clock) to generate the 28.375 MHz Amiga PAL core clock.
-- Entity ports kept identical to the template. Based on the MiSTer2MEGA65 framework
-- done by sy2002 and MJoergen and licensed under GPL v3.
-------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

entity clk is
   port (
      sys_clk_i       : in  std_logic;   -- expects 100 MHz

      -- Megamiga: the video standard (asynchronous; the BUFGMUX_CTRLs absorb it glitch-free):
      --   '0' = PAL  28.375000 MHz (ideal 28.3751600 MHz, -5.6 ppm), 4x 113.5 MHz
      --   '1' = NTSC 28.636364 MHz (exact),                          4x 114.545455 MHz
      ntsc_i          : in  std_logic;

      main_clk_o      : out std_logic;   -- Amiga core clock: PAL 28.375000 / NTSC 28.636364 MHz
      main_clk4x_o    : out std_logic;   -- 4 x the core clock for the SDRAM (Megamiga), same select
      main_rst_o      : out std_logic;   -- main's reset, synchronized
      -- Megamiga, October 2026 (branch cpu040): the AP68040's own clock, 1135 MHz / 27 =
      -- 42.037037 MHz from the native MMCM (CLKOUT2), unrelated in phase to the core clock
      -- for the design. Builds cpu040-d/-e/-f: 47.29 MHz missed by 1.5 ns without the
      -- core's speed-ups; with them 42.04 MHz missed by 1.8 ns and 37.83 MHz by ~2.7 ns
      -- (they lengthen the branch-redirect paths), so they are off (C_CPU040_FAST = 1).
      -- for the design: cpu_wrapper's ap040_island crosses to it with synchronizers
      cpu_clk_o       : out std_logic
   );
end entity clk;

architecture rtl of clk is

-- native leg (28.375000 MHz)
signal main_fb            : std_logic;
signal main_fb_mmcm       : std_logic;
signal native_clk_mmcm    : std_logic;
signal main_locked        : std_logic;

-- NTSC leg (28.636364 MHz), Megamiga (was AExp's HDMI flicker-free "fast" twin)
signal ntsc_fb            : std_logic;
signal ntsc_fb_mmcm       : std_logic;
signal ntsc_clk_mmcm      : std_logic;
signal ntsc_clk4x_mmcm    : std_logic;
signal ntsc_locked        : std_logic;

-- glitch-free mux output feeding the shared output BUFG
signal main_clk_mmcm      : std_logic;
signal native_clk4x_mmcm  : std_logic;
signal cpu_clk_mmcm       : std_logic;   -- Megamiga (cpu040): the AP68040's clock

begin

   -------------------------------------------------------------------------------------
   -- Generate the Amiga core clock: 28.375000 MHz
   -- 100 MHz x 56.750 / 5 = 1135.000 MHz VCO; 1135.000 MHz / 40 = 28.375000 MHz
   -------------------------------------------------------------------------------------

   i_clk_main : MMCME2_ADV
      generic map (
         BANDWIDTH            => "OPTIMIZED",
         CLKOUT4_CASCADE      => FALSE,
         COMPENSATION         => "ZHOLD",
         STARTUP_WAIT         => FALSE,
         CLKIN1_PERIOD        => 10.0,       -- INPUT @ 100 MHz
         REF_JITTER1          => 0.010,
         -- MiSTer2MEGA65 (AExp Amiga 500 port), June 2026: template made 54 MHz
         -- (DIVCLK_DIVIDE=1, CLKFBOUT_MULT_F=6.750, CLKOUT0_DIVIDE_F=12.500);
         -- changed to 28.375 MHz Amiga PAL master clock, see header for the math.
         DIVCLK_DIVIDE        => 5,
         CLKFBOUT_MULT_F      => 56.750,     -- VCO = 1135.000 MHz (legal: 600..1440 MHz @ -2)
         CLKFBOUT_PHASE       => 0.000,
         CLKFBOUT_USE_FINE_PS => FALSE,
         CLKOUT0_DIVIDE_F     => 40.000,     -- 28.375000 MHz (ideal 28.3751600 MHz, -5.6 ppm)
         CLKOUT0_PHASE        => 0.000,
         CLKOUT0_DUTY_CYCLE   => 0.500,
         CLKOUT0_USE_FINE_PS  => FALSE,
         CLKOUT1_DIVIDE       => 10,         -- 113.500000 MHz = 4 x CLKOUT0, phase-aligned
         CLKOUT1_PHASE        => 0.000,
         CLKOUT1_DUTY_CYCLE   => 0.500,
         CLKOUT1_USE_FINE_PS  => FALSE,
         CLKOUT2_DIVIDE       => 27,         -- Megamiga (cpu040): 42.037037 MHz, the AP68040
         CLKOUT2_PHASE        => 0.000,
         CLKOUT2_DUTY_CYCLE   => 0.500,
         CLKOUT2_USE_FINE_PS  => FALSE
      )
      port map (
         -- Output clocks
         CLKOUT1             => native_clk4x_mmcm,
         CLKOUT2             => cpu_clk_mmcm,
         CLKFBOUT            => main_fb_mmcm,
         CLKOUT0             => native_clk_mmcm,
         -- Input clock control
         CLKFBIN             => main_fb,
         CLKIN1              => sys_clk_i,
         CLKIN2              => '0',
         -- Tied to always select the primary input clock
         CLKINSEL            => '1',
         -- Ports for dynamic reconfiguration
         DADDR               => (others => '0'),
         DCLK                => '0',
         DEN                 => '0',
         DI                  => (others => '0'),
         DO                  => open,
         DRDY                => open,
         DWE                 => '0',
         -- Ports for dynamic phase shift
         PSCLK               => '0',
         PSEN                => '0',
         PSINCDEC            => '0',
         PSDONE              => open,
         -- Other control and status signals
         LOCKED              => main_locked,
         CLKINSTOPPED        => open,
         CLKFBSTOPPED        => open,
         PWRDWN              => '0',
         RST                 => '0'
      ); -- i_clk_main

   -------------------------------------------------------------------------------------
   -- Megamiga: the NTSC core clock 28.636364 MHz and its 4x twin 114.545455 MHz
   -- 100 MHz x 63.000 / 5 = 1260.000 MHz VCO; / 44 = 28.636364 MHz, / 11 = 114.545455 MHz
   -- (AExp: the HDMI flicker-free "fast" twin, 100 x 56.875 / 5 / 40 = 28.4375 MHz)
   -------------------------------------------------------------------------------------

   i_clk_ntsc : MMCME2_ADV
      generic map (
         BANDWIDTH            => "OPTIMIZED",
         CLKOUT4_CASCADE      => FALSE,
         COMPENSATION         => "ZHOLD",
         STARTUP_WAIT         => FALSE,
         CLKIN1_PERIOD        => 10.0,       -- INPUT @ 100 MHz
         REF_JITTER1          => 0.010,
         DIVCLK_DIVIDE        => 5,
         --CLKFBOUT_MULT_F      => 56.875,     -- VCO = 1137.500 MHz (legal: 600..1440 MHz @ -2)
         CLKFBOUT_MULT_F      => 63.000,     -- VCO = 1260.000 MHz (legal: 600..1440 MHz @ -2)
         CLKFBOUT_PHASE       => 0.000,
         CLKFBOUT_USE_FINE_PS => FALSE,
         --CLKOUT0_DIVIDE_F     => 40.000,     -- 28.437500 MHz (313-line PAL = 50.030 Hz, above 50)
         CLKOUT0_DIVIDE_F     => 44.000,     -- 28.636364 MHz, the NTSC master clock (0 ppm)
         CLKOUT0_PHASE        => 0.000,
         CLKOUT0_DUTY_CYCLE   => 0.500,
         CLKOUT0_USE_FINE_PS  => FALSE,
         CLKOUT1_DIVIDE       => 11,         -- 114.545455 MHz = 4 x CLKOUT0, phase-aligned
         CLKOUT1_PHASE        => 0.000,
         CLKOUT1_DUTY_CYCLE   => 0.500,
         CLKOUT1_USE_FINE_PS  => FALSE
      )
      port map (
         -- Output clocks
         CLKFBOUT            => ntsc_fb_mmcm,
         CLKOUT0             => ntsc_clk_mmcm,
         CLKOUT1             => ntsc_clk4x_mmcm,
         -- Input clock control
         CLKFBIN             => ntsc_fb,
         CLKIN1              => sys_clk_i,
         CLKIN2              => '0',
         -- Tied to always select the primary input clock
         CLKINSEL            => '1',
         -- Ports for dynamic reconfiguration
         DADDR               => (others => '0'),
         DCLK                => '0',
         DEN                 => '0',
         DI                  => (others => '0'),
         DO                  => open,
         DRDY                => open,
         DWE                 => '0',
         -- Ports for dynamic phase shift
         PSCLK               => '0',
         PSEN                => '0',
         PSINCDEC            => '0',
         PSDONE              => open,
         -- Other control and status signals
         LOCKED              => ntsc_locked,
         CLKINSTOPPED        => open,
         CLKFBSTOPPED        => open,
         PWRDWN              => '0',
         RST                 => '0'
      ); -- i_clk_ntsc

   -------------------------------------------------------------------------------------
   -- Output buffering
   -------------------------------------------------------------------------------------

   -- native leg feedback (ZHOLD compensates one BUFG delay)
   main_fb_bufg : BUFG
      port map (
         I => main_fb_mmcm,
         O => main_fb
      );

   -- NTSC leg feedback (its own BUFG, symmetric with native)
   ntsc_fb_bufg : BUFG
      port map (
         I => ntsc_fb_mmcm,
         O => ntsc_fb
      );

   -- Glitch-free switch between PAL ('0') and NTSC ('1'); the select is treated
   -- asynchronously to both clock inputs and absorbed cleanly by the BUFGMUX_CTRL.
   -- Keep the instance names: CORE.xdc sets the case analysis on their S pins.
   i_bufgmux : BUFGMUX_CTRL
      port map (
         I0 => native_clk_mmcm,     -- s = 0 -> PAL  (28.375000 MHz)
         I1 => ntsc_clk_mmcm,       -- s = 1 -> NTSC (28.636364 MHz)
         S  => ntsc_i,
         O  => main_clk_mmcm
      );

   -- the 4x clock follows the same select (it was a plain BUFG on the native MMCM's CLKOUT1)
   i_bufgmux4x : BUFGMUX_CTRL
      port map (
         I0 => native_clk4x_mmcm,   -- s = 0 -> PAL  (113.500000 MHz)
         I1 => ntsc_clk4x_mmcm,     -- s = 1 -> NTSC (114.545455 MHz)
         S  => ntsc_i,
         O  => main_clk4x_o
      );

   cpu_clk_bufg : BUFG
      port map (
         I => cpu_clk_mmcm,
         O => cpu_clk_o
      );

   main_clk_bufg : BUFG
      port map (
         I => main_clk_mmcm,
         O => main_clk_o
      );

   -------------------------------------
   -- Reset generation
   -------------------------------------

   i_xpm_cdc_async_rst_main : xpm_cdc_async_rst
      generic map (
         RST_ACTIVE_HIGH => 1,
         DEST_SYNC_FF    => 6
      )
      port map (
         -- Hold the core in reset until BOTH legs are locked, so the NTSC MMCM is already
         -- toggling before the select can ever choose it (load-bearing: BUFGMUX_CTRL would
         -- otherwise forward a dead clock on the first PAL->NTSC switch).
         src_arst  => not (main_locked and ntsc_locked),   -- 1-bit input: Source reset signal.
         dest_clk  => main_clk_o,        -- 1-bit input: Destination clock.
         dest_arst => main_rst_o         -- 1-bit output: src_rst synchronized to the destination clock domain.
                                         -- This output is registered.
      );

end architecture rtl;
