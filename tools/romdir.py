"""List or extract the files inside a PS2 BIOS image (its ROMDIR table).

  romdir.py BIOS                 list entries
  romdir.py BIOS OUTDIR [NAME..] extract (all, or just the named ones)
"""
import struct
import sys
from pathlib import Path


def entries(data):
    start = data.find(b"RESET\0\0\0\0\0")
    if start < 0:
        raise SystemExit("no ROMDIR found")
    off = 0
    pos = start
    while True:
        name, ext, size = struct.unpack_from("<10sHI", data, pos)
        if name[0] == 0:
            break
        yield name.rstrip(b"\0").decode("ascii", "replace"), ext, off, size
        off += (size + 15) & ~15
        pos += 16


def main():
    data = Path(sys.argv[1]).read_bytes()
    items = list(entries(data))
    if len(sys.argv) == 2:
        for name, ext, off, size in items:
            print(f"{name:12} ext={ext:5} off=0x{off:07x} size={size}")
        return
    out = Path(sys.argv[2])
    want = set(sys.argv[3:])
    out.mkdir(parents=True, exist_ok=True)
    for name, ext, off, size in items:
        if want and name not in want:
            continue
        safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in name) or "unnamed"
        (out / safe).write_bytes(data[off:off + size])
        print("extracted", safe, size)


main()
