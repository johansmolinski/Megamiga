# Build one board bitstream in Vivado batch mode - normally called by
# build_all.sh:
#
#   vivado -mode batch -source build_bitstream.tcl -tclargs <R3|R4|R5|R6> [jobs]
#
# Prints one machine-readable "RESULT <board> ..." line and exits non-zero on
# any failure. After the bitstream is written, the routed design is opened and
# the sign-off gates of CORE.xdc are checked explicitly, because those
# constraints silently no-op when instance names drift.

set board [lindex $argv 0]
set jobs  [expr {[llength $argv] > 1 ? [lindex $argv 1] : 4}]

open_project CORE-${board}.xpr

reset_run synth_1               ;# force a clean rebuild (invalidates impl_1)
# Incremental synthesis from the reference build (REF_SYNTH_DCP, set by
# build_all.sh from REF_DIR): where Vivado reuses the reference netlist,
# unchanged logic keeps its cell names and the incremental implementation can
# keep more of the reference placement (a fresh synthesis renamed ~10% of the
# cells for three changed menu-bit ranges in mega65.vhd: hmenu-f, 84.5% reuse).
# Vivado itself decides: for a large change ("Change is too high", e.g. hmenu-h,
# an edit of mega65.vhd) it falls back to a normal synthesis, which is
# accepted. Cleared afterwards, like the hooks.
set synth_ref ""
if {[info exists ::env(REF_SYNTH_DCP)] && $::env(REF_SYNTH_DCP) ne ""} {
    set synth_ref $::env(REF_SYNTH_DCP)
    puts "REF_SYNTH_DCP: incremental synthesis from $synth_ref"
    set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
    set_property INCREMENTAL_CHECKPOINT $synth_ref [get_runs synth_1]
}
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {$synth_ref ne ""} {
    set_property INCREMENTAL_CHECKPOINT "" [get_runs synth_1]
    catch {remove_files -quiet -fileset utils_1 [get_files -quiet -of_objects [get_filesets utils_1] $synth_ref]}
}
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "RESULT $board FAILED synth_1: [get_property STATUS [get_runs synth_1]]"
    exit 1
}

# Placement margin + optional reference checkpoint (impl_margin.tcl), as step
# hooks of this run only: cleared again afterwards, so the .xpr is unchanged.
set here [file normalize [file dirname [info script]]]
set hooks [list STEPS.PLACE_DESIGN.TCL.PRE [file join $here impl_pre_place.tcl] \
                STEPS.ROUTE_DESIGN.TCL.PRE [file join $here impl_pre_route.tcl]]
# the hooks run in the impl_1 child process, which inherits the environment
set ::env(IMPL_TCL_DIR) $here
foreach {prop file} $hooks { set_property $prop $file [get_runs impl_1] }
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
foreach {prop file} $hooks {
    set_property $prop "" [get_runs impl_1]
    # Vivado also lists a hook script in the utils_1 fileset.
    catch {remove_files -quiet -fileset utils_1 [get_files -quiet -of_objects [get_filesets utils_1] $file]}
}
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    puts "RESULT $board FAILED impl_1: [get_property STATUS [get_runs impl_1]]"
    exit 1
}

set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
if {$wns eq "" || $whs eq "" || $wns < 0 || $whs < 0} {
    puts "RESULT $board TIMING-FAILED WNS=$wns WHS=$whs"
    exit 2
}

open_run impl_1
set gate {}
# A500+ mode: the core clock is pinned to native (no flicker-free fast leg), and the
# chipset -> SDRAM multicycle constraints need the controller's instance name.
# Megamiga 0.7 NTSC: both clock muxes (core clock, SDRAM 4x clock) are on the NTSC leg
foreach pin {CORE/clk_gen/i_bufgmux/S CORE/clk_gen/i_bufgmux4x/S} {
    if {[llength [get_pins -quiet $pin]] == 0} {
        lappend gate "set_case_analysis target $pin missing"
    }
}
if {[llength [get_cells -quiet {CORE/i_amiga_sdram/i_sdram_ctrl/*}]] == 0} {
    lappend gate "multicycle target CORE/i_amiga_sdram/i_sdram_ctrl missing"
}
# the CPU -> SDRAM multicycle (CORE.xdc) must cover every TG68K, whatever its name
set tg [get_cells -quiet -hierarchical -filter {ORIG_REF_NAME =~ TG68KdotC_Kernel* || REF_NAME =~ TG68KdotC_Kernel*}]
if {[llength $tg] == 0} {
    lappend gate "no TG68KdotC_Kernel instance found (CPU -> SDRAM multicycle check)"
}
foreach c $tg {
    if {![string match {CORE/i_main/i_cpu_wrapper/*cpu_inst_p} $c] && ![string match {CORE/i_main/i_cpu_wrapper/*tg68k_inst} $c]} {
        lappend gate "$c is not a source of the CPU -> SDRAM multicycle in CORE.xdc"
    }
}
# Megamiga 0.7: main_clk is timed on the NTSC leg (28.636364 MHz; PAL was 35.242 ns)
foreach {clk want} {main_clk 34.921} {
    set c [get_clocks -quiet $clk]
    if {[llength $c] == 0} {
        lappend gate "generated clock $clk missing"
    } elseif {[expr {abs([get_property PERIOD $c] - $want)}] > 0.05} {
        lappend gate "$clk period [get_property PERIOD $c] ns, expected ~$want ns (NTSC 28.636364 MHz)"
    }
}
if {[llength $gate] > 0} {
    foreach g $gate { puts "GATE $board: $g" }
    puts "RESULT $board SIGNOFF-FAILED WNS=$wns WHS=$whs"
    exit 3
}

# Megamiga 0.7 NTSC: the PAL leg of the core clock (pal_leg.tcl; CORE.xdc times the NTSC
# leg). A miss there is a timing miss: build_all.sh may re-roll it like any other.
source [file join $here pal_leg.tcl]
set pal [pal_leg_gate]
if {[llength $pal] > 0} {
    foreach g $pal { puts "PAL LEG $board: $g" }
    set w [expr {$::pal_wns ne "" && $::pal_wns < $wns ? $::pal_wns : $wns}]
    set h [expr {$::pal_whs ne "" && $::pal_whs < $whs ? $::pal_whs : $whs}]
    puts "RESULT $board TIMING-FAILED WNS=$w WHS=$h (PAL leg)"
    exit 2
}

puts "RESULT $board OK WNS=$wns WHS=$whs bit=CORE-${board}.runs/impl_1/mega65_[string tolower $board].bit"
close_project
