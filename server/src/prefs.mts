import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { join } from "path";

interface AgentPrefs {
  lastModel?: string;
}

const PREFS_DIR = join(process.env.HOME || process.env.USERPROFILE || ".", ".nexus");
const PREFS_FILE = join(PREFS_DIR, "agent-prefs.json");
let cachedPrefs: Record<string, AgentPrefs> | null = null;


function ensureDir(): void {
  if (!existsSync(PREFS_DIR)) {
    mkdirSync(PREFS_DIR, { recursive: true });
  }
}

function loadPrefs(): Record<string, AgentPrefs> {
  if (cachedPrefs) return cachedPrefs;
  try {
    ensureDir();
    if (existsSync(PREFS_FILE)) {
      const parsed = JSON.parse(readFileSync(PREFS_FILE, "utf-8")) as Record<string, AgentPrefs>;
      cachedPrefs = parsed;
      return parsed;
    }
  } catch {
    // ignore corrupt file
  }
  cachedPrefs = {};
  return cachedPrefs;
}

function savePrefs(prefs: Record<string, AgentPrefs>): void {
  cachedPrefs = prefs;
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
