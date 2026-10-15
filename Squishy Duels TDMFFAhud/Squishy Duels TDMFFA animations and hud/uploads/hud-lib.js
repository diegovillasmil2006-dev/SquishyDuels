/* Squishy Duels HUD — data, procedural SFX and animation helpers (window.SDHUD) */
(function () {
  if (window.SDHUD) return;
  const I = 'uploads/hud-icons/';
  const ICON = {
    coin: 'uploads/upgraded_v1/coin_currency.png', grip: I + 'grip.svg', gear: 'uploads/upgraded_v1/settings.png', lock: I + 'lock.svg', check: I + 'check.svg', clock: I + 'clock.svg',
    trophy: I + 'trophy.svg', star: I + 'star.svg', bolt: I + 'bolt.svg', gem: I + 'gem.svg', close: I + 'close.svg', sound: I + 'sound.svg',
    gift: I + 'gift.svg', flame: I + 'flame.svg', squeeze: I + 'squeeze.svg',
    squishies: 'uploads/squishies.png', boxes: 'uploads/boxes.png', shop: 'uploads/shop.png', quests: 'uploads/quests.png', daily: 'uploads/daily.png', duel: 'uploads/duel_emblem.png',
  };
  const BLANK = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
  const RAR = {
    Common: { c: '#8C9AA8', d: '#5F6C79', l: '#EEF2F6', pips: 1, cps: 1, idx: 0 },
    Uncommon: { c: '#3FBF84', d: '#23875A', l: '#D8F8E7', pips: 2, cps: 2, idx: 1 },
    Epic: { c: '#9A63E8', d: '#6638BD', l: '#EEE2FF', pips: 3, cps: 4, idx: 2 },
    Exclusive: { c: '#F0A532', d: '#B86C0C', l: '#FFF2CC', pips: 4, cps: 8, idx: 3 },
  };
  // stats: speed st/s, size studs, reload s, windup s, arc st/s² (placeholders except Kitty Bread, which matches the live UI)
  const TOYS = [
    { id: 'KittyBread', name: 'Kitty Bread', rarity: 'Common', st: [95, 1, 1, 0.18, 35], thr: 'Overhand fastball' },
    { id: 'Dragon', name: 'Dragon', rarity: 'Exclusive', st: [110, 1.4, 1.3, 0.3, 30], thr: 'Two-hand chest shove', ult: 'Dragon Burst' },
    { id: 'Birdie', name: 'Birdie', rarity: 'Epic', st: [75, 0.9, 1.1, 0.2, 22], thr: 'Two-hand launch, glides', ult: 'Flock Volley' },
    { id: 'CloudBunny', name: 'Cloud Bunny', rarity: 'Epic', st: [70, 1.2, 1.2, 0.25, 48], thr: 'Floaty lob', ult: 'Rain Check' },
    { id: 'CupcakeAxolotl', name: 'Cupcake Axolotl', rarity: 'Epic', st: [80, 1.1, 1.1, 0.22, 40], thr: 'Wobble lob', ult: 'Bubble Pop' },
    { id: 'Donut', name: 'Donut', rarity: 'Epic', st: [88, 1.1, 1, 0.2, 28], thr: 'Sidearm wheel spin', ult: 'Sprinkle Roller' },
    { id: 'Butter', name: 'Butter', rarity: 'Uncommon', st: [92, 1, 0.9, 0.16, 25], thr: 'Skipping-stone slide' },
    { id: 'Chocolate', name: 'Chocolate', rarity: 'Uncommon', st: [98, 1, 1, 0.17, 30], thr: 'Sidearm frisbee' },
    { id: 'MochiFox', name: 'Mochi Fox', rarity: 'Uncommon', st: [100, 1, 1.05, 0.24, 34], thr: 'Slingshot stretch' },
    { id: 'StrawberryFrog', name: 'Strawberry Frog', rarity: 'Uncommon', st: [85, 0.9, 0.95, 0.18, 42], thr: 'Bounce pass' },
    { id: 'Banana', name: 'Banana', rarity: 'Common', st: [104, 0.9, 1, 0.16, 30], thr: 'Football spiral' },
    { id: 'BobaBear', name: 'Boba Bear', rarity: 'Common', st: [78, 1.1, 1.1, 0.2, 50], thr: 'Underhand lob' },
    { id: 'Toast', name: 'Toast', rarity: 'Common', st: [96, 1, 1, 0.18, 32], thr: 'Sidearm card-flick' },
    { id: 'PancakePup', name: 'Pancake Pup', rarity: 'Common', st: [94, 1, 1, 0.18, 30], thr: 'Frisbee flick' },
  ];
  const TOY = Object.fromEntries(TOYS.map((t) => [t.id, t]));
  const STAT_DEF = [
    ['Speed', 120, (v) => v + ' studs/s', 'linear-gradient(#8BEBFF,#25AEE6)'],
    ['Size', 1.6, (v) => v + ' studs', 'linear-gradient(#8BEBFF,#25AEE6)'],
    ['Reload', 1.6, (v) => v + ' s', 'linear-gradient(#C9A8FF,#8A55EE)'],
    ['Windup', 0.4, (v) => v + ' s', 'linear-gradient(#C9A8FF,#8A55EE)'],
    ['Arc', 60, (v) => v + ' studs/s²', 'linear-gradient(#8BEBFF,#25AEE6)'],
  ];
  const BOXES = [
    { name: 'Soft Box', price: 250, hue: 'none', odds: { Common: 70, Uncommon: 25, Epic: 5 }, plate: 'linear-gradient(#9BF1F8,#2CB8D4)' },
    { name: 'Sweet Box', price: 900, hue: 'hue-rotate(95deg) saturate(1.15)', odds: { Common: 30, Uncommon: 45, Epic: 22, Exclusive: 3 }, plate: 'linear-gradient(#D9B8FF,#8D5BEA)' },
    { name: 'Royal Box', price: 2500, hue: 'hue-rotate(-140deg) saturate(1.35) brightness(1.05)', odds: { Uncommon: 35, Epic: 50, Exclusive: 15 }, plate: 'linear-gradient(#FFE58A,#F2A31B)' },
  ];
  const UNLOCK_AT = { 6: 'Rubber Ball', 7: 'Bounce Trail', 8: 'Gold Squeeze Ring', 9: 'Jelly Mitts', 10: 'Mega Squish', 11: 'Rainbow Trail', 12: 'Crown Aura' };
  const GRIP_NAME = { 5: 'Soft Grip', 6: 'Rubber Grip', 7: 'Bouncy Grip', 8: 'Firm Grip', 9: 'Jelly Grip', 10: 'Mega Grip', 11: 'Rainbow Grip', 12: 'Royal Grip' };
  const PASSES = [
    { id: 'coins2', name: '2x Coins', desc: 'Double coins from every squeeze.', icon: 'uploads/upgraded_v1/double_coins.png', price: 199, bg: 'linear-gradient(#FFE88A,#FFB627)' },
    { id: 'grip2', name: '2x Grip', desc: 'Double Grip from every squeeze.', icon: 'uploads/upgraded_v1/double_grip.png', price: 149, bg: 'linear-gradient(#A4F6D4,#2FC48F)' },
    { id: 'lucky', name: 'Lucky Boxes', desc: 'Epic and Exclusive odds ×1.5.', icon: 'uploads/upgraded_v1/lucky_boxes.png', price: 299, bg: 'linear-gradient(#D7BEFF,#9363F0)' },
    { id: 'fast', name: 'Fast Open', desc: 'Skip the shake, reveal instantly.', icon: 'uploads/upgraded_v1/fast_open.png', price: 79, bg: 'linear-gradient(#9DEFFA,#28B3D6)' },
  ];
  const PACKS = [
    { amount: 1000, bonus: '', price: 49, n: 1, icon: 'uploads/upgraded_v1/coin_pack_1000.png' },
    { amount: 3300, bonus: '+10%', price: 129, n: 2, icon: 'uploads/upgraded_v1/coin_pack_3300.png' },
    { amount: 9600, bonus: '+20%', price: 299, n: 3, icon: 'uploads/upgraded_v1/coin_pack_9600.png' },
    { amount: 32500, bonus: '+30%', price: 799, n: 4, best: true, icon: 'uploads/upgraded_v1/coin_pack_32500.png' },
  ];
  const DAYS = [
    { n: 1, label: '50', type: 'coins', amount: 50, icon: ICON.coin },
    { n: 2, label: '100', type: 'coins', amount: 100, icon: ICON.coin },
    { n: 3, label: 'Soft Box', type: 'box', box: 0, icon: ICON.boxes },
    { n: 4, label: '250', type: 'coins', amount: 250, icon: ICON.coin },
    { n: 5, label: '2x Grip 15m', type: 'boost', secs: 900, icon: ICON.bolt },
    { n: 6, label: '400', type: 'coins', amount: 400, icon: ICON.coin },
    { n: 7, label: 'Royal Box', type: 'box', box: 2, icon: ICON.boxes, big: true },
  ];
  const QUESTS = {
    Daily: [
      { id: 'q1', title: 'Squeeze 20 times', goal: 20, reward: 50, icon: ICON.squeeze, go: 'squeeze' },
      { id: 'q2', title: 'Win a duel', goal: 1, reward: 120, icon: ICON.duel, go: 'duel' },
      { id: 'q3', title: 'Open 2 boxes', goal: 2, reward: 150, icon: ICON.boxes, go: 'boxes' },
      { id: 'q4', title: 'Squeeze 100 times', goal: 100, reward: 200, icon: ICON.grip, go: 'squeeze' },
    ],
    Weekly: [
      { id: 'w1', title: 'Collect 5 squishies', goal: 5, reward: 600, icon: ICON.squishies, go: 'boxes' },
      { id: 'w2', title: 'Reach Grip 6', goal: 6, reward: 400, icon: ICON.trophy, go: 'squeeze' },
      { id: 'w3', title: 'Win 10 duels', goal: 10, reward: 1000, icon: ICON.duel, go: 'duel' },
      { id: 'w4', title: 'Claim 5 daily rewards', goal: 5, reward: 300, icon: ICON.daily, go: 'daily' },
    ],
  };

  /* ---------------- procedural SFX ---------------- */
  class SFX {
    constructor() { this.ctx = null; this.on = true; this.vol = 0.8; }
    ensure() {
      if (!this.ctx) {
        const C = window.AudioContext || window.webkitAudioContext; if (!C) return null;
        const c = (this.ctx = new C());
        const comp = c.createDynamicsCompressor(); comp.threshold.value = -16; comp.ratio.value = 5; comp.attack.value = 0.002; comp.release.value = 0.15;
        this.out = c.createGain(); this.out.gain.value = this.vol; this.out.connect(comp); comp.connect(c.destination);
        const len = c.sampleRate * 2, nb = c.createBuffer(1, len, c.sampleRate), d = nb.getChannelData(0);
        for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
        this.nbuf = nb;
        const ir = c.createBuffer(2, c.sampleRate * 1.6, c.sampleRate);
        for (let ch = 0; ch < 2; ch++) { const x = ir.getChannelData(ch); for (let i = 0; i < x.length; i++) x[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / x.length, 3.2); }
        this.verb = c.createConvolver(); this.verb.buffer = ir; const vg = c.createGain(); vg.gain.value = 0.55; this.verb.connect(vg); vg.connect(this.out);
      }
      if (this.ctx.state === 'suspended') this.ctx.resume();
      return this.ctx;
    }
    setVol(v) { this.vol = v; if (this.out) this.out.gain.setTargetAtTime(v, this.ctx.currentTime, 0.03); }
    _c() { return this.on && this.ctx && this.ctx.state === 'running' ? this.ctx : null; }
    tone(f, d, o = {}) {
      const c = this._c(); if (!c) return;
      const t = c.currentTime + (o.at || 0), osc = c.createOscillator(), g = c.createGain();
      osc.type = o.type || 'sine'; osc.frequency.setValueAtTime(f, t);
      if (o.to) osc.frequency.exponentialRampToValueAtTime(o.to, t + (o.slide || d));
      if (o.det) osc.detune.value = o.det;
      const peak = o.g ?? 0.2;
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(peak, t + (o.a || 0.004)); g.gain.exponentialRampToValueAtTime(0.0001, t + d);
      let node = osc;
      if (o.lp) { const fl = c.createBiquadFilter(); fl.type = 'lowpass'; fl.frequency.value = o.lp; osc.connect(fl); node = fl; }
      node.connect(g); g.connect(this.out);
      if (o.verb) { const s = c.createGain(); s.gain.value = o.verb; g.connect(s); s.connect(this.verb); }
      osc.start(t); osc.stop(t + d + 0.05);
    }
    noise(d, o = {}) {
      const c = this._c(); if (!c) return;
      const t = c.currentTime + (o.at || 0), src = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain();
      src.buffer = this.nbuf; src.loop = true; f.type = o.type || 'bandpass'; f.frequency.setValueAtTime(o.f || 2000, t); f.Q.value = o.q ?? 1;
      if (o.to) f.frequency.exponentialRampToValueAtTime(o.to, t + d);
      const peak = o.g ?? 0.15;
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(peak, t + (o.a || 0.003)); g.gain.exponentialRampToValueAtTime(0.0001, t + d);
      src.connect(f); f.connect(g); g.connect(this.out);
      if (o.verb) { const s = c.createGain(); s.gain.value = o.verb; g.connect(s); s.connect(this.verb); }
      src.start(t, Math.random() * 1.5); src.stop(t + d + 0.05);
    }
    r(a = 0.04) { return 1 + (Math.random() * 2 - 1) * a; }
    note(semi, base = 523.25) { return base * Math.pow(2, semi / 12); }
    hover(p = 1) { const k = p * this.r(0.04); this.tone(1400 * k, 0.07, { to: 2000 * k, g: 0.035 }); this.tone(2800 * k, 0.04, { g: 0.012, at: 0.01 }); }
    press() { const k = this.r(0.05); this.tone(460 * k, 0.15, { to: 170 * k, g: 0.2 }); this.tone(920 * k, 0.07, { to: 320, type: 'triangle', g: 0.05 }); this.noise(0.05, { f: 1300, q: 0.8, g: 0.05 }); }
    pop() { const k = this.r(0.05); this.tone(360 * k, 0.09, { to: 1050 * k, g: 0.15 }); this.tone(2100 * k, 0.07, { at: 0.035, g: 0.035 }); }
    card() { const k = this.r(0.06); this.tone(700 * k, 0.07, { to: 1200 * k, g: 0.09, type: 'triangle' }); this.noise(0.03, { f: 4000, q: 2, g: 0.04 }); }
    tab() { this.noise(0.025, { f: 3400, q: 3, g: 0.09 }); this.tone(980 * this.r(0.03), 0.05, { to: 720, type: 'triangle', g: 0.07 }); }
    open() {
      this.noise(0.34, { f: 420, to: 3200, q: 1.1, g: 0.07, a: 0.14 });
      this.tone(220, 0.22, { to: 520, g: 0.12, a: 0.02 });
      [0, 4, 7, 12, 16].forEach((s, i) => this.tone(this.note(s, 784), 0.45, { at: 0.1 + i * 0.045, type: 'triangle', g: 0.055, verb: 0.5 }));
    }
    close() { this.noise(0.22, { f: 2800, to: 450, q: 1.1, g: 0.055, a: 0.02 }); this.tone(760, 0.15, { to: 260, g: 0.1 }); }
    coin(i = 0) { const f = this.note((i % 10) * 1, 1568) * this.r(0.01); this.tone(f, 0.3, { g: 0.06, verb: 0.25 }); this.tone(f * 1.5, 0.18, { g: 0.03, type: 'triangle', at: 0.012 }); this.tone(f * 2.76, 0.1, { g: 0.015 }); }
    claim() {
      [0, 4, 7, 12, 16, 19].forEach((s, i) => this.tone(this.note(s), 0.55, { at: i * 0.055, type: 'triangle', g: 0.07, verb: 0.45 }));
      this.tone(this.note(24), 0.9, { at: 0.33, g: 0.05, verb: 0.6 });
      this.noise(0.7, { f: 7500, type: 'highpass', q: 0.5, g: 0.025, at: 0.12, verb: 0.5 });
    }
    error() { this.tone(200, 0.18, { to: 120, type: 'square', g: 0.05, lp: 1200 }); this.tone(150, 0.26, { to: 90, type: 'triangle', g: 0.13, at: 0.06 }); }
    toggle(on) { if (on) { this.tone(620, 0.06, { to: 980, g: 0.09 }); this.tone(1320, 0.08, { at: 0.05, g: 0.06 }); } else { this.tone(980, 0.06, { to: 620, g: 0.08 }); this.tone(500, 0.08, { at: 0.05, g: 0.06 }); } }
    squeeze() {
      const k = this.r(0.09);
      this.noise(0.2, { f: 700 * k, to: 2600 * k, q: 5, g: 0.11, a: 0.02 });
      this.tone(230 * k, 0.15, { to: 470 * k, g: 0.15, a: 0.01 });
      this.tone(150 * k, 0.12, { to: 85, g: 0.09, at: 0.025 });
      this.noise(0.06, { f: 5200, q: 2, g: 0.03, at: 0.08 });
    }
    rattle(j) {
      const n = 5 + j * 2;
      for (let i = 0; i < n; i++) { this.noise(0.035, { at: i * 0.045, f: 2200 + Math.random() * 2200, q: 2.5, g: 0.07 + 0.03 * j }); this.tone(110 + j * 20, 0.08, { at: i * 0.045, to: 70, g: 0.06 + 0.02 * j }); }
      this.tone(this.note(j * 4, 392), 0.25, { at: 0.05, type: 'triangle', g: 0.04 + 0.015 * j, verb: 0.3 });
    }
    burst() {
      this.tone(180, 0.7, { to: 38, g: 0.32 });
      this.noise(0.9, { f: 1600, type: 'lowpass', q: 0.4, g: 0.24 });
      this.noise(1.4, { f: 8200, type: 'highpass', q: 0.5, g: 0.05, verb: 0.7, at: 0.03 });
    }
    reveal(idx) {
      const chords = [[0, 4, 7], [0, 4, 7, 12], [0, 4, 7, 11, 14, 19], [0, 7, 12, 16, 19, 24, 28]];
      chords[idx].forEach((s, i) => this.tone(this.note(s), 0.9 + idx * 0.25, { at: 0.04 + i * 0.07, type: 'triangle', g: 0.07, verb: 0.55 }));
      if (idx >= 2) [0, 7, 12].forEach((s) => { this.tone(this.note(s, 261.6), 1.8, { type: 'sawtooth', g: 0.022, a: 0.35, det: -9, lp: 2400, verb: 0.5 }); this.tone(this.note(s, 261.6), 1.8, { type: 'sawtooth', g: 0.022, a: 0.35, det: 9, lp: 2400 }); });
      if (idx === 3) for (let i = 0; i < 10; i++) this.tone(this.note(24 + ((i * 5) % 12), 1046), 0.25, { at: 0.5 + i * 0.07, g: 0.025, verb: 0.6 });
    }
    whoosh(up = true) { this.noise(0.3, { f: up ? 500 : 2600, to: up ? 2600 : 400, q: 1.2, g: 0.07, a: 0.1 }); }
    slot(i) { this.tone(this.note(i, 659), 0.12, { g: 0.07, type: 'triangle', verb: 0.2 }); this.tone(this.note(i + 12, 659), 0.06, { g: 0.02 }); }
    tick(hi) { this.tone(hi ? 1400 : 900, 0.05, { g: 0.05, type: 'triangle' }); }
    found() {
      [[0, 4, 7], [5, 9, 12], [7, 11, 14, 19]].forEach((ch, j) => ch.forEach((s) => { this.tone(this.note(s, 392), 0.32 + j * 0.25, { at: j * 0.16, type: 'sawtooth', g: 0.035, lp: 2600, verb: 0.35 }); this.tone(this.note(s, 392), 0.32 + j * 0.25, { at: j * 0.16, type: 'triangle', g: 0.04 }); }));
      this.tone(98, 0.5, { to: 60, g: 0.25 });
    }
    purchase() { this.noise(0.06, { f: 5200, q: 1, g: 0.09 }); this.tone(130, 0.18, { to: 70, g: 0.2 }); [1046, 1318, 1568, 2093].forEach((f, i) => this.tone(f, 0.9, { at: 0.08 + i * 0.03, type: 'triangle', g: 0.05, verb: 0.55 })); }
    stamp() { this.tone(120, 0.22, { to: 55, g: 0.3 }); this.noise(0.09, { f: 700, q: 0.7, g: 0.18 }); this.tone(2093, 0.45, { at: 0.09, g: 0.05, verb: 0.55 }); }
    levelup() {
      [0, 2, 4, 5, 7, 9, 11, 12].forEach((s, i) => this.tone(this.note(s), 0.18, { at: i * 0.05, type: 'square', g: 0.03, lp: 3200 }));
      [0, 4, 7, 12].forEach((s) => this.tone(this.note(s + 12), 1.2, { at: 0.42, type: 'triangle', g: 0.06, verb: 0.6 }));
      this.tone(196, 0.5, { at: 0.42, to: 98, g: 0.18 });
    }
    equip() { this.pop(); [0, 7, 12].forEach((s, i) => this.tone(this.note(s, 1046), 0.3, { at: 0.06 + i * 0.05, g: 0.04, verb: 0.4 })); }
    slide(v) { this.tone(500 + v * 900, 0.03, { g: 0.03, type: 'triangle' }); }
    crack(j) {
      const k = this.r(0.06);
      this.noise(0.09, { f: (3200 + j * 600) * k, q: 0.8, g: 0.24 + j * 0.04 });
      this.noise(0.04, { f: 8000, type: 'highpass', q: 0.5, g: 0.14 });
      this.tone((170 - j * 25) * k, 0.24, { to: 45, g: 0.3 });
      for (let i = 0; i < 3 + j; i++) this.tone(this.note(19 + Math.floor(Math.random() * 10), 1046), 0.18, { at: 0.03 + i * 0.035, g: 0.03, verb: 0.4 });
    }
    charge() {
      this.tone(180, 0.75, { to: 1100, type: 'sawtooth', g: 0.05, lp: 2200, a: 0.5 });
      this.tone(90, 0.75, { to: 160, g: 0.14, a: 0.3 });
      this.noise(0.75, { f: 400, to: 5200, q: 4, g: 0.09, a: 0.5 });
    }
    slam() { this.tone(110, 0.45, { to: 42, g: 0.32 }); this.noise(0.22, { f: 900, q: 0.6, g: 0.16 }); this.noise(0.5, { f: 7000, type: 'highpass', g: 0.03, verb: 0.6, at: 0.02 }); }
    fanfare() {
      [[0, [0, 4, 7], 0.14], [0.15, [0, 4, 7], 0.14], [0.3, [5, 9, 12], 0.18], [0.52, [7, 11, 14, 19], 1.3]].forEach(([at, ch, d]) => ch.forEach((n) => { this.tone(this.note(n, 392), d, { at, type: 'sawtooth', g: 0.035, lp: 3000, verb: 0.4 }); this.tone(this.note(n + 12, 392), d, { at, type: 'triangle', g: 0.03 }); }));
      this.tone(98, 0.7, { at: 0.52, to: 49, g: 0.25 });
      for (let i = 0; i < 12; i++) this.tone(this.note(24 + ((i * 7) % 12), 1046), 0.2, { at: 0.6 + i * 0.06, g: 0.02, verb: 0.6 });
      this.noise(1.2, { f: 8000, type: 'highpass', q: 0.5, g: 0.03, at: 0.5, verb: 0.6 });
    }
    chime() { [7, 12].forEach((s, i) => this.tone(this.note(s, 784), 0.4, { at: i * 0.08, g: 0.05, verb: 0.4, type: 'triangle' })); }
    /* match found + map vote */
    mfCharge() {
      this.noise(0.5, { f: 280, to: 5200, q: 2.4, g: 0.09, a: 0.42 });
      this.tone(150, 0.5, { to: 900, type: 'sawtooth', g: 0.03, lp: 2600, a: 0.44 });
      this.tone(70, 0.5, { to: 140, g: 0.12, a: 0.4 });
      [0, 3, 5, 7, 10, 12, 15, 17].forEach((s, i) => this.tone(this.note(s, 1046), 0.09, { at: i * 0.055, type: 'triangle', g: 0.018 + i * 0.004 }));
    }
    mfImpact() {
      this.tone(150, 0.95, { to: 32, g: 0.4 });
      this.noise(0.55, { f: 1300, type: 'lowpass', q: 0.5, g: 0.28 });
      this.noise(1.7, { f: 7200, type: 'highpass', q: 0.4, g: 0.06, verb: 0.8, at: 0.01 });
      [0, 4, 7, 12, 16].forEach((s) => { this.tone(this.note(s, 523.25), 1.2, { type: 'sawtooth', g: 0.028, lp: 3400, verb: 0.5 }); this.tone(this.note(s, 523.25), 1.2, { type: 'triangle', g: 0.032, det: 8 }); });
      this.tone(240, 0.3, { to: 640, g: 0.12, at: 0.04, a: 0.02 });
      this.tone(640, 0.28, { to: 300, type: 'triangle', g: 0.06, at: 0.2 });
    }
    mfLetters(n, gap = 0.045, base = 659.25) {
      const p = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26];
      for (let i = 0; i < n; i++) { const f = this.note(p[i % 12], base), at = i * gap; this.tone(f, 0.16, { at, type: 'triangle', g: 0.05 }); this.tone(f * 2, 0.07, { at, g: 0.014 }); this.noise(0.02, { at, f: 5200, q: 2, g: 0.02 }); }
    }
    vsSlam() {
      this.tone(120, 0.55, { to: 38, g: 0.34 });
      this.noise(0.14, { f: 2200, q: 0.7, g: 0.2 });
      [440, 660, 990].forEach((f, i) => this.tone(f, 0.55, { type: 'square', g: 0.016, lp: 4200, det: i * 7, verb: 0.55 }));
      this.noise(0.9, { f: 6500, type: 'highpass', q: 0.5, g: 0.03, at: 0.03, verb: 0.6 });
    }
    toss() { const k = this.r(0.08); this.noise(0.2, { f: 700 * k, to: 2600 * k, q: 1.6, g: 0.035, a: 0.07 }); }
    voteLand(n = 1, mine = false) {
      const p = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26], f = this.note(p[Math.min(Math.max(n, 1) - 1, 11)], 523.25), v = mine ? 1.7 : 1;
      this.tone(250 * this.r(0.05), 0.1, { to: 720, g: 0.08 * v });
      this.tone(f, 0.32, { at: 0.035, type: 'triangle', g: 0.045 * v, verb: 0.35 });
      this.tone(f * 2, 0.16, { at: 0.045, g: 0.014 * v });
      if (mine) { this.noise(0.45, { f: 7200, type: 'highpass', q: 0.5, g: 0.03, at: 0.05, verb: 0.5 }); this.tone(f * 1.5, 0.3, { at: 0.11, type: 'triangle', g: 0.04, verb: 0.4 }); }
    }
    clockTick(urgent) {
      if (urgent) { this.tone(1760, 0.08, { g: 0.07, type: 'triangle' }); this.tone(880, 0.12, { g: 0.04, type: 'square', lp: 2400 }); this.tone(130, 0.16, { to: 70, g: 0.14 }); }
      else { this.tone(1250, 0.045, { g: 0.04, type: 'triangle' }); this.noise(0.02, { f: 4200, q: 3, g: 0.03 }); }
    }
    roulette(i) { const f = this.note(i % 2 ? 7 : 12, 784); this.tone(f, 0.07, { type: 'square', g: 0.025, lp: 3200 }); this.tone(f * 2, 0.04, { g: 0.012 }); this.noise(0.02, { f: 3200, q: 3, g: 0.04 }); }
  }

  /* ---------------- DOM fx (particles, coin flights, floats) ---------------- */
  const FX = {
    layer: null, getLayer: null, k: 1, reduced: false,
    get L() { if (!(this.layer && this.layer.isConnected) && this.getLayer) this.layer = this.getLayer(); return this.layer; },
    center(el) { const r = el.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width, h: r.height }; },
    burst(x, y, o = {}) {
      if (!this.L || this.reduced) return;
      const k = this.k, n = o.n || 16, cols = o.colors || ['#FFD84A', '#FF6FA3', '#5FE0E8', '#8DF27A', '#B98CFF'];
      for (let i = 0; i < n; i++) {
        const d = document.createElement('div'), s = (o.size || 13) * (0.55 + Math.random() * 0.9) * k, star = Math.random() < (o.stars ?? 0.55);
        d.style.cssText = `position:absolute;left:${x - s / 2}px;top:${y - s / 2}px;width:${s}px;height:${s}px;background:${cols[i % cols.length]};` +
          (star ? 'clip-path:polygon(50% 0,62% 38%,100% 50%,62% 62%,50% 100%,38% 62%,0 50%,38% 38%)' : `border-radius:50%;box-shadow:0 0 0 ${Math.max(1.5, 2.5 * k)}px #1E1428`);
        this.L.appendChild(d);
        const a = (o.angle ?? Math.random() * Math.PI * 2) + (o.angle != null ? (Math.random() - 0.5) * (o.cone || 1.2) : 0);
        const v = (o.spread || 150) * (0.35 + Math.random() * 0.85) * k, dx = Math.cos(a) * v, dy = Math.sin(a) * v - (o.up ?? 40) * k, rot = (Math.random() - 0.5) * 600;
        d.animate([
          { transform: 'translate(0,0) scale(0) rotate(0deg)', opacity: 1 },
          { transform: `translate(${dx * 0.7}px,${dy * 0.7}px) scale(1.25) rotate(${rot * 0.5}deg)`, opacity: 1, offset: 0.35 },
          { transform: `translate(${dx}px,${dy + (o.grav ?? 110) * k}px) scale(0.1) rotate(${rot}deg)`, opacity: 0 },
        ], { duration: (o.dur || 820) + Math.random() * 420, easing: 'cubic-bezier(.15,.7,.35,1)', delay: o.delay || 0, fill: 'backwards' }).onfinish = () => d.remove();
      }
    },
    ring(x, y, color = '#fff', size = 160) {
      if (!this.L || this.reduced) return;
      const k = this.k, d = document.createElement('div'), s = size * k;
      d.style.cssText = `position:absolute;left:${x - s / 2}px;top:${y - s / 2}px;width:${s}px;height:${s}px;border-radius:50%;border:${6 * k}px solid ${color};`;
      this.L.appendChild(d);
      d.animate([{ transform: 'scale(.2)', opacity: 1 }, { transform: 'scale(1.3)', opacity: 0 }], { duration: 520, easing: 'cubic-bezier(.2,.8,.3,1)' }).onfinish = () => d.remove();
    },
    rain(n = 60, cols) {
      const L = this.L; if (!L || this.reduced) return;
      cols = cols || ['#FFD84A', '#FF6FA3', '#5FE0E8', '#8DF27A', '#B98CFF', '#FFFFFF'];
      const W = innerWidth, Hh = innerHeight, k = this.k;
      for (let i = 0; i < n; i++) {
        const d = document.createElement('div'), w = (8 + Math.random() * 8) * k, h = w * (Math.random() < 0.5 ? 1 : 1.8);
        d.style.cssText = 'position:absolute;left:' + Math.random() * W + 'px;top:' + (-30 - Math.random() * 80) + 'px;width:' + w + 'px;height:' + h + 'px;background:' + cols[i % cols.length] + ';border-radius:' + (Math.random() < 0.4 ? '50%' : '2px') + ';box-shadow:0 0 0 ' + Math.max(1.5, 2 * k) + 'px #1E1428';
        L.appendChild(d);
        const sway = (Math.random() - 0.5) * 160 * k, r = (Math.random() - 0.5) * 1080;
        d.animate([{ transform: 'translate(0,0) rotate(0)' }, { transform: 'translate(' + sway + 'px,' + (Hh * 0.55) + 'px) rotate(' + r * 0.5 + 'deg)', offset: 0.5 }, { transform: 'translate(' + (-sway * 0.4) + 'px,' + (Hh + 120) + 'px) rotate(' + r + 'deg)' }], { duration: 1900 + Math.random() * 1400, delay: Math.random() * 600, easing: 'cubic-bezier(.3,.1,.7,1)', fill: 'backwards' }).onfinish = () => d.remove();
      }
    },
    float(x, y, text, color = '#fff', size = 30, o = {}) {
      if (!this.L) return;
      const k = this.k, d = document.createElement('div');
      d.textContent = text;
      d.style.cssText = `position:absolute;left:${x}px;top:${y}px;font-family:Fredoka,sans-serif;font-weight:700;font-size:${size * k}px;color:${color};-webkit-text-stroke:${Math.max(3, 6 * k)}px #1E1428;paint-order:stroke fill;text-shadow:0 ${3 * k}px 0 #1E1428;white-space:nowrap;line-height:1`;
      this.L.appendChild(d);
      const dx = (o.dx ?? (Math.random() - 0.5) * 30) * k, rise = (o.rise ?? 80) * k;
      d.animate([
        { transform: 'translate(-50%,-50%) scale(.3)', opacity: 0 },
        { transform: `translate(calc(-50% + ${dx * 0.3}px),calc(-50% - ${rise * 0.25}px)) scale(1.25)`, opacity: 1, offset: 0.18 },
        { transform: `translate(calc(-50% + ${dx * 0.6}px),calc(-50% - ${rise * 0.55}px)) scale(1)`, opacity: 1, offset: 0.6 },
        { transform: `translate(calc(-50% + ${dx}px),calc(-50% - ${rise}px)) scale(.9)`, opacity: 0 },
      ], { duration: o.dur || 1050, easing: 'cubic-bezier(.2,.8,.3,1)' }).onfinish = () => d.remove();
    },
    fly(from, toEl, n, onLand, img = ICON.coin) {
      if (!this.L || !toEl) return;
      const k = this.k;
      for (let i = 0; i < n; i++) {
        setTimeout(() => {
          const to = toEl.getBoundingClientRect(), tx = to.left + Math.min(28 * k, to.width / 2), ty = to.top + to.height / 2;
          const e = document.createElement('img'), s = 46 * k; e.src = img; e.style.cssText = `position:absolute;left:0;top:0;width:${s}px;height:${s}px;`;
          this.L.appendChild(e);
          const sx = from.x - s / 2 + (Math.random() - 0.5) * 30 * k, sy = from.y - s / 2 + (Math.random() - 0.5) * 30 * k;
          const mx = sx + (Math.random() - 0.5) * 260 * k, my = sy - (50 + Math.random() * 140) * k;
          e.animate([
            { transform: `translate(${sx}px,${sy}px) scale(0) rotate(0deg)` },
            { transform: `translate(${mx}px,${my}px) scale(1.15) rotate(${(Math.random() - 0.5) * 90}deg)`, offset: 0.32, easing: 'cubic-bezier(.55,0,.85,.55)' },
            { transform: `translate(${tx - s / 2}px,${ty - s / 2}px) scale(.55) rotate(0deg)` },
          ], { duration: 720 + Math.random() * 220, easing: 'cubic-bezier(.25,.7,.35,1)', fill: 'forwards' }).onfinish = () => { e.remove(); onLand && onLand(i); };
        }, i * 60);
      }
    },
    converge(x, y, o = {}) {
      if (!this.L || this.reduced) return;
      const k = this.k, n = o.n || 20, R = (o.r || 520) * k, cols = o.colors || ['#FFD84A', '#FF6FA3', '#5FE0E8', '#FFFFFF', '#B98CFF'];
      for (let i = 0; i < n; i++) {
        const d = document.createElement('div'), s = (o.size || 15) * (0.6 + Math.random() * 0.8) * k, a = (i / n) * Math.PI * 2 + Math.random() * 0.3, r = R * (0.7 + Math.random() * 0.5);
        d.style.cssText = 'position:absolute;left:' + (x - s / 2) + 'px;top:' + (y - s / 2) + 'px;width:' + s + 'px;height:' + s + 'px;background:' + cols[i % cols.length] + ';clip-path:polygon(50% 0,62% 38%,100% 50%,62% 62%,50% 100%,38% 62%,0 50%,38% 38%)';
        this.L.appendChild(d);
        const dx = Math.cos(a) * r, dy = Math.sin(a) * r;
        d.animate([
          { transform: 'translate(' + dx + 'px,' + dy + 'px) scale(.4) rotate(0deg)', opacity: 0 },
          { transform: 'translate(' + dx * 0.75 + 'px,' + dy * 0.75 + 'px) scale(.8) rotate(60deg)', opacity: 1, offset: 0.25 },
          { transform: 'translate(0px,0px) scale(1.2) rotate(270deg)', opacity: 1, offset: 0.9 },
          { transform: 'translate(0px,0px) scale(0) rotate(300deg)', opacity: 0 },
        ], { duration: (o.dur || 480) + Math.random() * 80, delay: Math.random() * 60, easing: 'cubic-bezier(.55,0,.9,.5)', fill: 'backwards' }).onfinish = () => d.remove();
      }
    },
    toss(from, to, o = {}, onLand) {
      const L = this.L; if (!L || this.reduced) { if (onLand) onLand(); return; }
      const k = this.k, s = (o.size || 46) * k, dur = o.dur || 650;
      const ox = document.createElement('div'), oy = document.createElement('div'), d = document.createElement('div');
      ox.style.cssText = 'position:absolute;left:0;top:0;width:' + s + 'px;height:' + s + 'px;pointer-events:none';
      oy.style.cssText = 'width:' + s + 'px;height:' + s + 'px';
      d.style.cssText = 'box-sizing:border-box;width:' + s + 'px;height:' + s + 'px;border:' + Math.max(2, 4 * k) + 'px solid #1E1428;border-radius:' + 15 * k + 'px;background:' + (o.bg || '#fff') + ';box-shadow:0 ' + 3 * k + 'px 0 #1E1428,inset 0 ' + 3 * k + 'px 0 rgba(255,255,255,.45);display:grid;place-items:center;overflow:hidden';
      if (o.img) { const im = document.createElement('img'); im.src = o.img; im.style.cssText = 'width:88%;height:88%;object-fit:contain'; d.appendChild(im); }
      oy.appendChild(d); ox.appendChild(oy); L.appendChild(ox);
      const sx = from.x - s / 2, sy = from.y - s / 2, ex = to.x - s / 2, ey = to.y - s / 2, top = Math.min(sy, ey) - (o.arc ?? 120) * k, spin = o.spin ?? 360;
      ox.animate([{ transform: 'translateX(' + sx + 'px)' }, { transform: 'translateX(' + ex + 'px)' }], { duration: dur, easing: 'cubic-bezier(.4,.1,.6,.9)', fill: 'forwards' });
      oy.animate([{ transform: 'translateY(' + sy + 'px)', easing: 'cubic-bezier(.2,.6,.35,1)' }, { transform: 'translateY(' + top + 'px)', offset: 0.6, easing: 'cubic-bezier(.6,0,.85,.45)' }, { transform: 'translateY(' + ey + 'px)' }], { duration: dur, fill: 'forwards' });
      d.animate([{ transform: 'scale(.7) rotate(0deg)' }, { transform: 'scale(1.25) rotate(' + spin * 0.6 + 'deg)', offset: 0.55 }, { transform: 'scale(1) rotate(' + spin + 'deg)' }], { duration: dur, easing: 'ease-out', fill: 'forwards' }).onfinish = () => { ox.remove(); if (onLand) onLand(); };
      if (o.trail) { let n = 0; const iv = setInterval(() => { if (!ox.isConnected || n++ > 6) { clearInterval(iv); return; } const r = d.getBoundingClientRect(); this.burst(r.left + r.width / 2, r.top + r.height / 2, { n: 2, spread: 30, size: 8, up: 0, grav: 30, dur: 420, colors: o.trail }); }, dur / 7); }
    },
    squash(el, amt = 1) {
      if (!el || !el.animate) return;
      const a = 0.14 * amt;
      el.animate([
        { transform: 'scale(1,1)' }, { transform: `scale(${1 + a},${1 - a})`, offset: 0.2 }, { transform: `scale(${1 - a * 0.5},${1 + a * 0.6})`, offset: 0.45 },
        { transform: `scale(${1 + a * 0.2},${1 - a * 0.15})`, offset: 0.7 }, { transform: 'scale(1,1)' },
      ], { duration: 460, easing: 'ease-out', composite: 'add' });
    },
    shakeX(el, amt = 10) {
      if (!el || !el.animate) return;
      el.animate([0, -1, 1, -0.8, 0.6, -0.3, 0].map((v) => ({ transform: `translateX(${v * amt}px) rotate(${v * 2}deg)` })), { duration: 420, easing: 'ease-out', composite: 'add' });
    },
    jolt(el, amt = 10) {
      if (!el || !el.animate || this.reduced) return;
      const f = []; for (let i = 0; i < 8; i++) { const d = amt * (1 - i / 8); f.push({ transform: `translate(${(Math.random() - 0.5) * 2 * d}px,${(Math.random() - 0.5) * 2 * d}px)` }); } f.push({ transform: 'translate(0,0)' });
      el.animate(f, { duration: 380, easing: 'linear', composite: 'add' });
    },
  };
  const fmt = (n) => Math.round(n).toLocaleString('en-US');
  const clock = (s) => { s = Math.max(0, Math.floor(s)); const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60; return h ? `${h}h ${String(m).padStart(2, '0')}m` : `${m}:${String(x).padStart(2, '0')}`; };
  const hms = (s) => { s = Math.max(0, Math.floor(s)); const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60; return `${h}:${String(m).padStart(2, '0')}:${String(x).padStart(2, '0')}`; };
  window.SDHUD = { ICON, BLANK, RAR, TOYS, TOY, STAT_DEF, BOXES, UNLOCK_AT, GRIP_NAME, PASSES, PACKS, DAYS, QUESTS, SFX, FX, fmt, clock, hms };
})();
