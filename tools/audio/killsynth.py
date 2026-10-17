"""Kill banner sound synthesizer for Squishy Duels, v2 (2026-10-17: punchier, Valorant-style).

Renders one audio sprite per kill set: 6 tiers, each in its own SLOT-second slot (tier n starts at (n-1)*SLOT).
Every tier = a punch (sub thump + click) + the set's own metallic FM "ting" that climbs a step per kill + a digital
zap + a short tight tail; from 3k sparkle pings, from 5k a chord stab, and the 6k is the big flourish (the sound of
every kill past the 6th). Heavily compressed and loud, like a shooter's kill sounds. Original synthesis only.

usage: python -I killsynth.py <outdir>   (needs numpy and scipy)
Then encode each WAV to OGG (ffmpeg -i in.wav -c:a libvorbis -q:a 6 out.ogg) and upload it with upload.py; the
AssetTable sfx.kill.<set> slots hold the ids (the only place for asset ids), Config.Audio.killBanner the slot layout
(3 s slots, 6 tiers).
"""

import os
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
SLOT = 3.0
TIERS = 6
RNG = np.random.default_rng(20261017)

# ---------------------------------------------------------------- basics


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def place(buf, sig, at):
    i = int(at * SR)
    if sig.ndim == 1:
        sig = np.stack([sig, sig], axis=1)
    n = min(len(sig), len(buf) - i)
    if n > 0:
        buf[i : i + n] += sig[:n]


def phase_of(freq, n):
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq)[:n]
    return 2 * np.pi * np.cumsum(f) / SR


def sine(freq, dur):
    return np.sin(phase_of(freq, int(dur * SR)))


def env(dur, attack, tau):
    t = t_axis(dur)
    return np.clip(t / max(attack, 1e-4), 0, 1) * np.exp(-t / tau)


def noise(dur):
    return RNG.standard_normal(int(dur * SR))


def filt(x, kind, f, order=2):
    if kind == "band":
        lo, hi = f
        sos = butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], btype="band", output="sos")
    else:
        sos = butter(order, min(f / (SR / 2), 0.99), btype=kind, output="sos")
    return sosfilt(sos, x)


def pan(sig, p):
    a = (p + 1) * np.pi / 4
    return np.stack([sig * np.cos(a), sig * np.sin(a)], axis=1)


def semis(f, n):
    return f * 2 ** (n / 12)


def fm(carrier, ratio, index, dur, tau=0.4, index_tau=0.12, attack=0.001, glide=None):
    """Two-operator FM: carrier freq (or array), modulator = carrier*ratio, decaying index -> metallic bells."""
    n = int(dur * SR)
    t = t_axis(dur)
    cf = np.full(n, float(carrier)) if glide is None else carrier * (1 + glide(t))
    mod_phase = phase_of(cf * ratio, n)
    idx = index * np.exp(-t / index_tau)
    car_phase = phase_of(cf, n) + idx * np.sin(mod_phase)
    return np.sin(car_phase) * env(dur, attack, tau)


def saw_bl(freq, dur):
    n = int(dur * SR)
    ph = phase_of(freq, n)
    top = max(int(0.45 * SR / float(freq)), 1)
    out = np.zeros(n)
    for k in range(1, top + 1):
        out += np.sin(k * ph) / k
    return out * (2 / np.pi)


# ---------------------------------------------------------------- shared layers


def punch(level=1.0, f0=120, f1=42, dur=0.35, drive=2.2):
    t = t_axis(dur)
    f = f1 + (f0 - f1) * np.exp(-t / 0.035)
    body = np.tanh(sine(f, dur) * drive) / np.tanh(drive)
    body *= env(dur, 0.0008, 0.085)
    click = filt(noise(0.01), "band", (2500, 9000)) * np.linspace(1, 0, int(0.01 * SR)) * 0.9
    body[: len(click)] += click
    return body * level


def zap(f0=300, f1=2600, dur=0.07, level=0.35):
    t = t_axis(dur)
    f = f0 * (f1 / f0) ** (t / dur)
    s = np.sin(phase_of(f, len(t))) + 0.4 * np.sin(phase_of(f * 2.01, len(t)))
    return s * env(dur, 0.0005, 0.03) * level


def whoosh(dur, f0, f1, level=0.4):
    x = noise(dur)
    n = len(x)
    out = np.zeros(n)
    steps = 40
    edges = np.linspace(0, n, steps + 1).astype(int)
    for k in range(steps):
        a, b = edges[k], edges[k + 1]
        fc = f0 * (f1 / f0) ** ((k + 0.5) / steps)
        pad = min(a, 2048)
        seg = filt(x[a - pad : b], "band", (max(fc / 1.6, 40), min(fc * 1.6, SR * 0.45)))
        out[a:b] = seg[pad:]
    return out * np.sin(np.linspace(0, np.pi, n)) ** 1.4 * level


def sparkle(count, lo, hi, spread=0.35, seed=1, level=0.18):
    r = np.random.default_rng(seed)
    out = np.zeros((int((spread + 0.6) * SR), 2))
    for i in range(count):
        f = r.uniform(lo, hi)
        s = fm(f, 3.01, 1.5, 0.35, tau=0.08, index_tau=0.05) * level * r.uniform(0.7, 1.0)
        place(out, pan(s, r.uniform(-0.9, 0.9)), i * spread / max(count, 1) + r.uniform(0, 0.02))
    return out


def tail(st, seconds=0.7, wet=0.28, hp=350):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(5)
    ir = np.stack([filt(r.standard_normal(n), "low", 7000), filt(r.standard_normal(n), "low", 7000)], axis=1)
    ir *= np.exp(-t * 6.9 / seconds)[:, None]
    ir[: int(0.012 * SR)] = 0
    ir /= np.sqrt((ir**2).sum(axis=0))[None, :]
    send = np.stack([filt(st[:, 0], "high", hp), filt(st[:, 1], "high", hp)], axis=1)
    wetsig = np.stack([fftconvolve(send[:, 0], ir[:, 0]), fftconvolve(send[:, 1], ir[:, 1])], axis=1)
    out = np.zeros_like(wetsig)
    out[: len(st)] = st
    return out + wet * wetsig * 2.5


def master(st, dur, rms_db, peak_db=-0.8):
    n = int(dur * SR)
    st = st[:n] if len(st) >= n else np.vstack([st, np.zeros((n - len(st), 2))])
    fade = int(0.25 * SR)
    st[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
    # glue compression: a smoothed RMS envelope pulls the loud start down, then make-up gain
    mono = np.abs(st).max(axis=1)
    envl = np.sqrt(filt(mono**2, "low", 18) .clip(0)) + 1e-6
    gain = np.minimum(1.0, (0.35 / envl) ** 0.45)
    st = st * gain[:, None]
    head = st[: int(0.45 * SR)]
    rms = np.sqrt(np.mean(head**2)) + 1e-9
    st = st * 10 ** (rms_db / 20) / rms
    ceiling = 10 ** (peak_db / 20)
    return ceiling * np.tanh(st / ceiling)


# Each tier climbs the set's scale: tier 1..6 -> these semitones over the set's root.
STEPS = [0, 2, 4, 7, 9, 12]


def tier_base(tier, root, ratio, index, tau, identity=None, zap_from=300, zap_to=2600, punch_f0=120):
    """The common skeleton: punch, the ting (the set's identity), a zap, sparkles from 3k, a stab from 5k."""
    buf = np.zeros((int(SLOT * SR), 2))
    lvl = 0.9 + 0.04 * tier
    place(buf, punch(lvl, punch_f0), 0.0)
    f = semis(root, STEPS[tier - 1])
    ting = fm(f, ratio, index, 0.9 + 0.08 * tier, tau=tau, index_tau=0.1)
    ting_hi = fm(f * 2, ratio, index * 0.6, 0.6, tau=tau * 0.6, index_tau=0.06) * 0.35
    place(buf, pan(ting * 0.62, -0.18), 0.004)
    place(buf, pan(ting_hi, 0.22), 0.012)
    place(buf, zap(zap_from, zap_to * (1 + 0.08 * tier)), 0.0)
    if identity is not None:
        identity(buf, tier, f)
    if tier >= 3:
        place(buf, sparkle(tier, f * 2, f * 4, 0.18 + 0.04 * tier, seed=tier), 0.06)
    if tier >= 5:
        for k, step in enumerate((0, 4, 7)):
            stab = fm(semis(f, step) / 2, ratio * 0.5, index * 0.8, 0.8, tau=0.35, index_tau=0.15) * 0.3
            place(buf, pan(stab, (k - 1) * 0.5), 0.02)
    if tier >= 6:
        # the 6k flourish: a climbing glissando, a second punch, a wide shimmer and a low drop
        for k in range(8):
            g = fm(semis(f, 12 + STEPS[k % 6] + 12 * (k // 6)), ratio, index * 0.7, 0.4, tau=0.15, index_tau=0.05)
            place(buf, pan(g * 0.32, -0.7 + 1.4 * k / 7), 0.18 + k * 0.045)
        place(buf, punch(1.0, 90, 35, 0.6, 2.6), 0.5)
        place(buf, sparkle(16, f * 3, f * 6, 0.9, seed=66, level=0.14), 0.5)
        place(buf, whoosh(0.7, 300, 6000, 0.25), 0.3)
    return buf


# ---------------------------------------------------------------- the sets (each adds its own identity layer)


def set_standard(tier):
    """Candy Pop: a glassy candy chime (FM 2:1) with a squishy pop."""

    def ident(buf, tier, f):
        t = t_axis(0.09)
        pf = 260 * (1 + 3.5 * (t / 0.09))
        pop = np.sin(phase_of(pf, len(t))) * env(0.09, 0.0005, 0.03) * 0.55
        place(buf, pop, 0.0)

    return tail(tier_base(tier, 880, 2.0, 2.2, 0.35, ident), 0.6, 0.22)


def set_feather(tier):
    """Feather Storm: a whistled chirp gliding up over a wing whoosh, a bright bell."""

    def ident(buf, tier, f):
        for k in range(1 + tier // 2):
            ff = semis(f, 12 + 2 * k)
            d = 0.16
            t = t_axis(d)
            glide = ff * (0.8 + 0.45 * (1 - np.exp(-t / 0.03))) * (1 + 0.012 * np.sin(2 * np.pi * 30 * t))
            w = np.sin(phase_of(glide, len(t))) * env(d, 0.004, 0.07) * 0.33
            place(buf, pan(w, -0.4 + 0.3 * k), 0.03 + 0.05 * k)
        place(buf, whoosh(0.35, 600, 3500, 0.22 + 0.02 * tier), 0.0)

    return tail(tier_base(tier, 1046, 3.5, 1.6, 0.3, ident, 500, 3400), 0.6, 0.25)


def set_sprinkle(tier):
    """Sprinkle Blast: a rubbery boing, crunchy sprinkle crackle, a candy ting."""

    def ident(buf, tier, f):
        d = 0.45
        t = t_axis(d)
        bf = (f / 2) * (1 + 0.32 * np.exp(-t / 0.09) * np.sin(2 * np.pi * 11 * t)) * (1 + 0.3 * np.exp(-t / 0.02))
        boing = np.sin(phase_of(bf, len(t))) * env(d, 0.002, 0.16) * 0.42
        place(buf, boing, 0.0)
        r = np.random.default_rng(tier)
        for _ in range(6 + 3 * tier):
            c = filt(noise(0.012), "band", (3500, 9000)) * np.linspace(1, 0, int(0.012 * SR)) * r.uniform(0.15, 0.35)
            place(buf, pan(c, r.uniform(-0.9, 0.9)), r.uniform(0.02, 0.3))

    return tail(tier_base(tier, 784, 2.76, 1.8, 0.32, ident, 400, 3000), 0.55, 0.22)


def set_cloud(tier):
    """Cloudburst: a thunder crack and rumble under an airy, shimmering pluck."""

    def ident(buf, tier, f):
        crack = filt(noise(0.18), "high", 1500) * env(0.18, 0.0005, 0.035) * 0.55
        place(buf, crack, 0.0)
        rumble = filt(noise(1.0 + 0.1 * tier), "low", 160, 4) * env(1.0 + 0.1 * tier, 0.03, 0.35) * (0.6 + 0.08 * tier)
        place(buf, rumble * 3.0, 0.02)
        for k in range(3):
            p = fm(semis(f, 7 * k), 1.0, 0.8, 0.7, tau=0.25, index_tau=0.08) * 0.22
            place(buf, pan(p, -0.5 + 0.5 * k), 0.05 + 0.04 * k)

    return tail(tier_base(tier, 740, 1.41, 1.4, 0.4, ident, 250, 2200), 0.8, 0.3)


def set_bubble(tier):
    """Bubble Burst: popping tuned bubbles and a water plip under a glassy ting."""

    def ident(buf, tier, f):
        for k in range(2 + tier):
            ff = semis(f / 2, STEPS[k % 6])
            d = 0.1
            t = t_axis(d)
            bf = ff * (1 + 1.4 * (1 - np.exp(-t / 0.018)))
            b = np.sin(phase_of(bf, len(t))) * env(d, 0.0008, 0.03) * 0.4
            place(buf, pan(b, -0.6 + 1.2 * k / max(1 + tier, 1)), 0.01 + 0.035 * k)
        plip = filt(noise(0.05), "band", (900, 2600)) * env(0.05, 0.001, 0.012) * 0.3
        place(buf, plip, 0.0)

    return tail(tier_base(tier, 932, 1.5, 1.2, 0.33, ident, 350, 2600), 0.6, 0.26)


def set_dragon(tier):
    """Dragon's Blaze: a taiko punch, a fire whoosh, a distorted brass stab and a growl from 4k."""

    def ident(buf, tier, f):
        brass = np.zeros(int(0.6 * SR))
        for st in (0, 7, 12):
            for det in (-0.006, 0.006):
                brass += saw_bl(semis(f / 4, st) * (1 + det), 0.6) * 0.2
        brass = np.tanh(filt(brass, "low", 2200 + 300 * tier) * 2.5) * env(0.6, 0.015, 0.22) * 0.5
        place(buf, brass, 0.0)
        place(buf, whoosh(0.4 + 0.05 * tier, 250, 4500, 0.32), 0.0)
        if tier >= 4:
            d = 0.55
            t = t_axis(d)
            g = saw_bl(62, d) * (0.55 + 0.45 * np.sin(2 * np.pi * 26 * t))
            g = np.tanh(filt(g + 0.4 * noise(d), "band", (150, 900)) * 3) * env(d, 0.05, 0.25) * 0.3
            place(buf, g, 0.06)

    return tail(tier_base(tier, 587, 1.33, 2.6, 0.3, ident, 200, 2000, punch_f0=95), 0.7, 0.24)


SETS = {
    "standard": set_standard,
    "feather_storm": set_feather,
    "sprinkle_blast": set_sprinkle,
    "cloudburst": set_cloud,
    "bubble_burst": set_bubble,
    "dragon_blaze": set_dragon,
}

# loudness (RMS of the first 0.45 s): a rise per kill, the 6k loudest
TIER_RMS_DB = [-15.0, -14.5, -14.0, -13.5, -13.0, -12.0]


def render(outdir):
    os.makedirs(outdir, exist_ok=True)
    for name, fn in SETS.items():
        sprite = np.zeros((int(SLOT * TIERS * SR), 2))
        for tier in range(1, TIERS + 1):
            sound = master(fn(tier), SLOT - 0.05, TIER_RMS_DB[tier - 1])
            place(sprite, sound, (tier - 1) * SLOT)
        pcm = np.clip(sprite * 32767, -32768, 32767).astype(np.int16)
        path = os.path.join(outdir, f"sfx_kill_{name}_v2.wav")
        wavfile.write(path, SR, pcm)
        print(path)


if __name__ == "__main__":
    render(sys.argv[1])
