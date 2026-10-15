import * as THREE from 'three';
export { THREE };
export const STUD = 0.28;
export const V3 = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);
export function rng(seed) {
  let a = seed >>> 0;
  return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
export const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
export const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
export const sflat = (y, t, k) => (y >= t ? y : t - k * (1 - Math.exp((y - t) / k)));
export const sflatTop = (y, t, k) => (y <= t ? y : t + k * (1 - Math.exp(-(y - t) / k)));

const MATS = new Map();
export function mat(name, hex, rough = 0.7, extra = {}) {
  let m = MATS.get(name);
  if (m) return m;
  m = new THREE.MeshStandardMaterial(Object.assign({ color: hex, roughness: rough, metalness: 0 }, extra));
  m.name = name;
  MATS.set(name, m);
  return m;
}
export function mesh(geo, material, name, parent, p, r, s) {
  const m = new THREE.Mesh(geo, material);
  m.name = name;
  if (p) m.position.set(p[0], p[1], p[2]);
  if (r) m.rotation.set(r[0], r[1], r[2]);
  if (s) (typeof s === 'number' ? m.scale.setScalar(s) : m.scale.set(s[0], s[1], s[2]));
  if (parent) parent.add(m);
  return m;
}
export function group(name, parent, p, r) {
  const g = new THREE.Group();
  g.name = name;
  if (p) g.position.set(p[0], p[1], p[2]);
  if (r) g.rotation.set(r[0], r[1], r[2]);
  if (parent) parent.add(g);
  return g;
}

export function superR(d, a, b, c, n = 2, m = 2) {
  const xz = Math.pow(Math.pow(Math.abs(d.x / a), n) + Math.pow(Math.abs(d.z / c), n), m / n);
  const yy = Math.pow(Math.abs(d.y / b), m);
  return Math.pow(xz + yy, -1 / m);
}
export const superF = (a, b, c, n = 2, m = 2) => (d) => d.clone().multiplyScalar(superR(d, a, b, c, n, m));

export function warpSphere(f, ws = 64, hs = 48) {
  const g = new THREE.SphereGeometry(1, ws, hs);
  const P = g.attributes.position, N = g.attributes.normal;
  const d = new THREE.Vector3(), t1 = new THREE.Vector3(), t2 = new THREE.Vector3(), up = new THREE.Vector3(), q = new THREE.Vector3();
  const e = 0.003;
  for (let i = 0; i < P.count; i++) {
    d.fromBufferAttribute(P, i).normalize();
    up.set(0, 1, 0);
    if (Math.abs(d.y) > 0.95) up.set(1, 0, 0);
    t1.crossVectors(up, d).normalize();
    t2.crossVectors(d, t1);
    const p = f(d.clone());
    const a = f(q.copy(d).addScaledVector(t1, e).normalize().clone()).sub(p);
    const b = f(q.copy(d).addScaledVector(t2, e).normalize().clone()).sub(p);
    const n = a.cross(b);
    if (n.lengthSq() < 1e-16) n.copy(d);
    n.normalize();
    P.setXYZ(i, p.x, p.y, p.z);
    N.setXYZ(i, n.x, n.y, n.z);
  }
  g.computeBoundingBox();
  g.computeBoundingSphere();
  return g;
}

export function paramSurface(fn, us, vs, opts = {}) {
  const pos = [], nor = [], uv = [], idx = [];
  const e = 1e-3;
  const cu = (u) => (opts.wrapU ? u : clamp(u, 0, 1));
  const cv = (v) => (opts.wrapV ? v : clamp(v, 0, 1));
  for (let j = 0; j <= vs; j++) for (let i = 0; i <= us; i++) {
    const u = i / us, v = j / vs;
    const p = fn(u, v);
    const du = fn(cu(u + e), v).sub(fn(cu(u - e), v));
    const dv = fn(u, cv(v + e)).sub(fn(u, cv(v - e)));
    const n = du.cross(dv);
    if (n.lengthSq() < 1e-18) n.copy(opts.fallback || V3(0, 1, 0));
    n.normalize();
    pos.push(p.x, p.y, p.z); nor.push(n.x, n.y, n.z); uv.push(u, v);
  }
  for (let j = 0; j < vs; j++) for (let i = 0; i < us; i++) {
    const a = j * (us + 1) + i, b = a + 1, c = a + us + 1, d = c + 1;
    idx.push(a, b, c, b, d, c);
  }
  let flip = !!opts.flip;
  if (opts.inside) {
    const p = fn(0.5, 0.5);
    const n = fn(0.5 + e, 0.5).sub(fn(0.5 - e, 0.5)).cross(fn(0.5, 0.5 + e).sub(fn(0.5, 0.5 - e)));
    if (n.dot(p.clone().sub(opts.inside(0.5, 0.5))) < 0) flip = !flip;
  }
  if (flip) {
    for (let i = 0; i < nor.length; i++) nor[i] = -nor[i];
    for (let i = 0; i < idx.length; i += 3) { const t = idx[i + 1]; idx[i + 1] = idx[i + 2]; idx[i + 2] = t; }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeBoundingSphere();
  return g;
}

export function taperTube(curve, rFn, tubular = 48, radial = 16) {
  const frames = curve.computeFrenetFrames(tubular, false);
  const pos = [], nor = [], idx = [], uv = [];
  const P = new THREE.Vector3(), n = new THREE.Vector3();
  for (let i = 0; i <= tubular; i++) {
    const t = i / tubular;
    curve.getPointAt(t, P);
    const N = frames.normals[i], B = frames.binormals[i];
    const r = rFn(t);
    for (let j = 0; j <= radial; j++) {
      const v = (j / radial) * Math.PI * 2;
      const s = Math.sin(v), c = -Math.cos(v);
      n.set(c * N.x + s * B.x, c * N.y + s * B.y, c * N.z + s * B.z).normalize();
      pos.push(P.x + r * n.x, P.y + r * n.y, P.z + r * n.z);
      nor.push(n.x, n.y, n.z);
      uv.push(t, j / radial);
    }
  }
  for (let j = 1; j <= tubular; j++) for (let i = 1; i <= radial; i++) {
    const a = (radial + 1) * (j - 1) + (i - 1), b = (radial + 1) * j + (i - 1), c = (radial + 1) * j + i, d = (radial + 1) * (j - 1) + i;
    idx.push(a, b, d, b, c, d);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeBoundingSphere();
  return g;
}
export const curve = (pts) => new THREE.CatmullRomCurve3(pts.map((p) => V3(p[0], p[1], p[2])), false, 'centripetal');
export const roundEnd = (t, r, start = 0.8) => (t < start ? r : r * Math.sqrt(Math.max(0, 1 - Math.pow((t - start) / (1 - start), 2))));

export function lathe(pts, segs = 48, smoothN = 0) {
  let v = pts.map((p) => new THREE.Vector2(p[0], p[1]));
  if (smoothN) v = new THREE.SplineCurve(v).getPoints(smoothN);
  return new THREE.LatheGeometry(v, segs);
}

export function mergeGeos(list) {
  let total = 0;
  const parts = list.map((g) => { const ng = g.index ? g.toNonIndexed() : g; total += ng.attributes.position.count; return ng; });
  const pos = new Float32Array(total * 3), nor = new Float32Array(total * 3);
  let o = 0;
  for (const g of parts) { pos.set(g.attributes.position.array, o * 3); nor.set(g.attributes.normal.array, o * 3); o += g.attributes.position.count; }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  out.computeBoundingSphere();
  return out;
}

export function colorize(geo, fn) {
  const P = geo.attributes.position, N = geo.attributes.normal;
  const arr = new Float32Array(P.count * 3);
  const p = new THREE.Vector3(), n = new THREE.Vector3();
  for (let i = 0; i < P.count; i++) {
    p.fromBufferAttribute(P, i); n.fromBufferAttribute(N, i);
    const c = fn(p, n);
    arr[i * 3] = c.r; arr[i * 3 + 1] = c.g; arr[i * 3 + 2] = c.b;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(arr, 3));
  return geo;
}
export function tint(base, target) {
  const b = new THREE.Color(base), t = new THREE.Color(target);
  return new THREE.Color(Math.min(1, t.r / Math.max(b.r, 1e-4)), Math.min(1, t.g / Math.max(b.g, 1e-4)), Math.min(1, t.b / Math.max(b.b, 1e-4)));
}
const WHITE = new THREE.Color(1, 1, 1);
export const mix = (factor, amt) => WHITE.clone().lerp(factor, clamp(amt, 0, 1));

const RC = new THREE.Raycaster();
const NM = new THREE.Matrix3();
export function hit(targets, ox, oy, oz, dx, dy, dz) {
  for (const t of targets) t.updateWorldMatrix(true, false);
  RC.set(V3(ox, oy, oz), V3(dx, dy, dz).normalize());
  const h = RC.intersectObjects(targets, false)[0];
  if (!h) return null;
  NM.getNormalMatrix(h.object.matrixWorld);
  const n = h.face.normal.clone().applyMatrix3(NM).normalize();
  return { p: h.point.clone(), n };
}
export const hitFront = (targets, x, y) => hit(targets, x, y, 5, 0, 0, -1);
export const hitBack = (targets, x, y) => hit(targets, x, y, -5, 0, 0, 1);
export const hitTop = (targets, x, z) => hit(targets, x, 5, z, 0, -1, 0);
export const hitDir = (targets, center, dir) => { const d = dir.clone().normalize(); const o = center.clone().addScaledVector(d, 5); return hit(targets, o.x, o.y, o.z, -d.x, -d.y, -d.z); };
const ZA = V3(0, 0, 1);
export function stick(parent, obj, h, lift = 0) {
  if (!h) return obj;
  obj.position.copy(h.p).addScaledVector(h.n, lift);
  obj.quaternion.setFromUnitVectors(ZA, h.n);
  parent.add(obj);
  return obj;
}

const GEO = {};
const geoC = (k, f) => GEO[k] || (GEO[k] = f());
export function eyeGroup(r, big) {
  const ink = mat('face_ink', 0x2a1a22, 0.3), shine = mat('face_shine', 0xffffff, 0.2);
  const g = new THREE.Group(); g.name = 'eye';
  mesh(geoC('eyeball', () => new THREE.SphereGeometry(1, 28, 18)), ink, 'eye_ball', g, [0, 0, 0], null, [r, r * 1.16, r * 0.5]);
  mesh(geoC('shine', () => new THREE.SphereGeometry(1, 14, 10)), shine, 'eye_shine', g, [-0.28 * r, 0.4 * r, 0.4 * r], null, [r * 0.4, r * 0.4, r * 0.18]);
  if (big) mesh(geoC('shine', () => new THREE.SphereGeometry(1, 14, 10)), shine, 'eye_shine_b', g, [0.3 * r, -0.36 * r, 0.42 * r], null, [r * 0.16, r * 0.16, r * 0.08]);
  return g;
}
export function arc(R, tube, matl, name, down) {
  const m = new THREE.Mesh(new THREE.TorusGeometry(R, tube, 8, 22, Math.PI), matl);
  m.name = name;
  const g = new THREE.Group(); g.name = name + '_g'; g.add(m);
  if (down) { m.rotation.z = Math.PI; m.position.y = R * 0.5; } else m.position.y = -R * 0.5;
  return g;
}
function chevron(r, dir, ink) {
  const g = new THREE.Group(); g.name = 'eye_chevron';
  const cap = geoC('chev' + r.toFixed(4), () => new THREE.CapsuleGeometry(r * 0.3, r * 1.15, 4, 10));
  for (const s of [1, -1]) { const m = new THREE.Mesh(cap, ink); m.name = 'chev'; m.rotation.z = dir * s * 0.95; m.position.set(-dir * r * 0.32, s * r * 0.42, 0); m.scale.z = 0.5; g.add(m); }
  return g;
}
export function face(parent, targets, o) {
  const s = o.s ?? 1, cx = o.x ?? 0, cy = o.y, cart = o.cartoon ?? 1.22;
  const eyeR = (o.eyeR ?? 0.022) * s * cart, dx = (o.dx ?? 0.08) * s;
  const ink = mat('face_ink', 0x1b1220, 0.3), blushM = mat('face_blush', 0xff8fa8, 0.95);
  const gN = new THREE.Group(); gN.name = 'face_normal'; parent.add(gN);
  const gS = new THREE.Group(); gS.name = 'face_squish'; gS.visible = false; parent.add(gS);
  const out = { eyes: [], normal: gN, squish: gS };
  for (const side of [-1, 1]) {
    const h = hitFront(targets, cx + side * dx, cy);
    if (!h) continue;
    const eye = o.eyes === 'happy' ? arc(eyeR * 0.95, eyeR * 0.32, ink, 'eye_happy') : eyeGroup(eyeR, o.eyes !== 'dot');
    stick(gN, eye, h, o.eyes === 'happy' ? -eyeR * 0.05 : 0);
    out.eyes.push(eye);
    stick(gS, chevron(eyeR, side, ink), h, eyeR * 0.05);
  }
  const mw = (o.mw ?? 0.022) * s * (cart * 0.5 + 0.5), my = cy - (o.my ?? 0.045) * s;
  const mh = o.mouth === 'none' ? null : hitFront(targets, cx, my);
  const tube = (o.mt ?? 0.0055) * s * 1.25;
  const mm = mat('face_mouth', 0x8a2440, 0.55), tm = mat('face_tongue', 0xff7f96, 0.7);
  if (mh) {
    const g = new THREE.Group(); g.name = 'mouth';
    if (o.mouth === 'cat') {
      const a = arc(mw * 0.5, tube, ink, 'mouth_l', true); a.position.x = -mw * 0.5; g.add(a);
      const b = arc(mw * 0.5, tube, ink, 'mouth_r', true); b.position.x = mw * 0.5; g.add(b);
    } else if (o.mouth === 'open') {
      mesh(geoC('eyeball', () => new THREE.SphereGeometry(1, 28, 18)), mm, 'mouth_open', g, [0, 0, 0], null, [mw * 0.75, mw * 0.6, mw * 0.25]);
      mesh(geoC('eyeball', () => new THREE.SphereGeometry(1, 28, 18)), tm, 'mouth_tongue', g, [0, -mw * 0.25, mw * 0.08], null, [mw * 0.48, mw * 0.3, mw * 0.2]);
    } else g.add(arc(mw, tube, ink, 'mouth_smile', true));
    if (o.fang) mesh(new THREE.ConeGeometry(mw * 0.18, mw * 0.4, 10), mat('dragon_fang', 0xfffaf0, 0.4), 'mouth_fang', g, [mw * 0.55, -mw * 0.55, tube * 0.6], [Math.PI, 0, 0]);
    if (o.teeth) { const ttm = mat('bunny_teeth', 0xffffff, 0.35); for (const sx of [-1, 1]) mesh(new THREE.BoxGeometry(mw * 0.42, mw * 0.5, mw * 0.18), ttm, 'mouth_tooth', g, [sx * mw * 0.23, -mw * 1.15, 0], null); }
    if (o.tongue) mesh(geoC('eyeball', () => new THREE.SphereGeometry(1, 28, 18)), tm, 'mouth_tongue', g, [mw * 0.25, -mw * 1.05, mw * 0.12], [0.2, 0, 0], [mw * 0.5, mw * 0.7, mw * 0.22]);
    stick(gN, g, mh, -tube * 0.25);
    const sq = new THREE.Group(); sq.name = 'mouth_squish';
    const ow = Math.max(mw, eyeR * 0.9);
    mesh(geoC('eyeball', () => new THREE.SphereGeometry(1, 28, 18)), mm, 'mouth_squish_open', sq, [0, 0, 0], null, [ow * 0.95, ow * 0.62, ow * 0.25]);
    mesh(geoC('eyeball', () => new THREE.SphereGeometry(1, 28, 18)), tm, 'mouth_squish_tongue', sq, [0, -ow * 0.25, ow * 0.08], null, [ow * 0.55, ow * 0.3, ow * 0.2]);
    stick(gS, sq, mh, 0);
    out.mouth = g;
  }
  if (o.blush !== false) {
    const bx = (o.bx ?? 0.13) * s, by = cy - (o.by ?? 0.03) * s, br = (o.br ?? 0.024) * s * 1.1;
    for (const side of [-1, 1]) {
      const h = hitFront(targets, cx + side * bx, by);
      if (!h) continue;
      const b = mesh(geoC('eyeball', () => new THREE.SphereGeometry(1, 28, 18)), blushM, 'blush', null, null, null, [br * 1.3, br * 0.78, br * 0.22]);
      stick(parent, b, h, 0);
    }
  }
  return out;
}
