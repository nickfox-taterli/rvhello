// 独立运行固件: 没有 libc, 操作系统驱动或设备树. 以下左值宏把 C 语言
// 读写直接映射到 SoC 地址空间.
#define MMIO32(address) (*(volatile unsigned int *)(address))
#define MMIO8(address)  (*(volatile unsigned char *)(address))

// GPIO 按字读取; UART 数据只使用状态地址的最低字节通道. 不同 C 类型
// 有意让编译器分别生成 LW/SW 与 LB/SB.
#define GPIO          MMIO32(0x10000000u)
#define UART_STATE    MMIO32(0x10000010u)
#define UART_DATA     MMIO8(0x10000010u)

// Timer: counter 自由跑(只读), compare 设阈值, 到点 pending 置位(写清除).
#define TIMER_COUNTER MMIO32(0x10000020u)
#define TIMER_COMPARE MMIO32(0x10000024u)
#define TIMER_PENDING MMIO32(0x10000028u)

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

int main(void)
{
    // 第一个可见里程碑: 用 UART 之前先点亮 LED bit 0, 然后打个招呼.
    GPIO = 1;
    uart_putc('O');
    uart_putc('K');
    uart_putc('\n');

    // 用定时器把 LED 翻转节拍拉慢到肉眼可见. counter 自由单调递增;
    // compare 设成 counter+tick, counter 追上时 pending 置位; 软件轮询到就
    // 清 pending + 翻转 LED + 把 compare 推到下一个节拍. 这套轮询就是
    // 下一章接 IRQ 时中断处理程序的雏形.
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
        GPIO = leds;
        next += tick;                            // 下一节拍 (unsigned 回绕也无妨)
        TIMER_COMPARE = next;
    }
}
