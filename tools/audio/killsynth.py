"""Kill banner sound synthesizer for Squishy Duels (Valorant-style escalating kill sounds).

Renders one audio sprite per kill set: 6 tiers, each in its own SLOT-second slot (tier n starts at (n-1)*SLOT).
Every tier = a punchy hit + a rising musical sting in the set's own instrument; tier 6 is the big flourish
(the 6k sound, repeated for every kill past 6). Original synthesis only (no samples).

usage: python -I killsynth.py <outdir>   (needs numpy and scipy)
Then encode each WAV to OGG (ffmpeg -i in.wav -c:a libvorbis -q:a 6 out.ogg) and upload it with upload.py; the
AssetTable sfx.kill.<set> slots hold the ids (the only place for asset ids), Config.Audio.killBanner the slot layout
(3 s slots, 6 tiers). The bubble_pop sheet here is the Cupcake Axolotl's bubble_burst set.
"""

import os
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter, sosfilt

SR = 44100
SLOT = 3.0
TIERS = 6
RNG = np.random.default_rng(20261016)


# ---------------------------------------------------------------- helpers


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def place(buf, sig, at):
    i = int(at * SR)
    n = min(len(sig), len(buf) - i)
    if n > 0:
        buf[i : i + n] += sig[:n]


def osc(freq, dur, shape="sine", phase=0.0):
    """freq: float or array (Hz per sample)."""
    n = int(dur * SR)
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq)[:n]
    ph = phase + 2 * np.pi * np.cumsum(f) / SR
    if shape == "sine":
        return np.sin(ph)
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if shape == "saw":
        # band-limited (additive up to 0.45 x the sample rate): no aliasing on the brass and the growl
        top = max(int(0.45 * SR / max(float(np.max(f)), 1.0)), 1)
        out = np.zeros(n)
        for k in range(1, top + 1):
            out += np.sin(k * ph) / k
        return -2 / np.pi * out
    if shape == "square":
        return np.sign(np.sin(ph))
    raise ValueError(shape)


def expdec(dur, tau, attack=0.002):
    t = t_axis(dur)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / tau)


def adsr(dur, a, d, s, r):
    t = t_axis(dur)
    e = np.where(t < a, t / max(a, 1e-4), 1.0)
    e = np.where((t >= a) & (t < a + d), 1 - (1 - s) * (t - a) / max(d, 1e-4), e)
    e = np.where((t >= a + d) & (t < dur - r), s, e)
    e = np.where(t >= dur - r, s * np.clip((dur - t) / max(r, 1e-4), 0, 1), e)
    return e


def noise(dur):
    return RNG.standard_normal(int(dur * SR))


def bp(x, lo, hi, order=2):
    sos = butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], btype="band", output="sos")
    return sosfilt(sos, x)


def lp(x, f, order=2):
    sos = butter(order, min(f / (SR / 2), 0.99), btype="low", output="sos")
    return sosfilt(sos, x)


def hp(x, f, order=2):
    sos = butter(order, f / (SR / 2), btype="high", output="sos")
    return sosfilt(sos, x)


def sweep_bp(x, f0, f1, q=2.0, steps=48):
    """Band-pass whose centre glides f0 -> f1 (exponential), processed in blocks."""
    n = len(x)
    out = np.zeros(n)
    edges = np.linspace(0, n, steps + 1).astype(int)
    for k in range(steps):
        a, b = edges[k], edges[k + 1]
        u = (k + 0.5) / steps
        fc = f0 * (f1 / f0) ** u
        lo, hi = fc / (1 + 1 / q), fc * (1 + 1 / q)
        pad = min(a, 2048)
        seg = bp(x[a - pad : b], max(lo, 30), min(hi, SR / 2 * 0.95))
        out[a:b] = seg[pad:]
    return out


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def pan(sig, p):
    """p in [-1, 1] -> stereo (constant power)."""
    a = (p + 1) * np.pi / 4
    return np.stack([sig * np.cos(a), sig * np.sin(a)], axis=1)


def reverb_ir(seconds=1.4, damp=4500, seed=1):
    r = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 6.9 / seconds)
    left = lp(r.standard_normal(n) * env, damp)
    right = lp(r.standard_normal(n) * env, damp)
    # pre-delay 18 ms, no direct sound
    pre = int(0.018 * SR)
    left[:pre] = 0
    right[:pre] = 0
    norm = np.sqrt(np.sum(left**2))
    return np.stack([left, right], axis=1) / norm


IR = reverb_ir()


def add_reverb(st, wet=0.22, ir=IR):
    from scipy.signal import fftconvolve

    out = np.zeros((len(st) + len(ir) - 1, 2))
    send_l, send_r = hp(st[:, 0], 280), hp(st[:, 1], 280)  # no bass into the tail: the hit stays tight
    out[:, 0] = fftconvolve(send_l, ir[:, 0])
    out[:, 1] = fftconvolve(send_r, ir[:, 1])
    dry = np.zeros_like(out)
    dry[: len(st)] = st
    return dry + wet * out * 2.2


def finish(st, dur, rms_db=-17.0, peak_db=-1.0, fade=0.25):
    st = st[: int(dur * SR)]
    if len(st) < int(dur * SR):
        st = np.vstack([st, np.zeros((int(dur * SR) - len(st), 2))])
    n = int(fade * SR)
    st[-n:] *= np.linspace(1, 0, n)[:, None] ** 2
    # loudness: the first 0.8 s (the hit and the sting) at rms_db, then a soft limiter under peak_db
    head = st[: int(0.8 * SR)]
    rms = np.sqrt(np.mean(head**2)) + 1e-9
    st = st * 10 ** (rms_db / 20) / rms
    ceiling = 10 ** (peak_db / 20)
    st = ceiling * np.tanh(st / ceiling)
    return st


# ---------------------------------------------------------------- shared voices


def thump(level=1.0, f0=150, f1=42, dur=0.32):
    t = t_axis(dur)
    f = f1 + (f0 - f1) * np.exp(-t / 0.045)
    body = osc(f, dur) * expdec(dur, 0.07, 0.001)
    click = bp(noise(0.012), 1800, 5200) * np.linspace(1, 0, int(0.012 * SR)) * 0.5
    sig = body
    sig[: len(click)] += click
    return sig * level


def mallet(freq, dur=0.9, bright=1.0):
    """Marimba / glockenspiel-like: fundamental + inharmonic partials with fast decay."""
    s = osc(freq, dur) * expdec(dur, 0.42, 0.002)
    s += 0.45 * bright * osc(freq * 2.76, dur) * expdec(dur, 0.12, 0.001)
    s += 0.22 * bright * osc(freq * 5.40, dur) * expdec(dur, 0.05, 0.001)
    s += 0.30 * osc(freq * 2.0, dur) * expdec(dur, 0.25, 0.002)
    return s * 0.6


def bell(freq, dur=1.6):
    parts = [(1.0, 1.0, 0.9), (2.0, 0.5, 0.6), (2.76, 0.35, 0.35), (5.4, 0.2, 0.18), (8.93, 0.1, 0.1)]
    s = np.zeros(int(dur * SR))
    for ratio, amp, tau in parts:
        s += amp * osc(freq * ratio, dur) * expdec(dur, tau, 0.001)
    return s * 0.45


def pop(f0=300, f1=1100, dur=0.08):
    t = t_axis(dur)
    f = f0 * (f1 / f0) ** (t / dur)
    return osc(f, dur) * expdec(dur, 0.03, 0.001) * 0.8


def sparkle_shower(dur, count, lo=2200, hi=5200, seed=0):
    r = np.random.default_rng(seed)
    out = np.zeros((int(dur * SR) + SR, 2))
    for _ in range(count):
        f = r.uniform(lo, hi)
        at = r.uniform(0, dur * 0.7)
        s = osc(f, 0.35) * expdec(0.35, 0.07, 0.001) * r.uniform(0.08, 0.2)
        place(out, pan(s, r.uniform(-0.8, 0.8)), at)
    return out


def whoosh(dur, f0, f1, level=0.5, q=1.5):
    x = noise(dur)
    x = sweep_bp(x, f0, f1, q)
    env = np.sin(np.linspace(0, np.pi, len(x))) ** 1.5
    return x * env * level


def stereo(sig, p=0.0):
    return pan(sig, p)


def arpeggio(notes, step, voice, spread=0.5, **kw):
    """notes: midi numbers; returns a stereo buffer."""
    total = step * (len(notes) - 1) + 2.5
    out = np.zeros((int(total * SR), 2))
    for i, m in enumerate(notes):
        p = 0 if len(notes) == 1 else -spread + 2 * spread * i / (len(notes) - 1)
        place(out, pan(voice(midi(m), **kw), p), i * step)
    return out


# ---------------------------------------------------------------- the sets
# Each tier function returns a stereo buffer; tier 6 is the flourish. The top note rises every tier.

PENTA = [0, 2, 4, 7, 9]  # major pentatonic degrees


def scale_notes(root, degrees, count, top_index):
    """`count` notes of the scale ending on scale step `top_index` (ascending)."""
    out = []
    for k in range(top_index - count + 1, top_index + 1):
        octave, deg = divmod(k, len(degrees))
        out.append(root + 12 * octave + degrees[deg])
    return out


def set_standard(tier):
    """Candy Pop (Common / Uncommon): a squishy pop, a punchy thump, a marimba-glock arpeggio climbing C major
    pentatonic; 6k = full climb, chord bell and a sparkle shower."""
    root = 72  # C5
    tops = [4, 5, 6, 7, 8, 10]  # pentatonic steps: G5 A5 C6 D6 E6 A6
    count = min(tier, 5) if tier < 6 else 7
    notes = scale_notes(root, PENTA, count, tops[tier - 1])
    buf = np.zeros((int(SLOT * SR), 2))
    place(buf, stereo(thump(0.75 + 0.05 * tier)), 0.0)
    place(buf, stereo(pop(260 + 40 * tier, 900 + 120 * tier)), 0.0)
    step = 0.055 if tier < 6 else 0.05
    arp = arpeggio(notes, step, mallet, spread=0.45, bright=1.0)
    place(buf, arp * 0.85, 0.02)
    if tier >= 3:
        place(buf, stereo(bell(midi(notes[-1] + 12), 1.2) * (0.15 + 0.05 * (tier - 3))), 0.02 + step * (len(notes) - 1))
    if tier >= 6:
        for m in (notes[-1], notes[-1] - 5, notes[-1] - 8):
            place(buf, stereo(bell(midi(m), 1.8) * 0.3, 0.0), 0.42)
        place(buf, sparkle_shower(1.0, 26, seed=6), 0.4)
        place(buf, stereo(thump(0.9, 120, 38, 0.45)), 0.42)
    return add_reverb(buf, 0.18)


def chirp(freq, dur=0.16, up=1.45, vib=0.0):
    t = t_axis(dur)
    glide = freq * (1 + (up - 1) * (1 - np.exp(-t / 0.035)))
    if vib:
        glide = glide * (1 + vib * np.sin(2 * np.pi * 28 * t))
    s = osc(glide, dur) * adsr(dur, 0.006, 0.04, 0.6, 0.08)
    breath = bp(noise(dur), freq * 1.5, min(freq * 4, 16000)) * expdec(dur, 0.03) * 0.15
    return (s + breath) * 0.55


def flutter(dur, rate=15, level=0.4, lo=700, hi=2600):
    x = bp(noise(dur), lo, hi)
    t = t_axis(dur)
    am = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rate * t))
    am = lp(am, 60)
    env = np.sin(np.linspace(0, np.pi, len(x))) ** 0.8
    return x * am * env * level


def set_feather(tier):
    """Feather Storm (Birdie): wing flutter + a whistled bird call climbing E major pentatonic; 6k = a flock of
    chirps, a big wing whoosh and a bright bell."""
    root = 76  # E5
    tops = [3, 4, 5, 6, 7, 9]
    count = min(tier, 5) if tier < 6 else 7
    notes = scale_notes(root, PENTA, count, tops[tier - 1])
    buf = np.zeros((int(SLOT * SR), 2))
    place(buf, stereo(thump(0.6, 170, 55, 0.25)), 0.0)
    place(buf, pan(flutter(0.35 + 0.05 * tier, level=0.35 + 0.04 * tier), -0.3), 0.0)
    place(buf, pan(flutter(0.3 + 0.05 * tier, rate=17, level=0.3), 0.3), 0.03)
    step = 0.07
    for i, m in enumerate(notes):
        p = -0.4 + 0.8 * i / max(len(notes) - 1, 1)
        place(buf, pan(chirp(midi(m), 0.15, 1.35, vib=0.01), p), 0.03 + i * step)
    # the call's answer: a falling-rising two-note on the top
    if tier >= 2:
        place(buf, stereo(chirp(midi(notes[-1] + 12), 0.22, 1.25, vib=0.02) * 0.5), 0.05 + len(notes) * step)
    if tier >= 6:
        r = np.random.default_rng(66)
        for _ in range(14):
            m = notes[r.integers(0, len(notes))] + 12 * r.integers(0, 2)
            place(buf, pan(chirp(midi(m), 0.12, r.uniform(1.2, 1.6)) * r.uniform(0.25, 0.5), r.uniform(-0.9, 0.9)),
                  0.45 + r.uniform(0, 0.6))
        place(buf, stereo(whoosh(0.9, 400, 3000, 0.45)), 0.3)
        place(buf, stereo(bell(midi(notes[-1]), 1.6) * 0.35), 0.48)
    return add_reverb(buf, 0.2)


def boing(freq, dur=0.5, depth=0.35, rate=11):
    t = t_axis(dur)
    f = freq * (1 + depth * np.exp(-t / 0.09) * np.sin(2 * np.pi * rate * t)) * (1 + 0.25 * np.exp(-t / 0.02))
    s = 0.7 * osc(f, dur, "tri") + 0.3 * osc(f * 2, dur) * 0.4
    return s * expdec(dur, 0.18, 0.002) * 0.7


def ping(freq, dur=0.25):
    return osc(freq, dur) * expdec(dur, 0.05, 0.0008) * 0.3


def set_sprinkle(tier):
    """Sprinkle Blast (Donut): a rubbery boing climbing F major, sprinkles tinkling down; 6k = a boing chord,
    a sprinkle rain and a glaze shimmer."""
    root = 65  # F4
    major = [0, 2, 4, 5, 7, 9, 11]
    tops = [4, 5, 6, 7, 9, 11]
    count = min(tier, 5) if tier < 6 else 6
    notes = scale_notes(root, major, count, tops[tier - 1])
    buf = np.zeros((int(SLOT * SR), 2))
    place(buf, stereo(thump(0.7, 140, 45, 0.3)), 0.0)
    step = 0.075
    for i, m in enumerate(notes):
        p = -0.35 + 0.7 * i / max(len(notes) - 1, 1)
        place(buf, pan(boing(midi(m), 0.5), p), 0.01 + i * step)
    r = np.random.default_rng(tier * 7)
    for _ in range(4 + 3 * tier):
        place(buf, pan(ping(r.uniform(3000, 7200)), r.uniform(-0.8, 0.8)), r.uniform(0.05, 0.25 + 0.08 * tier))
    if tier >= 6:
        for m in (notes[-1], notes[-1] - 4, notes[-1] - 7):
            place(buf, stereo(boing(midi(m), 0.9, depth=0.25, rate=8) * 0.6), 0.5)
        place(buf, sparkle_shower(1.1, 34, 3000, 7500, seed=9), 0.45)
        place(buf, stereo(thump(0.9, 110, 36, 0.45)), 0.5)
    return add_reverb(buf, 0.16)


def pluck(freq, dur=1.4, damp=0.996):
    """Karplus-Strong string (harp-like)."""
    n = int(dur * SR)
    period = max(int(SR / freq), 2)
    buf = RNG.uniform(-1, 1, period)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % period]
        nxt = (i + 1) % period
        buf[i % period] = damp * 0.5 * (buf[i % period] + buf[nxt])
    return lp(out, 6000) * 0.8


def thunder(dur, level=0.6, crack=False):
    x = lp(noise(dur), 260, 4)
    t = t_axis(dur)
    am = 0.6 + 0.4 * lp(np.abs(RNG.standard_normal(len(t))), 6) * 3
    env = (1 - np.exp(-t / 0.05)) * np.exp(-t / (dur * 0.45))
    s = x * am * env * level * 4
    if crack:
        c = hp(noise(0.25), 1200) * expdec(0.25, 0.04, 0.0005) * 0.9
        s[: len(c)] += c
    return s


def set_cloud(tier):
    """Cloudburst (Cloud Bunny): an airy wind swell and a harp climbing D Lydian, soft thunder from 4k;
    6k = thunder crack, harp glissando and rain plinks."""
    root = 62  # D4
    lydian = [0, 2, 4, 6, 7, 9, 11]
    tops = [6, 7, 8, 9, 11, 14]
    count = min(tier + 1, 6) if tier < 6 else 9
    notes = scale_notes(root, lydian, count, tops[tier - 1])
    buf = np.zeros((int(SLOT * SR), 2))
    place(buf, stereo(thump(0.55, 120, 40, 0.3)), 0.0)
    place(buf, stereo(whoosh(0.5 + 0.06 * tier, 300, 1800, 0.25 + 0.03 * tier, q=1.2)), 0.0)
    step = 0.06 if tier < 6 else 0.045
    for i, m in enumerate(notes):
        p = -0.5 + 1.0 * i / max(len(notes) - 1, 1)
        place(buf, pan(pluck(midi(m), 1.3), p) * 0.7, 0.02 + i * step)
    if tier >= 4:
        place(buf, stereo(thunder(1.4, 0.18 + 0.06 * (tier - 4))), 0.1)
    if tier >= 6:
        place(buf, stereo(thunder(1.8, 0.45, crack=True)), 0.0)
        r = np.random.default_rng(16)
        for _ in range(16):
            place(buf, pan(ping(r.uniform(1800, 4200), 0.2) * 0.8, r.uniform(-0.8, 0.8)), 0.5 + r.uniform(0, 0.9))
        place(buf, stereo(bell(midi(notes[-1]), 1.6) * 0.25), 0.55)
    return add_reverb(buf, 0.3)


def bubble(freq, dur=0.12, rise=1.6):
    t = t_axis(dur)
    f = freq * (1 + (rise - 1) * (1 - np.exp(-t / 0.025)))
    return osc(f, dur) * expdec(dur, 0.035, 0.001) * 0.6


def blub(freq=180, dur=0.2):
    t = t_axis(dur)
    f = freq * (1 + 1.2 * (t / dur))
    return osc(f, dur) * expdec(dur, 0.06, 0.003) * 0.6


def set_bubble(tier):
    """Bubble Pop (Cupcake Axolotl): tuned bubbles climbing G major pentatonic over a soft underwater blub;
    6k = a bubble cascade, a splash and a glassy chime."""
    root = 79  # G5
    tops = [3, 4, 5, 6, 7, 9]
    count = min(tier + 1, 6) if tier < 6 else 8
    notes = scale_notes(root, PENTA, count, tops[tier - 1])
    buf = np.zeros((int(SLOT * SR), 2))
    place(buf, stereo(thump(0.55, 130, 45, 0.28)), 0.0)
    place(buf, stereo(blub(160, 0.25)), 0.0)
    place(buf, stereo(lp(whoosh(0.4, 300, 900, 0.2), 1500)), 0.0)
    step = 0.05
    for i, m in enumerate(notes):
        p = -0.45 + 0.9 * i / max(len(notes) - 1, 1)
        place(buf, pan(bubble(midi(m) / 2, 0.14), p), 0.02 + i * step)
        place(buf, pan(mallet(midi(m), 0.6, 0.6) * 0.35, p), 0.02 + i * step)
    if tier >= 6:
        r = np.random.default_rng(26)
        for _ in range(30):
            place(buf, pan(bubble(r.uniform(500, 1800), 0.1) * r.uniform(0.3, 0.7), r.uniform(-0.9, 0.9)),
                  0.4 + r.uniform(0, 0.8))
        splash = hp(noise(0.5), 900) * expdec(0.5, 0.09, 0.004) * 0.35
        place(buf, stereo(splash), 0.38)
        place(buf, stereo(bell(midi(notes[-1]), 1.8) * 0.3), 0.42)
    return add_reverb(buf, 0.24)


def taiko(level=1.0, f0=95, dur=0.7):
    t = t_axis(dur)
    f = 52 + (f0 - 52) * np.exp(-t / 0.06)
    body = osc(f, dur) * expdec(dur, 0.22, 0.001)
    skin = bp(noise(dur), 120, 900) * expdec(dur, 0.05, 0.001) * 0.6
    return (body + skin) * level


def brass(freqs, dur=0.9, cutoff=2400, attack=0.04):
    s = np.zeros(int(dur * SR))
    for f in freqs:
        for det in (-0.006, 0.0, 0.006):
            s += osc(f * (1 + det), dur, "saw") * 0.25
    t = t_axis(dur)
    env = adsr(dur, attack, 0.15, 0.55, 0.35)
    # filter opens with the attack
    s = lp(s, cutoff) * env
    return s * 0.55 / max(len(freqs), 1) ** 0.5


def growl(dur, level=0.5, f=68):
    t = t_axis(dur)
    s = osc(f * (1 + 0.05 * np.sin(2 * np.pi * 3 * t)), dur, "saw")
    am = 0.55 + 0.45 * np.sin(2 * np.pi * 24 * t)
    s = s * am + 0.5 * noise(dur)
    s = bp(s, 180, 520) * 1.2 + bp(s, 700, 1300) * 0.6
    env = adsr(dur, 0.08, 0.2, 0.7, 0.35)
    return np.tanh(s * 2) * env * level


def gong(freq=110, dur=2.2):
    ratios = [1.0, 1.49, 2.06, 2.76, 3.52, 4.62]
    s = np.zeros(int(dur * SR))
    for i, r in enumerate(ratios):
        s += osc(freq * r * (1 + 0.003 * np.sin(2 * np.pi * 0.7 * t_axis(dur))), dur) * expdec(dur, 1.0 / (1 + 0.4 * i), 0.01) / (1 + i * 0.6)
    return s * 0.35


def set_dragon(tier):
    """Dragon's Blaze (Dragon, Exclusive): a taiko hit, a fire whoosh and a brass stab climbing D minor; a growl
    from 4k; 6k = roar, gong, full brass chord."""
    root = 50  # D3
    minor = [0, 2, 3, 5, 7, 8, 10]
    tops = [7, 9, 10, 11, 12, 14]  # D4 F4 G4 A4 Bb4 D5
    buf = np.zeros((int(SLOT * SR), 2))
    place(buf, stereo(taiko(0.95 + 0.02 * tier)), 0.0)
    if tier >= 3:
        place(buf, stereo(taiko(0.7, 120, 0.5)), 0.16)
    place(buf, stereo(whoosh(0.45 + 0.05 * tier, 250, 3500, 0.35 + 0.03 * tier)), 0.0)
    top = scale_notes(root, minor, 1, tops[tier - 1])[0]
    chord = [top, top - 7, top - 12] if tier < 5 else [top, top - 4, top - 7, top - 12]
    stab = brass([midi(m) for m in chord], 0.55 + 0.05 * tier, cutoff=1600 + 300 * tier)
    place(buf, stereo(stab), 0.05)
    # a little lead-in run for the higher tiers
    if tier >= 2:
        run = scale_notes(root + 12, minor, min(tier, 5), tops[tier - 1] - 7)
        for i, m in enumerate(run):
            place(buf, pan(brass([midi(m)], 0.18, 2800, 0.01) * 0.6, -0.3 + 0.6 * i / max(len(run) - 1, 1)),
                  0.0 + i * 0.045)
    if tier >= 4:
        place(buf, stereo(growl(0.7, 0.25 + 0.05 * (tier - 4))), 0.12)
    if tier >= 6:
        place(buf, stereo(growl(1.3, 0.45, 60)), 0.35)
        place(buf, stereo(gong(midi(38), 2.3)), 0.4)
        big = brass([midi(m) for m in (top, top - 3, top - 7, top - 12, top - 24)], 1.4, 3200, 0.06)
        place(buf, stereo(big) * 1.1, 0.42)
        place(buf, stereo(taiko(1.0, 85, 0.9)), 0.4)
        place(buf, stereo(whoosh(1.0, 200, 5000, 0.4)), 0.35)
    return add_reverb(buf, 0.22)


SETS = {
    "standard": set_standard,
    "feather_storm": set_feather,
    "sprinkle_blast": set_sprinkle,
    "cloudburst": set_cloud,
    "bubble_pop": set_bubble,
    "dragon_blaze": set_dragon,
}

# per-tier loudness (RMS of the first 0.8 s): a gentle rise, the 6k loudest
TIER_RMS_DB = [-18.0, -17.4, -16.8, -16.2, -15.6, -14.4]


def render(outdir):
    os.makedirs(outdir, exist_ok=True)
    for name, fn in SETS.items():
        sprite = np.zeros((int(SLOT * TIERS * SR), 2))
        for tier in range(1, TIERS + 1):
            sound = finish(fn(tier), SLOT - 0.05, TIER_RMS_DB[tier - 1], fade=0.3)
            place(sprite, sound, (tier - 1) * SLOT)
        pcm = np.clip(sprite * 32767, -32768, 32767).astype(np.int16)
        path = os.path.join(outdir, f"sfx_kill_{name}.wav")
        wavfile.write(path, SR, pcm)
        print(path, f"{len(pcm) / SR:.2f}s")


if __name__ == "__main__":
    render(sys.argv[1])
