import { THREE } from './kit.js';

const grad = (() => { const t = new THREE.DataTexture(new Uint8Array([110, 175, 230, 255]), 4, 1, THREE.RedFormat); t.minFilter = t.magFilter = THREE.NearestFilter; t.generateMipmaps = false; t.needsUpdate = true; return t; })();
export const OUTLINE = { res: { value: new THREE.Vector2(1280, 720) } };
export function setOutlineRes(w, h) { OUTLINE.res.value.set(w, h); }
const VS = `uniform vec2 uRes; uniform float uW;
void main(){
  vec4 clip = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  vec3 nv = normalize(normalMatrix * normal);
  vec2 nc = (projectionMatrix * vec4(nv, 0.0)).xy;
  float l = length(nc); if (l > 1e-5) nc /= l;
  clip.xy += nc * uW * clip.w * 2.0 / uRes;
  gl_Position = clip;
}`;
const FS = `uniform vec3 uC; void main(){ gl_FragColor = vec4(uC, 1.0); }`;
const OM = new Map();
export function outlineMat(w = 2.6, color = 0x1b1220) {
  const k = w + ':' + color;
  if (!OM.has(k)) { const m = new THREE.ShaderMaterial({ uniforms: { uRes: OUTLINE.res, uW: { value: w }, uC: { value: new THREE.Color(color) } }, vertexShader: VS, fragmentShader: FS, side: THREE.BackSide }); m.name = 'toon_outline'; OM.set(k, m); }
  return OM.get(k);
}
const TC = new Map();
export function toonMat(m) {
  if (!m || !m.isMeshStandardMaterial) return m;
  let t = TC.get(m);
  if (!t) {
    t = new THREE.MeshToonMaterial({ color: m.color.clone(), vertexColors: m.vertexColors, gradientMap: grad, transparent: m.transparent, opacity: m.opacity, side: m.side, depthWrite: m.depthWrite });
    if (m.emissive && m.emissiveIntensity) { t.emissive = m.emissive.clone(); t.emissiveIntensity = m.emissiveIntensity; }
    if (m.roughness < 0.4) t.color.offsetHSL(0, 0.04, 0.03);
    t.name = m.name; t.userData.std = m; TC.set(m, t);
  }
  return t;
}
const SKIP = /eye|shine|mouth|blush|tooth|tongue|fang|nostril|nose|sprinkle|seed|speckle|stripe|plate|claw|toe|chev|stud_|line|court|tick|marker|dim|floor_base|grass_patch|paint/;
const OG = new WeakMap();
function outlineGeo(g) {
  if (OG.has(g)) return OG.get(g);
  if (!g.boundingSphere) g.computeBoundingSphere();
  const p = g.attributes.position, n = g.attributes.normal, map = new Map(), out = new THREE.BufferGeometry();
  const nn = new Float32Array(p.count * 3);
  for (let i = 0; i < p.count; i++) { const k = Math.round(p.getX(i) * 2e3) + ',' + Math.round(p.getY(i) * 2e3) + ',' + Math.round(p.getZ(i) * 2e3); let a = map.get(k); if (!a) map.set(k, (a = [0, 0, 0, []])); a[0] += n.getX(i); a[1] += n.getY(i); a[2] += n.getZ(i); a[3].push(i); }
  for (const a of map.values()) { const l = Math.hypot(a[0], a[1], a[2]) || 1; for (const i of a[3]) { nn[i * 3] = a[0] / l; nn[i * 3 + 1] = a[1] / l; nn[i * 3 + 2] = a[2] / l; } }
  out.setAttribute('position', p); out.setAttribute('normal', new THREE.BufferAttribute(nn, 3)); if (g.index) out.setIndex(g.index);
  out.boundingSphere = g.boundingSphere; OG.set(g, out); return out;
}
export function toonify(root, { width = 2.6, color = 0x1b1220, skip = SKIP, outline = true } = {}) {
  const om = outlineMat(width, color), list = [];
  root.traverse((o) => { if (o.isMesh && !o.userData.isOutline && !o.isInstancedMesh) list.push(o); });
  for (const o of list) {
    o.material = toonMat(o.material);
    if (!outline || skip.test(o.name) || o.userData.noOutline || o.material.transparent) continue;
    const h = new THREE.Mesh(outlineGeo(o.geometry), om);
    h.name = o.name + '_outline'; h.userData.isOutline = true; h.castShadow = false; h.receiveShadow = false; h.raycast = () => {};
    o.add(h);
  }
  return root;
}
export function prepExport(root) {
  const removed = [], swapped = [], geos = [];
  root.traverse((o) => {
    if (o.userData.isOutline) removed.push([o, o.parent]);
    else if (o.isMesh && o.material && o.material.userData && o.material.userData.std) swapped.push([o, o.material]);
    if (o.isMesh && o.userData.softOrig && !o.userData.isOutline) geos.push([o, o.geometry]);
  });
  removed.forEach(([o, p]) => p.remove(o));
  swapped.forEach(([o, m]) => (o.material = m.userData.std));
  geos.forEach(([o]) => (o.geometry = o.userData.softOrig));
  return () => { removed.forEach(([o, p]) => p.add(o)); swapped.forEach(([o, m]) => (o.material = m)); geos.forEach(([o, g]) => (o.geometry = g)); };
}
window.__sdPrepExport = prepExport;
