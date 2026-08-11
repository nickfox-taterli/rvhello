#!/usr/bin/env python3
# 把 RISC-V 固件的原始二进制 (.bin) 转成 prog_mem 的 $readmemh 字格式:
# 每行一个 32 位字 (8 个 hex 位), 小端打包, 从 mem[0] 起顺序填, 不带 @ 前缀.
# 末尾不足 4 字节补 0 对齐到字. 用法:
#   riscv32-unknown-elf-objcopy -O binary firmware.elf firmware.bin
#   python3 script/elf2hex.py firmware.bin > src/program.hex
import sys


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: elf2hex.py firmware.bin > program.hex\n")
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = f.read()

    pad = (-len(data)) % 4
    if pad:
        data = data + b"\x00" * pad

    out = []
    for i in range(0, len(data), 4):
        word = data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24)
        out.append("%08x" % word)
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
