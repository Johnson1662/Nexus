#!/bin/sh
# installed by nexus
# managed by nexus; updating overwrites this file.
# NEXUS_AMBIENT_INTEGRATION_VERSION=1

set -eu
action="${1:-session}"
hook_input_file="$(mktemp "${TMPDIR:-/tmp}/nexus-codex-hook.XXXXXX")" || exit 0
trap 'rm -f "$hook_input_file"' EXIT HUP INT TERM
cat >"$hook_input_file" 2>/dev/null || true

if [ "${HERDR_ENV:-}" = "1" ]; then
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  NEXUS_ACTION="$action" NEXUS_INPUT_FILE="$hook_input_file" python3 - <<'PY'
import json, os, sys, time

action = os.environ.get("NEXUS_ACTION", "session")
input_file = os.environ.get("NEXUS_INPUT_FILE")
data = {}
if input_file and os.path.exists(input_file):
    try:
        with open(input_file, encoding="utf-8") as f:
            content = f.read().strip()
            if content:
                data = json.loads(content)
    except Exception:
        pass

session_id = data.get("session_id")
if not session_id or not isinstance(session_id, str):
    sys.exit(0)

home = os.environ.get("NEXUS_DATA_DIR") or os.path.expanduser("~/.nexus")
sessions_dir = os.path.join(home, "ambient", "sessions")
os.makedirs(sessions_dir, exist_ok=True)
claim_file = os.path.join(sessions_dir, f"{session_id}.json")

if action == "stop" or action == "exit" or data.get("hook_event_name") == "SessionEnd":
    try:
        if os.path.exists(claim_file):
            os.remove(claim_file)
    except Exception:
        pass
    sys.exit(0)

status = "idle" if action == "stop" else "running"
transcript_path = data.get("transcript_path", "")
cwd = data.get("cwd") or os.getcwd()

payload = {
    "version": 1,
    "agent": "codex",
    "sessionId": session_id,
    "pid": os.getppid(),
    "cwd": cwd,
    "transcriptPath": transcript_path,
    "status": status,
    "lastSeen": int(time.time() * 1000)
}

tmp_file = f"{claim_file}.tmp.{os.getpid()}"
try:
    with open(tmp_file, "w", encoding="utf-8") as f:
        json.dump(payload, f)
    os.replace(tmp_file, claim_file)
except Exception:
    pass
PY
elif command -v node >/dev/null 2>&1; then
  NEXUS_ACTION="$action" NEXUS_INPUT_FILE="$hook_input_file" node - <<'JS'
const fs = require("fs");
const path = require("path");

const action = process.env.NEXUS_ACTION || "session";
const inputFile = process.env.NEXUS_INPUT_FILE;
let data = {};
if (inputFile && fs.existsSync(inputFile)) {
  try {
    const raw = fs.readFileSync(inputFile, "utf8").trim();
    if (raw) data = JSON.parse(raw);
  } catch {}
}

const sessionId = data.session_id;
if (!sessionId || typeof sessionId !== "string") process.exit(0);

const home = process.env.NEXUS_DATA_DIR || path.join(require("os").homedir(), ".nexus");
const sessionsDir = path.join(home, "ambient", "sessions");
fs.mkdirSync(sessionsDir, { recursive: true });
const claimFile = path.join(sessionsDir, `${sessionId}.json`);

if (action === "stop" || action === "exit" || data.hook_event_name === "SessionEnd") {
  try { if (fs.existsSync(claimFile)) fs.unlinkSync(claimFile); } catch {}
  process.exit(0);
}

const status = action === "stop" ? "idle" : "running";
const transcriptPath = data.transcript_path || "";
const cwd = data.cwd || process.cwd();

const payload = {
  version: 1,
  agent: "codex",
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
JS
fi
