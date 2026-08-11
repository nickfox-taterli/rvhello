# FPGA Hello

PRX100T 开发板, 主芯片 `xc7a100tfgg676-2` 的工程, 做一个小 RISC-V SoC, 也算记录这个工程一路怎么长出来的.

## SoC 结构

RV32I 单核, 取指与访存共用一组 valid/ready 总线, 经地址译码器分发到各个从端. 乘法子集当前实现 MUL, MULH, MULHSU, MULHU:

- DSP 路径按每种指令的 signedness 扩展两个操作数, 锁存完整 64 位积后取高半或低半.
- 回退路径按 `multiplier[0]` 做条件累加, 再左移被乘数和右移乘数.
- 除零和 `INT_MIN / -1` 走 ISA 规定的特殊结果.

| 地址 | 设备 | 语义 |
|---|---|---|
| 0x0000_0000 - 0x0000_3fff | BRAM 16 KiB | 代码 / 数据 / 栈 |
| 0x1000_0000 | GPIO | 字写 LED 输出, 字读回 |
| 0x1000_0010 | UART TX | 同地址读写分离: 写低字节=发送, 读 bit0=busy |
| 0x0200_0000 + 4*hart | CLINT MSIP | 软件中断位,RW |
| 0x0200_4000 + 8*hart | CLINT MTIMECMP | 64 位机器定时器比较值,RW |
| 0x0200_bff8 | CLINT MTIME | 64 位机器定时器计数,RW |
| 0x0c00_0004 - 0x0c00_0080 | PLIC priority | 固定读 1,当前写入忽略 |
| 0x0c00_1000 - 0x0c00_1004 | PLIC pending | source ID 位图,只读 |
| 0x0c00_1080 - 0x0c00_1084 | PLIC trigger | source ID 位图,0=电平,1=上升沿 |
| 0x0c00_2000 - 0x0c00_2004 | PLIC enable | source ID 位图,RW |
| 0x0c20_0000 | PLIC threshold | 固定读 0,当前写入忽略 |
| 0x0c20_0004 | PLIC claim/complete | 读 claim source ID,写 complete source ID |

CPU 只接收标准的 MSIP,MTIP 和 MEIP,分别位于 `mcause` 3,7 和 11.PLIC 默认实例化 16 路,参数可切换到 32 路,外设 source ID 从 1 开始.异步源统一经过两级同步,pending 会把同步器捕获到的边沿脉冲保持到 claim.当前所有源优先级固定为 1,同时 pending 时选择较小 source ID;threshold 保留为 0,地址地图为以后加入可编程优先级留好位置.CLINT 使用常见寄存器布局,当前实例化一个 hart,RTL 参数可以扩展多个 hart 的 `msip` 和 `mtimecmp`,所有 hart 共用 `mtime`.核实现标准机器态异常入口和精确 `mepc`,并提供 `mstatus`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`,机器 ID 以及 64 位 `mcycle/minstret`.用户别名 `cycle/instret` 为只读,所有 CSR 的 WARL/WPRI 掩码在 RTL 中显式处理.

ECALL,非法指令,指令/Load/Store 地址不对齐以及三类访问错误都会写入 `mcause/mepc/mtval` 后跳到 `mtvec`.WFI 会停止取指直到本地使能的中断待决或调试 halt,FENCE.I 会丢弃取指状态并从下一条指令重新取指.

## 调试链路

- FTDI 端口 0 继续用于 Xilinx 配置 JTAG;端口 1 通过独立 IO 接入 5 位 RISC-V JTAG TAP.
- Xilinx JTAG 的 USER3/USER4 通过两个 `BSCANE2` 分别接入 DTMCS 和 DMI.
- 两条链路汇入同一个 RISC-V Debug Module 0.13 后端,可由 OpenOCD 和 GDB 直接调试.
- 核内 halt 接口会锁存短脉冲请求.取指,数据访存或 PCPI 已经开始时,必须等当前事务完成并退休到精确边界后才冻结 PC;resume 从该边界继续.
- DM 支持 halt/resume/ndmreset,abstract register 和 8/16/32 位 SBA.当前单 hart 实现不带 program buffer,系统总线访问要求 hart 已停止.
- abstract register 可读写 32 个 GPR,dpc,dcsr,mstatus,misa,mie,mtvec,mepc,mcause,mip 和 hart ID CSR;dcsr.step 用于硬件单步,EBREAK 会进入 Debug Mode.

| DMI 地址 | 寄存器 |
|---|---|
| 0x04 | DATA0 |
| 0x10 - 0x12 | DMCONTROL / DMSTATUS / HARTINFO |
| 0x16 - 0x18 | ABSTRACTCS / COMMAND / ABSTRACTAUTO |
| 0x38 - 0x3c | SBCS / SBADDRESS0 / SBDATA0 |
| 0x40 | HALTSUM0 |

## 自定义指令 GPO.WR

`GPO.WR rs1` (custom-0, opcode 0x0b) 

编码 (R 型): `funct7=0 | rs2=0 | rs1 | funct3=0 | rd=0 | opcode=0001011`.

## 目录

- `src/core/` 核与 BRAM 后端
- `src/periph/` 地址译码器 + GPIO / UART / Timer / PLIC
- `src/board/` 顶层与数码管扫描
- `fw/` 固件源码 (link.ld / start.S / main.c), `-march=rv32im_zicsr_zifencei -mabi=ilp32`
- `sim/` 仿真测试台

## 用法

```sh
make sim          # iverilog 单元 + 顶层行为仿真
make arch-test ACT_ELF_DIR=/path/to/elfs # 批量运行 ACT4 自检 ELF
make fw           # riscv 工具链编译固件, 刷新 src/program.hex
make bitstream    # Vivado 综合并实现, 生成 bitstream
make program      # 下载到 FPGA
make jtag-smoke   # 从 FTDI 端口 1 检查 halt,abstract register 和 resume
make bscan-smoke  # 从 FTDI 端口 0 检查 BSCANE2 USER3/USER4 和标准 DM
make openocd-probe # OpenOCD 枚举 hart 并读取 PC/GPR
make openocd-load # 通过 OpenOCD 把 build/firmware.elf 写入 BRAM,校验后从 0 运行
# 另一个终端保持 OpenOCD 运行后执行:
make gdb-smoke    # GDB 检查寄存器,断点,单步和内存读写
make clean
```

ACT4 的 rvhello 配置和运行说明位于 `sim/act4/`.架构回归目标覆盖
RV32IM/Zicsr/Zifencei/Zicntr,并由独立测试台收集每个 ELF 的 pass/fail 结果.

`make fw` 需要 riscv 工具链 (PATH 里的 `riscv-none-elf-` 或 `riscv32-unknown-elf-`, 否则回落到 `~/.local/xpack/...`).
固件默认使用 `-Og -g3 -gdwarf-4`,便于 GDB 按源码单步.需要尺寸优化时可执行
`make FW_OPT=-Os fw`.

VS Code 中选择 `RVHello: Cortex-Debug 下载并调试` 后按 F5.配置会编译 ELF,启动 OpenOCD,
通过 SBA 把 ELF 写入 BRAM,然后运行到 `main`.只下载不进入调试器时,运行任务
`RVHello: OpenOCD 下载 ELF`.
