#!/usr/bin/env python3

from pyftdi.bits import BitSequence
from pyftdi.jtag import JtagEngine

URL = "ftdi://ftdi:2232/2"
IR_DTMCS = 0x10
IR_DMI = 0x11
DMI_NOP = 0
DMI_READ = 1
DMI_WRITE = 2


def idle(jtag, cycles):
    while cycles:
        count = min(cycles, 7)
        jtag.write_tms(BitSequence(0, length=count))
        cycles -= count


def dmi_scan(jtag, addr=0, data=0, op=DMI_NOP):
    value = (addr << 34) | (data << 2) | op
    jtag.write_dr(BitSequence(value, length=41))
    jtag.go_idle()
    idle(jtag, 16)
    raw = int(jtag.read_dr(41))
    jtag.go_idle()
    idle(jtag, 4)
    return raw & 3, (raw >> 2) & 0xFFFFFFFF


def access(jtag, addr, data, op):
    dmi_scan(jtag, addr, data, op)
    return dmi_scan(jtag)


def expect_ok(jtag, addr, data=0, op=DMI_READ):
    rsp_op, rsp_data = access(jtag, addr, data, op)
    if rsp_op != 0:
        raise SystemExit(f"DMI access failed: addr=0x{addr:02x} op={rsp_op}")
    return rsp_data


def wait_set(jtag, addr, mask, label):
    for _ in range(100):
        value = expect_ok(jtag, addr)
        if value & mask:
            return value
    raise SystemExit(f"Timeout waiting for {label}: last=0x{value:08x}")


def wait_clear(jtag, addr, mask, label):
    for _ in range(100):
        value = expect_ok(jtag, addr)
        if not value & mask:
            return value
    raise SystemExit(f"Timeout waiting for {label}: last=0x{value:08x}")


def main():
    jtag = JtagEngine(frequency=1e6)
    jtag.configure(URL)
    try:
        jtag.reset()
        jtag.go_idle()
        idcode = int(jtag.read_dr(32))
        if idcode != 0x100000DB:
            raise SystemExit(f"Unexpected IDCODE: 0x{idcode:08x}")

        jtag.write_ir(BitSequence(IR_DTMCS, length=5))
        dtmcs = int(jtag.read_dr(32))
        if (dtmcs & 0xF, (dtmcs >> 4) & 0x3F) != (1, 7):
            raise SystemExit(f"Unexpected DTMCS: 0x{dtmcs:08x}")

        jtag.write_ir(BitSequence(IR_DMI, length=5))
        expect_ok(jtag, 0x10, 0x00000001, DMI_WRITE)
        dmstatus = expect_ok(jtag, 0x11)
        if (dmstatus & 0xF) != 2 or not (dmstatus & (1 << 7)):
            raise SystemExit(f"Unexpected DMSTATUS: 0x{dmstatus:08x}")

        expect_ok(jtag, 0x10, 0x80000001, DMI_WRITE)
        dmstatus = wait_set(jtag, 0x11, 1 << 8, "halt")

        # Access Register: 32 位,transfer=1,读取 dpc.
        expect_ok(jtag, 0x17, 0x002207B1, DMI_WRITE)
        abstractcs = wait_clear(jtag, 0x16, 1 << 12, "abstract command")
        if abstractcs & 0x700:
            raise SystemExit(f"Abstract command failed: 0x{abstractcs:08x}")
        pc = expect_ok(jtag, 0x04)

        expect_ok(jtag, 0x04, 0x89ABCDEF, DMI_WRITE)
        expect_ok(jtag, 0x17, 0x00231005, DMI_WRITE)
        abstractcs = wait_clear(jtag, 0x16, 1 << 12, "abstract write")
        if abstractcs & 0x700:
            raise SystemExit(f"Abstract write failed: 0x{abstractcs:08x}")
        expect_ok(jtag, 0x17, 0x00221005, DMI_WRITE)
        abstractcs = wait_clear(jtag, 0x16, 1 << 12, "abstract read")
        if abstractcs & 0x700:
            raise SystemExit(f"Abstract read failed: 0x{abstractcs:08x}")
        t0 = expect_ok(jtag, 0x04)
        if t0 != 0x89ABCDEF:
            raise SystemExit(f"Abstract GPR mismatch: 0x{t0:08x}")

        expect_ok(jtag, 0x10, 0x40000001, DMI_WRITE)
        dmstatus = wait_set(jtag, 0x11, 1 << 10, "resume")

        print(f"IDCODE=0x{idcode:08x}")
        print(f"DTMCS=0x{dtmcs:08x}")
        print(f"DMSTATUS=0x{dmstatus:08x} DPC=0x{pc:08x} T0=0x{t0:08x}")
        print("JTAG_SMOKE_OK")
    finally:
        jtag.close()


if __name__ == "__main__":
    main()
