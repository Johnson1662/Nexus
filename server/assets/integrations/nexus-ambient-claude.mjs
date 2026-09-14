#!/usr/bin/env node
// installed by nexus
// managed by nexus; updating overwrites this file.
// NEXUS_AMBIENT_INTEGRATION_VERSION=2

import fs from "node:fs";
import path from "node:path";
import os from "node:os";

if (process.env.HERDR_ENV === "1") {
  process.exit(0);
}

const action = process.argv[2] || "session";

let rawInput = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  rawInput += chunk;
});
process.stdin.on("end", () => {
  handlePayload();
});
process.stdin.on("error", () => {
  process.exit(0);
});

function handlePayload() {
  let data = {};
  if (rawInput.trim()) {
    try {
      data = JSON.parse(rawInput.trim());
    } catch {}
  }

  const sessionId = data.session_id;
  if (!sessionId || typeof sessionId !== "string") {
    process.exit(0);
  }

  const home = process.env.NEXUS_DATA_DIR || path.join(os.homedir(), ".nexus");
  const sessionsDir = path.join(home, "ambient", "sessions");
  try {
    fs.mkdirSync(sessionsDir, { recursive: true });
  } catch {}

  const claimFile = path.join(sessionsDir, `${sessionId}.json`);

  if (action === "stop" || action === "exit" || data.hookEventName === "SessionEnd" || data.hook_event_name === "SessionEnd") {
    try {
      if (fs.existsSync(claimFile)) fs.unlinkSync(claimFile);
    } catch {}
    process.exit(0);
  }

  const status = action === "stop" ? "idle" : "running";
  const transcriptPath = data.transcript_path || "";
  const cwd = data.cwd || process.cwd();

  const payload = {
    version: 1,
    agent: "claude",
    sessionId,
    pid: process.ppid,
    cwd,
    transcriptPath,
    status,
    lastSeen: Date.now(),
  };

  const tmpFile = `${claimFile}.tmp.${process.pid}`;
  try {
    fs.writeFileSync(tmpFile, JSON.stringify(payload), "utf8");
    fs.renameSync(tmpFile, claimFile);
  } catch {}
  process.exit(0);
}
