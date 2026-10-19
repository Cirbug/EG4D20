# Standalone build; all generated artifacts stay outside the source project.
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file normalize [file join $root .. bank eg4d_udp_20261019 fpga]]
file mkdir $out
# Preserve a previous image under a different name before a new attempt.
# A failed build must not leave a stale image at the advertised download path.
set bitpath [file join $out eg4d20_udp_loop.bit]
if {[file exists $bitpath]} {
    file rename $bitpath [file join $out eg4d20_udp_loop_previous_[clock seconds].bit]
}
cd $root
open_project C:/Users/21397/Desktop/EG4D20/EG4D20.al -single_run
import_device eagle_s20.db -package EG4D20EG176
elaborate -top udp_transmit_test
read_adc C:/Users/21397/Desktop/EG4D20/uisrc/04_pin/fpga_pin.adc
read_sdc C:/Users/21397/Desktop/EG4D20/uisrc/04_pin/timing.sdc
cd $out
optimize_rtl
report_area -file rtl.area
optimize_gate -packarea gate.area
legalize_phy_inst
update_timing
export_db optimized_gate.db

place
route
report_area -io_info -file final.area
update_timing -mode final
report_timing_summary -file final_timing.rpt
report_timing_status -file timing_status.txt
export_db routed.db
set f [open final_timing.rpt r]
set timing [read $f]
close $f
if {![regexp {SWNS:\s*([-0-9.]+)ns, STNS:\s*([-0-9.]+)ns} $timing _ sw st] ||
    ![regexp {HWNS:\s*([-0-9.]+)ns, HTNS:\s*([-0-9.]+)ns} $timing _ hw ht]} {
    error "Missing timing summary; no bit generated"
}
if {$sw < 0 || $hw < 0 || $st != 0 || $ht != 0} {
    error "Timing failed: setup=$sw hold=$hw; no bit generated"
}
bitgen -bit eg4d20_udp_loop.bit
puts EG4D20_UDP_BUILD_COMPLETE
exit
