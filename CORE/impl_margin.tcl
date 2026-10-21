# Placement margin and incremental reference for implementation - sourced by
# impl_pre_place.tcl / impl_pre_route.tcl (the place_design and route_design
# TCL.PRE hooks that build_bitstream.tcl sets on impl_1) and by
# reroll_bitstream.tcl.
#
# Margin: the placer and the pre-route phys_opt see the clocks of IMPL_MARGIN
# tighter than they are (extra setup uncertainty), so they leave room for the
# delay routing adds on the long 68040 and SDRAM controller paths;
# impl_margin off restores the real constraints before route_design, so
# routing, post-route phys_opt and the reported slack are the real ones.
#
#   IMPL_MARGIN="cpu_clk:0.4 ntsc_clk4x_mmcm:0.2"     clock:ns pairs (default; Megamiga 0.7: the
#                                                      timed SDRAM clock is the NTSC leg, CORE.xdc)
#   IMPL_MARGIN=0                                      no margin
#
# Reference: REF_DCP=<routed .dcp of a build that met timing> makes the
# placer start from that build's placement and routing (incremental
# implementation, TimingClosure: unmatched or failing paths are redone).
# build_all.sh sets it per board from REF_DIR. With a reference there is no
# margin.

proc impl_margin_list {} {
    # Vivado: user clock uncertainty "will adversely impact the incremental
    # design run" (Project 1-1108); the reference placement is the margin then.
    if {[info exists ::env(REF_DCP)] && $::env(REF_DCP) ne ""} { return {} }
    set m "cpu_clk:0.4 ntsc_clk4x_mmcm:0.2"
    if {[info exists ::env(IMPL_MARGIN)]} { set m $::env(IMPL_MARGIN) }
    if {$m eq "" || $m eq "0"} { return {} }
    set out {}
    foreach pair $m {
        lassign [split $pair :] clk ns
        if {$clk eq "" || ![string is double -strict $ns]} {
            error "IMPL_MARGIN: bad entry '$pair', expected clock:ns"
        }
        lappend out $clk $ns
    }
    return $out
}

# on: add the margin; off: set it back to 0 (CORE.xdc sets no uncertainty on
# these clocks, so 0 is the real constraint).
proc impl_margin {mode} {
    foreach {clk ns} [impl_margin_list] {
        set c [get_clocks -quiet $clk]
        if {[llength $c] == 0} {
            puts "IMPL_MARGIN: clock $clk not found, skipped"
            continue
        }
        set v [expr {$mode eq "on" ? $ns : 0}]
        set_clock_uncertainty -setup $v $c
        puts "IMPL_MARGIN: $clk setup uncertainty $v ns ($mode)"
    }
}

proc impl_reference {} {
    if {![info exists ::env(REF_DCP)] || $::env(REF_DCP) eq ""} { return }
    set ref $::env(REF_DCP)
    if {![file exists $ref]} { error "REF_DCP $ref not found" }
    puts "REF_DCP: incremental implementation from $ref"
    read_checkpoint -incremental $ref -directive TimingClosure
}
