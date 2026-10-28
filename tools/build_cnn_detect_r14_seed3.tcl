set root D:/2026fpga/EG4D20
set parent D:/2026fpga/bank/eg4d20_cnn_detect_20261028_r14_signed_multiply_fix
set out D:/2026fpga/bank/eg4d20_cnn_detect_20261028_r14_signed_multiply_fix_seed3
file mkdir $out
cd $root
open_project D:/2026fpga/EG4D20/EG4D20_CNN_DETECT.al -single_run
import_device eagle_s20.db -package EG4D20EG176
cd $out
import_db $parent/optimized_gate.db
read_adc D:/2026fpga/EG4D20/uisrc/04_pin/cnn_fpga_pin.adc
read_sdc D:/2026fpga/EG4D20/uisrc/04_pin/cnn_timing.sdc
set_param place seed 3
place
route
report_area -io_info -file final.area
update_timing -mode final
report_timing_summary -file final_timing.rpt
report_timing_status -file timing_status.txt
export_db routed.db
set report [open final_timing.rpt r]
set timing [read $report]
close $report
if {![regexp {SWNS:\s*([-0-9.]+)ns, STNS:\s*([-0-9.]+)ns} $timing _ sw st] || ![regexp {HWNS:\s*([-0-9.]+)ns, HTNS:\s*([-0-9.]+)ns} $timing _ hw ht]} { error "Missing timing summary; no bit generated" }
if {$sw < 0 || $hw < 0 || $st != 0 || $ht != 0} { error "Timing failed: setup=$sw hold=$hw; no bit generated" }
bitgen -bit eg4d20_cnn_detect_r14_signed_multiply_fix_seed3.bit
puts EG4D20_CNN_DETECT_R14_SIGNED_MULTIPLY_FIX_SEED3_BUILD_COMPLETE
exit
