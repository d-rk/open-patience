"""Synthesized sound effects — stdlib only, no external audio libraries.

Pure Python synthesis for game sounds that don't exist in the Kenney pack.
Used by build_sfx.py to render audio before processing through the standard
ffmpeg pipeline.
"""

import math
import struct
import wave


SR = 44100


def midi(n):
    """Convert MIDI note number to frequency in Hz."""
    return 440.0 * 2 ** ((n - 69) / 12)


def bell(buf, t0, freq, amp, decay=1.2, bright=1.0):
    """Celesta/glockenspiel-ish: a few inharmonic partials, soft attack."""
    partials = [(1.0, 1.0, 1.0), (2.0, 0.35 * bright, 1.8),
                (3.01, 0.18 * bright, 2.6), (4.2, 0.08 * bright, 3.5)]
    start = int(t0 * SR)
    length = int(min(decay * 4, 3.5) * SR)
    for i in range(length):
        idx = start + i
        if idx >= len(buf):
            break
        t = i / SR
        attack = min(1.0, t / 0.004)
        s = 0.0
        for mul, a, dk in partials:
            s += a * math.exp(-t * dk / decay) * math.sin(2 * math.pi * freq * mul * t)
        buf[idx] += amp * attack * s


def pluck(buf, t0, freq, amp, decay=0.9):
    """Harp-ish pluck: bright attack, fast upper-partial decay."""
    start = int(t0 * SR)
    length = int(decay * 3 * SR)
    for i in range(length):
        idx = start + i
        if idx >= len(buf):
            break
        t = i / SR
        attack = min(1.0, t / 0.002)
        s = (math.sin(2 * math.pi * freq * t) * math.exp(-t / decay)
             + 0.5 * math.sin(4 * math.pi * freq * t) * math.exp(-t * 3 / decay)
             + 0.25 * math.sin(6 * math.pi * freq * t) * math.exp(-t * 6 / decay))
        buf[idx] += amp * attack * s


def reverb(buf, mix=0.28):
    """Small Schroeder reverb: 4 combs + 2 allpasses."""
    out = [0.0] * len(buf)
    for d, g in ((1557, 0.80), (1617, 0.79), (1491, 0.78), (1422, 0.77)):
        c = [0.0] * len(buf)
        for i in range(len(buf)):
            c[i] = buf[i] + (g * c[i - d] if i >= d else 0.0)
            out[i] += c[i] * 0.25
    for d, g in ((225, 0.5), (556, 0.5)):
        a = [0.0] * len(out)
        for i in range(len(out)):
            x = out[i]
            y = -g * x + (out[i - d] if i >= d else 0.0) + (g * a[i - d] if i >= d else 0.0)
            a[i] = y
        out = a
    return [(1 - mix) * x + mix * y for x, y in zip(buf, out)]


def sparkles(buf, rng, t_from, t_to, count, lo, hi, amp):
    """Randomly placed bell sparkles in a pentatonic scale."""
    scale = [0, 2, 4, 7, 9]  # major pentatonic
    for _ in range(count):
        t = rng.uniform(t_from, t_to)
        octave = rng.randint(lo, hi)
        note = 12 * octave + rng.choice(scale)
        bell(buf, t, midi(note), amp * rng.uniform(0.5, 1.0), decay=0.35, bright=1.4)


def harp_glissando(seconds=1.7):
    """Upward harp glissando, landing on a bell chord — 1.7s celebratory flourish."""
    import random
    buf = [0.0] * int(seconds * SR)
    rng = random.Random(3)
    scale = [0, 2, 4, 7, 9]
    # Shorter, faster glissando to fit within release window
    notes = [60 + 12 * o + s for o in range(2) for s in scale][:11] + [91]
    for i, n in enumerate(notes):
        pluck(buf, 0.02 + i * 0.035, midi(n), 0.5, decay=0.7)
    land = 0.02 + len(notes) * 0.035
    # Shorter chord hold
    for n in (84, 88, 91):
        bell(buf, land, midi(n), 0.35, decay=1.2)
    # Fewer, brighter sparkles
    sparkles(buf, rng, land + 0.05, 1.4, 8, 8, 9, 0.12)
    return reverb(buf)


def write_wav(path, buf, fade_s=0.4):
    """Write buffer to WAV file with fade-out."""
    n = len(buf)
    f = int(fade_s * SR)
    for i in range(f):
        buf[n - f + i] *= 1 - i / f
    peak = max(abs(x) for x in buf) or 1.0
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(x / peak * 0.89 * 32767)) for x in buf))
