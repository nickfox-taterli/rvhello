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

set response [dmi_access 0x70 0 1]
set op [expr {$response & 3}]
set ident [expr {($response >> 2) & 0xffffffff}]
if {$op != 0 || $ident != 0x52564831} {
    error [format "Unexpected USER4 DMI ID: op=%d data=0x%08x" $op $ident]
}
clear_dmi_error

set response [dmi_access 0x71 0x13579bdf 2]
clear_dmi_error
set response [dmi_access 0x71 0 1]
set op [expr {$response & 3}]
set scratch [expr {($response >> 2) & 0xffffffff}]
if {$op != 0 || $scratch != 0x13579bdf} {
    error [format "USER4 scratch mismatch: op=%d data=0x%08x" $op $scratch]
}

puts [format "USER3_DTMCS=0x%08x" $dtmcs]
puts [format "USER4_DMI_ID=0x%08x SCRATCH=0x%08x" $ident $scratch]
puts "BSCAN_SMOKE_OK"
