import assert from "node:assert/strict";
import { mkdtempSync, rmSync, existsSync, mkdirSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

console.log("=== Testing ACP Adapter Management ===");

const testAdaptersDir = mkdtempSync(join(tmpdir(), "nexus-adapters-test-"));

try {
  const {
    getAcpAdapterInfo,
    checkAcpAdapterStatus,
    detectPackageManager,
    installAcpAdapter,
    uninstallAcpAdapter,
  } = await import("../dist/discovery/acp-adapters.mjs");

  // 1. Adapter Info from Registry
  const claudeInfo = getAcpAdapterInfo("claude");
  assert.equal(claudeInfo.required, true, "claude requires ACP adapter");
  assert.equal(claudeInfo.package, "@agentclientprotocol/claude-agent-acp");
  assert.equal(claudeInfo.binary, "claude-agent-acp");

  const codexInfo = getAcpAdapterInfo("codex");
  assert.equal(codexInfo.required, true, "codex requires ACP adapter");
  assert.equal(codexInfo.package, "@agentclientprotocol/codex-acp");
  assert.equal(codexInfo.binary, "codex-acp");

  const piInfo = getAcpAdapterInfo("pi");
  assert.equal(piInfo.required, true, "pi requires ACP adapter");
  assert.equal(piInfo.package, "pi-acp");
  assert.equal(piInfo.binary, "pi-acp");

  const ompInfo = getAcpAdapterInfo("omp");
  assert.equal(ompInfo.required, false, "omp does not require ACP adapter");

  // 2. Initial status in empty test adapters dir
  const initialClaude = checkAcpAdapterStatus("claude", testAdaptersDir);
  assert.equal(initialClaude.required, true);
  // Note: if host happens to have claude-agent-acp on PATH, installed might be true via findExecutable,
  // but if we check with a fake agent that has adapter requirement:
  assert.equal(typeof initialClaude.installed, "boolean");

  // 3. Status when binary is placed directly in testAdaptersDir/node_modules/.bin
  const binDir = join(testAdaptersDir, "node_modules", ".bin");
  mkdirSync(binDir, { recursive: true });
  const mockBinaryPath = join(
    binDir,
    process.platform === "win32" ? "claude-agent-acp.cmd" : "claude-agent-acp",
  );
  writeFileSync(mockBinaryPath, "#!/bin/sh\necho mock acp\n", "utf8");
  if (process.platform !== "win32") {
    chmodSync(mockBinaryPath, 0o755);
  }

  const afterPlace = checkAcpAdapterStatus("claude", testAdaptersDir);
  assert.equal(afterPlace.installed, true, "detected installed in test adapters directory");
  assert.equal(afterPlace.path, mockBinaryPath, "points to mock binary");

  // 4. Package Manager detection
  const pm = detectPackageManager();
  assert(pm !== null, "Host should have at least npm, bun, or pnpm available");
  assert(["npm", "bun", "pnpm"].includes(pm.pm), `detected package manager: ${pm.pm}`);
  assert(existsSync(pm.execPath), "package manager executable exists");

  // 5. Non-required agent install returns ok: true immediately
  const ompInstall = await installAcpAdapter("omp", { adaptersDir: testAdaptersDir });
  assert.equal(ompInstall.ok, true);

  const ompUninstall = await uninstallAcpAdapter("omp", { adaptersDir: testAdaptersDir });
  assert.equal(ompUninstall.ok, true);

  console.log("ALL ACP ADAPTER TESTS PASSED!");
} finally {
  rmSync(testAdaptersDir, { recursive: true, force: true });
}
