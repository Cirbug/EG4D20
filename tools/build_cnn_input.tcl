set root D:/2026fpga/EG4D20
set out D:/2026fpga/bank/eg4d20_cnn_digit0_20261027_r5/fpga
file mkdir $out

cd $root
open_project D:/2026fpga/EG4D20/EG4D20_CNN_INPUT_FRESH.al -single_run
import_device eagle_s20.db -package EG4D20EG176
elaborate -top cnn_image_input_top
puts CNN_STAGE_ELABORATE_DONE
read_adc D:/2026fpga/EG4D20/uisrc/04_pin/cnn_fpga_pin.adc
puts CNN_STAGE_ADC_DONE
read_sdc D:/2026fpga/EG4D20/uisrc/04_pin/cnn_timing.sdc
puts CNN_STAGE_SDC_DONE
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

set report [open final_timing.rpt r]
set timing [read $report]
close $report
if {![regexp {SWNS:\s*([-0-9.]+)ns, STNS:\s*([-0-9.]+)ns} $timing _ sw st] ||
    ![regexp {HWNS:\s*([-0-9.]+)ns, HTNS:\s*([-0-9.]+)ns} $timing _ hw ht]} {
    error "Missing timing summary; no bit generated"
}
if {$sw < 0 || $hw < 0 || $st != 0 || $ht != 0} {
    error "Timing failed: setup=$sw hold=$hw; no bit generated"
}

bitgen -bit eg4d20_cnn_digit0.bit
puts EG4D20_CNN_DIGIT0_BUILD_COMPLETE
exit
