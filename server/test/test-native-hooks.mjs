import assert from "node:assert/strict";
import { mkdtempSync, rmSync, existsSync, writeFileSync, readFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

console.log("=== Testing Native Hook Management ===");

const testHome = mkdtempSync(join(tmpdir(), "nexus-hook-test-"));

try {
  const {
    checkNativeHookStatus,
    installNativeHook,
    uninstallNativeHook,
    listNativeHooks,
    getNativeHookDefinition,
  } = await import("../dist/discovery/native-hooks.mjs");

  // 1. Definition check
  const def = getNativeHookDefinition("omp");
  assert(def !== null, "omp must have a native hook definition");
  assert.equal(def.agentId, "omp");
  assert.equal(getNativeHookDefinition("unknown-agent"), null, "unknown agent returns null");

  // 2. Initial status: supported but not installed
  const initial = checkNativeHookStatus("omp", testHome);
  assert.equal(initial.supported, true, "omp hook is supported");
  assert.equal(initial.installed, false, "omp hook is initially not installed in clean home");
  assert(initial.path.includes("nexus-ambient.ts"), "target path points to nexus-ambient.ts");

  // 3. Install hook
  const installRes = await installNativeHook("omp", testHome);
  assert.equal(installRes.ok, true, `installNativeHook should succeed: ${installRes.error}`);
  assert(existsSync(installRes.path), "hook file must exist after install");
  const installedContent = readFileSync(installRes.path, "utf8");
  assert(installedContent.includes("NEXUS_AMBIENT_INTEGRATION_VERSION=1"), "hook must have version marker");
  assert(installedContent.includes("installed by nexus"), "hook must have management marker");

  // 4. Status after install
  const afterInstall = checkNativeHookStatus("omp", testHome);
  assert.equal(afterInstall.supported, true);
  assert.equal(afterInstall.installed, true, "hook is detected as installed");
  assert.equal(afterInstall.version, 1, "hook version is 1");

  // 5. listNativeHooks includes omp
  const list = listNativeHooks(testHome);
  const ompEntry = list.find((h) => h.agentId === "omp");
  assert(ompEntry, "listNativeHooks includes omp");
  assert.equal(ompEntry.installed, true);

  // 6. Uninstall hook
  const uninstallRes = await uninstallNativeHook("omp", testHome);
  assert.equal(uninstallRes.ok, true, `uninstallNativeHook should succeed: ${uninstallRes.error}`);
  assert(!existsSync(installRes.path), "hook file must be deleted after uninstall");

  // 7. Status after uninstall
  const afterUninstall = checkNativeHookStatus("omp", testHome);
  assert.equal(afterUninstall.installed, false, "hook is detected as not installed after uninstall");

  // 8. Safety check: do not delete unmanaged user extensions
  const unmanagedPath = installRes.path;
  writeFileSync(unmanagedPath, "// My custom extension without nexus markers\nexport default () => {};\n", "utf8");
  const unmanagedStatus = checkNativeHookStatus("omp", testHome);
  assert.equal(unmanagedStatus.installed, false, "unmanaged file is not claimed as installed");

  const uninstallUnmanaged = await uninstallNativeHook("omp", testHome);
  assert.equal(uninstallUnmanaged.ok, false, "uninstalling unmanaged file must fail");
  assert(existsSync(unmanagedPath), "unmanaged file must NOT be deleted");

  // Overwriting unmanaged file with installNativeHook must also fail to prevent data loss
  const installOverUnmanaged = await installNativeHook("omp", testHome);
  assert.equal(installOverUnmanaged.ok, false, "installing over unmanaged file must fail");

  // 9. Claude hook test with settings.json management
  const claudeDef = getNativeHookDefinition("claude");
  assert(claudeDef !== null, "claude must have native hook definition");
  assert.equal(claudeDef.isExecutable, true, "claude hook is executable");

  const claudeInitial = checkNativeHookStatus("claude", testHome);
  assert.equal(claudeInitial.supported, true);
  assert.equal(claudeInitial.installed, false);

  // Pre-populate settings.json with a user key
  const claudeSettingsPath = join(testHome, ".claude", "settings.json");
  mkdirSync(join(testHome, ".claude"), { recursive: true });
  writeFileSync(claudeSettingsPath, JSON.stringify({ userKey: "keepMe" }, null, 2), "utf8");

  const claudeInstall = await installNativeHook("claude", testHome);
  assert.equal(claudeInstall.ok, true, `claude install should succeed: ${claudeInstall.error}`);
  assert(existsSync(claudeInstall.path), "claude hook script exists");

  const claudeSettingsAfter = JSON.parse(readFileSync(claudeSettingsPath, "utf8"));
  assert.equal(claudeSettingsAfter.userKey, "keepMe", "user settings preserved");
  assert(claudeSettingsAfter.hooks?.SessionStart?.length > 0, "SessionStart hook added");
  assert(claudeSettingsAfter.hooks?.Stop?.length > 0, "Stop hook added");

  const claudeAfterInstall = checkNativeHookStatus("claude", testHome);
  assert.equal(claudeAfterInstall.installed, true, "claude hook detected as installed");

  const claudeUninstall = await uninstallNativeHook("claude", testHome);
  assert.equal(claudeUninstall.ok, true);
  assert(!existsSync(claudeInstall.path), "claude hook script deleted");

  const claudeSettingsCleaned = JSON.parse(readFileSync(claudeSettingsPath, "utf8"));
  assert.equal(claudeSettingsCleaned.userKey, "keepMe", "user settings still preserved");
  assert.equal(claudeSettingsCleaned.hooks, undefined, "empty hooks object cleaned up");

  // 10. Codex hook test with hooks.json management
  const codexDef = getNativeHookDefinition("codex");
  assert(codexDef !== null, "codex must have native hook definition");

  const codexInstall = await installNativeHook("codex", testHome);
  assert.equal(codexInstall.ok, true, `codex install should succeed: ${codexInstall.error}`);
  assert(existsSync(codexInstall.path), "codex hook script exists");

  const codexHooksPath = join(testHome, ".codex", "hooks.json");
  assert(existsSync(codexHooksPath), "hooks.json created");

  const codexAfterInstall = checkNativeHookStatus("codex", testHome);
  assert.equal(codexAfterInstall.installed, true, "codex hook detected as installed");

  const codexUninstall = await uninstallNativeHook("codex", testHome);
  assert.equal(codexUninstall.ok, true);
  assert(!existsSync(codexInstall.path), "codex hook script deleted");
  assert(!existsSync(codexHooksPath), "empty hooks.json file cleaned up");

  // 11. Preservation of other hooks in the same matcher group
  const multiHookSettingsPath = join(testHome, ".claude", "settings.json");
  mkdirSync(join(testHome, ".claude"), { recursive: true });
  writeFileSync(multiHookSettingsPath, JSON.stringify({
    hooks: {
      SessionStart: [
        {
          matcher: ".*",
          hooks: [
            { type: "command", command: "my-custom-logger session", timeout: 10 },
          ],
        },
      ],
    },
  }, null, 2), "utf8");

  await installNativeHook("claude", testHome);
  const multiSettingsAfter = JSON.parse(readFileSync(multiHookSettingsPath, "utf8"));
  const sessionHooks = multiSettingsAfter.hooks.SessionStart.flatMap((g) => g.hooks);
  assert(sessionHooks.some((h) => h.command === "my-custom-logger session"), "user custom hook preserved in group");
  assert(sessionHooks.some((h) => h.nexus === true), "nexus hook injected");

  await uninstallNativeHook("claude", testHome);
  const multiSettingsCleaned = JSON.parse(readFileSync(multiHookSettingsPath, "utf8"));
  const cleanedHooks = multiSettingsCleaned.hooks.SessionStart.flatMap((g) => g.hooks);
  assert(cleanedHooks.some((h) => h.command === "my-custom-logger session"), "user custom hook still preserved after uninstall");
  assert(!cleanedHooks.some((h) => h.nexus === true), "nexus hook cleanly removed");

  console.log("ALL NATIVE HOOK TESTS PASSED!");
} finally {
  rmSync(testHome, { recursive: true, force: true });
}
