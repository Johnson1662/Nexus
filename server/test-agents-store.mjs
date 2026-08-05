import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { spawnSync } from "node:child_process";
import { execPath } from "node:process";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) passed += 1;
  else {
    failed += 1;
    console.error(`FAIL: ${message}`);
  }
}

function hasTempFiles(storeDir) {
  return readdirSync(storeDir).some((name) => /^\.installed-agents-.*\.tmp$/.test(name));
}

function readAgentInChild(moduleUrl, storeDir, agentId) {
  const script = `
    const store = await import(${JSON.stringify(moduleUrl)});
    const agent = store.getInstalledAgents().find((entry) => entry.agentId === ${JSON.stringify(agentId)});
    console.log(JSON.stringify(agent ?? null));
  `;
  const result = spawnSync(execPath, ["--input-type=module", "-e", script], {
    cwd: fileURLToPath(new URL(".", import.meta.url)),
    env: { ...process.env, NEXUS_AGENTS_STORE_DIR: storeDir },
    encoding: "utf8",
  });
  const line = result.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1);
  let parsed = null;
  try {
    parsed = line ? JSON.parse(line) : null;
  } catch {
    parsed = null;
  }
  return { result, parsed };
}

async function main() {
  const storeDir = mkdtempSync(join(tmpdir(), "nexus-agents-store-"));
  const storeFile = join(storeDir, "installed-agents.json");
  const moduleUrl = new URL("./dist/agents-store.mjs", import.meta.url).href;
  process.env.NEXUS_AGENTS_STORE_DIR = storeDir;

  writeFileSync(storeFile, JSON.stringify({
    agents: [
      {
        agentId: "valid-agent",
        source: "custom",
        customCommand: execPath,
        customEnv: { EXISTING_TOKEN: "secret" },
      },
      { agentId: "", installedAt: Date.now(), source: "custom" },
      { agentId: "bad-source", installedAt: Date.now(), source: "unknown" },
      { agentId: "bad-args", installedAt: Date.now(), source: "custom", customArgs: "not-an-array" },
      { agentId: "bad-env", installedAt: Date.now(), source: "custom", customEnv: { TOKEN: 42 } },
    ],
  }), { encoding: "utf8", mode: 0o600 });

  try {
    const {
      getInstalledAgents,
      installAgent,
      setAgentEnvOverrides,
      uninstallAgent,
    } = await import("./dist/agents-store.mjs");

    const loaded = getInstalledAgents();
    assert(loaded.length === 1 && loaded[0].agentId === "valid-agent", "非法条目被逐条过滤");
    assert(typeof loaded[0].installedAt === "number", "缺失 installedAt 使用默认时间");

    // 原子写入成功：安装后主文件存在且可解析。
    installAgent("atomic-agent", "custom", { command: execPath, args: ["-e", ""], env: {} });
    const disk = JSON.parse(readFileSync(storeFile, "utf8"));
    assert(Array.isArray(disk.agents) && disk.agents.some((agent) => agent.agentId === "atomic-agent"), "原子写入后文件可解析且 agentId 正确");

    // 多次写入与删除后不留下临时文件。
    for (let i = 0; i < 3; i += 1) {
      const agentId = `cycle-agent-${i}`;
      installAgent(agentId, "custom", { command: execPath });
      assert(!hasTempFiles(storeDir), `安装 ${agentId} 后临时文件已清理`);
      assert(uninstallAgent(agentId), `卸载 ${agentId} 成功`);
      assert(!hasTempFiles(storeDir), `卸载 ${agentId} 后临时文件已清理`);
    }

    // 写入环境变量后由新进程重新加载，确认敏感字段没有丢失。
    setAgentEnvOverrides("valid-agent", { ADDED_TOKEN: "updated" });
    const reloaded = readAgentInChild(moduleUrl, storeDir, "valid-agent");
    assert(
      reloaded.result.status === 0
      && reloaded.parsed?.customEnv?.EXISTING_TOKEN === "secret"
      && reloaded.parsed?.customEnv?.ADDED_TOKEN === "updated",
      "customEnv 写入后可从磁盘恢复",
    );

    if (process.platform !== "win32") {
      assert((statSync(storeFile).mode & 0o777) === 0o600, "Unix STORE_FILE 权限为 600");
      assert((statSync(storeDir).mode & 0o777) === 0o700, "Unix STORE_DIR 权限为 700");
    }

    // 将目标路径替换为目录，稳定触发 rename 失败，验证临时文件清理与目标不被替换。
    const original = readFileSync(storeFile);
    rmSync(storeFile, { force: true });
    mkdirSync(storeFile);
    installAgent("rename-failure-agent", "custom", { command: execPath });
    assert(statSync(storeFile).isDirectory(), "rename 失败时目标路径保持不变");
    assert(!hasTempFiles(storeDir), "rename 失败后临时文件已清理");
    rmSync(storeFile, { recursive: true, force: true });
    writeFileSync(storeFile, original, { encoding: "utf8", mode: 0o600 });

    // 合法 JSON 数组但全部非法时，不触发默认 Agent 自动安装。
    const corruptDir = mkdtempSync(join(tmpdir(), "nexus-agents-store-corrupt-"));
    const corruptFile = join(corruptDir, "installed-agents.json");
    writeFileSync(corruptFile, JSON.stringify({ agents: [{ agentId: "", source: "custom" }] }), "utf8");
    const corruptChild = spawnSync(execPath, ["--input-type=module", "-e", `
      const store = await import(${JSON.stringify(moduleUrl)});
      console.log(JSON.stringify(store.getInstalledAgents()));
    `], {
      cwd: fileURLToPath(new URL(".", import.meta.url)),
      env: { ...process.env, NEXUS_AGENTS_STORE_DIR: corruptDir },
      encoding: "utf8",
    });
    const corruptLine = corruptChild.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1);
    let corruptAgents = null;
    try {
      corruptAgents = corruptLine ? JSON.parse(corruptLine) : null;
    } catch {
      corruptAgents = null;
    }
    assert(corruptChild.status === 0 && Array.isArray(corruptAgents) && corruptAgents.length === 0, "全非法数组返回空列表");
    assert(JSON.parse(readFileSync(corruptFile, "utf8")).agents.length === 1, "全非法数组不触发默认安装");
    rmSync(corruptDir, { recursive: true, force: true });
  } finally {
    rmSync(storeDir, { recursive: true, force: true });
  }

  console.log(`Agents store: ${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
