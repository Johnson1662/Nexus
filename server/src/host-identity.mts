import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { homedir } from 'node:os';
export interface HostIdentityData {
  schemaVersion: number;
  hostId: string;
  publicKeyHex?: string;
  privateKeyHex?: string;
  ed25519PublicKeyHex?: string;
  ed25519PrivateKeyHex?: string;
}

const ANYWHERE_DIR = path.join(homedir(), '.nexus');
const IDENTITY_PATH = path.join(ANYWHERE_DIR, 'host-identity.json');
const OLD_IDENTITY_PATH = path.resolve(process.cwd(), '.nexus-host.json');

// Migration from old location (project root) to ~/.nexus/
try {
  if (fs.existsSync(OLD_IDENTITY_PATH) && !fs.existsSync(IDENTITY_PATH)) {
    fs.mkdirSync(ANYWHERE_DIR, { recursive: true });
    fs.copyFileSync(OLD_IDENTITY_PATH, IDENTITY_PATH);
    fs.unlinkSync(OLD_IDENTITY_PATH);
    console.log(`[host-identity] migrated from project root to ${IDENTITY_PATH}`);
  }
} catch (err) {
  console.log(`[host-identity] migration check failed: ${err}`);
}
fs.mkdirSync(ANYWHERE_DIR, { recursive: true });


function generateHostId(): string {
  return crypto.randomUUID();
}

function generateKeyPair() {
  const x25519 = crypto.generateKeyPairSync('x25519' as any, {
    publicKeyEncoding: { type: 'spki', format: 'jwk' } as any,
    privateKeyEncoding: { type: 'pkcs8', format: 'jwk' } as any,
  });
  const xPubJwk = x25519.publicKey as any;
  const xPrivJwk = x25519.privateKey as any;

  const ed25519 = crypto.generateKeyPairSync('ed25519' as any, {
    publicKeyEncoding: { type: 'spki', format: 'jwk' } as any,
    privateKeyEncoding: { type: 'pkcs8', format: 'jwk' } as any,
  });
  const ePubJwk = ed25519.publicKey as any;
  const ePrivJwk = ed25519.privateKey as any;

  return {
    publicKey: Buffer.from(xPubJwk.x as string, 'base64url').toString('hex'),
    privateKey: Buffer.from(xPrivJwk.d as string, 'base64url').toString('hex'),
    ed25519PublicKey: Buffer.from(ePubJwk.x as string, 'base64url').toString('hex'),
    ed25519PrivateKey: Buffer.from(ePrivJwk.d as string, 'base64url').toString('hex'),
  };
}

export function getOrCreateHostIdentity(): HostIdentityData {
  // Phase 2b: Key rotation via NEXUS_ROTATE_KEYS=1
  if (process.env.NEXUS_ROTATE_KEYS === '1') {
    try {
      fs.unlinkSync(IDENTITY_PATH);
      console.log('[host-identity] Key rotation: deleted existing identity file');
    } catch {}
  }

  let schemaVersion: number = 1;
  let hostId: string;
  let publicKeyHex: string | undefined;
  let privateKeyHex: string | undefined;
  let ed25519PublicKeyHex: string | undefined;
  let ed25519PrivateKeyHex: string | undefined;

  try {
    const raw = fs.readFileSync(IDENTITY_PATH, 'utf-8');
    const data = JSON.parse(raw) as Partial<HostIdentityData>;
    schemaVersion = typeof data.schemaVersion === 'number' ? data.schemaVersion : 0;
    if (typeof data.hostId === 'string' && data.hostId.length > 0) {
      hostId = data.hostId;
      publicKeyHex = data.publicKeyHex;
      privateKeyHex = data.privateKeyHex;
      ed25519PublicKeyHex = data.ed25519PublicKeyHex;
      ed25519PrivateKeyHex = data.ed25519PrivateKeyHex;
    } else {
      hostId = generateHostId();
    }
  } catch {
    hostId = generateHostId();
  }

  // Re-generate keys if missing (but preserve hostId)
  if (!publicKeyHex || !privateKeyHex || !ed25519PublicKeyHex || !ed25519PrivateKeyHex) {
    const keys = generateKeyPair();
    publicKeyHex ??= keys.publicKey;
    privateKeyHex ??= keys.privateKey;
    ed25519PublicKeyHex ??= keys.ed25519PublicKey;
    ed25519PrivateKeyHex ??= keys.ed25519PrivateKey;
  }

  schemaVersion = 1;

  const data: HostIdentityData = {
    schemaVersion,
    hostId,
    publicKeyHex,
    privateKeyHex,
    ed25519PublicKeyHex,
    ed25519PrivateKeyHex,
  };
  fs.writeFileSync(IDENTITY_PATH, JSON.stringify(data, null, 2), 'utf-8');
  return data;
}

export function getOrCreateHostId(): string {
  return getOrCreateHostIdentity().hostId;
}
