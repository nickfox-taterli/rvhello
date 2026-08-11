#!/usr/bin/env python3
"""Convert and run self-checking ACT4 ELF files on the RTL testbench."""

import argparse
import pathlib
import subprocess
import sys
import tempfile


def elf_to_hex(objcopy, elf, output):
    binary = output.with_suffix(".bin")
    subprocess.run([objcopy, "-O", "binary", str(elf), str(binary)], check=True)
    data = binary.read_bytes()
    data += b"\0" * (-len(data) % 4)
    words = [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]
    output.write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("elf_dir", type=pathlib.Path)
    parser.add_argument("--vvp-image", default="build/arch.vvp")
    parser.add_argument("--objcopy", default="riscv-none-elf-objcopy")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--max-cycles", type=int, default=2_000_000)
    args = parser.parse_args()

    elfs = sorted(path for path in args.elf_dir.rglob("*.elf") if not path.name.endswith(".sig.elf"))
    if not elfs:
        parser.error(f"no ACT4 ELF files found below {args.elf_dir}")

    failures = []
    with tempfile.TemporaryDirectory(prefix="rvhello-act4-") as tmp:
        temp_dir = pathlib.Path(tmp)
        for index, elf in enumerate(elfs, 1):
            image = temp_dir / f"test-{index}.hex"
            try:
                elf_to_hex(args.objcopy, elf, image)
                result = subprocess.run(
                    [args.vvp, args.vvp_image, f"+HEX={image}", f"+MAX_CYCLES={args.max_cycles}"],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    check=False,
                )
            except (OSError, subprocess.CalledProcessError) as error:
                failures.append((elf, str(error)))
                print(f"FAIL {elf}: {error}")
                continue
            if result.returncode == 0 and "ARCH PASS" in result.stdout:
                print(f"PASS [{index}/{len(elfs)}] {elf.name}")
            else:
                failures.append((elf, result.stdout.strip()))
                print(f"FAIL [{index}/{len(elfs)}] {elf.name}")

    if failures:
        print(f"\n{len(failures)} of {len(elfs)} ACT4 tests failed", file=sys.stderr)
        for elf, detail in failures:
            print(f"- {elf}: {detail}", file=sys.stderr)
        return 1
    print(f"\nACT4 PASS: {len(elfs)} tests")
    return 0


if __name__ == "__main__":
    sys.exit(main())

