// Snapshot helper for Squishy Duels. Studio talks to it on http://127.0.0.1:34901 (see studio.luau next to this file).
//   node tools/snapshot/snap.mjs snapshot "what changed"  waits for Studio's export, commits it and pushes it to GitHub
//   node tools/snapshot/snap.mjs restore                 serves src/ and world/ as they are on disk so Studio can load them
// Each run handles one request from Studio and exits. The bootstraps that drive it from Studio are in CLAUDE.md.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const PORT = 34901;
const IDLE_TIMEOUT_MS = 120_000;
const CODE_CHUNK_BYTES = 400_000;
const PUSH_ATTEMPTS = 3;

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const SRC = path.join(ROOT, "src");
const WORLD = path.join(ROOT, "world");
const TOOL = path.join(ROOT, "tools", "snapshot", "studio.luau");
const MARKER = path.join(ROOT, ".git", "claude-snapshot.json");

const [mode, ...rest] = process.argv.slice(2);
const message = rest.join(" ").trim();
if (mode !== "snapshot" && mode !== "restore") fail('usage: snap.mjs snapshot "message" | snap.mjs restore');
if (mode === "snapshot" && !message) fail("a snapshot needs a short message saying what changed");

function fail(text) {
	console.error(text);
	process.exit(1);
}

function git(...args) {
	return execFileSync("git", args, { cwd: ROOT, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

function tryGit(...args) {
	try {
		return { ok: true, out: git(...args) };
	} catch (e) {
		return { ok: false, out: String(e.stderr || e.message).trim() };
	}
}

function inside(base, rel) {
	const p = path.resolve(base, rel);
	if (!p.startsWith(base + path.sep)) throw new Error("path escapes its folder: " + rel);
	return p;
}

function walk(dir, base = dir, files = [], dirs = []) {
	if (!fs.existsSync(dir)) return { files, dirs };
	for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
		const full = path.join(dir, e.name);
		const rel = path.relative(base, full).split(path.sep).join("/");
		if (e.isDirectory()) {
			dirs.push(rel);
			walk(full, base, files, dirs);
		} else {
			files.push(rel);
		}
	}
	return { files: files.sort(), dirs: dirs.sort() };
}

// Brings in the partner's snapshots before ours. On a conflict our side wins: the next export rewrites src/ and world/ anyway.
function syncWithGitHub() {
	if (!tryGit("fetch", "origin").ok) return "offline: could not reach GitHub";
	if (!tryGit("rev-parse", "--verify", "origin/main").ok) return "no origin/main yet";
	const rebase = tryGit("rebase", "-X", "theirs", "--autostash", "origin/main");
	if (rebase.ok) return "up to date with GitHub";
	tryGit("rebase", "--abort");
	return "could not merge GitHub's latest: " + rebase.out.split("\n")[0];
}

function commitAndPush() {
	git("add", "-A");
	const marker = { at: Date.now() };
	if (tryGit("diff", "--cached", "--quiet").ok) {
		fs.writeFileSync(MARKER, JSON.stringify({ ...marker, result: "no changes" }));
		return "NO CHANGES: Studio matches the last snapshot.";
	}
	const commit = tryGit("commit", "-m", message);
	if (!commit.ok) return "SNAPSHOT FAILED: git commit: " + commit.out;
	const sha = git("rev-parse", "--short", "HEAD");
	let pushed = tryGit("push", "origin", "HEAD:main");
	for (let i = 1; i < PUSH_ATTEMPTS && !pushed.ok; i++) {
		syncWithGitHub();
		pushed = tryGit("push", "origin", "HEAD:main");
	}
	fs.writeFileSync(MARKER, JSON.stringify({ ...marker, result: sha }));
	const files = git("show", "--stat", "--format=", "HEAD").split("\n").pop();
	return pushed.ok
		? `SNAPSHOT SAVED ${sha} and uploaded to GitHub (${files.trim()})`
		: `SNAPSHOT SAVED ${sha} on this PC only, GitHub upload failed: ${pushed.out.split("\n")[0]}`;
}

function readJson(req) {
	return new Promise((resolve, reject) => {
		const chunks = [];
		req.on("data", (c) => chunks.push(c));
		req.on("end", () => {
			try {
				resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {});
			} catch (e) {
				reject(e);
			}
		});
	});
}

// restore: code is sent in chunks so no single response gets huge.
function codeChunks() {
	const { files } = walk(SRC);
	const chunks = [[]];
	let size = 0;
	for (const rel of files) {
		if (!rel.endsWith(".luau")) continue;
		const source = fs.readFileSync(path.join(SRC, rel), "utf8");
		if (size + source.length > CODE_CHUNK_BYTES && chunks.at(-1).length) {
			chunks.push([]);
			size = 0;
		}
		chunks.at(-1).push({ path: rel, source });
		size += source.length;
	}
	return chunks;
}

const startNote = mode === "snapshot" ? syncWithGitHub() : "serving the files on disk";
let chunks = null;
let idle;
const resetIdle = () => {
	clearTimeout(idle);
	idle = setTimeout(() => fail("SNAPSHOT HELPER TIMED OUT: Studio never connected. Is Studio open on the place?"), IDLE_TIMEOUT_MS);
};

const routes = {
	"GET /tool": () => fs.readFileSync(TOOL, "utf8"),

	// snapshot
	"POST /begin": () => {
		for (const dir of [SRC, WORLD]) fs.rmSync(dir, { recursive: true, force: true });
		return { ok: true };
	},
	"POST /code": (body) => {
		for (const f of body.files) {
			const target = inside(SRC, f.path);
			if (f.dir) {
				fs.mkdirSync(target, { recursive: true });
				fs.writeFileSync(path.join(target, ".gitkeep"), "");
				continue;
			}
			if (!target.endsWith(".luau")) throw new Error("not a .luau file: " + f.path);
			fs.mkdirSync(path.dirname(target), { recursive: true });
			fs.writeFileSync(target, f.source, "utf8");
		}
		return { ok: true };
	},
	"POST /world": (body) => {
		for (const f of body.files) {
			const target = inside(WORLD, f.path);
			if (!target.endsWith(".rbxm")) throw new Error("not a .rbxm file: " + f.path);
			fs.mkdirSync(path.dirname(target), { recursive: true });
			fs.writeFileSync(target, Buffer.from(f.base64, "base64"));
		}
		return { ok: true };
	},
	"POST /index": (body) => {
		fs.mkdirSync(WORLD, { recursive: true });
		fs.writeFileSync(path.join(WORLD, "index.json"), JSON.stringify(body.index, null, "\t") + "\n");
		return { ok: true };
	},
	"POST /abort": (body) => {
		tryGit("checkout", "--", "src", "world");
		tryGit("clean", "-fdq", "--", "src", "world");
		finish("SNAPSHOT FAILED in Studio: " + body.error);
		return { ok: true };
	},

	// restore
	"GET /manifest": () => {
		chunks = codeChunks();
		const { dirs } = walk(SRC);
		const indexFile = path.join(WORLD, "index.json");
		const index = fs.existsSync(indexFile) ? JSON.parse(fs.readFileSync(indexFile, "utf8")) : [];
		return { codeChunks: chunks.length, dirs, index };
	},
	"GET /code": (_, url) => ({ files: chunks[Number(url.searchParams.get("part"))] }),
	"GET /worldfile": (_, url) => ({ base64: fs.readFileSync(inside(WORLD, url.searchParams.get("file"))).toString("base64") }),
};

function finish(text) {
	console.log(text);
	setTimeout(() => process.exit(0), 200);
}

const server = http.createServer(async (req, res) => {
	resetIdle();
	const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
	const key = `${req.method} ${url.pathname}`;
	try {
		if (key === "POST /end") {
			const body = await readJson(req);
			const result = mode === "snapshot" ? commitAndPush() : "RESTORE DONE: " + body.result;
			res.end(JSON.stringify({ result }));
			finish(result);
			return;
		}
		const route = routes[key];
		if (!route) {
			res.statusCode = 404;
			res.end(JSON.stringify({ error: "unknown route " + key }));
			return;
		}
		const out = await route(req.method === "POST" ? await readJson(req) : null, url);
		res.end(typeof out === "string" ? out : JSON.stringify(out));
	} catch (e) {
		res.statusCode = 500;
		res.end(JSON.stringify({ error: String(e.message || e) }));
	}
});

server.on("error", (e) => fail("SNAPSHOT HELPER could not start: " + e.message));
server.listen(PORT, "127.0.0.1", () => {
	resetIdle();
	console.log(`READY (${mode}, ${startNote}). Now run the ${mode} bootstrap in Studio.`);
});
