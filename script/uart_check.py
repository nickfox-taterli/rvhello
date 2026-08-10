#!/usr/bin/env python3
import argparse
import os
import select
import termios
import time

parser = argparse.ArgumentParser(description="检查 FPGA 周期发送的 UART 文本")
parser.add_argument("--port", default="/dev/ttyACM0")
parser.add_argument("--baud", type=int, default=115200)
parser.add_argument("--timeout", type=float, default=3.0)
args = parser.parse_args()

speed = getattr(termios, f"B{args.baud}", None)
if speed is None:
    raise SystemExit(f"不支持波特率 {args.baud}")
fd = os.open(args.port, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
try:
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0
    attrs[4] = speed
    attrs[5] = speed
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIFLUSH)
    deadline = time.monotonic() + args.timeout
    data = bytearray()
    while time.monotonic() < deadline and b"Hello FPGA!\r\n" not in data:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            data.extend(os.read(fd, 4096))
    if b"Hello FPGA!\r\n" not in data:
        raise SystemExit(f"UART_CHECK_FAIL: 收到 {bytes(data)!r}")
    print(f"UART_CHECK_OK: {args.port} 收到 Hello FPGA!")
finally:
    os.close(fd)
