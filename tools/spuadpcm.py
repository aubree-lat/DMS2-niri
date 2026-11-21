"""Split a raw SPU2 ADPCM bank into its samples and decode each to 16-bit WAV.

Frames are 16 bytes: shift/filter byte, flags byte (bit0 = end of sample,
bit1 = repeat, bit2 = loop start), 14 bytes of 4-bit deltas (28 samples).

  spuadpcm.py BANK OUTDIR [RATE]
"""
import struct
import sys
import wave
from pathlib import Path

F0 = (0, 60, 115, 98, 122)
F1 = (0, 0, -52, -55, -60)


def decode(frames):
    s1 = s2 = 0
    pcm = []
    for fr in frames:
        shift = fr[0] & 0x0F
        filt = min(fr[0] >> 4, 4)
        for byte in fr[2:16]:
            for nib in (byte & 0x0F, byte >> 4):
                n = nib - 16 if nib >= 8 else nib
                v = (n << 12) >> shift if shift <= 12 else 0
                v += (s1 * F0[filt] + s2 * F1[filt] + 32) >> 6
                v = max(-32768, min(32767, v))
                pcm.append(v)
                s2, s1 = s1, v
    return pcm


def split(bank):
    frames = [bank[i:i + 16] for i in range(0, len(bank) - 15, 16)]
    samples, cur, start = [], [], 0
    for idx, fr in enumerate(frames):
        if not cur:
            if fr == b"\0" * 16:
                continue
            start = idx * 16
        cur.append(fr)
        if fr[1] & 1:
            samples.append((start, cur))
            cur = []
    if cur:
        samples.append((start, cur))
    return samples


def main():
    bank = Path(sys.argv[1]).read_bytes()
    out = Path(sys.argv[2])
    rate = int(sys.argv[3]) if len(sys.argv) > 3 else 48000
    out.mkdir(parents=True, exist_ok=True)
    for n, (off, frames) in enumerate(split(bank)):
        pcm = decode(frames)
        name = out / f"{n:02d}_off{off:06x}.wav"
        with wave.open(str(name), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
        loop = any(f[1] & 4 for f in frames)
        print(f"{name.name}  {len(pcm)/rate:6.3f}s @{rate}  frames={len(frames)}{'  loops' if loop else ''}")


main()
