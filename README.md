# FPGA Hello

PRX100T 开发板, 主芯片 `xc7a100tfgg676-2` 的工程, 做一个小 RISC-V SoC, 也算记录这个工程一路怎么长出来的.

## SoC 结构

RV32I 单核, 取指与访存共用一组 valid/ready 总线, 经地址译码器分发到四个从端:

| 地址 | 设备 | 语义 |
|---|---|---|
| 0x0000_0000 - 0x0000_3fff | BRAM 16 KiB | 代码 / 数据 / 栈 |
| 0x1000_0000 | GPIO | 字写 LED 输出, 字读回 |
| 0x1000_0010 | UART TX | 同地址读写分离: 写低字节=发送, 读 bit0=busy |
| 0x1000_0020 / 24 / 28 | Timer | counter(RO) / compare(RW) / pending(R=状态, W=清除) |

## 目录

- `src/core/` 核与 BRAM 后端
- `src/periph/` 地址译码器 + GPIO / UART / Timer
- `src/board/` 顶层与数码管扫描
- `fw/` 固件源码 (link.ld / start.S / main.c), `-march=rv32i -mabi=ilp32`
- `sim/` 仿真测试台

## 用法

```sh
make sim          # iverilog 单元 + 顶层行为仿真
make fw           # riscv 工具链编译固件, 刷新 src/program.hex
make bitstream    # Vivado 综合并实现, 生成 bitstream
make program      # 下载到 FPGA
make clean
```

`make fw` 需要 riscv 工具链 (PATH 里的 `riscv-none-elf-` 或 `riscv32-unknown-elf-`, 否则回落到 `~/.local/xpack/...`). 