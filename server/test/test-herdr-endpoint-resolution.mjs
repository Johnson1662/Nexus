import assert from "node:assert/strict";
import { resolveHerdrEndpoint, probeHerdr, HerdrAdapter } from "../dist/discovery/herdr-adapter.mjs";

console.log("=== Testing Herdr Endpoint Resolution & Probe ===");

// 1. Test explicit Named Pipe in HERDR_SOCKET_PATH
const origEnv = { ...process.env };
try {
  process.env.HERDR_SOCKET_PATH = "\\\\.\\pipe\\herdr-test";
  const pipeEp = resolveHerdrEndpoint();
  assert.equal(pipeEp.kind, "pipe", "explicit named pipe kind");
  assert.equal(pipeEp.path, "\\\\.\\pipe\\herdr-test", "explicit named pipe path");

  // 2. Test explicit Unix socket in HERDR_SOCKET_PATH
  process.env.HERDR_SOCKET_PATH = "/tmp/custom-herdr.sock";
  const unixEp = resolveHerdrEndpoint();
  assert.equal(unixEp.kind, "unix", "explicit unix socket kind");
  assert.equal(unixEp.path, "/tmp/custom-herdr.sock", "explicit unix socket path");

  // 3. Test HERDR_SESSION on Unix
  delete process.env.HERDR_SOCKET_PATH;
  process.env.HERDR_SESSION = "sess123";
  const sessionEp = resolveHerdrEndpoint();
  assert.equal(sessionEp.kind, "unix", "default unix session kind on posix");
  assert(sessionEp.path.includes("sess123.sock"), "unix session socket file name");

  // 4. Test probeHerdr with nonexistent socket
  process.env.HERDR_SOCKET_PATH = "/tmp/definitely-nonexistent-herdr.sock";
  const probe = await probeHerdr(true);
  assert.equal(probe.available, false, "probe should report unavailable for nonexistent socket");
  assert.equal(probe.endpointKind, "unix", "endpointKind is unix");
  assert(typeof probe.reason === "string", "reason provided");

  // 5. Test probe cache
  const cachedProbe = await probeHerdr(false);
  assert.equal(cachedProbe.checkedAt, probe.checkedAt, "probe should return cached result within TTL");
} finally {
  process.env = origEnv;
}

console.log("ALL HERDR ENDPOINT RESOLUTION TESTS PASSED!");
