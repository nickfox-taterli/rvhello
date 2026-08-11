// 独立运行固件: 没有 libc, 操作系统驱动或设备树. 以下左值宏把 C 语言
// 读写直接映射到 SoC 地址空间.
#define MMIO32(address) (*(volatile unsigned int *)(address))
#define MMIO8(address)  (*(volatile unsigned char *)(address))

// UART 数据只使用状态地址的最低字节通道. 不同 C 类型有意让编译器分别生成 LW/SB.
#define UART_STATE    MMIO32(0x10000010u)
#define UART_DATA     MMIO8(0x10000010u)

// Timer: counter 自由跑(只读), compare 设阈值, 到点 pending 置位(写清除).
#define TIMER_COUNTER MMIO32(0x10000020u)
#define TIMER_COMPARE MMIO32(0x10000024u)
#define TIMER_PENDING MMIO32(0x10000028u)

// GPO.WR rs1: 自定义指令 (custom-0, opcode 0x0b), 把 rs1 的 32 位值直接写到
// GPIO (0x1000_0000). 相比 lui+addi+sw, 它省掉地址准备又仍走 mem_valid/mem_ready
// 总线, 保留 CPU/外设解耦. 固定字段 funct7/funct3/rd/rs2 全 0; 读回 GPIO 仍用
// MMIO32(0x10000000u) 走标准 LW.
#define gpo_wr(value) do { \
    unsigned int _gpo_v = (unsigned int)(value); \
    __asm__ volatile (".insn r 0x0b, 0, 0, x0, %0, x0" : : "r"(_gpo_v) : "memory"); \
} while (0)

// volatile MMIO 访问必须保持程序顺序; 发送器忙时 UART_STATE 的 bit 0 为 1.
static void uart_putc(char character)
{
    // 在中断课之前先使用轮询; volatile 强制每轮重新读总线, 而非缓存状态.
    while (UART_STATE & 1u) {
        // 忙等待; 后续课程会用中断替代.
    }
    // 字节写产生 wstrb=0001, 不会干扰未实现的通道.
    UART_DATA = (unsigned char)character;
}

static int mul_self_test(void)
{
    // volatile 只用于防止固定用例被常量折叠. 每一条断言本身就是待验证的 C 算式.
    volatile unsigned int a;
    volatile unsigned int b;

    a = 0u; b = 1u;
    if (a * b != 0u) return 0;                                                    // MUL
    a = 0xffffffffu; b = 1u;
    if (a * b != 0xffffffffu) return 0;                                           // MUL
    a = 0xffffffffu; b = 0xffffffffu;
    if ((unsigned int)(((long long)(int)a * (long long)(int)b) >> 32) != 0u) return 0;  // MULH
    a = 0xffffffffu; b = 1u;
    if ((unsigned int)(((long long)(int)a * (long long)(int)b) >> 32) !=
        0xffffffffu) return 0;                                                    // MULH
    a = 0xffffffffu; b = 0xffffffffu;
    if ((unsigned int)(((unsigned long long)((long long)(int)a *
                                               (unsigned long long)b)) >> 32) !=
        0xffffffffu) return 0;                                                    // MULHSU
    if ((unsigned int)(((unsigned long long)a * (unsigned long long)b) >> 32) !=
        0xfffffffeu) return 0;                                                    // MULHU
    a = 0x80000000u; b = 0x80000000u;
    if (a * b != 0u) return 0;                                                     // MUL
    if ((unsigned int)(((long long)(int)a * (long long)(int)b) >> 32) !=
        0x40000000u) return 0;                                                    // MULH
    b = 0xffffffffu;
    if ((unsigned int)(((unsigned long long)((long long)(int)a *
                                               (unsigned long long)b)) >> 32) !=
        0x80000000u) return 0;                                                    // MULHSU
    if ((unsigned int)(((unsigned long long)a * (unsigned long long)b) >> 32) !=
        0x7fffffffu) return 0;                                                    // MULHU

    a = 7u; b = 3u;
    if ((unsigned int)((int)a / (int)b) != 2u) return 0;                          // DIV
    if (a / b != 2u) return 0;                                                     // DIVU
    a = 0xfffffff9u;
    if ((unsigned int)((int)a / (int)b) != 0xfffffffeu) return 0;                 // DIV
    if ((unsigned int)((int)a % (int)b) != 0xffffffffu) return 0;                 // REM
    a = 7u;
    if (a % b != 1u) return 0;                                                     // REMU
    a = 0x80000000u; b = 0xffffffffu;
    if ((unsigned int)((int)a / (int)b) != 0x80000000u) return 0;                 // DIV overflow
    if ((unsigned int)((int)a % (int)b) != 0u) return 0;                          // REM overflow
    a = 7u; b = 0u;
    if ((unsigned int)((int)a / (int)b) != 0xffffffffu) return 0;                 // DIV by zero
    if (a / b != 0xffffffffu) return 0;                                            // DIVU by zero
    if ((unsigned int)((int)a % (int)b) != 7u) return 0;                          // REM by zero
    if (a % b != 7u) return 0;                                                     // REMU by zero
    return 1;
}

int main(void)
{
    // 第一个可见里程碑: 用自定义指令 GPO.WR 点亮 LED bit 0 (不走标准 SW),
    // 然后用 UART 打个招呼.
    gpo_wr(1);
    if (!mul_self_test()) {
        gpo_wr(0x81u);
        uart_putc('M');
        uart_putc('!');
        uart_putc('\n');
        for (;;) {
            // 乘法自检失败后保持错误码, 方便实板直接识别.
        }
    }
    uart_putc('O');
    uart_putc('K');
    uart_putc('\n');

    // 用定时器把 LED 翻转节拍拉慢到肉眼可见. counter 自由单调递增;
    // compare 设成 counter+tick, counter 追上时 pending 置位; 软件轮询到就
    // 清 pending + 翻转 LED + 把 compare 推到下一个节拍.
    const unsigned int tick = 25000000u;        // 50 MHz / 25M = 0.5 s
    unsigned int next = TIMER_COUNTER + tick;
    TIMER_COMPARE = next;
    unsigned int leds = 0xFFu;
    for (;;) {
        while ((TIMER_PENDING & 1u) == 0u) {
            // 等节拍到来; pending 置位后保持到软件写清除.
        }
        TIMER_PENDING = 1u;                     // 写任意值清 pending
        leds ^= 0xFFu;                          // 全 8 位 LED 翻转
        gpo_wr(leds);                           // 用 GPO.WR 把新图案送出去
        next += tick;                            // 下一节拍 (unsigned 回绕也无妨)
        TIMER_COMPARE = next;
    }
}
