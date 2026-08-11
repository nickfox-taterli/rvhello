connect -url tcp:127.0.0.1:3121
jtag targets -set -filter {name == "xc7a100t"}

proc scan_dr {user bits value idle_cycles} {
    set seq [jtag sequence]
    $seq state IDLE
    $seq irshift -register $user -state IDLE
    $seq drshift -integer -state IDLE $bits $value
    if {$idle_cycles > 0} {
        $seq state IDLE $idle_cycles
    }
    $seq drshift -capture -tdi 0 -state IDLE $bits
    set result [$seq run -integer]
    $seq delete
    return $result
}

proc read_dtmcs {} {
    set seq [jtag sequence]
    $seq state RESET
    $seq state IDLE
    $seq irshift -register user3 -state IDLE
    $seq drshift -capture -tdi 0 -state IDLE 32
    set result [$seq run -integer]
    $seq delete
    return $result
}

proc clear_dmi_error {} {
    set seq [jtag sequence]
    $seq state IDLE
    $seq irshift -register user3 -state IDLE
    $seq drshift -integer -state IDLE 32 0x00010000
    $seq state IDLE 8
    $seq run
    $seq delete
}

proc dmi_access {addr data op} {
    set request [expr {($addr << 34) | ($data << 2) | $op}]
    return [scan_dr user4 41 $request 128]
}

set dtmcs [read_dtmcs]
if {($dtmcs & 0xf) != 1 || (($dtmcs >> 4) & 0x3f) != 7} {
    error [format "Unexpected USER3 DTMCS: 0x%08x" $dtmcs]
}

set response [dmi_access 0x10 1 2]
clear_dmi_error

set response [dmi_access 0x11 0 1]
set op [expr {$response & 3}]
set dmstatus [expr {($response >> 2) & 0xffffffff}]
if {$op != 0 || ($dmstatus & 0xf) != 2 || ($dmstatus & 0x80) == 0} {
    error [format "Unexpected USER4 DMSTATUS: op=%d data=0x%08x" $op $dmstatus]
}
clear_dmi_error

set response [dmi_access 0x10 0x80000001 2]
clear_dmi_error
after 10
set response [dmi_access 0x11 0 1]
set op [expr {$response & 3}]
set halted_status [expr {($response >> 2) & 0xffffffff}]
if {$op != 0 || ($halted_status & 0x100) == 0} {
    error [format "USER4 halt failed: op=%d data=0x%08x" $op $halted_status]
}
clear_dmi_error

# Access Register: 32 位,transfer=1,读取 dpc.
set response [dmi_access 0x17 0x002207b1 2]
clear_dmi_error
after 10
set response [dmi_access 0x04 0 1]
set op [expr {$response & 3}]
set dpc [expr {($response >> 2) & 0xffffffff}]
if {$op != 0} {
    error [format "USER4 abstract DPC read failed: op=%d" $op]
}
clear_dmi_error

set response [dmi_access 0x10 0x40000001 2]
clear_dmi_error

puts [format "USER3_DTMCS=0x%08x" $dtmcs]
puts [format "USER4_DMSTATUS=0x%08x DPC=0x%08x" $halted_status $dpc]
puts "BSCAN_SMOKE_OK"
