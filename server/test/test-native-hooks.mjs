import assert from "node:assert/strict";
import { mkdtempSync, rmSync, existsSync, writeFileSync, readFileSync } from "node:fs";
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

  console.log("ALL NATIVE HOOK TESTS PASSED!");
} finally {
  rmSync(testHome, { recursive: true, force: true });
}
