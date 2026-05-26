/**
 * EncryptedChannel Unit Test — Phase 2a verification
 *
 * Tests the E2EE handshake protocol in-process without network:
 * 1. Successful E2EE handshake (matching AES keys)
 * 2. Version negotiation rejection
 * 3. Signature verification failure
 *
 * Usage: node test-e2ee-unit.mjs
 */

import crypto from "node:crypto";
import { EncryptedChannel, MIN_PROTOCOL_VERSION } from "./dist/encrypted-channel.mjs";

// ── Helpers ────────────────────────────────────────────────────────

function generateEd25519KeyPair() {
  const ed = crypto.generateKeyPairSync("ed25519", {
    publicKeyEncoding: { type: "spki", format: "jwk" },
    privateKeyEncoding: { type: "pkcs8", format: "jwk" },
  });
  return {
    publicKeyHex: Buffer.from(ed.publicKey.x, "base64url").toString("hex"),
    privateKeyHex: Buffer.from(ed.privateKey.d, "base64url").toString("hex"),
  };
}

function generateX25519KeyPair() {
  const x = crypto.generateKeyPairSync("x25519", {
    publicKeyEncoding: { type: "spki", format: "jwk" },
    privateKeyEncoding: { type: "pkcs8", format: "jwk" },
  });
  return {
    publicKeyHex: Buffer.from(x.publicKey.x, "base64url").toString("hex"),
    privateKeyHex: Buffer.from(x.privateKey.d, "base64url").toString("hex"),
  };
}

/**
 * In-memory transport pair: two Transport instances connected via EventEmitter
 */
class MockTransport {
  constructor() { this.listeners = {}; this._peer = null; }
  on(event, fn) {
    if (!this.listeners[event]) this.listeners[event] = [];
    this.listeners[event].push(fn);
  }
  send(data) {
    if (this._peer) {
      for (const fn of (this._peer.listeners["message"] || [])) fn(data);
    }
  }
  close() {
    for (const fn of (this.listeners["close"] || [])) fn();
  }
  emitError(err) {
    for (const fn of (this.listeners["error"] || [])) fn(err);
  }
  readyState = 1; // WebSocket.OPEN
}

function createTransportPair() {
  const a = new MockTransport();
  const b = new MockTransport();
  a._peer = b;
  b._peer = a;
  return [a, b];
}

function arraysEqual(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

// ── Test 1: Successful Handshake ────────────────────────────────────

function testSuccessfulHandshake() {
  console.log("Test 1: Successful E2EE Handshake");
  const hostKeys = generateEd25519KeyPair();
  const hostEcdh = generateX25519KeyPair();
  const clientEd = generateEd25519KeyPair();
  const hostIdentity = {
    hostId: "test-host",
    ed25519PrivateKeyHex: hostKeys.privateKeyHex,
    ed25519PublicKeyHex: hostKeys.publicKeyHex,
    privateKeyHex: hostEcdh.privateKeyHex,
    publicKeyHex: hostEcdh.publicKeyHex,
  };

  const [hostTransport, clientTransport] = createTransportPair();

  let hostOpen = false;
  let clientOpen = false;
  let hostAesKey = null;
  let clientAesKey = null;

  const hostChan = new EncryptedChannel(
    { role: "host", hostIdentity },
    {
      onopen: () => { hostOpen = true; },
      onmessage: () => {},
    }
  );

  const clientChan = new EncryptedChannel(
    {
      role: "client",
      hostEd25519PublicKeyHex: hostKeys.publicKeyHex,
      clientId: "test-client",
      clientEd25519PrivateKeyHex: clientEd.privateKeyHex,
      clientEd25519PublicKeyHex: clientEd.publicKeyHex,
      hostIdentity: { hostId: "test-host" },
    },
    {
      onopen: () => {
        clientOpen = true;
        clientAesKey = clientChan["aesKey"];
      },
      onmessage: () => {},
    }
  );

  // Attach transports (this triggers connecting → handshaking)
  hostChan.attachTransport(hostTransport);
  clientChan.attachTransport(clientTransport);

  // After async setup, check...
  return new Promise((resolve) => {
    setTimeout(() => {
      hostAesKey = hostChan["aesKey"];

      if (hostChan.getState() === "open") {
        console.log("  ✅ Host state: open");
      } else {
        console.log(`  ❌ Host state: ${hostChan.getState()}`);
        resolve(false);
        return;
      }

      if (clientChan.getState() === "open") {
        console.log("  ✅ Client state: open");
      } else {
        console.log(`  ❌ Client state: ${clientChan.getState()}`);
        resolve(false);
        return;
      }

      if (hostAesKey && clientAesKey) {
        const match = arraysEqual(
          new Uint8Array(hostAesKey),
          new Uint8Array(clientAesKey)
        );
        if (match) {
          console.log("  ✅ AES keys match!");
          console.log(`     Key: ${hostAesKey.toString("hex").slice(0, 16)}...`);
          resolve(true);
        } else {
          console.log("  ❌ AES keys do NOT match!");
          console.log(`     Host: ${hostAesKey.toString("hex").slice(0, 16)}...`);
          console.log(`     Client: ${clientAesKey.toString("hex").slice(0, 16)}...`);
          resolve(false);
        }
      } else {
        console.log(`  ❌ AES keys not derived (host: ${!!hostAesKey}, client: ${!!clientAesKey})`);
        resolve(false);
      }
    }, 500);
  });
}

// ── Test 2: Version Negotiation Rejection ──────────────────────────

function testVersionRejection() {
  console.log("Test 2: Version Negotiation Rejection");
  const hostKeys = generateEd25519KeyPair();
  const hostEcdh = generateX25519KeyPair();
  const hostIdentity = {
    hostId: "test-host",
    ed25519PrivateKeyHex: hostKeys.privateKeyHex,
    ed25519PublicKeyHex: hostKeys.publicKeyHex,
    privateKeyHex: hostEcdh.privateKeyHex,
    publicKeyHex: hostEcdh.publicKeyHex,
  };

  // Client sends protocolVersion=0 (< MIN_PROTOCOL_VERSION=1)
  const clientEd = generateEd25519KeyPair();
  const [hostTransport, clientTransport] = createTransportPair();

  let hostClosed = false;

  const hostChan = new EncryptedChannel({ role: "host", hostIdentity });
  const clientChan = new EncryptedChannel(
    {
      role: "client",
      hostEd25519PublicKeyHex: hostKeys.publicKeyHex,
      clientId: "old-client",
      protocolVersion: 0,  // < 1, should be rejected
    },
    {
      onclose: () => { hostClosed = true; },
    }
  );

  hostChan.attachTransport(hostTransport);
  clientChan.attachTransport(clientTransport);

  return new Promise((resolve) => {
    setTimeout(() => {
      // Host should have closed after rejecting
      if (hostChan.getState() === "closed") {
        console.log("  ✅ Host channel closed after version rejection");
        resolve(true);
      } else {
        console.log(`  ❌ Host state: ${hostChan.getState()} (expected: closed)`);
        resolve(false);
      }
    }, 500);
  });
}

// ── Test 3: Bad Signature Rejection ────────────────────────────────

function testBadSignature() {
  console.log("Test 3: Bad Signature Rejection");
  const hostKeys = generateEd25519KeyPair();
  const hostEcdh = generateX25519KeyPair();
  const hostIdentity = {
    hostId: "test-host",
    ed25519PrivateKeyHex: hostKeys.privateKeyHex,
    ed25519PublicKeyHex: hostKeys.publicKeyHex,
    privateKeyHex: hostEcdh.privateKeyHex,
    publicKeyHex: hostEcdh.publicKeyHex,
  };

  const clientEd = generateEd25519KeyPair();
  // Use a DIFFERENT key to sign (simulating wrong client key)
  const wrongKey = generateEd25519KeyPair();

  const [hostTransport, clientTransport] = createTransportPair();

  const hostChan = new EncryptedChannel({
    role: "host",
    hostIdentity,
  });

  const clientChan = new EncryptedChannel({
    role: "client",
    hostEd25519PublicKeyHex: hostKeys.publicKeyHex,
    clientId: "evil-client",
    clientEd25519PrivateKeyHex: wrongKey.privateKeyHex, // signs with wrong key
    clientEd25519PublicKeyHex: clientEd.publicKeyHex,   // claims this is the key
    hostIdentity: { hostId: "test-host" },
  });

  hostChan.attachTransport(hostTransport);
  clientChan.attachTransport(clientTransport);

  return new Promise((resolve) => {
    setTimeout(() => {
      if (hostChan.getState() === "closed") {
        console.log("  ✅ Host rejected bad signature (channel closed)");
        resolve(true);
      } else {
        console.log(`  ❌ Host state: ${hostChan.getState()} (expected: closed)`);
        resolve(false);
      }
    }, 500);
  });
}

// ── Run ────────────────────────────────────────────────────────────

async function main() {
  console.log("=== EncryptedChannel Unit Tests (Phase 2a) ===\n");

  const t1 = await testSuccessfulHandshake();
  const t2 = testVersionRejection();
  const t3 = testBadSignature();

  const results = await Promise.all([t1, t2, t3]);

  console.log("\n=== Results ===");
  console.log(`Test 1 (Successful Handshake): ${results[0] ? "✅ PASS" : "❌ FAIL"}`);
  console.log(`Test 2 (Version Rejection):    ${results[1] ? "✅ PASS" : "❌ FAIL"}`);
  console.log(`Test 3 (Bad Signature):        ${results[2] ? "✅ PASS" : "❌ FAIL"}`);

  const allPass = results.every(Boolean);
  if (allPass) {
    console.log("\n✅ All Phase 2a tests passed!");
  } else {
    console.log("\n❌ Some tests failed!");
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Test error:", err);
  process.exit(1);
});
