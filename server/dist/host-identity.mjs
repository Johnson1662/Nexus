import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const IDENTITY_PATH = path.resolve(process.cwd(), '.anywhere-host.json');
function generateHostId() {
    return crypto.randomUUID();
}
function generateKeyPair() {
    const pair = crypto.generateKeyPairSync('x25519', {
        publicKeyEncoding: { type: 'spki', format: 'jwk' },
        privateKeyEncoding: { type: 'pkcs8', format: 'jwk' },
    });
    const pubJwk = pair.publicKey;
    const privJwk = pair.privateKey;
    return {
        publicKey: Buffer.from(pubJwk.x, 'base64url').toString('hex'),
        privateKey: Buffer.from(privJwk.d, 'base64url').toString('hex'),
    };
}
export function getOrCreateHostIdentity() {
    try {
        const raw = fs.readFileSync(IDENTITY_PATH, 'utf-8');
        const data = JSON.parse(raw);
        if (typeof data.hostId === 'string' && data.hostId.length > 0 &&
            typeof data.publicKeyHex === 'string' && data.publicKeyHex.length > 0 &&
            typeof data.privateKeyHex === 'string' && data.privateKeyHex.length > 0) {
            return data;
        }
    }
    catch { }
    const hostId = generateHostId();
    const keys = generateKeyPair();
    const data = {
        hostId,
        publicKeyHex: keys.publicKey,
        privateKeyHex: keys.privateKey
    };
    fs.writeFileSync(IDENTITY_PATH, JSON.stringify(data, null, 2), 'utf-8');
    return data;
}
export function getOrCreateHostId() {
    return getOrCreateHostIdentity().hostId;
}
//# sourceMappingURL=host-identity.mjs.map