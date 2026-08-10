IVERILOG ?= iverilog
VVP ?= vvp
VIVADO ?= /home/taterli/tools/Xilinx/Vivado/2024.2/bin/vivado
JOBS ?= 8
PORT ?= /dev/ttyACM0

RTL := src/blink.v src/uart_tx.v src/top.v

.PHONY: all sim sim-unit sim-top create synth impl bitstream program uart-check clean

all: sim

sim: sim-unit sim-top

sim-unit: build/blink.vvp build/uart_tx.vvp
	$(VVP) build/blink.vvp
	$(VVP) build/uart_tx.vvp

sim-top: build/top.vvp
	$(VVP) build/top.vvp

build/blink.vvp: src/blink.v sim/tb_blink.v | build
	$(IVERILOG) -g2012 -s tb_blink -o $@ $^

build/uart_tx.vvp: src/uart_tx.v sim/tb_uart_tx.v | build
	$(IVERILOG) -g2012 -s tb_uart_tx -o $@ $^

build/top.vvp: $(RTL) sim/tb_top.v | build
	$(IVERILOG) -g2012 -s tb_top -o $@ $^

build:
	mkdir -p $@

create synth impl bitstream:
	$(VIVADO) -mode batch -source script/vivado_flow.tcl -tclargs $@ $(JOBS)

program:
	$(VIVADO) -mode batch -source script/vivado_flow.tcl -tclargs program

uart-check:
	python3 script/uart_check.py --port $(PORT)

clean:
	rm -rf build rvhello.xpr rvhello.cache rvhello.hw rvhello.ip_user_files rvhello.runs rvhello.sim rvhello.srcs rvhello.gen .Xil xsim.dir
	rm -f *.jou *.log *.pb *.str *.wdb
