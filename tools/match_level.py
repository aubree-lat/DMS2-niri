"""Scale SRC so its peak matches REF's, write OUT (16-bit WAV, SRC's format).

  match_level.py SRC REF OUT
"""
import sys
import wave

import numpy as np


def read(p):
    with wave.open(p) as w:
        return w.getparams(), np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float32)


sp, s = read(sys.argv[1])
_, r = read(sys.argv[2])
g = (np.max(np.abs(r)) or 1.0) / (np.max(np.abs(s)) or 1.0)
with wave.open(sys.argv[3], "wb") as w:
    w.setparams(sp)
    w.writeframes(np.clip(s * g, -32768, 32767).astype("<i2").tobytes())
print(f"{sys.argv[3]}: gain {g:.3f}")
