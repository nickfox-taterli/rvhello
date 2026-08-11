IVERILOG ?= iverilog
VVP ?= vvp
VIVADO ?= /home/taterli/tools/Xilinx/Vivado/2024.2/bin/vivado
JOBS ?= 8

# RISC-V 工具链: PATH 里有的话直接用, 没有就找本地 xpack 安装补进 PATH.
RISCV_PREFIX ?= riscv-none-elf-
XPACK_BIN := $(firstword $(wildcard $(HOME)/.local/xpack/xpack-riscv-none-elf-gcc-*/bin))
ifneq ($(XPACK_BIN),)
  PATH := $(XPACK_BIN):$(PATH)
  export PATH
endif
RISCV_GCC     := $(RISCV_PREFIX)gcc
RISCV_OBJCOPY := $(RISCV_PREFIX)objcopy
RISCV_OBJDUMP := $(RISCV_PREFIX)objdump
FW_FLAGS := -march=rv32im -mabi=ilp32 -ffreestanding -nostdlib -nostartfiles -Os -T fw/link.ld

RTL := src/core/rv32i_core.v src/core/rv32m_pcpi.v src/core/prog_mem.v \
       src/periph/bus_decode.v src/periph/gpio.v src/periph/uart_tx.v src/periph/timer.v \
       src/board/clk_pll.v src/board/top.v src/board/seg_display.v src/periph/sram_async.v

.PHONY: all sim sim-unit sim-m-disabled sim-timer sim-top sim-sram fw create synth impl bitstream program sram-create sram-synth sram-impl sram-bitstream sram-program clean

all: sim

sim: sim-unit sim-m-disabled sim-timer sim-top

sim-unit: build/rv32i.vvp
	$(VVP) build/rv32i.vvp

sim-m-disabled: build/m_disabled.vvp
	$(VVP) build/m_disabled.vvp

build/m_disabled.vvp: src/core/rv32i_core.v src/core/rv32m_pcpi.v src/core/prog_mem.v sim/tb_m_disabled.v sim/program_core.hex | build
	$(IVERILOG) -g2012 -s tb_m_disabled -o $@ src/core/rv32i_core.v src/core/rv32m_pcpi.v src/core/prog_mem.v sim/tb_m_disabled.v

sim-timer: build/timer.vvp
	$(VVP) build/timer.vvp

build/timer.vvp: src/periph/timer.v sim/tb_timer.v | build
	$(IVERILOG) -g2012 -s tb_timer -o $@ src/periph/timer.v sim/tb_timer.v

sim-top: build/top.vvp
	$(VVP) build/top.vvp

sim-sram: build/sram_async.vvp
	$(VVP) build/sram_async.vvp

build/sram_async.vvp: src/periph/sram_async.v sim/tb_sram_async.v | build
	$(IVERILOG) -g2012 -s tb_sram_async -o $@ src/periph/sram_async.v sim/tb_sram_async.v

build/rv32i.vvp: src/core/rv32i_core.v src/core/rv32m_pcpi.v src/core/prog_mem.v sim/tb_rv32i.v sim/program_core.hex | build
	$(IVERILOG) -g2012 -s tb_rv32i -o $@ src/core/rv32i_core.v src/core/rv32m_pcpi.v src/core/prog_mem.v sim/tb_rv32i.v

build/top.vvp: $(RTL) sim/tb_top.v src/program.hex | build
	$(IVERILOG) -g2012 -s tb_top -o $@ $(RTL) sim/tb_top.v

build:
	mkdir -p $@

# 固件: start.S + main.c -> elf -> bin -> 字格式 hex (刷新 src/program.hex).
# src/program.hex 随仓库提交了一份, 没装 riscv 工具链也能直接 make sim; 装了才 make fw.
fw: build/firmware.bin script/elf2hex.py
	python3 script/elf2hex.py build/firmware.bin > src/program.hex
	@echo "已刷新 src/program.hex"

build/firmware.elf: fw/start.S fw/main.c fw/link.ld | build
	$(RISCV_GCC) $(FW_FLAGS) fw/start.S fw/main.c -o $@
	$(RISCV_OBJDUMP) -dr $@ > build/firmware.lst

build/firmware.bin: build/firmware.elf
	$(RISCV_OBJCOPY) -O binary $< $@

create synth impl bitstream:
	$(VIVADO) -mode batch -source script/vivado_flow.tcl -tclargs $@ $(JOBS)

sram-create sram-synth sram-impl sram-bitstream:
	$(VIVADO) -mode batch -source script/vivado_flow.tcl -tclargs $@ $(JOBS)

program:
	$(VIVADO) -mode batch -source script/vivado_flow.tcl -tclargs program

sram-program:
	$(VIVADO) -mode batch -source script/vivado_flow.tcl -tclargs sram-program

clean:
	rm -rf build rvhello.xpr rvhello.cache rvhello.hw rvhello.ip_user_files rvhello.runs rvhello.sim rvhello.srcs rvhello.gen .Xil xsim.dir
	rm -f *.jou *.log *.pb *.str *.wdb
