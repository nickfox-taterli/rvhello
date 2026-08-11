.section .text.start
.globl _start

# 复位入口: 初始化栈, 清空 .bss, 然后进入 C.
_start:
  # _stack_top 由 link.ld 定义在 BRAM 末端, 并按 16 字节对齐.
  la sp, _stack_top
  # a0 是当前清零指针, a1 是不包含在范围内的结束地址.
  la a0, _bss_start
  la a1, _bss_end

# 链接脚本保证 .bss 边界按字对齐.
1:
  # 这些值是物理地址, 因此使用无符号比较.
  bgeu a0, a1, 2f
  # 链接器已对齐 .bss, 因此字写入天然对齐.
  sw zero, 0(a0)
  addi a0, a0, 4
  j 1b

2:
  # RISC-V call 把返回地址写入 ra; main 使用普通 ilp32 ABI.
  call main

# main 正常情况下不会返回; 若返回, 则停在此处.
3:
  # 系统中没有操作系统可以接收退出状态.
  j 3b
