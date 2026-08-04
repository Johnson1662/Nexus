import assert from "node:assert/strict";
import { once } from "node:events";
import WebSocket from "ws";

process.env.NEXUS_AUTH_TOKEN = "test-bridge-token";

const { createBridgeServer } = await import("./dist/server.mjs");

const app = createBridgeServer({ port: 0, hostId: "test-host" });
await once(app.httpServer, "listening");
const address = app.httpServer.address();
assert(address && typeof address === "object");
const port = address.port;
const httpUrl = `http://127.0.0.1:${port}`;
const wsUrl = `ws://127.0.0.1:${port}`;

try {
  const unauthorized = await fetch(`${httpUrl}/probe`);
  assert.equal(unauthorized.status, 401);
  assert.equal((await unauthorized.json()).code, "AUTH_REQUIRED");

  const authorized = await fetch(`${httpUrl}/probe`, {
    headers: { Authorization: "Bearer test-bridge-token" },
  });
  assert.equal(authorized.status, 200);
  assert.equal((await authorized.json()).hostId, "test-host");

  const rejected = await new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    ws.once("unexpected-response", (_request, response) => {
      resolve(response.statusCode);
      ws.close();
    });
    ws.once("error", reject);
  });
  assert.equal(rejected, 401);

  const serverInfo = await new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl, {
      headers: { Authorization: "Bearer test-bridge-token" },
    });
    ws.once("message", (raw) => {
      try {
        const message = JSON.parse(raw.toString());
        ws.close();
        resolve(message);
      } catch (error) {
        reject(error);
      }
    });
    ws.once("error", reject);
  });
  assert.equal(serverInfo.type, "server_info");
  assert.equal("ed25519PublicKeyHex" in serverInfo, false);

  console.log("Bridge auth: 7 passed, 0 failed");
} finally {
  await app.stop();
}
