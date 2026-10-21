# Megamiga 0.7 NTSC: the sign-off gate for the PAL leg of the core clock - sourced by
# build_bitstream.tcl and reroll_bitstream.tcl, called on the routed design.
#
# clk.vhd makes the core clock and its 4x SDRAM twin twice: PAL (i_clk_main, 28.375 /
# 113.5 MHz) and NTSC (i_clk_ntsc, 28.636364 / 114.545 MHz), and two BUFGMUX_CTRLs select one
# pair. CORE.xdc times the faster NTSC leg (set_case_analysis 1 on both selects); the PAL leg
# is 0.9 % slower, but its MMCM is another one, with another skew and (the fractional
# multiplier 56.75) more jitter, so its main <-> 4x paths can miss hold where the NTSC ones
# just meet it (ntsc-a: SDRAM read data -> ide_board, NTSC +0.011 ns, PAL -0.003 ns). This
# re-times the routed design with both selects on PAL and checks setup and hold inside and
# between the PAL core clock and its 4x twin; it does not touch the netlist, and the project
# is closed without saving afterwards. Paths to other clocks are not checked here: their
# constraints in CORE.xdc name main_clk, the NTSC leg.
#
# Returns a list of gate failures (empty = the PAL leg meets timing) and sets ::pal_wns and
# ::pal_whs to the worst PAL setup and hold slack ("" if there is no such path). Run it on a
# design whose constraints are not saved afterwards (or saved before), as it changes them.
proc pal_leg_gate {} {
    set gate {}
    set ::pal_wns ""
    set ::pal_whs ""
    foreach pin {CORE/clk_gen/i_bufgmux/S CORE/clk_gen/i_bufgmux4x/S} {
        if {[llength [get_pins -quiet $pin]] == 0} {
            return [list "PAL leg: $pin missing"]
        }
    }
    set_case_analysis 0 [get_pins CORE/clk_gen/i_bufgmux/S]
    set_case_analysis 0 [get_pins CORE/clk_gen/i_bufgmux4x/S]
    create_generated_clock -name pal_main [get_pins CORE/clk_gen/i_clk_main/CLKOUT0]
    create_generated_clock -name pal_4x   [get_pins CORE/clk_gen/i_clk_main/CLKOUT1]
    foreach {a b} {pal_main pal_main pal_main pal_4x pal_4x pal_main pal_4x pal_4x} {
        foreach {d t} {setup max hold min} {
            set p [get_timing_paths -quiet -from [get_clocks $a] -to [get_clocks $b] -delay_type $t -max_paths 1]
            if {[llength $p] == 0} { continue }
            set s [get_property SLACK $p]
            if {![string is double -strict $s]} { continue }
            puts [format "PAL LEG %s -> %s %s: slack %.3f ns" $a $b $d $s]
            set v [expr {$d eq "setup" ? "::pal_wns" : "::pal_whs"}]
            if {[set $v] eq "" || $s < [set $v]} { set $v $s }
            if {$s < 0} {
                lappend gate [format "PAL leg %s -> %s %s slack %.3f ns (%s -> %s)" $a $b $d $s \
                    [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]]
            }
        }
    }
    return $gate
}
