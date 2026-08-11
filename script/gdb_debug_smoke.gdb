set pagination off
set confirm off
file build/firmware.elf
target extended-remote localhost:3333
monitor halt
set $t0 = 0x12345678
if $t0 != 0x12345678
  quit 1
end
set $pc = 0
break main
continue
if $pc != main
  quit 1
end
set $t1 = 0x89abcdef
set $before_step_pc = $pc
stepi
if $t1 != 0x89abcdef
  quit 1
end
if $pc == $before_step_pc
  quit 1
end
set {unsigned int}0x00000300 = 0x55aa33cc
if {unsigned int}0x00000300 != 0x55aa33cc
  quit 1
end
delete breakpoints
detach
quit 0
