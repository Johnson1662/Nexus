import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

interface HostIdentityData {
  hostId: string;
}

const IDENTITY_PATH = path.resolve(process.cwd(), '.anywhere-host.json');

function generateHostId(): string {
  return crypto.randomUUID();
}

export function getOrCreateHostId(): string {
  try {
    const raw = fs.readFileSync(IDENTITY_PATH, 'utf-8');
    const data = JSON.parse(raw) as Partial<HostIdentityData>;
    if (typeof data.hostId === 'string' && data.hostId.length > 0) {
      return data.hostId;
    }
  } catch {}

  const hostId = generateHostId();
  const data: HostIdentityData = { hostId };
  fs.writeFileSync(IDENTITY_PATH, JSON.stringify(data, null, 2), 'utf-8');
  return hostId;
}
