# FPGA Hello

PRX100T开发板,主芯片`xc7a100tfgg676-2`的工程,最终目标做个什么我还没想好,先尝试一个小RISC-V吧,这个工程也算是记录这个工程成长了.

```sh
make sim          # 单元与顶层行为仿真
make bitstream    # 综合,实现并生成 bitstream
make program      # 下载到 FPGA
make uart-check   # 默认检查 /dev/ttyACM0,可用 PORT=/dev/ttyXXX 覆盖
make clean
```
