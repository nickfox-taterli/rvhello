IVERILOG ?= iverilog
VVP ?= vvp
VIVADO ?= /home/taterli/tools/Xilinx/Vivado/2024.2/bin/vivado
JOBS ?= 8

RTL := src/prog_mem.v src/seg_display.v src/rv32i_core.v src/top.v

.PHONY: all sim sim-unit sim-top create synth impl bitstream program clean

all: sim

sim: sim-unit sim-top

sim-unit: build/rv32i.vvp
	$(VVP) build/rv32i.vvp

sim-top: build/top.vvp
	$(VVP) build/top.vvp

build/rv32i.vvp: src/rv32i_core.v src/prog_mem.v sim/tb_rv32i.v src/program.hex | build
	$(IVERILOG) -g2012 -s tb_rv32i -o $@ src/rv32i_core.v src/prog_mem.v sim/tb_rv32i.v

build/top.vvp: $(RTL) sim/tb_top.v src/program.hex | build
	$(IVERILOG) -g2012 -s tb_top -o $@ $(RTL) sim/tb_top.v

build:
	mkdir -p $@

create synth impl bitstream:
	$(VIVADO) -mode batch -source script/vivado_flow.tcl -tclargs $@ $(JOBS)

program:
	$(VIVADO) -mode batch -source script/vivado_flow.tcl -tclargs program

clean:
	rm -rf build rvhello.xpr rvhello.cache rvhello.hw rvhello.ip_user_files rvhello.runs rvhello.sim rvhello.srcs rvhello.gen .Xil xsim.dir
	rm -f *.jou *.log *.pb *.str *.wdb
