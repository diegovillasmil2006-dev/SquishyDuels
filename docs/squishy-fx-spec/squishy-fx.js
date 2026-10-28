/* squishy-fx.js — shared preview engine for the Squishy Duels VFX spec pages.
   It holds NO design values: every number it uses is read from the page's CONFIG
   (CONFIG.viewer = preview-stage values that are not part of the Roblox build).
   Load after squishy-kit.js. Plain script so pages also open straight from disk. */
(function () {
'use strict';
const JOINTS = ['Root', 'Waist', 'Neck', 'LeftShoulder', 'LeftElbow', 'LeftWrist', 'RightShoulder', 'RightElbow', 'RightWrist', 'LeftHip', 'LeftKnee', 'LeftAnkle', 'RightHip', 'RightKnee', 'RightAnkle'];
const POSE_KEYS = JOINTS.concat(['RootPos']);
const NAV = [['kit.html', 'Kit'], ['move.html', '1 · Move'], ['hit.html', '2 · Hit'], ['duelflight.html', '3 · Duel flight'], ['highway.html', '4 · Highway']];
const KINDS = ['motion', 'burst', 'emit', 'stop', 'ring', 'pop', 'trail', 'flash', 'glow', 'light', 'shake', 'fov', 'punch', 'dip', 'hitstop', 'slowmo', 'pose', 'squash', 'wobble', 'sound', 'ui', 'afterimage', 'call', 'note'];
// Easing curve definitions (Roblox Enum.EasingStyle / Penner). These constants define the curves; they are not tunables.
const BACK_S = 1.70158;
const EASE_IN = {
  Linear: x => x,
  Sine: x => 1 - Math.cos(x * Math.PI / 2),
  Quad: x => x * x,
  Cubic: x => x * x * x,
  Quart: x => x * x * x * x,
  Quint: x => x * x * x * x * x,
  Exponential: x => (x <= 0 ? 0 : Math.pow(2, 10 * x - 10)),
  Circular: x => 1 - Math.sqrt(1 - x * x),
  Back: x => x * x * ((BACK_S + 1) * x - BACK_S),
  Elastic: x => (x <= 0 || x >= 1 ? x : -Math.pow(2, 10 * x - 10) * Math.sin((x * 10 - 10.75) * (2 * Math.PI / 3))),
  Bounce: x => 1 - bounceOut(1 - x)
};
function bounceOut(x) {
  const n = 7.5625, d = 2.75;
  if (x < 1 / d) return n * x * x;
  if (x < 2 / d) { x -= 1.5 / d; return n * x * x + 0.75; }
  if (x < 2.5 / d) { x -= 2.25 / d; return n * x * x + 0.9375; }
  x -= 2.625 / d; return n * x * x + 0.984375;
}
function clamp01(u) { return u < 0 ? 0 : u > 1 ? 1 : u; }
function ease(name, u) {
  u = clamp01(u);
  if (!name || name === 'Linear') return u;
  if (name === 'Constant') return u >= 1 ? 1 : 0;
  const p = name.split(' '), f = EASE_IN[p[0]] || EASE_IN.Linear, dir = p[1] || 'Out';
  if (dir === 'In') return f(u);
  if (dir === 'Out') return 1 - f(1 - u);
  return u < 0.5 ? f(2 * u) / 2 : 1 - f(2 - 2 * u) / 2;
}
function seqN(s, u) {
  if (s == null) return 0;
  if (typeof s === 'number') return s;
  if (u <= s[0][0]) return s[0][1];
  for (let i = 1; i < s.length; i++) {
    if (u <= s[i][0]) { const a = s[i - 1], b = s[i]; return a[1] + (b[1] - a[1]) * ((u - a[0]) / ((b[0] - a[0]) || 1)); }
  }
  return s[s.length - 1][1];
}
function seqMax(s) { return s == null ? 0 : typeof s === 'number' ? s : Math.max.apply(null, s.map(k => k[1])); }
function rr(r) { return Array.isArray(r) ? r[0] + Math.random() * (r[1] - r[0]) : (r || 0); }
function hi(r) { return Array.isArray(r) ? Math.max(r[0], r[1]) : (r || 0); }
function pair(c) { return Array.isArray(c) ? c : [c, c]; }
function wrap180(a) { return ((((a + 180) % 360) + 360) % 360) - 180; }
function fmt(n) { return (Math.round(n * 100) / 100).toFixed(2); }
function rng(r) { return Array.isArray(r) ? (r[0] === r[1] ? `${r[0]}` : `${r[0]}–${r[1]}`) : `${r}`; }
function esc(s) { return String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c])); }

const CSS = `
*{box-sizing:border-box}
html,body{margin:0;height:100%;background:var(--bg);color:var(--ink);font-family:'Fredoka',ui-rounded,system-ui,sans-serif}
a{color:var(--ink)} a:hover{color:var(--accent-ink)}
.sq-app{position:fixed;inset:0;display:grid;grid-template-columns:272px minmax(0,1fr) 352px}
.sq-side,.sq-time{overflow:auto;padding:18px 16px 28px;display:flex;flex-direction:column;gap:18px;min-height:0}
.sq-side{border-right:2px solid var(--line)}
.sq-time{border-left:2px solid var(--line);gap:12px}
.sq-brand{font-weight:700;font-size:15px;display:flex;gap:8px;align-items:baseline}
.sq-brand span{font-weight:500;color:var(--muted)}
.sq-nav{display:flex;flex-wrap:wrap;gap:6px}
.sq-nav a{text-decoration:none;font-size:13px;font-weight:500;padding:5px 10px;border-radius:999px;border:2px solid var(--line);background:var(--panel)}
.sq-nav a:hover{border-color:var(--ink);color:var(--ink)}
.sq-nav a.on{background:var(--ink);border-color:var(--ink);color:var(--bg)}
.sq-side h1{font-size:27px;line-height:1.05;margin:0 0 6px;font-weight:700}
.sq-time h2{font-size:19px;margin:0;font-weight:600}
.sq-sub{margin:0;font-size:13.5px;line-height:1.42;color:var(--muted);text-wrap:pretty}
.sq-label{font-size:11.5px;font-weight:600;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);margin-bottom:8px;display:flex;justify-content:space-between;gap:8px}
.sq-label em{font-style:normal;letter-spacing:0;text-transform:none;font-weight:500}
.sq-col{display:flex;flex-direction:column;gap:6px}
.sq-row{display:flex;flex-wrap:wrap;gap:6px}
.sq-btn{font:inherit;font-size:14px;font-weight:500;color:var(--ink);background:var(--panel);border:2px solid var(--line);border-radius:12px;padding:8px 12px;cursor:pointer;text-align:left;display:flex;justify-content:space-between;align-items:center;gap:10px}
.sq-btn:hover{border-color:var(--ink)}
.sq-btn.on{background:var(--accent);border-color:var(--ink)}
.sq-btn .k{font-family:'IBM Plex Mono',monospace;font-size:11px;color:var(--muted)}
.sq-btn.on .k{color:var(--ink)}
.sq-row .sq-btn{flex:1 1 auto;justify-content:center;font-size:13px;padding:7px 10px}
.sq-btn[disabled]{opacity:.35;cursor:not-allowed;border-color:var(--line)}
.sq-tog .dot{width:30px;height:18px;border-radius:999px;background:var(--line);position:relative;flex:none;transition:background .15s}
.sq-tog .dot::after{content:'';position:absolute;top:3px;left:3px;width:12px;height:12px;border-radius:50%;background:var(--panel);transition:left .15s}
.sq-tog.on{background:var(--panel)}
.sq-tog.on .dot{background:var(--ink)}
.sq-tog.on .dot::after{left:15px}
.sq-main{position:relative;min-width:0;min-height:0}
#sq-viewport{position:absolute;inset:14px;border-radius:20px;overflow:hidden;background:var(--stage);border:3px solid var(--ink)}
#sq-viewport canvas{display:block;width:100%;height:100%;touch-action:none;cursor:grab}
#sq-overlay{position:absolute;inset:0;pointer-events:none;overflow:hidden}
#sq-hud{position:absolute;left:12px;top:12px;display:flex;flex-wrap:wrap;gap:6px;pointer-events:none;font-family:'IBM Plex Mono',monospace;font-size:12px}
#sq-hud span{background:var(--ink);color:var(--bg);padding:4px 8px;border-radius:8px}
#sq-hud span.warn{background:var(--accent);color:var(--ink)}
#sq-viewlabel{position:absolute;right:12px;top:12px;font-size:12.5px;font-weight:600;background:var(--panel);border:2px solid var(--ink);border-radius:8px;padding:3px 9px;pointer-events:none}
#sq-sfx{position:absolute;left:12px;bottom:12px;display:flex;flex-direction:column-reverse;gap:4px;pointer-events:none}
#sq-sfx div{font-family:'IBM Plex Mono',monospace;font-size:12px;background:var(--panel);border:2px solid var(--ink);border-radius:8px;padding:3px 8px;transition:opacity .35s}
.sq-flash{position:absolute;inset:0;opacity:0}
.sq-img{position:absolute;-webkit-mask-size:contain;mask-size:contain;-webkit-mask-repeat:no-repeat;mask-repeat:no-repeat;-webkit-mask-position:center;mask-position:center;transform-origin:50% 50%}
.sq-squished{position:absolute;left:50%;top:50%;font-weight:700;letter-spacing:.02em;white-space:nowrap;paint-order:stroke fill;line-height:1}
.sq-events{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:2px;font-size:12.5px}
.sq-events li{display:grid;grid-template-columns:42px 62px minmax(0,1fr);gap:6px;padding:4px 6px;border-radius:8px;align-items:baseline}
.sq-events li .t,.sq-events li .k{font-family:'IBM Plex Mono',monospace;font-size:11.5px}
.sq-events li .t{color:var(--muted)}
.sq-events li .v{line-height:1.35;overflow-wrap:anywhere}
.sq-events li.fired{background:var(--accent-soft)}
.sq-events li.skip{opacity:.38}
.sq-events li.anchor{display:block;margin-top:8px;font-weight:600;font-size:12px;color:var(--muted);padding:2px 6px}
.sq-events li.anchor span{font-family:'IBM Plex Mono',monospace;font-weight:500;color:var(--ink)}
.sq-measure{font-family:'IBM Plex Mono',monospace;font-size:12px;line-height:1.5;display:flex;flex-direction:column;gap:4px}
.sq-measure div{background:var(--panel);border:2px solid var(--line);border-radius:10px;padding:5px 8px}
.sq-measure:empty{display:none}
.sq-rules{font-size:12.5px;display:flex;flex-direction:column;gap:3px;line-height:1.35}
.sq-rules .ok{color:var(--good)} .sq-rules .bad{color:var(--bad);font-weight:600}
.sq-rules details summary{cursor:pointer;color:var(--muted)}
.sq-extra:empty{display:none}
.sq-slider{display:flex;flex-direction:column;gap:6px;font-size:13px}
.sq-slider input{width:100%;accent-color:var(--ink)}
.sq-slider b{font-family:'IBM Plex Mono',monospace;font-weight:500}
@media (max-width:1180px){.sq-app{grid-template-columns:236px minmax(0,1fr);grid-template-rows:minmax(0,1fr) 36vh}.sq-time{grid-column:1/-1;border-left:0;border-top:2px solid var(--line)}}
@media (max-width:760px){.sq-app{position:static;display:flex;flex-direction:column}.sq-main{height:62vh}.sq-side,.sq-time{border:0}}
`;

window.SquishyFX = function (THREE, CONFIG, hooks) {
  const V = CONFIG.viewer, FX = CONFIG.fx, RULES = CONFIG.rules, RM = CONFIG.reduceMotion, PH = CONFIG.phone;
  const KIT = (window.SQUISHY_KIT || {}).pictures || {};
  const DEG = Math.PI / 180, TAU = Math.PI * 2;
  const UP = new THREE.Vector3(0, 1, 0), ZAX = new THREE.Vector3(0, 0, 1), ORIGIN = new THREE.Vector3();
  const viewKeys = Object.keys(CONFIG.views);
  const S = { preview: 1, phone: false, reduce: false, view: viewKeys[0], moment: null, t: 0, world: 0, clock: 0, hitstop: 0, slow: null, timeScale: 1, lastFlash: -Infinity, queue: [], signals: {}, ready: false };
  const live = { parts: [], emitters: [], rings: [], pops: [], trails: [], ghosts: [], ghostQ: [], lights: [], ui: [], shakes: [], fovs: [], punches: [], dips: [] };
  const actors = [], tex = {}, rowsByEv = new Map(), anchorEls = {}, expanded = new Map(), keyedCache = new WeakMap();

  // ---------- shell ----------
  const ui = V.ui;
  const style = document.createElement('style');
  style.textContent = `:root{--bg:${ui.bg};--panel:${ui.panel};--ink:${ui.ink};--muted:${ui.muted};--line:${ui.line};--accent:${ui.accent};--accent-soft:${ui.accentSoft};--accent-ink:${ui.accentInk};--good:${ui.good};--bad:${ui.bad};--stage:${ui.stage}}` + CSS;
  document.head.appendChild(style);
  const file = (location.pathname.split('/').pop() || '').toLowerCase();
  const app = document.createElement('div');
  app.className = 'sq-app';
  app.innerHTML = `
    <aside class="sq-side">
      <div class="sq-brand">Squishy Duels <span>game-feel &amp; VFX spec</span></div>
      <nav class="sq-nav">${NAV.map(n => `<a href="${n[0]}" class="${n[0] === file || n[0] === CONFIG.page.file ? 'on' : ''}">${n[1]}</a>`).join('')}</nav>
      <div><h1>${esc(CONFIG.page.title)}</h1><p class="sq-sub">${esc(CONFIG.page.subtitle)}</p></div>
      <section><div class="sq-label">Moments <em>click = replay · R</em></div><div id="sq-moments" class="sq-col"></div></section>
      <section><div class="sq-label">Camera</div><div id="sq-views" class="sq-row"></div></section>
      <section><div class="sq-label">Preview</div><div id="sq-toggles" class="sq-col"></div></section>
      <section id="sq-extra" class="sq-extra"></section>
    </aside>
    <main class="sq-main"><div id="sq-viewport"><div id="sq-overlay"></div><div id="sq-hud"></div><div id="sq-viewlabel"></div><div id="sq-sfx"></div></div></main>
    <aside class="sq-time">
      <div><div class="sq-label">Timeline <em>real seconds</em></div><h2 id="sq-mname"></h2></div>
      <p id="sq-mnote" class="sq-sub"></p>
      <div id="sq-measure" class="sq-measure"></div>
      <ol id="sq-events" class="sq-events"></ol>
      <section><div class="sq-label">Rules check</div><div id="sq-rules" class="sq-rules"></div></section>
    </aside>`;
  document.body.appendChild(app);
  const $ = id => app.querySelector('#' + id);
  const el = { viewport: $('sq-viewport'), overlay: $('sq-overlay'), hud: $('sq-hud'), viewlabel: $('sq-viewlabel'), sfx: $('sq-sfx'), moments: $('sq-moments'), views: $('sq-views'), toggles: $('sq-toggles'), extra: $('sq-extra'), mname: $('sq-mname'), mnote: $('sq-mnote'), events: $('sq-events'), rules: $('sq-rules'), measure: $('sq-measure') };

  // ---------- three ----------
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, V.render.maxPixelRatio));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  el.viewport.prepend(renderer.domElement);
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(V.colors.sky);
  scene.fog = new THREE.Fog(V.colors.sky, V.render.fogNear, V.render.fogFar);
  const camera = new THREE.PerspectiveCamera(CONFIG.world.fov, 1, V.render.near, V.render.far);
  scene.add(new THREE.HemisphereLight(V.colors.hemiSky, V.colors.hemiGround, V.light.hemi));
  const sun = new THREE.DirectionalLight(V.colors.sun, V.light.sun);
  sun.castShadow = true;
  sun.shadow.mapSize.set(V.light.shadowMap, V.light.shadowMap);
  sun.shadow.bias = V.light.shadowBias;
  const sc = sun.shadow.camera;
  sc.left = -V.light.shadowExtent; sc.right = V.light.shadowExtent; sc.top = V.light.shadowExtent; sc.bottom = -V.light.shadowExtent;
  sc.near = V.light.shadowNear; sc.far = V.light.shadowFar;
  scene.add(sun, sun.target);
  let skyDome = null;
  if (V.sky && V.sky.top) {   // optional gradient sky dome (pages that build their own leave V.sky.top unset)
    const sk = V.sky;
    const mat = new THREE.ShaderMaterial({ name: 'sky', side: THREE.BackSide, depthWrite: false, fog: false,
      uniforms: { top: { value: new THREE.Color(sk.top) }, horizon: { value: new THREE.Color(sk.horizon) }, power: { value: sk.power } },
      vertexShader: `varying vec3 vDir;
void main() { vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
      fragmentShader: `uniform vec3 top;
uniform vec3 horizon;
uniform float power;
varying vec3 vDir;
void main() {
  gl_FragColor = vec4(mix(horizon, top, pow(clamp(vDir.y, 0.0, 1.0), power)), 1.0);
  #include <colorspace_fragment>
}` });
    skyDome = new THREE.Mesh(new THREE.SphereGeometry(sk.radius, sk.segments, sk.segments / 2), mat);
    skyDome.name = 'Sky (preview)'; skyDome.renderOrder = -1; skyDome.frustumCulled = false; scene.add(skyDome);
    scene.background = null; scene.fog.color.set(sk.horizon);
  }
  const lightPool = [];
  for (let i = 0; i < V.light.pointPool; i++) { const l = new THREE.PointLight(0xffffff, 0, 1, V.light.pointDecay); l.name = 'EffectLight'; scene.add(l); lightPool.push(l); }
  function setFocus(v) {
    sun.position.set(v.x + V.light.sunOffset[0], v.y + V.light.sunOffset[1], v.z + V.light.sunOffset[2]);
    sun.target.position.copy(v);
  }
  function resize() {
    const r = el.viewport.getBoundingClientRect();
    if (!r.width || !r.height) return;
    renderer.setSize(r.width, r.height, false);
    camera.aspect = r.width / r.height;
    camera.updateProjectionMatrix();
  }
  new ResizeObserver(resize).observe(el.viewport);

  // ---------- helpers ----------
  const colorCache = {};
  function col(hex) { return colorCache[hex] || (colorCache[hex] = new THREE.Color(hex)); }
  function seqColor(s, u, out) {
    if (typeof s === 'string') return out.copy(col(s));
    if (!s) return out.setRGB(1, 1, 1);
    if (u <= s[0][0]) return out.copy(col(s[0][1]));
    for (let i = 1; i < s.length; i++) if (u <= s[i][0]) { const a = s[i - 1], b = s[i]; return out.copy(col(a[1])).lerp(col(b[1]), (u - a[0]) / ((b[0] - a[0]) || 1)); }
    return out.copy(col(s[s.length - 1][1]));
  }
  function count(c) { return Array.isArray(c) ? c[S.phone ? 1 : 0] : c; }
  function material(name, hex, rough, metal) { return new THREE.MeshStandardMaterial({ name, color: hex, roughness: rough, metalness: metal || 0 }); }
  function checker(a, b, repeat) {
    const c = document.createElement('canvas'), n = V.ground.checkerPx;
    c.width = c.height = n * 2;
    const g = c.getContext('2d');
    g.fillStyle = a; g.fillRect(0, 0, n * 2, n * 2);
    g.fillStyle = b; g.fillRect(0, 0, n, n); g.fillRect(n, n, n, n);
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(repeat / 2, repeat / 2);
    t.magFilter = THREE.NearestFilter; t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = renderer.capabilities.getMaxAnisotropy();
    return t;
  }
  function perp(d) { const a = Math.abs(d.y) < V.fx.upTest ? UP : ZAX; return new THREE.Vector3().crossVectors(d, a).normalize(); }
  function randUnit() { const z = Math.random() * 2 - 1, a = Math.random() * TAU, r = Math.sqrt(1 - z * z); return new THREE.Vector3(r * Math.cos(a), z, r * Math.sin(a)); }
  function spreadDir(dir, sp) {
    const sx = sp ? sp[0] : 0, sy = sp ? sp[1] : 0;
    if (sx >= 180 && sy >= 180) return randUnit();
    const a1 = perp(dir), a2 = new THREE.Vector3().crossVectors(dir, a1).normalize();
    return dir.clone().applyAxisAngle(a1, (Math.random() * 2 - 1) * sx * DEG).applyAxisAngle(a2, (Math.random() * 2 - 1) * sy * DEG).normalize();
  }
  function faceQuat(dir, up) {
    const m = new THREE.Matrix4().lookAt(ORIGIN, dir, up || UP);
    return new THREE.Quaternion().setFromRotationMatrix(m);
  }

  // ---------- kit textures ----------
  function loadKit() {
    return Promise.all(Object.keys(KIT).map(k => new Promise(res => {
      const img = new Image();
      img.onload = () => {
        const c = document.createElement('canvas'); c.width = c.height = V.fx.textureSize;
        c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
        const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.name = k; tex[k] = t; res();
      };
      img.onerror = () => res();
      img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(KIT[k]);
    })));
  }
  function maskEl(name, color) {
    const d = document.createElement('div'); d.className = 'sq-img';
    const url = `url("data:image/svg+xml;charset=utf-8,${encodeURIComponent(KIT[name] || '')}")`;
    d.style.webkitMaskImage = url; d.style.maskImage = url; d.style.background = color;
    return d;
  }

  // ---------- avatar (blocky R15 stand-in) ----------
  const Z3 = [0, 0, 0];
  function zeroPose() { const p = {}; for (const k of POSE_KEYS) p[k] = [0, 0, 0]; return p; }
  function copyPose(a, out) { for (const k of POSE_KEYS) { out[k][0] = a[k][0]; out[k][1] = a[k][1]; out[k][2] = a[k][2]; } return out; }
  function blendPose(a, b, w, out) {
    for (const k of POSE_KEYS) for (let i = 0; i < 3; i++) {
      out[k][i] = k === 'RootPos' ? a[k][i] + (b[k][i] - a[k][i]) * w : a[k][i] + wrap180(b[k][i] - a[k][i]) * w;
    }
    return out;
  }
  function keyedSet(def) {
    let s = keyedCache.get(def);
    if (!s) { s = new Set(); for (const k of def.Keys) for (const j of POSE_KEYS) if (k[j]) s.add(j); keyedCache.set(def, s); }
    return s;
  }
  function evalTrack(def, t, base, out) {
    const keys = def.Keys, set = keyedSet(def);
    let i = 0; while (i < keys.length - 1 && t >= keys[i + 1].t) i++;
    const a = keys[i], b = keys[Math.min(i + 1, keys.length - 1)];
    const u = b === a ? 1 : ease(a.Easing || 'Linear', (t - a.t) / (b.t - a.t));
    for (const j of POSE_KEYS) {
      const o = out[j];
      if (!set.has(j)) { o[0] = base[j][0]; o[1] = base[j][1]; o[2] = base[j][2]; continue; }
      const va = a[j] || Z3, vb = b[j] || Z3;
      for (let k = 0; k < 3; k++) o[k] = va[k] + (vb[k] - va[k]) * u;
    }
    return out;
  }
  function basePose(av, out) {
    for (const k of POSE_KEYS) { out[k][0] = 0; out[k][1] = 0; out[k][2] = 0; }
    const L = V.loco;
    if (av.loco === 'run') {
      const s = Math.sin(av.phase), c = Math.cos(av.phase);
      out.LeftHip[0] = L.hip * s; out.RightHip[0] = -L.hip * s;
      out.LeftKnee[0] = -L.knee * (1 - s) / 2; out.RightKnee[0] = -L.knee * (1 + s) / 2;
      out.LeftShoulder[0] = -L.shoulder * s; out.RightShoulder[0] = L.shoulder * s;
      out.LeftElbow[0] = L.elbow; out.RightElbow[0] = L.elbow;
      out.Waist[1] = L.twist * s; out.Root[0] = L.lean;
      out.RootPos[1] = L.bob * Math.abs(c);
    } else if (av.loco === 'air') {
      out.LeftShoulder[0] = L.airShoulder; out.RightShoulder[0] = L.airShoulder;
      out.LeftShoulder[2] = -L.airSpread; out.RightShoulder[2] = L.airSpread;
      out.LeftKnee[0] = -L.airKnee; out.RightKnee[0] = -L.airKnee;
    }
    return out;
  }
  function makeAvatar(opts) {
    const r = V.rig, name = opts.name, colors = opts.colors;
    const group = new THREE.Group(); group.name = name;
    const ink = new THREE.MeshBasicMaterial({ name: name + '_ink', color: V.colors.ink, side: THREE.BackSide });
    const eyeMat = new THREE.MeshBasicMaterial({ name: name + '_eyes', color: V.colors.ink });
    const mats = {};
    const matFor = k => mats[k] || (mats[k] = new THREE.MeshStandardMaterial({ name: name + '_' + k, color: colors[k], roughness: V.material.avatarRoughness, metalness: 0 }));
    const joints = {}, parts = {}, bodyParts = [];
    const rootPos = new THREE.Group(); rootPos.name = 'RootPos'; group.add(rootPos);
    const piv = (n, parent, x, y, z) => { const o = new THREE.Group(); o.name = n; o.position.set(x, y, z); parent.add(o); joints[n] = o; return o; };
    const box = (n, parent, w, h, d, x, y, z, ck) => {
      const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), matFor(ck)); m.name = n; m.position.set(x, y, z); m.castShadow = true; m.receiveShadow = true; parent.add(m);
      const t = V.material.outline, o = new THREE.Mesh(m.geometry, ink); o.name = n + 'Outline'; o.scale.set((w + 2 * t) / w, (h + 2 * t) / h, (d + 2 * t) / d); m.add(o);
      parts[n] = m; bodyParts.push(m); return m;
    };
    const legH = r.footH + r.lowerLegH + r.upperLegH;
    const root = piv('Root', rootPos, 0, legH + r.lowerTorsoH / 2, 0);
    box('LowerTorso', root, r.torsoW, r.lowerTorsoH, r.torsoD, 0, 0, 0, 'legs');
    const waist = piv('Waist', root, 0, r.lowerTorsoH / 2, 0);
    box('UpperTorso', waist, r.torsoW, r.upperTorsoH, r.torsoD, 0, r.upperTorsoH / 2, 0, 'torso');
    const neck = piv('Neck', waist, 0, r.upperTorsoH, 0);
    const head = box('Head', neck, r.headSize, r.headSize, r.headSize, 0, r.headSize / 2, 0, 'head');
    for (const s of [-1, 1]) {
      const e = new THREE.Mesh(new THREE.BoxGeometry(r.eye[0], r.eye[1], r.eye[2]), eyeMat); e.name = 'Eye';
      e.position.set(s * r.eyeSpacing, r.eyeY, -r.headSize / 2); head.add(e);
    }
    for (const side of ['Left', 'Right']) {
      const sx = side === 'Left' ? -1 : 1;
      const sh = piv(side + 'Shoulder', waist, sx * (r.torsoW / 2 + r.limbW / 2), r.upperTorsoH - r.limbW / 2, 0);
      box(side + 'UpperArm', sh, r.limbW, r.upperArmH, r.limbD, 0, -(r.upperArmH / 2 - r.limbW / 2), 0, 'arms');
      const elb = piv(side + 'Elbow', sh, 0, -(r.upperArmH - r.limbW / 2), 0);
      box(side + 'LowerArm', elb, r.limbW, r.lowerArmH, r.limbD, 0, -r.lowerArmH / 2, 0, 'arms');
      const wr = piv(side + 'Wrist', elb, 0, -r.lowerArmH, 0);
      box(side + 'Hand', wr, r.limbW, r.handH, r.limbD, 0, -r.handH / 2, 0, 'head');
      const hip = piv(side + 'Hip', root, sx * r.torsoW / 4, -r.lowerTorsoH / 2, 0);
      box(side + 'UpperLeg', hip, r.limbW, r.upperLegH, r.limbD, 0, -r.upperLegH / 2, 0, 'legs');
      const kn = piv(side + 'Knee', hip, 0, -r.upperLegH, 0);
      box(side + 'LowerLeg', kn, r.limbW, r.lowerLegH, r.limbD, 0, -r.lowerLegH / 2, 0, 'legs');
      const an = piv(side + 'Ankle', kn, 0, -r.lowerLegH, 0);
      box(side + 'Foot', an, r.limbW, r.footH, r.footD, 0, -r.footH / 2, -(r.footD - r.limbD) / 2, 'shoes');
    }
    const TMP = zeroPose();
    const av = {
      kind: 'avatar', name, group, joints, parts, bodyParts, mats, ink, rootPos,
      loco: 'idle', phase: 0, track: null, glow: null, pose: zeroPose(), base: zeroPose(),
      play(def) { this.track = { def, t0: S.world, from: copyPose(this.pose, zeroPose()) }; },
      stop() { this.track = null; },
      reset() { this.track = null; this.glow = null; this.loco = 'idle'; this.phase = 0; this.setGlow(0, null); this.group.visible = true; },
      setFirstPerson(on) { for (const n of V.rig.firstPersonHidden) parts[n].visible = !on; },
      setGlow(fill, outline) {
        for (const k in mats) { mats[k].emissive.copy(fill > 0 && this.glow ? col(this.glow.def.FillColor) : col(V.colors.black)); mats[k].emissiveIntensity = fill; }
        ink.color.copy(outline || col(V.colors.ink));
      },
      update(dtW, dtR) {
        basePose(this, this.base);
        if (this.track) {
          const tr = this.track, d = tr.def, t = S.world - tr.t0, end = d.Keys[d.Keys.length - 1].t;
          evalTrack(d, Math.min(t, end), this.base, TMP);
          if (d.FadeIn && t < d.FadeIn) blendPose(tr.from, TMP, ease('Sine InOut', t / d.FadeIn), this.pose);
          else if (t > end && d.FadeOut != null) {
            const w = (t - end) / d.FadeOut;
            blendPose(TMP, this.base, ease('Sine InOut', w), this.pose);
            if (w >= 1) this.track = null;
          } else copyPose(TMP, this.pose);
        } else copyPose(this.base, this.pose);
        for (const j of JOINTS) { const a = this.pose[j]; joints[j].rotation.set(a[0] * DEG, a[1] * DEG, a[2] * DEG, 'XYZ'); }
        rootPos.position.set(this.pose.RootPos[0], this.pose.RootPos[1], this.pose.RootPos[2]);
        updateGlow(this, dtR);
      }
    };
    actors.push(av);
    return av;
  }
  const _gc = new THREE.Color();
  function updateGlow(a, dtR) {
    if (!a.glow) return;
    const d = a.glow.def; a.glow.age += dtR;
    const e = ease(d.Easing, a.glow.age / d.Time);
    _gc.copy(col(d.OutlineColor)).lerp(col(V.colors.ink), Math.min(1, d.OutlineTransparencyStart + (1 - d.OutlineTransparencyStart) * e));
    a.setGlow((1 - d.FillTransparencyStart) * (1 - e) * V.material.glowScale, _gc);
    if (a.glow.age >= d.Time) { a.glow = null; a.setGlow(0, null); }
  }

  // ---------- squishy (soft blob stand-in) ----------
  function makeSquishy(opts) {
    const Q = V.squishy, r = opts.radius;
    const group = new THREE.Group(); group.name = opts.name;
    const orient = new THREE.Group(); orient.name = 'Orient'; group.add(orient);
    const spin = new THREE.Group(); spin.name = 'Spin'; orient.add(spin);
    const scaleN = new THREE.Group(); scaleN.name = 'SquashStretch'; spin.add(scaleN);
    const mat = new THREE.MeshStandardMaterial({ name: opts.name + '_jelly', color: opts.color, roughness: Q.roughness, metalness: 0 });
    const body = new THREE.Mesh(new THREE.SphereGeometry(1, Q.segments, Q.rings), mat);
    body.name = 'Body'; body.scale.set(r, r * Q.restSquash, r); body.castShadow = true; scaleN.add(body);
    const ink = new THREE.MeshBasicMaterial({ name: opts.name + '_ink', color: V.colors.ink, side: THREE.BackSide });
    const hull = new THREE.Mesh(body.geometry, ink); hull.name = 'BodyOutline'; hull.scale.setScalar(1 + Q.outline / r); body.add(hull);
    const eyeMat = new THREE.MeshBasicMaterial({ name: opts.name + '_eyes', color: V.colors.ink });
    const shineMat = new THREE.MeshBasicMaterial({ name: opts.name + '_shine', color: V.colors.white });
    const onSurface = (x, y) => new THREE.Vector3(x, y, -Math.sqrt(Math.max(0, 1 - x * x - y * y))).multiply(new THREE.Vector3(r, r * Q.restSquash, r));
    for (const s of [-1, 1]) {
      const e = new THREE.Mesh(new THREE.SphereGeometry(Q.eyeSize * r, Q.eyeSeg, Q.eyeSeg), eyeMat); e.name = 'Eye';
      e.position.copy(onSurface(s * Q.eyeX, Q.eyeY)); scaleN.add(e);
    }
    const sh = new THREE.Mesh(new THREE.SphereGeometry(Q.shineSize * r, Q.eyeSeg, Q.eyeSeg), shineMat); sh.name = 'Shine';
    sh.position.copy(onSurface(Q.shine[0], Q.shine[1])); scaleN.add(sh);
    const sq = {
      kind: 'squishy', name: opts.name, group, orient, spin, scaleN, mats: { jelly: mat }, ink, radius: r,
      track: null, wobble: null, glow: null, spinRate: 0, spinAngle: 0, base: [1, 1, 1],
      squash(def) { this.track = { def, t0: S.world }; },
      setWobble(def) { this.wobble = def ? { def, t0: S.world } : null; },
      face(dir, up) { if (dir.lengthSq() > 0) this.orient.quaternion.copy(faceQuat(dir.clone().normalize(), up)); },
      reset() { this.track = null; this.wobble = null; this.glow = null; this.spinRate = 0; this.spinAngle = 0; this.base = [1, 1, 1]; this.setGlow(0, null); this.group.visible = true; this.scaleN.scale.set(1, 1, 1); this.spin.rotation.set(0, 0, 0); },
      setGlow(fill, outline) {
        mat.emissive.copy(fill > 0 && this.glow ? col(this.glow.def.FillColor) : col(V.colors.black)); mat.emissiveIntensity = fill;
        ink.color.copy(outline || col(V.colors.ink));
      },
      update(dtW, dtR) {
        let sx = this.base[0], sy = this.base[1], sz = this.base[2];
        if (this.track) {
          const d = this.track.def, keys = d.Keys, t = S.world - this.track.t0;
          let i = 0; while (i < keys.length - 1 && t >= keys[i + 1][0]) i++;
          const a = keys[i], b = keys[Math.min(i + 1, keys.length - 1)];
          const u = a === b ? 1 : ease(a[4] || 'Linear', (t - a[0]) / (b[0] - a[0]));
          sx *= a[1] + (b[1] - a[1]) * u; sy *= a[2] + (b[2] - a[2]) * u; sz *= a[3] + (b[3] - a[3]) * u;
          if (t > keys[keys.length - 1][0] && !d.Hold) this.track = null;
        }
        if (this.wobble) {
          const d = this.wobble.def, t = S.world - this.wobble.t0;
          const k = d.Amplitude * Math.exp(-d.Decay * t) * Math.sin(TAU * d.Frequency * t);
          sx *= 1 + k; sz *= 1 + k; sy *= 1 - k * d.AxisRatio;
          if (t > d.Time) this.wobble = null;
        }
        this.spinAngle += this.spinRate * DEG * dtW;
        this.spin.rotation.z = this.spinAngle;
        this.scaleN.scale.set(sx, sy, sz);
        updateGlow(this, dtR);
      }
    };
    actors.push(sq);
    return sq;
  }

  // ---------- particles (Roblox ParticleEmitter look-alike) ----------
  const spritePool = [];
  const _p = new THREE.Vector3(), _q = new THREE.Vector3();
  function getSprite() {
    let s = spritePool.pop();
    if (!s) s = new THREE.Sprite(new THREE.SpriteMaterial({ transparent: true, depthWrite: false, toneMapped: false, fog: false }));
    s.visible = true; scene.add(s); return s;
  }
  function emitOne(def, tint, pos, dir, vel, lock) {
    if (live.parts.length >= V.fx.maxSprites) return;
    const s = getSprite(), m = s.material;
    if (m.map !== tex[def.Texture]) { m.map = tex[def.Texture] || null; m.needsUpdate = true; }
    const blend = (def.LightEmission || 0) >= V.fx.additiveFrom ? THREE.AdditiveBlending : THREE.NormalBlending;
    if (m.blending !== blend) { m.blending = blend; m.needsUpdate = true; }
    const o = pos.clone(); let d = dir.clone();
    const shape = def.Shape || 'Point';
    if (shape === 'Sphere') { const n = randUnit(); o.addScaledVector(n, def.ShapeRadius || 0); d = def.ShapeInOut === 'Inward' ? n.clone().negate() : n; }
    else if (shape === 'Cylinder') {
      const a1 = perp(dir), a2 = new THREE.Vector3().crossVectors(dir, a1).normalize(), a = Math.random() * TAU;
      const n = a1.multiplyScalar(Math.cos(a)).addScaledVector(a2, Math.sin(a)); o.addScaledVector(n, def.ShapeRadius || 0); d = n;
    } else if (shape === 'Box') { const b = def.ShapeSize; o.x += (Math.random() - 0.5) * b[0]; o.y += (Math.random() - 0.5) * b[1]; o.z += (Math.random() - 0.5) * b[2]; }
    d = spreadDir(d, def.SpreadAngle);
    const p = { s, def, tint, age: 0, life: rr(def.Lifetime), pos: o, vel: d.multiplyScalar(rr(def.Speed)), rot: rr(def.Rotation), rotSpeed: rr(def.RotSpeed) };
    if (vel && def.VelocityInheritance) p.vel.addScaledVector(vel, def.VelocityInheritance);
    if (lock && def.LockedToPart) { p.lock = lock; p.local = o.clone().sub(pos); }
    live.parts.push(p);
    updateParticle(p, 0);
  }
  function burst(def, pos, dir, vel, lock) {
    if (!def) return;
    const tints = def.Tints || [null], per = Math.max(1, Math.round(count(def.Count) / tints.length));
    for (const tint of tints) for (let i = 0; i < per; i++) emitOne(def, tint, pos, dir, vel, lock);
  }
  function updateParticle(p, dt) {
    const d = p.def;
    p.age += dt;
    if (dt > 0) {
      if (d.Drag) p.vel.multiplyScalar(Math.pow(2, -d.Drag * dt));
      if (d.Acceleration) { p.vel.x += d.Acceleration[0] * dt; p.vel.y += d.Acceleration[1] * dt; p.vel.z += d.Acceleration[2] * dt; }
      (p.lock ? p.local : p.pos).addScaledVector(p.vel, dt);
      p.rot += p.rotSpeed * dt;
    }
    if (p.lock) p.pos.copy(resolveAnchor(p.lock.ev, p.lock.data).pos).add(p.local);
    const u = clamp01(p.age / p.life), size = seqN(d.Size, u), sq = seqN(d.Squash, u), k = 1 + Math.abs(sq);
    p.s.position.copy(p.pos);
    p.s.scale.set(sq >= 0 ? size / k : size * k, sq >= 0 ? size * k : size / k, 1);
    const m = p.s.material;
    if (p.tint) m.color.copy(col(p.tint)); else seqColor(d.Color, u, m.color);
    m.opacity = 1 - clamp01(seqN(d.Transparency, u));
    if (d.Orientation === 'VelocityParallel') {
      _p.copy(p.pos).project(camera); _q.copy(p.pos).addScaledVector(p.vel, V.fx.velocityProbe).project(camera);
      m.rotation = Math.atan2(_q.y - _p.y, (_q.x - _p.x) * camera.aspect) - Math.PI / 2;
    } else m.rotation = p.rot * DEG;
    return p.age < p.life;
  }
  function startEmitter(def, ev, data) {
    live.emitters.push({ def, ev, data, name: ev.emit, acc: 0, until: S.world + (ev.for != null ? ev.for : Infinity) });
  }
  function stopNamed(name) {
    for (const e of live.emitters) if (e.name === name || e.ev.group === name) e.until = S.world;
    for (const t of live.trails) if (t.name === name || (t.ev && t.ev.group === name)) t.until = S.world;
  }

  // ---------- rings / billboards / trails / afterimages / lights ----------
  const ringGeo = new THREE.PlaneGeometry(1, 1);
  function ring(def, pos, normal, lock) {
    const mat = new THREE.MeshBasicMaterial({ map: tex[def.Texture || 'ring'], color: def.Color, transparent: true, depthWrite: false, side: THREE.DoubleSide, toneMapped: false, fog: false, blending: (def.LightEmission || 0) >= V.fx.additiveFrom ? THREE.AdditiveBlending : THREE.NormalBlending });
    const m = new THREE.Mesh(ringGeo, mat); m.name = 'Ring';
    m.position.copy(pos); m.quaternion.setFromUnitVectors(ZAX, normal.clone().normalize());
    scene.add(m);
    const r = { def, m, age: 0, lock: def.Follow ? lock : null }; live.rings.push(r); updateRing(r, 0);
  }
  function updateRing(r, dt) {
    const d = r.def; r.age += dt;
    if (r.lock) r.m.position.copy(resolveAnchor(r.lock.ev, r.lock.data).pos);
    const u = r.age / d.Time;
    const s = d.SizeStart + (d.SizeEnd - d.SizeStart) * ease(d.Easing, u);
    r.m.scale.set(s, s, 1);
    r.m.material.opacity = 1 - (d.TransparencyStart + (d.TransparencyEnd - d.TransparencyStart) * ease(d.TransparencyEasing || 'Linear', u));
    return u < 1;
  }
  const _off = new THREE.Vector3();
  function textTexture(text, def) {
    const T = V.textBillboard, c = document.createElement('canvas'); c.width = T.w; c.height = T.h;
    const g = c.getContext('2d'); g.font = `700 ${T.font}px Fredoka, sans-serif`; g.textAlign = 'center'; g.textBaseline = 'middle'; g.lineJoin = 'round';
    g.lineWidth = T.stroke; g.strokeStyle = def.Stroke; g.strokeText(text, T.w / 2, T.h / 2);
    g.fillStyle = def.Color; g.fillText(text, T.w / 2, T.h / 2);
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
  }
  function pop(def, pos, lock, data) {
    const text = def.Kind === 'Text' ? String(def.Text != null ? def.Text : (data && data.text) || '') : null;
    const map = text != null ? textTexture(text, def) : tex[def.Texture];
    const s = new THREE.Sprite(new THREE.SpriteMaterial({ map, color: text != null ? V.colors.white : def.Color, transparent: true, depthWrite: false, depthTest: !def.AlwaysOnTop, toneMapped: false, fog: false }));
    s.renderOrder = V.fx.popRenderOrder; s.name = 'Billboard'; scene.add(s);
    const p = { def, s, age: 0, rot: rr(def.Rotation), base: pos.clone(), lock: def.Follow ? lock : null, aspect: text != null ? V.textBillboard.w / V.textBillboard.h : 1, own: text != null ? map : null };
    live.pops.push(p); updatePop(p, 0);
  }
  function updatePop(p, dt) {
    const d = p.def; p.age += dt;
    p.s.position.copy(p.lock ? resolveAnchor(p.lock.ev, p.lock.data).pos : p.base);
    if (d.Offset) p.s.position.add(_off.fromArray(d.Offset));
    const size = seqN(d.Size, p.age); p.s.scale.set(size * p.aspect, size, 1);
    p.s.material.opacity = 1 - clamp01(seqN(d.Transparency, p.age));
    p.s.material.rotation = (p.rot + (d.RotSpeed || 0) * p.age) * DEG;
    return p.age < d.Time;
  }
  function trailOn(def, ev, data) {
    const max = V.fx.trailMaxPoints, geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(max * 6), 3).setUsage(THREE.DynamicDrawUsage));
    geo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(max * 8), 4).setUsage(THREE.DynamicDrawUsage));
    const idx = []; for (let i = 0; i < max - 1; i++) { const a = i * 2; idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2); }
    geo.setIndex(idx); geo.setDrawRange(0, 0);
    const mat = new THREE.MeshBasicMaterial({ vertexColors: true, transparent: true, depthWrite: false, side: THREE.DoubleSide, toneMapped: false, fog: false, blending: (def.LightEmission || 0) >= V.fx.additiveFrom ? THREE.AdditiveBlending : THREE.NormalBlending });
    const mesh = new THREE.Mesh(geo, mat); mesh.frustumCulled = false; mesh.name = 'Trail'; scene.add(mesh);
    live.trails.push({ def, ev, data, pts: [], until: S.world + (ev.for != null ? ev.for : Infinity), mesh, geo, name: ev.trail, c: new THREE.Color() });
  }
  const _side = new THREE.Vector3(), _tan = new THREE.Vector3(), _view = new THREE.Vector3();
  function updateTrail(tr) {
    const d = tr.def, life = d.Lifetime * (S.phone ? PH.trailLifetimeScale : 1);
    if (S.world <= tr.until) {
      const a = resolveAnchor(tr.ev, tr.data), p = a.pos.clone(), head = tr.pts[0];
      if (!head || head.p.distanceTo(p) >= (d.MinLength || 0)) tr.pts.unshift({ p, t: S.world, side: a.side ? a.side.clone() : null });
      else { head.p.copy(p); head.t = S.world; }
    }
    while (tr.pts.length && S.world - tr.pts[tr.pts.length - 1].t > life) tr.pts.pop();
    if (tr.pts.length > V.fx.trailMaxPoints) tr.pts.length = V.fx.trailMaxPoints;
    const n = tr.pts.length, P = tr.geo.attributes.position.array, C = tr.geo.attributes.color.array;
    for (let i = 0; i < n; i++) {
      const pt = tr.pts[i], u = clamp01((S.world - pt.t) / life);
      _tan.subVectors(tr.pts[Math.max(i - 1, 0)].p, tr.pts[Math.min(i + 1, n - 1)].p);
      if (_tan.lengthSq() === 0) _tan.copy(UP);
      if (d.FaceCamera === false && pt.side) _side.copy(pt.side);
      else { _view.subVectors(camera.position, pt.p); _side.crossVectors(_tan, _view).normalize(); }
      const hw = (d.Width / 2) * seqN(d.WidthScale == null ? 1 : d.WidthScale, u);
      P[i * 6] = pt.p.x + _side.x * hw; P[i * 6 + 1] = pt.p.y + _side.y * hw; P[i * 6 + 2] = pt.p.z + _side.z * hw;
      P[i * 6 + 3] = pt.p.x - _side.x * hw; P[i * 6 + 4] = pt.p.y - _side.y * hw; P[i * 6 + 5] = pt.p.z - _side.z * hw;
      seqColor(d.Color, u, tr.c); const al = 1 - clamp01(seqN(d.Transparency, u));
      C[i * 8] = C[i * 8 + 4] = tr.c.r; C[i * 8 + 1] = C[i * 8 + 5] = tr.c.g; C[i * 8 + 2] = C[i * 8 + 6] = tr.c.b; C[i * 8 + 3] = C[i * 8 + 7] = al;
    }
    tr.geo.setDrawRange(0, Math.max(0, (n - 1) * 6));
    tr.geo.attributes.position.needsUpdate = true; tr.geo.attributes.color.needsUpdate = true;
    return n > 0 || S.world <= tr.until;
  }
  function afterimage(def, av) {
    const n = count(def.Count);
    for (let i = 0; i < n; i++) live.ghostQ.push({ def, av, at: S.world + i * def.Interval });
  }
  function spawnGhost(def, av) {
    av.group.updateWorldMatrix(true, true);
    const mat = new THREE.MeshBasicMaterial({ color: def.Color, transparent: true, depthWrite: false, toneMapped: false, opacity: 1 - def.TransparencyStart });
    const g = new THREE.Group(); g.name = 'Afterimage';
    for (const m of av.bodyParts) { const c = new THREE.Mesh(m.geometry, mat); c.matrixAutoUpdate = false; c.matrix.copy(m.matrixWorld); g.add(c); }
    scene.add(g); live.ghosts.push({ def, g, mat, age: 0 });
  }
  function light(def, pos) {
    const l = lightPool.find(x => !x.userData.busy); if (!l) return;
    l.userData.busy = true; l.color.set(def.Color); l.distance = def.Range; l.position.copy(pos);
    live.lights.push({ def, l, age: 0 });
  }

  // ---------- screen effects (ScreenGui look-alikes) ----------
  const flashEl = document.createElement('div'); flashEl.className = 'sq-flash'; el.overlay.appendChild(flashEl);
  function px() { return el.viewport.clientHeight / V.ui.refHeight; }
  function flash(def) {
    if (S.clock - S.lastFlash < 1 / RULES.maxFlashesPerSecond) return 'blocked (max 3/s)';
    S.lastFlash = S.clock;
    const scale = S.reduce ? RM.flash : 1;
    flashEl.style.background = def.Color;
    live.ui.push({ age: 0, update(dt) {
      this.age += dt; const a = this.age;
      const o = a < def.In ? a / def.In : 1 - clamp01((a - def.In) / def.Out);
      flashEl.style.opacity = o * def.Opacity * scale;
      if (a >= def.In + def.Out) { flashEl.style.opacity = 0; return false; } return true;
    }});
    return '';
  }
  function uiFx(def, data) {
    if (def.Kind === 'SquishedText') return uiSquished(def);
    if (def.Kind === 'EdgeSplat') return uiEdgeSplat(def, data);
    if (def.Kind === 'SpeedLines') return uiSpeedLines(def, data);
    if (def.Kind === 'Vignette') return uiVignette(def);
    if (def.Kind === 'Banner') return uiBanner(def, data);
    if (def.Kind === 'Letterbox') return uiLetterbox(def);
    if (def.Kind === 'Counter') return uiCounter(def);
  }
  let banner = null;
  function textEl(def, color) {
    const k = px(), d = document.createElement('div'); d.className = 'sq-squished';
    d.style.color = color; d.style.fontSize = def.FontPx * k + 'px'; d.style.webkitTextStroke = `${def.StrokePx * k}px ${def.Stroke}`;
    el.overlay.appendChild(d); return d;
  }
  function uiBanner(def, data) {
    if (banner) banner.kill();
    const d = textEl(def, (data && data.color) || def.Color); d.textContent = (data && data.text) || def.Text;
    const tEnd = def.In + def.Hold + def.Out;
    const item = { age: 0, dead: false, kill() { this.dead = true; d.remove(); }, update(dt) {
      if (this.dead) return false;
      this.age += dt; const a = this.age; let y = def.Y, op = 1, sc = 1;
      if (a < def.In) { const e = ease(def.InEasing, a / def.In); y = def.FromY + (def.Y - def.FromY) * e; sc = def.FromScale + (1 - def.FromScale) * e; }
      else if (a > def.In + def.Hold) { const e = ease(def.OutEasing, (a - def.In - def.Hold) / def.Out); y = def.Y + (def.FromY - def.Y) * e; op = 1 - e; }
      d.style.top = y * 100 + '%'; d.style.opacity = op; d.style.transform = `translate(-50%,-50%) scale(${sc})`;
      if (a >= tEnd) { d.remove(); if (banner === item) banner = null; return false; } return true;
    }};
    banner = item; live.ui.push(item); item.update(0);
  }
  function uiLetterbox(def) {
    const bars = [0, 1].map(i => { const b = document.createElement('div'); b.style.position = 'absolute'; b.style.left = '0'; b.style.right = '0'; b.style.height = def.Height * 100 + '%'; b.style[i ? 'bottom' : 'top'] = '0'; b.style.background = def.Color; el.overlay.appendChild(b); return b; });
    const tEnd = def.In + def.Hold + def.Out;
    const item = { age: 0, update(dt) {
      this.age += dt; const a = this.age;
      const v = clamp01(a < def.In ? ease(def.InEasing, a / def.In) : 1 - ease(def.OutEasing, (a - def.In - def.Hold) / def.Out));
      bars[0].style.transform = `translateY(${(v - 1) * 100}%)`; bars[1].style.transform = `translateY(${(1 - v) * 100}%)`;
      if (a >= tEnd) { bars.forEach(b => b.remove()); return false; } return true;
    }};
    live.ui.push(item); item.update(0);
  }
  function uiCounter(def) {
    const d = textEl(def, def.Color); d.style.top = def.Y * 100 + '%';
    let pulse = -1, last = '';
    const item = { update(dt) {
      const r = hooks.readout ? hooks.readout(api, def.Source) : null; if (!r) return true;
      const txt = Math.round(r.value).toLocaleString() + def.Suffix;
      if (txt !== last) { d.textContent = txt; last = txt; }
      if (r.done && pulse < 0) { pulse = 0; d.style.color = def.DoneColor; }
      let sc = 1;
      if (pulse >= 0) { pulse += dt; sc = 1 + (def.PulseScale - 1) * ease(def.PulseEasing, pulse / def.PulseTime); }
      d.style.transform = `translate(-50%,-50%) scale(${sc})`;
      return true;
    }};
    live.ui.push(item); item.update(0);
  }
  function uiSquished(def) {
    const k = px(), d = document.createElement('div'); d.className = 'sq-squished'; d.textContent = def.Text;
    d.style.color = def.Color; d.style.fontSize = def.FontPx * k + 'px';
    d.style.webkitTextStroke = `${def.StrokePx * k}px ${def.Stroke}`;
    el.overlay.appendChild(d);
    const t1 = def.PopTime, t2 = t1 + def.SettleTime, t3 = t2 + def.CenterHold, t4 = t3 + def.MoveTime, tEnd = t4 + def.Hold + def.FadeTime;
    live.ui.push({ age: 0, update(dt) {
      this.age += dt; const a = this.age; let sc = 1, y = 0.5, op = 1;
      if (a < t1) sc = def.PopScale * ease(def.PopEasing, a / def.PopTime);
      else if (a < t2) sc = def.PopScale + (1 - def.PopScale) * ease(def.SettleEasing, (a - t1) / def.SettleTime);
      else if (a < t3) sc = 1;
      else if (a < t4) { const e = ease(def.MoveEasing, (a - t3) / def.MoveTime); sc = 1 + (def.TopScale - 1) * e; y = 0.5 + (def.TopY - 0.5) * e; }
      else { sc = def.TopScale; y = def.TopY; op = 1 - clamp01((a - t4 - def.Hold) / def.FadeTime); }
      const tilt = def.TiltDeg * Math.sin(a * def.WobbleHz * TAU);
      d.style.top = y * 100 + '%'; d.style.opacity = op;
      d.style.transform = `translate(-50%,-50%) scale(${sc}) rotate(${tilt}deg)`;
      if (a >= tEnd) { d.remove(); return false; } return true;
    }});
  }
  function uiEdgeSplat(def, data) {
    const W = el.viewport.clientWidth, H = el.viewport.clientHeight, k = px();
    const side = (data && data.screenSide) || def.Side, n = count(def.Count), items = [];
    for (let i = 0; i < n; i++) {
      const e = maskEl(def.Texture, def.Color), size = rr(def.SizePx) * k, along = 0.5 + (Math.random() - 0.5) * def.Spread;
      let x, y;
      if (side === 'left') { x = def.Inset * W; y = along * H; } else if (side === 'right') { x = (1 - def.Inset) * W; y = along * H; }
      else if (side === 'top') { x = along * W; y = def.Inset * H; } else { x = along * W; y = (1 - def.Inset) * H; }
      e.style.width = e.style.height = size + 'px'; e.style.left = x - size / 2 + 'px'; e.style.top = y - size / 2 + 'px'; e.style.opacity = def.Opacity;
      el.overlay.appendChild(e); items.push({ e, rot: rr(def.Rotation), delay: i * def.Stagger });
    }
    const total = def.PopTime + def.Hold + def.FadeTime + def.Stagger * n;
    live.ui.push({ age: 0, update(dt) {
      this.age += dt;
      for (const it of items) {
        const a = this.age - it.delay; if (a < 0) { it.e.style.transform = 'scale(0)'; continue; }
        const s = ease(def.PopEasing, a / def.PopTime), f = clamp01((a - def.PopTime - def.Hold) / def.FadeTime);
        it.e.style.transform = `translateY(${ease('Quad In', f) * def.Drip * H}px) rotate(${it.rot}deg) scale(${s})`;
        it.e.style.opacity = def.Opacity * (1 - f);
      }
      if (this.age >= total) { items.forEach(it => it.e.remove()); return false; } return true;
    }});
  }
  function uiSpeedLines(def, data) {
    const W = el.viewport.clientWidth, H = el.viewport.clientHeight, k = px(), cx = W / 2, cy = H / 2, R = Math.hypot(cx, cy);
    const n = Math.round(count(def.Count) * (S.reduce ? RM.speedLines : 1)), items = [];
    for (let i = 0; i < n; i++) {
      const a = (i / n) * TAU + rr([-def.Jitter, def.Jitter]) * DEG, r0 = rr([def.Inner, def.Outer]) * R;
      const len = rr(def.LengthPx) * k, wid = rr(def.WidthPx) * k, e = maskEl(def.Texture, (data && data.color) || def.Color);
      e.style.width = wid + 'px'; e.style.height = len + 'px';
      el.overlay.appendChild(e); items.push({ e, a, r0, len, wid, delay: Math.random() * def.Stagger });
    }
    live.ui.push({ age: 0, update(dt) {
      this.age += dt;
      for (const it of items) {
        const u = clamp01((this.age - it.delay) / def.Time), r = it.r0 - def.Travel * R * ease(def.Easing, u);
        const x = cx + Math.cos(it.a) * r, y = cy + Math.sin(it.a) * r;
        it.e.style.left = x - it.wid / 2 + 'px'; it.e.style.top = y - it.len / 2 + 'px';
        it.e.style.transform = `rotate(${it.a / DEG - 90}deg)`;
        it.e.style.opacity = this.age < it.delay ? 0 : def.Opacity * (1 - ease(def.FadeEasing, u));
      }
      if (this.age >= def.Time + def.Stagger) { items.forEach(it => it.e.remove()); return false; } return true;
    }});
  }
  function uiVignette(def) {
    const d = document.createElement('div'); d.style.position = 'absolute'; d.style.inset = '0';
    d.style.background = `radial-gradient(ellipse at center, transparent ${def.ClearRadius * 100}%, ${def.Color} 100%)`;
    d.style.opacity = 0; el.overlay.appendChild(d);
    live.ui.push({ age: 0, update(dt) {
      this.age += dt; const a = this.age;
      const o = a < def.In ? ease('Quad Out', a / def.In) : 1 - ease('Quad In', (a - def.In - def.Hold) / def.Out);
      d.style.opacity = def.Opacity * clamp01(o);
      if (a >= def.In + def.Hold + def.Out) { d.remove(); return false; } return true;
    }});
  }
  function sound(name) {
    const d = document.createElement('div'); d.textContent = '♪ ' + name; el.sfx.prepend(d);
    while (el.sfx.children.length > V.ui.sfxMax) el.sfx.lastChild.remove();
    live.ui.push({ age: 0, update(dt) { this.age += dt; if (this.age > V.ui.sfxHold) d.style.opacity = 0; if (this.age > V.ui.sfxHold + V.ui.sfxFade) { d.remove(); return false; } return true; } });
  }

  // ---------- camera effects ----------
  function envelope(d, a, attack, hold, release, ea, er) {
    if (a < attack) return ease(ea, a / attack);
    if (a < attack + hold) return 1;
    return 1 - ease(er, (a - attack - hold) / release);
  }
  function camShake(def) {
    if (S.reduce && !RM.shake) return 'off (reduce motion)';
    live.shakes.push({ def, age: 0, ph: Array.from({ length: 6 }, () => Math.random() * TAU) });
    return '';
  }
  const camRot = [0, 0, 0], camOff = [0, 0, 0];
  function applyCamera(dtR) {
    const base = hooks.camera ? hooks.camera(api, S.view, dtR) : null;
    if (!base) return;
    camera.position.copy(base.pos); camera.up.copy(base.up || UP); camera.lookAt(base.look);
    camRot[0] = camRot[1] = camRot[2] = 0; camOff[0] = camOff[1] = camOff[2] = 0;
    let dip = 0, fov = base.fov || CONFIG.world.fov;
    for (const d of live.dips) dip += d.def.Depth * d.scale * envelope(d.def, d.age, d.def.Down, d.def.Hold || 0, d.def.Up, d.def.DownEasing, d.def.UpEasing);
    for (const p of live.punches) {
      const d = p.def, e = envelope(d, p.age, d.Attack, d.Hold || 0, d.Release, d.AttackEasing, d.ReleaseEasing) * (S.reduce ? RM.punch : 1);
      for (let i = 0; i < 3; i++) { camOff[i] += (d.Offset ? d.Offset[i] : 0) * e; camRot[i] += (d.Rotation ? d.Rotation[i] : 0) * e; }
    }
    for (const s of live.shakes) {
      const d = s.def, env = (1 - ease(d.Easing, s.age / d.Time)) * d.Amplitude * (S.reduce ? RM.shake : 1), w = TAU * d.Frequency * s.age, N = V.shakeNoise;
      for (let i = 0; i < 3; i++) camRot[i] += env * d.Axes[i] * (N[0] * Math.sin(w + s.ph[i]) + N[1] * Math.sin(w * N[2] + s.ph[i + 3]));
    }
    for (const f of live.fovs) fov += f.def.Delta * envelope(f.def, f.age, f.def.Attack, f.def.Hold || 0, f.def.Release, f.def.AttackEasing, f.def.ReleaseEasing) * (S.reduce ? RM.fovKick : 1);
    camera.position.y -= dip * (S.reduce ? RM.dip : 1);
    camera.translateX(camOff[0]); camera.translateY(camOff[1]); camera.translateZ(camOff[2]);
    camera.rotateX(camRot[0] * DEG); camera.rotateY(camRot[1] * DEG); camera.rotateZ(camRot[2] * DEG);
    if (Math.abs(camera.fov - fov) > 1e-4) { camera.fov = fov; camera.updateProjectionMatrix(); }
  }
  function slowScale(dtR) {
    if (!S.slow) return 1;
    const s = S.slow, d = s.def; s.age += dtR; const a = s.age;
    if (a < d.In) return 1 + (d.Speed - 1) * ease(d.InEasing, a / d.In);
    if (a < d.In + d.Hold) return d.Speed;
    if (a < d.In + d.Hold + d.Out) return d.Speed + (1 - d.Speed) * ease(d.OutEasing, (a - d.In - d.Hold) / d.Out);
    S.slow = null; return 1;
  }

  // ---------- orbit (drag to look around) ----------
  const orbits = {};
  function orbit(key, target, d) {
    const o = orbits[key] || (orbits[key] = { az: d.az, el: d.el, dist: d.dist, d });
    const az = o.az * DEG, elv = o.el * DEG;
    const pos = new THREE.Vector3(target.x + Math.sin(az) * Math.cos(elv) * o.dist, target.y + Math.sin(elv) * o.dist, target.z + Math.cos(az) * Math.cos(elv) * o.dist);
    return { pos, look: target.clone() };
  }
  let drag = null;
  const cv = renderer.domElement;
  cv.addEventListener('pointerdown', e => { drag = { x: e.clientX, y: e.clientY }; cv.setPointerCapture(e.pointerId); cv.style.cursor = 'grabbing'; });
  cv.addEventListener('pointerup', () => { drag = null; cv.style.cursor = ''; });
  cv.addEventListener('pointermove', e => {
    if (!drag) return; const o = orbits[S.view]; if (!o) return;
    o.az -= (e.clientX - drag.x) * V.orbit.degPerPx; o.el = Math.min(o.d.elMax, Math.max(o.d.elMin, o.el + (e.clientY - drag.y) * V.orbit.degPerPx));
    drag = { x: e.clientX, y: e.clientY };
  });
  cv.addEventListener('wheel', e => {
    const o = orbits[S.view]; if (!o) return; e.preventDefault();
    o.dist = Math.min(o.d.maxDist, Math.max(o.d.minDist, o.dist * (e.deltaY > 0 ? 1 + V.orbit.wheelStep : 1 / (1 + V.orbit.wheelStep))));
  }, { passive: false });

  // ---------- timeline / sequencer ----------
  function momentEvents(id) {
    if (expanded.has(id)) return expanded.get(id);
    const out = [];
    const add = list => { for (const ev of list) { if (ev.include) add(CONFIG.shared[ev.include]); else out.push(ev); } };
    add(CONFIG.moments[id].events);
    expanded.set(id, out); return out;
  }
  function kindOf(ev) { return KINDS.find(k => ev[k] != null); }
  function describe(ev) {
    const k = kindOf(ev), n = ev[k], d = FX[n];
    const at = ev.at ? ` @ ${ev.at}` : '', tg = ev.target ? ` → ${ev.target}` : '';
    let s;
    if (!d && !['motion', 'stop', 'sound', 'call', 'note'].includes(k)) s = `<b>missing fx “${esc(n)}”</b>`;
    else switch (k) {
      case 'motion': s = ev.label || n; break;
      case 'burst': { const c = pair(d.Count); s = `${n} · ${d.Texture} ×${c[0]}${c[1] !== c[0] ? ` (phone ${c[1]})` : ''}${d.Tints ? ` · ${d.Tints.length} tints` : ''} · life ${rng(d.Lifetime)} s${at}`; break; }
      case 'emit': { const c = pair(d.Rate); s = `${n} · ${d.Texture} ${c[0]}/s${c[1] !== c[0] ? ` (phone ${c[1]})` : ''} for ${ev.for != null ? ev.for + ' s' : 'whole flight'}${at}`; break; }
      case 'stop': s = `stop ${n}`; break;
      case 'ring': s = `${n} · ${d.SizeStart}→${d.SizeEnd} studs · ${d.Time} s ${d.Easing}${at}`; break;
      case 'pop': s = `${n} · ${d.Kind === 'Text' ? 'text' : d.Texture} billboard${d.Follow ? ' (follows)' : ''} · peak ${seqMax(d.Size)} studs · ${d.Time} s${at}`; break;
      case 'trail': s = `${n} · width ${d.Width} · life ${d.Lifetime} s${at}`; break;
      case 'flash': s = `${n} · ${d.Color} ${Math.round(d.Opacity * 100)}% · ${fmt(d.In + d.Out)} s`; break;
      case 'glow': s = `${n} · Highlight ${d.FillColor} · ${d.Time} s${tg}`; break;
      case 'light': s = `${n} · PointLight ${d.Brightness} / ${d.Range} studs · ${d.Time} s${at}`; break;
      case 'shake': s = `${n} · ${d.Amplitude}° · ${d.Time} s · ${d.Frequency} Hz`; break;
      case 'fov': s = `${n} · ${d.Delta > 0 ? '+' : ''}${d.Delta}° · in ${d.Attack} s · out ${d.Release} s`; break;
      case 'punch': s = `${n} · ${d.Offset ? d.Offset.join('/') + ' studs' : ''} ${d.Rotation ? d.Rotation.join('/') + '°' : ''} · ${fmt(d.Attack + (d.Hold || 0) + d.Release)} s`; break;
      case 'dip': s = `${n} · ${d.Depth} studs · down ${d.Down} s · up ${d.Up} s`; break;
      case 'hitstop': s = `${n} · freeze ${d.Time} s`; break;
      case 'slowmo': s = `${n} · ×${d.Speed} · ${fmt(d.In + d.Hold + d.Out)} s`; break;
      case 'pose': s = `${n} · ${d.Keys.length} R15 keys · ${d.Keys[d.Keys.length - 1].t} s${tg}`; break;
      case 'squash': s = `${n} · ${d.Keys.length} scale keys · ${d.Keys[d.Keys.length - 1][0]} s${tg}`; break;
      case 'wobble': s = `${n} · ±${Math.round(d.Amplitude * 100)}% · ${d.Frequency} Hz${tg}`; break;
      case 'sound': s = `“${n}”`; break;
      case 'ui': s = `${n} · ${d.Kind}`; break;
      case 'afterimage': { const c = pair(d.Count); s = `${n} · ×${c[0]}${c[1] !== c[0] ? ` (phone ${c[1]})` : ''} every ${d.Interval} s${tg}`; break; }
      case 'call': s = ev.label || n; break;
      default: s = ev.note || '';
    }
    if (ev.views) s += ` <em>[${ev.views.join(' / ')} only]</em>`;
    return [k, s];
  }
  function renderTimeline(id) {
    const m = CONFIG.moments[id], evs = momentEvents(id);
    el.mname.textContent = m.label; el.mnote.textContent = m.note || '';
    el.events.innerHTML = ''; rowsByEv.clear();
    for (const k in anchorEls) delete anchorEls[k];
    const groups = [{ on: null, evs: [] }];
    for (const ev of evs) { const on = ev.on || null; let g = groups.find(x => x.on === on); if (!g) { g = { on, evs: [] }; groups.push(g); } g.evs.push(ev); }
    for (const g of groups) {
      if (!g.evs.length) continue;
      if (g.on) {
        const h = document.createElement('li'); h.className = 'anchor';
        h.innerHTML = `on <b>${esc(g.on)}</b> <span></span>`; el.events.appendChild(h); anchorEls[g.on] = h.querySelector('span');
      }
      g.evs.slice().sort((a, b) => (a.t || 0) - (b.t || 0)).forEach(ev => {
        const [k, s] = describe(ev), li = document.createElement('li');
        li.innerHTML = `<span class="t">${g.on ? '+' : ''}${fmt(ev.t || 0)}</span><span class="k">${k}</span><span class="v">${s}</span>`;
        el.events.appendChild(li); rowsByEv.set(ev, li);
      });
    }
  }
  function resolveAnchor(ev, data) {
    const a = hooks.anchor ? hooks.anchor(api, ev.at || 'default', data || {}, ev) : null;
    return a || { pos: new THREE.Vector3(), dir: UP.clone() };
  }
  function aimVec(name, a, data) {
    if (name && hooks.aim) { const v = hooks.aim(api, name, data || {}, a); if (v) return v.clone().normalize(); }
    if (name === 'up') return UP.clone();
    if (name === 'down') return UP.clone().negate();
    if (name === 'normal' && data && data.normal) return data.normal.clone().normalize();
    return (a.dir || UP).clone().normalize();
  }
  function target(ev, data) { return hooks.target(api, ev.target || 'default', data || {}); }
  function exec(item) {
    const ev = item.ev, data = item.data || {}, row = rowsByEv.get(ev);
    if (ev.views && !ev.views.includes(S.view)) { if (row) row.classList.add('skip'); return; }
    let skip = '';
    if (ev.motion) hooks.motions[ev.motion](api, ev, data);
    else if (ev.burst) { const a = resolveAnchor(ev, data); burst(FX[ev.burst], a.pos, aimVec(ev.aim, a, data), a.vel, { ev, data }); }
    else if (ev.emit) startEmitter(FX[ev.emit], ev, data);
    else if (ev.stop) stopNamed(ev.stop);
    else if (ev.ring) { const a = resolveAnchor(ev, data); ring(FX[ev.ring], a.pos, aimVec(ev.face || 'up', a, data), { ev, data }); }
    else if (ev.pop) { const a = resolveAnchor(ev, data); pop(FX[ev.pop], a.pos, { ev, data }, data); }
    else if (ev.trail) trailOn(FX[ev.trail], ev, data);
    else if (ev.flash) skip = flash(FX[ev.flash]);
    else if (ev.glow) { const t = target(ev, data); t.glow = { def: FX[ev.glow], age: 0 }; }
    else if (ev.light) { const a = resolveAnchor(ev, data); light(FX[ev.light], a.pos); }
    else if (ev.shake) skip = camShake(FX[ev.shake]);
    else if (ev.fov) { if (S.reduce && !RM.fovKick) skip = 'off'; else live.fovs.push({ def: FX[ev.fov], age: 0 }); }
    else if (ev.punch) { if (S.reduce && !RM.punch) skip = 'off'; else live.punches.push({ def: FX[ev.punch], age: 0 }); }
    else if (ev.dip) live.dips.push({ def: FX[ev.dip], age: 0, scale: ev.scale || 1 });
    else if (ev.hitstop) S.hitstop = Math.max(S.hitstop, FX[ev.hitstop].Time);
    else if (ev.slowmo) { if (S.reduce && !RM.slowMo) skip = 'off'; else S.slow = { def: FX[ev.slowmo], age: 0 }; }
    else if (ev.pose) target(ev, data).play(FX[ev.pose]);
    else if (ev.squash) target(ev, data).squash(FX[ev.squash]);
    else if (ev.wobble) target(ev, data).setWobble(FX[ev.wobble]);
    else if (ev.sound) sound(ev.sound);
    else if (ev.ui) uiFx(FX[ev.ui], data);
    else if (ev.afterimage) afterimage(FX[ev.afterimage], target(ev, data));
    else if (ev.call) hooks.calls[ev.call](api, ev, data);
    if (row) row.classList.add(skip ? 'skip' : 'fired');
  }
  function signal(name, data) {
    if (!S.moment) return;
    S.signals[name] = (S.signals[name] || 0) + 1;
    for (const ev of momentEvents(S.moment)) if (ev.on === name) S.queue.push({ at: S.t + (ev.t || 0), ev, data });
    S.queue.sort((a, b) => a.at - b.at);
    const h = anchorEls[name]; if (h) h.textContent = `@ ${fmt(S.t)} s${S.signals[name] > 1 ? ` · ×${S.signals[name]}` : ''}`;
  }
  function runQueue() { while (S.queue.length && S.queue[0].at <= S.t) exec(S.queue.shift()); }
  function clearFx() {
    for (const p of live.parts) { scene.remove(p.s); spritePool.push(p.s); }
    for (const r of live.rings) { scene.remove(r.m); r.m.material.dispose(); }
    for (const p of live.pops) { scene.remove(p.s); p.s.material.dispose(); if (p.own) p.own.dispose(); }
    for (const t of live.trails) { scene.remove(t.mesh); t.geo.dispose(); t.mesh.material.dispose(); }
    for (const g of live.ghosts) { scene.remove(g.g); g.mat.dispose(); }
    for (const l of live.lights) { l.l.intensity = 0; l.l.userData.busy = false; }
    el.overlay.querySelectorAll('.sq-img,.sq-squished').forEach(n => n.remove());
    el.overlay.querySelectorAll('div:not(.sq-flash)').forEach(n => n.remove());
    flashEl.style.opacity = 0;
    for (const k in live) live[k].length = 0;
    S.hitstop = 0; S.slow = null; S.timeScale = 1; banner = null;
  }
  function play(id) {
    if (!CONFIG.moments[id]) return;
    clearFx();
    const m = CONFIG.moments[id];
    S.moment = id;
    if (!m.views.includes(S.view)) S.view = m.views[0];
    S.t = -(m.preRoll || 0); S.world = S.t; S.queue = []; S.signals = {};
    el.measure.innerHTML = ''; measures = {};
    for (const a of actors) a.reset();
    hooks.reset(api, id, m);
    for (const ev of momentEvents(id)) if (!ev.on) S.queue.push({ at: ev.t || 0, ev, data: {} });
    S.queue.sort((a, b) => a.at - b.at);
    renderTimeline(id); syncButtons();
  }
  let measures = {};
  function measure(key, text) {
    let d = measures[key];
    if (!d) { d = measures[key] = document.createElement('div'); el.measure.appendChild(d); }
    d.textContent = text;
  }

  // ---------- controls ----------
  const momentIds = Object.keys(CONFIG.moments);
  const mBtns = {}, vBtns = {}, tBtns = {};
  momentIds.forEach((id, i) => {
    const b = document.createElement('button'); b.className = 'sq-btn';
    b.innerHTML = `<span>${esc(CONFIG.moments[id].label)}</span><span class="k">${i + 1}</span>`;
    b.onclick = () => play(id); el.moments.appendChild(b); mBtns[id] = b;
  });
  viewKeys.forEach(k => {
    const b = document.createElement('button'); b.className = 'sq-btn'; b.textContent = CONFIG.views[k];
    b.onclick = () => { if (b.disabled) return; S.view = k; play(S.moment); }; el.views.appendChild(b); vBtns[k] = b;
  });
  const togs = [['slow', `${V.previewSlowMo}× slow-mo`, 'preview only'], ['phone', 'Phone', 'fewer particles'], ['reduce', 'Reduce motion', 'no shake / slow-mo']];
  for (const [k, label, hint] of togs) {
    const b = document.createElement('button'); b.className = 'sq-btn sq-tog';
    b.innerHTML = `<span>${label} <span class="k">${hint}</span></span><span class="dot"></span>`;
    b.onclick = () => {
      if (k === 'slow') S.preview = S.preview === 1 ? V.previewSlowMo : 1;
      if (k === 'phone') { S.phone = !S.phone; play(S.moment); }
      if (k === 'reduce') { S.reduce = !S.reduce; play(S.moment); }
      syncButtons();
    };
    el.toggles.appendChild(b); tBtns[k] = b;
  }
  function syncButtons() {
    const m = CONFIG.moments[S.moment];
    for (const id in mBtns) mBtns[id].classList.toggle('on', id === S.moment);
    for (const k in vBtns) { vBtns[k].classList.toggle('on', k === S.view); vBtns[k].disabled = !!m && !m.views.includes(k); }
    tBtns.slow.classList.toggle('on', S.preview !== 1); tBtns.phone.classList.toggle('on', S.phone); tBtns.reduce.classList.toggle('on', S.reduce);
    el.viewlabel.textContent = CONFIG.views[S.view];
  }
  window.addEventListener('keydown', e => {
    if (e.target && /input|textarea|select/i.test(e.target.tagName)) return;
    if (e.key === 'r' || e.key === 'R' || e.key === ' ') { e.preventDefault(); play(S.moment); }
    const n = parseInt(e.key, 10); if (n >= 1 && n <= momentIds.length) play(momentIds[n - 1]);
  });

  // ---------- rules check ----------
  function validate() {
    const res = [], ok = (c, t) => res.push({ ok: !!c, t });
    const used = {};
    for (const id of momentIds) for (const ev of momentEvents(id)) {
      const k = kindOf(ev); if (!k) { ok(false, `${id}: event without action`); continue; }
      if (['motion', 'stop', 'sound', 'call', 'note'].includes(k)) continue;
      if (!FX[ev[k]]) { ok(false, `${id}: missing fx “${ev[k]}”`); continue; }
      (used[ev[k]] = used[ev[k]] || { kind: k, evs: [] }).evs.push({ id, ev });
    }
    const maxT = RULES.maxEffectTime, mp = RULES.maxParticles;
    for (const n in used) {
      const d = FX[n], k = used[n].kind;
      if (k === 'burst') { const c = pair(d.Count); ok(c[0] <= mp[0] && c[1] <= mp[1], `${n}: ${c[0]} / ${c[1]} particles (max ${mp[0]} / ${mp[1]})`); ok(hi(d.Lifetime) <= maxT, `${n}: over in ${hi(d.Lifetime)} s`); }
      if (k === 'emit') {
        const c = pair(d.Rate); ok(c[0] * hi(d.Lifetime) <= mp[0] && c[1] * hi(d.Lifetime) <= mp[1], `${n}: ≤ ${Math.ceil(c[0] * hi(d.Lifetime))} / ${Math.ceil(c[1] * hi(d.Lifetime))} alive (max ${mp[0]} / ${mp[1]})`);
        for (const u of used[n].evs) if (u.ev.for != null) ok(u.ev.for + hi(d.Lifetime) <= maxT, `${u.id} · ${n}: over in ${fmt(u.ev.for + hi(d.Lifetime))} s`); else ok(hi(d.Lifetime) <= maxT, `${u.id} · ${n}: rides the squishy, each particle ≤ ${hi(d.Lifetime)} s`);
      }
      if (k === 'ring' || k === 'pop' || k === 'glow' || k === 'light') ok(d.Time <= maxT, `${n}: over in ${d.Time} s`);
      if (k === 'trail') ok(d.Lifetime <= maxT, `${n}: trail life ${d.Lifetime} s`);
      if (k === 'flash') ok(d.In + d.Out <= RULES.maxFlashTime && d.Opacity <= RULES.maxFlashOpacity, `${n}: flash ${fmt(d.In + d.Out)} s at ${Math.round(d.Opacity * 100)}% (max ${RULES.maxFlashTime} s / ${Math.round(RULES.maxFlashOpacity * 100)}%)`);
      if (k === 'shake') ok(d.Amplitude <= RULES.maxShake && d.Time <= maxT, `${n}: shake ${d.Amplitude}° (max ${RULES.maxShake}°)`);
      if (k === 'fov') ok(Math.abs(d.Delta) <= RULES.maxFovKick, `${n}: FOV kick ${d.Delta}° (max ${RULES.maxFovKick}°)`);
      if (k === 'hitstop') ok(d.Time <= RULES.maxHitStop, `${n}: hit-stop ${d.Time} s (max ${RULES.maxHitStop} s)`);
      if (k === 'slowmo') for (const u of used[n].evs) ok(CONFIG.moments[u.id].slowMoAllowed, `${u.id}: slow-mo only where allowed (${CONFIG.moments[u.id].slowMoAllowed ? 'round decided / own highway throw' : 'NOT allowed here'})`);
      if (k === 'ui' && d.Kind === 'SquishedText') { const c = d.PopTime + d.SettleTime + d.CenterHold + d.MoveTime; ok(c <= RULES.maxCenterCover, `${n}: covers centre ${fmt(c)} s (max ${RULES.maxCenterCover} s)`); }
      if (k === 'ui' && (d.Kind === 'Counter' || d.Kind === 'Banner')) ok(Math.abs(d.Y - 0.5) >= RULES.centerClear, `${n}: sits ${Math.round(d.Y * 100)} % from the top, centre clear`);
      if (k === 'ui' && d.Kind !== 'SquishedText' && d.Kind !== 'Counter') { const tt = d.Kind === 'EdgeSplat' ? d.PopTime + d.Hold + d.FadeTime + d.Stagger * pair(d.Count)[0] : d.Kind === 'SpeedLines' ? d.Time + d.Stagger : d.In + d.Hold + d.Out; ok(tt <= maxT, `${n}: over in ${fmt(tt)} s, keeps centre clear`); }
      if (k === 'pose') {
        let safe = true; const ks = d.Keys;
        for (let i = 1; i < ks.length; i++) for (const j of JOINTS) for (let a = 0; a < 3; a++) if (Math.abs((ks[i][j] || Z3)[a] - (ks[i - 1][j] || Z3)[a]) >= 180) safe = false;
        ok(safe, `${n}: keys < 180° apart (Roblox slerp-safe)`);
      }
    }
    for (const id of momentIds) {
      const slots = {};
      for (const ev of momentEvents(id)) if (ev.light) { const key = (ev.on || '') + '@' + (ev.t || 0); slots[key] = (slots[key] || 0) + 1; }
      ok(Object.values(slots).every(v => v <= RULES.maxLightsPerEffect), `${id}: ≤ ${RULES.maxLightsPerEffect} light per effect`);
    }
    if (hooks.validate) hooks.validate(api, ok);
    const bad = res.filter(r => !r.ok);
    el.rules.innerHTML = `<div class="${bad.length ? 'bad' : 'ok'}">${bad.length ? '✗' : '✓'} ${res.length - bad.length} / ${res.length} checks pass</div>` +
      bad.map(r => `<div class="bad">✗ ${esc(r.t)}</div>`).join('') +
      `<details><summary>All checks</summary>${res.map(r => `<div class="${r.ok ? 'ok' : 'bad'}">${r.ok ? '✓' : '✗'} ${esc(r.t)}</div>`).join('')}</details>`;
  }

  // ---------- loop ----------
  function updateFx(dtW, dtR) {
    for (let i = live.ghostQ.length - 1; i >= 0; i--) if (S.world >= live.ghostQ[i].at) { const g = live.ghostQ.splice(i, 1)[0]; spawnGhost(g.def, g.av); }
    if (dtW > 0) {
      for (let i = live.emitters.length - 1; i >= 0; i--) {
        const e = live.emitters[i];
        if (S.world > e.until) { live.emitters.splice(i, 1); continue; }
        const tints = e.def.Tints || [null];
        e.acc += count(e.def.Rate) * dtW;
        while (e.acc >= 1) { e.acc -= 1; const a = resolveAnchor(e.ev, e.data); emitOne(e.def, tints[Math.floor(Math.random() * tints.length)], a.pos, aimVec(e.ev.aim, a, e.data), a.vel, e); }
      }
    }
    live.parts = live.parts.filter(p => { if (updateParticle(p, dtW)) return true; scene.remove(p.s); spritePool.push(p.s); return false; });
    live.rings = live.rings.filter(r => { if (updateRing(r, dtW)) return true; scene.remove(r.m); r.m.material.dispose(); return false; });
    live.pops = live.pops.filter(p => { if (updatePop(p, dtR)) return true; scene.remove(p.s); p.s.material.dispose(); if (p.own) p.own.dispose(); return false; });
    live.trails = live.trails.filter(t => { if (updateTrail(t)) return true; scene.remove(t.mesh); t.geo.dispose(); t.mesh.material.dispose(); return false; });
    live.ghosts = live.ghosts.filter(g => {
      g.age += dtW; const u = g.age / g.def.Time;
      g.mat.opacity = (1 - g.def.TransparencyStart) * (1 - ease(g.def.Easing, u));
      if (u < 1) return true; scene.remove(g.g); g.mat.dispose(); return false;
    });
    live.lights = live.lights.filter(l => {
      l.age += dtW; const u = l.age / l.def.Time;
      l.l.intensity = l.def.Brightness * V.light.pointScale * (1 - ease(l.def.Easing, u));
      if (u < 1) return true; l.l.intensity = 0; l.l.userData.busy = false; return false;
    });
    live.ui = live.ui.filter(u => u.update(dtR));
    for (const k of ['shakes', 'fovs', 'punches', 'dips']) live[k] = live[k].filter(x => {
      x.age += dtR; const d = x.def;
      const total = k === 'shakes' ? d.Time : k === 'dips' ? d.Down + (d.Hold || 0) + d.Up : d.Attack + (d.Hold || 0) + d.Release;
      return x.age < total;
    });
  }
  function hud() {
    const b = [`<span>t ${S.t < 0 ? '−' : ''}${fmt(Math.abs(S.t))} s</span>`];
    if (S.preview !== 1) b.push(`<span class="warn">preview ×${S.preview}</span>`);
    if (S.phone) b.push('<span>phone</span>');
    if (S.reduce) b.push('<span>reduce motion</span>');
    if (S.hitstop > 0) b.push('<span class="warn">hit-stop</span>');
    if (S.timeScale < 1) b.push(`<span class="warn">slow-mo ×${S.timeScale.toFixed(2)}</span>`);
    const h = b.join(''); if (h !== el.hud._h) { el.hud.innerHTML = h; el.hud._h = h; }
  }
  let last = performance.now();
  function frame(now) {
    requestAnimationFrame(frame);
    const raw = Math.min((now - last) / 1000, V.render.maxDt); last = now;
    const dtR = raw * S.preview;
    S.clock += dtR;
    if (S.ready && S.moment) {
      S.timeScale = slowScale(dtR);
      let dtW = dtR * S.timeScale;
      if (S.hitstop > 0) { S.hitstop = Math.max(0, S.hitstop - dtR); dtW = 0; }
      S.t += dtR; S.world += dtW;
      runQueue();
      if (hooks.update) hooks.update(api, dtW, dtR);
      runQueue();
      for (const a of actors) a.update(dtW, dtR);
      updateFx(dtW, dtR);
    }
    if (S.moment) applyCamera(dtR);
    if (skyDome) skyDome.position.copy(camera.position);
    renderer.render(scene, camera);
    hud();
  }

  const api = {
    THREE, CONFIG, scene, camera, renderer, S, el, DEG, TAU, UP,
    ease, seqN, rr, count, fmt, clamp01,
    avatar: makeAvatar, squishy: makeSquishy, material, checker, faceQuat,
    signal, play, measure, setFocus, orbit,
    burst, ring, pop, trailOn, stopNamed, sound,
    replay: () => play(S.moment)
  };
  hooks.setup(api);
  resize();
  validate();
  syncButtons();
  requestAnimationFrame(frame);
  loadKit().then(() => { S.ready = true; play(hooks.firstMoment || momentIds[0]); });
  return api;
};
window.SquishyFX.ease = ease;
})();
