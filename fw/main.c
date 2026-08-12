// 独立运行固件,没有 libc 和操作系统.MMIO 左值直接映射到 SoC 地址空间.
#define MMIO32(address) (*(volatile unsigned int *)(address))

#define GPIO_OUTPUT       MMIO32(0x10000000u)
#define CLINT_MTIMECMP_LO MMIO32(0x02004000u)
#define CLINT_MTIMECMP_HI MMIO32(0x02004004u)
#define CLINT_MTIME_LO    MMIO32(0x0200bff8u)
#define CLINT_MTIME_HI    MMIO32(0x0200bffcu)
#define PLIC_CLAIM        MMIO32(0x0c200004u)

// CPU 时钟是 100 MHz,每 50M 拍翻转一次,所以 LED 每 0.5 s 变化一次.
#define TIMER_TICKS 50000000ull

extern void trap_entry(void);

static volatile unsigned int led_state;

// RV32 读 64 位 mtime 时确认高半没有跨越,避免得到撕裂值.
static unsigned long long timer_now(void)
{
    unsigned int hi0;
    unsigned int lo;
    unsigned int hi1;

    do {
        hi0 = CLINT_MTIME_HI;
        lo = CLINT_MTIME_LO;
        hi1 = CLINT_MTIME_HI;
    } while (hi0 != hi1);

    return ((unsigned long long)hi1 << 32) | lo;
}

// RV32 按高全 1,低,最终高的顺序更新比较值,避免写到一半误触发 MTIP.
static void timer_set_compare(unsigned long long value)
{
    CLINT_MTIMECMP_HI = 0xffffffffu;
    CLINT_MTIMECMP_LO = (unsigned int)value;
    CLINT_MTIMECMP_HI = (unsigned int)(value >> 32);
}

static void timer_interrupt(void)
{
    timer_set_compare(timer_now() + TIMER_TICKS);
    led_state ^= 0xffu;
    GPIO_OUTPUT = led_state;
}

void machine_trap(void)
{
    unsigned int cause;
    unsigned int source;

    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    if (cause == 0x80000007u) {
        timer_interrupt();
    } else if (cause == 0x8000000bu) {
        // claim 读会原子清 pending.complete 写会重新打开对应 gateway.
        source = PLIC_CLAIM;
        if (source != 0u)
            PLIC_CLAIM = source;
    }
}

int main(void)
{
    unsigned int bits;

    led_state = 0u;
    GPIO_OUTPUT = led_state;
    timer_set_compare(timer_now() + TIMER_TICKS);

    // 使用 RISC-V 机器模式标准 CSR 打开 MTIP 和全局中断.
    __asm__ volatile ("csrw mtvec, %0" : : "r"(trap_entry) : "memory");
    bits = 1u << 7;
    __asm__ volatile ("csrs mie, %0" : : "r"(bits) : "memory");
    bits = 1u << 3;
    __asm__ volatile ("csrs mstatus, %0" : : "r"(bits) : "memory");

    for (;;) {
        // 本核允许 WFI 当 NOP,中断仍只会在指令边界进入.
        __asm__ volatile ("wfi");
    }
}
