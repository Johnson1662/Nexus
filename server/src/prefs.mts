import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { join } from "path";

interface AgentPrefs {
  lastModel?: string;
}

const PREFS_DIR = join(process.env.HOME || process.env.USERPROFILE || ".", ".anywhere");
const PREFS_FILE = join(PREFS_DIR, "agent-prefs.json");

function ensureDir(): void {
  if (!existsSync(PREFS_DIR)) {
    mkdirSync(PREFS_DIR, { recursive: true });
  }
}

function loadPrefs(): Record<string, AgentPrefs> {
  try {
    ensureDir();
    if (existsSync(PREFS_FILE)) {
      return JSON.parse(readFileSync(PREFS_FILE, "utf-8"));
    }
  } catch {
    // ignore corrupt file
  }
  return {};
}

function savePrefs(prefs: Record<string, AgentPrefs>): void {
  ensureDir();
  writeFileSync(PREFS_FILE, JSON.stringify(prefs, null, 2), "utf-8");
}

export function getLastModel(agentName: string): string | undefined {
  const prefs = loadPrefs();
  return prefs[agentName]?.lastModel;
}

export function setLastModel(agentName: string, model: string): void {
  const prefs = loadPrefs();
  if (!prefs[agentName]) prefs[agentName] = {};
  prefs[agentName].lastModel = model;
  savePrefs(prefs);
}
