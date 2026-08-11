set project_name rvhello
set project_file "$project_name.xpr"
set part_name "xc7a100tfgg676-2"

proc arg {idx default} {
    global argv
    if {[llength $argv] > $idx} { return [lindex $argv $idx] }
    return $default
}

proc ensure_project {} {
    global project_name project_file part_name
    if {[llength [get_projects -quiet]] == 0} {
        if {[file exists $project_file]} { open_project $project_file } else {
            create_project $project_name . -part $part_name
        }
    }
    set_property target_language Verilog [current_project]
    foreach path {src/prog_mem.v src/seg_display.v src/rv32i_core.v src/top.v} {
        if {![file exists $path]} { error "Missing file: $path" }
        if {[llength [get_files -quiet $path]] == 0} { add_files -norecurse $path }
    }
    # BRAM 初值文件, 综合时由 $readmemh 加载; 同时把 src/ 加入包含路径,
    # 保证 $readmemh("program.hex") 在综合运行目录下也能定位到该文件.
    if {[llength [get_files -quiet src/program.hex]] == 0} {
        add_files -norecurse src/program.hex
    }
    set_property include_dirs [list [file normalize "src"]] [get_filesets sources_1]
    if {[llength [get_files -quiet constr/top.xdc]] == 0} {
        add_files -fileset constrs_1 -norecurse constr/top.xdc
    }
    foreach tb {sim/tb_top.v} {
        if {[llength [get_files -quiet $tb]] == 0} {
            add_files -fileset sim_1 -norecurse $tb
        }
    }
    set_property top top [get_filesets sources_1]
    set_property top tb_top [get_filesets sim_1]
    set_property top_auto_set false [get_filesets sim_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
}

proc run_synth {jobs} {
    ensure_project
    reset_run synth_1
    launch_runs synth_1 -jobs $jobs
    wait_on_run synth_1
    set status [get_property STATUS [get_runs synth_1]]
    if {$status ne "synth_design Complete!"} { error "Synthesis failed: $status" }
    puts "SYNTH_OK"
}

proc run_impl {jobs to_step} {
    run_synth $jobs
    reset_run impl_1
    launch_runs impl_1 -to_step $to_step -jobs $jobs
    wait_on_run impl_1
    set status [get_property STATUS [get_runs impl_1]]
    if {$to_step eq "write_bitstream"} {
        if {![string match "*write_bitstream Complete*" $status]} { error "Bitstream failed: $status" }
        puts "BITSTREAM_OK: rvhello.runs/impl_1/top.bit"
    } else {
        if {![string match "*route_design Complete*" $status]} { error "Implementation failed: $status" }
        puts "IMPL_OK"
    }
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
    create { ensure_project; puts "PROJECT_OK: rvhello.xpr" }
    synth { run_synth $jobs }
    impl { run_impl $jobs route_design }
    bitstream { run_impl $jobs write_bitstream }
    program { program_board [arg 1 "rvhello.runs/impl_1/top.bit"] }
    default { error "unknown command: $cmd" }
}
