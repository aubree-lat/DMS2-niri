"""Render PS2 BIOS sounds the way the SPU2 would play them.

  ps2snd.py osd  HEADER.raw BANK.raw OUTDIR          one WAV per OSD voice preset
  ps2snd.py seq  HEADER.raw BANK.raw SEQ.raw OUT.wav  render an SSsq sequence
  ps2snd.py boot HEADER.raw BANK.raw SEQ.raw OUT.wav  boot jingle (sequence + noise rush)

HEADER/BANK/SEQ are the decompressed SNDxxxxH / SNDxxxxB / SNDxxxxS files
(tools/osdlz.py). Formats, as worked out from the SCPH-77001 BIOS:

- OSD header (SShd, OSD flavour): u32 count at 0x84, presets of 0x40 bytes from
  0xA0, each starting with SPU2 voice registers: VOLL, VOLR, PITCH, (detune),
  ADSR1, ADSR2, ?, flags, SSA (byte address in the bank).
- Program header (SShd, VAB-like): u16 program offsets (relative to 0x80) at
  0x82 + 2*program; a program is 8 bytes (tone count - 1 in the low 7 bits of
  byte 0, volume, pan) followed by 16-byte tones: ?, ?, centre note (plays at
  pitch 0x1000), fine (signed, 1/128 semitone), SSA/8 (u16), ADSR1, ADSR2, ?,
  volume, pan, min note, max note, flags.
- SSsq: resolution (u16 at 2), then 16 channel records of 16 bytes from 0x10,
  then a MIDI event stream from 0x110 (delta-time first, running status,
  FF 51 tempo with a 2-byte BPM, FF 2F end).
- Bank: SPU2 ADPCM. Pitch 0x1000 plays at 44.1 kHz (fitted against a PCSX2
  recording of the menu); the samples sit at pitch 0x0800, i.e. 22.05 kHz.
"""
import math
import struct
import sys
import wave
from pathlib import Path

import numpy as np

BOOT_WHOOSH = 0.15  # rush level relative to the jingle's RMS (fitted)
BOOT_WHOOSH_START = 4.5  # seconds after the first note (fitted)
OUT_RATE = 44100  # the BIOS treats pitch 0x1000 as 44.1 kHz (fitted against PCSX2)
SAMPLE_RATE = 22050  # pitch 0x0800, the OSD presets' "natural" pitch
F0 = (0, 60, 115, 98, 122)
F1 = (0, 0, -52, -55, -60)


# ---------------------------------------------------------------- ADPCM bank
class Bank:
    def __init__(self, data):
        n = len(data) // 16
        self.flags = np.zeros(n, dtype=np.uint8)
        self.pcm = np.zeros(n * 28, dtype=np.float32)
        s1 = s2 = 0
        for k in range(n):
            fr = data[k * 16:(k + 1) * 16]
            self.flags[k] = fr[1]
            shift = fr[0] & 0x0F
            filt = min(fr[0] >> 4, 4)
            if fr[1] & 4:  # a sample starts here: no history carried in
                s1 = s2 = 0
            i = k * 28
            for byte in fr[2:]:
                for nib in (byte & 0x0F, byte >> 4):
                    v = nib - 16 if nib >= 8 else nib
                    v = (v << 12) >> shift if shift <= 12 else 0
                    v += (s1 * F0[filt] + s2 * F1[filt] + 32) >> 6
                    v = max(-32768, min(32767, v))
                    self.pcm[i] = v / 32768.0
                    i += 1
                    s2, s1 = s1, v
            if fr[1] & 1 and not fr[1] & 2:
                s1 = s2 = 0


# ---------------------------------------------------------------- envelope
class Envelope:
    """SPU2 ADSR, stepped once per 48 kHz output sample."""

    def __init__(self, adsr1, adsr2):
        self.a1, self.a2 = adsr1, adsr2
        self.level = 0
        self.phase = "attack"
        self.counter = 0

    def _params(self):
        a1, a2 = self.a1, self.a2
        if self.phase == "attack":
            return bool(a1 >> 15), (a1 >> 10) & 0x1F, 7 - ((a1 >> 8) & 3), False
        if self.phase == "decay":
            return True, (a1 >> 4) & 0x0F, -8, True
        if self.phase == "sustain":
            dec = bool((a2 >> 14) & 1)
            s = (a2 >> 6) & 3
            return bool(a2 >> 15), (a2 >> 8) & 0x1F, (-8 + s) if dec else (7 - s), dec
        return bool((a2 >> 5) & 1), a2 & 0x1F, -8, True  # release

    def key_off(self):
        self.phase = "release"

    def tick(self):
        if self.phase == "off":
            return 0.0
        exp, shift, step, dec = self._params()
        cycles = 1 << max(0, shift - 11)
        stepv = step << max(0, 11 - shift)
        if exp and not dec and self.level > 0x6000:
            cycles *= 4
        if exp and dec:
            stepv = (stepv * self.level) >> 15
        self.counter += 1
        if self.counter >= cycles:
            self.counter = 0
            self.level = max(0, min(0x7FFF, self.level + stepv))
        if self.phase == "attack" and self.level >= 0x7FFF:
            self.phase = "decay"
        elif self.phase == "decay" and self.level <= ((self.a1 & 0x0F) + 1) * 0x800:
            self.phase = "sustain"
        elif self.phase == "release" and self.level <= 0:
            self.phase = "off"
        return self.level / 0x7FFF


# ---------------------------------------------------------------- voice
class Voice:
    def __init__(self, bank, ssa_bytes, step, adsr1, adsr2, vol_l, vol_r):
        self.bank = bank
        self.frame = ssa_bytes // 16
        self.loop = self.frame
        self.pos = self.frame * 28.0
        self.step = step
        self.env = Envelope(adsr1, adsr2)
        self.vl, self.vr = vol_l, vol_r
        self.done = False
        if bank.flags[self.frame] & 4:
            self.loop = self.frame

    def render(self, n):
        out = np.zeros((n, 2), dtype=np.float32)
        b = self.bank
        for i in range(n):
            if self.done:
                break
            e = self.env.tick()
            if self.env.phase == "off":
                self.done = True
                break
            ip = int(self.pos)
            frac = self.pos - ip
            s = b.pcm[ip] * (1 - frac) + b.pcm[min(ip + 1, len(b.pcm) - 1)] * frac
            out[i, 0] = s * e * self.vl
            out[i, 1] = s * e * self.vr
            self.pos += self.step
            nf = int(self.pos) // 28
            while nf != self.frame:
                fl = b.flags[self.frame]
                if fl & 1:  # end of the block we're leaving
                    if fl & 2:
                        nf = self.loop
                        self.pos = self.loop * 28 + (self.pos - int(self.pos))
                    else:
                        self.done = True
                        break
                self.frame = nf if fl & 1 else self.frame + 1
                if b.flags[self.frame] & 4:
                    self.loop = self.frame
                if fl & 1:
                    break
        return out


def spu_volume(v):
    """SPU2 fixed volume register: 15-bit signed 'volume/2' (-0x4000..0x3FFF)."""
    if v & 0x8000:  # sweep mode: treat as its target magnitude
        return 0.5
    v &= 0x7FFF
    if v & 0x4000:
        v -= 0x8000
    return v / 0x4000


# ---------------------------------------------------------------- reverb
def reverb(x, wet=0.28, room=0.84, damp=0.3):
    """Small Freeverb-style hall, standing in for the SPU2's reverb unit."""
    from scipy.signal import lfilter
    combs = (1557, 1617, 1491, 1422, 1277, 1356, 1188, 1116)
    allps = (225, 556, 441, 341)
    out = np.zeros_like(x)
    for ch in range(2):
        sig = x[:, ch].astype(np.float64) * 0.015
        spread = 23 * ch
        acc = np.zeros(len(sig))
        for d in combs:
            d = int((d + spread) * OUT_RATE / 44100)
            # Lowpass-feedback comb: z^-d (1 - damp z^-1) / (1 - damp z^-1 - room (1-damp) z^-d)
            b = np.zeros(d + 2)
            b[d] = 1.0
            b[d + 1] = -damp
            a = np.zeros(d + 1)
            a[0] = 1.0
            a[1] = -damp
            a[d] += -room * (1 - damp)
            acc += lfilter(b, a, sig)
        for d in allps:
            d = int((d + spread) * OUT_RATE / 44100)
            b = np.zeros(d + 1)
            b[0] = -1.0
            b[d] = 1.0
            a = np.zeros(d + 1)
            a[0] = 1.0
            a[d] = -0.5
            acc = lfilter(b, a, acc)
        out[:, ch] = x[:, ch] * (1 - wet * 0.5) + acc.astype(np.float32) * wet
    return out


def boot_whoosh(total, gain=1.0, seed=2, start=None):
    """The broadband rush at 4 s into the boot jingle.

    RECONSTRUCTED, not decoded: it comes from the SPU2 noise generator, switched
    on by OSDSYS code rather than by anything in the sound bank. Shape fitted to
    a PCSX2 recording: rises 3.9 s -> 4.55 s, fades ~linearly to silence at 8.1 s,
    energy from ~2 kHz up, equal in both channels.
    """
    rng = np.random.default_rng(seed)
    n = int(4.4 * OUT_RATE)
    noise = rng.standard_normal((n, 2)).astype(np.float32)
    spec = np.fft.rfft(noise, axis=0)
    f = np.fft.rfftfreq(n, 1 / OUT_RATE)
    shape = np.interp(f, [0, 1000, 1900, 3000, 4500, 7000, 10500, 16000, 22050],
                      [0.0, 0.05, 0.35, 0.8, 1.0, 0.75, 0.45, 0.22, 0.1])
    noise = np.fft.irfft(spec * shape[:, None], n=n, axis=0).astype(np.float32)
    noise /= float(np.sqrt((noise ** 2).mean())) + 1e-9
    start = BOOT_WHOOSH_START if start is None else start
    t = np.arange(n) / OUT_RATE
    env = np.where(t < 0.65, t / 0.65, np.clip((4.2 - t) / (4.2 - 0.65), 0, 1)).astype(np.float32)
    out = np.zeros((total, 2), dtype=np.float32)
    o = int(start * OUT_RATE)
    m = min(n, total - o)
    if m > 0:
        out[o:o + m] = noise[:m] * env[:m, None] * gain
    return out


def write_wav(path, stereo):
    peak = float(np.max(np.abs(stereo))) or 1.0
    stereo = stereo * (0.89 / peak)  # normalise to about -1 dBFS
    data = (np.clip(stereo, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(OUT_RATE)
        w.writeframes(data.tobytes())


def trim_tail(x, floor=1e-4):
    nz = np.where(np.max(np.abs(x), axis=1) > floor)[0]
    return x[: (nz[-1] + 1 if len(nz) else 1)]


# ---------------------------------------------------------------- OSD presets
def osd_presets(h):
    count = struct.unpack_from("<I", h, 0x84)[0]
    out = []
    for i in range(count):
        w = struct.unpack_from("<10H", h, 0xA0 + i * 0x40)
        out.append({
            "vol_l": spu_volume(w[0]), "vol_r": spu_volume(w[1]), "pitch": w[2],
            "adsr1": w[4], "adsr2": w[5], "ssa": w[8] | (w[9] << 16),
        })
    return out


def render_osd(h, bank, outdir, hold=0.25, wet=0.22):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    for i, p in enumerate(osd_presets(h)):
        v = Voice(bank, p["ssa"], p["pitch"] / 0x1000, p["adsr1"], p["adsr2"], p["vol_l"], p["vol_r"])
        a = v.render(int(hold * OUT_RATE))
        v.env.key_off()
        b = v.render(int(4.0 * OUT_RATE))
        x = trim_tail(np.vstack([a, b]))
        x = np.vstack([x, np.zeros((int(0.8 * OUT_RATE), 2), np.float32)])
        x = trim_tail(reverb(x, wet=wet), 3e-4)
        write_wav(outdir / f"osd-{i:02d}.wav", x)
        print(f"osd-{i:02d}.wav  {len(x)/OUT_RATE:5.2f}s  pitch {p['pitch']:#06x}  ssa {p['ssa']:#07x}  adsr {p['adsr1']:#06x}/{p['adsr2']:#06x}")


# ---------------------------------------------------------------- programs + sequence
def programs(h):
    progs = {}
    for prog in range(128):
        off = struct.unpack_from("<H", h, 0x82 + prog * 2)[0]
        if off == 0xFFFF:
            continue
        base = 0x80 + off
        if base + 8 > len(h):
            continue
        hdr = h[base:base + 8]
        tones = []
        p = base + 8
        for _ in range((hdr[0] & 0x7F) + 1):
            if p + 16 > len(h):
                break
            t = h[p:p + 16]
            fine = t[3] - 256 if t[3] >= 128 else t[3]
            tones.append({
                "center": t[2], "fine": fine,
                "ssa": struct.unpack_from("<H", t, 4)[0] * 8,
                "adsr1": struct.unpack_from("<H", t, 6)[0],
                "adsr2": struct.unpack_from("<H", t, 8)[0],
                "vol": t[11], "pan": t[12], "min": t[13], "max": t[14],
            })
            p += 16
        progs[prog] = {"vol": hdr[1], "pan": hdr[2], "tones": tones}
    return progs


def parse_seq(s):
    res = struct.unpack_from("<H", s, 2)[0]
    chans = {}
    for c in range(16):
        r = s[0x10 + c * 16: 0x20 + c * 16]
        chans[r[1]] = {"prog": r[2], "vol": r[3], "pan": r[4]}
    events, p, tick, status, bpm = [], 0x110, 0, None, 120
    first = True
    while p < len(s):
        delta = 0
        if not first:
            while True:
                b = s[p]
                p += 1
                delta = (delta << 7) | (b & 0x7F)
                if not b & 0x80:
                    break
        first = False
        tick += delta
        b = s[p]
        if b == 0xFF:
            kind = s[p + 1]
            if kind == 0x51:
                bpm = s[p + 2] | (s[p + 3] << 8)
                events.append((tick, "tempo", bpm))
                p += 4
                continue
            if kind == 0x2F:
                events.append((tick, "end"))
                break
            p += 2
            continue
        if b & 0x80:
            status = b
            p += 1
        hi, ch = status & 0xF0, status & 0x0F
        if hi in (0x80, 0x90, 0xB0, 0xE0, 0xA0):
            d1, d2 = s[p], s[p + 1]
            p += 2
            if hi == 0x90 and d2 > 0:
                events.append((tick, "on", ch, d1, d2))
            elif hi in (0x80, 0x90):
                events.append((tick, "off", ch, d1))
            elif hi == 0xB0:
                events.append((tick, "cc", ch, d1, d2))
        elif hi in (0xC0, 0xD0):
            if hi == 0xC0:
                events.append((tick, "prog", ch, s[p]))
            p += 1
        else:
            raise ValueError(f"unknown status {status:#x} at {p:#x}")
    return res, chans, events


def pan_gains(pan):
    a = (pan / 127.0) * math.pi / 2
    return math.cos(a) * math.sqrt(2) * 0.75, math.sin(a) * math.sqrt(2) * 0.75


def events_offset(events, ticks_per_sec):
    """Seconds from the start of the render to the first note."""
    first = next((e[0] for e in events if e[1] == "on"), 0)
    return first / ticks_per_sec


def render_seq(h, bank, s, out, wet=0.35, whoosh=0.0):
    progs = programs(h)
    res, chans, events = parse_seq(s)
    state = {c: dict(v) for c, v in chans.items()}
    bpm = next((e[2] for e in events if e[1] == "tempo"), 120)
    ticks_per_sec = res * bpm / 60.0
    end_tick = max(e[0] for e in events)
    total = int((end_tick / ticks_per_sec + 4.0) * OUT_RATE)
    mix = np.zeros((total, 2), dtype=np.float32)
    active = []  # (start_sample, voice, ch, note)
    voices = []  # (start, voice, ch, note, off_sample)
    for e in events:
        t = int(e[0] / ticks_per_sec * OUT_RATE)
        kind = e[1]
        if kind == "prog":
            state.setdefault(e[2], {"vol": 100, "pan": 64})["prog"] = e[3]
        elif kind == "cc":
            st = state.setdefault(e[2], {"vol": 100, "pan": 64, "prog": 0})
            if e[3] == 7:
                st["vol"] = e[4]
            elif e[3] == 10:
                st["pan"] = e[4]
        elif kind == "on":
            ch, note, vel = e[2], e[3], e[4]
            st = state.get(ch, {"vol": 100, "pan": 64, "prog": 0})
            prog = progs.get(st.get("prog", 0))
            if not prog:
                continue
            for tone in prog["tones"]:
                if not tone["min"] <= note <= tone["max"]:
                    continue
                semis = note - tone["center"] + tone["fine"] / 128.0
                # A tone at its centre note plays at pitch 0x1000 (checked against PCSX2).
                step = 2 ** (semis / 12.0)
                amp = (vel / 127) * (st["vol"] / 127) * (prog["vol"] / 127) * (tone["vol"] / 127)
                pan = max(0, min(127, tone["pan"] + (st["pan"] - 64) + (prog["pan"] - 64)))
                gl, gr = pan_gains(pan)
                v = Voice(bank, tone["ssa"], step, tone["adsr1"], tone["adsr2"], amp * gl, amp * gr)
                voices.append([t, v, ch, note, None])
        elif kind == "off":
            for vv in voices:
                if vv[2] == e[2] and vv[3] == e[3] and vv[4] is None:
                    vv[4] = t
    for start, v, ch, note, off in voices:
        hold = (off if off is not None else total) - start
        a = v.render(max(0, min(hold, total - start)))
        v.env.key_off()
        rest = total - start - len(a)
        b = v.render(max(0, min(rest, int(6 * OUT_RATE))))
        seg = np.vstack([a, b])
        mix[start:start + len(seg)] += seg
    if whoosh:
        lead = int(events_offset(events, ticks_per_sec) * OUT_RATE)
        rms = float(np.sqrt((mix ** 2).mean())) or 1.0
        w = boot_whoosh(total - lead, gain=whoosh * rms)
        mix[lead:lead + len(w)] += w
    mix = trim_tail(mix)
    mix = np.vstack([mix, np.zeros((int(1.5 * OUT_RATE), 2), np.float32)])
    mix = trim_tail(reverb(mix, wet=wet), 3e-4)
    write_wav(out, mix)
    notes = sum(1 for e in events if e[1] == "on")
    print(f"{Path(out).name}: {len(mix)/OUT_RATE:.2f}s, {notes} notes, {len(voices)} voices, bpm {bpm}, res {res}")


def main():
    mode = sys.argv[1]
    h = Path(sys.argv[2]).read_bytes()
    bank = Bank(Path(sys.argv[3]).read_bytes())
    if mode == "osd":
        render_osd(h, bank, sys.argv[4])
    elif mode == "seq":
        render_seq(h, bank, Path(sys.argv[4]).read_bytes(), sys.argv[5])
    elif mode == "boot":
        # The boot jingle: SNDBOOTS plus the reconstructed noise rush.
        render_seq(h, bank, Path(sys.argv[4]).read_bytes(), sys.argv[5],
                   whoosh=float(sys.argv[6]) if len(sys.argv) > 6 else BOOT_WHOOSH)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
