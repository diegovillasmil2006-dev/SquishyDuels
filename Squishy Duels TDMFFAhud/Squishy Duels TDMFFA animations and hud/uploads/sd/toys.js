import { toonify } from './toon.js';
import { THREE, V3, mat, mesh, group, superF, warpSphere, paramSurface, taperTube, curve, roundEnd, lathe, mergeGeos, colorize, tint, mix, smooth, sflat, sflatTop, hit, hitFront, hitBack, hitTop, hitDir, stick, face, rng, STUD } from './kit.js';

const UNIT = new THREE.SphereGeometry(1, 32, 24);
const YA = V3(0, 1, 0);
function ell(name, m, parent, p, s, r) { return mesh(UNIT, m, name, parent, p, r, s); }
function stickY(parent, obj, h, lift = 0) {
  if (!h) return obj;
  obj.position.copy(h.p).addScaledVector(h.n, lift);
  obj.quaternion.setFromUnitVectors(YA, h.n);
  parent.add(obj);
  return obj;
}
function pivot(name, parent, p) { return group(name, parent, p); }
function tubeAt(name, m, parent, pts, rFn, tub = 40, rad = 14) {
  const c = curve(pts);
  const g = taperTube(c, rFn, tub, rad);
  const p0 = pts[0];
  g.translate(-p0[0], -p0[1], -p0[2]);
  const pv = pivot(name + '_pivot', parent, p0);
  mesh(g, m, name, pv);
  return { pivot: pv, curve: c };
}
function bake(meshes) { return mergeGeos(meshes.map((m) => { m.updateMatrix(); return m.geometry.clone().applyMatrix4(m.matrix); })); }
const vc = (name, hex, rough) => mat(name, hex, rough, { vertexColors: true });

function makeRoot(id) {
  const root = new THREE.Group(); root.name = 'SD_ART_' + id;
  const squash = group(id + '_deform', root);
  const content = group(id + '_geo', squash);
  return { id, root, squash, content, sec: [] };
}
function sec(t, obj, axis, amp, sign = 1) { t.sec.push({ obj, axis, amp, sign, base: obj.rotation[axis] }); }
function finalize(t) {
  t.content.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(t.content);
  t.content.position.y = -box.min.y;
  t.size = box.getSize(V3());
  return t;
}

/* ---------------- existing eight ---------------- */
function KittyBread() {
  const t = makeRoot('KittyBread'), C = t.content;
  const base = 0xF9E3BC, fGold = tint(base, 0xEFBC7A), fCrust = tint(base, 0xCF8443);
  const g = warpSphere((d) => { const p = superF(0.3, 0.17, 0.235, 2.6, 2.3)(d); p.y = sflat(p.y, -0.085, 0.03); p.y += 0.018 * Math.max(0, p.y / 0.17) * (1 - Math.pow(p.x / 0.3, 2)); return p; });
  colorize(g, (p) => mix(fGold, smooth(-0.08, 0.02, p.y)).lerp(fCrust, smooth(0.03, 0.17, p.y)));
  const body = mesh(g, vc('kitty_bread_dough', base, 0.82), 'kitty_body', C);
  const crust = mat('kitty_bread_crust', 0xD48D4C, 0.8), inner = mat('kitty_ear_inner', 0xF5A9A0, 0.9);
  const earG = lathe([[0.07, 0], [0.066, 0.03], [0.05, 0.065], [0.028, 0.095], [0.01, 0.112], [0, 0.116]], 32, 24);
  for (const s of [-1, 1]) {
    const pv = stickY(C, pivot('kitty_ear_' + (s < 0 ? 'R' : 'L'), null), hitTop([body], s * 0.165, 0.03), -0.022);
    pv.rotateZ(-s * 0.18);
    mesh(earG, crust, 'kitty_ear', pv, null, null, [1, 1, 0.62]);
    mesh(earG, inner, 'kitty_ear_inner', pv, [0, 0.012, 0.026], null, [0.6, 0.72, 0.3]);
    sec(t, pv, 'x', 0.9);
  }
  const stripe = mat('kitty_stripe', 0xB86A35, 0.8);
  [-0.045, 0, 0.045].forEach((x, i) => { const h = hitTop([body], x, 0.11 - (i === 1 ? 0.01 : 0)); const m = mesh(new THREE.CapsuleGeometry(0.009, i === 1 ? 0.06 : 0.045, 4, 10), stripe, 'kitty_stripe', null, null, null, [1, 1, 0.45]); stick(C, m, h, -0.002); });
  face(C, [body], { y: 0.035, dx: 0.085, eyeR: 0.024, mouth: 'cat', mw: 0.024, my: 0.042, bx: 0.14, by: 0.03 });
  const paw = mat('kitty_bread_paw', 0xFCEBD0, 0.85);
  for (const s of [-1, 1]) stick(C, ell('kitty_paw', paw, null, null, [0.045, 0.03, 0.04]), hitFront([body], s * 0.1, -0.075), -0.012);
  const tg = new THREE.TorusGeometry(0.045, 0.02, 12, 28, Math.PI * 1.25);
  const tail = pivot('kitty_tail', null);
  mesh(tg, crust, 'kitty_tail', tail);
  stick(C, tail, hitBack([body], 0.07, 0.0), -0.014);
  sec(t, tail, 'z', 1.2);
  t.targets = [body];
  return finalize(t);
}

function Toast() {
  const t = makeRoot('Toast'), C = t.content;
  const W = 0.17, H = 0.25, r = 0.04;
  const s = new THREE.Shape();
  s.moveTo(-W + r, 0); s.lineTo(W - r, 0); s.quadraticCurveTo(W, 0, W, r); s.lineTo(W, H);
  s.bezierCurveTo(W + 0.055, H + 0.01, W + 0.065, H + 0.12, W - 0.03, H + 0.14);
  s.quadraticCurveTo(0, H + 0.165, -W + 0.03, H + 0.14);
  s.bezierCurveTo(-W - 0.065, H + 0.12, -W - 0.055, H + 0.01, -W, H);
  s.lineTo(-W, r); s.quadraticCurveTo(-W, 0, -W + r, 0);
  const cg = new THREE.ExtrudeGeometry(s, { depth: 0.07, bevelEnabled: true, bevelThickness: 0.025, bevelSize: 0.022, bevelSegments: 6, curveSegments: 28 });
  cg.translate(0, 0, -0.035);
  const crust = mesh(cg, mat('toast_crust', 0xC9803F, 0.74), 'toast_crust', C);
  const pts = s.getPoints(40).map((p) => new THREE.Vector2(p.x * 0.84, 0.2 + (p.y - 0.2) * 0.84));
  const ig = new THREE.ExtrudeGeometry(new THREE.Shape(pts), { depth: 0.004, bevelEnabled: true, bevelThickness: 0.014, bevelSize: 0.012, bevelSegments: 4, curveSegments: 12 });
  const base = 0xFDF0D3, ft = tint(base, 0xF0CE8C);
  colorize(ig, (p) => mix(ft, 1 - smooth(0.0, 0.15, Math.hypot(p.x, (p.y - 0.2) * 1.1))));
  const cm = vc('toast_crumb', base, 0.92);
  const front = mesh(ig, cm, 'toast_crumb_front', C, [0, 0, 0.052]);
  mesh(ig, cm, 'toast_crumb_back', C, [0, 0, -0.052], [0, Math.PI, 0]);
  face(C, [front], { y: 0.205, dx: 0.065, eyeR: 0.022, mouth: 'smile', mw: 0.02, my: 0.045, bx: 0.11, by: 0.03 });
  t.targets = [front, crust];
  return finalize(t);
}

function Banana() {
  const t = makeRoot('Banana'), C = t.content;
  const L = 0.3, R = 0.075, Rb = 0.4;
  const g = warpSphere((d) => {
    const tt = d.y, ang = Math.atan2(d.z, d.x);
    const sN = Math.sqrt(Math.max(0, 1 - tt * tt));
    const r = R * Math.pow(sN, 0.55) * (1 + 0.06 * tt) * (1 + 0.045 * Math.cos(5 * ang));
    const cx = -r * Math.cos(ang), cz = r * Math.sin(ang);
    const th = (tt * L) / Rb, rr = Rb - cx;
    return V3(rr * Math.sin(th), Rb - rr * Math.cos(th), cz);
  }, 64, 64);
  const base = 0xFFE067, fg = tint(base, 0xB5CC50), fb = tint(base, 0x7A5530);
  colorize(g, (p) => { const tt = (Math.atan2(p.x, Rb - p.y) * Rb) / L; return mix(fg, smooth(0.66, 0.97, tt)).multiply(mix(fb, smooth(-0.9, -0.99, tt))); });
  const body = mesh(g, vc('banana_peel', base, 0.7), 'banana_body', C);
  const th = L / Rb, end = V3(Rb * Math.sin(th), Rb * (1 - Math.cos(th)), 0), tan = V3(Math.cos(th), Math.sin(th), 0);
  const stem = mesh(new THREE.CylinderGeometry(0.015, 0.021, 0.075, 16), mat('banana_stem', 0x8C9A3E, 0.75), 'banana_stem', C);
  stem.position.copy(end).addScaledVector(tan, 0.028); stem.quaternion.setFromUnitVectors(YA, tan);
  const cap = mesh(new THREE.CylinderGeometry(0.017, 0.016, 0.012, 16), mat('banana_tip', 0x6B4A2B, 0.8), 'banana_stem_cap', C);
  cap.position.copy(end).addScaledVector(tan, 0.066); cap.quaternion.copy(stem.quaternion);
  const e2 = V3(-Rb * Math.sin(th), Rb * (1 - Math.cos(th)), 0), out2 = V3(-Math.cos(th), Math.sin(th), 0);
  ell('banana_tip', mat('banana_tip', 0x6B4A2B, 0.8), C, null, 0.014).position.copy(e2).addScaledVector(out2, 0.002);
  const sp = mat('banana_speckle', 0x8A6236, 0.8);
  [[-0.12, 0.03], [0.05, -0.01], [0.14, 0.05], [-0.03, 0.025], [0.09, 0.0], [-0.17, 0.06]].forEach(([x, y]) => stick(C, ell('banana_speckle', sp, null, null, [0.009, 0.006, 0.002]), hitBack([body], x, y), 0));
  face(C, [body], { y: 0.012, dx: 0.065, eyeR: 0.019, mouth: 'smile', mw: 0.018, my: 0.036, bx: 0.11, by: 0.012, br: 0.02 });
  t.targets = [body];
  return finalize(t);
}

function Butter() {
  const t = makeRoot('Butter'), C = t.content;
  const bm = mat('butter_block', 0xFBE38C, 0.55);
  const body = mesh(warpSphere(superF(0.25, 0.13, 0.16, 5, 5)), bm, 'butter_block', C);
  mesh(warpSphere((d) => { const p = superF(0.258, 0.137, 0.168, 5, 5)(d); p.y = sflatTop(p.y, -0.005, 0.006); return p; }), mat('butter_wrapper', 0xFFF5DE, 0.88), 'butter_wrapper', C);
  mesh(warpSphere((d) => { const p = superF(0.262, 0.141, 0.172, 5, 5)(d); p.y = sflatTop(sflat(p.y, -0.088, 0.003), -0.052, 0.003); return p; }), mat('butter_label_blue', 0x4A78D6, 0.62), 'butter_label_band', C);
  const tri = new THREE.Shape(); tri.moveTo(-0.075, 0); tri.lineTo(0.075, 0); tri.lineTo(0, 0.07); tri.lineTo(-0.075, 0);
  const tg = new THREE.ExtrudeGeometry(tri, { depth: 0.002, bevelEnabled: true, bevelThickness: 0.004, bevelSize: 0.004, bevelSegments: 2 });
  for (const s of [-1, 1]) mesh(tg, mat('butter_fold', 0xF0E2C2, 0.88), 'butter_wrapper_fold', C, [s * 0.262, -0.128, 0], [0, s * Math.PI / 2, 0]);
  stick(C, ell('butter_seal', mat('foil_gold', 0xE8B84A, 0.34, { metalness: 0.3 }), null, null, [0.034, 0.024, 0.006]), hitFront([C.children[2]], 0, -0.07), 0);
  mesh(new THREE.TorusGeometry(0.04, 0.017, 14, 32, Math.PI * 1.5), mat('butter_curl', 0xF6D35C, 0.5), 'butter_curl', C, [-0.1, 0.143, 0.03], [-Math.PI / 2, 0, 0.6]);
  ell('butter_melt', mat('butter_melt', 0xFDE89A, 0.28), C, [0.07, 0.127, -0.02], [0.08, 0.012, 0.06]);
  face(C, [body], { y: 0.065, dx: 0.08, eyeR: 0.022, mouth: 'open', mw: 0.026, my: 0.045, bx: 0.135, by: 0.025 });
  t.targets = [body];
  return finalize(t);
}

function Chocolate() {
  const t = makeRoot('Chocolate'), C = t.content;
  const body = mesh(warpSphere(superF(0.15, 0.22, 0.05, 6, 6)), mat('chocolate', 0x6E3D2B, 0.5), 'choc_bar', C);
  const sg = warpSphere(superF(0.06, 0.042, 0.024, 2.6, 2.6), 40, 30), sm = mat('chocolate_square', 0x7A4532, 0.48);
  for (const x of [-0.068, 0.068]) for (const y of [0.075, 0.165]) { mesh(sg, sm, 'choc_square', C, [x, y, 0.046]); mesh(sg, sm, 'choc_square_back', C, [x, y, -0.046]); }
  mesh(warpSphere((d) => { const p = superF(0.153, 0.226, 0.0535, 6, 6)(d); p.multiplyScalar(1 + 0.012 * Math.sin(60 * Math.atan2(d.z, d.x))); p.y = sflatTop(sflat(p.y, -0.06, 0.004), 0.002, 0.005); return p; }, 96, 48), mat('foil_gold', 0xE8B84A, 0.34, { metalness: 0.3 }), 'choc_foil', C);
  const wrap = mesh(warpSphere((d) => { const p = superF(0.158, 0.23, 0.057, 6, 6)(d); p.y = sflatTop(p.y, -0.022, 0.006); return p; }), mat('choc_wrapper', 0xD8475E, 0.6), 'choc_wrapper', C);
  const label = stick(C, ell('choc_label', mat('choc_label', 0xFFF1DC, 0.8), null, null, [0.098, 0.07, 0.016]), hitFront([wrap], 0, -0.125), -0.008);
  mesh(new THREE.BoxGeometry(0.018, 0.19, 0.006), mat('choc_wrapper_seam', 0xB8364C, 0.65), 'choc_wrapper_seam', C, [0, -0.125, -0.058]);
  face(C, [label], { y: -0.112, dx: 0.045, eyeR: 0.017, mouth: 'smile', mw: 0.016, my: 0.032, bx: 0.072, by: 0.022, br: 0.014 });
  t.targets = [wrap, body];
  return finalize(t);
}

function Birdie() {
  const t = makeRoot('Birdie'), C = t.content;
  const base = 0x8BD0F3, ft = tint(base, 0x5AAEE6);
  const g = warpSphere((d) => { const p = superF(0.19, 0.205, 0.18)(d); const k = 1 + 0.1 * Math.min(1, Math.max(0, -p.y / 0.2)); p.x *= k; p.z *= k; p.y = sflat(p.y, -0.165, 0.025); return p; });
  colorize(g, (p) => mix(ft, smooth(0.0, 0.2, p.y)));
  const body = mesh(g, vc('birdie_body', base, 0.76), 'birdie_body', C);
  const belly = stick(C, ell('birdie_belly', mat('birdie_belly', 0xFFF4DA, 0.85), null, null, [0.115, 0.095, 0.045]), hitFront([body], 0, -0.1), -0.026);
  face(C, [body], { y: 0.075, dx: 0.072, eyeR: 0.023, eyes: 'big', mouth: 'none', bx: 0.12, by: 0.065 });
  const beak = stickY(C, mesh(lathe([[0.032, 0], [0.028, 0.02], [0.016, 0.04], [0.004, 0.052], [0, 0.054]], 24, 16), mat('birdie_beak', 0xFFA64D, 0.6), 'birdie_beak'), hitFront([body], 0, 0.035), -0.01);
  beak.rotateX(0.25);
  const wm = mat('birdie_wing', 0x5FB0E8, 0.74);
  for (const s of [-1, 1]) {
    const pv = pivot('birdie_wing_' + (s < 0 ? 'R' : 'L'), C, [s * 0.172, 0.06, -0.01]);
    pv.rotation.set(0.15, 0, s * 0.32);
    ell('birdie_wing', wm, pv, [0, -0.065, 0], [0.03, 0.09, 0.065]);
    ell('birdie_wing_tip', wm, pv, [0, -0.12, -0.03], [0.022, 0.04, 0.035]);
    sec(t, pv, 'z', 1.6, s);
  }
  const tail = pivot('birdie_tail', C, [0, -0.06, -0.165]);
  [-0.45, 0, 0.45].forEach((a) => { const f = pivot('birdie_feather', tail, null, null); f.rotation.set(-0.95, 0, a); ell('birdie_tail_feather', wm, f, [0, 0.055, 0], [0.028, 0.065, 0.012]); });
  sec(t, tail, 'x', 1.0);
  const tuft = mat('birdie_tuft', 0x5FB0E8, 0.74);
  mesh(new THREE.TorusGeometry(0.028, 0.011, 10, 20, Math.PI * 1.3), tuft, 'birdie_tuft', C, [0, 0.215, 0.01], [0, Math.PI / 2, -0.4]);
  mesh(new THREE.TorusGeometry(0.018, 0.009, 10, 20, Math.PI * 1.3), tuft, 'birdie_tuft_small', C, [0.015, 0.21, -0.03], [0, Math.PI / 2, -0.2]);
  const fm = mat('birdie_feet', 0xFFA64D, 0.6);
  for (const s of [-1, 1]) { ell('birdie_foot', fm, C, [s * 0.065, -0.183, 0.11], [0.035, 0.014, 0.045]); for (const k of [-1, 0, 1]) ell('birdie_toe', fm, C, [s * 0.065 + k * 0.018, -0.183, 0.15], 0.012); }
  t.targets = [body, belly];
  return finalize(t);
}

function Donut() {
  const t = makeRoot('Donut'), C = t.content;
  const R = 0.17, r = 0.088, SZ = 0.82;
  const dough = mesh(new THREE.TorusGeometry(R, r, 40, 128), mat('donut_dough', 0xE6A35E, 0.72), 'donut_dough', C, null, null, [1, 1, SZ]);
  const A = (phi) => 1.28 + 0.2 * Math.sin(5 * phi + 0.6) + 0.12 * Math.sin(11 * phi + 2.0) + 0.06 * Math.sin(17 * phi);
  const ice = (u, v, extra = 0) => { const phi = u * Math.PI * 2, a = A(phi), beta = Math.PI / 2 - a + 2 * a * v; const rr = r * (0.985 + 0.085 * Math.pow(Math.max(0, Math.sin(Math.PI * v)), 0.3)) + extra; const ex = Math.cos(phi), ey = Math.sin(phi); return V3((R + rr * Math.cos(beta)) * ex, (R + rr * Math.cos(beta)) * ey, rr * Math.sin(beta)); };
  const icing = mesh(paramSurface(ice, 200, 40, { wrapU: true, inside: (u) => V3(R * Math.cos(u * Math.PI * 2), R * Math.sin(u * Math.PI * 2), 0) }), mat('donut_icing', 0xF68FB4, 0.45), 'donut_icing', C, null, null, [1, 1, SZ]);
  const rand = rng(7), cols = [0xFFFFFF, 0x6EC6F5, 0xFFD54A, 0x7EDDB5], bins = [[], [], [], []];
  const cap = new THREE.CapsuleGeometry(0.0055, 0.02, 3, 8);
  for (let i = 0; i < 64; i++) {
    const u = rand(), v = 0.18 + rand() * 0.64, phi = u * Math.PI * 2;
    let dphi = Math.abs(((phi - Math.PI * 1.5 + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
    if (dphi < 0.8 && v > 0.28 && v < 0.72) continue;
    const p = ice(u, v, 0.001), c0 = V3(R * Math.cos(phi), R * Math.sin(phi), 0);
    const n = p.clone().sub(c0); p.z *= SZ; n.z /= SZ; n.normalize();
    const tg = V3(rand() - 0.5, rand() - 0.5, rand() - 0.5).cross(n).normalize();
    const m = new THREE.Mesh(cap); m.position.copy(p); m.quaternion.setFromUnitVectors(YA, tg);
    bins[i % 4].push(m);
  }
  bins.forEach((b, i) => mesh(bake(b), mat('sprinkle_' + i, cols[i], 0.5), 'donut_sprinkles_' + i, C));
  const fry = mat('donut_fry_line', 0xF7DCAA, 0.8);
  mesh(new THREE.TorusGeometry(R + r * 0.995, 0.009, 8, 160), fry, 'donut_fry_outer', C);
  mesh(new THREE.TorusGeometry(R - r * 0.995, 0.007, 8, 100), fry, 'donut_fry_inner', C);
  face(C, [icing], { y: -0.152, dx: 0.062, eyeR: 0.021, mouth: 'smile', mw: 0.02, my: 0.04, bx: 0.11, by: 0.02, br: 0.02 });
  t.targets = [icing, dough];
  return finalize(t);
}

function dragonHorns(C, targets, s = 1) {
  const hg = lathe([[0.03, 0], [0.027, 0.03], [0.018, 0.06], [0.008, 0.08], [0, 0.088]], 24, 16), hm = mat('dragon_horn', 0xFFE2A0, 0.55);
  for (const sx of [-1, 1]) { const h = stickY(C, mesh(hg, hm, 'dragon_horn', null, null, null, s), hitTop(targets, sx * 0.09 * s, -0.01 * s), -0.012 * s); h.rotateX(-0.45); h.rotateZ(-sx * 0.15); }
}
function Dragon() {
  const t = makeRoot('Dragon'), C = t.content;
  const base = 0x5ECBA8, fd = tint(base, 0x3BA58A);
  const g = lathe([[0, 0], [0.12, 0.004], [0.175, 0.03], [0.2, 0.1], [0.192, 0.18], [0.165, 0.245], [0.158, 0.28], [0.172, 0.33], [0.182, 0.4], [0.165, 0.47], [0.115, 0.53], [0.05, 0.556], [0, 0.56]], 64, 64);
  colorize(g, (p, n) => mix(fd, smooth(0.25, 0.56, p.y) * 0.7 + smooth(0.0, -0.8, n.z) * 0.5));
  const body = mesh(g, vc('dragon_body', base, 0.7), 'dragon_body', C, null, null, [1, 1, 0.9]);
  const teal = mat('dragon_teal', 0x4FBE9B, 0.7), lilac = mat('dragon_lilac', 0xB892F0, 0.68), cream = mat('dragon_belly', 0xFFF0C8, 0.85);
  const muzzle = stick(C, ell('dragon_muzzle', mat('dragon_muzzle', 0xA9EBD4, 0.72), null, null, [0.105, 0.066, 0.07]), hitFront([body], 0, 0.355), -0.036);
  for (const s of [-1, 1]) stick(C, ell('dragon_nostril', mat('dragon_nostril', 0x2F7D68, 0.6), null, null, [0.008, 0.006, 0.004]), hitFront([muzzle], s * 0.03, 0.378), 0);
  face(C, [body, muzzle], { y: 0.452, dx: 0.078, eyeR: 0.026, eyes: 'big', mouth: 'smile', mw: 0.024, my: 0.098, fang: true, bx: 0.135, by: 0.06 });
  dragonHorns(C, [body]);
  for (const s of [-1, 1]) { const f = stickY(C, pivot('dragon_fin', null), hit([body], s * 5, 0.43, -0.01, -s, 0, 0), -0.01); f.rotateX(-0.5); ell('dragon_fin', lilac, f, [0, 0.03, 0], [0.034, 0.05, 0.01]); sec(t, f, 'x', 0.8); }
  const sg = lathe([[0.026, 0], [0.023, 0.018], [0.012, 0.034], [0, 0.046]], 20, 12);
  [[0.5, 0.9], [0.4, 1], [0.28, 0.9], [0.16, 0.75]].forEach(([y, k]) => { const m = stickY(C, mesh(sg, lilac, 'dragon_spike', null, null, null, [k * 1.15, k * 1.6, k * 0.8]), hitBack([body], 0, y), -0.01); m.rotateX(-0.4); });
  const belly = stick(C, ell('dragon_belly', cream, null, null, [0.125, 0.11, 0.05]), hitFront([body], 0, 0.12), -0.026);
  const plate = mat('dragon_belly_plate', 0xF1DCA6, 0.85);
  [0.085, 0.12, 0.155].forEach((y, i) => { const gg = group('dragon_plate'); mesh(new THREE.CapsuleGeometry(0.005, 0.11 - Math.abs(i - 1) * 0.025, 4, 8), plate, 'dragon_belly_plate', gg, null, [0, 0, Math.PI / 2]); stick(C, gg, hitFront([belly], 0, y), -0.002); });
  for (const s of [-1, 1]) stick(C, ell('dragon_arm', teal, null, null, [0.04, 0.03, 0.035]), hitFront([body], s * 0.135, 0.17), -0.016);
  const claw = mat('dragon_claw', 0xFFF6E6, 0.5);
  for (const s of [-1, 1]) { ell('dragon_foot', teal, C, [s * 0.085, 0.024, 0.13], [0.055, 0.03, 0.06]); for (const k of [-1, 0, 1]) ell('dragon_claw', claw, C, [s * 0.085 + k * 0.022, 0.022, 0.186], 0.0095); }
  const ws = new THREE.Shape();
  ws.moveTo(0, 0); ws.quadraticCurveTo(0.05, 0.12, 0.15, 0.14); ws.quadraticCurveTo(0.13, 0.08, 0.15, 0.03); ws.quadraticCurveTo(0.11, 0.04, 0.1, -0.01); ws.quadraticCurveTo(0.07, 0.03, 0.04, -0.03); ws.quadraticCurveTo(0.03, 0.0, 0, 0);
  const wg = new THREE.ExtrudeGeometry(ws, { depth: 0.008, bevelEnabled: true, bevelThickness: 0.006, bevelSize: 0.006, bevelSegments: 3, curveSegments: 16 });
  const wmat = mat('dragon_wing', 0xC6A3F4, 0.7);
  for (const s of [-1, 1]) { const pv = pivot('dragon_wing_' + (s < 0 ? 'R' : 'L'), C, [s * 0.07, 0.26, -0.12]); pv.rotation.set(0, s * 0.6, s * 0.25); mesh(wg, wmat, 'dragon_wing', pv, null, null, [s, 1, 1]); sec(t, pv, 'y', 1.4, s); }
  const tl = tubeAt('dragon_tail', teal, C, [[0, 0.08, -0.12], [0.03, 0.045, -0.24], [0.13, 0.03, -0.3], [0.22, 0.06, -0.25], [0.25, 0.1, -0.17]], (u) => roundEnd(u, 0.05 * (1 - u) + 0.016, 0.9), 48, 14);
  const end = tl.curve.getPointAt(1).sub(V3(0, 0.08, -0.12)), tan = tl.curve.getTangentAt(1);
  const spade = ell('dragon_tail_spade', lilac, tl.pivot, null, [0.04, 0.045, 0.012]);
  spade.position.copy(end).addScaledVector(tan, 0.022); spade.quaternion.setFromUnitVectors(YA, tan);
  sec(t, tl.pivot, 'y', 0.8);
  t.targets = [body, muzzle];
  return finalize(t);
}
export function DragonHead() {
  const C = new THREE.Group(); C.name = 'FX_DragonHead';
  const head = ell('dh_head', mat('dragon_teal', 0x4FBE9B, 0.7), C, [0, 0, 0], [0.19, 0.16, 0.18]);
  const muzzle = ell('dh_muzzle', mat('dragon_muzzle', 0xA9EBD4, 0.72), C, [0, -0.04, 0.15], [0.12, 0.08, 0.11]);
  ell('dh_jaw', mat('face_mouth', 0x9c2f47, 0.55), C, [0, -0.085, 0.17], [0.085, 0.03, 0.08]);
  face(C, [head, muzzle], { y: 0.07, dx: 0.085, eyeR: 0.03, eyes: 'big', mouth: 'none', bx: 0.14, by: 0.06 });
  dragonHorns(C, [head], 1.25);
  const lilac = mat('dragon_lilac', 0xB892F0, 0.68);
  for (const s of [-1, 1]) { const f = stickY(C, pivot('dh_fin', null), hit([head], s * 5, 0.0, -0.03, -s, 0, 0), -0.01); f.rotateX(-0.7); ell('dh_fin', lilac, f, [0, 0.05, 0], [0.05, 0.08, 0.012]); }
  return C;
}

/* ---------------- six new originals ---------------- */
function MochiFox() {
  const t = makeRoot('MochiFox'), C = t.content;
  const base = 0xFFF8EF, fo = tint(base, 0xF39A4C);
  const g = warpSphere((d) => { const p = superF(0.25, 0.165, 0.225, 2.2, 2.1)(d); const k = 1 + 0.13 * smooth(0.05, -0.16, p.y); p.x *= k; p.z *= k; p.y = sflat(p.y, -0.11, 0.03); return p; });
  colorize(g, (p) => mix(fo, smooth(0.03, 0.08, p.y - 0.085 * (p.z / 0.225) - 0.04 * Math.abs(p.x) / 0.25)));
  const body = mesh(g, vc('mochi_fox_body', base, 0.6), 'mochi_body', C);
  const orange = 0xF39A4C;
  const eg = lathe([[0.06, 0], [0.056, 0.035], [0.042, 0.075], [0.022, 0.11], [0.006, 0.13], [0, 0.133]], 32, 24);
  colorize(eg, (p) => mix(tint(orange, 0x7A3E22), smooth(0.085, 0.118, p.y)));
  const em = vc('mochi_fox_ear', orange, 0.65), im = mat('mochi_fox_ear_inner', 0xFFE7D2, 0.85);
  for (const s of [-1, 1]) { const pv = stickY(C, pivot('fox_ear', null), hitTop([body], s * 0.13, 0.0), -0.02); pv.rotateZ(-s * 0.28); mesh(eg, em, 'fox_ear', pv, null, null, [1, 1, 0.6]); mesh(eg, im, 'fox_ear_inner', pv, [0, 0.008, 0.02], null, [0.58, 0.68, 0.28]); sec(t, pv, 'x', 1.0); }
  const tc = curve([[0, 0.06, -0.19], [0.12, 0.05, -0.27], [0.25, 0.06, -0.2], [0.29, 0.08, -0.06], [0.24, 0.12, 0.04]]);
  const tg = taperTube(tc, (u) => 0.075 * Math.pow(Math.max(0, Math.sin(Math.PI * (0.12 + 0.88 * u))), 0.7), 56, 18);
  const uv = tg.attributes.uv, col = new Float32Array(uv.count * 3), fT = tint(0xFFFFFF, orange);
  for (let i = 0; i < uv.count; i++) { const c = mix(fT, 1 - smooth(0.74, 0.84, uv.getX(i))); col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b; }
  tg.setAttribute('color', new THREE.BufferAttribute(col, 3));
  tg.translate(0, -0.06, 0.19);
  const tp = pivot('fox_tail_pivot', C, [0, 0.06, -0.19]);
  mesh(tg, vc('mochi_fox_tail', 0xFFFFFF, 0.8), 'fox_tail', tp);
  sec(t, tp, 'y', 0.9);
  face(C, [body], { y: 0.03, dx: 0.075, eyeR: 0.022, eyes: 'happy', mouth: 'cat', mw: 0.02, my: 0.04, bx: 0.13, by: 0.022, br: 0.028 });
  const pin = group('sakura_pin'), pm = mat('sakura_petal', 0xFFB3C8, 0.7);
  for (let i = 0; i < 5; i++) { const a = (i / 5) * Math.PI * 2; ell('sakura_petal', pm, pin, [Math.cos(a) * 0.016, Math.sin(a) * 0.016, 0], [0.013, 0.009, 0.005], [0, 0, a]); }
  ell('sakura_center', mat('sakura_center', 0xFFD25E, 0.6), pin, [0, 0, 0.004], 0.006);
  stick(C, pin, hitTop([body], -0.075, 0.1), 0.002);
  t.targets = [body];
  return finalize(t);
}

function StrawberryFrog() {
  const t = makeRoot('StrawberryFrog'), C = t.content;
  const red = mat('strawberry_red', 0xEE4A5C, 0.62);
  const body = mesh(warpSphere((d) => { const p = superF(0.215, 0.215, 0.2)(d); const k = 0.6 + 0.4 * smooth(-0.95, 0.45, d.y); p.x *= k; p.z *= k; p.y = sflat(p.y, -0.15, 0.03); return p; }), red, 'frog_body', C);
  const seeds = [];
  for (let row = 0; row < 7; row++) {
    const y = -0.62 + row * 0.19, n = 11;
    for (let i = 0; i < n; i++) {
      const a = ((i + (row % 2) * 0.5) / n) * Math.PI * 2, rr = Math.sqrt(1 - y * y), dir = V3(Math.cos(a) * rr, y, Math.sin(a) * rr);
      if (dir.z > 0.45 && y > -0.35) continue;
      const h = hitDir([body], V3(0, 0, 0), dir); if (!h) continue;
      const m = new THREE.Mesh(UNIT); m.scale.set(0.007, 0.011, 0.004); m.position.copy(h.p).addScaledVector(h.n, -0.001); m.quaternion.setFromUnitVectors(V3(0, 0, 1), h.n); seeds.push(m);
    }
  }
  mesh(bake(seeds), mat('strawberry_seed', 0xFFE07A, 0.5), 'frog_seeds', C);
  const bumps = [-1, 1].map((s) => ell('frog_eye_bump', red, C, [s * 0.095, 0.17, 0.045], 0.068));
  face(C, [...bumps, body], { y: 0.18, dx: 0.095, eyeR: 0.03, eyes: 'big', mouth: 'smile', mw: 0.036, my: 0.105, mt: 0.0055, bx: 0.15, by: 0.1, br: 0.026 });
  const green = mat('frog_green', 0x6CC56A, 0.7);
  const cal = group('frog_calyx', C, [0, 0.205, -0.055]);
  for (let i = 0; i < 6; i++) { const a = (i / 6) * Math.PI * 2; const l = group('leaf', cal, null, [0, -a, 0]); ell('frog_leaf', green, l, [0.04, 0, 0], [0.045, 0.007, 0.02], [0, 0, -0.25]); }
  const st = tubeAt('frog_stem', mat('frog_stem', 0x4FA650, 0.7), cal, [[0, 0, 0], [0.005, 0.03, -0.005], [0.02, 0.05, -0.01]], (u) => roundEnd(u, 0.011, 0.85), 16, 10);
  sec(t, cal, 'x', 0.7);
  for (const s of [-1, 1]) { ell('frog_foot', green, C, [s * 0.08, -0.168, 0.11], [0.05, 0.02, 0.045]); for (const k of [-1, 0, 1]) ell('frog_toe', green, C, [s * 0.08 + k * 0.026, -0.168, 0.152], 0.014); }
  t.targets = [body];
  return finalize(t);
}

function BobaBear() {
  const t = makeRoot('BobaBear'), C = t.content;
  const cup = mesh(lathe([[0, 0], [0.11, 0], [0.13, 0.008], [0.138, 0.03], [0.152, 0.12], [0.166, 0.22], [0.175, 0.3], [0.172, 0.31]], 64, 40), mat('boba_milk_tea', 0xDDB68D, 0.72), 'boba_cup', C);
  const brown = mat('boba_bear_brown', 0xB07A52, 0.76);
  const lid = mesh(lathe([[0.18, 0.295], [0.186, 0.315], [0.178, 0.35], [0.15, 0.405], [0.1, 0.445], [0.04, 0.462], [0, 0.465]], 64, 40), brown, 'boba_bear_head', C);
  mesh(new THREE.TorusGeometry(0.182, 0.012, 10, 72), mat('boba_rim', 0xFFF0DA, 0.7), 'boba_rim', C, [0, 0.305, 0], [Math.PI / 2, 0, 0]);
  const inner = mat('boba_ear_inner', 0xE8C29A, 0.8);
  for (const s of [-1, 1]) { const e = stickY(C, pivot('bear_ear', null), hitTop([lid], s * 0.115, -0.005), -0.012); ell('bear_ear', brown, e, [0, 0.03, 0], [0.05, 0.048, 0.03]); ell('bear_ear_inner', inner, e, [0, 0.03, 0.014], [0.03, 0.03, 0.02]); sec(t, e, 'x', 0.7); }
  const muzzle = stick(C, ell('bear_muzzle', mat('bear_muzzle', 0xF6E2C6, 0.82), null, null, [0.062, 0.042, 0.03]), hitFront([lid], 0, 0.345), -0.012);
  stick(C, ell('bear_nose', mat('face_ink', 0x2a1a22, 0.3), null, null, [0.018, 0.012, 0.01]), hitFront([muzzle], 0, 0.36), -0.002);
  face(C, [lid, muzzle], { y: 0.405, dx: 0.065, eyeR: 0.02, mouth: 'cat', mw: 0.016, my: 0.05, bx: 0.11, by: 0.04, br: 0.02 });
  const pearls = [];
  [0.045, 0.088].forEach((y, row) => { for (let i = 0; i < 11; i++) { const a = ((i + row * 0.5) / 11) * Math.PI * 2; const h = hitDir([cup], V3(0, y, 0), V3(Math.cos(a), 0, Math.sin(a))); if (!h) continue; const m = new THREE.Mesh(UNIT); m.scale.setScalar(0.026); m.position.copy(h.p).addScaledVector(h.n, -0.012); pearls.push(m); } });
  mesh(bake(pearls), mat('boba_pearl', 0x3A2420, 0.28), 'boba_pearls', C);
  const st = tubeAt('boba_straw', mat('boba_straw', 0xFF8FB0, 0.5), C, [[0.05, 0.38, -0.03], [0.075, 0.5, -0.06], [0.1, 0.6, -0.085]], () => 0.019, 24, 16);
  const end = st.curve.getPointAt(1), tan = st.curve.getTangentAt(1);
  const capm = mesh(new THREE.CylinderGeometry(0.0192, 0.0192, 0.004, 20), mat('boba_straw_end', 0xE06A90, 0.55), 'boba_straw_end', C);
  capm.position.copy(end); capm.quaternion.setFromUnitVectors(YA, tan);
  t.targets = [lid, muzzle];
  return finalize(t);
}

function PancakePup() {
  const t = makeRoot('PancakePup'), C = t.content;
  const base = 0xF8DDA9, fb = tint(base, 0xD98F45);
  const pg = warpSphere(superF(0.19, 0.034, 0.19, 2, 3.2), 72, 32);
  colorize(pg, (p, n) => mix(fb, smooth(0.5, 0.85, Math.abs(n.y))));
  const pm = vc('pancake', base, 0.78);
  const bot = mesh(pg, pm, 'pancake_bottom', C, [0.008, 0.034, 0], [0, 0.3, 0]);
  const mid = mesh(pg, pm, 'pancake_middle', C, [-0.008, 0.1, 0.004], [0, 1.1, 0]);
  const top = mesh(pg, pm, 'pancake_top', C, [0, 0.166, 0], [0, 2.0, 0]);
  mesh(warpSphere(superF(0.045, 0.02, 0.045, 5, 5), 32, 24), mat('butter_block', 0xFBE38C, 0.55), 'pancake_butter', C, [0.02, 0.212, -0.02], [0, 0.4, 0]);
  const drips = [[0.4, 0.07], [2.3, 0.085], [3.3, 0.06], [4.3, 0.09], [5.4, 0.075], [6.0, 0.05]];
  const sy = warpSphere((d) => { const p = superF(0.194, 0.0365, 0.194, 2, 3.2)(d); const phi = Math.atan2(p.z, p.x); let yc = 0.024; for (const [a, amp] of drips) { const dd = Math.atan2(Math.sin(phi - a), Math.cos(phi - a)); yc -= amp * Math.exp(-Math.pow(dd / 0.11, 2)); } p.y = sflat(p.y, yc, 0.005); return p; }, 128, 48);
  mesh(sy, mat('syrup', 0xC8752A, 0.22), 'pancake_syrup', C, [0, 0.166, 0]);
  const brown = mat('pup_ear', 0x9B6338, 0.78);
  for (const s of [-1, 1]) { const pv = pivot('pup_ear', C, [s * 0.165, 0.19, 0.03]); pv.rotation.z = s * 0.22; ell('pup_ear', brown, pv, [0, -0.07, 0], [0.05, 0.085, 0.022]); sec(t, pv, 'z', 1.6, s); }
  face(C, [top, mid], { y: 0.168, dx: 0.06, eyeR: 0.02, mouth: 'cat', mw: 0.016, my: 0.078, tongue: true, bx: 0.11, by: 0.012, br: 0.02 });
  stick(C, ell('pup_nose', mat('face_ink', 0x2a1a22, 0.3), null, null, [0.022, 0.016, 0.012]), hitFront([mid], 0, 0.116), -0.003);
  const tl = tubeAt('pup_tail', brown, C, [[0, 0.1, -0.18], [0.0, 0.14, -0.235], [0.03, 0.18, -0.25]], (u) => roundEnd(u, 0.02, 0.75), 20, 12);
  sec(t, tl.pivot, 'z', 2.0);
  t.targets = [top, mid];
  return finalize(t);
}

function CloudBunny() {
  const t = makeRoot('CloudBunny'), C = t.content;
  const lumps = [[0, 1, 0.2, 0.12], [0.7, 0.6, 0, 0.13], [-0.7, 0.6, 0, 0.13], [0.5, 0.5, -0.6, 0.12], [-0.5, 0.5, -0.6, 0.12], [1, 0, 0.2, 0.14], [-1, 0, 0.2, 0.14], [0.6, 0.1, -0.8, 0.12], [-0.6, 0.1, -0.8, 0.12], [0, 0.4, -1, 0.13], [0.9, -0.3, 0.5, 0.1], [-0.9, -0.3, 0.5, 0.1], [0, -0.2, -1, 0.1]].map(([x, y, z, a]) => ({ d: V3(x, y, z).normalize(), a }));
  const base = 0xF8F5FF, fl = tint(base, 0xD5C8F6);
  const g = warpSphere((d) => { const p = superF(0.24, 0.17, 0.19)(d); let b = 0; for (const l of lumps) b += l.a * 1.5 * Math.exp(-(1 - d.dot(l.d)) / 0.045); p.multiplyScalar(1 + b); p.y = sflat(p.y, -0.12, 0.03); return p; }, 96, 64);
  colorize(g, (p) => mix(fl, smooth(0.0, -0.14, p.y)));
  const body = mesh(g, vc('cloud_bunny_body', base, 0.88), 'cloud_body', C);
  const em = mat('cloud_bunny_ear', 0xF3EEFF, 0.85), pink = mat('cloud_bunny_ear_inner', 0xFFC2D6, 0.85);
  const earR = (u) => 0.04 * Math.pow(Math.max(0, Math.sin(Math.PI * (0.1 + 0.9 * u))), 0.5);
  [[[0.07, 0.14, -0.01], [0.085, 0.26, -0.03], [0.1, 0.36, -0.06], [0.11, 0.43, -0.09]], [[-0.07, 0.14, -0.01], [-0.09, 0.26, -0.02], [-0.15, 0.31, -0.02], [-0.22, 0.3, 0.0]]].forEach((pts, i) => {
    const ear = tubeAt('bunny_ear_' + (i ? 'R' : 'L'), em, C, pts, earR, 36, 14);
    ear.pivot.scale.z = 0.6;
    const ip = pts.map((p) => [p[0] - pts[0][0], p[1] - pts[0][1], p[2] - pts[0][2] + 0.026]);
    mesh(taperTube(curve(ip), (u) => earR(u) * 0.55, 36, 10), pink, 'bunny_ear_inner', ear.pivot);
    sec(t, ear.pivot, 'x', 1.1);
  });
  face(C, [body], { y: 0.02, dx: 0.075, eyeR: 0.025, eyes: 'big', mouth: 'smile', mw: 0.014, my: 0.04, teeth: true, bx: 0.13, by: 0.025 });
  const rb = group('cloud_rainbow');
  [[0.06, 0xFF9BB8], [0.047, 0xFFE27A], [0.034, 0x8EE0C4]].forEach(([R, c], i) => mesh(new THREE.TorusGeometry(R, 0.0072, 10, 32, Math.PI), mat('rainbow_' + i, c, 0.6), 'cloud_rainbow_band', rb));
  stick(C, rb, hitBack([body], 0, -0.04), -0.004);
  t.targets = [body];
  return finalize(t);
}

function CupcakeAxolotl() {
  const t = makeRoot('CupcakeAxolotl'), C = t.content;
  const liner = mesh(paramSurface((u, v) => { const phi = u * Math.PI * 2; let y, rr; if (v < 0.1) { y = 0; rr = 0.13 * (1 + 0.028 * Math.cos(28 * phi)) * (v / 0.1); } else { const w = (v - 0.1) / 0.9; y = 0.16 * w; rr = (0.13 + 0.05 * w) * (1 + 0.028 * Math.cos(28 * phi)); } return V3(rr * Math.cos(phi), y, -rr * Math.sin(phi)); }, 224, 30, { wrapU: true, inside: () => V3(0, 0.08, 0), fallback: V3(0, -1, 0) }), mat('cupcake_liner', 0x8FDCC4, 0.75), 'cupcake_liner', C);
  mesh(new THREE.TorusGeometry(0.182, 0.011, 10, 72), mat('cupcake_liner_rim', 0xC4F0E1, 0.7), 'cupcake_rim', C, [0, 0.16, 0], [Math.PI / 2, 0, 0]);
  const frost = mesh(warpSphere((d) => { const p = superF(0.19, 0.15, 0.18)(d); const phi = Math.atan2(p.z, p.x); const fm = smooth(0.1, 0.45, d.z) * (1 - smooth(0.6, 0.85, Math.abs(d.x))) * (1 - smooth(0.82, 0.97, d.y)); p.multiplyScalar(1 + 0.035 * Math.sin(3 * phi + 16 * d.y) * (1 - fm) * smooth(-0.2, 0.2, d.y)); p.y = sflat(p.y, -0.01, 0.012); return p; }, 96, 64), mat('axolotl_frosting', 0xF9AFCB, 0.55), 'axolotl_frosting_head', C, [0, 0.155, 0]);
  const gm = mat('axolotl_gill', 0xE7609F, 0.62);
  for (const s of [-1, 1]) for (const k of [-1, 0, 1]) {
    const g = tubeAt('axolotl_gill', gm, C, [[s * 0.15, 0.245 + 0.04 * k, -0.01], [s * 0.21, 0.265 + 0.06 * k, -0.02], [s * 0.255, 0.285 + 0.09 * k, -0.03]], (u) => roundEnd(u, 0.019 * (0.65 + 0.35 * Math.abs(Math.sin(u * Math.PI * 4))), 0.8), 28, 10);
    sec(t, g.pivot, 'z', 1.4, s);
  }
  face(C, [frost], { y: 0.245, dx: 0.084, eyeR: 0.02, mouth: 'smile', mw: 0.03, my: 0.045, bx: 0.135, by: 0.03 });
  const hm = mat('axolotl_hand', 0xF7A0C0, 0.6);
  for (const s of [-1, 1]) ell('axolotl_hand', hm, C, [s * 0.07, 0.158, 0.185], [0.03, 0.02, 0.022]);
  const rand = rng(11), cols = [0xFFFFFF, 0xFFD54A, 0x6EC6F5], bins = [[], [], []], cap = new THREE.CapsuleGeometry(0.005, 0.018, 3, 8);
  for (let i = 0; i < 18; i++) { const a = rand() * Math.PI * 2, rr = 0.03 + rand() * 0.09; const x = Math.cos(a) * rr, z = Math.sin(a) * rr; if (z > 0.05) continue; const h = hitTop([frost], x, z); if (!h) continue; const m = new THREE.Mesh(cap); m.position.copy(h.p); m.quaternion.setFromUnitVectors(YA, V3(rand() - 0.5, 0, rand() - 0.5).normalize()); bins[i % 3].push(m); }
  bins.forEach((b, i) => b.length && mesh(bake(b), mat('sprinkle_ax_' + i, cols[i], 0.5), 'axolotl_sprinkles', C));
  t.targets = [frost];
  return finalize(t);
}

/* ---------------- catalog ---------------- */
export const RARITY = { Common: '#7C8A96', Uncommon: '#3FAF7E', Epic: '#9A63E8', Exclusive: '#E8A23A' };
const T = (a, b, w, life, shape, pcols, rate, extra = {}) => Object.assign({ a, b, w, life, shape, pcols, rate }, extra);
export const CATALOG = [
  { id: 'KittyBread', name: 'Kitty Bread', rarity: 'Common', existing: true, build: KittyBread, flight: 'tumble', squeeze: { depth: 0.6, kRel: 34, cRel: 8.5, widen: 0.72, pitch: 1.0 }, trail: T(0xF7D9A8, 0xD9934E, 0.11, 0.32, 'cube', [0xE9B575, 0xF6DDB0], 26), note: 'Bread settles slowly; ears lag and spring back.' },
  { id: 'Toast', name: 'Toast', rarity: 'Common', existing: true, build: Toast, flight: 'frisbee', squeeze: { depth: 0.66, kRel: 40, cRel: 9, widen: 0.6, pitch: 0.9 }, trail: T(0xFBEBC9, 0xC9803F, 0.1, 0.3, 'cube', [0xC9803F, 0xFDF0D3], 22), note: 'Slab compresses face-on; crust edges stay crisp.' },
  { id: 'Banana', name: 'Banana', rarity: 'Common', existing: true, build: Banana, flight: 'spiral', squeeze: { depth: 0.7, kRel: 48, cRel: 9, widen: 0.55, pitch: 1.15 }, trail: T(0xFFE98A, 0xFFD23F, 0.09, 0.3, 'sphere', [0xFFE067, 0xC9D85A], 18), note: 'Curvature flattens then re-arcs; stem stays rigid.' },
  { id: 'Butter', name: 'Butter', rarity: 'Uncommon', existing: true, build: Butter, flight: 'tumble', squeeze: { depth: 0.62, kRel: 30, cRel: 9.5, widen: 0.7, pitch: 0.85 }, trail: T(0xFFF4C2, 0xF6D35C, 0.12, 0.36, 'sphere', [0xFBE38C, 0xFFF5DE], 24, { gravity: -3 }), note: 'Soft block, wrapper creases on compression.' },
  { id: 'Chocolate', name: 'Chocolate', rarity: 'Uncommon', existing: true, build: Chocolate, flight: 'frisbee', squeeze: { depth: 0.68, kRel: 42, cRel: 9, widen: 0.58, pitch: 0.8 }, trail: T(0x8A5236, 0xD8475E, 0.1, 0.34, 'cube', [0x6E3D2B, 0xE8B84A], 24, { sparkle: 0xE8B84A }), note: 'Squares pillow outward; foil frill flutters.' },
  { id: 'Birdie', name: 'Birdie', rarity: 'Epic', existing: true, build: Birdie, flight: 'glide', squeeze: { depth: 0.6, kRel: 56, cRel: 8, widen: 0.7, pitch: 1.45 }, trail: T(0xBFE7FA, 0x5FB0E8, 0.05, 0.42, 'petal', [0xFFFFFF, 0x8BD0F3], 20, { twin: 0.17, sparkle: 0xFFFFFF }), note: 'Wings flare on release, tail feathers flick once.' },
  { id: 'Donut', name: 'Donut', rarity: 'Epic', existing: true, build: Donut, flight: 'wheel', squeeze: { depth: 0.66, kRel: 46, cRel: 8.5, widen: 0.62, pitch: 1.05 }, trail: T(0xFFC1D8, 0xF68FB4, 0.12, 0.4, 'capsule', [0xFFFFFF, 0x6EC6F5, 0xFFD54A, 0x7EDDB5], 34, { sparkle: 0xFFFFFF }), note: 'Ring compresses as one surface; hole narrows, never closes.' },
  { id: 'Dragon', name: 'Dragon', rarity: 'Exclusive', existing: true, build: Dragon, flight: 'face', squeeze: { depth: 0.64, kRel: 40, cRel: 7.5, widen: 0.66, pitch: 0.7 }, trail: T(0x9EF0D3, 0xB892F0, 0.14, 0.45, 'drop', [0xFF9A4D, 0xFFD25E, 0xB892F0], 40, { sparkle: 0xFFE7A0, ember: true }), note: 'Wings and tail counter-swing; horns stay rigid.' },
  { id: 'MochiFox', name: 'Mochi Fox', rarity: 'Uncommon', existing: false, build: MochiFox, flight: 'tumble', squeeze: { depth: 0.55, kRel: 26, cRel: 8, widen: 0.8, pitch: 1.2 }, trail: T(0xFFF8EF, 0xF39A4C, 0.12, 0.38, 'petal', [0xFFB3C8, 0xFFFFFF], 22), note: 'Mochi sags wide and recovers slowest of all; tail sweeps.' },
  { id: 'StrawberryFrog', name: 'Strawberry Frog', rarity: 'Uncommon', existing: false, build: StrawberryFrog, flight: 'hop', squeeze: { depth: 0.62, kRel: 52, cRel: 8, widen: 0.66, pitch: 1.3 }, trail: T(0xFF9AA8, 0xEE4A5C, 0.1, 0.34, 'heart', [0xEE4A5C, 0xFFE07A, 0x6CC56A], 20), note: 'Eye bumps bob after the body; calyx springs.' },
  { id: 'BobaBear', name: 'Boba Bear', rarity: 'Common', existing: false, build: BobaBear, flight: 'upright', squeeze: { depth: 0.7, kRel: 44, cRel: 9, widen: 0.5, pitch: 0.95 }, trail: T(0xEED6B8, 0xB07A52, 0.09, 0.32, 'sphere', [0x3A2420, 0x5A3A30], 18, { gravity: -6 }), note: 'Cup squeezes at the waist; straw stays straight.' },
  { id: 'PancakePup', name: 'Pancake Pup', rarity: 'Common', existing: false, build: PancakePup, flight: 'frisbee', squeeze: { depth: 0.58, kRel: 36, cRel: 8.5, widen: 0.68, pitch: 1.1 }, trail: T(0xF8DDA9, 0xC8752A, 0.11, 0.34, 'drop', [0xC8752A, 0xFBE38C], 18, { gravity: -5 }), note: 'Layers compress in sequence top-down; ears flop.' },
  { id: 'CloudBunny', name: 'Cloud Bunny', rarity: 'Epic', existing: false, build: CloudBunny, flight: 'float', squeeze: { depth: 0.56, kRel: 30, cRel: 7, widen: 0.8, pitch: 1.35 }, trail: T(0xFFFFFF, 0xD5C8F6, 0.16, 0.5, 'sphere', [0xFFFFFF, 0xE6DEFF], 26, { sparkle: 0xFFE27A }), note: 'Puffs billow, long ears whip and settle.' },
  { id: 'CupcakeAxolotl', name: 'Cupcake Axolotl', rarity: 'Epic', existing: false, build: CupcakeAxolotl, flight: 'wobble', squeeze: { depth: 0.64, kRel: 44, cRel: 7.5, widen: 0.62, pitch: 1.25 }, trail: T(0xFFD0E2, 0x8FDCC4, 0.11, 0.42, 'capsule', [0xFFFFFF, 0xFFD54A, 0x6EC6F5, 0xE7609F], 28, { wavy: 1 }), note: 'Frosting squashes over the liner; gills ripple.' },
];
export const byId = (id) => CATALOG.find((c) => c.id === id);
export function buildToy(id, opts = {}) {
  const c = byId(id); const t = c.build(); t.meta = c; t.root.userData.toyId = id;
  t.faceN = []; t.faceS = []; t.root.traverse((o) => { if (o.name === 'face_normal') t.faceN.push(o); if (o.name === 'face_squish') t.faceS.push(o); });
  t.setFace = (k) => { t.faceN.forEach((g) => (g.visible = k !== 'squish')); t.faceS.forEach((g) => (g.visible = k === 'squish')); t.face = k; };
  if (opts.toon !== false) toonify(t.root, { width: opts.outline ?? 2.6 });
  return t;
}
export function toonHead() { return toonify(DragonHead(), { width: 3 }); }
export const studs = (m) => (m / STUD).toFixed(1);

export class Squisher {
  constructor(toy) { this.toy = toy; this.y = 1; this.v = 0; this.t = 0; this.pressed = false; this.s = toy.sec.map(() => ({ a: 0, v: 0 })); this.phase = 'idle'; }
  press() { this.pressed = true; this.t = 0; this.phase = 'compress'; }
  release() { if (this.pressed) { this.pressed = false; this.phase = 'recover'; } }
  kick(v) { this.v += v; }
  update(dt) {
    const p = this.toy.meta.squeeze;
    let target = 1, k = p.kRel, c = p.cRel;
    if (this.pressed) { this.t += dt; target = this.t < 0.06 ? 1.045 : p.depth + 0.006 * Math.sin(this.t * 42); k = 260; c = 26; if (this.t > 0.25) this.phase = 'hold'; }
    const n = Math.max(1, Math.ceil(dt / (1 / 240))), h = dt / n;
    for (let i = 0; i < n; i++) {
      const a = k * (target - this.y) - c * this.v; this.v += a * h; this.y += this.v * h;
      for (let j = 0; j < this.s.length; j++) { const st = this.s[j], s = this.toy.sec[j]; const aa = 140 * (-this.v * s.amp * 0.12 - st.a) - 8 * st.v; st.v += aa * h; st.a += st.v * h; }
    }
    if (!this.pressed && Math.abs(this.y - 1) < 0.002 && Math.abs(this.v) < 0.01) this.phase = 'idle';
    if (this.toy.setFace && !this.lockFace) { const want = this.y < 0.86 ? 'squish' : 'normal'; if (this.toy.face !== want) this.toy.setFace(want); }
    const w = 1 + (1 - this.y) * p.widen;
    this.toy.squash.scale.set(w, this.y, w);
    for (let j = 0; j < this.s.length; j++) { const s = this.toy.sec[j]; s.obj.rotation[s.axis] = s.base + this.s[j].a * s.sign; }
  }
}
