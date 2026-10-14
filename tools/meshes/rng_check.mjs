// Prints the first values of the design's kit.js rng(7), running the design's own function text (not the page).
import { readFileSync } from 'node:fs';
const src = readFileSync(process.argv[2], 'utf8');
const m = src.match(/export function rng\(seed\) \{[\s\S]*?\n\}/);
if (!m) throw new Error('rng() not found in kit.js');
const rng = new Function(m[0].replace('export ', '') + '\nreturn rng;')();
const r = rng(7);
console.log(JSON.stringify([r(), r(), r(), r(), r()]));
