// Claude Code Stop hook (.claude/settings.json). If Roblox Studio was changed after the last snapshot, it stops Claude
// from finishing and asks it to take one. It asks once per turn (stop_hook_active), so a failing snapshot cannot loop.
// "Changed" = a Roblox Studio MCP tool that can edit the place; execute_luau calls starting with `-- readonly` don't count.
const fs = require("fs");
const path = require("path");

const EDITING_TOOL = /__(execute_luau|multi_edit|insert_asset|generate_[a-z_]+|segment_mesh|subagent)$/;
const READONLY = /^\s*--\s*readonly\b/;

function lastSnapshotAt(root) {
	try {
		return JSON.parse(fs.readFileSync(path.join(root, ".git", "claude-snapshot.json"), "utf8")).at || 0;
	} catch {
		return 0;
	}
}

function lastStudioEditAt(transcriptPath) {
	let last = 0;
	for (const line of fs.readFileSync(transcriptPath, "utf8").split("\n")) {
		if (!line.includes("tool_use")) continue;
		let entry;
		try {
			entry = JSON.parse(line);
		} catch {
			continue;
		}
		if (entry.type !== "assistant" || !Array.isArray(entry.message && entry.message.content)) continue;
		for (const block of entry.message.content) {
			if (block.type !== "tool_use") continue;
			const name = String(block.name || "");
			if (!name.toLowerCase().includes("roblox") || !EDITING_TOOL.test(name)) continue;
			if (name.endsWith("execute_luau") && READONLY.test(String((block.input && block.input.code) || ""))) continue;
			last = Math.max(last, Date.parse(entry.timestamp) || 0);
		}
	}
	return last;
}

let raw = "";
process.stdin.on("data", (c) => (raw += c));
process.stdin.on("end", () => {
	const input = JSON.parse(raw.replace(/^﻿/, "").trim() || "{}");
	if (input.stop_hook_active || !input.transcript_path) return;
	const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
	if (lastStudioEditAt(input.transcript_path) <= lastSnapshotAt(root)) return;
	process.stdout.write(
		JSON.stringify({
			decision: "block",
			reason:
				"Roblox Studio was changed and no snapshot has been saved since. Take one now as CLAUDE.md > Snapshots says: " +
				'1) start `node tools/snapshot/snap.mjs snapshot "<one line: what changed>"` in the background, ' +
				"2) run the snapshot bootstrap from CLAUDE.md with execute_luau and report its result. " +
				"If Studio is in Play mode, stop the playtest first. If it fails, tell the user why instead of retrying forever.",
		}),
	);
});
