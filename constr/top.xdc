# 时钟
set_property PACKAGE_PIN U22 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 20.000 -name sys_clk [get_ports clk]

# KEY1/MENU -> 用作复位
set_property PACKAGE_PIN M4 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]
set_property PULLUP true [get_ports rst_n]

# LED0
set_property PACKAGE_PIN N17 [get_ports led]
set_property IOSTANDARD LVCMOS33 [get_ports led]
set_property DRIVE 8 [get_ports led]
set_property SLEW SLOW [get_ports led]

# 板载TTL
set_property PACKAGE_PIN L18 [get_ports ttl_tx]
set_property IOSTANDARD LVCMOS33 [get_ports ttl_tx]
set_property DRIVE 8 [get_ports ttl_tx]
set_property SLEW SLOW [get_ports ttl_tx]
