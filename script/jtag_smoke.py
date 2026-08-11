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
        op, ident = access(jtag, 0x70, 0, DMI_READ)
        if op != 0 or ident != 0x52564831:
            raise SystemExit(f"Unexpected DMI ID: op={op} data=0x{ident:08x}")

        access(jtag, 0x71, 0x89ABCDEF, DMI_WRITE)
        op, scratch = access(jtag, 0x71, 0, DMI_READ)
        if op != 0 or scratch != 0x89ABCDEF:
            raise SystemExit(f"Scratch mismatch: op={op} data=0x{scratch:08x}")

        op, pc = access(jtag, 0x72, 0, DMI_READ)
        if op != 0:
            raise SystemExit(f"PC read failed: op={op}")

        print(f"IDCODE=0x{idcode:08x}")
        print(f"DTMCS=0x{dtmcs:08x}")
        print(f"DMI_ID=0x{ident:08x} SCRATCH=0x{scratch:08x} PC=0x{pc:08x}")
        print("JTAG_SMOKE_OK")
    finally:
        jtag.close()


if __name__ == "__main__":
    main()
