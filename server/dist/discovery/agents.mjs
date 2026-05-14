import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
const ACP_AGENTS = [
    ["opencode", "OpenCode"],
    ["claude-code", "Claude Code"],
    ["gemini", "Gemini CLI"],
    ["cline", "Cline"],
    ["kimi", "Kimi CLI"],
    ["qwen-code", "Qwen Code"],
    ["mistral-vibe", "Mistral Vibe"],
    ["goose", "Goose"],
    ["minion-code", "Minion Code"],
    ["openclaw", "OpenClaw"],
    ["qoder", "Qoder CLI"],
    ["vtcode", "VT Code"],
    ["crow", "crow-cli"],
    ["codex", "Codex CLI"],
    ["code-assistant", "Code Assistant"],
    ["stakpak", "Stakpak"],
    ["poolside", "Poolside"],
    ["cursor", "Cursor"],
    ["augment-code", "Augment Code"],
    ["blackbox", "Blackbox AI"],
    ["fast-agent", "fast-agent"],
    ["fount", "fount"],
    ["hermes", "Hermes Agent"],
    ["kiro", "Kiro CLI"],
    ["junie", "Junie"],
    ["copilot", "GitHub Copilot"],
    ["docker-cagent", "Docker cagent"],
    ["pi", "pi coding agent"],
    ["factory-droid", "Factory Droid"],
    ["openhands", "OpenHands"],
    ["agoragentic", "Agoragentic"],
    ["amp", "Amp"],
    ["autohand-code", "Autohand Code"],
    ["codebuddy", "Codebuddy Code"],
    ["cortex-code", "Cortex Code"],
    ["corust", "Corust Agent"],
    ["deepagents", "DeepAgents"],
    ["dimcode", "DimCode"],
    ["dirac", "Dirac"],
    ["kilo", "Kilo"],
    ["nova", "Nova"],
    ["sigit-code", "siGit Code"],
    ["glm-agent", "GLM Agent"],
    ["rayclaw", "RayClaw"],
    ["stdio-bus", "stdio Bus"],
    ["iflow-cli", "iflow-cli"],
    ["lody", "Lody"],
    ["toad", "Toad"],
    ["pixi", "pixi"],
    ["tidewave", "Tidewave"],
    ["mitto", "Mitto"],
    ["nori-cli", "Nori CLI"],
    ["ngent", "Ngent"],
    ["rlm-code", "RLM Code"],
    ["happy", "Happy"],
    ["jockey", "Jockey"],
    ["agente", "Agmente"],
    ["ferngeist", "Ferngeist"],
    ["mobvibe", "Mobvibe"],
];
function findInPath(binaryName) {
    const pathDirs = (process.env.PATH || "").split(path.delimiter);
    const extensions = [".cmd", ".exe", ".bat", ".ps1", ""];
    for (const dir of pathDirs) {
        if (!dir)
            continue;
        for (const ext of extensions) {
            const fullPath = path.join(dir.trim(), binaryName + ext);
            try {
                if (existsSync(fullPath))
                    return fullPath;
            }
            catch { }
        }
    }
    return null;
}
function getAgentVersion(binaryPath) {
    try {
        const result = execSync(`"${binaryPath}" --version`, {
            encoding: "utf8",
            timeout: 3000,
        });
        return result.trim().split("\n")[0];
    }
    catch {
        return null;
    }
}
export function discoverAgents() {
    const discovered = [];
    for (const [binaryName, title] of ACP_AGENTS) {
        const binaryPath = findInPath(binaryName);
        if (binaryPath) {
            const version = getAgentVersion(binaryPath);
            discovered.push({
                name: binaryName,
                title,
                version: version || "unknown",
                source: "path",
                binaryPath,
                installed: true,
            });
        }
    }
    console.log(`[server] discovered ${discovered.length} ACP agents: ${discovered.map((a) => a.name).join(", ")}`);
    return discovered;
}
//# sourceMappingURL=agents.mjs.map