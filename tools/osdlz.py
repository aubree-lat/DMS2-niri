"""Decompressor for the PS2 BIOS's LZ-compressed resources (SNDIMAGE parts,
ICOIMAGE, TEXIMAGE...). Layout: u32 LE output size, then groups of a 32-bit
big-endian control word followed by up to 30 items. The control word's low
2 bits pick how a back-reference is split between offset and length; the top
30 bits flag each item as a literal byte (0) or a 2-byte back-reference (1).

  osdlz.py IN OUT
"""
import struct
import sys
from pathlib import Path


def decompress(src, variant=(True, True, 1, 3)):
    msb_first, be_block, off_add, len_add = variant
    out_len = struct.unpack_from("<I", src, 0)[0]
    p = 4
    out = bytearray()
    while len(out) < out_len:
        if p + 4 > len(src):
            raise ValueError("ran out of input")
        block = int.from_bytes(src[p:p + 4], "big" if be_block else "little")
        p += 4
        shift = block & 3
        mask = 0x3FFF >> shift
        for i in range(30):
            if len(out) >= out_len:
                break
            bit = (block >> (31 - i)) & 1 if msb_first else (block >> (2 + i)) & 1
            if bit:
                h = (src[p] << 8) | src[p + 1]
                p += 2
                off = (h & mask) + off_add
                run = (h >> (14 - shift)) + len_add
                if off > len(out) or off <= 0:
                    raise ValueError("bad back-reference")
                for _ in range(run):
                    out.append(out[-off])
            else:
                out.append(src[p])
                p += 1
    return bytes(out[:out_len]), p


if __name__ == "__main__":
    data = Path(sys.argv[1]).read_bytes()
    out, used = decompress(data)
    Path(sys.argv[2]).write_bytes(out)
    print(f"{len(data)} -> {len(out)} bytes (consumed {used})")
