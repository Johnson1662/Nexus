import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export interface HostIdentityData {
  hostId: string;
  publicKeyHex?: string;
  privateKeyHex?: string;
}

const IDENTITY_PATH = path.resolve(process.cwd(), '.anywhere-host.json');

function generateHostId(): string {
  return crypto.randomUUID();
}

function generateKeyPair() {
  const pair = crypto.generateKeyPairSync('x25519' as any, {
    publicKeyEncoding: { type: 'spki', format: 'jwk' } as any,
    privateKeyEncoding: { type: 'pkcs8', format: 'jwk' } as any,
  });
  const pubJwk = pair.publicKey as any;
  const privJwk = pair.privateKey as any;
  return {
    publicKey: Buffer.from(pubJwk.x as string, 'base64url').toString('hex'),
    privateKey: Buffer.from(privJwk.d as string, 'base64url').toString('hex'),
  };
}

export function getOrCreateHostIdentity(): HostIdentityData {
  try {
    const raw = fs.readFileSync(IDENTITY_PATH, 'utf-8');
    const data = JSON.parse(raw) as Partial<HostIdentityData>;
    if (
      typeof data.hostId === 'string' && data.hostId.length > 0 &&
      typeof data.publicKeyHex === 'string' && data.publicKeyHex.length > 0 &&
      typeof data.privateKeyHex === 'string' && data.privateKeyHex.length > 0
    ) {
      return data as HostIdentityData;
    }
  } catch {}

  const hostId = generateHostId();
  const keys = generateKeyPair();
  const data: HostIdentityData = { 
    hostId,
    publicKeyHex: keys.publicKey,
    privateKeyHex: keys.privateKey
  };
  fs.writeFileSync(IDENTITY_PATH, JSON.stringify(data, null, 2), 'utf-8');
  return data;
}

export function getOrCreateHostId(): string {
  return getOrCreateHostIdentity().hostId;
}
