// Run: node tools/maps/make_vote_cards.mjs <a folder with his demos + support.js> <out dir> docs/new-maps/maps.json
// Makes the map vote card pictures from Diego's own demos (NEW MAPS FINALS zip). Each demo takes 2 photos of every map
// when it starts (its snap(), window.__sqThumbs) and draws its "PICK A MAP" cards (photo, mini map, name band). This
// reads the photos, mini-map SVG, texts and colours from the demo page, then draws each card in his style at the vote
// board's slot (the 372 x 292 card at (40, 30) of a 452 x 400 picture, Config.UI.MatchFound.vote.cards), once with
// photo a and once with photo b, and saves transparent PNGs at 2x.
// node cards.mjs <demosDir> <outDir> <maps.json>
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [demos, out, mapsJson] = process.argv.slice(2);
const CHROME = "C:/Program Files/Google/Chrome/Application/chrome.exe";
const PORT = 9333;
const SCALE = 2;
const K = 1.25; // his 230-wide card's px, grown for the 372 slot
fs.mkdirSync(path.join(out, "_html"), { recursive: true });

const byName = {};
const maps = JSON.parse(fs.readFileSync(mapsJson, "utf8"));
for (const m of Object.values(maps.modes).flat()) byName[m.name.toLowerCase()] = { id: m.id, model: m.name.replace(/\s/g, ""), sub: m.sub, th: m.theme };

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "sd-cards-"));
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`, "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--window-size=1400,900", "--allow-file-access-from-files", "about:blank"], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function cdp(wsUrl) {
	const ws = new WebSocket(wsUrl);
	await new Promise((r, j) => { ws.addEventListener("open", r); ws.addEventListener("error", j); });
	let id = 0;
	const pending = new Map();
	ws.addEventListener("message", (ev) => {
		const m = JSON.parse(ev.data);
		if (m.id && pending.has(m.id)) {
			const p = pending.get(m.id);
			pending.delete(m.id);
			m.error ? p.j(new Error(JSON.stringify(m.error))) : p.r(m.result);
		}
	});
	return {
		send: (method, params = {}) => new Promise((r, j) => { const i = ++id; pending.set(i, { r, j }); ws.send(JSON.stringify({ id: i, method, params })); }),
		close: () => ws.close(),
	};
}
async function openPage(url) {
	for (let i = 0; i < 50; i++) {
		try { await fetch(`http://127.0.0.1:${PORT}/json/version`); break; } catch { await sleep(200); }
	}
	const t = await (await fetch(`http://127.0.0.1:${PORT}/json/new?${encodeURIComponent(url)}`, { method: "PUT" })).json();
	const page = await cdp(t.webSocketDebuggerUrl);
	await page.send("Page.enable");
	await page.send("Runtime.enable");
	return { page, targetId: t.id };
}
const evaluate = async (page, expression) => (await page.send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })).result.value;

const READ = `JSON.stringify({ thumbs: window.__sqThumbs, cards: [...document.querySelectorAll('button')].filter((b) => b.querySelector('svg')).map((b) => {
	const spans = b.querySelectorAll('span'), top = b.firstElementChild;
	return { name: spans[0].textContent, sub: spans[1].textContent, footer: b.style.background, photoBg: top.style.background,
		subColor: spans[1].style.color, subFont: getComputedStyle(spans[1]).fontFamily, svg: b.querySelector('svg').outerHTML };
}) })`;

const made = [];
try {
	for (const file of ["Squishy Duels TDM Demo.dc.html", "Squishy Duels FFA Demo.dc.html", "Squishy Duels Duel Demo.dc.html"]) {
		const { page, targetId } = await openPage(pathToFileURL(path.join(demos, file)).href);
		let data = null;
		for (let i = 0; i < 120 && !data; i++) {
			await sleep(500);
			const ready = await evaluate(page, "!!(window.__sqThumbs && document.querySelector('button svg'))");
			if (ready) data = JSON.parse(await evaluate(page, READ));
		}
		await fetch(`http://127.0.0.1:${PORT}/json/close/${targetId}`);
		if (!data) throw new Error(`${file}: no photos after 60 s`);
		console.log(file, data.cards.length, "cards", data.thumbs.length, "photo pairs");
		data.cards.forEach((card, i) => {
			const map = byName[card.name.toLowerCase()];
			if (!map) throw new Error(`unknown map ${card.name}`);
			for (const [k, photo] of [["a", data.thumbs[i][0]], ["b", data.thumbs[i][1]]]) {
				const html = `<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600;700&family=Nunito:wght@800&display=swap" rel="stylesheet">
<style>html,body{margin:0;background:transparent;width:452px;height:400px;overflow:hidden}
.card{position:absolute;left:40px;top:30px;width:372px;height:292px;box-sizing:border-box;display:flex;flex-direction:column;background:${map.th.footer};border:${4 * K}px solid #1c1530;border-radius:${20 * K}px;overflow:hidden;box-shadow:0 ${6 * K}px 0 #1c1530;color:#fff}
.photo{position:relative;flex:1;overflow:hidden;background:linear-gradient(180deg,${map.th.cardTop},${map.th.cardBg})}
.photo img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.mini{position:absolute;right:${6 * K}px;bottom:${6 * K}px;width:38%;padding:${3 * K}px;background:rgba(255,255,255,.92);border:${3 * K}px solid #1c1530;border-radius:${8 * K}px;box-sizing:border-box}
.mini svg{width:100%;height:auto;display:block}
.band{padding:${10 * K}px ${14 * K}px ${12 * K}px;border-top:${4 * K}px solid #1c1530;display:flex;flex-direction:column;gap:${2 * K}px}
.name{font-family:'Fredoka',sans-serif;font-weight:700;font-size:${20 * K}px;letter-spacing:.02em;text-transform:uppercase;line-height:1.2}
.sub{font-family:${card.subFont};font-weight:800;font-size:${13 * K}px;color:${map.th.sub};line-height:1.2}</style></head>
<body><div class="card"><div class="photo"><img src="${photo}"><div class="mini">${card.svg}</div></div>
<div class="band"><span class="name">${card.name}</span><span class="sub">${map.sub}</span></div></div></body></html>`;
				const htmlPath = path.join(out, "_html", `${map.id}_${k}.html`);
				fs.writeFileSync(htmlPath, html);
				made.push({ id: map.id, model: map.model, k, htmlPath });
			}
		});
	}
	for (const m of made) {
		const { page, targetId } = await openPage("about:blank");
		await page.send("Emulation.setDeviceMetricsOverride", { width: 452, height: 400, deviceScaleFactor: SCALE, mobile: false });
		await page.send("Emulation.setDefaultBackgroundColorOverride", { color: { r: 0, g: 0, b: 0, a: 0 } });
		await page.send("Page.navigate", { url: pathToFileURL(m.htmlPath).href });
		for (let i = 0; i < 40; i++) {
			await sleep(250);
			if (await evaluate(page, "document.readyState === 'complete' && document.fonts.status === 'loaded' && document.images[0].complete")) break;
		}
		await sleep(300);
		const shot = await page.send("Page.captureScreenshot", { format: "png", clip: { x: 0, y: 0, width: 452, height: 400, scale: 1 } });
		const file = path.join(out, `vote_card_${m.model}_${m.k}.png`);
		fs.writeFileSync(file, Buffer.from(shot.data, "base64"));
		await fetch(`http://127.0.0.1:${PORT}/json/close/${targetId}`);
		console.log("wrote", file);
	}
} finally {
	chrome.kill();
}
