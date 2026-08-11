.section .text.start
.globl _start
.globl trap_entry

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

.balign 4
trap_entry:
  # 异步中断会打断任意 C 代码,所以保存所有 caller-saved 寄存器.
  addi sp, sp, -64
  sw ra,  0(sp)
  sw t0,  4(sp)
  sw t1,  8(sp)
  sw t2, 12(sp)
  sw a0, 16(sp)
  sw a1, 20(sp)
  sw a2, 24(sp)
  sw a3, 28(sp)
  sw a4, 32(sp)
  sw a5, 36(sp)
  sw a6, 40(sp)
  sw a7, 44(sp)
  sw t3, 48(sp)
  sw t4, 52(sp)
  sw t5, 56(sp)
  sw t6, 60(sp)

  call timer_interrupt

  lw ra,  0(sp)
  lw t0,  4(sp)
  lw t1,  8(sp)
  lw t2, 12(sp)
  lw a0, 16(sp)
  lw a1, 20(sp)
  lw a2, 24(sp)
  lw a3, 28(sp)
  lw a4, 32(sp)
  lw a5, 36(sp)
  lw a6, 40(sp)
  lw a7, 44(sp)
  lw t3, 48(sp)
  lw t4, 52(sp)
  lw t5, 56(sp)
  lw t6, 60(sp)
  addi sp, sp, 64
  mret
