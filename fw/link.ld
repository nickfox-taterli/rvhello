ENTRY(_start)

MEMORY
{
    /* rwx 描述链接权限; 这个简单 FPGA 后端没有 MPU. */
    BRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS
{
    .text : {
        /* _start 是入口, 天然存活, 因此不需要 KEEP. */
        *(.text.start)
        /* 编译器生成的函数和只读常量紧跟启动段. */
        *(.text*)
        *(.rodata*)
    } > BRAM

    .data : {
        /* 有初值的可写对象会占用固件镜像字节. */
        *(.data*)
    } > BRAM

    .bss (NOLOAD) : {
        /* NOLOAD 节省镜像空间; start.S 在启动时显式写零. */
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    } > BRAM

    /* RISC-V ABI 要求函数调用边界上栈按 16 字节对齐. */
    . = ALIGN(16);
    _end = .;
    /* 栈从 BRAM 末端后的第一个字节向低地址增长. */
    _stack_top = ORIGIN(BRAM) + LENGTH(BRAM);
}
