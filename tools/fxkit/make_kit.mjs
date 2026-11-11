// make_kit.mjs: writes the candy kit SVGs (256 x 256). Tintable ones: dark ink outline, light-grey shaded body,
// pure white shine (a tint keeps the outline dark, shades the body, and the shine is the tint at full strength).
// Full-colour ones (gold star, pink heart): true white shine, used with a white particle Color.
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const out = join(dirname(fileURLToPath(import.meta.url)), "svg");
mkdirSync(out, { recursive: true });
const INK = "#251B32"; // Art/Palette PlumInk: every UI outline

const svg = (body, defs = "") =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">\n<defs>${defs}</defs>\n${body}\n</svg>\n`;

const grad = (id, top, bottom) =>
  `<linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${top}"/><stop offset="1" stop-color="${bottom}"/></linearGradient>`;

// ---- star -------------------------------------------------------------------------------------------------------
const STAR = "128,42 153.9,98.4 215.5,105.6 169.8,147.6 182.1,208.4 128,178 73.9,208.4 86.2,147.6 40.5,105.6 102.1,98.4";
const star = (top, bottom, rim, shine = "#FFFFFF") =>
  svg(
    `<polygon points="${STAR}" fill="${INK}" stroke="${INK}" stroke-width="48" stroke-linejoin="round"/>
<polygon points="${STAR}" fill="${rim}" stroke="${rim}" stroke-width="12" stroke-linejoin="round"/>
<g transform="translate(0,-5)"><polygon points="${STAR}" fill="url(#g)" stroke="url(#g)" stroke-width="6" stroke-linejoin="round"/></g>
<ellipse cx="104" cy="92" rx="20" ry="11" transform="rotate(-32 104 92)" fill="${shine}"/>
<circle cx="138" cy="74" r="6" fill="${shine}"/>`,
    grad("g", top, bottom),
  );
writeFileSync(join(out, "star.svg"), star("#FAF9FD", "#E9E6F2", "#C9C4DC"));
writeFileSync(join(out, "starGold.svg"), star("#FFE873", "#FFBE26", "#F09A0A"));

// ---- heart ------------------------------------------------------------------------------------------------------
const HEART = "M128 206 C 52 150, 40 104, 66 76 C 92 50, 120 64, 128 86 C 136 64, 164 50, 190 76 C 216 104, 204 150, 128 206 Z";
const heart = (top, bottom, rim) =>
  svg(
    `<path d="${HEART}" fill="${INK}" stroke="${INK}" stroke-width="44" stroke-linejoin="round"/>
<path d="${HEART}" fill="${rim}" stroke="${rim}" stroke-width="10" stroke-linejoin="round"/>
<g transform="translate(0,-5)"><path d="${HEART}" fill="url(#g)" stroke="url(#g)" stroke-width="4" stroke-linejoin="round"/></g>
<ellipse cx="88" cy="88" rx="17" ry="10" transform="rotate(-38 88 88)" fill="#FFFFFF"/>
<circle cx="110" cy="72" r="5" fill="#FFFFFF"/>`,
    grad("g", top, bottom),
  );
writeFileSync(join(out, "heart.svg"), heart("#FF9CC2", "#FF5B91", "#D93C75")); // CandyCoral family: candy pink, not blood red

// ---- sparkle (4-point twinkle): white core, thin ink edge so it reads on pale floors ----------------------------
const SPARK = "M128 20 C 137 92, 164 119, 236 128 C 164 137, 137 164, 128 236 C 119 164, 92 137, 20 128 C 92 119, 119 92, 128 20 Z";
writeFileSync(
  join(out, "sparkle.svg"),
  svg(
    `<path d="${SPARK}" fill="${INK}" stroke="${INK}" stroke-width="22" stroke-linejoin="round"/>
<path d="${SPARK}" fill="#FFFFFF"/>`,
  ),
);

// ---- puff (cartoon cloud): light top, darker underside, soft plum edge -------------------------------------------
const CLOUD = [
  [92, 150, 46],
  [148, 118, 54],
  [190, 158, 40],
  [132, 174, 46],
  [66, 172, 30],
];
const circles = (grow, fill) => CLOUD.map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r + grow}" fill="${fill}"/>`).join("");
writeFileSync(
  join(out, "puff.svg"),
  svg(
    `${circles(11, "#4A3A63")}
<g clip-path="url(#c)"><rect x="0" y="0" width="256" height="256" fill="url(#g)"/>
<ellipse cx="128" cy="232" rx="110" ry="46" fill="#CBC6DD" opacity="0.8"/>
<circle cx="128" cy="92" r="26" fill="#FFFFFF"/><circle cx="82" cy="126" r="16" fill="#FFFFFF"/></g>`,
    grad("g", "#FFFFFF", "#E6E3F0") + `<clipPath id="c">${circles(0, "#000")}</clipPath>`,
  ),
);

// ---- confetti capsule ------------------------------------------------------------------------------------------
writeFileSync(
  join(out, "confetti.svg"),
  svg(
    `<rect x="84" y="20" width="88" height="216" rx="44" fill="${INK}"/>
<rect x="100" y="36" width="56" height="184" rx="28" fill="url(#g)"/>
<rect x="110" y="50" width="12" height="96" rx="6" fill="#FFFFFF"/>`,
    grad("g", "#F4F3F9", "#E4E1EE"),
  ),
);

// ---- ring: white band between two ink edges -----------------------------------------------------------------------
writeFileSync(
  join(out, "ring.svg"),
  svg(
    `<circle cx="128" cy="128" r="109" fill="none" stroke="${INK}" stroke-width="30"/>
<circle cx="128" cy="128" r="109" fill="none" stroke="#EEEDF5" stroke-width="17"/>
<circle cx="128" cy="128" r="112" fill="none" stroke="#FFFFFF" stroke-width="6"/>`,
  ),
);

// ---- pow burst: ink edge, shaded body, a white inner burst (the hot core) ----------------------------------------
const burst = (cx, cy, rOut, rIn, n, rot = 0) => {
  const pts = [];
  for (let i = 0; i < n * 2; i++) {
    const r = i % 2 === 0 ? rOut : rIn;
    const a = (Math.PI * i) / n + rot;
    pts.push(`${(cx + r * Math.sin(a)).toFixed(1)},${(cy - r * Math.cos(a)).toFixed(1)}`);
  }
  return pts.join(" ");
};
writeFileSync(
  join(out, "pow.svg"),
  svg(
    `<polygon points="${burst(128, 128, 104, 70, 12)}" fill="${INK}" stroke="${INK}" stroke-width="30" stroke-linejoin="round"/>
<polygon points="${burst(128, 128, 104, 70, 12)}" fill="url(#g)" stroke="url(#g)" stroke-width="4" stroke-linejoin="round"/>
<polygon points="${burst(128, 128, 62, 40, 12, Math.PI / 12)}" fill="#FFFFFF"/>`,
    grad("g", "#F6F5FA", "#E4E1EE"),
  ),
);

// ---- jelly drop ---------------------------------------------------------------------------------------------------
const DROP = "M128 30 C 150 74, 196 116, 196 160 C 196 200, 166 226, 128 226 C 90 226, 60 200, 60 160 C 60 116, 106 74, 128 30 Z";
writeFileSync(
  join(out, "jelly.svg"),
  svg(
    `<path d="${DROP}" fill="${INK}" stroke="${INK}" stroke-width="36" stroke-linejoin="round"/>
<path d="${DROP}" fill="url(#g)" stroke="url(#g)" stroke-width="4" stroke-linejoin="round"/>
<ellipse cx="103" cy="150" rx="12" ry="24" transform="rotate(18 103 150)" fill="#FFFFFF"/>
<circle cx="112" cy="110" r="6" fill="#FFFFFF"/>`,
    grad("g", "#F4F3F9", "#E4E1EE"),
  ),
);

// ---- peppermint swirl (Mint Whirl, the Christmas Puffin's ultimate; 512 x 512, full colour, no outline) -------------
// Claude Design's own disc (sd/lab50.js:427-430): white, red where sin(4θ + 9r) > 0 (four spiral arms), r = 0..1.
const SWIRL_R = 250;
const swirlPoint = (r, a) => `${(256 + SWIRL_R * r * Math.cos(a)).toFixed(1)},${(256 + SWIRL_R * r * Math.sin(a)).toFixed(1)}`;
const swirlArm = (m) => {
  const pts = [];
  const edge = (r, half) => (2 * Math.PI * m + (half ? Math.PI : 0) - 9 * r) / 4;
  for (let i = 0; i <= 48; i++) pts.push(swirlPoint(i / 48, edge(i / 48, false)));
  for (let i = 1; i < 8; i++) pts.push(swirlPoint(1, edge(1, false) + ((edge(1, true) - edge(1, false)) * i) / 8)); // along the rim
  for (let i = 48; i >= 0; i--) pts.push(swirlPoint(i / 48, edge(i / 48, true)));
  return `<polygon points="${pts.join(" ")}" fill="#F04A5E"/>`;
};
writeFileSync(
  join(out, "mintSwirl.svg"),
  `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">\n<circle cx="256" cy="256" r="${SWIRL_R}" fill="#FFFFFF"/>\n${[0, 1, 2, 3].map(swirlArm).join("\n")}\n</svg>\n`,
);

console.log("svgs written to", out);
