set project_name rvhello
set project_file "$project_name.xpr"
set part_name "xc7a100tfgg676-2"

proc arg {idx default} {
    global argv
    if {[llength $argv] > $idx} { return [lindex $argv $idx] }
    return $default
}

proc ensure_project {{use_sram 0}} {
    global project_name project_file part_name
    if {[llength [get_projects -quiet]] == 0} {
        if {[file exists $project_file]} { open_project $project_file } else {
            create_project $project_name . -part $part_name
        }
    }
    set_property target_language Verilog [current_project]
    # clk_pll 的 MMCM 原语只在综合期启用; iverilog 行为仿真走旁路.
    set_property verilog_define [list SYNTHESIS_PLL] [get_filesets sources_1]
    foreach path {src/core/rv32i_core.v src/core/rv32m_pcpi.v src/core/prog_mem.v src/periph/bus_decode.v src/periph/gpio.v src/periph/uart_tx.v src/periph/timer.v src/periph/sram_async.v src/debug/jtag_dtm_cdc.v src/debug/jtag_dtm_tap.v src/debug/bscan_dtm.v src/debug/riscv_debug_dm.v src/board/clk_pll.v src/board/top.v src/board/seg_display.v} {
        if {![file exists $path]} { error "Missing file: $path" }
        if {[llength [get_files -quiet $path]] == 0} { add_files -norecurse $path }
    }
    # BRAM 初值文件, 综合时由 $readmemh 加载; 同时把 src/ 加入包含路径,
    # 保证 $readmemh("program.hex") 在综合运行目录下也能定位到该文件.
    if {[llength [get_files -quiet src/program.hex]] == 0} {
        add_files -norecurse src/program.hex
    }
    set_property include_dirs [list [file normalize "src"]] [get_filesets sources_1]
    if {$use_sram} {
        set xdc_path constr/top_sram.xdc
        set synth_top top_sram
    } else {
        set xdc_path constr/top.xdc
        set synth_top top
    }
    if {$use_sram && [llength [get_files -quiet constr/top.xdc]] == 0} {
        add_files -fileset constrs_1 -norecurse constr/top.xdc
    }
    if {[llength [get_files -quiet $xdc_path]] == 0} {
        add_files -fileset constrs_1 -norecurse $xdc_path
    }
    foreach tb {sim/tb_top.v} {
        if {[llength [get_files -quiet $tb]] == 0} {
            add_files -fileset sim_1 -norecurse $tb
        }
    }
    set_property top $synth_top [get_filesets sources_1]
    set_property top tb_top [get_filesets sim_1]
    set_property top_auto_set false [get_filesets sim_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
}

proc run_synth {jobs {use_sram 0}} {
    ensure_project $use_sram
    reset_run synth_1
    launch_runs synth_1 -jobs $jobs
    wait_on_run synth_1
    set status [get_property STATUS [get_runs synth_1]]
    if {$status ne "synth_design Complete!"} { error "Synthesis failed: $status" }
    puts "SYNTH_OK"
}

proc run_impl {jobs to_step {use_sram 0}} {
    run_synth $jobs $use_sram
    reset_run impl_1
    launch_runs impl_1 -to_step $to_step -jobs $jobs
    wait_on_run impl_1
    set status [get_property STATUS [get_runs impl_1]]
    if {$to_step eq "write_bitstream"} {
        if {![string match "*write_bitstream Complete*" $status]} { error "Bitstream failed: $status" }
        puts "BITSTREAM_OK"
    } else {
        if {![string match "*route_design Complete*" $status]} { error "Implementation failed: $status" }
        puts "IMPL_OK"
    }
}

proc select_sram_project {} {
    global project_name project_file
    set project_name rvhello_sram
    set project_file "$project_name.xpr"
}

proc program_board {bit_file} {
    if {![file exists $bit_file]} { error "Bitstream not found: $bit_file" }
    open_hw_manager
    connect_hw_server
    open_hw_target
    set devices [get_hw_devices -quiet xc7a100t*]
    if {[llength $devices] == 0} { error "No xc7a100t hardware device found" }
    set device [lindex $devices 0]
    current_hw_device $device
    refresh_hw_device $device
    set_property PROGRAM.FILE [file normalize $bit_file] $device
    program_hw_devices $device
    puts "PROGRAM_OK: [file normalize $bit_file]"
}

set cmd [arg 0 "create"]
set jobs [arg 1 8]
switch -- $cmd {
    create { ensure_project 0; puts "PROJECT_OK: rvhello.xpr" }
    synth { run_synth $jobs 0 }
    impl { run_impl $jobs route_design 0 }
    bitstream { run_impl $jobs write_bitstream 0 }
    program { program_board [arg 1 "rvhello.runs/impl_1/top.bit"] }
    sram-create { select_sram_project; ensure_project 1; puts "PROJECT_OK: rvhello_sram.xpr" }
    sram-synth { select_sram_project; run_synth $jobs 1 }
    sram-impl { select_sram_project; run_impl $jobs route_design 1 }
    sram-bitstream { select_sram_project; run_impl $jobs write_bitstream 1 }
    sram-program { select_sram_project; program_board [arg 1 "rvhello_sram.runs/impl_1/top_sram.bit"] }
    default { error "unknown command: $cmd" }
}
